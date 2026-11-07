defmodule MeetcutesWeb.NotificationChannel do
  use MeetcutesWeb, :channel

  alias Meetcutes.Accounts

  @impl true
  def join("notifications:" <> user_id, _payload, socket) do
    # The topic id must match the authenticated bearer user. User ids are
    # ULIDs, so compare strings instead of converting to an integer.
    if socket.assigns.current_user_id == user_id do
      case Accounts.get_user(user_id) do
        nil ->
          {:error, %{reason: "user_not_found"}}

        user ->
          Logger.metadata(user_id: user.id)
          # Store registered event IDs in socket assigns for easy access.
          registered_event_ids = get_registered_event_ids(user.registered_events || [])
          socket = assign(socket, :registered_event_ids, registered_event_ids)

          {:ok, socket}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @impl true
  def handle_in("subscribe_to_events", _payload, socket) do
    # User is already subscribed to their registered events via the topic.
    # This is just an acknowledgment.
    {:reply, {:ok, %{message: "Subscribed to notifications for your registered events"}}, socket}
  end

  # Helper function to extract event IDs from registered events. Legacy rows
  # stored ids as integers while current events use ULIDs, so both are kept.
  defp get_registered_event_ids(registered_events) when is_list(registered_events) do
    Enum.map(registered_events, fn
      %{"event_id" => event_id} -> event_id
      %{"id" => event_id} -> event_id
      event_id -> event_id
    end)
  end

  defp get_registered_event_ids(_), do: []
end
