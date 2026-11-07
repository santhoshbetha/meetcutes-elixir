defmodule MeetcutesWeb.EventController do
  use MeetcutesWeb, :controller

  plug MeetcutesWeb.Plugs.SearchRateLimit when action in [:search]
  alias MeetcutesWeb.CalendarExporter

  alias Meetcutes.Events
  alias Meetcutes.Events.Event
  alias Meetcutes.Events.Notifications
  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias MeetcutesWeb.EventJSON

  plug :authenticate
       when action in [
              :index,
              :create,
              :update,
              :joined_events,
              :created_events,
              :join,
              :leave,
              :search,
              :delete_old_events
            ]

  # GET "/events"
  def index(conn, params) do
    case Events.list_events(params) do
      %{events: events, pagination: pagination} ->
        conn
        |> put_status(:ok)
        |> json(EventJSON.index(%{events: events, pagination: pagination}))
    end
  end

  # POST "/search/events"
  def search(conn, params) do
    # Parse and validate parameters
    start_date = Map.get(params, "start_date")
    geohash = Map.get(params, "geohash") || current_user_geohash(conn)
    distance_miles = parse_float_param(params, "distance_miles")

    # Validate required parameters for distance search
    cond do
      distance_miles && !geohash ->
        conn
        |> put_status(:bad_request)
        |> json(
          MeetcutesWeb.ErrorJSON.bad_request(%{
            message: "geohash is required when using distance_miles"
          })
        )

      true ->
        # Build search options
        search_opts = []

        search_opts =
          if start_date, do: Keyword.put(search_opts, :start_date, start_date), else: search_opts

        search_opts =
          if geohash, do: Keyword.put(search_opts, :geohash, geohash), else: search_opts

        search_opts =
          if distance_miles,
            do: Keyword.put(search_opts, :distance_miles, distance_miles),
            else: search_opts

        search_opts =
          Keyword.put(
            search_opts,
            :user,
            conn.assigns[:current_user] || conn.assigns[:user]
          )

        events = Events.search_events(search_opts)

        conn
        |> put_status(:ok)
        |> json(EventJSON.index(%{events: events, pagination: %{total_count: length(events)}}))
    end
  end

  defp current_user_geohash(conn) do
    case conn.assigns[:user] do
      %User{geohash: geohash} when is_binary(geohash) and geohash != "" -> geohash
      _ -> nil
    end
  end

  # GET "/events/joined_events"
  def joined_events(%{assigns: %{user: %User{} = user}} = conn, _params) do
    # Extract event IDs from user's registered_events
    event_ids = extract_event_ids(user.registered_events || [])

    # Fetch events by IDs
    events = Events.get_events_by_ids(event_ids)

    # Filter out past events and return only future/upcoming events
    future_events = Enum.filter(events, &Event.is_upcoming?/1)

    conn
    |> put_status(:ok)
    |> json(
      EventJSON.index(%{events: future_events, pagination: %{total_count: length(future_events)}})
    )
  end

  # GET "/events/created_events"
  def created_events(%{assigns: %{user: %User{} = user}} = conn, _params) do
    # Extract event IDs from user's created_events
    event_ids = extract_event_ids(user.created_events || [])

    # Fetch events by IDs
    events = Events.get_events_by_ids(event_ids)

    # Return all created events (both past and future)
    conn
    |> put_status(:ok)
    |> json(EventJSON.index(%{events: events, pagination: %{total_count: length(events)}}))
  end

  # POST "/events"
  def create(%{assigns: %{user: %User{} = user}} = conn, %{"event" => event_params}) do
    # Map API field names to schema field names
    mapped_params = map_event_params(event_params)

    # Dejar que el fallback controller maneje los errores
    with {:ok, %Event{} = event} <- Events.create_event(mapped_params, user.id) do
      # Update user's created_events array
      updated_created_events =
        (user.created_events || []) ++
          [
            %{
              "event_id" => event.id,
              "event_date" => event.event_date
            }
          ]

      Accounts.update_user(user, %{created_events: updated_created_events})

      conn
      |> put_status(:created)
      |> json(EventJSON.show(%{event: event}))
    end
  end

  # GET "/events/:id"
  def show(conn, %{"id" => id}) do
    event = Events.get_event!(id)

    conn
    |> put_status(:ok)
    |> json(EventJSON.show(%{event: event}))
  end

  # PUT "/events/:id"
  def update(conn, %{"id" => id, "event" => event_params}) do
    event = Events.get_event!(id)

    # Map API field names to schema field names
    mapped_params = map_event_params(event_params)

    with {:ok, %Event{} = event} <- Events.update_event(event, mapped_params) do
      conn
      |> put_status(:ok)
      |> json(EventJSON.show(%{event: event}))
    end
  end

  # POST "/events/:id/join"
  def join(%{assigns: %{user: %User{} = user}} = conn, %{"id" => event_id}) do
    case Events.get_event(event_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(MeetcutesWeb.ErrorJSON.not_found())

      event ->
        # Check if user is already registered
        already_registered =
          Enum.any?(user.registered_events || [], fn event_map ->
            (event_map["event_id"] || event_map["id"]) == event_id
          end)

        if already_registered do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: %{code: "ALREADY_REGISTERED", message: "Already registered for this event"}
          })
        else
          # Add event to user's registered_events
          updated_registered_events =
            (user.registered_events || []) ++
              [
                %{
                  "event_id" => event.id,
                  "event_date" => event.event_date
                }
              ]

          case Accounts.update_user(user, %{registered_events: updated_registered_events}) do
            {:ok, _updated_user} ->
              # Notify event creator if someone else joined
              if event.created_by != user.id do
                Notifications.notify_user_joined_event(event, user)
              end

              conn
              |> put_status(:ok)
              |> json(%{message: "Successfully joined the event"})

            {:error, _changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(MeetcutesWeb.ErrorJSON.unprocessable_entity())
          end
        end
    end
  end

  # POST "/events/:id/leave"
  def leave(%{assigns: %{user: %User{} = user}} = conn, %{"id" => event_id}) do
    # Remove event from user's registered_events
    updated_registered_events =
      Enum.reject(user.registered_events || [], fn event_map ->
        (event_map["event_id"] || event_map["id"]) == event_id
      end)

    case Accounts.update_user(user, %{registered_events: updated_registered_events}) do
      {:ok, _updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Successfully left the event"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(MeetcutesWeb.ErrorJSON.unprocessable_entity())
    end
  end

  # POST "/events/:id/cancel"
  def cancel(%{assigns: %{user: %User{} = user}} = conn, %{"id" => event_id}) do
    case Events.get_event(event_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(MeetcutesWeb.ErrorJSON.not_found())

      event ->
        # Check if the user is the creator of the event
        if event.created_by == user.id do
          case Events.cancel_event(event) do
            {:ok, cancelled_event} ->
              conn
              |> put_status(:ok)
              |> json(EventJSON.show(%{event: cancelled_event}))

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(MeetcutesWeb.ErrorJSON.error(%{changeset: changeset}))
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(MeetcutesWeb.ErrorJSON.forbidden())
        end
    end
  end

  # DELETE "/events/:id"
  def delete(conn, %{"id" => id}) do
    event = Events.get_event!(id)

    with {:ok, %Event{}} <- Events.delete_event(event) do
      send_resp(conn, :no_content, "")
    end
  end

  # DELETE "/events/cleanup/old"
  def delete_old_events(conn, _params) do
    case Events.delete_old_events() do
      {:ok, count} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Successfully deleted #{count} old events"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(
          MeetcutesWeb.ErrorJSON.unprocessable_entity(%{
            message: "Failed to delete old events: #{inspect(reason)}"
          })
        )
    end
  end

  defp authenticate(conn, _opts) do
    token = get_req_header(conn, "authorization") |> List.first()

    case token do
      "Bearer " <> provided_token ->
        static_token =
          Application.get_env(:event_api, :static_auth_token, "admin-token-123")

        if provided_token == static_token do
          conn
        else
          conn
          |> put_status(:unauthorized)
          |> json(MeetcutesWeb.ErrorJSON.unauthorized())
          |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(MeetcutesWeb.ErrorJSON.unauthorized())
        |> halt()
    end
  end

  # Helper function to map API field names to schema field names
  defp map_event_params(params) do
    params
    |> Enum.map(fn
      {"name", value} -> {"title", value}
      {"start_time", value} -> {"start_at", value}
      {"end_time", value} -> {"end_at", value}
      {key, value} -> {key, value}
    end)
    |> Map.new()
  end

  # Helper function for parameter parsing
  defp parse_float_param(params, key) do
    case Map.get(params, key) do
      nil ->
        nil

      value when is_binary(value) ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> nil
        end

      value when is_number(value) ->
        value

      _ ->
        nil
    end
  end

  # Helper function to extract event IDs from event arrays (registered_events, created_events)
  defp extract_event_ids(registered_events) do
    Enum.map(registered_events, fn event_map ->
      # Assume each map has an "event_id" key
      event_map["event_id"] || event_map["id"]
    end)
    |> Enum.reject(&is_nil/1)
  end

  def download(conn, %{"id" => id}) do
    event = Meetcutes.Events.get_event!(id)
    ics_data = CalendarExporter.to_ics([event])

    conn
    |> put_resp_content_type("text/calendar")
    |> put_resp_header("content-disposition", "attachment; filename=\"event.ics\"")
    |> send_resp(200, ics_data)
  end
end
