defmodule Meetcutes.Relationships do
  @moduledoc """
  Relationship layer for likes, blocks, mutes, and derived matches.

  All reads and writes are scoped by the acting user. Blocking or muting is
  symmetric for visibility: if either party has blocked or muted the other,
  neither should appear in the other's feed or direct profile lookups.
  """

  import Ecto.Query, warn: false

  alias Meetcutes.Accounts.User
  alias Meetcutes.Locations
  alias Meetcutes.Repo
  alias Meetcutes.Relationships.Relationship

  @kinds [:like, :block, :mute]
  @hidden_kinds [:block, :mute]
  @like_distance_miles 100

  @doc """
  Returns the relationship kinds the API accepts.
  """
  def kinds, do: @kinds

  @doc """
  Creates (or returns) a directed relationship from `actor_id` to `target_id`.

  Blocking removes any likes in both directions and any mute from the actor,
  because a block supersedes every other relationship. Muting removes the
  actor's outgoing like so a mute cannot accidentally create a match.
  """
  def create_relationship(actor_id, target_id, kind)
      when is_binary(actor_id) and is_binary(target_id) do
    with {:ok, kind} <- cast_kind(kind),
         :ok <- ensure_not_self(actor_id, target_id),
         :ok <- ensure_target_exists(target_id),
         :ok <- ensure_like_allowed(actor_id, target_id, kind) do
      do_create_relationship(actor_id, target_id, kind)
    end
  end

  def create_relationship(_actor_id, _target_id, _kind), do: {:error, :invalid_relationship}

  @doc """
  Removes a directed relationship. Idempotent: deleting something that does not
  exist is still a success.
  """
  def delete_relationship(actor_id, target_id, kind)
      when is_binary(actor_id) and is_binary(target_id) do
    with {:ok, kind} <- cast_kind(kind) do
      Repo.delete_all(
        from(r in Relationship,
          where: r.actor_id == ^actor_id and r.target_id == ^target_id and r.kind == ^kind
        )
      )

      {:ok, kind}
    end
  end

  def delete_relationship(_actor_id, _target_id, _kind), do: {:error, :invalid_relationship}

  @doc """
  Returns the acting user's relationship summary.

  `matches` contains the user IDs of people who liked the user back.
  """
  def summary(user_id) when is_binary(user_id) do
    likes = ids_for(user_id, :like, :outgoing)
    blocks = ids_for(user_id, :block, :outgoing)
    mutes = ids_for(user_id, :mute, :outgoing)

    matches =
      Repo.all(
        from a in Relationship,
          join: b in Relationship,
          on: a.actor_id == b.target_id and a.target_id == b.actor_id,
          where: a.actor_id == ^user_id,
          where: a.kind == :like and b.kind == :like,
          select: a.target_id
      )

    %{likes: likes, blocks: blocks, mutes: mutes, matches: matches}
  end

  @doc """
  True when either user has blocked the other.

  Blocks are enforced bidirectionally across user search and direct profile
  lookups. Mutes are intentionally handled separately: a muted profile still
  remains reachable from the management directory so it can be unmuted.
  """
  def blocked?(user_id, other_id)
      when is_binary(user_id) and is_binary(other_id) and user_id != other_id do
    Repo.exists?(
      from r in Relationship,
        where: r.kind == :block,
        where:
          (r.actor_id == ^user_id and r.target_id == ^other_id) or
            (r.actor_id == ^other_id and r.target_id == ^user_id)
    )
  end

  def blocked?(_user_id, _other_id), do: false

  @doc """
  Returns the users the actor has blocked.
  """
  def list_blocked_users(user_id) when is_binary(user_id), do: users_for(user_id, :block)

  @doc """
  Returns the users the actor has muted.
  """
  def list_muted_users(user_id) when is_binary(user_id), do: users_for(user_id, :mute)

  @doc """
  Returns active profiles the actor has liked within 100 miles.

  Coordinates are decoded from the stored fuzzed geohash and then filtered with
  the same Haversine distance helper used by event location checks.
  """
  def list_liked_users(user_id) when is_binary(user_id) do
    proximity_likes(user_id, :outgoing)
  end

  def list_liked_users(_user_id), do: []

  @doc """
  Returns active profiles who liked the actor within 100 miles.
  """
  def list_liked_by_users(user_id) when is_binary(user_id) do
    proximity_likes(user_id, :incoming)
  end

  def list_liked_by_users(_user_id), do: []

  @doc """
  Returns the IDs blocked in either direction for the given viewer.

  This is used to keep blocked users out of attendee snapshots.
  """
  def blocked_ids(user_id) when is_binary(user_id) do
    Repo.all(
      from r in Relationship,
        where: r.kind == :block,
        where: r.actor_id == ^user_id or r.target_id == ^user_id,
        select:
          fragment(
            "CASE WHEN ? = ? THEN ? ELSE ? END",
            r.actor_id,
            ^user_id,
            r.target_id,
            r.actor_id
          )
    )
  end

  def blocked_ids(_user_id), do: []

  @doc """
  True when either user has blocked or muted the other.
  """
  def hidden?(user_id, other_id)
      when is_binary(user_id) and is_binary(other_id) and user_id != other_id do
    Repo.exists?(
      from r in Relationship,
        where: r.kind in ^@hidden_kinds,
        where:
          (r.actor_id == ^user_id and r.target_id == ^other_id) or
            (r.actor_id == ^other_id and r.target_id == ^user_id)
    )
  end

  def hidden?(_user_id, _other_id), do: false

  @doc """
  Excludes anyone blocked or muted by either party from a users query.

  The query must select from `Meetcutes.Accounts.User` (aliased as `u`).
  """
  def exclude_hidden(query, nil), do: query

  def exclude_hidden(query, viewer_id) when is_binary(viewer_id) do
    hidden_ids =
      from r in Relationship,
        where: r.kind in ^@hidden_kinds,
        where: r.actor_id == ^viewer_id or r.target_id == ^viewer_id,
        select:
          fragment(
            "CASE WHEN ? = ? THEN ? ELSE ? END",
            r.actor_id,
            ^viewer_id,
            r.target_id,
            r.actor_id
          )

    from u in query, where: u.id not in subquery(hidden_ids)
  end

  defp do_create_relationship(actor_id, target_id, kind) do
    Repo.transact(fn ->
      if kind == :block do
        delete_pair(actor_id, target_id, :like)
        delete_pair(target_id, actor_id, :like)
        delete_pair(actor_id, target_id, :mute)
      end

      if kind == :mute do
        delete_pair(actor_id, target_id, :like)
      end

      case Repo.get_by(Relationship, actor_id: actor_id, target_id: target_id, kind: kind) do
        %Relationship{} = relationship ->
          {:ok, relationship}

        nil ->
          %Relationship{}
          |> Relationship.changeset(%{
            actor_id: actor_id,
            target_id: target_id,
            kind: kind
          })
          |> Repo.insert()
      end
    end)
  end

  defp delete_pair(actor_id, target_id, kind) do
    Repo.delete_all(
      from r in Relationship,
        where: r.actor_id == ^actor_id and r.target_id == ^target_id and r.kind == ^kind
    )
  end

  defp ids_for(user_id, kind, :outgoing) do
    Repo.all(
      from r in Relationship,
        where: r.actor_id == ^user_id and r.kind == ^kind,
        select: r.target_id
    )
  end

  defp proximity_likes(user_id, direction) do
    with {:ok, viewer_lat, viewer_lng} <- viewer_coordinates(user_id) do
      user_id
      |> likes_query(direction)
      |> Repo.all()
      |> Enum.flat_map(fn user ->
        try do
          {user_lat, user_lng} = Geohash.decode(user.geohash)

          distance =
            Locations.distance_miles(
              viewer_lat,
              viewer_lng,
              user_lat,
              user_lng
            )

          if distance <= @like_distance_miles do
            [%{user: user, distance_miles: Float.round(distance * 1.0, 1)}]
          else
            []
          end
        rescue
          _ -> []
        end
      end)
      |> Enum.sort_by(& &1.distance_miles)
    else
      _ -> []
    end
  end

  defp viewer_coordinates(user_id) do
    case Repo.get(User, user_id) do
      %User{geohash: geohash} when is_binary(geohash) ->
        try do
          {latitude, longitude} = Geohash.decode(geohash)
          {:ok, latitude, longitude}
        rescue
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp likes_query(user_id, :outgoing) do
    from(u in User,
      join: r in Relationship,
      on: r.target_id == u.id,
      where: r.actor_id == ^user_id and r.kind == :like,
      where: u.is_active == true and u.is_approved == true and is_nil(u.deleted_at),
      where: not is_nil(u.geohash),
      select: u
    )
    |> exclude_hidden(user_id)
  end

  defp likes_query(user_id, :incoming) do
    from(u in User,
      join: r in Relationship,
      on: r.actor_id == u.id,
      where: r.target_id == ^user_id and r.kind == :like,
      where: u.is_active == true and u.is_approved == true and is_nil(u.deleted_at),
      where: not is_nil(u.geohash),
      select: u
    )
    |> exclude_hidden(user_id)
  end

  defp users_for(user_id, kind) do
    Repo.all(
      from u in User,
        join: r in Relationship,
        on: r.target_id == u.id,
        where: r.actor_id == ^user_id and r.kind == ^kind,
        where: is_nil(u.deleted_at),
        order_by: [desc: r.inserted_at],
        select: u
    )
  end

  defp cast_kind(kind) when kind in @kinds, do: {:ok, kind}

  defp cast_kind(kind) when is_binary(kind) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == kind)) do
      nil -> {:error, :invalid_kind}
      kind -> {:ok, kind}
    end
  end

  defp cast_kind(_kind), do: {:error, :invalid_kind}

  defp ensure_not_self(actor_id, target_id) do
    if actor_id == target_id, do: {:error, :self_relationship}, else: :ok
  end

  defp ensure_target_exists(target_id) do
    case Repo.get(User, target_id) do
      %User{deleted_at: nil} -> :ok
      _ -> {:error, :target_not_found}
    end
  end

  defp ensure_like_allowed(actor_id, target_id, :like) do
    if hidden?(actor_id, target_id), do: {:error, :blocked}, else: :ok
  end

  defp ensure_like_allowed(_actor_id, _target_id, _kind), do: :ok
end
