defmodule MeetcutesWeb.UserNotificationsChannel do
  use MeetcutesWeb, :channel

  alias Meetcutes.Accounts

  @impl true
  def join("user_notifications:" <> user_id, _payload, socket) do
    # The topic id must match the authenticated bearer user. User ids are
    # ULIDs, so compare strings instead of converting to an integer.
    if socket.assigns.current_user_id == user_id do
      case Accounts.get_user(user_id) do
        nil ->
          {:error, %{reason: "user_not_found"}}

        _user ->
          Logger.metadata(user_id: user_id)
          {:ok, assign(socket, :notification_user_id, user_id)}
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
  def handle_in("subscribe", _payload, socket) do
    {:reply, {:ok, %{subscribed: true}}, socket}
  end
end
