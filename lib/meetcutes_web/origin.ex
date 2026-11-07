defmodule MeetcutesWeb.Origin do
  @moduledoc """
  Runtime allow-list for browser origins.

  Both `CORSPlug` (HTTP) and the Phoenix websocket transport read this module,
  so a Coolify/Kamal deployment only has to set `CORS_ORIGINS` once:

      CORS_ORIGINS=https://app.meetcutes.us,https://meetcutes.us

  Entries may contain `*` wildcards (for example `https://*.meetcutes.us`).
  When the variable is not configured we fall back to the local development
  ports plus the production domains.
  """

  @default_origins [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:5180",
    "http://127.0.0.1:5180",
    "https://localhost",
    "capacitor://localhost",
    "https://meetcutes.us",
    "https://*.meetcutes.us"
  ]

  @doc """
  Returns the configured origins, or the safe defaults.
  """
  def allowed_origins do
    case Application.get_env(:meetcutes, :cors_origins) do
      origins when is_list(origins) and origins != [] -> origins
      _other -> @default_origins
    end
  end

  @doc """
  Origin list prepared for `CORSPlug` (exact strings plus compiled wildcards).
  """
  def cors_origins do
    Enum.map(allowed_origins(), &matcher/1)
  end

  @doc """
  `check_origin` callback for the Phoenix websocket transport.

  Phoenix passes the parsed `%URI{}` of the `Origin` request header.
  """
  def allowed?(%URI{} = uri) do
    origin = to_origin(uri)
    origin != "" and Enum.any?(allowed_origins(), &matches?(origin, &1))
  end

  def allowed?(_other), do: false

  defp matcher("*"), do: "*"

  defp matcher(pattern) when is_binary(pattern) do
    if String.contains?(pattern, "*") do
      compile_pattern(pattern)
    else
      pattern
    end
  end

  defp matcher(other), do: other

  defp matches?(origin, %Regex{} = regex), do: Regex.match?(regex, origin)
  defp matches?(_origin, "*"), do: true

  defp matches?(origin, pattern) when is_binary(pattern) do
    if String.contains?(pattern, "*") do
      pattern |> compile_pattern() |> Regex.match?(origin)
    else
      origin == pattern
    end
  end

  defp matches?(_origin, _other), do: false

  defp compile_pattern(pattern) do
    escaped = pattern |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.compile!("^" <> escaped <> "$")
  end

  defp to_origin(%URI{scheme: scheme, host: host} = uri) when is_binary(host) do
    scheme = scheme || "http"
    port = if uri.port && uri.port != default_port(scheme), do: ":#{uri.port}", else: ""
    "#{scheme}://#{host}#{port}"
  end

  defp to_origin(_uri), do: ""

  defp default_port("https"), do: 443
  defp default_port(_scheme), do: 80
end
