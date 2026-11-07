defmodule MeetcutesWeb.UserAuthTest do
  use MeetcutesWeb.ConnCase, async: true

  alias Meetcutes.Accounts
  alias MeetcutesWeb.UserAuth

  import Meetcutes.AccountsFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, MeetcutesWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: %{user_fixture() | authenticated_at: DateTime.utc_now(:second)}, conn: conn}
  end

  describe "fetch_current_user/2" do
    test "assigns current_user from a valid bearer token", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
      assert conn.assigns.current_user.email == user.email
    end

    test "assigns nil when authorization header is missing", %{conn: conn} do
      conn = UserAuth.fetch_current_user(conn, [])

      assert conn.assigns.current_user == nil
    end

    test "assigns nil when bearer token is invalid", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user == nil
    end
  end

  describe "require_sudo_mode/2" do
    test "allows users that have authenticated in the last 10 minutes", %{conn: conn, user: user} do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_user, user)
        |> UserAuth.require_sudo_mode([])

      refute conn.halted
      refute conn.status
    end

    test "redirects when authentication is too old", %{conn: conn, user: user} do
      eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)
      user = %{user | authenticated_at: eleven_minutes_ago}
      user_token = Accounts.generate_user_session_token(user)
      {user, token_inserted_at} = Accounts.get_user_by_session_token(user_token)
      assert DateTime.compare(token_inserted_at, user.authenticated_at) == :gt

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_user, user)
        |> UserAuth.require_sudo_mode([])

      assert conn.halted
      assert conn.status == 403

      assert %{"error" => "You must re-authenticate to access this resource."} =
               Jason.decode!(conn.resp_body)
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert conn.status == 403
      assert %{"error" => "You are already logged in."} = Jason.decode!(conn.resp_body)
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn = UserAuth.redirect_if_user_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user/2" do
    test "returns 401 if user is not authenticated", %{conn: conn} do
      conn = conn |> UserAuth.require_authenticated_user([])
      assert conn.halted
      assert conn.status == 401

      assert %{"status" => "error", "message" => "You must log in to access this resource."} =
               Jason.decode!(conn.resp_body)
    end

    test "does not halt if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
      refute conn.status
    end
  end
end
