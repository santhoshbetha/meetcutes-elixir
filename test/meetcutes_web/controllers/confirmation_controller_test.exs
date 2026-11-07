defmodule MeetcutesWeb.ConfirmationControllerTest do
  use MeetcutesWeb.ConnCase, async: true

  import Ecto.Query
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.UserToken
  alias Meetcutes.Repo

  describe "POST /api/users/resend_confirmation" do
    @tag :capture_log
    test "sends a new confirmation email for an unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture()

      conn =
        post(conn, ~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => user.email}
        })

      assert %{"status" => "success", "message" => message} = json_response(conn, 200)
      assert message =~ "If this email is associated"

      assert Repo.exists?(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
               )
             )
    end

    test "does not reveal whether an email is registered", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => unique_user_email()}
        })

      assert %{"status" => "success", "message" => message} = json_response(conn, 200)
      assert message =~ "If this email is associated"
    end

    test "does not send another email for a confirmed user", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => user.email}
        })

      assert %{"status" => "success"} = json_response(conn, 200)

      refute Repo.exists?(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
               )
             )
    end
  end

  describe "POST /api/users/confirm/:token" do
    test "confirms the user and returns the profile", %{conn: conn} do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = post(conn, ~p"/api/users/confirm/#{token}")

      assert %{"status" => "success", "user" => user_data} = json_response(conn, 200)
      assert user_data["id"] == user.id
      assert user_data["confirmed_at"] != nil
      assert user_data["is_confirmed"] == true
      assert user_data["email_verified"] == true

      confirmed_user = Accounts.get_user!(user.id)
      assert confirmed_user.confirmed_at
      assert confirmed_user.is_confirmed
    end

    test "returns an error for an invalid token", %{conn: conn} do
      conn = post(conn, ~p"/api/users/confirm/not-a-real-token")

      assert %{"status" => "error", "message" => message} = json_response(conn, 422)
      assert message =~ "invalid or has expired"
    end
  end
end
