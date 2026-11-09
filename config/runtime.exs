import Config

# Load local environment variables before anything else reads them.
#
# This file is evaluated after compilation, so the Dotenv dependency is on the
# code path here (it is not yet available while `config/config.exs` runs).
# `load!/1` exports the values into `System.get_env/1`; `load/1` would only
# parse the file and return a struct.
if config_env() in [:dev, :test] do
  env_file = Path.expand("../.env", __DIR__)

  if File.exists?(env_file) and Code.ensure_loaded?(Dotenv) do
    Dotenv.load!(env_file)
  end
end

# Waffle / ExAws storage (Cloudflare R2 is S3-compatible).
#
# These values must be read at runtime: in development they come from `.env`,
# and in production they come from the deploy environment. Values are trimmed
# because Dotenv keeps a trailing `\r` when the file has CRLF line endings.
get_env = fn key ->
  case System.get_env(key) do
    nil ->
      nil

    value ->
      case String.trim(value) do
        "" -> nil
        trimmed -> trimmed
      end
  end
end

get_int = fn key, default ->
  case get_env.(key) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {parsed, ""} -> parsed
        _ -> default
      end
  end
end

case get_env.("RATE_LIMIT_ENABLED") do
  "false" -> config :meetcutes, :rate_limit_enabled, false
  "true" -> config :meetcutes, :rate_limit_enabled, true
  _ -> :ok
end

truthy? = fn value ->
  value
  |> String.downcase()
  |> then(&(&1 in ~w(true 1 yes on)))
end

case get_env.("PAYMENT_FEATURE_ENABLED") do
  nil -> :ok
  value -> config :meetcutes, :payment_feature_enabled, truthy?.(value)
end

case get_env.("MAINTENANCE_MODE_ACTIVE") do
  nil -> :ok
  value -> config :meetcutes, :maintenance_mode_active, truthy?.(value)
end

config :meetcutes, :mcp_admin_secret_key, get_env.("MCP_ADMIN_SECRET_KEY")

dashboard_password =
  get_env.("DASHBOARD_PASSWORD") ||
    if config_env() == :prod do
      raise "DASHBOARD_PASSWORD environment variable is required in production"
    else
      "secret_pass_change_me"
    end

config :meetcutes, :dashboard_auth,
  username: get_env.("DASHBOARD_USER") || "admin",
  password: dashboard_password

aws_access_key_id = get_env.("AWS_ACCESS_KEY_ID") || get_env.("R2_ACCESS_KEY_ID")
aws_secret_access_key = get_env.("AWS_SECRET_ACCESS_KEY") || get_env.("R2_SECRET_ACCESS_KEY")

aws_s3_host =
  get_env.("AWS_S3_HOST") ||
    case get_env.("CLOUDFLARE_ACCOUNT_ID") do
      nil -> nil
      account_id -> "#{account_id}.r2.cloudflarestorage.com"
    end

aws_s3_port =
  case get_env.("AWS_S3_PORT") do
    nil -> nil
    port -> String.to_integer(port)
  end

aws_s3_bucket = get_env.("AWS_S3_BUCKET") || "meetcutes-images"
aws_s3_scheme = get_env.("AWS_S3_SCHEME") || "https://"

# Waffle builds public URLs as `asset_host + "/" + key`. Fall back to the R2
# endpoint (path-style) so uploads never silently point at AWS when the asset
# host is not explicitly configured.
aws_asset_host =
  get_env.("AWS_S3_ASSET_HOST") ||
    if aws_s3_host do
      "#{aws_s3_scheme}#{aws_s3_host}/#{aws_s3_bucket}"
    end

config :waffle,
  storage: Waffle.Storage.S3,
  bucket: aws_s3_bucket,
  asset_host: aws_asset_host

config :ex_aws,
  access_key_id: aws_access_key_id,
  secret_access_key: aws_secret_access_key,
  region: get_env.("AWS_REGION") || "auto",
  s3: [
    scheme: aws_s3_scheme,
    host: aws_s3_host,
    port: aws_s3_port
  ]

# Stripe membership billing. The secret key is read at runtime so test/dev
# never require a live Stripe account.
config :stripity_stripe, api_key: get_env.("STRIPE_SECRET_KEY")

config :meetcutes, :stripe,
  webhook_secret: get_env.("STRIPE_WEBHOOK_SECRET"),
  frontend_url: get_env.("FRONTEND_URL"),
  success_url: get_env.("STRIPE_SUCCESS_URL"),
  cancel_url: get_env.("STRIPE_CANCEL_URL"),
  portal_return_url: get_env.("STRIPE_PORTAL_RETURN_URL")

if get_env.("INVOICE_STORAGE") == "local" do
  config :meetcutes, :invoice_storage, Meetcutes.Billing.InvoiceStorage.Local
end

# Origins allowed to call the JSON API and open the Phoenix websocket.
#
# Coolify/Kamal deployments set `CORS_ORIGINS` to a comma-separated list, e.g.
#
#     CORS_ORIGINS=https://app.meetcutes.us,https://meetcutes.us
#
# When the variable is absent, `MeetcutesWeb.Origin` falls back to the local
# development ports plus the production domains.
cors_origins =
  case get_env.("CORS_ORIGINS") do
    nil ->
      nil

    value ->
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
  end

if cors_origins not in [nil, []] do
  config :meetcutes, :cors_origins, cors_origins
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/meetcutes start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :meetcutes, MeetcutesWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Structured JSON logs for container aggregators (Vector, Loki, Papertrail).
  # `request_id` comes from Plug.RequestId and `user_id` is added by the API
  # auth plug and channel join handlers.
  config :logger, :default_handler,
    formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id, :user_id]}

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  # Hosted Postgres providers (including the ones commonly used with Coolify and
  # Kamal) require TLS. Accept either the standard libpq `sslmode` query
  # parameter or an explicit `DATABASE_SSL` override.
  parse_database_url = fn url ->
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")
    ssl_from_query = Map.get(query, "sslmode") in ["require", "verify-ca", "verify-full"]
    query = Map.drop(query, ["sslmode"])
    encoded_query = if map_size(query) == 0, do: nil, else: URI.encode_query(query)
    {%{uri | query: encoded_query} |> URI.to_string(), ssl_from_query}
  end

  {clean_database_url, ssl_from_url} = parse_database_url.(database_url)

  database_ssl =
    case get_env.("DATABASE_SSL") do
      nil -> ssl_from_url
      value -> value in ~w(true 1 yes on)
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Prefer the explicit production pool variable, then the legacy POOL_SIZE.
  # Keep a safe fallback so a malformed value cannot prevent the release boot.
  pool_size =
    (get_int.("DATABASE_POOL_SIZE", get_int.("POOL_SIZE", 10)) || 10)
    |> max(1)

  config :meetcutes, Meetcutes.Repo,
    url: clean_database_url,
    ssl: database_ssl,
    pool_size: pool_size,
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    ssl: [verify: :verify_none],
    socket_options: [keepalive: true] ++ maybe_ipv6

  # Queue concurrency can be tuned per container without rebuilding the image.
  # Defaults match config/config.exs and keep a single-container deployment
  # responsive while preventing Oban from monopolising database connections.
  config :meetcutes, Oban,
    queues: [
      default: max(get_int.("OBAN_DEFAULT_CONCURRENCY", 10), 1),
      events: max(get_int.("OBAN_EVENTS_CONCURRENCY", 5), 1),
      mailer: max(get_int.("OBAN_MAILER_CONCURRENCY", 5), 1)
    ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "meetcutes.us"
  port = String.to_integer(System.get_env("PORT") || "4000")
  url_scheme = get_env.("PHX_URL_SCHEME") || "https"
  default_url_port = if url_scheme == "https", do: 443, else: 80
  url_port = String.to_integer(get_env.("PHX_URL_PORT") || Integer.to_string(default_url_port))

  config :meetcutes, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :meetcutes, MeetcutesWeb.Endpoint,
    # This ensures url(~p"/...") generates the public host, even when the
    # container listens on a different internal port (Kamal/Coolify proxy).
    url: [host: host, scheme: url_scheme, port: url_port],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Configure frontend URL for generating links
  config :meetcutes, Meetcutes.Accounts,
    frontend_url: System.get_env("FRONTEND_URL", "https://meetcutes.us")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :meetcutes, MeetcutesWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :meetcutes, MeetcutesWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Production always sends through Resend's native HTTP API adapter. That
  # adapter posts straight to the Resend API with `RESEND_API_KEY`; it never
  # falls back to an SMTP relay (which was slower and added an extra hop).
  #
  # Gmail and Mailgun SMTP are retained only as explicit opt-in providers.
  resend_config = [
    adapter: Resend.Swoosh.Adapter,
    api_key:
      get_env.("RESEND_API_KEY") ||
        raise("RESEND_API_KEY environment variable is required for Resend")
  ]

  gmail_config = fn ->
    [
      adapter: Swoosh.Adapters.SMTP,
      relay: "smtp.gmail.com",
      username:
        System.get_env("GMAIL_USERNAME") ||
          raise("GMAIL_USERNAME environment variable is required for Gmail"),
      password:
        System.get_env("GMAIL_APP_PASSWORD") ||
          raise("GMAIL_APP_PASSWORD environment variable is required for Gmail"),
      tls: :always,
      auth: :always,
      port: 587
    ]
  end

  mailgun_config = fn ->
    [
      adapter: Swoosh.Adapters.SMTP,
      relay: "smtp.mailgun.org",
      username:
        System.get_env("MAILGUN_SMTP_USERNAME") ||
          raise("MAILGUN_SMTP_USERNAME environment variable is required for Mailgun"),
      password:
        System.get_env("MAILGUN_SMTP_PASSWORD") ||
          raise("MAILGUN_SMTP_PASSWORD environment variable is required for Mailgun"),
      tls: :always,
      auth: :always,
      port: 587
    ]
  end

  mailer_config =
    cond do
      get_env.("SMTP_PROVIDER") == "gmail" ->
        gmail_config.()

      get_env.("SMTP_PROVIDER") == "mailgun" ->
        mailgun_config.()

      is_nil(get_env.("SMTP_PROVIDER")) and get_env.("GMAIL_USERNAME") ->
        gmail_config.()

      is_nil(get_env.("SMTP_PROVIDER")) and get_env.("MAILGUN_SMTP_USERNAME") ->
        mailgun_config.()

      true ->
        resend_config
    end

  config :meetcutes, Meetcutes.Mailer, mailer_config

  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
