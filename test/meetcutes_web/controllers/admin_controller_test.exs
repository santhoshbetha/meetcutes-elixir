defmodule MeetcutesWeb.AdminControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Ecto.Query
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.{User, UserToken}
  alias Meetcutes.Events
  alias Meetcutes.Locations
  alias Meetcutes.Repo

  @secret "test-mcp-admin-secret-key-0123456789"

  setup %{conn: conn} do
    previous_secret = Application.get_env(:meetcutes, :mcp_admin_secret_key)
    previous_payment = Application.get_env(:meetcutes, :payment_feature_enabled)
    previous_maintenance = Application.get_env(:meetcutes, :maintenance_mode_active)

    Application.put_env(:meetcutes, :mcp_admin_secret_key, @secret)

    on_exit(fn ->
      restore_env(:mcp_admin_secret_key, previous_secret)
      restore_env(:payment_feature_enabled, previous_payment)
      restore_env(:maintenance_mode_active, previous_maintenance)
    end)

    conn =
      conn
      |> put_req_header("x-mcp-admin-key", @secret)
      |> put_req_header("content-type", "application/json")

    %{conn: conn}
  end

  describe "POST /api/v1/admin/mcp-action authentication" do
    test "rejects a missing or incorrect admin key", %{conn: conn} do
      no_key =
        conn
        |> delete_req_header("x-mcp-admin-key")
        |> post(~p"/api/v1/admin/mcp-action", %{"action" => "get_system_stats"})

      assert %{"success" => false, "status" => "error"} = json_response(no_key, 401)

      wrong_key =
        build_conn()
        |> put_req_header("x-mcp-admin-key", "wrong-secret")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/admin/mcp-action", %{"action" => "get_system_stats"})

      assert %{"success" => false, "status" => "error"} = json_response(wrong_key, 401)
    end
  end

  describe "get_system_stats" do
    test "returns counts for active users, events, subscriptions, and Oban failures", %{
      conn: conn
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      active =
        user_fixture()
        |> Ecto.Changeset.change(is_active: true, user_state: :active)
        |> Repo.update!()

      _subscriber =
        user_fixture()
        |> Ecto.Changeset.change(
          is_active: true,
          user_state: :active,
          subscription_expires_at: DateTime.add(now, 30, :day)
        )
        |> Repo.update!()

      _inactive =
        user_fixture()
        |> Ecto.Changeset.change(is_active: false, user_state: :inactive)
        |> Repo.update!()

      {:ok, location} =
        Locations.create_location(%{
          name: "Admin Test Venue",
          street: "1 Admin Way",
          locality: "Austin",
          state: "TX",
          postal_code: "78701",
          latitude: 30.2672,
          longitude: -97.7431
        })

      start_at = DateTime.add(now, 2, :day)

      {:ok, _event} =
        Events.create_event(
          %{
            "title" => "Admin Stats Event",
            "location_id" => location.id,
            "start_at" => start_at,
            "end_at" => DateTime.add(start_at, 2, :hour),
            "status" => "PUBLISHED"
          },
          active.id
        )

      {:ok, job} = Oban.insert(Meetcutes.Workers.CleanupOldEvents.new(%{}))

      Repo.update_all(
        from(j in Oban.Job, where: j.id == ^job.id),
        set: [state: "discarded"]
      )

      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{"action" => "get_system_stats"})
        |> json_response(200)

      assert %{"success" => true, "data" => stats} = response
      assert stats["active_users"] == 2
      assert stats["event_total"] == 1
      assert stats["active_subscriptions"] == 1
      assert stats["oban_failure_backlog"] == 1
      assert is_binary(stats["generated_at"])
    end
  end

  describe "runtime toggles" do
    test "toggle_maintenance updates application configuration", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{
          "action" => "toggle_maintenance",
          "params" => %{"value" => "true"}
        })
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["maintenance_mode_active"] == true
      assert Application.get_env(:meetcutes, :maintenance_mode_active) == true

      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{
          "action" => "toggle_maintenance",
          "params" => %{"value" => "false"}
        })
        |> json_response(200)

      assert response["data"]["maintenance_mode_active"] == false
      assert Application.get_env(:meetcutes, :maintenance_mode_active) == false
    end

    test "toggle_paywall updates application configuration", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{
          "action" => "toggle_paywall",
          "params" => %{"value" => "false"}
        })
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["payment_feature_enabled"] == false
      assert Application.get_env(:meetcutes, :payment_feature_enabled) == false
    end
  end

  describe "user status and match count" do
    test "suspends by email and revokes session tokens, then restores active access", %{
      conn: conn
    } do
      user =
        user_fixture(%{email: "mcp-status-#{System.unique_integer([:positive])}@example.com"})

      token = Accounts.generate_user_session_token(user)

      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{
          "action" => "update_user_status",
          "params" => %{"email" => user.email, "user_state" => "suspended"}
        })
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["user_state"] == "suspended"

      stored = Repo.get!(User, user.id)
      assert stored.user_state == :suspended
      assert stored.is_active == false
      assert stored.is_locked == true
      assert Accounts.get_user_by_session_token(token) == nil
      assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count, :id) == 0

      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{
          "action" => "update_user_status",
          "params" => %{"user_id" => user.id, "user_state" => "active"}
        })
        |> json_response(200)

      assert response["data"]["user_state"] == "active"

      restored = Repo.get!(User, user.id)
      assert restored.user_state == :active
      assert restored.is_active == true
      assert restored.is_locked == false
    end

    test "force_match_count writes a deterministic count", %{conn: conn} do
      user = user_fixture()

      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{
          "action" => "force_match_count",
          "params" => %{"user_id" => user.id, "count" => "250"}
        })
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["around_user_count"] == 250

      stored = Repo.get!(User, user.id)
      assert stored.around_user_count == 250
      assert stored.around_user_count_updated_at != nil
    end

    test "rejects unsupported actions", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/admin/mcp-action", %{"action" => "drop_all_tables"})
        |> json_response(422)

      assert %{"success" => false} = response
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:meetcutes, key)
  defp restore_env(key, value), do: Application.put_env(:meetcutes, key, value)
end
