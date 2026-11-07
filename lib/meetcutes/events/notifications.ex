defmodule Meetcutes.Events.Notifications do
  @moduledoc """
  Notification service for event lifecycle events.
  Broadcasts notifications via websockets and logs them.
  """
  require Logger

  import Ecto.Query, warn: false

  alias Meetcutes.Events.Event
  alias MeetcutesWeb.Endpoint
  alias Meetcutes.Repo
  alias Meetcutes.Accounts.User

  @doc """
  Notify event creator when a user joins their event.
  """
  def notify_user_joined_event(%Event{} = event, %User{} = joining_user) do
    notification = %{
      type: "user_joined_event",
      event_id: event.id,
      event_title: event.title,
      joining_user_id: joining_user.id,
      joining_user_name: "#{joining_user.first_name} #{joining_user.last_name}",
      joining_user_nickname: joining_user.nickname,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to event creator only
    broadcast_user(event.created_by, "user_joined_event", notification)

    log_notification(notification)
    :ok
  end

  @doc """
  Notify when an event is created.
  """
  def notify_event_created(%Event{} = event) do
    notification = %{
      type: "event_created",
      event_id: event.id,
      title: event.title,
      start_at: format_datetime(event.start_at),
      location: event.location,
      created_by: event.created_by,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to users within 25 miles of the event
    broadcast_to_local_users(event, "event_created", notification)

    log_notification(notification)
    :ok
  end

  @doc """
  Notify when an event is updated.
  """
  def notify_event_updated(%Event{} = event) do
    notification = %{
      type: "event_updated",
      event_id: event.id,
      title: event.title,
      internal_notes_updated: not is_nil(event.internal_notes),
      timestamp: DateTime.utc_now()
    }

    # Broadcast to users registered for this event
    broadcast_to_registered_users(event.id, "event_updated", notification)

    log_notification(notification)
    :ok
  end

  @doc """
  Notify when an event is published.
  """
  def notify_event_published(%Event{} = event) do
    notification = %{
      type: "event_published",
      event_id: event.id,
      title: event.title,
      start_at: format_datetime(event.start_at),
      location: event.location,
      is_upcoming: Event.is_upcoming?(event),
      timestamp: DateTime.utc_now()
    }

    # Broadcast to users within 25 miles of the event
    broadcast_to_local_users(event, "event_published", notification)

    log_notification(notification)
    :ok
  end

  @doc """
  Notify when an event is cancelled.
  """
  def notify_event_cancelled(%Event{} = event) do
    notification = %{
      type: "event_cancelled",
      event_id: event.id,
      title: event.title,
      scheduled_for: format_datetime(event.start_at),
      location: event.location,
      reason: event.internal_notes,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to users registered for this event
    broadcast_to_registered_users(event.id, "event_cancelled", notification)

    log_notification(notification)
    :ok
  end

  @doc """
  Notify when an event is re-published (from CANCELLED to PUBLISHED).
  """
  def notify_event_republished(%Event{} = event) do
    notification = %{
      type: "event_republished",
      event_id: event.id,
      title: event.title,
      start_at: format_datetime(event.start_at),
      location: event.location,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to users registered for this event
    broadcast_to_registered_users(event.id, "event_republished", notification)

    log_notification(notification)
    :ok
  end

  # Broadcast to users within 25 miles of the event location
  defp broadcast_to_local_users(%Event{} = event, event_type, notification) do
    # Only broadcast if event has location data
    if event.location && event.location.latitude && event.location.longitude do
      event_lat = event.location.latitude
      event_lon = event.location.longitude

      # Get users with location data
      local_user_ids = get_users_within_distance(event_lat, event_lon, 25)

      # Broadcast to each local user
      Enum.each(local_user_ids, fn user_id ->
        broadcast_user(user_id, event_type, notification)
      end)
    end
  end

  # Broadcast to users registered for a specific event
  defp broadcast_to_registered_users(event_id, event_type, notification) do
    # Get all users registered for this event
    # This is a simplified approach - in production, you might want to
    # store registered users in a more efficient way (e.g., Redis, database table)
    registered_user_ids = get_registered_user_ids_for_event(event_id)

    Enum.each(registered_user_ids, fn user_id ->
      broadcast_user(user_id, event_type, notification)
    end)
  end

  # Get user IDs registered for an event
  defp get_registered_user_ids_for_event(event_id) do
    # Query users who have this event_id in their registered_events array
    # registered_events is array of maps, check if any map has event_id
    Repo.all(
      from u in User,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM json_array_elements(?) AS elem WHERE elem->>'event_id' = ?)",
            u.registered_events,
            ^event_id
          ),
        select: u.id
    )
  end

  # Get user IDs of users within the specified distance (in miles) of the given coordinates
  defp get_users_within_distance(_lat, _lon, _distance_miles) do
    []
  end

  defp broadcast_user(user_id, event_type, notification) do
    Endpoint.broadcast("notifications:#{user_id}", event_type, notification)
    Endpoint.broadcast("user_notifications:#{user_id}", event_type, notification)
  end

  defp log_notification(notification) do
    Logger.info("""
    [NOTIFICATION] #{String.upcase(notification.type)}:
    - Event ID: #{notification[:event_id] || "N/A"}
    - Title: #{notification[:title] || "N/A"}
    - Details: #{inspect(notification, pretty: true)}
    """)
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    DateTime.to_iso8601(datetime)
  end
end
