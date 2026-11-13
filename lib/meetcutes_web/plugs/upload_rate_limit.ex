defmodule MeetcutesWeb.Plugs.UploadRateLimit do
  @moduledoc """
  Per-user protection for avatar and gallery upload endpoints.

  The token bucket allows a burst of ten uploads and refills at ten uploads per
  minute steady-state. Non-upload profile updates pass through untouched.
  """

  @behaviour Plug

  require Logger

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Meetcutes.RateLimit

  @refill_rate 1
  @capacity 60
  @upload_cost 6
  @message "Too many photo uploads. Please wait a moment before trying again."

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Application.get_env(:meetcutes, :rate_limit_enabled, true) and
         upload_request?(conn.params) do
      enforce(conn)
    else
      conn
    end
  end

  defp enforce(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} when is_binary(user_id) ->
        key = "upload:user:#{user_id}"

        case RateLimit.hit(key, @refill_rate, @capacity, @upload_cost) do
          {:allow, _count} ->
            conn

          {:deny, retry_after_ms} ->
            retry_after_seconds = max(div(retry_after_ms + 999, 1000), 1)

            conn
            |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
            |> put_status(:too_many_requests)
            |> json(%{success: false, code: "upload_rate_limited", msg: @message})
            |> halt()
        end

      _ ->
        conn
    end
  rescue
    error ->
      # Never turn limiter infrastructure failure into a 500 for the caller.
      Logger.error(
        "Upload rate limiter unavailable; allowing request: " <>
          Exception.message(error)
      )

      conn
  end

  defp upload_request?(params) when is_map(params) do
    upload?(params["avatar"]) or
      upload?(params["banner"]) or
      upload?(params["file"]) or
      upload?(params["image"]) or
      nested_upload?(params["user"])
  end

  defp upload_request?(_params), do: false

  defp nested_upload?(params) when is_map(params) do
    upload?(params["avatar"]) or
      upload?(params["banner"]) or
      upload?(params["file"]) or
      upload?(params["image"])
  end

  defp nested_upload?(_params), do: false

  defp upload?(%Plug.Upload{}), do: true
  defp upload?(_value), do: false
end
