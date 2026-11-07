# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Environment variables for local development are loaded in
# `config/runtime.exs`, which runs after dependencies are compiled. Loading
# them here does not work reliably: this file is evaluated before the Dotenv
# module is available on the code path.

# Configure Elixir's time zone database
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure Tz HTTP client
config :tz, :http_client, Meetcutes.Tz.HTTPClient

# Configure ExAws to use Finch
config :ex_aws, http_client: Meetcutes.ExAws.FinchClient

# Waffle/ExAws storage credentials are environment-dependent and are therefore
# configured in `config/runtime.exs`.

# Configure custom mailer
config :meetcutes, Meetcutes.Emails.Mailer, enabled: true

config :meetcutes,
  ecto_repos: [Meetcutes.Repo],
  generators: [timestamp_type: :utc_datetime]

# The public annual membership fee in whole dollars. Existing accounts keep
# the amount stored in their accepted_onetime_fees_amount column.
config :meetcutes, :membership_fee_usd, 50

# Search API token-bucket limiter. Disable only in isolated test/E2E runs.
config :meetcutes, :rate_limit_enabled, true

# Runtime operational flags. These can be overridden by config/runtime.exs
# without rebuilding a release.
config :meetcutes, :payment_feature_enabled, true
config :meetcutes, :maintenance_mode_active, false
config :meetcutes, :mcp_admin_secret_key, nil

config :meetcutes, Meetcutes.Repo,
  migration_primary_key: [name: :id, type: :string],
  migration_foreign_key: [type: :string]

# Configures the endpoint
config :meetcutes, MeetcutesWeb.Endpoint,
  # 1 SERVER BINDING (Internal)
  # This makes the app listen on the container's local port (e.g. 4000)
  http: [port: System.get_env("PORT") || 4000],
  # 2. GENERATED URLS (External)
  # This makes url(~p"/...") return "https://example.com/..."
  url: [host: "localhost", port: 5173, scheme: "http"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MeetcutesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Meetcutes.PubSub

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :meetcutes, Meetcutes.Mailer, adapter: Swoosh.Adapters.Local

# Configure Oban for background job processing
config :meetcutes, Oban,
  repo: Meetcutes.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Meetcutes.Workers.AroundUserCountWorker}
     ]}
  ],
  engine: Oban.Engines.Basic,
  queues: [default: 10, events: 5, mailer: 5]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Geospatial configuration
config :geospatial, Geospatial.Service, service: Geospatial.Providers.Nominatim

config :geospatial, Geospatial.Providers.GoogleMaps,
  api_key: nil,
  fetch_place_details: true

config :geospatial, Geospatial.Providers.Nominatim,
  endpoint: "https://nominatim.openstreetmap.org",
  api_key: nil

config :geospatial, Geospatial.Providers.Pelias,
  endpoint: "https://api.geocode.earth",
  api_key: nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
