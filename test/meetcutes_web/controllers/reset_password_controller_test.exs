defmodule MeetcutesWeb.ResetPasswordControllerTest do
  use MeetcutesWeb.ConnCase, async: true

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts

  describe "GET /api/users/reset_password/:token" do
    test "returns success for a valid, unexpired token", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      conn = get(conn, ~p"/api/users/reset_password/#{token}")

      assert %{"status" => "success", "message" => message} = json_response(conn, 200)
      assert message =~ "valid"
    end

    test "does not consume the token", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      assert json_response(get(conn, ~p"/api/users/reset_password/#{token}"), 200)

      conn =
        put(conn, ~p"/api/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "brand new password",
            "password_confirmation" => "brand new password"
          }
        })

      assert %{"status" => "success"} = json_response(conn, 200)
    end

    test "returns an error for an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/api/users/reset_password/not-a-real-token")

      assert %{"status" => "error", "message" => message} =
               json_response(conn, 422)

      assert message =~ "invalid or has expired"
    end

    test "is available to signed-in users as well", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      session_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{session_token}")
        |> get(~p"/api/users/reset_password/#{token}")

      assert %{"status" => "success"} = json_response(conn, 200)
    end
  end

  describe "POST /api/v1/auth/forgot-password" do
    test "returns 200 and increments the retry counter for a known account", %{
      conn: conn
    } do
      user = user_fixture()

      conn =
        post(conn, ~p"/api/v1/auth/forgot-password", %{
          "user" => %{"email" => user.email}
        })

      assert %{
               "status" => "success",
               "password_retry_count" => 1
             } = json_response(conn, 200)

      assert Accounts.get_user!(user.id).password_retry_count == 1
    end

    test "returns 200 for an unknown address without revealing account existence", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/api/v1/auth/forgot-password", %{
          "user" => %{"email" => unique_user_email()}
        })

      assert %{"status" => "success", "message" => message} =
               json_response(conn, 200)

      assert message =~ "If this email is associated with an account"
    end

    test "returns 429 with the retry payload once the limit is exceeded", %{
      conn: conn
    } do
      user = user_fixture()
      {:ok, user} = Accounts.update_user(user, %{password_retry_count: 6})

      conn =
        post(conn, ~p"/api/v1/auth/forgot-password", %{
          "user" => %{"email" => user.email}
        })

      assert %{
               "status" => "error",
               "code" => "password_reset_limit_exceeded",
               "message" => "Password reset limit exceeded. Please contact support.",
               "password_retry_count" => 7
             } = json_response(conn, 429)
    end
  end

  describe "POST /api/v1/auth/reset-password/:token" do
    test "returns 200 and clears the retry counter on success", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.update_user(user, %{password_retry_count: 3})

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      conn =
        post(conn, ~p"/api/v1/auth/reset-password/#{token}", %{
          "user" => %{
            "password" => "brand new password",
            "password_confirmation" => "brand new password"
          }
        })

      assert %{"status" => "success", "password_retry_count" => 0} =
               json_response(conn, 200)

      refreshed = Accounts.get_user!(user.id)
      assert refreshed.password_retry_count == 0
      assert Accounts.get_user_by_email_and_password(user.email, "brand new password")
    end

    test "accepts the token inside the user payload", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      conn =
        post(conn, ~p"/api/v1/auth/reset-password", %{
          "user" => %{
            "token" => token,
            "password" => "brand new password",
            "password_confirmation" => "brand new password"
          }
        })

      assert %{"status" => "success"} = json_response(conn, 200)
    end

    test "returns 401 for an invalid token", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/auth/reset-password/not-a-real-token", %{
          "user" => %{
            "password" => "brand new password",
            "password_confirmation" => "brand new password"
          }
        })

      assert %{"status" => "error"} = json_response(conn, 401)
    end
  end
end
