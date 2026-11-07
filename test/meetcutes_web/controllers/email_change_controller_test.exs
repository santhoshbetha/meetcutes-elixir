defmodule MeetcutesWeb.EmailChangeControllerTest do
  use MeetcutesWeb.ConnCase, async: true

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts

  defp change_email_token(user, email) do
    extract_user_token(fn url ->
      Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
    end)
  end

  describe "POST /api/users/confirm_email_change/:token" do
    test "confirms the change without a session", %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()
      token = change_email_token(user, email)

      conn = post(conn, ~p"/api/users/confirm_email_change/#{token}")

      assert %{
               "status" => "success",
               "message" => message,
               "email" => ^email
             } = json_response(conn, 200)

      assert message =~ "Email has been updated successfully"
      assert Accounts.get_user_by_email(email)
      refute Accounts.get_user_by_email(user.email)
    end

    test "deletes the token after it is used", %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()
      token = change_email_token(user, email)

      assert json_response(
               post(conn, ~p"/api/users/confirm_email_change/#{token}"),
               200
             )

      conn = post(conn, ~p"/api/users/confirm_email_change/#{token}")

      assert %{"status" => "error", "message" => message} = json_response(conn, 422)
      assert message =~ "invalid or it has expired"
      assert Accounts.get_user_by_email(email)
    end

    test "rejects an invalid token", %{conn: conn} do
      user = user_fixture()

      conn = post(conn, ~p"/api/users/confirm_email_change/not-a-real-token")

      assert %{"status" => "error", "message" => message} = json_response(conn, 422)
      assert message =~ "invalid or it has expired"
      assert Accounts.get_user_by_email(user.email)
    end

    test "works for a signed-in user as well", %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()
      token = change_email_token(user, email)
      session_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{session_token}")
        |> post(~p"/api/users/confirm_email_change/#{token}")

      assert %{"status" => "success", "email" => ^email} = json_response(conn, 200)
    end
  end
end
