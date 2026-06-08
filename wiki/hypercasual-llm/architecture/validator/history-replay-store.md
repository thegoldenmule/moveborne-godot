# History Replay Store

**Status:** current

## Kind
subsystem

## Summary
`store/history-store.ts` — the `IHistoryStore` interface (in-memory and filesystem impls) backing `POST /api/match/init-from-history`, which seeds a validator session from a saved sequence of `StateHistorySnapshot`s for debugging state-sync issues.

## Purpose
Make hash-mismatch bugs reproducible. Instead of replaying a whole match, a saved history (from `src/game/fixtures/history/{id}.json` or inline `history_data`) is loaded into the match's `state_history` Map and `current_state` is set to a chosen `start_from_index`, so a session can be initialized mid-game at the exact state where a divergence occurred.

## Design notes
_None._

## Components
_No components._

## Dependencies
- **depends-on** → [Match State Store](architecture:mq1c31rb-000x-6l2ehj) — Seeds match state_history / current_state into the match-state store.

## Code references
- interface `IHistoryStore` in `moveborne/src/validator/store/history-store.ts`

## Data model
_None._

## Usage
`POST /api/match/init-from-history` with one of `history_file_id` / `history_data`, plus `player_id`, `signature`, optional `start_from_index` (defaults to last). Returns the same `{connection_id, expires_at}` as `/init`. Saved histories carry their own TTL; the store interface is `save/get/delete/cleanup`.

## Invariants & constraints
- init-from-history yields a session indistinguishable from a fresh /init — same response shape and same downstream validation path — so replays exercise the real code, not a debug branch.

## Synced commit
ada25ef
