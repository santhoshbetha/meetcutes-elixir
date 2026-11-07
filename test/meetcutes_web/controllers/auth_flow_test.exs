defmodule MeetcutesWeb.AuthFlowTest do
  @moduledoc """
  End-to-end coverage for the JSON auth endpoints the React client uses.

  These tests follow the same order the frontend does: sign up, confirm the
  email, log in, load the profile, log out, then reset a password.
  """
  use MeetcutesWeb.ConnCase, async: true

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts

  @password "correct horse battery"

  defp registration_params(email) do
    %{
      "email" => email,
      "password" => @password,
      "password_confirmation" => @password,
      "first_name" => "Ada",
      "last_name" => "Lovelace",
      "phone_number" => unique_user_phone(),
      "birthday" => "1990-05-01",
      "city" => "Austin",
      "state" => "Texas",
      "time_zone" => "America/Chicago",
      "settings" => %{"visibility_preference" => "events-only"},
      "raw_lat" => 30.2672,
      "raw_lon" => -97.7431
    }
  end

  defp login(conn, email, password) do
    post(conn, ~p"/api/users/login", %{
      "action" => "password",
      "user" => %{"email" => email, "password" => password}
    })
  end

  describe "signup -> confirm -> login -> profile -> logout" do
    test "walks the full confirmation flow without leaking secrets", %{conn: conn} do
      email = unique_user_email()

      conn = post(conn, ~p"/api/users/register", %{"user" => registration_params(email)})

      assert %{"status" => "success", "data" => %{"user" => registered}} =
               json_response(conn, 201)

      assert registered["email"] == email
      assert registered["confirmed_at"] == nil
      assert registered["user_state"] == "active"
      assert registered["visibility_preference"] == "events-only"
      assert is_float(registered["latitude"])
      assert is_float(registered["longitude"])
      refute Map.has_key?(registered, "hashed_password")
      refute Map.has_key?(registered, "calendar_token")

      # No session may be issued before the address is confirmed.
      conn = login(build_conn(), email, @password)
      assert %{"code" => "email_not_confirmed"} = json_response(conn, 403)

      user = Accounts.get_user_by_email(email)

      confirmation_token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = post(build_conn(), ~p"/api/users/confirm/#{confirmation_token}")
      assert %{"status" => "success", "user" => confirmed} = json_response(conn, 200)
      assert confirmed["confirmed_at"] != nil

      conn = login(build_conn(), email, @password)
      assert %{"token" => session_token, "user" => profile} = json_response(conn, 200)
      assert is_binary(session_token)
      assert profile["id"] == user.id

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> session_token)
        |> get(~p"/api/users/profile")

      assert %{"user" => fetched} = json_response(conn, 200)
      assert fetched["id"] == user.id
      assert fetched["email"] == email
      assert is_float(fetched["latitude"])
      assert is_float(fetched["longitude"])

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> session_token)
        |> delete(~p"/api/users/logout")

      assert %{"message" => "Logged out successfully."} = json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> session_token)
        |> get(~p"/api/users/profile")

      assert %{"status" => "error"} = json_response(conn, 401)
    end
  end

  describe "password reset" do
    test "is generic for unknown emails and rotates credentials for known ones", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/reset_password", %{
          "user" => %{"email" => unique_user_email()}
        })

      assert %{"status" => "success"} = json_response(conn, 200)

      user = user_fixture() |> set_password()

      conn =
        build_conn()
        |> post(~p"/api/users/reset_password", %{"user" => %{"email" => user.email}})

      assert %{"status" => "success", "message" => message} = json_response(conn, 200)
      assert message =~ "If this email is associated"

      reset_token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      new_password = "brand new passphrase"

      conn =
        build_conn()
        |> put(~p"/api/users/reset_password/#{reset_token}", %{
          "user" => %{
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert %{"status" => "success"} = json_response(conn, 200)

      # The previous password is no longer accepted.
      conn = login(build_conn(), user.email, valid_user_password())
      assert json_response(conn, 401)

      conn = login(build_conn(), user.email, new_password)
      assert %{"token" => _token} = json_response(conn, 200)
    end

    test "rejects an invalid reset token", %{conn: conn} do
      conn =
        put(conn, ~p"/api/users/reset_password/not-a-real-token", %{
          "user" => %{
            "password" => "brand new passphrase",
            "password_confirmation" => "brand new passphrase"
          }
        })

      assert %{"message" => message} = json_response(conn, 401)
      assert message =~ "invalid or has expired"
    end
  end
end
