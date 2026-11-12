# MeetCutes API

Elixir/Phoenix JSON API for MeetCutes: authentication, profiles, proximity discovery, events, attendance, discussions, notifications, transactional email, media uploads, and Stripe membership billing.

## Production stack

| Layer | Technology |
| --- | --- |
| Language/runtime | Elixir 1.17+, Erlang/OTP 27 |
| Web/API | Phoenix 1.8 JSON API |
| Database | PostgreSQL 16 with PostGIS enabled |
| Data layer | Ecto SQL |
| Background jobs | Oban |
| Email | Swoosh with Resend (native HTTP adapter) |
| Media storage | Cloudflare R2 / S3 via Waffle + ExAws |
| Payments | Stripe via Stripity Stripe |
| Realtime | Phoenix Channels and Presence |
| Deployment | Docker + Kamal 2 |

## Requirements

- Elixir 1.17 or newer.
- Erlang/OTP 27.
- PostgreSQL 16.
- PostGIS enabled in the production database.
- Node/npm is not required for the API runtime; the release image runs the compiled OTP application.

## Local setup

```bash
cp .env.example .env
mix setup
```

`mix setup` runs:

1. `mix deps.get`
2. `mix ecto.create`
3. `mix ecto.migrate`
4. `mix run priv/repo/seeds.exs`

The seeds are idempotent and create deterministic Austin demo accounts. The shared seed password is `Password123!`.

Start the API:

```bash
mix phx.server
```

Local endpoints:

- API: <http://localhost:4000>
- Health: <http://localhost:4000/api/health>
- Swoosh mailbox (development): <http://localhost:4000/dev/mailbox>
- LiveDashboard: <http://localhost:4000/dashboard>

## Environment

Copy `.env.example` to `.env` for development. The most important variables are:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string. |
| `SECRET_KEY_BASE` | Cookie/token signing secret. Generate with `mix phx.gen.secret`. |
| `FRONTEND_URL` | Frontend origin used in confirmation, reset, and billing redirects. |
| `PHX_HOST` / `PORT` | Public host and internal listener port. |
| `CORS_ORIGINS` | Comma-separated browser origins allowed to call the API and socket. |
| `RESEND_API_KEY` | Resend API key for transactional email. |
| `MAIL_FROM_EMAIL` | Verified sender address. |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | S3-compatible credentials. |
| `AWS_S3_BUCKET` / `AWS_S3_HOST` / `AWS_REGION` | R2 or S3 storage configuration. |
| `AWS_S3_ASSET_HOST` | Public CDN/asset host for uploaded media. |
| `CLOUDFLARE_ACCOUNT_ID` | Used to derive the R2 endpoint when `AWS_S3_HOST` is unset. |
| `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` | Stripe membership billing. |
| `MCP_ADMIN_SECRET_KEY` | High-entropy key for the MCP administrative command API. |
| `DASHBOARD_USER` / `DASHBOARD_PASSWORD` | LiveDashboard basic-auth credentials in production. |
| `RATE_LIMIT_ENABLED` | Enables the search rate limiter. |
| `OBAN_*_CONCURRENCY` | Queue concurrency for default, events, and mailer jobs. |
| `INVOICE_STORAGE=local` | Skips R2 invoice uploads during local/E2E runs. |

Never commit `.env`, `.env.*`, `.kamal/secrets`, or provider credentials.

## Common commands

```bash
mix setup               # dependencies, database, migrations, seeds
mix phx.server          # development server
mix ecto.reset          # drop, recreate, migrate, seed
mix test                # test suite
mix precommit           # compile --warning-as-errors, deps.unlock --unused, format, test
mix deps.unlock --unused
mix compile --warnings-as-errors
mix release             # production OTP release
```

## API surface

All authenticated endpoints use the opaque bearer token returned by `POST /api/users/login`:

```http
Authorization: Bearer <token>
```

Primary route groups:

- `/api/users/*` — registration, login, logout, confirmation, password reset, profile.
- `/api/v1/profiles/*` — profile read/update, handle availability, media slots.
- `/api/v1/relationships/*` — likes, dislikes, shortlist, blocks, and mutes.
- `/api/v1/events/*` — discovery, creation, updates, cancellation, join/leave, fatigue checks.
- `/api/search/*` and `/api/v1/search/*` — people and event search.
- `/api/v1/notifications/*` — inbox, unread count, and read state.
- `/api/v1/payments/*` — Stripe checkout, portal, and webhook handling.
- `/api/v1/admin/mcp-action` — protected administrative command API.
- `/api/v1/public/global-announcement` — public announcement banner.

## Architecture

```text
lib/meetcutes/            Domain contexts, schemas, workers, billing, uploads
lib/meetcutes_web/        Controllers, JSON views, plugs, channels, endpoint
priv/repo/                Migrations, seeds, and database helpers
priv/e2e/                 Deterministic E2E seed and Oban inspection helpers
config/                    Compile-time, runtime, and Kamal deployment config
rel/overlays/              Release boot overlay (migrations + server start)
test/                      ExUnit suites
```

### Background jobs

Oban runs the default, events, and mailer queues. Scheduled work includes profile match-count refreshes and notification delivery. Tests run Oban in manual mode so workers can be asserted without polling the database.

### Media

Avatar, banner, and event media uploads are validated by magic bytes and stored through Waffle in Cloudflare R2 or S3. Tests use an in-memory storage adapter and never touch a live bucket.

### Email

Production uses Swoosh's native Resend adapter with `RESEND_API_KEY`. Confirmation and password-reset links point at `FRONTEND_URL`.

### Payments

Stripe checkout and customer-portal sessions are created server-side. The webhook verifies the signing secret and records invoices atomically. Development and test can run without a live Stripe account.

### Realtime

Phoenix Channels provide event attendee updates, discussion streams, presence, and per-user notification topics. The frontend connects with the same bearer token used for HTTP requests.

## Testing

```bash
mix test
mix precommit
```

The frontend Playwright suite starts this API on port `4100` and uses `priv/e2e/seed.exs` plus `priv/e2e/inspect_oban.exs` for deterministic data and job inspection.

## Deployment

Production runs the API as a multi-stage Docker image behind Kamal 2 and `kamal-proxy`, with PostgreSQL 16/PostGIS, Cloudflare R2, Resend, Stripe, and Oban. The release boot overlay runs migrations before starting the server, and `/health` gates traffic until the database and migrations are ready.

See [DEPLOYMENT.md](DEPLOYMENT.md) for the complete Kamal, secrets, Cloudflare frontend, storage, email, Stripe, and verification guide.
