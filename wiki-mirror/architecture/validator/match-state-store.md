# Match State Store

**Status:** current

## Kind
subsystem

## Summary
`store/match-state.ts` — the `MatchStateStore` interface and its `InMemoryMatchStateStore` implementation: a TTL cache of `StoredMatch` keyed by `match_id`, plus a `connection_id → match_id` index for socket auth and a background sweep for expiry.

## Purpose
Hold authoritative per-match state between actions. Each entry tracks `current_state`, `state_history` (moveIndex → state), `player_id`, `connection_id`, counters and timestamps. The interface (`get/set/delete/getByConnectionId/getAll`) is storage-agnostic — the in-memory impl is the default; the spec anticipates a Redis-backed impl for horizontal scale.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- class `InMemoryMatchStateStore` in `validator/src/validator/store/match-state.ts`
- interface `StoredMatch` in `validator/src/validator/types.ts`

## Data model
_None._

## Usage
`store.set(match_id, match, MATCH_SESSION_TTL)` on init; `store.get(match_id)` / `getByConnectionId(connection_id)` in the socket path. A `setInterval` sweep (every 60s) evicts entries past `expiresAt` and cleans the connection index. Inspectable live via the MCP debug interface (`list_matches`, `get_match_state`).

## Invariants & constraints
- The connection→match index must stay consistent with the primary cache; eviction removes both, or socket auth could resolve a dead match.
- Reads honor TTL: an entry past expiresAt is treated as absent (and lazily deleted) even before the sweep runs.

## Synced commit
ada25ef
