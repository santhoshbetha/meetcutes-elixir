defmodule MeetcutesWeb.UserSocket do
  use Phoenix.Socket

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics
  # from `handle_in/3` callbacks.
  #
  # ## Examples
  #
  #     def connect(_params, socket, _connect_info) do
  #       {:ok, socket}
  #     end
  #
  #     def id(_socket), do: nil
  #
  # To accept connections with parameters, add the `connect/3` function.
  # For example, to authenticate a user:
  #
  #     def connect(%{"token" => token}, socket, _connect_info) do
  #       case authenticate_user(token) do
  #         {:ok, user} ->
  #           socket = assign(socket, :user, user)
  #           {:ok, socket}
  #         {:error, _reason} -> :error
  #       end
  #     end
  #
  # It is also possible to have the connect/3 function return an {:error, reason}
  # tuple. This will be returned to the client and the connection will be denied.

  ## Channels
  channel("notifications:*", MeetcutesWeb.NotificationChannel)
  channel("user_notifications:*", MeetcutesWeb.UserNotificationsChannel)
  channel("event:*", MeetcutesWeb.EventChannel)
  channel("events:discussion:*", MeetcutesWeb.CommentChannel)
  channel("online_users", MeetcutesWeb.PresenceChannel)
  channel("presence", MeetcutesWeb.PresenceChannel)
  channel("job_updates:*", MeetcutesWeb.JobUpdateChannel)
  channel("comments:*", MeetcutesWeb.CommentChannel)

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     MeetcutesWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  def id(socket), do: "user_socket:#{socket.assigns.current_user_id}"

  def connect(%{"token" => token}, socket, _connect_info) do
    case Meetcutes.Accounts.get_user_by_session_token(token) do
      {%Meetcutes.Accounts.User{} = user, _inserted_at} ->
        Meetcutes.Accounts.touch_last_seen(user)

        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_user_id, user.id)

        {:ok, socket}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error
end
