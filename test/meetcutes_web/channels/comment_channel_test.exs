defmodule MeetcutesWeb.CommentChannelTest do
  use MeetcutesWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Events
  alias Meetcutes.Locations

  @austin_lat 30.2672
  @austin_lng -97.7431

  setup do
    user =
      user_fixture()
      |> with_identity("comment_channel_user")

    {:ok, location} =
      Locations.create_location(%{
        name: "Comment Channel Venue #{System.unique_integer([:positive])}",
        street: "1 Congress Ave",
        locality: "Austin",
        state: "TX",
        postal_code: "78701",
        latitude: @austin_lat,
        longitude: @austin_lng
      })

    start_at = DateTime.add(DateTime.utc_now(:second), 7, :day)

    {:ok, event} =
      Events.create_event(
        %{
          "title" => "Comment Channel Event",
          "content" => "Real-time discussion",
          "location_id" => location.id,
          "start_at" => start_at,
          "end_at" => DateTime.add(start_at, 2, :hour),
          "status" => "PUBLISHED"
        },
        user.id
      )

    token = Accounts.generate_user_session_token(user)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{"token" => token})

    %{event: event, socket: socket}
  end

  test "joins the events:discussion topic", %{event: event, socket: socket} do
    assert {:ok, _reply, _socket} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.CommentChannel,
               "events:discussion:#{event.id}"
             )
  end

  test "rejects an unknown event", %{socket: socket} do
    assert {:error, %{reason: "event_not_found"}} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.CommentChannel,
               "events:discussion:does-not-exist"
             )
  end

  test "receives new_comment broadcasts on the discussion topic", %{
    event: event,
    socket: socket
  } do
    assert {:ok, _reply, _socket} =
             subscribe_and_join(
               socket,
               MeetcutesWeb.CommentChannel,
               "events:discussion:#{event.id}"
             )

    payload = %{
      comment: %{
        id: "comment-channel-test",
        content: "Hello from the channel",
        event_id: event.id
      }
    }

    MeetcutesWeb.Endpoint.broadcast(
      "events:discussion:#{event.id}",
      "new_comment",
      payload
    )

    assert_push("new_comment", ^payload)
  end

  defp with_identity(user, nickname) do
    {:ok, user} =
      Accounts.update_user(user, %{
        nickname: nickname,
        gender: "Female",
        first_name: "Test"
      })

    user
  end
end
