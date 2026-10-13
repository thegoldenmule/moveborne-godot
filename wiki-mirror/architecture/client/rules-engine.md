# Rules Engine

**Status:** current

## Kind
subsystem

## Summary
The pure rules engine — the core of the port. `engine.gd` (`MbEngine`) applies swipe/merge/spawn/combo/score plus the validator's caller-overrides; supporting modules cover power cards (26), totems (11), tile effects, events, scenarios, validation, and constants. No Node/scene deps; `class_name Mb*` + static functions.

## Purpose
Compute the next `SynchronizedGameState` (and its hash) for every action, byte-for-byte like `@spyre-io/moveborne-logic`. `MbEngine.step / step_card / step_totem` apply an action and the overrides the validator applies — accumulated `score`, `rngIndices`, and `moveIndex` (+2 on auto-draw else +1) — returning `{state, hash, ...}`. This is what the Match Controller drives and what the Validator independently re-runs.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
- **depends-on** → [Determinism Primitives](architecture:mq1c2syb-000l-6okg54) — Draws RNG and computes state hashes via the determinism primitives.

## Code references
- class `MbEngine` in `game/logic/engine.gd`
- `game/logic/powercards.gd`
- `game/logic/tile_effects.gd`
- `game/logic/totems.gd`
- `game/logic/scenarios.gd`
- `game/logic/constants.gd`

## Data model
_None._

## Usage
Call `MbEngine.step(state, action)` etc.; never mutate state outside the engine's documented in-place semantics. After touching any `logic/` file, run the relevant headless verifier (`tools/verify_engine_swipe.gd`, `verify_playcard.gd`, …) or the `McpTestSuite` via MCP `test_run`. New logic needs a golden oracle dumped from the real TS dist before its expected hashes can be asserted — never hand-write expected values.

## Invariants & constraints
- Mirror the TS in-place mutation semantics: shallow .duplicate() for [...]/{...}, mutate tile dicts where TS does, new dicts for merged/spawned tiles. Non-empty merge/spawn tiles carry "meta": {}; empties don't.
- Any change to engine behavior must be proven parity-preserving with a golden before commit; a changed golden hash is a broken contract, not an expected diff.

## Synced commit
85f64c0
