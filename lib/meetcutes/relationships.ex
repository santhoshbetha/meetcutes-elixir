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
  alias Meetcutes.Workers.NotificationWorker

  require Logger

  @kinds [:like, :block, :mute]
  @hidden_kinds [:block, :mute]
  @like_distance_miles 100
  @default_per_page 20
  @max_per_page 20

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
    case create_relationship_with_status(actor_id, target_id, kind) do
      {:ok, relationship, _inserted?} -> {:ok, relationship}
      {:error, _reason} = error -> error
    end
  end

  def create_relationship(_actor_id, _target_id, _kind), do: {:error, :invalid_relationship}

  @doc """
  Creates a relationship and reports whether the row was newly inserted.

  Controllers use the third tuple element to avoid duplicating side effects
  (such as a like notification) when the client repeats an idempotent request.
  """
  def create_relationship_with_status(actor_id, target_id, kind)
      when is_binary(actor_id) and is_binary(target_id) do
    with {:ok, kind} <- cast_kind(kind),
         :ok <- ensure_not_self(actor_id, target_id),
         :ok <- ensure_target_exists(target_id),
         :ok <- ensure_like_allowed(actor_id, target_id, kind) do
      actor_id
      |> do_create_relationship(target_id, kind)
      |> handle_created_relationship(actor_id, target_id, kind)
    end
  end

  def create_relationship_with_status(_actor_id, _target_id, _kind),
    do: {:error, :invalid_relationship}

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
  Returns a bounded page of profiles the actor liked within 100 miles.

  Pages are capped at 20 cards so a large interaction history never streams
  the entire shortlist to the client.
  """
  def list_liked_users_paginated(user_id, opts \\ [])

  def list_liked_users_paginated(user_id, opts) when is_binary(user_id) do
    user_id
    |> proximity_likes(:outgoing)
    |> paginate_proximity(opts)
  end

  def list_liked_users_paginated(_user_id, opts), do: empty_proximity_page(opts)

  @doc """
  Returns a bounded page of profiles who liked the actor within 100 miles.
  """
  def list_liked_by_users_paginated(user_id, opts \\ [])

  def list_liked_by_users_paginated(user_id, opts) when is_binary(user_id) do
    user_id
    |> proximity_likes(:incoming)
    |> paginate_proximity(opts)
  end

  def list_liked_by_users_paginated(_user_id, opts), do: empty_proximity_page(opts)

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
          {:ok, {relationship, false}}

        nil ->
          %Relationship{}
          |> Relationship.changeset(%{
            actor_id: actor_id,
            target_id: target_id,
            kind: kind
          })
          |> Repo.insert()
          |> case do
            {:ok, relationship} -> {:ok, {relationship, true}}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  defp handle_created_relationship({:ok, {relationship, true}}, actor_id, target_id, :like) do
    maybe_enqueue_match_reminders(actor_id, target_id)
    {:ok, relationship, true}
  end

  defp handle_created_relationship(
         {:ok, {relationship, inserted?}},
         _actor_id,
         _target_id,
         _kind
       ) do
    {:ok, relationship, inserted?}
  end

  defp handle_created_relationship({:error, _reason} = error, _actor_id, _target_id, _kind),
    do: error

  # The match is derived from mutual likes rather than stored as a separate row.
  # Enqueue only after the like transaction commits, and only when the reverse
  # like already exists, so a one-way like never sends a false reminder.
  defp maybe_enqueue_match_reminders(actor_id, target_id) do
    if Repo.exists?(
         from r in Relationship,
           where:
             r.actor_id == ^target_id and r.target_id == ^actor_id and
               r.kind == :like
       ) do
      enqueue_match_reminder(actor_id, target_id)
      enqueue_match_reminder(target_id, actor_id)
    end

    :ok
  end

  defp enqueue_match_reminder(user_id, match_id) do
    %{user_id: user_id, match_id: match_id, action: "match_reminder"}
    |> NotificationWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Unable to enqueue match reminder for #{user_id} -> #{match_id}: #{inspect(reason)}"
        )

        :error
    end
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
      |> Enum.sort_by(&{&1.distance_miles, &1.user.id})
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

  defp paginate_proximity(entries, opts) do
    page = opts |> Keyword.get(:page, 1) |> normalize_positive(1)
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> normalize_per_page()

    total = length(entries)
    total_pages = total_pages(total, per_page)

    users =
      entries
      |> Enum.drop((page - 1) * per_page)
      |> Enum.take(per_page)

    %{
      users: users,
      pagination: %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: total_pages,
        has_next_page: page < total_pages
      }
    }
  end

  defp empty_proximity_page(opts) do
    %{
      users: [],
      pagination: %{
        page: normalize_positive(Keyword.get(opts, :page, 1), 1),
        per_page: opts |> Keyword.get(:per_page, @default_per_page) |> normalize_per_page(),
        total: 0,
        total_pages: 0,
        has_next_page: false
      }
    }
  end

  defp normalize_positive(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_positive(_value, default), do: default

  defp normalize_per_page(value) do
    value
    |> normalize_positive(@default_per_page)
    |> min(@max_per_page)
  end

  defp total_pages(0, _per_page), do: 0
  defp total_pages(total, per_page), do: div(total + per_page - 1, per_page)

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
