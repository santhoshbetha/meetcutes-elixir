defmodule MeetcutesWeb.RegistrationControllerTest do
  use MeetcutesWeb.ConnCase, async: true

  import Ecto.Query
  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.UserToken
  alias Meetcutes.Repo

  describe "POST /users/register" do
    @tag :capture_log
    test "creates an unconfirmed account and sends a confirmation email", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, "/api/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert %{"status" => "success", "message" => message, "data" => data} =
               json_response(conn, 201)

      assert message =~ "Registration successful"
      assert %{"user" => user_data} = data
      refute Map.has_key?(data, "token")
      assert user_data["email"] == email
      assert user_data["confirmed_at"] == nil
      assert user_data["is_confirmed"] == false

      user = Accounts.get_user_by_email(email)
      assert user

      assert Repo.exists?(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
               )
             )
    end

    test "stores a fuzzed geohash and visibility preference from signup", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, "/api/users/register", %{
          "user" =>
            valid_user_attributes(email: email)
            |> Map.merge(%{
              "raw_lat" => 30.2672,
              "raw_lon" => -97.7431,
              "settings" => %{"visibility_preference" => "events-only"}
            })
        })

      assert %{"data" => %{"user" => user_data}} = json_response(conn, 201)
      assert is_binary(user_data["geohash"])
      assert user_data["visibility_preference"] == "events-only"
      assert user_data["default_coords_set"] == true
      assert user_data["user_coords_set"] == false

      user = Accounts.get_user_by_email(email)
      assert is_binary(user.geohash)
      assert user.default_coords_set == true
      assert user.user_coords_set == false
      assert user.exact_coords_set == false
      {lat, lon} = Geohash.decode(user.geohash)
      assert is_float(lat)
      assert is_float(lon)
    end

    test "stores and returns the selected ethnicity", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, "/api/users/register", %{
          "user" =>
            valid_user_attributes(email: email)
            |> Map.put("ethnicity", "Hispanic / Latino")
        })

      assert %{"data" => %{"user" => user_data}} = json_response(conn, 201)
      assert user_data["ethnicity"] == "Hispanic / Latino"

      user = Accounts.get_user_by_email(email)
      assert user.ethnicity == "Hispanic / Latino"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, "/api/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert is_map(errors)
    end
  end
end
