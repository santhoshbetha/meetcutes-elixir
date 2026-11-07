defmodule MeetcutesWeb.SettingsControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  alias Meetcutes.Accounts
  import Meetcutes.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture() |> set_password()
    auth_token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> auth_token)

    %{conn: conn, user: user, auth_token: auth_token}
  end

  describe "PUT /users/settings (change password form)" do
    test "updates the user password and resets tokens", %{
      conn: conn,
      user: user,
      auth_token: auth_token
    } do
      conn =
        put(conn, ~p"/api/users/settings", %{
          "action" => "update_password",
          "user" => %{
            "current_password" => valid_user_password(),
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert %{"status" => "success", "message" => message, "token" => token} =
               json_response(conn, 200)

      assert message =~ "Password has been reset successfully"
      assert is_binary(token)

      refute Accounts.get_user_by_session_token(auth_token)
      assert {token_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert token_user.id == user.id

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/api/users/settings", %{
          "action" => "update_password",
          "user" => %{
            "current_password" => valid_user_password(),
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert %{"status" => "error", "message" => "Validation failed", "errors" => errors} =
               json_response(conn, 422)

      assert is_map(errors)
    end
  end

  describe "PUT /users/settings (change email form)" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/api/users/settings", %{
          "action" => "update_email",
          "user" => %{
            "email" => unique_user_email(),
            "current_password" => valid_user_password()
          }
        })

      assert %{"status" => "success", "message" => message} = json_response(conn, 202)
      assert message =~ "A link to confirm your email change has been sent"

      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/api/users/settings", %{
          "action" => "update_email",
          "user" => %{
            "email" => "with spaces",
            "current_password" => valid_user_password()
          }
        })

      assert %{"status" => "error", "message" => "Validation failed", "errors" => errors} =
               json_response(conn, 422)

      assert is_map(errors)
    end
  end

  describe "GET /users/settings/confirm-email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, ~p"/api/users/settings/confirm_email/#{token}")

      assert %{"status" => "success", "message" => message, "user" => user_data} =
               json_response(conn, 200)

      assert message =~ "Email has been updated successfully"
      assert is_map(user_data)
      assert user_data["email"] == email

      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # Try to use the token again
      conn = get(conn, ~p"/api/users/settings/confirm_email/#{token}")

      assert %{"status" => "error", "message" => message} = json_response(conn, 422)

      assert message =~ "invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/api/users/settings/confirm_email/oops")

      assert %{"status" => "error", "message" => message} = json_response(conn, 422)

      assert message =~ "invalid or it has expired"

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/api/users/settings/confirm_email/#{token}")

      assert %{"status" => "error", "message" => message} = json_response(conn, 401)
      assert message =~ "You must log in to access this resource"
    end
  end
end
