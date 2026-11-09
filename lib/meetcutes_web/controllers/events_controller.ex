defmodule MeetcutesWeb.EventsController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Events
  alias Meetcutes.Relationships
  alias MeetcutesWeb.EventJSON

  plug MeetcutesWeb.Plugs.SearchRateLimit when action in [:index]

  @default_distance_miles 150.0
  @default_limit 20
  @max_limit 20

  @doc """
  GET /api/v1/events

  Returns published events, optionally limited to a radius around a point and
  an inclusive event-date window. Distances are expressed in miles; the legacy
  `distance`/`searchdistance` parameters are metres and are converted.
  """
  def index(conn, params) do
    with {:ok, opts} <- index_opts(params) do
      user = conn.assigns.current_user
      result = Events.list_nearby_events(Keyword.put(opts, :user, user))
      blocked_ids = Relationships.blocked_ids(user.id)
      counts = Events.gender_counts(Enum.map(result.events, & &1.id))

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: %{
          events:
            Enum.map(
              result.events,
              &EventJSON.event(&1, blocked_ids, Map.get(counts, &1.id, %{}))
            ),
          pagination: result.pagination,
          has_more: result.pagination.has_more,
          next_page: result.pagination.next_page
        }
      })
    else
      {:error, errors} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  @doc """
  GET /api/v1/events/:id
  """
  def show(conn, %{"id" => id}) do
    case Events.get_event(id) do
      nil ->
        MeetcutesWeb.FallbackController.call(conn, {:error, :event_not_found})

      event ->
        user = conn.assigns.current_user
        blocked_ids = Relationships.blocked_ids(user.id)
        counts = Events.gender_counts([event.id]) |> Map.get(event.id, %{})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{event: EventJSON.event(event, blocked_ids, counts)}
        })
    end
  end

  @doc """
  GET /api/v1/events/:event_id/check-fatigue

  Stateless overlap check between the target event's attendee set and the
  requesting user's previous event attendee network.
  """
  def check_fatigue(conn, %{"event_id" => event_id}) do
    user = conn.assigns.current_user

    case Events.get_event(event_id) do
      nil ->
        MeetcutesWeb.FallbackController.call(conn, {:error, :event_not_found})

      _event ->
        conn
        |> put_status(:ok)
        |> json(%{is_fatigued: Events.fatigue_check(event_id, user.id)})
    end
  end

  @doc """
  GET /api/v1/events/created

  Events created by the bearer user.
  """
  def created(conn, params) do
    user = conn.assigns.current_user

    with {:ok, opts} <- pagination_opts(params) do
      result = Events.list_created_events(user, opts)
      blocked_ids = Relationships.blocked_ids(user.id)
      counts = Events.gender_counts(Enum.map(result.events, & &1.id))

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: %{
          events:
            Enum.map(
              result.events,
              &EventJSON.event(&1, blocked_ids, Map.get(counts, &1.id, %{}))
            ),
          pagination: result.pagination,
          has_more: result.pagination.has_more,
          next_page: result.pagination.next_page
        }
      })
    else
      {:error, errors} -> validation_error(conn, errors)
    end
  end

  @doc """
  GET /api/v1/events/joined

  Events the bearer user is attending.
  """
  def joined(conn, params) do
    user = conn.assigns.current_user

    with {:ok, opts} <- pagination_opts(params) do
      result = Events.list_joined_events(user, opts)
      blocked_ids = Relationships.blocked_ids(user.id)
      counts = Events.gender_counts(Enum.map(result.events, & &1.id))

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: %{
          events:
            Enum.map(
              result.events,
              &EventJSON.event(&1, blocked_ids, Map.get(counts, &1.id, %{}))
            ),
          pagination: result.pagination,
          has_more: result.pagination.has_more,
          next_page: result.pagination.next_page
        }
      })
    else
      {:error, errors} -> validation_error(conn, errors)
    end
  end

  @doc """
  POST /api/v1/events

  Creates an event. The creator is always the bearer user, never a
  client-supplied id.
  """
  def create(conn, params) do
    user = conn.assigns.current_user

    case Events.create_event_for_user(user, params) do
      {:ok, event} ->
        blocked_ids = Relationships.blocked_ids(user.id)

        conn
        |> put_status(:created)
        |> json(%{status: "success", data: %{event: EventJSON.event(event, blocked_ids)}})

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc """
  PATCH /api/v1/events/:id

  Updates an owned event and notifies every attendee atomically.
  """
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    case Events.update_event_for_owner(user, id, params) do
      {:ok, event} ->
        blocked_ids = Relationships.blocked_ids(user.id)
        counts = Events.gender_counts([event.id]) |> Map.get(event.id, %{})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{event: EventJSON.event(event, blocked_ids, counts)}
        })

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc """
  DELETE /api/v1/events/:id

  Cancels an owned event, preserves the row for the organizer, clears the
  attendance projection, and notifies every registered attendee.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Events.cancel_event_for_owner(user, id) do
      {:ok, event} ->
        blocked_ids = Relationships.blocked_ids(user.id)
        counts = Events.gender_counts([event.id]) |> Map.get(event.id, %{})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Event canceled",
          data: %{event: EventJSON.event(event, blocked_ids, counts)}
        })

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc """
  POST /api/v1/events/:id/join

  Adds the bearer user to the attendee list. The request body may contain the
  legacy `userhandle`/`attendeesdata` fields, but they are ignored.
  """
  def join(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Events.join_event(id, user) do
      {:ok, event} ->
        broadcast_attendees(event)
        blocked_ids = Relationships.blocked_ids(user.id)
        counts = Events.gender_counts([event.id]) |> Map.get(event.id, %{})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{
            event: EventJSON.event(event, blocked_ids, counts),
            attendee: %{id: user.id, handle: user.nickname, gender: user.gender}
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        registration_failure(conn, "Registration failed", changeset)

      {:error, :age_restricted} ->
        registration_failure(conn, "Registration failed", :age_restricted)

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc """
  DELETE /api/v1/events/:id/join

  Removes the bearer user from the attendee list.
  """
  def leave(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Events.leave_event(id, user) do
      {:ok, event} ->
        broadcast_attendees(event)
        blocked_ids = Relationships.blocked_ids(user.id)
        counts = Events.gender_counts([event.id]) |> Map.get(event.id, %{})

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{
            event: EventJSON.event(event, blocked_ids, counts),
            attendee: %{id: user.id, handle: user.nickname, gender: user.gender}
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        registration_failure(conn, "Unregistration failed", changeset)

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end

  defp registration_failure(conn, prefix, %Ecto.Changeset{} = changeset) do
    errors = changeset_errors(changeset)

    detail =
      errors
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(messages, &"#{field} #{&1}")
      end)
      |> Enum.join("; ")
      |> case do
        "" -> "the server rejected the attendance update"
        message -> message
      end

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      success: false,
      status: "error",
      msg: "#{prefix}: #{detail}",
      message: "#{prefix}: #{detail}",
      errors: errors
    })
  end

  defp registration_failure(conn, prefix, :age_restricted) do
    detail = "You do not match the specific age criteria set by the organizer for this event."

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      success: false,
      status: "error",
      msg: "#{prefix}: #{detail}",
      message: "#{prefix}: #{detail}",
      errors: %{age_restriction: [detail]}
    })
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Pushes attendee changes to anyone watching the event's channel. The socket
  # is a best-effort notification path: the HTTP response already contains the
  # authoritative event, so a broadcast failure must not fail the request.
  defp broadcast_attendees(event) do
    MeetcutesWeb.Endpoint.broadcast("event:#{event.id}", "attendees_updated", %{
      event_id: event.id,
      attendees_count: event.attendees_count
    })
  end

  defp pagination_opts(params) do
    with {:ok, requested_limit} <-
           optional_integer(
             params["page_size"] || params["limit"],
             @default_limit,
             1,
             nil,
             "limit"
           ),
         {:ok, page} <- optional_integer(params["page"], 1, 1, nil, "page"),
         {:ok, requested_offset} <-
           optional_integer(params["offset"], nil, 0, nil, "offset") do
      limit = min(requested_limit, @max_limit)
      offset = requested_offset || (page - 1) * limit

      {:ok, [limit: limit, offset: offset]}
    end
  end

  defp validation_error(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{status: "error", message: "Validation failed", errors: errors})
  end

  defp index_opts(params) do
    with {:ok, lat} <- optional_coordinate(params["lat"], "lat", -90, 90),
         {:ok, lng} <- optional_coordinate(params["lng"], "lng", -180, 180),
         {:ok, distance_miles} <- distance_miles(params),
         {:ok, start_date} <-
           optional_date(params["start_date"] || params["startdate"], "start_date"),
         {:ok, end_date} <- optional_date(params["end_date"] || params["enddate"], "end_date"),
         {:ok, requested_limit} <-
           optional_integer(params["limit"], @default_limit, 1, nil, "limit"),
         {:ok, offset} <- optional_integer(params["offset"], 0, 0, nil, "offset") do
      limit = min(requested_limit, @max_limit)

      if is_number(lat) == is_number(lng) do
        {:ok,
         [
           lat: lat,
           lng: lng,
           distance_miles: distance_miles,
           start_date: start_date,
           end_date: end_date,
           limit: limit,
           offset: offset
         ]}
      else
        {:error, %{location: ["lat and lng must be provided together"]}}
      end
    end
  end

  defp distance_miles(params) do
    cond do
      not is_nil(params["distance_miles"]) ->
        parse_number(params["distance_miles"], "distance_miles", @default_distance_miles)

      not is_nil(params["distance"]) ->
        metres_to_miles(params["distance"], "distance")

      not is_nil(params["searchdistance"]) ->
        metres_to_miles(params["searchdistance"], "searchdistance")

      true ->
        {:ok, @default_distance_miles}
    end
  end

  defp metres_to_miles(value, field) do
    case parse_number(value, field, nil) do
      {:ok, nil} -> {:ok, @default_distance_miles}
      {:ok, metres} when metres > 0 -> {:ok, metres / 1609.344}
      {:ok, _} -> {:error, %{field => ["must be greater than zero"]}}
      error -> error
    end
  end

  defp optional_coordinate(nil, _field, _min, _max), do: {:ok, nil}

  defp optional_coordinate(value, field, min, max) do
    case optional_number(value, field) do
      {:ok, number} when number >= min and number <= max -> {:ok, number}
      {:ok, _number} -> {:error, %{field => ["must be between #{min} and #{max}"]}}
      error -> error
    end
  end

  defp optional_number(nil, _field), do: {:ok, nil}
  defp optional_number(value, _field) when is_number(value), do: {:ok, value}

  defp optional_number(value, field) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> {:error, %{field => ["is invalid"]}}
    end
  end

  defp optional_number(_value, field), do: {:error, %{field => ["is invalid"]}}

  defp parse_number(nil, _field, default), do: {:ok, default}

  defp parse_number(value, field, _default) do
    case optional_number(value, field) do
      {:ok, number} -> {:ok, number}
      error -> error
    end
  end

  defp optional_date(nil, _field), do: {:ok, nil}

  defp optional_date(value, field) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, %{field => ["must be an ISO 8601 date"]}}
    end
  end

  defp optional_date(_value, field), do: {:error, %{field => ["must be an ISO 8601 date"]}}

  defp optional_integer(nil, default, _min, _max, _field), do: {:ok, default}

  defp optional_integer(value, _default, min, max, field) do
    parsed =
      cond do
        is_integer(value) -> value
        is_binary(value) -> Integer.parse(String.trim(value)) |> elem_or_nil()
        true -> nil
      end

    cond do
      is_nil(parsed) -> {:error, %{field => ["is invalid"]}}
      is_integer(min) and parsed < min -> {:error, %{field => ["must be at least #{min}"]}}
      is_integer(max) and parsed > max -> {:error, %{field => ["must be at most #{max}"]}}
      true -> {:ok, parsed}
    end
  end

  defp elem_or_nil({value, ""}), do: value
  defp elem_or_nil(_), do: nil
end
