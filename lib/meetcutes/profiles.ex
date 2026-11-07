defmodule Meetcutes.Profiles do
  @moduledoc """
  Profile and settings writes for the current user.

  The React client still speaks a mix of canonical snake_case and the legacy
  Supabase column names, so this module normalizes both shapes before touching
  Ecto. The authenticated user always comes from the session; client-supplied
  identifiers are ignored.
  """

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias Meetcutes.Accounts.UserToken
  alias Meetcutes.GeoPrivacy
  alias Meetcutes.Repo
  alias Meetcutes.Uploads

  @legacy_aliases %{
    "userhandle" => "nickname",
    "firstname" => "first_name",
    "lastname" => "last_name",
    "phonenumber" => "phone_number",
    "emailsearch" => "email_search",
    "phonenumbersearch" => "phone_number_search",
    "userhandlesearch" => "user_handle_search",
    "onlyhundredmileevisiblity" => "only_hundred_miles_visibility",
    "onlyhundredmilesvisibility" => "only_hundred_miles_visibility",
    "hidelastname" => "hide_last_name",
    "defaultcoordsset" => "default_coords_set",
    "usercoordsset" => "user_coords_set",
    "exactcoordsset" => "exact_coords_set",
    "dateoflocation" => "date_of_location",
    "dateofcoordinates" => "date_of_coordinates",
    "timeoflogin" => "time_of_login",
    "questionairevalues" => "questionaire_values",
    "questionairevaluesset" => "questionaire_values_set",
    "previouseventsattendeeslist" => "previous_events_attendees_list",
    "previouseventsattendeesdate" => "previous_events_attendees_date",
    "termsaccepted" => "terms_accepted",
    "visibilitypreference" => "visibility_preference"
  }

  @datetime_fields ~w(
    date_of_location
    date_of_coordinates
    time_of_login
    last_login_at
    last_seen_at
    previous_events_attendees_date
  )

  @doc """
  Updates the profile for the given user.

  Uploads are passed as `:avatar` / `:banner` options (or as `%Plug.Upload{}`
  values in the params) and are validated before any metadata is written.
  """
  def update_profile(%User{} = user, attrs, opts \\ []) when is_map(attrs) do
    normalized = normalize_attrs(attrs, user)
    avatar = opts[:avatar] || take_upload(normalized, "avatar")
    banner = opts[:banner] || take_upload(normalized, "banner")
    normalized = Map.drop(normalized, ["avatar", "banner"])

    changeset = User.profile_changeset(user, normalized)

    with :ok <- Uploads.validate(avatar),
         :ok <- Uploads.validate(banner) do
      Repo.transact(fn ->
        with {:ok, updated} <- Repo.update(changeset),
             {:ok, updated} <- maybe_store_media(updated, :avatar, avatar),
             {:ok, updated} <- maybe_store_media(updated, :banner, banner) do
          {:ok, updated}
        end
      end)
    end
  end

  @doc """
  Returns a fresh copy of the user, including any columns written by a worker.
  """
  def get_profile(%User{} = user), do: Repo.reload(user)

  @max_images 10

  @doc """
  Maximum number of profile photos a user may keep.
  """
  def max_images, do: @max_images

  @doc """
  Stores an uploaded photo in the given 0-based slot and records its filename in
  `users.images`.

  The new file is written first; if the metadata update fails it is removed
  again so storage never holds a file the database does not reference.
  """
  def set_image(%User{}, slot, %Plug.Upload{})
      when is_integer(slot) and (slot < 0 or slot >= @max_images) do
    {:error, :invalid_slot}
  end

  def set_image(%User{} = user, slot, %Plug.Upload{} = upload)
      when is_integer(slot) and slot >= 0 and slot < @max_images do
    current = normalize_images(user.images)

    with {:ok, %{filename: filename}} <- Uploads.store(user, :image, upload) do
      images = put_image_slot(current, slot, filename)
      changeset = User.images_changeset(user, images)

      case Repo.update(changeset) do
        {:ok, updated} ->
          # Best effort: drop the file this slot used to point at.
          Uploads.delete(user, Enum.at(current, slot))
          {:ok, updated}

        {:error, changeset} ->
          Uploads.delete(user, filename)
          {:error, changeset}
      end
    end
  end

  def set_image(_user, _slot, _upload), do: {:error, :invalid_image}

  @doc """
  Clears a 0-based photo slot and removes the stored file.
  """
  def remove_image(%User{}, slot)
      when is_integer(slot) and (slot < 0 or slot >= @max_images) do
    {:error, :invalid_slot}
  end

  def remove_image(%User{} = user, slot)
      when is_integer(slot) and slot >= 0 and slot < @max_images do
    images = normalize_images(user.images)

    case Enum.at(images, slot) do
      filename when is_binary(filename) and filename != "" ->
        changeset =
          User.images_changeset(user, List.replace_at(images, slot, ""))

        case Repo.update(changeset) do
          {:ok, updated} ->
            Uploads.delete(user, filename)
            {:ok, updated}

          {:error, changeset} ->
            {:error, changeset}
        end

      _empty ->
        {:ok, user}
    end
  end

  def remove_image(_user, _slot), do: {:error, :invalid_slot}

  @doc """
  Reorders the photos a user already owns.

  Entries must be `""` (empty slot) or a filename currently recorded on the
  user; duplicates are rejected so a file cannot be shown twice.
  """
  def reorder_images(%User{} = user, images) when is_list(images) do
    current = normalize_images(user.images)

    with :ok <- validate_reorder(images, current) do
      user
      |> User.images_changeset(images)
      |> Repo.update()
    end
  end

  def reorder_images(_user, _images), do: {:error, :invalid_images}

  defp validate_reorder(images, current) do
    present = Enum.reject(images, &(&1 == ""))

    if length(images) <= @max_images and
         Enum.all?(images, &is_binary/1) and
         Enum.all?(present, &(&1 in current)) and
         length(present) == length(Enum.uniq(present)) do
      :ok
    else
      {:error, :invalid_images}
    end
  end

  defp normalize_images(images) when is_list(images) do
    Enum.map(images, fn
      nil -> ""
      value when is_binary(value) -> value
      value -> to_string(value)
    end)
  end

  defp normalize_images(_images), do: []

  defp put_image_slot(images, slot, filename) do
    images = Enum.take(images, @max_images)
    padding = max(slot + 1 - length(images), 0)

    (images ++ List.duplicate("", padding))
    |> List.replace_at(slot, filename)
  end

  @doc """
  Deactivates the account without removing rows.

  The user is flagged `user_state: :delete` and `is_active: false`, so they
  disappear from feeds and can no longer sign in. All session tokens are
  revoked so an already-issued bearer token stops working immediately.
  """
  def deactivate_profile(%User{} = user) do
    changeset = Ecto.Changeset.change(user, user_state: :delete, is_active: false)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: updated}} -> {:ok, updated}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Returns true when no existing account already uses `handle`.

  Deactivated accounts still hold their nickname (they are soft-deactivated,
  not deleted), so they keep the handle reserved.
  """
  def handle_available?(handle) when is_binary(handle) do
    case String.trim(handle) do
      "" -> false
      trimmed -> not Accounts.handle_taken?(trimmed)
    end
  end

  def handle_available?(_handle), do: false

  @doc """
  Normalizes a params map into canonical Ecto attributes.

  Exposed for tests so the legacy-key mapping is covered directly.
  """
  def normalize_attrs(attrs, %User{} = user) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> normalize_array_keys()
    |> normalize_aliases()
    |> normalize_json_fields()
    |> normalize_coordinates()
    |> normalize_settings(user)
    |> normalize_datetimes()
    |> drop_client_identifiers()
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_array_keys(attrs) do
    Enum.reduce(attrs, attrs, fn {key, value}, acc ->
      if String.ends_with?(key, "[]") do
        acc
        |> Map.put(String.trim_trailing(key, "[]"), value)
        |> Map.delete(key)
      else
        acc
      end
    end)
  end

  defp normalize_aliases(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      canonical = Map.get(@legacy_aliases, key, key)
      Map.put(acc, canonical, value)
    end)
  end

  defp normalize_json_fields(attrs) do
    attrs
    |> maybe_decode("settings", &is_map/1)
    |> maybe_decode("questionaire_values", &is_map/1)
    |> maybe_decode("notification_settings", &is_map/1)
    |> maybe_decode_list("images")
    |> maybe_decode_list("previous_events_attendees_list")
  end

  defp maybe_decode(attrs, key, predicate) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} ->
            if predicate.(decoded), do: Map.put(attrs, key, decoded), else: Map.delete(attrs, key)

          _ ->
            Map.delete(attrs, key)
        end

      value ->
        if is_nil(value) or predicate.(value), do: attrs, else: Map.delete(attrs, key)
    end
  end

  defp maybe_decode_list(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} when is_list(decoded) -> Map.put(attrs, key, decoded)
          _ -> Map.delete(attrs, key)
        end

      value when is_list(value) ->
        attrs

      nil ->
        attrs

      _value ->
        Map.delete(attrs, key)
    end
  end

  defp normalize_coordinates(attrs) do
    raw_lat = Map.get(attrs, "raw_lat")
    raw_lon = Map.get(attrs, "raw_lon")
    legacy_lat = Map.get(attrs, "latitude")
    legacy_lon = Map.get(attrs, "longitude")

    cond do
      present?(raw_lat) and present?(raw_lon) ->
        with {:ok, lat} <- parse_number(raw_lat),
             {:ok, lon} <- parse_number(raw_lon) do
          {fuzzed_lat, fuzzed_lon} = GeoPrivacy.fuzz_coordinates(lat, lon)

          attrs
          |> Map.put("geohash", Geohash.encode(fuzzed_lat, fuzzed_lon, 9))
          |> put_default_date_of_coordinates()
          |> Map.drop(["raw_lat", "raw_lon", "latitude", "longitude"])
        else
          _ -> Map.drop(attrs, ["raw_lat", "raw_lon"])
        end

      present?(legacy_lat) and present?(legacy_lon) ->
        with {:ok, lat} <- parse_number(legacy_lat),
             {:ok, lon} <- parse_number(legacy_lon) do
          # Legacy clients already fuzz before sending, so encode as-is.
          attrs
          |> Map.put("geohash", Geohash.encode(lat, lon, 9))
          |> put_default_date_of_coordinates()
          |> Map.drop(["latitude", "longitude", "raw_lat", "raw_lon"])
        else
          _ -> Map.drop(attrs, ["latitude", "longitude"])
        end

      true ->
        Map.drop(attrs, ["raw_lat", "raw_lon", "latitude", "longitude"])
    end
  end

  defp put_default_date_of_coordinates(attrs) do
    if Map.has_key?(attrs, "date_of_coordinates") do
      attrs
    else
      Map.put(attrs, "date_of_coordinates", DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end

  defp normalize_settings(attrs, %User{} = user) do
    settings = Map.get(attrs, "settings")
    visibility = Map.get(attrs, "visibility_preference")
    attrs = Map.delete(attrs, "visibility_preference")

    cond do
      is_map(settings) or is_binary(visibility) ->
        base = user.settings || %{}
        merged = if is_map(settings), do: Map.merge(base, settings), else: base

        merged =
          if is_binary(visibility),
            do: Map.put(merged, "visibility_preference", visibility),
            else: merged

        Map.put(attrs, "settings", merged)

      true ->
        attrs
    end
  end

  defp normalize_datetimes(attrs) do
    Enum.reduce(@datetime_fields, attrs, fn field, acc ->
      case Map.get(acc, field) do
        nil ->
          acc

        value ->
          case parse_datetime(value) do
            {:ok, datetime} -> Map.put(acc, field, datetime)
            :error -> Map.delete(acc, field)
          end
      end
    end)
  end

  defp drop_client_identifiers(attrs) do
    Map.drop(attrs, [
      "id",
      "userid",
      "user_id",
      "email",
      "hashed_password",
      "password",
      "password_confirmation",
      "calendar_token",
      "avatar",
      "banner"
    ])
  end

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, DateTime.truncate(datetime, :second)}

  defp parse_datetime(%NaiveDateTime{} = datetime) do
    {:ok, DateTime.from_naive!(datetime, "Etc/UTC")}
  end

  defp parse_datetime(%Date{} = date), do: {:ok, date_to_datetime(date)}

  defp parse_datetime(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        :error

      value =~ ~r/^\d{4}-\d{2}-\d{2}$/ ->
        with {:ok, date} <- Date.from_iso8601(value), do: {:ok, date_to_datetime(date)}

      value =~ ~r/^\d{1,2}\/\d{1,2}\/\d{4}$/ ->
        parse_us_date(value)

      true ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
          _ -> parse_naive_datetime(value)
        end
    end
  end

  defp parse_datetime(_value), do: :error

  defp parse_us_date(value) do
    with [month, day, year] <- String.split(value, "/"),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day),
         {year, ""} <- Integer.parse(year),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date_to_datetime(date)}
    else
      _ -> :error
    end
  end

  defp parse_naive_datetime(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
      _ -> :error
    end
  end

  defp date_to_datetime(%Date{} = date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp parse_number(value) when is_number(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_number(_value), do: :error

  defp present?(value), do: not is_nil(value) and value != ""

  defp take_upload(attrs, key) do
    case Map.get(attrs, key) do
      %Plug.Upload{} = upload -> upload
      _ -> nil
    end
  end

  defp maybe_store_media(user, _kind, nil), do: {:ok, user}

  defp maybe_store_media(user, kind, %Plug.Upload{} = upload) do
    case Uploads.store(user, kind, upload) do
      {:ok, media} ->
        key = if kind == :avatar, do: :avatar, else: :banner
        user |> User.media_changeset(%{key => media}) |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end
end
