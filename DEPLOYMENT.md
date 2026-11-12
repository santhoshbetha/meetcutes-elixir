# MeetCutes Deployment Guide

This guide covers the production topology for the MeetCutes platform:

- **Frontend:** React/Vite bundle on Cloudflare Pages/Workers via Wrangler.
- **API:** Elixir/Phoenix release in Docker, orchestrated by Kamal 2.
- **Database:** PostgreSQL 16 with PostGIS.
- **Background jobs:** Oban.
- **Email:** Swoosh with the Resend HTTP adapter.
- **Media:** Cloudflare R2 (or any S3-compatible bucket).
- **Payments:** Stripe Checkout, Customer Portal, and signed webhooks.
- **Edge proxy/TLS:** `kamal-proxy`.

No credentials belong in this repository. Keep production values in `.kamal/secrets`, the platform secret store, or the CI/CD environment.

## 1. Production topology

```text
Browser
  |
  | HTTPS
  v
Cloudflare Pages/Workers (frontend)
  |
  | HTTPS + WebSocket
  v
kamal-proxy (TLS, health checks)
  |
  v
Phoenix API container (Docker, non-root)
  |-- PostgreSQL 16 + PostGIS
  |-- Oban queues
  |-- Resend email
  |-- Cloudflare R2 / S3
  |-- Stripe API + webhooks
```

DNS:

- `meetcutes.us` and `www.meetcutes.us` → Cloudflare frontend.
- `api.meetcutes.us` → the Kamal server and `kamal-proxy`.

## 2. Prerequisites

- A Linux host with Docker and SSH access for Kamal.
- A container registry account (the examples use `ghcr.io`).
- Kamal 2 installed locally:
  ```bash
  gem install kamal
  kamal version
  ```
- A PostgreSQL 16 database with the PostGIS extension available.
- A Cloudflare account for the frontend and R2 bucket.
- A Resend account and verified sending domain.
- A Stripe account with webhook access.
- Ports 80/443 open on the API host; port 5432 private.

## 3. Backend secrets

Copy the example and fill in production values:

```bash
cp .kamal/secrets.example .kamal/secrets
chmod 600 .kamal/secrets
```

Minimum required values:

```bash
KAMAL_REGISTRY_PASSWORD='...'
DATABASE_URL='ecto://USER:PASSWORD@DB_HOST:5432/meetcutes_prod?sslmode=require'
SECRET_KEY_BASE='...'
DASHBOARD_USER='admin'
DASHBOARD_PASSWORD='...'
STRIPE_SECRET_KEY='sk_live_...'
STRIPE_WEBHOOK_SECRET='whsec_...'
RESEND_API_KEY='re_...'
MCP_ADMIN_SECRET_KEY='...'
AWS_ACCESS_KEY_ID='...'
AWS_SECRET_ACCESS_KEY='...'
CLOUDFLARE_ACCOUNT_ID='...'
```

Generate high-entropy values locally:

```bash
mix phx.gen.secret                 # SECRET_KEY_BASE
openssl rand -base64 48            # DASHBOARD_PASSWORD
openssl rand -hex 32               # MCP_ADMIN_SECRET_KEY
```

`.kamal/secrets` is a local shell fragment evaluated by Kamal. It is ignored by Git and must never be baked into an image.

## 4. Backend image

The multi-stage `Dockerfile`:

1. Uses `hexpm/elixir:1.17.2-erlang-27.0.1-alpine-3.20.2` to fetch and compile dependencies.
2. Copies `config`, `priv`, `lib`, and `rel`.
3. Compiles the application, runs `mix assets.deploy`, and builds an OTP release.
4. Copies only the release into a minimal Alpine runtime image.
5. Runs as `nobody` with `PHX_SERVER=true` and `ERL_CRASH_DUMP=/tmp/erl_crash.dump`.

The release boot overlay is `rel/overlays/bin/server`. It runs `Meetcutes.Release.migrate/0` before starting the server, then Phoenix listens on the internal port.

Useful local checks:

```bash
docker build -t meetcutes-api .
docker run --rm -p 4000:4000 \
  -e DATABASE_URL='ecto://postgres:postgres@host.docker.internal/meetcutes_dev' \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  meetcutes-api
```

## 5. Kamal 2 API deployment

Run every Kamal command from the repository root containing `config/deploy.yml`.

Review and update:

- `image`
- `servers.web.hosts`
- `proxy.host`
- `registry.server` / `registry.username`
- `builder.arch`
- `env.clear` and `env.secret`
- Optional Grafana Loki logging settings

Deploy:

```bash
kamal setup        # first deployment
kamal deploy       # subsequent deployments
kamal details
kamal app logs -f
kamal rollback     # revert to the previous image
```

`config/deploy.yml` uses `kamal-proxy` with TLS, forwarded client headers, and a `/health` probe. The proxy switches traffic only after the new container returns a healthy response. `deploy_timeout` allows the migration step to finish.

### Health and migration gate

- `/health` — database and migration readiness; returns `200` only when the schema is current.
- `/api/health` — application health endpoint used by smoke checks.

If the database is unreachable or a migration is pending, the boot/health gate fails and Kamal does not route traffic to the new container.

## 6. Database

Provision PostgreSQL 16 and enable PostGIS:

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

Use a managed database when possible. Restrict the database port to the API host or private network. Keep `sslmode=require` in `DATABASE_URL` unless the connection is inside a trusted private network.

Migrations run automatically through the release overlay. For a manual release:

```bash
_build/prod/rel/meetcutes/bin/meetcutes eval "Meetcutes.Release.migrate()"
_build/prod/rel/meetcutes/bin/meetcutes start
```

## 7. Frontend deployment on Cloudflare

The frontend is a static Vite bundle deployed through Wrangler. `wrangler.toml` publishes `./dist` as static assets with SPA fallback for React Router.

```bash
cd meetcutes-fe
npm ci
npm run cf:whoami
npm run cf:preview
npm run cf:deploy
```

Set these build-time values in Cloudflare Pages or the shell running Wrangler:

```env
VITE_API_URL=https://api.meetcutes.us
VITE_WS_URL=wss://api.meetcutes.us/socket
VITE_SITE_URL=https://meetcutes.us
VITE_REACT_APP_GEOAPIFY_API_KEY=...
VITE_MAINTENANCE_MODE=false
VITE_ASSET_HOST=https://assets.meetcutes.us
VITE_CDN_URL=https://assets.meetcutes.us
```

Vite inlines `VITE_*` values at build time. Rebuild and redeploy after changing them.

Attach `meetcutes.us` and `www.meetcutes.us` to the Cloudflare project and configure the API CORS allow-list:

```env
CORS_ORIGINS=https://meetcutes.us,https://www.meetcutes.us
```

The API socket must also be reachable at `wss://api.meetcutes.us/socket`.

## 8. Storage, email, and payments

### Cloudflare R2 / S3

Set the R2/S3 credentials and endpoint values in `.kamal/secrets`:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_S3_BUCKET`
- `AWS_S3_HOST` (or `CLOUDFLARE_ACCOUNT_ID` to derive it)
- `AWS_REGION` (`auto` for R2)
- `AWS_S3_ASSET_HOST` (public CDN/custom domain)

Uploads are validated by magic bytes before storage. The API never stores raw media in PostgreSQL.

### Resend email

Production uses the native Swoosh Resend adapter:

- `RESEND_API_KEY`
- `MAIL_FROM_EMAIL` (defaults to `noreply@meetcutes.us`)

Verify the sending domain in Resend before launch. Confirmation and reset links use `FRONTEND_URL`.

### Stripe

Configure:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- Optional `STRIPE_SUCCESS_URL`, `STRIPE_CANCEL_URL`, `STRIPE_PORTAL_RETURN_URL`

The webhook is `POST /api/v1/payments/webhook`. Register the production URL in Stripe and keep the signing secret only in `.kamal/secrets`. Membership invoices are stored in R2; `INVOICE_STORAGE=local` skips that for local/E2E runs.

## 9. MCP administrative API

The platform is administered through the protected MCP command endpoint:

```http
POST /api/v1/admin/mcp-action
Content-Type: application/json
X-MCP-Admin-Key: <MCP_ADMIN_SECRET_KEY>
```

Example actions:

- `get_system_stats`
- `toggle_maintenance`
- `toggle_paywall`
- `update_user_status`
- `force_match_count`
- `push_notification`
- `set_global_announcement`

The endpoint rejects missing or incorrect keys with `401`. Keep `MCP_ADMIN_SECRET_KEY` server-side and never expose it to the browser or an LLM prompt. The request/response tool definition lives in `mcp-config.json`.

## 10. Verification checklist

Backend:

```bash
mix deps.unlock --unused
mix compile --warnings-as-errors
mix test
mix precommit
```

Frontend:

```bash
npm ci
npx eslint .
npm run build
npx playwright test
```

Smoke checks after deployment:

1. `GET https://api.meetcutes.us/health` returns `200`.
2. `GET https://api.meetcutes.us/api/health` returns `200`.
3. Registration sends a Resend confirmation email.
4. Login returns a bearer token and the dashboard loads.
5. Profile image upload reaches R2 and returns a public URL.
6. A Stripe webhook is accepted and an invoice row is created.
7. Oban queues are processing and no failed jobs accumulate.
8. The frontend deep link `/dashboard/search` loads after a hard refresh.
9. Playwright signup, login, discovery, and notification flows pass.

## 11. Secret hygiene

- `.env`, `.env.*`, `.kamal/secrets`, and `.kamal/secrets.*` are ignored.
- `.dockerignore` excludes `.git`, `.env*`, `.kamal`, `_build`, `deps`, `test`, and local upload folders.
- Never print secrets in CI logs.
- Rotate `SECRET_KEY_BASE`, database credentials, Stripe keys, Resend keys, and MCP keys after any suspected exposure.
