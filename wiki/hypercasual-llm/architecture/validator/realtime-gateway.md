# Realtime Gateway

**Status:** current

## Kind
subsystem

## Summary
The HTTP + WebSocket front door: a Hono app for `POST /api/match/init` and `init-from-history`, and a Socket.IO server (`@socket.io/bun-engine`) for the per-action validation loop. `index.ts` wires auth middleware, the connection handler, and the action handler that runs the engine and signs responses.

## Purpose
Terminate client connections and orchestrate the validation loop. Socket.IO middleware authenticates the handshake (`connection_id`, `player_id`) against the store before any game logic; on each action event it fetches state, runs `executeAction`, computes the hash, signs `(match_id, index, action, state_hash)`, and emits match (`index, sig`) or mismatch (`index, state, sig`), then writes new state back to the store.

## Design notes
_None._

## Components
_No components._

## Dependencies
- **depends-on** → [Match State Store](architecture:mq1c31rb-000x-6l2ehj) — Reads/writes match state and resolves sockets by connection_id.
- **depends-on** → [Crypto &amp; Signing](architecture:mq1c351c-0011-gtfyxx) — Verifies the Nakama init signature and signs each validation response.

## Code references
- `validator/src/validator/index.ts`
- function `createMatchRoutes` in `validator/src/validator/routes/match.ts`

## Data model
_None._

## Usage
`bun run dev`. REST init returns a `connection_id`; clients then open a Socket.IO connection carrying it. Match routes (`createMatchRoutes`) are mounted on the Hono app; CORS is wide-open for dev. Per CLAUDE.md, the dev server runs under `bun run --watch` — do not kill/restart it; it hot-reloads on file change.

## Invariants & constraints
- Handshake auth (connection_id → match_id → player_id) must pass before any action is processed; failures reject with MATCH_NOT_FOUND / PLAYER_MISMATCH / AUTHENTICATION_FAILED.

## Synced commit
ada25ef
