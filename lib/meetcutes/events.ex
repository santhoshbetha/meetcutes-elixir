defmodule Meetcutes.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  alias Meetcutes.Repo

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias Meetcutes.Events.Event
  alias Meetcutes.Events.Location
  alias Meetcutes.Events.Notifications
  alias Meetcutes.Locations
  alias Meetcutes.Notifications, as: InboxNotifications

  @max_event_distance_miles 150

  @doc """
  Returns paginated list of events with filtering
  """
  def list_events(params \\ %{}) do
    page = String.to_integer(Map.get(params, "page", "1"))
    limit = String.to_integer(Map.get(params, "limit", "20")) |> min(100)
    offset = (page - 1) * limit

    base_query = from(e in Event, preload: [:location])

    query =
      base_query
      |> apply_date_filter(params)
      |> apply_location_filter(params)
      |> apply_status_filter(params)
      |> order_by([e], asc: e.start_at)

    total = Repo.aggregate(query, :count)
    events = query |> offset(^offset) |> limit(^limit) |> Repo.all()

    %{
      events: events,
      pagination: %{
        page: page,
        limit: limit,
        total: total,
        total_pages: ceil(total / limit)
      }
    }
  end

  defp apply_date_filter(query, %{"dateFrom" => date_from, "dateTo" => date_to}) do
    # CORRECCIÃ“N: Usar NaiveDateTime.new! correctamente
    start_date = NaiveDateTime.new!(Date.from_iso8601!(date_from), ~T[00:00:00])
    end_date = NaiveDateTime.new!(Date.from_iso8601!(date_to), ~T[23:59:59])

    where(query, [e], e.start_at >= ^start_date and e.end_at <= ^end_date)
  end

  defp apply_date_filter(query, _), do: query

  defp apply_location_filter(query, %{"locations" => locations}) do
    location_list =
      String.split(locations, ",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&"%#{&1}%")

    query
    |> join(:left, [e], l in assoc(e, :location))
    |> where([e, l], fragment("LOWER(?) LIKE ANY(?)", l.name, ^location_list))
  end

  defp apply_location_filter(query, _), do: query

  defp apply_status_filter(query, %{"status" => status}) do
    status_list = String.split(status, ",") |> Enum.map(&String.trim/1)
    where(query, [e], e.status in ^status_list)
  end

  defp apply_status_filter(query, _), do: query

  @doc """
  Gets a single event.
  """
  def get_event!(id), do: Repo.get!(Event, id) |> Repo.preload(:location)

  @doc """
  Gets a single event with comments, user, and location preloaded.
  """
  def get_event_with_comments!(id) do
    Event
    |> Repo.get!(id)
    # Preload discussion & existing fields
    |> Repo.preload([:comments, :user, :location])
  end

  @doc """
  Gets a single event without raising on not found.
  Returns nil if event doesn't exist.
  """
  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> nil
      event -> Repo.preload(event, :location)
    end
  end

  @doc """
  Gets multiple events by their IDs.
  Returns a list of events, filtering out any that don't exist.
  """
  def get_events_by_ids(ids) when is_list(ids) do
    Event
    |> where([e], e.id in ^ids)
    |> preload(:location)
    |> Repo.all()
  end

  @doc """
  Lists published events near a point, optionally bounded by event date.

  Returns a page plus pagination metadata. Distance filtering happens in
  Elixir so the same haversine helper is used everywhere and no PostGIS
  extension is required.
  """
  def list_nearby_events(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 20) |> min(20) |> max(1)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    events =
      Event
      |> where([e], e.status == "PUBLISHED")
      |> apply_age_restriction(Keyword.get(opts, :user))
      |> apply_event_date_bounds(opts)
      |> preload(:location)
      |> order_by([e], asc: e.start_at)
      |> Repo.all()
      |> filter_by_distance(opts)

    total = length(events)
    page = Enum.slice(events, offset, limit)
    has_more = offset + length(page) < total
    next_page = if has_more, do: div(offset, limit) + 2, else: nil

    %{
      events: page,
      pagination: %{
        total: total,
        limit: limit,
        offset: offset,
        has_more: has_more,
        next_page: next_page
      }
    }
  end

  @doc """
  Returns aggregate male/female attendee counts for the given event IDs.

  The counts are calculated inside PostgreSQL by expanding the JSONB attendee
  map once per event. This keeps demographic numbers off the frontend and
  avoids loading profile datasets just to count genders.
  """
  def gender_counts(event_ids) when is_list(event_ids) do
    ids = event_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case ids do
      [] ->
        %{}

      ids ->
        sql = """
        SELECT e.id,
               COUNT(*) FILTER (
                 WHERE LOWER(COALESCE(a.value->>'gender', u.gender, '')) LIKE 'm%'
               )::int AS male_count,
               COUNT(*) FILTER (
                 WHERE LOWER(COALESCE(a.value->>'gender', u.gender, '')) LIKE 'f%'
               )::int AS female_count
        FROM events e
        CROSS JOIN LATERAL jsonb_each(COALESCE(e.attendees, '{}'::jsonb)) AS a
        LEFT JOIN users u ON u.id = a.key
        WHERE e.id = ANY($1)
        GROUP BY e.id
        """

        %{rows: rows} = Repo.query!(sql, [ids])

        Map.new(rows, fn [event_id, male_count, female_count] ->
          {event_id, %{male_count: male_count, female_count: female_count}}
        end)
    end
  end

  @doc """
  Checks whether at least half of the target event's registered attendees
  overlap with attendees from events the requesting user has already joined.

  A single grouped SQL statement builds the two attendee ID sets and compares
  them, so no attendee/profile arrays cross the network boundary.
  """
  def fatigue_check(event_id, user_id)
      when is_binary(event_id) and is_binary(user_id) do
    sql = """
    WITH target_attendees AS (
      SELECT jsonb_object_keys(COALESCE(e.attendees, '{}'::jsonb)) AS user_id
      FROM events e
      WHERE e.id = $1
    ),
    past_attendees AS (
      SELECT DISTINCT jsonb_object_keys(COALESCE(e.attendees, '{}'::jsonb)) AS user_id
      FROM events e
      WHERE e.id <> $1
        AND e.attendees ? $2
    )
    SELECT
      (SELECT COUNT(*) FROM target_attendees)::int AS attendee_count,
      (
        SELECT COUNT(*)
        FROM target_attendees t
        INNER JOIN past_attendees p USING (user_id)
      )::int AS overlap_count
    """

    %{rows: [[attendee_count, overlap_count]]} =
      Repo.query!(sql, [event_id, user_id])

    attendee_count > 0 and overlap_count * 2 >= attendee_count
  end

  @doc """
  Lists every event created by the given user, soonest first.
  """
  def list_created_events(%User{} = user), do: list_created_events(user, []).events

  def list_created_events(%User{} = user, opts) do
    Event
    |> where([e], e.created_by == ^user.id)
    |> paginate_events(opts)
  end

  @doc """
  Lists published events the given user is attending, soonest first.
  """
  def list_joined_events(%User{} = user), do: list_joined_events(user, []).events

  def list_joined_events(%User{} = user, opts) do
    Event
    |> where([e], e.status == "PUBLISHED")
    |> where([e], fragment("jsonb_exists(?, ?)", e.attendees, ^user.id))
    |> paginate_events(opts)
  end

  defp paginate_events(query, opts) do
    limit = opts |> Keyword.get(:limit, 20) |> min(20) |> max(1)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    total = Repo.aggregate(query, :count)

    events =
      query
      |> preload(:location)
      |> order_by([e], asc: e.start_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    has_more = offset + length(events) < total

    %{
      events: events,
      pagination: %{
        total: total,
        limit: limit,
        offset: offset,
        has_more: has_more,
        next_page: if(has_more, do: div(offset, limit) + 2, else: nil)
      }
    }
  end

  defp apply_event_date_bounds(query, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    query =
      if match?(%Date{}, start_date) do
        start_at = NaiveDateTime.new!(start_date, ~T[00:00:00])
        where(query, [e], e.start_at >= ^start_at)
      else
        query
      end

    if match?(%Date{}, end_date) do
      end_at = NaiveDateTime.new!(end_date, ~T[23:59:59])
      where(query, [e], e.start_at <= ^end_at)
    else
      query
    end
  end

  # Discovery visibility is requester-aware. Restricted events are omitted
  # entirely unless the authenticated viewer's gender-specific age bounds match.
  defp apply_age_restriction(query, %User{} = user) do
    case {normalize_gender(user.gender), user.age} do
      {"male", age} when is_integer(age) ->
        where(
          query,
          [e],
          e.has_age_restriction == false or
            (not is_nil(e.men_min_age) and e.men_min_age <= ^age and
               not is_nil(e.men_max_age) and e.men_max_age >= ^age)
        )

      {"female", age} when is_integer(age) ->
        where(
          query,
          [e],
          e.has_age_restriction == false or
            (not is_nil(e.women_min_age) and e.women_min_age <= ^age and
               not is_nil(e.women_max_age) and e.women_max_age >= ^age)
        )

      _ ->
        where(query, [e], e.has_age_restriction == false)
    end
  end

  defp apply_age_restriction(query, _user), do: where(query, [e], e.has_age_restriction == false)

  defp filter_by_distance(events, opts) do
    lat = Keyword.get(opts, :lat)
    lng = Keyword.get(opts, :lng)
    distance_miles = Keyword.get(opts, :distance_miles)

    if is_number(lat) and is_number(lng) and is_number(distance_miles) do
      Enum.filter(events, fn event ->
        location = event.location

        is_number(location && location.latitude) and is_number(location && location.longitude) and
          Locations.distance_miles(lat, lng, location.latitude, location.longitude) <=
            distance_miles
      end)
    else
      events
    end
  end

  @doc """
  Creates a published event from the legacy React payload.

  The creator is always the bearer user; any client-supplied `created_by`,
  `creatorid`, or `userid` value is ignored. The location is resolved or
  created, the date/time strings are combined into UTC datetimes, and the
  150-mile radius plus per-location overlap rules are enforced.
  """
  def create_event_for_user(%User{} = user, params) when is_map(params) do
    with {:ok, location} <- resolve_event_location(params),
         {:ok, start_at, end_at, event_date} <- event_times(params),
         :ok <- ensure_within_distance(user, location),
         :ok <- ensure_no_conflict(location.id, start_at, end_at) do
      create_event(
        %{
          "title" => params["title"],
          "content" => params["content"] || params["description"],
          "location_id" => location.id,
          "start_at" => start_at,
          "end_at" => end_at,
          "event_date" => event_date,
          "status" => "PUBLISHED",
          "has_age_restriction" => truthy_param(params["has_age_restriction"]),
          "men_min_age" => params["men_min_age"],
          "men_max_age" => params["men_max_age"],
          "women_min_age" => params["women_min_age"],
          "women_max_age" => params["women_max_age"]
        },
        user.id
      )
    end
  end

  @doc """
  Returns true when another event already occupies the location during the
  supplied window. Cancelled events do not block a slot.
  """
  def event_conflict?(location_id, start_at, end_at) do
    Event
    |> where([e], e.location_id == ^location_id)
    |> where([e], e.status != "CANCELLED")
    |> where([e], e.start_at < ^end_at and e.end_at > ^start_at)
    |> Repo.exists?()
  end

  defp ensure_no_conflict(location_id, start_at, end_at) do
    if event_conflict?(location_id, start_at, end_at) do
      {:error, :conflict}
    else
      :ok
    end
  end

  defp ensure_within_distance(
         %User{geohash: geohash},
         %Location{latitude: latitude, longitude: longitude}
       )
       when is_binary(geohash) and is_number(latitude) and is_number(longitude) do
    try do
      {user_latitude, user_longitude} = Geohash.decode(geohash)

      if Locations.distance_miles(user_latitude, user_longitude, latitude, longitude) <=
           @max_event_distance_miles do
        :ok
      else
        {:error, :too_far}
      end
    rescue
      _ -> :ok
    end
  end

  defp ensure_within_distance(_user, _location), do: :ok

  defp resolve_event_location(params) do
    location_id = params["location_id"] || params["locationid"]

    if is_binary(location_id) and location_id != "" do
      case Locations.get_location(location_id) do
        nil -> create_location_from_params(params)
        location -> {:ok, location}
      end
    else
      create_location_from_params(params)
    end
  end

  defp create_location_from_params(params) do
    nested = if is_map(params["location"]), do: params["location"], else: %{}

    street =
      first_string([nested["street"], nested["address1"], params["address1"], params["street"]])

    locality =
      first_string([nested["locality"], nested["city"], params["city"], params["locality"]])

    state = first_string([nested["state"], params["state"]])

    postal_code =
      first_string([nested["postal_code"], nested["zipcode"], params["zipcode"], params["zip"]])

    latitude = first_number([nested["latitude"], params["eventlat"], params["latitude"]])
    longitude = first_number([nested["longitude"], params["eventlng"], params["longitude"]])

    name =
      first_string([
        nested["name"],
        params["location_name"],
        params["name"],
        params["location"],
        street
      ]) || "Event Location"

    case Locations.find_by_address(street, locality, state, postal_code) do
      %Location{} = location ->
        {:ok, location}

      nil ->
        Locations.create_location(%{
          name: name,
          street: street,
          locality: locality,
          state: state,
          postal_code: postal_code,
          latitude: latitude,
          longitude: longitude
        })
    end
  end

  defp event_times(params) do
    with {:ok, start_at} <- parse_datetime(params["start_at"]),
         {:ok, end_at} <- parse_datetime(params["end_at"]),
         {:ok, event_date} <- parse_date(params["event_date"] || params["eventdate"]) do
      cond do
        start_at && end_at ->
          {:ok, start_at, end_at, DateTime.to_date(start_at)}

        true ->
          with {:ok, start_time} <- parse_time(params["start_time"] || params["starttime"]),
               {:ok, end_time} <- parse_time(params["end_time"] || params["endtime"]),
               {:ok, start_at} <- combine(event_date, start_time),
               {:ok, end_at} <- combine(event_date, end_time),
               :ok <- validate_window(start_at, end_at) do
            {:ok, start_at, end_at, event_date}
          end
      end
    end
  end

  defp parse_datetime(nil), do: {:ok, nil}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  defp parse_date(_value), do: :error

  defp parse_time(%Time{} = time), do: {:ok, time}

  defp parse_time(value) when is_binary(value) do
    value = String.trim(value)
    value = if String.length(value) == 5, do: value <> ":00", else: value

    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      _ -> :error
    end
  end

  defp parse_time(_value), do: :error

  defp combine(date, time) do
    case NaiveDateTime.new(date, time) do
      {:ok, naive} ->
        case DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, datetime} -> {:ok, datetime}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp validate_window(start_at, end_at) do
    if DateTime.compare(end_at, start_at) == :gt do
      :ok
    else
      {:error, :invalid_time_range}
    end
  end

  defp first_string(values) do
    Enum.find_value(values, fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end)
  end

  defp first_number(values) do
    Enum.find_value(values, fn
      value when is_number(value) ->
        value

      value when is_binary(value) ->
        case Float.parse(String.trim(value)) do
          {number, ""} -> number
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp truthy_param(true), do: true
  defp truthy_param("true"), do: true
  defp truthy_param(1), do: true
  defp truthy_param(_), do: false

  @doc """
  Creates an event.
  """
  def create_event(attrs \\ %{}, user_id) do
    # Handle location data - find or create location if provided as a map
    attrs_with_location =
      case Map.get(attrs, "location") do
        location_data when is_map(location_data) and map_size(location_data) > 0 ->
          case Meetcutes.Locations.find_or_create_location(location_data) do
            {:ok, location} ->
              attrs
              |> Map.delete("location")
              |> Map.put("location_id", location.id)

            {:error, reason} ->
              # Return error if location creation fails
              {:error, reason}
          end

        _ ->
          # No location data provided or location_id already present
          attrs
      end

    # If we got an error from location handling, return it
    case attrs_with_location do
      {:error, _} = error ->
        error

      attrs_with_location ->
        attrs_with_user = Map.put(attrs_with_location, "created_by", user_id)

        %Event{}
        |> Event.changeset(attrs_with_user)
        |> Repo.insert()
        |> case do
          {:ok, event} ->
            event = Repo.preload(event, :location)
            Notifications.notify_event_created(event)
            {:ok, event}

          error ->
            error
        end
    end
  end

  @doc """
  Updates an event (status, internal_notes, and location allowed).
  """
  def update_event(%Event{} = event, attrs) do
    # Handle location data - find or create location if provided as a map
    attrs_with_location =
      case Map.get(attrs, "location") do
        location_data when is_map(location_data) and map_size(location_data) > 0 ->
          case Meetcutes.Locations.find_or_create_location(location_data) do
            {:ok, location} ->
              attrs
              |> Map.delete("location")
              |> Map.put("location_id", location.id)

            {:error, reason} ->
              # Return error if location creation fails
              {:error, reason}
          end

        _ ->
          # No location data provided or location_id already present
          attrs
      end

    # If we got an error from location handling, return it
    case attrs_with_location do
      {:error, _} = error ->
        error

      attrs_with_location ->
        allowed_fields =
          Map.take(attrs_with_location, [
            "status",
            "internal_notes",
            "location_id",
            "title",
            "content",
            "start_at",
            "end_at",
            "event_date",
            "attendees_count",
            "attendees",
            "has_age_restriction",
            "men_min_age",
            "men_max_age",
            "women_min_age",
            "women_max_age"
          ])

        forbidden_fields =
          Map.drop(attrs_with_location, [
            "status",
            "internal_notes",
            "location_id",
            "title",
            "content",
            "start_at",
            "end_at",
            "event_date",
            "attendees_count",
            "attendees",
            "has_age_restriction",
            "men_min_age",
            "men_max_age",
            "women_min_age",
            "women_max_age"
          ])

        if map_size(forbidden_fields) > 0 do
          {:error, :forbidden_fields}
        else
          update_allowed_fields(event, allowed_fields)
        end
    end
  end

  defp update_allowed_fields(event, allowed_fields) do
    event
    |> Event.changeset(allowed_fields)
    |> Repo.update()
    |> case do
      {:ok, updated_event} ->
        handle_successful_update(event, updated_event)

      error ->
        error
    end
  end

  defp handle_successful_update(old_event, updated_event) do
    notify_status_change(old_event, updated_event)
    {:ok, Repo.preload(updated_event, :location, force: true)}
  end

  defp notify_status_change(old_event, new_event) do
    case {old_event.status, new_event.status} do
      {"DRAFT", "PUBLISHED"} ->
        Notifications.notify_event_published(new_event)

      {"CANCELLED", "PUBLISHED"} ->
        Notifications.notify_event_republished(new_event)

      {_, "CANCELLED"} when old_event.status != "CANCELLED" ->
        Notifications.notify_event_cancelled(new_event)

      {old_status, new_status} when old_status != new_status ->
        Notifications.notify_event_updated(new_event)

      _ ->
        # Solo cambiÃ³ internal_notes, no el status
        if old_event.internal_notes != new_event.internal_notes do
          Notifications.notify_event_updated(new_event)
        else
          :no_notification
        end
    end
  end

  @doc """
  List public events (only PUBLISHED and CANCELLED status)
  """
  def list_public_events(params \\ %{}) do
    _public_params = Map.drop(params, ["status"])

    %{events: events, pagination: pagination} =
      params
      |> Map.put("status", "PUBLISHED,CANCELLED")
      |> list_events()

    public_events = Enum.map(events, &Event.public_fields/1)

    %{
      events: public_events,
      pagination: pagination
    }
  end

  @doc """
  Cancels an event by updating its status to "CANCELLED".

  ## Examples

      iex> cancel_event(event)
      {:ok, %Event{}}

      iex> cancel_event(event)
      {:error, %Ecto.Changeset{}}

  """
  def cancel_event(%Event{} = event) do
    update_event(event, %{"status" => "CANCELLED"})
  end

  @doc """
  Deletes a event.

  ## Examples

      iex> delete_event(event)
      {:ok, %Event{}}

      iex> delete_event(event)
      {:error, %Ecto.Changeset{}}

  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Updates an event only when the bearer user owns it.

  The event row, its location projection, and every attendee notification row
  are committed atomically. Channel broadcasts happen after the transaction
  commits.
  """
  def update_event_for_owner(%User{} = user, event_id, params) when is_map(params) do
    Repo.transaction(fn ->
      event = fetch_event_for_owner!(event_id, user)

      with {:ok, attrs} <- owner_update_attrs(event, params),
           {:ok, updated} <- apply_owner_update(event, attrs) do
        updated = Repo.preload(updated, :location, force: true)

        entries =
          if owner_update_changed?(event, updated) do
            updated
            |> build_attendee_notifications(
              "Event updated: #{updated.title}",
              "Notice: The event '#{updated.title}' has updated its logistics (Date/Time or Venue). Please check the event page for details.",
              "updated"
            )
          else
            []
          end

        InboxNotifications.insert_broadcast_entries(entries)
        {updated, entries}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {updated, entries}} ->
        InboxNotifications.broadcast_entries(entries)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancels an event only when the bearer user owns it.

  Attendee ids are captured before the attendance projection is cleared. The
  cancellation rows and the event update commit in one transaction, then the
  persisted notifications broadcast to each attendee's personal topic.
  """
  def cancel_event_for_owner(%User{} = user, event_id) do
    Repo.transaction(fn ->
      event = fetch_event_for_owner!(event_id, user)

      entries =
        InboxNotifications.build_event_broadcasts(
          attendee_ids_for_event(event),
          "Event canceled: #{event.title}",
          "Alert: The upcoming event '#{event.title}' has been canceled by the organizer.",
          %{
            "event_id" => event.id,
            "event_title" => event.title,
            "kind" => "canceled"
          }
        )

      InboxNotifications.insert_broadcast_entries(entries)

      case event
           |> Ecto.Changeset.change(%{
             status: "CANCELLED",
             attendees: %{},
             attendees_count: 0
           })
           |> Repo.update() do
        {:ok, cancelled} ->
          {Repo.preload(cancelled, :location, force: true), entries}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, {updated, entries}} ->
        InboxNotifications.broadcast_entries(entries)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the ids of every user registered for an event.

  The v1 attendance projection is the `events.attendees` map. Legacy users may
  still carry the event id in `registered_events`, so those ids are unioned in
  without double-notifying anyone.
  """
  def attendee_ids_for_event(%Event{} = event) do
    projected_ids =
      event.attendees
      |> Kernel.||(%{})
      |> Map.keys()
      |> Enum.reject(&is_nil/1)

    legacy_ids =
      Repo.all(
        from u in User,
          where: not is_nil(u.registered_events),
          where:
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS elem WHERE elem->>'event_id' = ?)",
              u.registered_events,
              ^event.id
            ),
          select: u.id
      )

    Enum.uniq(projected_ids ++ legacy_ids)
  end

  defp fetch_event_for_owner!(event_id, %User{} = user) do
    case Repo.get(Event, event_id) do
      nil ->
        Repo.rollback(:event_not_found)

      event ->
        event = Repo.preload(event, :location, force: true)

        if event.created_by != user.id do
          Repo.rollback(:forbidden_event_owner)
        end

        event
    end
  end

  defp owner_update_attrs(event, params) do
    with {:ok, location} <- update_event_location(event, params) do
      case owner_event_times(event, params) do
        {:ok, start_at, end_at, event_date} ->
          attrs = %{
            "title" => params["title"] || event.title,
            "content" => params["content"] || params["description"] || event.content,
            "location_id" => location.id,
            "start_at" => start_at,
            "end_at" => end_at,
            "event_date" => event_date
          }

          {:ok, Map.merge(attrs, owner_age_attrs(params))}

        :error ->
          {:error, :invalid_time_range}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp update_event_location(%Event{location: %Location{} = location}, params) do
    nested = if is_map(params["location"]), do: params["location"], else: %{}

    attrs =
      %{
        name: first_string([nested["name"], params["location"], params["location_name"]]),
        street:
          first_string([
            nested["street"],
            nested["address1"],
            params["address1"],
            params["street"]
          ]),
        locality:
          first_string([nested["locality"], nested["city"], params["city"], params["locality"]]),
        state: first_string([nested["state"], params["state"]]),
        postal_code:
          first_string([
            nested["postal_code"],
            nested["zipcode"],
            params["zipcode"],
            params["zip"]
          ]),
        latitude: first_number([nested["latitude"], params["eventlat"], params["latitude"]]),
        longitude: first_number([nested["longitude"], params["eventlng"], params["longitude"]])
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Locations.update_location(location, attrs)
  end

  defp update_event_location(%Event{}, params), do: resolve_event_location(params)

  defp owner_event_times(event, params) do
    if is_binary(params["start_at"]) and is_binary(params["end_at"]) do
      with {:ok, start_at} <- parse_datetime(params["start_at"]),
           {:ok, end_at} <- parse_datetime(params["end_at"]),
           :ok <- validate_window(start_at, end_at) do
        {:ok, start_at, end_at, DateTime.to_date(start_at)}
      end
    else
      date =
        params["eventdate"] || params["event_date"] || event.event_date ||
          DateTime.to_date(event.start_at)

      start_time = params["start_time"] || params["starttime"] || DateTime.to_time(event.start_at)
      end_time = params["end_time"] || params["endtime"] || DateTime.to_time(event.end_at)

      with {:ok, date} <- parse_date(date),
           {:ok, start_time} <- parse_time(start_time),
           {:ok, end_time} <- parse_time(end_time),
           {:ok, start_at} <- combine(date, start_time),
           {:ok, end_at} <- combine(date, end_time),
           :ok <- validate_window(start_at, end_at) do
        {:ok, start_at, end_at, date}
      end
    end
  end

  defp owner_age_attrs(params) do
    if Map.has_key?(params, "has_age_restriction") do
      if truthy_param(params["has_age_restriction"]) do
        %{
          "has_age_restriction" => true,
          "men_min_age" => params["men_min_age"],
          "men_max_age" => params["men_max_age"],
          "women_min_age" => params["women_min_age"],
          "women_max_age" => params["women_max_age"]
        }
      else
        %{
          "has_age_restriction" => false,
          "men_min_age" => nil,
          "men_max_age" => nil,
          "women_min_age" => nil,
          "women_max_age" => nil
        }
      end
    else
      %{}
    end
  end

  defp apply_owner_update(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  defp owner_update_changed?(old_event, updated_event) do
    event_fields = [
      :title,
      :content,
      :start_at,
      :end_at,
      :event_date,
      :location_id,
      :has_age_restriction,
      :men_min_age,
      :men_max_age,
      :women_min_age,
      :women_max_age
    ]

    location_fields = [
      :name,
      :street,
      :locality,
      :state,
      :postal_code,
      :latitude,
      :longitude
    ]

    Enum.any?(event_fields, &(Map.get(old_event, &1) != Map.get(updated_event, &1))) or
      Enum.any?(
        location_fields,
        &(Map.get(old_event.location || %{}, &1) != Map.get(updated_event.location || %{}, &1))
      )
  end

  defp build_attendee_notifications(event, title, body, kind) do
    InboxNotifications.build_event_broadcasts(
      attendee_ids_for_event(event),
      title,
      body,
      %{
        "event_id" => event.id,
        "event_title" => event.title,
        "kind" => kind
      }
    )
  end

  @doc """
  Deletes all events older than a month.

  ## Examples

      iex> delete_old_events()
      {:ok, 5}

  """
  def delete_old_events do
    # Calculate date one month ago
    one_month_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    # First, get the IDs of events that will be deleted
    event_ids = from(e in Event, where: e.end_at < ^one_month_ago, select: e.id) |> Repo.all()

    # Delete comments for these events
    comments_deleted =
      if event_ids != [] do
        from(c in Meetcutes.Discussion.Comment, where: c.event_id in ^event_ids)
        |> Repo.delete_all()
        |> case do
          {count, _} -> count
          _ -> 0
        end
      else
        0
      end

    # Delete the events
    case Repo.delete_all(from(e in Event, where: e.end_at < ^one_month_ago)) do
      {events_count, _} ->
        {:ok, events_count, comments_deleted}

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.

  ## Examples

      iex> change_event(event)
      %Ecto.Changeset{data: %Event{}}

  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  @doc """
  Searches for events with advanced filtering options.

  ## Options
  - :start_date - Filter events starting from this date (ISO 8601 format)
  - :geohash - User geohash used as the search origin
  - :distance_miles - Maximum distance in miles (optional)
  """
  def search_events(opts \\ []) do
    start_date = Keyword.get(opts, :start_date)
    geohash = Keyword.get(opts, :geohash)
    distance_miles = Keyword.get(opts, :distance_miles)

    base_query =
      from(e in Event,
        join: l in assoc(e, :location),
        where: e.status == "PUBLISHED",
        preload: [:location]
      )
      |> apply_age_restriction(Keyword.get(opts, :user))

    # Apply start date filter
    query_with_date =
      if start_date do
        # Parse the start_date string to a date
        case Date.from_iso8601(start_date) do
          {:ok, date} ->
            # Filter events that start on or after the given date
            start_datetime = NaiveDateTime.new!(date, ~T[00:00:00])
            from([e, l] in base_query, where: e.start_at >= ^start_datetime)

          _ ->
            base_query
        end
      else
        base_query
      end

    # Apply distance filter if coordinates and distance provided
    query_with_distance =
      case decode_search_origin(geohash, distance_miles) do
        {:ok, {latitude, longitude}} ->
          events = Repo.all(query_with_date)

          Enum.filter(events, fn event ->
            event.location && event.location.latitude && event.location.longitude &&
              calculate_distance(
                latitude,
                longitude,
                event.location.latitude,
                event.location.longitude
              ) <= distance_miles
          end)

        :error ->
          Repo.all(query_with_date)
      end

    query_with_distance
  end

  defp decode_search_origin(geohash, distance_miles)
       when is_binary(geohash) and is_number(distance_miles) do
    try do
      {:ok, Geohash.decode(geohash)}
    rescue
      _ -> :error
    end
  end

  defp decode_search_origin(_, _), do: :error

  # Calculate distance between two points using haversine formula
  # Returns distance in miles
  defp calculate_distance(lat1, lon1, lat2, lon2) do
    # Earth's radius in miles
    earth_radius = 3958.8

    # Convert degrees to radians
    lat1_rad = lat1 * :math.pi() / 180
    lon1_rad = lon1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    lon2_rad = lon2 * :math.pi() / 180

    # Haversine formula
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    earth_radius * c
  end

  @doc """
  Adds a user to an event's attendees list.

  Accepts either a `%User{}` or a user id so the legacy controller and the
  bearer-authenticated v1 controller can share the same implementation. A
  snapshot of the attendee's public identity is stored with the attendance so
  feeds do not need to join the users table on every render.
  """
  def join_event(event_id, user_or_id) do
    with %User{} = user <- resolve_user(user_or_id),
         %Event{} = event <- get_event(event_id),
         :ok <- ensure_age_eligible(event, user) do
      attendees = event.attendees || %{}

      if Map.has_key?(attendees, user.id) do
        {:error, :already_attending}
      else
        updated_attendees = Map.put(attendees, user.id, attendee_snapshot(user))

        event
        |> Event.attendance_changeset(updated_attendees)
        |> Repo.update()
        |> case do
          {:ok, updated_event} ->
            record_previous_attendees(event, user)

            if event.created_by && event.created_by != user.id do
              Notifications.notify_user_joined_event(event, user)
            end

            {:ok, Repo.preload(updated_event, :location, force: true)}

          error ->
            error
        end
      end
    else
      {:error, :age_restricted} = error -> error
      nil -> {:error, :event_not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns true when the user satisfies the event's gender-specific age bounds.

  Bounds are inclusive and only apply to users whose gender starts with `m`
  (men) or `f` (women). Users with another/unset gender are not blocked by a
  gender-specific rule.
  """
  def age_restriction_allows?(%Event{} = event, %User{} = user) do
    if event.has_age_restriction do
      case gender_age_bounds(event, user.gender) do
        nil ->
          true

        {min_age, max_age} ->
          min_age = min_age || 0
          max_age = max_age || 999

          is_integer(user.age) and user.age >= min_age and user.age <= max_age
      end
    else
      true
    end
  end

  defp ensure_age_eligible(event, user) do
    if age_restriction_allows?(event, user) do
      :ok
    else
      {:error, :age_restricted}
    end
  end

  defp gender_age_bounds(event, gender) do
    case normalize_gender(gender) do
      "male" -> {event.men_min_age, event.men_max_age}
      "female" -> {event.women_min_age, event.women_max_age}
      _ -> nil
    end
  end

  defp normalize_gender(gender) when is_binary(gender) do
    normalized = gender |> String.trim() |> String.downcase()

    cond do
      String.starts_with?(normalized, "m") -> "male"
      String.starts_with?(normalized, "f") -> "female"
      true -> nil
    end
  end

  defp normalize_gender(_), do: nil

  @doc """
  Removes a user from an event's attendees list.
  """
  def leave_event(event_id, user_or_id) do
    with %User{} = user <- resolve_user(user_or_id),
         %Event{} = event <- get_event(event_id) do
      attendees = event.attendees || %{}

      if Map.has_key?(attendees, user.id) do
        updated_attendees = Map.delete(attendees, user.id)

        event
        |> Event.attendance_changeset(updated_attendees)
        |> Repo.update()
        |> case do
          {:ok, updated_event} ->
            {:ok, Repo.preload(updated_event, :location, force: true)}

          error ->
            error
        end
      else
        {:error, :not_attending}
      end
    else
      nil -> {:error, :event_not_found}
      {:error, _} = error -> error
    end
  end

  defp resolve_user(%User{} = user), do: user
  defp resolve_user(user_id) when is_binary(user_id), do: Accounts.get_user(user_id)
  defp resolve_user(_), do: nil

  defp attendee_snapshot(%User{} = user) do
    %{
      "handle" => user.nickname,
      "gender" => user.gender,
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "joined_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Preserves the legacy "people you met at events" signal: everyone already
  # attending learns that the new attendee was at the same event.
  defp record_previous_attendees(%Event{attendees: attendees}, %User{} = joiner) do
    handle = joiner.nickname

    if is_binary(handle) and handle != "" do
      (attendees || %{})
      |> Map.keys()
      |> List.delete(joiner.id)
      |> Accounts.list_users_by_ids()
      |> Enum.each(fn other ->
        list = other.previous_events_attendees_list || []

        unless handle in list do
          other
          |> Ecto.Changeset.change(previous_events_attendees_list: list ++ [handle])
          |> Repo.update()
        end
      end)
    end

    :ok
  end

  # List upcoming events for a specific user within 30 miles of their location
  def list_upcoming_events_for_user(user) do
    # Step 1: Get the current moment in UTC and today's date
    now_utc = DateTime.utc_now()
    today = Date.utc_today()

    # Step 2: Query upcoming events created by the user within 30 miles
    # First get events from database with location join
    events =
      from(e in Event,
        join: l in assoc(e, :location),
        where: e.created_by == ^user.id,
        where: e.start_at >= ^now_utc,
        where: e.event_date > ^today,
        where: not is_nil(l.latitude) and not is_nil(l.longitude),
        preload: [:location],
        order_by: [asc: e.start_at]
      )
      |> Repo.all()

    events
  end
end
