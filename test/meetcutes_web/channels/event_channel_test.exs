defmodule MeetcutesWeb.EventChannelTest do
  use MeetcutesWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Events
  alias Meetcutes.Locations

  @austin_lat 30.2672
  @austin_lng -97.7431

  setup do
    creator =
      user_fixture()
      |> with_identity("channel_creator")
      |> with_location(@austin_lat, @austin_lng)

    attendee =
      user_fixture()
      |> with_identity("channel_attendee")
      |> with_location(@austin_lat, @austin_lng)

    {:ok, location} =
      Locations.create_location(%{
        name: "Channel Venue #{System.unique_integer([:positive])}",
        street: "1 Congress Ave",
        locality: "Austin",
        state: "TX",
        postal_code: "78701",
        latitude: @austin_lat,
        longitude: @austin_lng
      })

    start_at =
      DateTime.new!(
        Date.add(Date.utc_today(), 7),
        Time.new!(8, 0, 0),
        "Etc/UTC"
      )

    {:ok, event} =
      Events.create_event(
        %{
          "title" => "Channel Test Event",
          "content" => "Live updates",
          "location_id" => location.id,
          "start_at" => start_at,
          "end_at" => DateTime.add(start_at, 2, :hour),
          "status" => "PUBLISHED"
        },
        creator.id
      )

    %{conn: build_conn(), creator: creator, attendee: attendee, event: event}
  end

  describe "UserSocket.connect/3" do
    test "authenticates with a bearer session token", %{creator: creator} do
      token = Accounts.generate_user_session_token(creator)

      assert {:ok, socket} =
               Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{"token" => token})

      assert socket.assigns.current_user_id == creator.id
    end

    test "rejects an invalid token" do
      assert :error =
               Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{
                 "token" => "not-a-real-token"
               })
    end
  end

  describe "event channel" do
    test "joins an existing event", %{creator: creator, event: event} do
      token = Accounts.generate_user_session_token(creator)
      {:ok, socket} = Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{"token" => token})

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MeetcutesWeb.EventChannel, "event:#{event.id}")
    end

    test "rejects an unknown event", %{creator: creator} do
      token = Accounts.generate_user_session_token(creator)
      {:ok, socket} = Phoenix.ChannelTest.connect(MeetcutesWeb.UserSocket, %{"token" => token})

      assert {:error, %{reason: "event_not_found"}} =
               subscribe_and_join(socket, MeetcutesWeb.EventChannel, "event:does-not-exist")
    end

    test "broadcasts attendees_updated when someone joins over HTTP", %{
      conn: conn,
      attendee: attendee,
      event: event
    } do
      MeetcutesWeb.Endpoint.subscribe("event:#{event.id}")

      token = Accounts.generate_user_session_token(attendee)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v1/events/#{event.id}/join")

      assert %{"status" => "success"} = json_response(conn, 200)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: topic,
        event: "attendees_updated",
        payload: %{event_id: event_id, attendees_count: 1}
      }

      assert topic == "event:#{event.id}"
      assert event_id == event.id
    end

    test "broadcasts attendees_updated when someone leaves over HTTP", %{
      conn: conn,
      attendee: attendee,
      event: event
    } do
      {:ok, _event} = Events.join_event(event.id, attendee)
      MeetcutesWeb.Endpoint.subscribe("event:#{event.id}")

      token = Accounts.generate_user_session_token(attendee)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/v1/events/#{event.id}/join")

      assert %{"status" => "success"} = json_response(conn, 200)

      assert_receive %Phoenix.Socket.Broadcast{
        event: "attendees_updated",
        payload: %{event_id: event_id, attendees_count: 0}
      }

      assert event_id == event.id
    end
  end

  defp with_identity(user, nickname) do
    {:ok, user} =
      Accounts.update_user(user, %{nickname: nickname, gender: "Female", first_name: "Test"})

    user
  end

  defp with_location(user, lat, lng) do
    {:ok, user} = Accounts.update_user(user, %{geohash: Geohash.encode(lat, lng, 9)})
    user
  end
end
