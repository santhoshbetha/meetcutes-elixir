defmodule MeetcutesWeb.PresenceChannelTest do
  use MeetcutesWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias MeetcutesWeb.Presence

  setup do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{"token" => token})

    %{user: user, socket: socket}
  end

  test "tracks an authenticated user under online_users", %{
    user: user,
    socket: socket
  } do
    assert {:ok, _reply, _channel} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.PresenceChannel,
               "online_users"
             )

    assert_push("presence_state", state)
    assert Map.has_key?(state, user.id)
    assert Map.has_key?(Presence.list("online_users"), user.id)
  end
end
