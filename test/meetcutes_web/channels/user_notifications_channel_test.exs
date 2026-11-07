defmodule MeetcutesWeb.UserNotificationsChannelTest do
  use MeetcutesWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts

  setup do
    user = user_fixture()
    other_user = user_fixture()

    token = Accounts.generate_user_session_token(user)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{"token" => token})

    %{user: user, other_user: other_user, socket: socket}
  end

  test "joins the authenticated user's personal topic", %{
    user: user,
    socket: socket
  } do
    assert {:ok, _reply, _socket} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.UserNotificationsChannel,
               "user_notifications:#{user.id}"
             )
  end

  test "rejects a topic owned by another user", %{
    other_user: other_user,
    socket: socket
  } do
    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.UserNotificationsChannel,
               "user_notifications:#{other_user.id}"
             )
  end

  test "receives event_created pushes on the personal topic", %{
    user: user,
    socket: socket
  } do
    assert {:ok, _reply, _socket} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.UserNotificationsChannel,
               "user_notifications:#{user.id}"
             )

    payload = %{
      type: "event_created",
      event_id: "evt-channel-test",
      title: "Channel Test Event"
    }

    MeetcutesWeb.Endpoint.broadcast(
      "user_notifications:#{user.id}",
      "event_created",
      payload
    )

    assert_push("event_created", ^payload)
  end
end
