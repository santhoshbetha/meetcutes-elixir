defmodule Meetcutes.Matching do
  @moduledoc """
  Daily proximity match aggregation.

  A user's `around_user_count` is the number of active opposite-gender profiles
  within 100 miles. The count is cached on the user row and refreshed by the
  daily Oban worker, or immediately on login when the cache is more than 24
  hours old.

  The geohash query is deliberately coarse first: it selects a two-ring set of
  precision-3 geohash cells around the viewer, then applies an exact Haversine
  distance check in Elixir.
  """

  import Ecto.Query, warn: false

  alias Meetcutes.Accounts.User
  alias Meetcutes.Locations
  alias Meetcutes.Relationships
  alias Meetcutes.Repo

  @radius_miles 100
  @geohash_precision 3
  @geohash_rings 2
  @stale_after_seconds 24 * 60 * 60

  def radius_miles, do: @radius_miles

  @doc """
  Returns true when the cached count has never been computed or is 24+ hours old.
  """
  def stale?(%User{around_user_count_updated_at: nil}), do: true

  def stale?(%User{around_user_count_updated_at: %DateTime{} = updated_at}) do
    DateTime.diff(DateTime.utc_now(), updated_at, :second) >= @stale_after_seconds
  end

  def stale?(_user), do: true

  @doc """
  Refreshes the count for one user id.
  """
  def refresh_around_user_count(user_id) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found}

      %User{} = user ->
        with {:ok, count} <- count_opposite_gender_within_radius(user) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          user
          |> Ecto.Changeset.change(%{
            around_user_count: count,
            around_user_count_updated_at: now
          })
          |> Repo.update()
        end
    end
  end

  def refresh_around_user_count(_user_id), do: {:error, :user_not_found}

  @doc """
  Refreshes a user only when the cached value is stale.

  This is the login/profile serialization fast path: a warm cache costs no
  extra work.
  """
  def refresh_if_stale(%User{} = user) do
    if stale?(user) do
      case refresh_around_user_count(user.id) do
        {:ok, updated} -> updated
        {:error, _reason} -> user
      end
    else
      user
    end
  end

  def refresh_if_stale(user), do: user

  @doc """
  Recomputes every active user's count. Intended for the daily Oban worker.
  """
  def refresh_all_around_counts(opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 4)

    Repo.all(
      from u in User,
        where: u.is_active == true and is_nil(u.deleted_at),
        select: u.id
    )
    |> Task.async_stream(&refresh_around_user_count/1,
      max_concurrency: concurrency,
      timeout: :infinity,
      on_timeout: :kill_task
    )
    |> Stream.run()

    :ok
  end

  @doc """
  Counts active opposite-gender profiles within the configured radius.

  Returns `{:ok, integer}`. Viewers without a geohash or a binary gender get a
  zero count rather than an error.
  """
  def count_opposite_gender_within_radius(user, radius_miles \\ @radius_miles)

  def count_opposite_gender_within_radius(%User{} = user, radius_miles) do
    with {:ok, latitude, longitude} <- viewer_coordinates(user),
         opposite when is_binary(opposite) <- opposite_gender(user.gender) do
      prefixes = geohash_prefixes(latitude, longitude)

      user.id
      |> candidates_query(opposite, prefixes)
      |> Repo.all()
      |> Enum.count(fn geohash ->
        within_radius?(latitude, longitude, geohash, radius_miles)
      end)
      |> then(&{:ok, &1})
    else
      _ -> {:ok, 0}
    end
  end

  def count_opposite_gender_within_radius(_user, _radius_miles), do: {:ok, 0}

  defp candidates_query(viewer_id, opposite_gender, prefixes) do
    query =
      from u in User,
        where: u.id != ^viewer_id,
        where: u.is_active == true and u.is_approved == true and is_nil(u.deleted_at),
        where: u.gender == ^opposite_gender,
        where: not is_nil(u.geohash),
        where: fragment("left(?, ?)", u.geohash, ^@geohash_precision) in ^prefixes,
        select: u.geohash

    Relationships.exclude_hidden(query, viewer_id)
  end

  defp viewer_coordinates(%User{geohash: geohash}) when is_binary(geohash) do
    {latitude, longitude} = Geohash.decode(geohash)
    {:ok, latitude, longitude}
  rescue
    _ -> :error
  end

  defp viewer_coordinates(_user), do: :error

  defp within_radius?(latitude, longitude, geohash, radius_miles)
       when is_binary(geohash) do
    {candidate_lat, candidate_lon} = Geohash.decode(geohash)

    Locations.distance_miles(latitude, longitude, candidate_lat, candidate_lon) <=
      radius_miles
  rescue
    _ -> false
  end

  defp within_radius?(_latitude, _longitude, _geohash, _radius_miles), do: false

  defp geohash_prefixes(latitude, longitude) do
    center = Geohash.encode(latitude, longitude, @geohash_precision)

    expand_rings([center], @geohash_rings)
    |> Enum.uniq()
  end

  defp expand_rings(prefixes, 0), do: prefixes

  defp expand_rings(prefixes, rings_left) do
    next =
      prefixes
      |> Enum.flat_map(fn prefix ->
        [prefix | Map.values(Geohash.neighbors(prefix))]
      end)
      |> Enum.uniq()

    expand_rings(next, rings_left - 1)
  end

  defp opposite_gender(gender) when is_binary(gender) do
    case String.downcase(String.trim(gender)) do
      "male" -> "Female"
      "female" -> "Male"
      _ -> nil
    end
  end

  defp opposite_gender(_gender), do: nil
end
