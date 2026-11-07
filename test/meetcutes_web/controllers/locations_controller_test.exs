defmodule MeetcutesWeb.LocationsControllerTest do
  use MeetcutesWeb.ConnCase, async: true

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Locations

  setup %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn}
  end

  describe "GET /api/v1/locations/autocomplete" do
    test "returns nearby locations nearest first and collapses duplicates", %{conn: conn} do
      {:ok, near} =
        Locations.create_location(%{
          name: "Near Venue",
          street: "1 Congress Ave",
          locality: "Austin",
          state: "TX",
          postal_code: "78701",
          latitude: 30.2672,
          longitude: -97.7431
        })

      {:ok, duplicate} =
        Locations.create_location(%{
          name: "Near Venue Annex",
          street: "1 Congress Ave",
          locality: "Austin",
          state: "TX",
          postal_code: "78701",
          latitude: 30.2673,
          longitude: -97.7432
        })

      {:ok, farther} =
        Locations.create_location(%{
          name: "Farther Venue",
          street: "500 E 5th St",
          locality: "Austin",
          state: "TX",
          postal_code: "78701",
          latitude: 30.2672,
          longitude: -97.70
        })

      {:ok, _dallas} =
        Locations.create_location(%{
          name: "Dallas Venue",
          street: "1 Main St",
          locality: "Dallas",
          state: "TX",
          postal_code: "75201",
          latitude: 32.7767,
          longitude: -96.7970
        })

      conn =
        get(
          conn,
          ~p"/api/v1/locations/autocomplete?lat=30.2672&lng=-97.7431&distance=160934"
        )

      assert %{"status" => "success", "data" => %{"locations" => locations}} =
               json_response(conn, 200)

      ids = Enum.map(locations, & &1["id"])
      assert near.id in ids
      assert farther.id in ids
      refute duplicate.id in ids
      refute Enum.any?(locations, &(&1["name"] == "Dallas Venue"))
      assert hd(ids) == near.id

      assert %{"street" => "1 Congress Ave", "city" => "Austin", "postal_code" => "78701"} =
               hd(locations)
    end

    test "defaults to a 150 mile radius", %{conn: conn} do
      {:ok, location} =
        Locations.create_location(%{
          name: "Austin Venue",
          street: "2 Congress Ave",
          locality: "Austin",
          state: "TX",
          postal_code: "78701",
          latitude: 30.2672,
          longitude: -97.7431
        })

      conn = get(conn, ~p"/api/v1/locations/autocomplete?lat=30.2672&lng=-97.7431")

      assert %{"data" => %{"locations" => [found]}} = json_response(conn, 200)
      assert found["id"] == location.id
    end

    test "rejects invalid coordinates", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/locations/autocomplete?lat=999&lng=-97.7431")

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["lat"]
    end

    test "requires authentication", %{conn: _conn} do
      conn = get(build_conn(), ~p"/api/v1/locations/autocomplete?lat=30&lng=-97")

      assert json_response(conn, 401)
    end
  end
end
