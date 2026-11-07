defmodule MeetcutesWeb.DashboardAuthTest do
  use MeetcutesWeb.ConnCase, async: false

  @username "admin"
  @password "secret_pass_change_me"

  test "rejects unauthenticated dashboard requests" do
    conn = get(build_conn(), "/dashboard")

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") != []
  end

  test "allows requests with the configured basic auth credentials" do
    authorization = Plug.BasicAuth.encode_basic_auth(@username, @password)

    conn =
      build_conn()
      |> put_req_header("authorization", authorization)
      |> get("/dashboard")

    # LiveDashboard may canonicalize /dashboard to its home page.
    assert conn.status in [200, 302]

    if conn.status == 302 do
      assert redirected_to(conn) =~ "/dashboard"
    end
  end
end
