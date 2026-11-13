defmodule MeetcutesWeb.Plugs.UploadRateLimitTest do
  use MeetcutesWeb.ConnCase, async: false

  alias MeetcutesWeb.Plugs.UploadRateLimit

  setup do
    previous = Application.get_env(:meetcutes, :rate_limit_enabled)
    Application.put_env(:meetcutes, :rate_limit_enabled, true)

    on_exit(fn ->
      Application.put_env(:meetcutes, :rate_limit_enabled, previous)
    end)

    :ok
  end

  test "allows ten uploads and rejects the eleventh with 429" do
    conn = upload_conn(Ecto.ULID.generate())

    allowed = Enum.map(1..10, fn _ -> UploadRateLimit.call(conn, []) end)

    refute Enum.any?(allowed, & &1.halted)

    denied = UploadRateLimit.call(conn, [])

    assert denied.halted
    assert denied.status == 429
    assert get_resp_header(denied, "retry-after") != []

    assert %{"success" => false, "code" => "upload_rate_limited"} =
             Jason.decode!(denied.resp_body)
  end

  test "does not limit non-upload profile updates" do
    conn = %{
      (build_conn()
       |> Plug.Conn.assign(:current_user, %{id: Ecto.ULID.generate()}))
      | params: %{"first_name" => "Ada"}
    }

    results = Enum.map(1..20, fn _ -> UploadRateLimit.call(conn, []) end)

    refute Enum.any?(results, & &1.halted)
  end

  test "passes through when the limiter is disabled" do
    Application.put_env(:meetcutes, :rate_limit_enabled, false)
    conn = upload_conn(Ecto.ULID.generate())

    result =
      Enum.reduce(1..20, conn, fn _, acc ->
        UploadRateLimit.call(acc, [])
      end)

    refute result.halted
    assert result.status == nil
  end

  defp upload_conn(user_id) do
    %{
      (build_conn()
       |> Plug.Conn.assign(:current_user, %{id: user_id}))
      | params: %{
          "file" => %Plug.Upload{path: "photo.png", filename: "photo.png"}
        }
    }
  end
end
