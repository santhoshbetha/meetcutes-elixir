defmodule MeetcutesWeb.RelationshipsControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Ecto.Query
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Notifications.Notification
  alias Meetcutes.Relationships
  alias Meetcutes.Repo

  setup %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn, user: user, token: token}
  end

  describe "POST /api/v1/relationships" do
    test "creates a like for the bearer user", %{conn: conn} do
      target = user_fixture()

      conn =
        post(conn, ~p"/api/v1/relationships", %{
          "kind" => "like",
          "target_id" => target.id,
          "actor_id" => target.id
        })

      assert %{
               "status" => "success",
               "data" => %{
                 "relationship" => %{"kind" => "like", "target_id" => target_id},
                 "relationships" => %{"likes" => likes}
               }
             } = json_response(conn, 201)

      assert target_id == target.id
      assert likes == [target.id]
    end

    test "creates a profile_like notification and broadcasts it to the target", %{
      conn: conn,
      user: user
    } do
      user =
        user
        |> Ecto.Changeset.change(nickname: "notifier_actor")
        |> Repo.update!()

      target = user_fixture(%{first_name: "Notified"})
      :ok = MeetcutesWeb.Endpoint.subscribe("user_notifications:#{target.id}")

      conn =
        post(conn, ~p"/api/v1/relationships", %{
          "kind" => "like",
          "target_id" => target.id
        })

      assert %{"status" => "success"} = json_response(conn, 201)

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: topic,
                       event: "new_notification",
                       payload: payload
                     },
                     500

      assert topic == "user_notifications:#{target.id}"
      assert payload.type == "profile_like"
      assert payload.title == "Someone liked your profile"
      assert payload.metadata["sender_id"] == user.id
      assert payload.metadata["sender_handle"] == "notifier_actor"
    end

    test "does not duplicate the like notification on a repeated request", %{conn: conn} do
      target = user_fixture()

      for _attempt <- 1..2 do
        conn =
          post(conn, ~p"/api/v1/relationships", %{
            "kind" => "like",
            "target_id" => target.id
          })

        assert %{"status" => "success"} = json_response(conn, 201)
      end

      assert Repo.aggregate(
               from(n in Notification,
                 where: n.user_id == ^target.id and n.type == :profile_like
               ),
               :count,
               :id
             ) == 1
    end

    test "creates a block and removes mutual likes", %{conn: conn, user: user} do
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "like")
      assert {:ok, _} = Relationships.create_relationship(target.id, user.id, "like")

      conn =
        post(conn, ~p"/api/v1/relationships", %{"kind" => "block", "target_id" => target.id})

      assert %{"data" => %{"relationships" => summary}} = json_response(conn, 201)
      assert summary["likes"] == []
      assert summary["matches"] == []
      assert summary["blocks"] == [target.id]
      assert Relationships.summary(target.id).likes == []
    end

    test "rejects self relationships", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/v1/relationships", %{"kind" => "like", "target_id" => user.id})

      assert %{"status" => "error", "errors" => %{"relationship" => errors}} =
               json_response(conn, 422)

      assert errors == ["cannot target yourself"]
    end

    test "rejects an unknown target", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/relationships", %{
          "kind" => "like",
          "target_id" => Ecto.ULID.generate()
        })

      assert %{"status" => "error"} = json_response(conn, 404)
    end

    test "rejects an invalid kind", %{conn: conn} do
      target = user_fixture()

      conn =
        post(conn, ~p"/api/v1/relationships", %{"kind" => "follow", "target_id" => target.id})

      assert %{"status" => "error", "errors" => %{"relationship" => errors}} =
               json_response(conn, 422)

      assert errors == ["must be one of like, block, or mute"]
    end

    test "requires authentication" do
      conn =
        build_conn()
        |> post(~p"/api/v1/relationships", %{
          "kind" => "like",
          "target_id" => Ecto.ULID.generate()
        })

      assert %{"status" => "error"} = json_response(conn, 401)
    end
  end

  describe "DELETE /api/v1/relationships/:kind/:target_id" do
    test "removes the relationship", %{conn: conn, user: user} do
      target = user_fixture()
      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "mute")

      conn = delete(conn, ~p"/api/v1/relationships/mute/#{target.id}")

      assert %{"data" => %{"relationships" => summary}} = json_response(conn, 200)
      assert summary["mutes"] == []
      refute Relationships.hidden?(user.id, target.id)
    end
  end

  describe "GET /api/v1/relationships" do
    test "returns the relationship summary", %{conn: conn, user: user} do
      target = user_fixture()
      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "like")
      assert {:ok, _} = Relationships.create_relationship(target.id, user.id, "like")

      conn = get(conn, ~p"/api/v1/relationships")

      assert %{"data" => %{"relationships" => summary}} = json_response(conn, 200)
      assert summary["likes"] == [target.id]
      assert summary["matches"] == [target.id]
    end
  end

  describe "GET /api/v1/relationships/blocked and /muted" do
    test "returns the blocked users with public profile data", %{conn: conn, user: user} do
      target = user_fixture(%{first_name: "Blocked", last_name: "Person"})

      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "block")

      conn = get(conn, ~p"/api/v1/relationships/blocked")

      assert %{
               "data" => %{
                 "kind" => "blocked",
                 "users" => [user_data]
               }
             } = json_response(conn, 200)

      assert user_data["id"] == target.id
      assert user_data["first_name"] == "Blocked"
    end

    test "returns the muted users with public profile data", %{conn: conn, user: user} do
      target = user_fixture(%{first_name: "Muted", last_name: "Person"})

      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "mute")

      conn = get(conn, ~p"/api/v1/relationships/muted")

      assert %{
               "data" => %{
                 "kind" => "muted",
                 "users" => [user_data]
               }
             } = json_response(conn, 200)

      assert user_data["id"] == target.id
      assert user_data["first_name"] == "Muted"
    end

    test "does not mix blocked and muted users", %{conn: conn, user: user} do
      blocked = user_fixture()
      muted = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(user.id, blocked.id, "block")
      assert {:ok, _} = Relationships.create_relationship(user.id, muted.id, "mute")

      blocked_response = json_response(get(conn, ~p"/api/v1/relationships/blocked"), 200)
      muted_response = json_response(get(conn, ~p"/api/v1/relationships/muted"), 200)

      assert [blocked_user] = blocked_response["data"]["users"]
      assert [muted_user] = muted_response["data"]["users"]
      assert blocked_user["id"] == blocked.id
      assert muted_user["id"] == muted.id
      refute blocked_user["id"] == muted.id
      refute muted_user["id"] == blocked.id
    end
  end

  describe "GET /api/v1/relationships/liked and /liked-by proximity" do
    test "returns only active likes within 100 miles", %{conn: conn, user: user} do
      viewer =
        user
        |> Ecto.Changeset.change(geohash: Geohash.encode(30.2672, -97.7431, 9))
        |> Repo.update!()

      near =
        user_fixture()
        |> with_geohash(30.2672, -97.5)

      far =
        user_fixture()
        |> with_geohash(32.0, -97.7431)

      assert {:ok, _} = Relationships.create_relationship(viewer.id, near.id, "like")
      assert {:ok, _} = Relationships.create_relationship(viewer.id, far.id, "like")
      assert {:ok, _} = Relationships.create_relationship(near.id, viewer.id, "like")
      assert {:ok, _} = Relationships.create_relationship(far.id, viewer.id, "like")

      liked = json_response(get(conn, ~p"/api/v1/relationships/liked"), 200)
      liked_by = json_response(get(conn, ~p"/api/v1/relationships/liked-by"), 200)

      assert [liked_user] = liked["data"]["users"]
      assert [liked_by_user] = liked_by["data"]["users"]
      assert liked_user["id"] == near.id
      assert liked_by_user["id"] == near.id
      assert liked_user["distance_miles"] <= 100
      assert liked_by_user["distance_miles"] <= 100
      refute Enum.any?(liked["data"]["users"], &(&1["id"] == far.id))
      refute Enum.any?(liked_by["data"]["users"], &(&1["id"] == far.id))
    end

    test "excludes muted fans from the received likes directory", %{
      conn: conn,
      user: user
    } do
      viewer =
        user
        |> Ecto.Changeset.change(geohash: Geohash.encode(30.2672, -97.7431, 9))
        |> Repo.update!()

      fan =
        user_fixture()
        |> with_geohash(30.2672, -97.5)

      assert {:ok, _} = Relationships.create_relationship(fan.id, viewer.id, "like")
      assert {:ok, _} = Relationships.create_relationship(viewer.id, fan.id, "mute")

      liked_by = json_response(get(conn, ~p"/api/v1/relationships/liked-by"), 200)

      assert liked_by["data"]["users"] == []
    end

    test "paginates liked profiles at twenty per page", %{conn: conn, user: user} do
      viewer =
        user
        |> Ecto.Changeset.change(geohash: Geohash.encode(30.2672, -97.7431, 9))
        |> Repo.update!()

      fans =
        for index <- 1..21 do
          user_fixture(%{first_name: "Fan#{index}"})
          |> with_geohash(30.2672, -97.5)
        end

      Enum.each(fans, fn fan ->
        assert {:ok, _} = Relationships.create_relationship(viewer.id, fan.id, "like")
      end)

      first_page =
        json_response(
          get(conn, ~p"/api/v1/relationships/liked?page=1&per_page=20"),
          200
        )

      assert length(first_page["data"]["users"]) == 20
      assert first_page["data"]["pagination"]["page"] == 1
      assert first_page["data"]["pagination"]["per_page"] == 20
      assert first_page["data"]["pagination"]["total"] == 21
      assert first_page["data"]["pagination"]["total_pages"] == 2
      assert first_page["data"]["pagination"]["has_next_page"] == true

      second_page =
        json_response(
          get(conn, ~p"/api/v1/relationships/liked?page=2&per_page=20"),
          200
        )

      assert length(second_page["data"]["users"]) == 1
      assert second_page["data"]["pagination"]["has_next_page"] == false
    end
  end

  describe "feed scoping" do
    test "excludes users blocked by either party from search", %{conn: conn, user: user} do
      visible = user_fixture()
      blocked = user_fixture()
      muted = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(user.id, blocked.id, "block")
      assert {:ok, _} = Relationships.create_relationship(muted.id, user.id, "mute")

      conn = post(conn, ~p"/api/search/users", %{"limit" => 100})

      assert %{"data" => %{"users" => users}} = json_response(conn, 200)
      ids = Enum.map(users, & &1["id"])

      assert visible.id in ids
      refute blocked.id in ids
      refute muted.id in ids
      refute user.id in ids
    end

    test "does not return a blocked user from direct search", %{conn: conn, user: user} do
      target =
        user_fixture(%{nickname: "hidden_handle", user_handle_search: true})

      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "block")

      conn = get(conn, ~p"/api/search/user/#{target.nickname}")

      assert %{"status" => "error"} = json_response(conn, 404)
    end

    test "does not return a user who blocked the viewer from direct search", %{
      conn: conn,
      user: user
    } do
      target =
        user_fixture(%{nickname: "reverse_block", user_handle_search: true})

      assert {:ok, _} = Relationships.create_relationship(target.id, user.id, "block")

      conn = get(conn, ~p"/api/search/user/#{target.nickname}")

      assert %{"status" => "error"} = json_response(conn, 404)
    end

    test "does not return a muted user or a user who muted the viewer", %{
      conn: conn,
      user: user
    } do
      muted =
        user_fixture(%{nickname: "muted_handle", user_handle_search: true})

      reverse_muted =
        user_fixture(%{nickname: "reverse_mute", user_handle_search: true})

      assert {:ok, _} = Relationships.create_relationship(user.id, muted.id, "mute")
      assert {:ok, _} = Relationships.create_relationship(reverse_muted.id, user.id, "mute")

      assert %{"status" => "error"} =
               json_response(get(conn, ~p"/api/search/user/#{muted.nickname}"), 404)

      assert %{"status" => "error"} =
               json_response(get(conn, ~p"/api/search/user/#{reverse_muted.nickname}"), 404)
    end

    test "excludes events-only profiles from the feed", %{conn: conn} do
      events_only = user_fixture()

      assert {:ok, _} =
               events_only
               |> Ecto.Changeset.change(settings: %{"visibility_preference" => "events-only"})
               |> Meetcutes.Repo.update()

      conn = post(conn, ~p"/api/search/users", %{"limit" => 100})

      assert %{"data" => %{"users" => users}} = json_response(conn, 200)
      refute events_only.id in Enum.map(users, & &1["id"])
    end
  end

  defp with_geohash(user, latitude, longitude) do
    user
    |> Ecto.Changeset.change(geohash: Geohash.encode(latitude, longitude, 9))
    |> Repo.update!()
  end
end
