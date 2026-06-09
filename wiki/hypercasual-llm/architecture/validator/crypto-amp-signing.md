# Crypto &amp; Signing

**Status:** current

## Kind
subsystem

## Summary
Inbound trust + outbound signing. `utils/snapser-auth.ts` — gateway-header caller verification (`verifySnapserCaller`) binding the Snapser gateway's validated `User-Id` to the claimed `player_id`. `utils/crypto.ts` — HMAC-SHA256 over canonical serialization for the outbound validator response `(match_id, index, action, state_hash)`, plus connection-id/UUID generation.

## Purpose
Establish trust at both ends of the loop. Inbound: the BYOSnap is only reachable through the Snapser gateway, which validates the caller's session token against the Auth snap BEFORE forwarding and stamps the result as plain headers (`User-Id`, `Auth-Type`, `Gateway`) — Snapser exposes no signed claim/JWKS for offline verification, so those headers ARE the claim. `verifySnapserCaller` gates `/init`, `/init-from-history`, and the Socket.IO handshake unconditionally (there is no DEV_MODE bypass): the gateway-validated `User-Id` must equal the claimed `player_id`; `api-key` and `internal` (snap-to-snap) callers carry no user context and pass without binding. Locally there is no gateway, so callers self-stamp a matching `User-Id` (the check is a no-op consistency check there, not real auth). This replaced the original Nakama init HMAC (`verifyNakamaSignature`, removed). Outbound: `signValidatorResponse` signs every ACK/mismatch so a downstream server can accept validated actions without re-simulating; HMACs are computed over `canonicalStringify(data)` and compared with `timingSafeEqual`.

## Design notes
_None._

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- function `signValidatorResponse` in `validator/src/validator/utils/crypto.ts`
- interface `ValidatorConfig` in `validator/src/validator/config.ts`
- function `verifySnapserCaller` in `validator/src/validator/utils/snapser-auth.ts`

## Data model
_None._

## Usage
`verifySnapserCaller(headers, player_id)` takes a lowercased header bag — Hono's `c.req.header()` and Socket.IO's `socket.handshake.headers` both qualify — and returns `{ok}` or `{ok:false, reason}`. For signing: `computeHmacSignature(data, secret)` / `verifyHmacSignature`, and the typed wrappers `signValidatorResponse` / `verifyValidatorSignature`. Secret comes from `VALIDATOR_SHARED_SECRET` (config); generate a production secret with `openssl rand -hex 32`.

## Invariants & constraints
- Signing canonicalization MUST match the client/engine's (canonicalStringify) byte-for-byte, or a correct state would fail verification. Comparison is constant-time (timingSafeEqual).
- Gateway-header trust is only sound while the BYOSnap has no ingress other than the Snapser gateway (private snapend network), AND the gateway sanitizes client-supplied User-Id/Gateway headers and re-stamps User-Id from the validated token. Never expose the container port directly to untrusted callers.

## Synced commit
7f55d94
