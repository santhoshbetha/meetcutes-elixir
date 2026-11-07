defmodule MeetcutesWeb.SearchControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias Meetcutes.Repo

  setup %{conn: conn} do
    viewer = user_fixture()
    token = Accounts.generate_user_session_token(viewer)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn, viewer: viewer}
  end

  describe "GET /api/search/user/:identifier discoverability" do
    test "finds a user by email when email search is enabled", %{conn: conn} do
      target =
        user_fixture(%{email: "discoverable@example.com", ethnicity: "Asian"})
        |> set_flags(email_search: true)

      conn = get(conn, ~p"/api/search/user/#{target.email}")

      assert %{"status" => "success", "data" => %{"user" => user}} =
               json_response(conn, 200)

      assert user["id"] == target.id
      assert user["ethnicity"] == "Asian"
    end

    test "treats a missing email flag as enabled (settings default)", %{conn: conn} do
      target = user_fixture(%{email: "default-email@example.com"})
      assert is_nil(target.email_search)

      conn = get(conn, ~p"/api/search/user/#{target.email}")

      assert %{"data" => %{"user" => user}} = json_response(conn, 200)
      assert user["id"] == target.id
    end

    test "hides a user who opted out of email search", %{conn: conn} do
      target =
        user_fixture(%{email: "private@example.com"})
        |> set_flags(email_search: false)

      conn = get(conn, ~p"/api/search/user/#{target.email}")

      assert %{"status" => "error"} = json_response(conn, 404)
    end

    test "only finds a phone number when phone search is enabled", %{conn: conn} do
      hidden =
        user_fixture(%{phone_number: "5125550101"})
        |> set_flags(phone_number_search: false)

      conn = get(conn, ~p"/api/search/user/#{hidden.phone_number}")
      assert %{"status" => "error"} = json_response(conn, 404)

      discoverable =
        user_fixture(%{phone_number: "5125550102"})
        |> set_flags(phone_number_search: true)

      conn = get(conn, ~p"/api/search/user/#{discoverable.phone_number}")

      assert %{"data" => %{"user" => user}} = json_response(conn, 200)
      assert user["id"] == discoverable.id
    end

    test "only finds a handle when handle search is enabled", %{conn: conn} do
      hidden =
        user_fixture(%{nickname: "hidden_handle"})
        |> set_flags(user_handle_search: false)

      conn = get(conn, ~p"/api/search/user/#{hidden.nickname}")
      assert %{"status" => "error"} = json_response(conn, 404)

      discoverable =
        user_fixture(%{nickname: "public_handle"})
        |> set_flags(user_handle_search: true)

      conn = get(conn, ~p"/api/search/user/#{discoverable.nickname}")

      assert %{"data" => %{"user" => user}} = json_response(conn, 200)
      assert user["id"] == discoverable.id
    end
  end

  describe "POST /api/search/users gender scoping" do
    test "uses the authenticated viewer gender and ignores a same-gender hint", %{
      conn: conn
    } do
      viewer = user_fixture(%{gender: "Male"})
      token = Accounts.generate_user_session_token(viewer)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)

      female = user_fixture(%{gender: "Female", age: 28})
      male = user_fixture(%{gender: "Male", age: 30})

      conn =
        post(conn, ~p"/api/search/users", %{
          "gender" => "Male",
          "limit" => 50
        })

      assert %{"status" => "success", "data" => %{"users" => users}} =
               json_response(conn, 200)

      ids = Enum.map(users, & &1["id"])

      assert female.id in ids
      refute male.id in ids
    end
  end

  defp set_flags(%User{} = user, attrs) do
    user
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end
end
