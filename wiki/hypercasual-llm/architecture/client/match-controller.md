# Match Controller

**Status:** current

## Kind
subsystem

## Summary
`game/match_controller.gd` (`MbMatch`) — the seam between pure logic and the live game. Owns the current game state and exposes `new_game / swipe / play_card / spawn_totem`, driving `MbEngine` and (optionally) relaying predicted hashes to the validator client.

## Purpose
Hold mutable session state and translate player intent into engine actions, then publish the resulting state + hash to presentation. When online it hands each move's predicted hash to the Validator Client and applies the authoritative state on mismatch. This is the only place that owns 'current state' — the engine is stateless, scenes are read-only consumers.

## Design notes
_None._

## Components
_No components._

## Dependencies
- **depends-on** → [Rules Engine](architecture:mq1c2u50-000n-gspuzp) — Drives MbEngine.step/step_card/step_totem to advance state.
- **depends-on** → [Validator Client](architecture:mq1c2wgh-000r-sjn10a) — Sends predicted hashes and applies authoritative state on mismatch.

## Code references
- class `MbMatch` in `llm-workflow/game/match_controller.gd`
- class `MbDebug` in `llm-workflow/game/mcp_game_api.gd`

## Data model
_None._

## Usage
Scenes call `MbMatch.swipe(dir)` / `play_card(...)` / `spawn_totem(...)`; the controller emits the new state for `board_view` to render. The `MbDebug` autoload wraps the controller for MCP-driven play (`game_eval` → `MbDebug.get_state()` / swipe / read board). Validator hookup is optional and toggled at runtime (the `V` key).

## Invariants & constraints
- MbMatch is the single owner of live game state; the engine stays stateless and scenes never mutate state directly.

## Synced commit
85f64c0
