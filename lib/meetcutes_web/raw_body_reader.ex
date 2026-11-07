defmodule MeetcutesWeb.RawBodyReader do
  @moduledoc """
  Caches the raw request body before Plug.Parsers decodes it.

  Stripe signs the exact bytes it sends, so the webhook controller must verify
  the original payload rather than a re-encoded JSON map.
  """

  def read_body(conn, opts) do
    case read_full_body(conn, opts, []) do
      {:ok, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def raw_body(conn), do: conn.private[:raw_body] || ""

  defp read_full_body(conn, opts, acc) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, IO.iodata_to_binary([acc, body]), conn}

      {:more, body, conn} ->
        read_full_body(conn, opts, [acc, body])

      {:error, reason} ->
        {:error, reason}
    end
  end
end
