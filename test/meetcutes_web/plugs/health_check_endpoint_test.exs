defmodule MeetcutesWeb.Plugs.HealthCheckEndpointTest do
  use MeetcutesWeb.ConnCase, async: false

  test "GET /health is served above the master router", %{conn: conn} do
    conn = get(conn, "/health")

    assert json_response(conn, 200) == %{"status" => "healthy"}
  end
end
