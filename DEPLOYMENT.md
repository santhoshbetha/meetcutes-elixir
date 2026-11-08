# MCP Administration

The MCP command API replaces a standalone web admin panel.

## Required environment

```env
MCP_ADMIN_SECRET_KEY=replace_with_a_long_random_secret
PAYMENT_FEATURE_ENABLED=true
MAINTENANCE_MODE_ACTIVE=false
```

`MCP_ADMIN_SECRET_KEY` is independent from user bearer tokens. Requests must send
it in the `X-MCP-Admin-Key` header. If the key is missing or incorrect, the
endpoint returns `401 Unauthorized` before touching application state.

## Endpoint

```text
POST /api/v1/admin/mcp-action
Content-Type: application/json
X-MCP-Admin-Key: <MCP_ADMIN_SECRET_KEY>
```

## Actions

### `get_system_stats`

Returns active users, total events, active Stripe subscriptions, and the Oban
failure backlog.

```json
{ "action": "get_system_stats" }
```

### `toggle_maintenance`

```json
{ "action": "toggle_maintenance", "params": { "value": true } }
```

### `toggle_paywall`

```json
{ "action": "toggle_paywall", "params": { "value": false } }
```

Both toggles update runtime configuration on the running node. In a
single-container deployment this changes behavior immediately without a
rebuild.

### `update_user_status`

Accepts a `user_id` or `email`, plus `user_state`:

```json
{
  "action": "update_user_status",
  "params": { "email": "member@example.com", "user_state": "suspended" }
}
```

Supported states: `active`, `inactive`, `suspended`, `delete`.

- `active` clears manual locks and restores access.
- `inactive`, `suspended`, and `delete` deactivate the account and revoke all
  stored session tokens.
- The update and token revocation are committed atomically.

### `force_match_count`

```json
{
  "action": "force_match_count",
  "params": { "user_id": "01J...", "count": 250 }
}
```

Sets `around_user_count` and its refresh timestamp directly, which is useful for
testing paywall thresholds.

### `push_notification`

Supports three target scopes:

```json
{
  "action": "push_notification",
  "params": {
    "target_scope": "all",
    "title": "Weekend meetup",
    "body": "A new gathering is happening near you."
  }
}
```

- `all` targets every active profile.
- `user` accepts `email` or `user_handle`.
- `area` accepts `center_lat`, `center_lng`, and `radius_miles`.

Rows are inserted atomically, then each user's `user_notifications:<user_id>`
Phoenix topic receives a `new_notification` event.

### `set_global_announcement`

```json
{
  "action": "set_global_announcement",
  "params": {
    "message": "Holiday giveaway: premium discovery is free this week."
  }
}
```

Sending an empty string or `null` clears the public banner. The public endpoint
is:

```text
GET /api/v1/public/global-announcement
```

It returns either `{"message":"..."}` or `{"message":null}`.

## Node.js MCP tool mapping

Use `mcp-config.json` as the tool definition. The server-side handler should:

1. Read `MEETCUTES_API_URL` and `MCP_ADMIN_SECRET_KEY` from its own environment.
2. POST the MCP arguments to `/api/v1/admin/mcp-action`.
3. Forward the JSON result as the tool response.
4. Never expose `MCP_ADMIN_SECRET_KEY` to the browser or LLM prompt.

Example handler:

```js
async function manageMeetcutesPlatform({ action, params = {} }) {
  const response = await fetch(
    `${process.env.MEETCUTES_API_URL}/api/v1/admin/mcp-action`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-MCP-Admin-Key": process.env.MCP_ADMIN_SECRET_KEY,
      },
      body: JSON.stringify({ action, params }),
    },
  );

  return await response.json();
}
```

## Curl smoke test

```bash
curl -X POST "$MEETCUTES_API_URL/api/v1/admin/mcp-action" \
  -H "Content-Type: application/json" \
  -H "X-MCP-Admin-Key: $MCP_ADMIN_SECRET_KEY" \
  -d '{"action":"get_system_stats"}'
```

---

# Self-Hosted Production Deployment (Kamal 2)

This section describes a single-server, zero-downtime launch of the Phoenix API
behind `kamal-proxy`. The frontend is a separate static container and can be
served by the same proxy or by any CDN.

## Deployment pieces

| Asset | Location | Purpose |
| --- | --- | --- |
| API image | `meetcutes-elixir/Dockerfile` | Multi-stage Elixir/OTP release, runs as `nobody` |
| Boot overlay | `meetcutes-elixir/rel/overlays/bin/server` | Runs `Meetcutes.Release.migrate` before `start` |
| Kamal config | `meetcutes-elixir/config/deploy.yml` | `kamal-proxy`, health checks, secrets |
| Health probe | `meetcutes-elixir/lib/meetcutes_web/plugs/health_check.ex` | `GET /health` DB + migration gate |
| Web image | `meetcutes-fe/Dockerfile` | Vite build served by nginx with SPA fallback |
| nginx config | `meetcutes-fe/nginx.conf` | `try_files ... /index.html` |

The boot sequence is:

1. Kamal starts the new container.
2. `bin/server` runs `Meetcutes.Release.migrate/0`.
3. Phoenix binds `0.0.0.0:4000` with `PHX_SERVER=true`.
4. `kamal-proxy` calls `GET /health` every 3 seconds.
5. The proxy switches traffic only after a `200 {"status":"healthy"}`.
6. The previous container drains and is retired.

If the database is unreachable or a migration is still pending, `/health`
returns `503 {"status":"unhealthy"}` and the rollout is aborted instead of
routing users to a broken schema.

## 1. Prerequisites

- A Linux server with a public IPv4 address and SSH access.
- Two DNS records pointing at that server:
  - `api.meetcutes.us` for the Phoenix API.
  - `meetcutes.us` (and optionally `www`) for the frontend.
- A container registry. The examples use GitHub Container Registry
  (`ghcr.io`); Docker Hub or any OCI registry works with the same pattern.
- Kamal 2 installed locally:

  ```bash
  gem install kamal
  kamal version
  ```

- The `.kamal/` directory and `config/deploy.yml` live in `meetcutes-elixir/`.
  Run every Kamal command from that directory.

## 2. Firewall and network rules

Ports **80** and **443** must be open for `kamal-proxy` to obtain certificates
and serve traffic. Keep SSH available, and never expose the internal app port
or Postgres publicly.

On Ubuntu with `ufw`:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp   # HTTP/3 through kamal-proxy
sudo ufw enable
sudo ufw status verbose
```

Also open 80/443/22 in the cloud provider's security group or firewall. If the
database is managed, allow the server's public IP (or private network range) on
the Postgres port; do not open 5432 to `0.0.0.0/0`.

## 3. Registry setup

Create a GitHub token with `write:packages` (classic) or a fine-grained token
with package write permission, then place it in `.kamal/secrets` as
`KAMAL_REGISTRY_PASSWORD`. Update these values in `config/deploy.yml`:

```yaml
image: <your-org>/meetcutes-api
registry:
  server: ghcr.io
  username: <your-org>
```

Kamal builds the final repository as `registry.server/image`, so the image
name must not repeat `ghcr.io`. The resulting image is
`ghcr.io/<your-org>/meetcutes-api`. The image name and registry username are
deployment identifiers, not secrets. The token is read from `.kamal/secrets`
at deploy time.

## 4. Configure `.kamal/secrets`

Copy the example and fill in real values:

```bash
cp .kamal/secrets.example .kamal/secrets
chmod 600 .kamal/secrets
```

`.kamal/secrets` is a local shell fragment. Kamal evaluates it and injects the
listed variables into the container; the file must never be committed or baked
into an image. It is already ignored by `.gitignore`.

Minimum required values:

```bash
KAMAL_REGISTRY_PASSWORD='...'
DATABASE_URL='ecto://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require'
SECRET_KEY_BASE='...'
DASHBOARD_USER='admin'
DASHBOARD_PASSWORD='...'
STRIPE_SECRET_KEY='sk_live_...'
RESEND_API_KEY='re_...'
```

Additional values referenced by `config/deploy.yml`:

```bash
STRIPE_WEBHOOK_SECRET='whsec_...'
MCP_ADMIN_SECRET_KEY='...'
AWS_ACCESS_KEY_ID='...'
AWS_SECRET_ACCESS_KEY='...'
CLOUDFLARE_ACCOUNT_ID='...'
```

Generate the high-entropy values locally:

```bash
mix phx.gen.secret                       # SECRET_KEY_BASE
openssl rand -base64 48                  # DASHBOARD_PASSWORD
openssl rand -hex 32                     # MCP_ADMIN_SECRET_KEY
```

Values can also be pulled from a password manager inside `.kamal/secrets`:

```bash
SECRET_KEY_BASE=$(op read "op://Meetcutes/production/secret_key_base")
DATABASE_URL=$(op read "op://Meetcutes/production/database_url")
```

## 5. Review `config/deploy.yml`

Replace the placeholders before the first deploy:

- `image` and `registry` — your registry namespace.
- `servers.web.hosts` — the public server IP.
- `proxy.host` — `api.meetcutes.us`.
- `PHX_HOST`, `FRONTEND_URL`, and `CORS_ORIGINS` — your real domains.

The internal contract is intentionally fixed:

```yaml
proxy:
  ssl: true
  forward_headers: true
  app_port: 4000
  healthcheck:
    path: /health
    interval: 3
    timeout: 5
```

`kamal-proxy` retries the health check until the top-level `deploy_timeout`
(default 30 seconds, set to 120 seconds in this config) expires. The boot
overlay runs migrations before the server binds, so the first check may happen
while the release is still preparing.

The container listens on `PORT=4000`; `PHX_URL_SCHEME=https` and
`PHX_URL_PORT=443` keep generated URLs public even though the app is bound to a
private port.

Validate the merged configuration before deploying:

```bash
kamal config
```

## 6. Build and verify locally

Backend:

```bash
docker build -t meetcutes-api:local .
docker run --rm -p 4000:4000 \
  --env-file .env.production \
  meetcutes-api:local
```

Then:

```bash
curl -i http://localhost:4000/health
# HTTP/1.1 200 OK
# {"status":"healthy"}
```

To prove the failure path, stop Postgres (or point `DATABASE_URL` at an
unreachable host) and repeat the request. The response must be
`503 {"status":"unhealthy"}`.

Frontend:

```bash
docker build \
  --build-arg VITE_API_URL=https://api.meetcutes.us \
  -t meetcutes-web:local .

docker run --rm -p 8080:80 meetcutes-web:local

curl -I http://localhost:8080/dashboard/settings
# 200, served by index.html for the React Router SPA fallback
```

## 7. First deploy

Bootstrap Docker on the server, then perform the first blue-green rollout:

```bash
kamal server bootstrap
kamal setup
```

`kamal server bootstrap` installs Docker and prepares the host.
`kamal setup` deploys the app for the first time. On later releases use:

```bash
kamal deploy
```

Kamal starts the new container alongside the old one, waits for the proxy
health check, switches traffic, and only then stops the old container. There is
no downtime window.

## 8. Verify and operate

```bash
kamal details                 # servers, containers, proxy status
kamal app logs -f             # Phoenix logs
kamal proxy logs -f           # TLS + health-check traffic
kamal app exec --reuse "bin/meetcutes eval 'Meetcutes.Release.migrate'"
kamal rollback <VERSION>      # return to a previous image
```

Public checks:

```bash
curl https://api.meetcutes.us/health
curl https://api.meetcutes.us/api/v1/public/global-announcement
curl -I https://meetcutes.us/
```

Expected health payloads:

```json
{ "status": "healthy" }
```

```json
{ "status": "unhealthy" }
```

## 9. Runtime environment matrix

| Variable | Required | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | yes | Postgres connection; include `sslmode=require` for hosted DBs |
| `SECRET_KEY_BASE` | yes | Cookie/token signing |
| `DASHBOARD_USER` | yes | LiveDashboard operator |
| `DASHBOARD_PASSWORD` | yes | LiveDashboard password |
| `STRIPE_SECRET_KEY` | billing | Stripe API |
| `STRIPE_WEBHOOK_SECRET` | billing | Stripe webhook verification |
| `RESEND_API_KEY` | yes | Transactional email |
| `MCP_ADMIN_SECRET_KEY` | admin | `X-MCP-Admin-Key` gate |
| `PHX_HOST` | yes | Public host for generated URLs |
| `PORT` | yes | Internal container port (`4000`) |
| `PHX_URL_SCHEME` / `PHX_URL_PORT` | yes | Public URL scheme/port |
| `CORS_ORIGINS` | yes | Comma-separated browser origins |
| `DATABASE_POOL_SIZE` | no | Repo pool size (default 10) |
| `OBAN_*_CONCURRENCY` | no | Oban queue concurrency |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | images | R2/S3 uploads |
| `CLOUDFLARE_ACCOUNT_ID` | images | Derives the R2 endpoint |
| `PAYMENT_FEATURE_ENABLED` | no | Runtime paywall toggle |
| `MAINTENANCE_MODE_ACTIVE` | no | Runtime maintenance toggle |

The periodic IANA timezone updaters are disabled in production
(`config :meetcutes, :start_tz_updater, false` and
`config :tzdata, :autoupdate, :disabled`). The release runs as `nobody` from an
immutable filesystem, so runtime recompilation of timezone data would fail.
Refresh timezone data by rebuilding the image with updated `:tz` / `:tzdata`
dependencies.

All application values are read at runtime by `config/runtime.exs`. The image
contains no environment-specific credentials and the same artifact can be
promoted between environments.

## 10. Frontend deployment options

The frontend image is independent of the API:

```bash
docker build \
  --build-arg VITE_API_URL=https://api.meetcutes.us \
  --build-arg VITE_WS_URL=wss://api.meetcutes.us/socket \
  --build-arg VITE_SITE_URL=https://meetcutes.us \
  --build-arg VITE_REACT_APP_GEOAPIFY_API_KEY=<your-browser-key> \
  -t meetcutes-web:latest .
```

`VITE_API_URL` is mandatory: the image build fails if it is empty so a
production bundle can never silently fall back to `http://localhost:4000`.
`VITE_REACT_APP_GEOAPIFY_API_KEY` is a public browser key, not a server secret.

It can be served by the same Kamal proxy as a second service:

```yaml
service: meetcutes-web
image: ghcr.io/your-org/meetcutes-web
servers:
  web:
    hosts:
      - 203.0.113.10
proxy:
  ssl: true
  host: meetcutes.us
  app_port: 80
  healthcheck:
    path: /health
```

Any static host (Cloudflare Pages, S3 + CDN, Caddy) also works as long as it
rewrites unknown paths to `index.html`. `nginx.conf` in `meetcutes-fe/` already
implements that fallback and long-lived caching for hashed `/assets/` files.

`VITE_*` values are inlined by Vite at build time, so each environment needs
its own image build. Keep API URLs out of source code; pass them as build args.

## 11. Troubleshooting

**`/health` returns 503 after deploy**

```bash
kamal app logs -f
```

Common causes:

- `DATABASE_URL` is missing, malformed, or the server IP is not allowed by the
  database firewall.
- A pending migration exists. The boot overlay should have run it; check for a
  failed migration in the logs and run it manually with `kamal app exec`.
- `RESEND_API_KEY` or `SECRET_KEY_BASE` is missing, so the release cannot boot.
- The database requires TLS but `sslmode=require` is absent.

**Proxy returns 502/503 while the app looks healthy**

Check `kamal proxy logs -f`. Confirm `app_port` is `4000` and that the
container is listening on all interfaces. Confirm DNS points at the server
before the first TLS attempt.

**Frontend deep links return 404**

Ensure the nginx `try_files` fallback is present and that the static host is
configured for an SPA. Hashed assets should return 200; unknown routes should
return `index.html`.

**Container permission errors**

The runtime image runs as `nobody`. Do not mount root-owned directories that
the app must write to. Uploads go to R2/S3, not the container filesystem.

**Migrations need to be re-run manually**

```bash
kamal app exec --reuse "bin/meetcutes eval 'Meetcutes.Release.migrate'"
```

## 12. Security checklist

- Ports 80/443 are the only public HTTP ports; 4000 and 5432 stay private.
- `.kamal/secrets` is `chmod 600` and never committed.
- Registry tokens are read-only for consumers and scoped for CI writers.
- The API image runs as `nobody`; no build toolchain ships in the runtime.
- `DATABASE_URL` uses TLS (`sslmode=require` or stronger).
- `MCP_ADMIN_SECRET_KEY` is high entropy and stored separately from user
  bearer tokens.
- Rotate `SECRET_KEY_BASE`, dashboard credentials, Stripe, Resend, and MCP keys
  through `.kamal/secrets` plus `kamal deploy`.
- Keep the host patched and restrict SSH to trusted addresses where possible.

