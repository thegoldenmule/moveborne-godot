# Validator

**Status:** current

## Kind
service

## Summary
Real-time state-validation authority for Moveborne, built with **Bun + Hono + Socket.IO** (`@socket.io/bun-engine`). It re-runs the canonical `@spyre-io/moveborne-logic` engine for every action, signs valid transitions with HMAC-SHA256, and returns authoritative state on mismatch. Lives in this repo at `validator/src/validator` and runs unchanged against the Godot client.

## Purpose
Be the trusted arbiter of game state. The client plays optimistically; the validator independently executes each action against stored state, hashes the result, and either ACKs the client's predicted hash (fast path) or ships back the authoritative state to sync. Signed responses `HMAC((match_id, index, action, state_hash), secret)` let a downstream server accept validated actions without re-simulating.

Sessions are scoped to a single player; multi-user orchestration is the platform's job (Snapser — the validator deploys there as a BYOSnap), relaying validated actions.

## Design notes
_No design notes._

## Components
- [Realtime Gateway](architecture:mq1c2z0y-000v-v2bzv9)
- [Match State Store](architecture:mq1c31rb-000x-6l2ehj)
- [History Replay Store](architecture:mq1c3370-000z-l7ivsv)
- [Crypto & Signing](architecture:mq1c351c-0011-gtfyxx)
- [MCP Debug Interface](architecture:mq1c366g-0013-odkry1)

## Dependencies
_No dependencies._

## Code references
- `validator/src/validator/index.ts`
- function `createMatchRoutes` in `validator/src/validator/routes/match.ts`
- interface `StoredMatch` in `validator/src/validator/types.ts`
- function `getConfig` in `validator/src/validator/config.ts`
- `moveborne/spec/validator/connection-flow.md`

## Data model
`StoredMatch` keyed by `match_id`: `{ current_state: SynchronizedGameState, connection_id, player_id, created_at, last_action_at, action_count, state_history: Map<number, state> }`. A second index maps `connection_id → match_id` for socket auth.

Wire types: `ValidatorInitRequest/Response`, `GameActionRequest {index, action, state_hash}`, and the response union `GameActionResponseMatch {index, signature}` | `GameActionResponseMismatch {index, state, signature}`. State and action types come from `@spyre-io/moveborne-logic` (`SynchronizedGameState`, `GameAction`), keeping the validator's serialization identical to client and engine.

## Usage
`bun run dev` (hot reload) or `bun run start`. Default port `3000`; the Godot client's `tools/run_validator.sh` runs it on `:5555`.

**Lifecycle:** (1) `POST /api/match/init` with `(match_id, starting_state, player_id)` → the gateway-validated `User-Id` header must match `player_id` (see Crypto & Signing); stores match, returns `connection_id`. (2) Client connects via Socket.IO with `(connection_id, player_id)` — the handshake is bound to the same gateway-validated user. (3) Per action, client emits `(index, action, state_hash)`; validator executes, hashes, signs, replies match or mismatch. (4) `POST /api/match/init-from-history` replays a saved state history for debugging (same caller check). Locally there is no gateway, so callers self-stamp a matching `User-Id`.

**Config (env):** `VALIDATOR_SHARED_SECRET` (required), `CONNECTION_TOKEN_TTL` (300s), `MATCH_SESSION_TTL` (3600s), `PORT` (3000). There is no DEV_MODE — the auth check always runs.

## Invariants & constraints
- The validator is the source of truth for state: on any hash mismatch it returns its computed authoritative state and the client must sync to it.
- All signatures are HMAC-SHA256 over a *canonical* serialization (`canonicalStringify` from the logic package), compared with `timingSafeEqual`. Identical canonicalization across client/validator/engine is what makes hashes and signatures line up.
- It runs the SAME `@spyre-io/moveborne-logic` engine the client ports — `executeAction`, `computeStateHash`, `RandomGenerator`. Determinism parity between Godot engine and this package is the whole contract.
- Sessions are single-player scoped; socket auth binds `connection_id` → `match_id` → `player_id`, rejecting MATCH_NOT_FOUND / PLAYER_MISMATCH before any game logic runs.

## Synced commit
7f55d94
