defmodule MeetcutesWeb.Plugs.HealthCheckTest do
  use Meetcutes.DataCase, async: false

  import Plug.Test

  alias MeetcutesWeb.Plugs.HealthCheck

  describe "GET /health" do
    test "returns 200 with a healthy payload when the database and migrations are ready" do
      conn =
        conn(:get, "/health")
        |> HealthCheck.call([])

      assert conn.status == 200
      assert conn.halted
      assert Jason.decode!(conn.resp_body) == %{"status" => "healthy"}
    end

    test "returns 503 and halts when a check fails" do
      conn =
        conn(:get, "/health")
        |> HealthCheck.call(check: fn -> {:error, :database} end)

      assert conn.status == 503
      assert conn.halted
      assert Jason.decode!(conn.resp_body) == %{"status" => "unhealthy"}
    end

    test "returns 503 when the checker raises" do
      conn =
        conn(:get, "/health")
        |> HealthCheck.call(check: fn -> raise "boom" end)

      assert conn.status == 503
      assert conn.halted
      assert Jason.decode!(conn.resp_body) == %{"status" => "unhealthy"}
    end
  end

  describe "non-health requests" do
    test "passes through untouched" do
      conn =
        conn(:get, "/api/v1/events")
        |> HealthCheck.call([])

      assert conn.status == nil
      refute conn.halted
    end
  end

  describe "pending/1" do
    test "returns only migrations that are not applied" do
      assert HealthCheck.pending([{:up, 1, "one"}, {:up, 2, "two"}]) == []
      assert HealthCheck.pending([{:up, 1, "one"}, {:down, 2, "two"}]) == [{:down, 2, "two"}]
    end
  end
end
