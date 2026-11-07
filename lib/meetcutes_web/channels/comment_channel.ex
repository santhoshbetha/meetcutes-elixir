defmodule MeetcutesWeb.CommentChannel do
  use MeetcutesWeb, :channel

  alias Meetcutes.Events
  alias MeetcutesWeb.Presence

  @impl true
  def join("comments:" <> event_id, payload, socket) do
    join_event(event_id, payload, socket)
  end

  @impl true
  def join("events:discussion:" <> event_id, payload, socket) do
    join_event(event_id, payload, socket)
  end

  defp join_event(event_id, _payload, socket) do
    # Verify that the event exists
    case Events.get_event(event_id) do
      nil ->
        {:error, %{reason: "event_not_found"}}

      _event ->
        Logger.metadata(user_id: socket.assigns.current_user_id)
        # Track user presence
        send(self(), :after_join)
        {:ok, assign(socket, :event_id, event_id)}
    end
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  # Handle presence tracking after join
  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.current_user_id

    # Track user presence in this event's comment channel
    {:ok, _} =
      Presence.track(socket, user_id, %{
        online_at: inspect(System.system_time(:second)),
        user_id: user_id
      })

    # Push the current presence state to the client
    push(socket, "presence_state", Presence.list(socket))

    {:noreply, socket}
  end

  # Handle presence diff updates
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  # Optional: Handle new comment from client (if allowing direct posting)
  # But since we have the controller, maybe not needed
end
