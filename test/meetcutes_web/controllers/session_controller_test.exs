defmodule MeetcutesWeb.SessionControllerTest do
  use MeetcutesWeb.ConnCase, async: true

  import Meetcutes.AccountsFixtures
  alias Meetcutes.Accounts
  alias Meetcutes.Repo

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture() |> set_password()}
  end

  describe "POST /api/users/login (magic link)" do
    test "logs the user in with valid token", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "verify_magic_link",
          "user" => %{"token" => token}
        })

      response = json_response(conn, 200)
      user_data = response["user"] || get_in(response, ["data", "user"]) || response["data"]
      returned_token = response["token"] || get_in(response, ["data", "token"])

      assert user_data["id"] == user.id
      assert is_binary(response["message"])
      assert is_binary(returned_token)
      assert {session_user, _inserted_at} = Accounts.get_user_by_session_token(returned_token)
      assert session_user.id == user.id
    end

    test "logs the user in with valid token (confirmed user)", %{
      conn: conn,
      unconfirmed_user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "verify_magic_link",
          "user" => %{"token" => token}
        })

      response = json_response(conn, 200)
      user_data = response["user"] || get_in(response, ["data", "user"]) || response["data"]
      returned_token = response["token"] || get_in(response, ["data", "token"])

      assert user_data["id"] == user.id
      assert is_binary(response["message"])
      assert is_binary(returned_token)
      assert Accounts.get_user!(user.id).confirmed_at != nil
    end

    test "returns error with invalid token", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "verify_magic_link",
          "user" => %{"token" => "invalid"}
        })

      response = json_response(conn, 401)

      assert (response["error"] || response["message"]) ==
               "The link is invalid or it has expired."
    end
  end

  describe "POST /api/users/login (email + password)" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      response = json_response(conn, 200)
      user_data = response["user"] || get_in(response, ["data", "user"]) || response["data"]
      returned_token = response["token"] || get_in(response, ["data", "token"])

      assert user_data["id"] == user.id
      assert is_binary(response["message"])
      assert is_binary(returned_token)
      assert {session_user, _inserted_at} = Accounts.get_user_by_session_token(returned_token)
      assert session_user.id == user.id
    end

    test "records time_of_login and last_seen_at on login", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert json_response(conn, 200)

      refreshed = Accounts.get_user!(user.id)
      assert %DateTime{} = refreshed.time_of_login
      assert %DateTime{} = refreshed.last_seen_at
      assert %NaiveDateTime{} = refreshed.last_active_at
    end

    test "refreshes last_seen_at during bearer token validation", %{
      conn: conn,
      user: user
    } do
      old_seen =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(-300, :second)

      old_active =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.add(-300, :second)

      {:ok, _user} =
        user
        |> Ecto.Changeset.change(
          last_seen_at: old_seen,
          last_active_at: old_active
        )
        |> Repo.update()

      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> get(~p"/api/users/profile")

      assert json_response(conn, 200)

      refreshed = Accounts.get_user!(user.id)
      assert DateTime.compare(refreshed.last_seen_at, old_seen) == :gt
    end

    test "resets the password retry counter on successful login", %{conn: conn, user: user} do
      {:ok, _user} = Accounts.update_user(user, %{password_retry_count: 3})

      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert json_response(conn, 200)
      assert Accounts.get_user_by_email(user.email).password_retry_count == 0
    end

    test "rejects login for an unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture() |> set_password()

      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert %{
               "status" => "error",
               "code" => "email_not_confirmed",
               "message" => message
             } = json_response(conn, 403)

      assert message =~ "confirm your email"
      refute Accounts.get_user_by_email(user.email).confirmed_at
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(%{user_return_to: "/foo/bar"})
        |> post(~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      response = json_response(conn, 200)
      user_data = response["user"] || get_in(response, ["data", "user"]) || response["data"]
      returned_token = response["token"] || get_in(response, ["data", "token"])

      assert user_data["id"] == user.id
      assert is_binary(response["message"])
      assert is_binary(returned_token)
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => "invalid_password"
          }
        })

      response = json_response(conn, 401)
      assert (response["error"] || response["message"]) == "Invalid email or password"
    end
  end

  describe "POST /api/users/login (magic link request)" do
    test "sends magic link email", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "request_magic_link",
          "user" => %{"email" => user.email}
        })

      assert %{"message" => message} = json_response(conn, 200)
      assert message =~ "If your email is in our system"
    end
  end

  describe "DELETE /api/users/logout" do
    test "logs the user out", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> delete(~p"/api/users/logout")

      assert %{"message" => message} = json_response(conn, 200)
      assert message == "Logged out successfully."

      refute Accounts.get_user_by_session_token(token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/api/users/logout")

      response = json_response(conn, 400)
      assert (response["error"] || response["message"]) == "Missing authorization bearer token."
    end
  end
end
