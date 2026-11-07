defmodule MeetcutesWeb.Plugs.McpAdminAuth do
  @moduledoc """
  Constant-time gate for the MCP administrative command API.

  The shared secret is read from runtime configuration and is intentionally
  independent from user bearer tokens. Requests without a match are stopped
  before any controller action can touch application state or the database.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @header "x-mcp-admin-key"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    expected = Application.get_env(:meetcutes, :mcp_admin_secret_key)
    provided = conn |> get_req_header(@header) |> List.first()

    if valid_secret?(expected, provided) do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        status: "error",
        message: "Unauthorized: invalid MCP admin key."
      })
      |> halt()
    end
  end

  defp valid_secret?(expected, provided)
       when is_binary(expected) and expected != "" and is_binary(provided) do
    byte_size(expected) == byte_size(provided) and
      Plug.Crypto.secure_compare(expected, provided)
  end

  defp valid_secret?(_expected, _provided), do: false
end
