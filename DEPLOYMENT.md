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
