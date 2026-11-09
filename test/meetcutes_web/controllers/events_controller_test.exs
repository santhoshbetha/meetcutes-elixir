defmodule MeetcutesWeb.EventsControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Ecto.Query

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts

  alias Meetcutes.Events
  alias Meetcutes.Events.Event
  alias Meetcutes.Locations
  alias Meetcutes.Repo

  @austin_lat 30.2672
  @austin_lng -97.7431

  setup %{conn: conn} do
    user =
      user_fixture()
      |> with_identity("event_owner")
      |> with_location(@austin_lat, @austin_lng)

    token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn, user: user, token: token}
  end

  describe "GET /api/v1/events" do
    test "returns nearby published events with attendee data", %{conn: conn, user: user} do
      near = location_fixture()

      far =
        location_fixture(%{
          name: "Dallas Venue",
          street: "1 Main St",
          locality: "Dallas",
          postal_code: "75201",
          latitude: 32.7767,
          longitude: -96.7970
        })

      near_event = event_fixture(user, near, future_datetime(7, 8))
      _far_event = event_fixture(user, far, future_datetime(7, 9))

      {:ok, _joined} = Events.join_event(near_event.id, user)

      conn =
        get(
          conn,
          ~p"/api/v1/events?lat=#{@austin_lat}&lng=#{@austin_lng}&distance_miles=150"
        )

      assert %{"status" => "success", "data" => %{"events" => events, "pagination" => pagination}} =
               json_response(conn, 200)

      assert pagination["total"] == 1
      assert [event] = events
      assert event["id"] == near_event.id
      assert event["event_date"] == Date.to_iso8601(Date.add(Date.utc_today(), 7))
      assert event["male_count"] == 0
      assert event["female_count"] == 1
      assert event["location"]["name"] == near.name
      assert [attendee] = event["attendees"]
      assert attendee["id"] == user.id
      assert attendee["handle"] == user.nickname
      assert attendee["gender"] == "Female"
    end

    test "filters by event date range", %{conn: conn, user: user} do
      location = location_fixture()
      in_range = event_fixture(user, location, future_datetime(7, 8))
      _out_of_range = event_fixture(user, location, future_datetime(20, 8))

      conn =
        get(
          conn,
          ~p"/api/v1/events?startdate=#{Date.to_iso8601(Date.add(Date.utc_today(), 5))}&enddate=#{Date.to_iso8601(Date.add(Date.utc_today(), 10))}"
        )

      assert %{"data" => %{"events" => [event]}} = json_response(conn, 200)
      assert event["id"] == in_range.id
    end

    test "caps discovery page size at 20 and exposes next-page metadata", %{
      conn: conn
    } do
      conn =
        get(
          conn,
          ~p"/api/v1/events?lat=#{@austin_lat}&lng=#{@austin_lng}&limit=100"
        )

      assert %{
               "data" => %{
                 "pagination" => pagination,
                 "has_more" => has_more,
                 "next_page" => next_page
               }
             } = json_response(conn, 200)

      assert pagination["limit"] == 20
      assert is_boolean(has_more)
      assert next_page == nil or next_page == 2
    end

    test "hides events whose gender-specific age bounds exclude the viewer", %{
      conn: conn,
      user: user
    } do
      {:ok, _user} =
        user
        |> Ecto.Changeset.change(age: 22, gender: "Male")
        |> Repo.update()

      location = location_fixture()

      restricted =
        event_fixture(user, location, future_datetime(7, 8), %{
          "has_age_restriction" => true,
          "men_min_age" => 30,
          "men_max_age" => 40,
          "women_min_age" => 21,
          "women_max_age" => 45
        })

      visible = event_fixture(user, location, future_datetime(8, 8))

      conn =
        get(
          conn,
          ~p"/api/v1/events?lat=#{@austin_lat}&lng=#{@austin_lng}&distance_miles=150"
        )

      assert %{"data" => %{"events" => events}} = json_response(conn, 200)
      ids = Enum.map(events, & &1["id"])

      refute restricted.id in ids
      assert visible.id in ids
    end

    test "shows an age-restricted event to a matching viewer", %{
      conn: conn,
      user: user
    } do
      {:ok, _user} =
        user
        |> Ecto.Changeset.change(age: 35, gender: "Male")
        |> Repo.update()

      location = location_fixture()

      restricted =
        event_fixture(user, location, future_datetime(7, 8), %{
          "has_age_restriction" => true,
          "men_min_age" => 30,
          "men_max_age" => 40,
          "women_min_age" => 21,
          "women_max_age" => 45
        })

      conn =
        get(
          conn,
          ~p"/api/v1/events?lat=#{@austin_lat}&lng=#{@austin_lng}&distance_miles=150"
        )

      assert %{"data" => %{"events" => events}} = json_response(conn, 200)
      assert Enum.any?(events, &(&1["id"] == restricted.id))
    end

    test "rejects invalid query parameters", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/events?lat=999&lng=#{@austin_lng}")

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["lat"]
    end
  end

  describe "POST /api/v1/events" do
    test "creates a published event owned by the bearer user", %{conn: conn, user: user} do
      other = user_fixture() |> with_identity("spoofed_owner")

      conn =
        post(conn, ~p"/api/v1/events", %{
          "title" => "Coffee Meetup",
          "location" => "Cafe",
          "address1" => "100 Main St",
          "city" => "Austin",
          "state" => "TX",
          "zip" => "78701",
          "eventlat" => @austin_lat,
          "eventlng" => @austin_lng,
          "eventdate" => Date.to_iso8601(Date.add(Date.utc_today(), 7)),
          "start_time" => "08:00",
          "end_time" => "10:00",
          "description" => "Meet new people",
          "userid" => other.id,
          "creatorid" => other.id
        })

      assert %{"status" => "success", "data" => %{"event" => event}} = json_response(conn, 201)
      assert event["created_by"] == user.id
      assert event["title"] == "Coffee Meetup"
      assert event["status"] == "PUBLISHED"
      assert event["event_date"] == Date.to_iso8601(Date.add(Date.utc_today(), 7))
      assert event["location"]["street"] == "100 Main St"
      assert event["location"]["locality"] == "Austin"
    end

    test "returns conflict when the same location is already booked", %{conn: conn} do
      params = event_params(Date.add(Date.utc_today(), 7), "08:00", "10:00")

      conn = post(conn, ~p"/api/v1/events", params)
      assert json_response(conn, 201)

      conn = post(conn, ~p"/api/v1/events", params)

      assert %{"code" => "conflict"} = json_response(conn, 409)
    end

    test "rejects locations farther than 150 miles", %{conn: conn} do
      params =
        event_params(Date.add(Date.utc_today(), 7), "08:00", "10:00")
        |> Map.merge(%{
          "location" => "Dallas Venue",
          "address1" => "1 Main St",
          "city" => "Dallas",
          "zip" => "75201",
          "eventlat" => 32.7767,
          "eventlng" => -96.7970
        })

      conn = post(conn, ~p"/api/v1/events", params)

      assert %{"code" => "too_far"} = json_response(conn, 422)
    end

    test "rejects an end time before the start time", %{conn: conn} do
      params = event_params(Date.add(Date.utc_today(), 7), "10:00", "09:00")

      conn = post(conn, ~p"/api/v1/events", params)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["end_time"]
    end

    test "requires authentication" do
      conn =
        build_conn()
        |> post(~p"/api/v1/events", event_params(Date.add(Date.utc_today(), 7), "08:00", "10:00"))

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/events/created" do
    test "returns only events created by the bearer user", %{conn: conn, user: user} do
      other = user_fixture() |> with_identity("other_creator")
      location = location_fixture()

      mine = event_fixture(user, location, future_datetime(7, 8))
      _theirs = event_fixture(other, location, future_datetime(8, 8))

      conn = get(conn, ~p"/api/v1/events/created")

      assert %{"data" => %{"events" => [event]}} = json_response(conn, 200)
      assert event["id"] == mine.id
    end

    test "paginates created events in 20-record chunks", %{conn: conn, user: user} do
      location = location_fixture()

      Enum.each(1..21, fn index ->
        event_fixture(user, location, future_datetime(7, 8 + rem(index, 10)))
      end)

      first_page = get(conn, ~p"/api/v1/events/created?limit=100&offset=0")

      assert %{
               "data" => %{
                 "events" => events,
                 "pagination" => pagination,
                 "has_more" => true,
                 "next_page" => 2
               }
             } = json_response(first_page, 200)

      assert length(events) == 20
      assert pagination["limit"] == 20

      second_page = get(conn, ~p"/api/v1/events/created?limit=20&offset=20")

      assert %{
               "data" => %{
                 "events" => events,
                 "pagination" => pagination,
                 "has_more" => false,
                 "next_page" => nil
               }
             } = json_response(second_page, 200)

      assert length(events) == 1
      assert pagination["offset"] == 20
    end
  end

  describe "POST /api/v1/events/:id/join" do
    test "joins as the bearer user and ignores a spoofed userhandle", %{conn: conn, user: user} do
      creator = user_fixture() |> with_identity("creator")
      location = location_fixture()
      event = event_fixture(creator, location, future_datetime(7, 8))

      conn =
        post(conn, ~p"/api/v1/events/#{event.id}/join", %{
          "userhandle" => "someone_else",
          "attendeesdata" => [%{"attendeehandle" => "someone_else"}]
        })

      assert %{
               "status" => "success",
               "data" => %{
                 "event" => returned,
                 "attendee" => %{"id" => attendee_id, "handle" => handle}
               }
             } = json_response(conn, 200)

      assert attendee_id == user.id
      assert handle == user.nickname

      assert [%{"handle" => handle}] = returned["attendees"]
      assert handle == user.nickname

      stored = Events.get_event(event.id)
      assert Map.has_key?(stored.attendees, user.id)
      assert stored.attendees[user.id]["handle"] == user.nickname
    end

    test "returns the joined event in GET /api/v1/events/joined", %{conn: conn} do
      creator = user_fixture() |> with_identity("creator2")
      location = location_fixture()
      event = event_fixture(creator, location, future_datetime(7, 8))

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")
      assert json_response(conn, 200)

      conn = get(conn, ~p"/api/v1/events/joined")

      assert %{"data" => %{"events" => [returned]}} = json_response(conn, 200)
      assert returned["id"] == event.id
    end

    test "rejects joining twice", %{conn: conn, user: user} do
      location = location_fixture()
      event = event_fixture(user, location, future_datetime(7, 8))

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")
      assert json_response(conn, 200)

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")

      assert %{"code" => "already_attending", "message" => message} =
               json_response(conn, 422)

      assert message =~ "already attending"
    end

    test "rejects registration outside the event's gender-specific age range", %{
      conn: conn,
      user: user
    } do
      {:ok, _user} =
        user
        |> Ecto.Changeset.change(age: 41, gender: "Female")
        |> Repo.update()

      creator = user_fixture() |> with_identity("age_creator")
      location = location_fixture()

      event =
        event_fixture(creator, location, future_datetime(7, 8), %{
          "has_age_restriction" => true,
          "men_min_age" => 21,
          "men_max_age" => 35,
          "women_min_age" => 21,
          "women_max_age" => 35
        })

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")

      assert %{
               "success" => false,
               "msg" =>
                 "Registration failed: You do not match the specific age criteria set by the organizer for this event."
             } = json_response(conn, 422)

      refute Map.has_key?(Events.get_event(event.id).attendees || %{}, user.id)
    end

    test "allows registration inside the event's gender-specific age range", %{
      conn: conn,
      user: user
    } do
      {:ok, _user} =
        user
        |> Ecto.Changeset.change(age: 29, gender: "Female")
        |> Repo.update()

      creator = user_fixture() |> with_identity("age_creator_ok")
      location = location_fixture()

      event =
        event_fixture(creator, location, future_datetime(7, 8), %{
          "has_age_restriction" => true,
          "men_min_age" => 21,
          "men_max_age" => 35,
          "women_min_age" => 21,
          "women_max_age" => 35
        })

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")

      assert %{"status" => "success", "data" => %{"attendee" => attendee}} =
               json_response(conn, 200)

      assert attendee["id"] == user.id
    end

    test "joins an event whose start time has already passed", %{
      conn: conn,
      user: user
    } do
      location = location_fixture()
      event = event_fixture(user, location, future_datetime(7, 8))
      past_start = DateTime.add(DateTime.utc_now(), -2, :day)

      Repo.update_all(
        from(e in Event, where: e.id == ^event.id),
        set: [
          start_at: past_start,
          end_at: DateTime.add(past_start, 2, :hour),
          event_date: DateTime.to_date(past_start)
        ]
      )

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")

      assert %{
               "status" => "success",
               "data" => %{"event" => returned, "attendee" => attendee}
             } = json_response(conn, 200)

      assert attendee["id"] == user.id
      assert Enum.any?(returned["attendees"], &(&1["id"] == user.id))
    end
  end

  describe "DELETE /api/v1/events/:id/join" do
    test "leaves the event and clears the joined list", %{conn: conn, user: user} do
      location = location_fixture()
      event = event_fixture(user, location, future_datetime(7, 8))

      conn = post(conn, ~p"/api/v1/events/#{event.id}/join")
      assert json_response(conn, 200)

      conn = delete(conn, ~p"/api/v1/events/#{event.id}/join")

      assert %{"status" => "success", "data" => %{"event" => returned}} =
               json_response(conn, 200)

      assert returned["attendees"] == []

      conn = get(conn, ~p"/api/v1/events/joined")
      assert %{"data" => %{"events" => []}} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/events/:id/check-fatigue" do
    test "returns true when at least half of attendees overlap previous events", %{
      conn: conn,
      user: viewer
    } do
      location = location_fixture()
      past_event = event_fixture(viewer, location, future_datetime(5, 8))
      target_event = event_fixture(viewer, location, future_datetime(7, 8))

      a = user_fixture() |> with_identity("fatigue_a")
      b = user_fixture() |> with_identity("fatigue_b")
      c = user_fixture() |> with_identity("fatigue_c")

      {:ok, _} = Events.join_event(past_event.id, viewer)
      {:ok, _} = Events.join_event(past_event.id, a)
      {:ok, _} = Events.join_event(past_event.id, b)

      {:ok, _} = Events.join_event(target_event.id, a)
      {:ok, _} = Events.join_event(target_event.id, b)
      {:ok, _} = Events.join_event(target_event.id, c)

      conn = get(conn, ~p"/api/v1/events/#{target_event.id}/check-fatigue")

      assert %{"is_fatigued" => true} = json_response(conn, 200)
    end

    test "returns false when fewer than half of attendees overlap", %{
      conn: conn,
      user: viewer
    } do
      location = location_fixture()
      past_event = event_fixture(viewer, location, future_datetime(5, 8))
      target_event = event_fixture(viewer, location, future_datetime(7, 8))

      a = user_fixture() |> with_identity("fatigue_a2")
      c = user_fixture() |> with_identity("fatigue_c2")
      d = user_fixture() |> with_identity("fatigue_d2")

      {:ok, _} = Events.join_event(past_event.id, viewer)
      {:ok, _} = Events.join_event(past_event.id, a)

      {:ok, _} = Events.join_event(target_event.id, a)
      {:ok, _} = Events.join_event(target_event.id, c)
      {:ok, _} = Events.join_event(target_event.id, d)

      conn = get(conn, ~p"/api/v1/events/#{target_event.id}/check-fatigue")

      assert %{"is_fatigued" => false} = json_response(conn, 200)
    end
  end

  describe "PATCH /api/v1/events/:id" do
    test "updates an owned event and broadcasts an attendee notification", %{
      conn: conn,
      user: user
    } do
      location = location_fixture()
      event = event_fixture(user, location, future_datetime(7, 8))
      attendee = user_fixture() |> with_identity("update_attendee")
      {:ok, _} = Events.join_event(event.id, attendee)
      :ok = MeetcutesWeb.Endpoint.subscribe("user_notifications:#{attendee.id}")

      conn =
        patch(
          conn,
          ~p"/api/v1/events/#{event.id}",
          Map.merge(event_params(Date.add(Date.utc_today(), 8), "09:00", "11:00"), %{
            "title" => "Updated Event Title",
            "location" => "Updated Venue",
            "description" => "Updated logistics"
          })
        )

      assert %{"status" => "success", "data" => %{"event" => updated}} =
               json_response(conn, 200)

      assert updated["title"] == "Updated Event Title"
      assert updated["location"]["name"] == "Updated Venue"
      assert updated["event_date"] == Date.to_iso8601(Date.add(Date.utc_today(), 8))

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: topic,
                       event: "new_notification",
                       payload: payload
                     },
                     500

      assert topic == "user_notifications:#{attendee.id}"
      assert payload.type == "upcoming_event"
      assert payload.title == "Event updated: Updated Event Title"
      assert payload.body =~ "updated its logistics"
      assert payload.metadata["event_id"] == event.id

      assert Repo.get_by(Meetcutes.Notifications.Notification,
               user_id: attendee.id,
               type: :upcoming_event
             )
    end

    test "returns 403 for a non-owner and does not mutate the event", %{
      conn: conn,
      user: _actor
    } do
      owner = user_fixture() |> with_identity("event_owner_guard")
      location = location_fixture()
      event = event_fixture(owner, location, future_datetime(7, 8))

      conn =
        patch(
          conn,
          ~p"/api/v1/events/#{event.id}",
          Map.merge(event_params(Date.add(Date.utc_today(), 8), "09:00", "11:00"), %{
            "title" => "Unauthorized Title"
          })
        )

      assert %{"status" => "error", "code" => "forbidden"} =
               json_response(conn, 403)

      assert Events.get_event(event.id).title == event.title
    end

    test "rejects an invalid update window without inserting notifications", %{
      conn: conn,
      user: user
    } do
      location = location_fixture()
      event = event_fixture(user, location, future_datetime(7, 8))
      attendee = user_fixture() |> with_identity("invalid_window_attendee")
      {:ok, _} = Events.join_event(event.id, attendee)

      conn =
        patch(
          conn,
          ~p"/api/v1/events/#{event.id}",
          event_params(Date.add(Date.utc_today(), 8), "10:00", "09:00")
        )

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["end_time"]

      assert Repo.aggregate(
               from(n in Meetcutes.Notifications.Notification,
                 where: n.user_id == ^attendee.id
               ),
               :count,
               :id
             ) == 0

      assert Events.get_event(event.id).title == event.title
    end
  end

  describe "DELETE /api/v1/events/:id" do
    test "cancels an owned event, clears attendance, and alerts every attendee", %{
      conn: conn,
      user: user
    } do
      location = location_fixture()
      event = event_fixture(user, location, future_datetime(7, 8))
      attendee = user_fixture() |> with_identity("cancel_attendee")
      {:ok, _} = Events.join_event(event.id, attendee)
      :ok = MeetcutesWeb.Endpoint.subscribe("user_notifications:#{attendee.id}")

      conn = delete(conn, ~p"/api/v1/events/#{event.id}")

      assert %{
               "status" => "success",
               "message" => "Event canceled",
               "data" => %{"event" => canceled}
             } = json_response(conn, 200)

      assert canceled["status"] == "CANCELLED"
      assert canceled["attendees"] == []

      stored = Events.get_event(event.id)
      assert stored.status == "CANCELLED"
      assert stored.attendees == %{}

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: topic,
                       event: "new_notification",
                       payload: payload
                     },
                     500

      assert topic == "user_notifications:#{attendee.id}"
      assert payload.type == "upcoming_event"
      assert payload.title == "Event canceled: #{event.title}"
      assert payload.body =~ "has been canceled by the organizer"
      assert payload.metadata["event_id"] == event.id

      assert Repo.get_by(Meetcutes.Notifications.Notification,
               user_id: attendee.id,
               type: :upcoming_event
             )
    end

    test "returns 403 for a non-owner and keeps the event published", %{
      conn: conn,
      user: _actor
    } do
      owner = user_fixture() |> with_identity("cancel_owner_guard")
      location = location_fixture()
      event = event_fixture(owner, location, future_datetime(7, 8))

      conn = delete(conn, ~p"/api/v1/events/#{event.id}")

      assert %{"status" => "error", "code" => "forbidden"} =
               json_response(conn, 403)

      assert Events.get_event(event.id).status == "PUBLISHED"
    end
  end

  defp event_params(date, start_time, end_time) do
    %{
      "title" => "Coffee Meetup",
      "location" => "Cafe",
      "address1" => "100 Main St",
      "city" => "Austin",
      "state" => "TX",
      "zip" => "78701",
      "eventlat" => @austin_lat,
      "eventlng" => @austin_lng,
      "eventdate" => Date.to_iso8601(date),
      "start_time" => start_time,
      "end_time" => end_time,
      "description" => "Meet new people"
    }
  end

  defp location_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Venue #{System.unique_integer([:positive])}",
          street: "1 Congress Ave",
          locality: "Austin",
          state: "TX",
          postal_code: "78701",
          latitude: @austin_lat,
          longitude: @austin_lng
        },
        attrs
      )

    {:ok, location} = Locations.create_location(attrs)
    location
  end

  defp event_fixture(user, location, start_at, extra_attrs \\ %{}) do
    end_at = DateTime.add(start_at, 2, :hour)

    attrs =
      Map.merge(
        %{
          "title" => "Test Event",
          "content" => "Test",
          "location_id" => location.id,
          "start_at" => start_at,
          "end_at" => end_at,
          "status" => "PUBLISHED"
        },
        extra_attrs
      )

    {:ok, event} = Events.create_event(attrs, user.id)

    event
  end

  defp future_datetime(days, hour) do
    date = Date.add(Date.utc_today(), days)
    DateTime.new!(date, Time.new!(hour, 0, 0), "Etc/UTC")
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
