# MCP Debug Interface

**Status:** current

## Kind
subsystem

## Summary
`mcp.ts` — an MCP server (mounted at `http://localhost:5555/mcp`) for inspecting and debugging live match state: list matches, dump full state + RNG indices + computed hash, walk state history, simulate an action without applying it, and clear a match.

## Purpose
Give agents/operators a game-semantic window into the validator without poking the wire protocol. `simulate_action` is the key tool — it runs the engine on stored state and returns score/shard deltas, before/after hashes, and updated RNG indices without mutating the match, which is how hash-mismatch divergences get diagnosed against the client's optimistic result.

## Design notes
_None._

## Components
_No components._

## Dependencies
- **depends-on** → [Match State Store](architecture:mq1c31rb-000x-6l2ehj) — Reads (and clears) entries from the match-state store.

## Code references
- function `createValidatorMCP` in `moveborne/src/validator/mcp.ts`

## Data model
_None._

## Usage
Tools: `list_matches`, `get_match_state {match_id}`, `get_state_history {match_id}`, `simulate_action {match_id, action_type: SWIPE|PLAY_CARD, action_payload}`, `clear_match {match_id}`. Pairs with the client's `MbDebug` MCP surface to compare both engines at the same moveIndex.

## Invariants & constraints
- Debug tools are read-only except clear_match: simulate_action must never mutate stored match state.

## Synced commit
ada25ef
