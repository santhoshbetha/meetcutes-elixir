defmodule MeetcutesWeb.Plugs.SearchRateLimit do
  @moduledoc """
  Dual-key token-bucket protection for search endpoints.

  Both the requester IP and the authenticated user id are checked. A bucket
  holds 60 tokens and each search costs 6, allowing ten searches immediately
  and refilling at ten searches per minute.
  """

  @behaviour Plug

  require Logger

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Meetcutes.RateLimit

  @refill_rate 1
  @capacity 60
  @search_cost 6
  @message "Rate limit exceeded. Please wait a moment before searching again."

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Application.get_env(:meetcutes, :rate_limit_enabled, true) do
      enforce(conn)
    else
      conn
    end
  end

  defp enforce(conn) do
    keys = [ip_key(conn) | user_keys(conn)]

    case Enum.find_value(keys, &check/1) do
      nil ->
        conn

      {_key, retry_after_ms} ->
        retry_after_seconds = max(div(retry_after_ms + 999, 1000), 1)

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> put_status(:too_many_requests)
        |> json(%{success: false, msg: @message})
        |> halt()
    end
  end

  defp check(key) do
    case RateLimit.hit(key, @refill_rate, @capacity, @search_cost) do
      {:allow, _count} -> nil
      {:deny, retry_after_ms} -> {key, retry_after_ms}
    end
  rescue
    error ->
      # Never turn a limiter infrastructure failure into a 500 for the caller.
      # Fail open, but leave a loud trail so a stale build/hot-reload gap is
      # visible in logs and gets fixed.
      Logger.error(
        "Search rate limiter unavailable; allowing request: " <>
          Exception.message(error)
      )

      nil
  end

  defp user_keys(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} when is_binary(user_id) -> ["search:user:#{user_id}"]
      _ -> []
    end
  end

  defp ip_key(conn) do
    "search:ip:#{client_ip(conn)}"
  end

  defp client_ip(conn) do
    case conn.remote_ip do
      ip when is_tuple(ip) -> ip |> :inet.ntoa() |> to_string()
      ip -> to_string(ip)
    end
  rescue
    _ -> "unknown"
  end
end
