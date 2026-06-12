# Client

**Status:** current

## Kind
service

## Summary
Godot 4.6 (GDScript) port of **Moveborne**, a 2048-style swipe-merge puzzle. A hard wall separates a **pure deterministic rules engine** from presentation; the engine is byte-for-byte compatible with the original TypeScript `@spyre-io/moveborne-logic`, so it computes identical state hashes and can play against the existing **Validator** service unchanged — no Nakama, no server changes.

## Purpose
Deliver the full Moveborne single-player experience natively in Godot while preserving **determinism parity** with the canonical TS engine. Parity is the headline property: identical hashes mean the same client can be validated online by the unmodified validator, and the same golden vectors test both implementations.

The port is organized so logic never depends on the scene tree: `input → action → engine (pure) → new state + hash → scenes render`, with `net/` confirming each move against the validator when online.

## Design notes
Packaging the client for distribution (committed export presets plus a tools/build.sh driver that builds any one platform, any subset, or all five) is documented in the Build and Distribution subsystem page.

## Components
- [Determinism Primitives](architecture:mq1c2syb-000l-6okg54)
- [Rules Engine](architecture:mq1c2u50-000n-gspuzp)
- [Match Controller](architecture:mq1c2vaw-000p-3fdst6)
- [Validator Client](architecture:mq1c2wgh-000r-sjn10a)
- [Presentation &amp; VFX](architecture:mq1c2xsl-000t-8j2hqc)
- [Editor Tools](architecture:mq8hyn2w-000i-cryytk)
- [Build &amp; Distribution](architecture:mq9llv7f-00a3-c5f96m)
- [Game Control API (MbDebug)](architecture:mqay9c1u-0013-wu1lcn)
- [UI Control API (MbUi)](architecture:mqayf7o4-001y-dyr6k0)

## Dependencies
- **calls** → [Validator](architecture:mq1c2ixi-000h-kd018q) — Online play: validates every move against the Validator over Socket.IO (via net/).
- **depends-on** → [Server](architecture:mq1c2nid-000j-6cf0hr) — Nakama match creation / authoritative submission — omitted in this single-player port (DEV_MODE).
- **owns** → [Build &amp; Distribution](architecture:mq9llv7f-00a3-c5f96m) — Build & Distribution — export presets + build.sh for macOS/Windows/Web/iOS/Android.

## Code references
- class `MbEngine` in `game/logic/engine.gd`
- class `MbMatch` in `game/game/match_controller.gd`
- class `MbValidatorClient` in `game/net/validator_client.gd`
- `game/scenes/main.gd`
- `game/CLAUDE.md`
- `game/GODOT_PORT_PLAN.md`

## Data model
Game state is a `Dictionary` mirror of the TS `SynchronizedGameState`; field names match the TS **exactly**. Tiles are a flat **row-major** `Array` of tile `Dictionary`s. GDScript `Dictionary`/`Array` are **reference types** (like JS objects/arrays), which lets the port reproduce the original `merge.ts` in-place mutation/aliasing semantics — shallow `.duplicate()` mirrors `[...arr]`/`{...obj}`; deep copies are avoided unless the TS does them.

Non-empty tiles produced by merge/spawn carry `"meta": {}`; empties don't. RNG state lives in `rngIndices` across 5 namespaces; `moveIndex` advances +2 on auto-draw else +1. State is hashed via `canonical_stringify` (sorted keys, 2-space, JS number format).

## Usage
Open the project in **Godot 4.6.3** and press Play (`scenes/main.tscn`). The game runs fully offline — no backend required.

**Controls:** arrow keys / drag = move tiles; tap a card then tap target tile(s) = play a power card; `0`–`7` = load a scenario; `R` = new game; `Esc` = cancel targeting; `V` = connect to the validator.

**Online play:** run `tools/run_validator.sh` (DEV_MODE, `:5555`), press `V`. The HUD shows `validator: ✓ move N ok`; on a hash mismatch the client snaps to the validator's authoritative state.

**Driving via MCP:** the game is driven through the godot-ai MCP `game_eval` — **MbDebug** for gameplay (swipe / read board / play card; see the **Game Control API (MbDebug)** subsystem page) and **MbUi** for the menus (navigate screens / press buttons / run scripted sequences; see the **UI Control API (MbUi)** subsystem page). Both are autoloads; new MbUi controls register via `MbUiReg`.

## Invariants & constraints
- Determinism parity is load-bearing: `logic/` must compute the same state hashes as the TS engine and validator. Never change engine behavior without re-running the parity tests; a changed golden hash means broken compatibility.
- The TS source (`moveborne/src/logic/src` + `src/game/engine/scenarios.ts`) is the source of truth. Code beats spec. Ports must mirror iteration order, RNG draw order/count per namespace, and which fields are present in state.
- `logic/` is pure: no Node/scene references. Classes are `class_name Mb<Thing>` with static functions; scenes/tests reference them via `preload("res://logic/x.gd")`.
- The client plays optimistically — every move is applied locally for instant feedback and (when online) its predicted hash is sent to the validator; a match ACKs the fast path, a mismatch returns authoritative state to snap to.

## Synced commit
85f64c0
