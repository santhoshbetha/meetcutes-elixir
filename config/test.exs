import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :meetcutes, Meetcutes.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "meetcutes_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :meetcutes, MeetcutesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tD010ZIpaO/bl1uPDAHsc2ztfiPo4xxMeXa5ddlM13BhHMMfxNQcO9XwtP6Ye8LI",
  server: false

# In test we don't send emails
config :meetcutes, Meetcutes.Mailer, adapter: Swoosh.Adapters.Test

# Never touch S3/R2 from tests.
config :meetcutes, :image_storage, Meetcutes.Uploads.TestStorage
config :meetcutes, :max_upload_bytes, 8_000_000

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Keep tz test builds stable; the periodic updater can mutate bundled tzdata versions.
config :meetcutes, :start_tz_updater, false

# Run Oban without queues, plugins, or the Stager during tests. Those processes
# are not owned by the Ecto SQL sandbox, so letting them poll the database
# raises DBConnection.OwnershipError for every test run. Jobs can still be
# exercised explicitly with Oban.Testing (perform_job/assert_enqueued).
config :meetcutes, Oban, testing: :manual

# Rate limiting is exercised directly in its plug test; keep the rest of the
# suite isolated from shared ETS buckets (all test requests share localhost).
config :meetcutes, :rate_limit_enabled, false

# Billing is fully mocked in tests: no Stripe network calls and no R2 writes.
config :meetcutes, :stripe_client, Meetcutes.Billing.StripeClientStub
config :meetcutes, :invoice_storage, Meetcutes.Billing.InvoiceStorageStub

config :meetcutes, :stripe,
  webhook_secret: "whsec_test",
  frontend_url: "http://localhost:5180"
