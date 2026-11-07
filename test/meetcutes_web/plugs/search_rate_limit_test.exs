defmodule MeetcutesWeb.Plugs.SearchRateLimitTest do
  use MeetcutesWeb.ConnCase, async: false

  alias MeetcutesWeb.Plugs.SearchRateLimit

  setup do
    previous = Application.get_env(:meetcutes, :rate_limit_enabled)
    Application.put_env(:meetcutes, :rate_limit_enabled, true)

    on_exit(fn ->
      Application.put_env(:meetcutes, :rate_limit_enabled, previous)
    end)

    :ok
  end

  test "allows ten searches and rejects the eleventh with the standard payload" do
    user_id = Ecto.ULID.generate()
    conn = conn_with_identity(user_id, {10, 40, 0, 1})

    allowed =
      Enum.map(1..10, fn _ ->
        SearchRateLimit.call(conn, [])
      end)

    refute Enum.any?(allowed, & &1.halted)

    denied = SearchRateLimit.call(conn, [])

    assert denied.halted
    assert denied.status == 429
    assert get_resp_header(denied, "retry-after") != []

    assert %{
             "success" => false,
             "msg" => "Rate limit exceeded. Please wait a moment before searching again."
           } = Jason.decode!(denied.resp_body)
  end

  test "the authenticated user key is enforced independently of the IP key" do
    user_id = Ecto.ULID.generate()

    allowed =
      Enum.map(1..10, fn index ->
        conn = conn_with_identity(user_id, {10, 41, 0, index})
        SearchRateLimit.call(conn, [])
      end)

    refute Enum.any?(allowed, & &1.halted)

    denied =
      SearchRateLimit.call(
        conn_with_identity(user_id, {10, 41, 0, 99}),
        []
      )

    assert denied.halted
    assert denied.status == 429
  end

  test "uses the IP key when no authenticated user is assigned" do
    conn = conn_with_identity(nil, {10, 42, 0, 1})

    allowed =
      Enum.map(1..10, fn _ ->
        SearchRateLimit.call(conn, [])
      end)

    refute Enum.any?(allowed, & &1.halted)
    assert SearchRateLimit.call(conn, []).status == 429
  end

  test "passes through when the limiter is disabled" do
    Application.put_env(:meetcutes, :rate_limit_enabled, false)

    conn = conn_with_identity(Ecto.ULID.generate(), {10, 43, 0, 1})

    result =
      Enum.reduce(1..50, conn, fn _, acc ->
        SearchRateLimit.call(acc, [])
      end)

    refute result.halted
    assert result.status == nil
  end

  defp conn_with_identity(user_id, remote_ip) do
    conn = build_conn()
    conn = %{conn | remote_ip: remote_ip}

    if is_binary(user_id) do
      Plug.Conn.assign(conn, :current_user, %{id: user_id})
    else
      conn
    end
  end
end
