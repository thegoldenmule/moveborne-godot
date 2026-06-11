---
name: snapser-validator
description: Authenticate against the Snapser gateway (anonymous login) and call the validator BYOSnap. Use when you need to smoke-test validator endpoints (/health, /api/status) through the gateway, or to obtain a session token for the Hermes WSS endpoint (wss://gateway.snapser.com/<snapend>/v1/hermes/ws?token=...), which carries the gRPC match RPCs. Handles login, token caching in a dotfile, and authenticated requests.
---

# Snapser Validator Client

The validator runs as a BYOSnap behind the Snapser gateway, which requires a credential on
every route (there are no credential-free routes). This skill performs an **anonymous login**
via the Auth snap to get a user session token, caches it, and calls the validator with the
`Token` / `User-Id` headers the gateway expects.

## Prerequisite (one-time)

The snapend's Auth snap must have the **Anonymous connector enabled** (Snapser dashboard:
Auth snap → Connectors → Anonymous → enable → redeploy the snapend). Until then, login returns
`400 "Anonymous login not enabled"`.

## Config

Resolution order: env vars → `~/.snapser/validator.json` → built-in defaults.

`~/.snapser/validator.json`:
```json
{
  "gateway": "https://gateway.snapser.com/c4n1awfs",
  "snap_prefix": "/v1/byosnap-validator",
  "username": "validator-dev-client"
}
```
Env overrides: `SNAPSER_GATEWAY`, `SNAPSER_VALIDATOR_PREFIX`, `SNAPSER_ANON_USERNAME`.
The session token is cached at `~/.snapser/validator-session.json` (chmod 600, in `$HOME` so
it is never committed).

## Usage

```bash
python3 .claude/skills/snapser-validator/scripts/client.py smoke      # login + GET /health,/api/status,/
python3 .claude/skills/snapser-validator/scripts/client.py login      # anon login, cache token
python3 .claude/skills/snapser-validator/scripts/client.py token      # print cached session token
python3 .claude/skills/snapser-validator/scripts/client.py call GET /health
# Match RPCs are gRPC via Hermes WSS, not HTTP — get a token for the WS URL with:
python3 .claude/skills/snapser-validator/scripts/client.py token
```

`call` auto-logs-in if there is no cached token and retries once if the token is stale.
It targets `<gateway><snap_prefix><path>`, so pass app-relative paths like `/health`.

## Notes

- Auth-types per endpoint live in `validator/swagger.json`. `/health`, `/api/status`, `/`,
  and `/api/match/init-from-history` accept user tokens (passthrough). `/mcp`,
  `/api/match/save-history`, `/api/match/load-history` are api-key/internal only and will
  401/400 for a user session token (by design).
- Game-facing match RPCs (InitMatch/ValidateAction/CompleteMatch) are gRPC
  (`moveborne.validator.v1.ValidatorService`, protos in `validator/protos/`) reached through
  the Hermes WSS endpoint with the cached session token as the `?token=` query param —
  binary protobuf ClientMessage/ServerMessage frames (MESSAGE_TYPE_SNAP_API_PROXY). See
  `game/tools/test_snapser_client.gd` for a working end-to-end example.
