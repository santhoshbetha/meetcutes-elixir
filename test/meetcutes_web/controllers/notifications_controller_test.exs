defmodule MeetcutesWeb.NotificationsControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Notifications

  setup %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn, user: user, token: token}
  end

  defp notification_fixture(user, attrs \\ %{}) do
    {:ok, notification} =
      Notifications.create_notification(
        Map.merge(
          %{
            user_id: user.id,
            type: :admin_broadcast,
            title: "Welcome to MeetCutes",
            body: "Your inbox is ready.",
            metadata: %{}
          },
          attrs
        )
      )

    notification
  end

  describe "GET /api/v1/notifications" do
    test "returns the bearer user's inbox newest-first with pagination", %{
      conn: conn,
      user: user
    } do
      notification_fixture(user, %{type: :upcoming_event, title: "Event reminder"})
      notification_fixture(user, %{type: :profile_like, title: "New like"})
      notification_fixture(user, %{type: :admin_broadcast, title: "Announcement"})

      conn = get(conn, ~p"/api/v1/notifications?page=1&per_page=2")

      assert %{
               "status" => "success",
               "data" => %{
                 "notifications" => notifications,
                 "pagination" => pagination,
                 "unread_count" => 3
               }
             } = json_response(conn, 200)

      assert length(notifications) == 2
      assert pagination["page"] == 1
      assert pagination["per_page"] == 2
      assert pagination["total"] == 3
      assert pagination["total_pages"] == 2

      assert Enum.map(notifications, & &1["title"]) == ["Announcement", "New like"]
      assert Enum.map(notifications, & &1["type"]) == ["admin_broadcast", "profile_like"]
      assert Enum.all?(notifications, &(&1["is_read"] == false))
    end

    test "never leaks another user's notifications", %{conn: conn, user: user} do
      other = user_fixture()
      notification_fixture(user, %{title: "Mine"})
      notification_fixture(other, %{title: "Theirs"})

      conn = get(conn, ~p"/api/v1/notifications")

      assert %{"data" => %{"notifications" => notifications, "unread_count" => 1}} =
               json_response(conn, 200)

      assert Enum.map(notifications, & &1["title"]) == ["Mine"]
    end

    test "clamps invalid pagination instead of failing", %{conn: conn, user: user} do
      notification_fixture(user)

      conn = get(conn, ~p"/api/v1/notifications?page=-4&per_page=1000")

      assert %{"data" => %{"pagination" => pagination}} = json_response(conn, 200)
      assert pagination["page"] == 1
      assert pagination["per_page"] == 100
    end

    test "requires authentication" do
      conn = build_conn() |> get(~p"/api/v1/notifications")

      assert json_response(conn, 401)
    end
  end

  describe "PATCH /api/v1/notifications/:id/read" do
    test "marks one owned notification as read", %{conn: conn, user: user} do
      notification = notification_fixture(user)

      conn = patch(conn, ~p"/api/v1/notifications/#{notification.id}/read")

      assert %{
               "status" => "success",
               "data" => %{
                 "notification" => %{"id" => id, "is_read" => true},
                 "unread_count" => 0
               }
             } = json_response(conn, 200)

      assert id == notification.id
    end

    test "is idempotent for notifications that are already read", %{
      conn: conn,
      user: user
    } do
      notification = notification_fixture(user, %{is_read: true})

      conn = patch(conn, ~p"/api/v1/notifications/#{notification.id}/read")

      assert %{"data" => %{"notification" => %{"is_read" => true}, "unread_count" => 0}} =
               json_response(conn, 200)
    end

    test "returns 404 for another user's notification", %{conn: conn} do
      other = user_fixture()
      notification = notification_fixture(other)

      conn = patch(conn, ~p"/api/v1/notifications/#{notification.id}/read")

      assert %{"status" => "error", "code" => "notification_not_found"} =
               json_response(conn, 404)
    end

    test "requires authentication" do
      notification = notification_fixture(user_fixture())

      conn =
        build_conn()
        |> patch(~p"/api/v1/notifications/#{notification.id}/read")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/notifications/mark-all-read" do
    test "bulk marks only the bearer user's unread notifications", %{
      conn: conn,
      user: user
    } do
      notification_fixture(user)
      notification_fixture(user)
      notification_fixture(user, %{is_read: true})
      other = user_fixture()
      other_unread = notification_fixture(other)

      conn = post(conn, ~p"/api/v1/notifications/mark-all-read")

      assert %{
               "status" => "success",
               "data" => %{"updated" => 2, "unread_count" => 0}
             } = json_response(conn, 200)

      assert Notifications.unread_count(user.id) == 0
      assert Notifications.unread_count(other.id) == 1
      assert {:ok, %{is_read: true}} = Notifications.mark_read(other.id, other_unread.id)
    end

    test "returns zero when there is nothing unread", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications/mark-all-read")

      assert %{"data" => %{"updated" => 0, "unread_count" => 0}} =
               json_response(conn, 200)
    end

    test "requires authentication" do
      conn = build_conn() |> post(~p"/api/v1/notifications/mark-all-read")

      assert json_response(conn, 401)
    end
  end
end
