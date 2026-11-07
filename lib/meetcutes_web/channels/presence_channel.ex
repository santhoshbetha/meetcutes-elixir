defmodule MeetcutesWeb.PresenceChannel do
  use MeetcutesWeb, :channel

  alias MeetcutesWeb.Presence

  @impl true
  def join(topic, _payload, socket) when topic in ["online_users", "presence"] do
    Logger.metadata(user_id: socket.assigns.current_user_id)
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    user = socket.assigns.current_user

    {:ok, _ref} =
      Presence.track(socket, user.id, %{
        user_id: user.id,
        handle: user.nickname,
        online_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff},
        socket
      ) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end
end
