# Moveborne — Godot Port

A Godot 4.6 (GDScript) port of **Moveborne**, a 2048-style swipe-merge puzzle with
tile effects, power cards, totems, combos, events, and scenarios. The original game
is a TypeScript/PixiJS web client backed by a Go (Nakama) server and a real-time
validator service.

The headline property of this port: the GDScript rules engine is **byte-for-byte
deterministically compatible** with the original TypeScript engine
(`@spyre-io/moveborne-logic`). It computes identical state hashes, so the Godot
client can play against the **existing validator service unchanged** — no Nakama,
no server changes.

> Source of truth for game rules: `~/projects/thegoldenmule/moveborne` (the TS
> `src/logic` package and `spec/game`). See [`GODOT_PORT_PLAN.md`](GODOT_PORT_PLAN.md)
> for the full investigation, architecture, and phase-by-phase status.

## Status

| Phase | What | State |
|---|---|---|
| 0 | Determinism primitives (seedrandom ARC4, custom hash, canonical JSON) | ✅ byte-exact |
| 1 | Full deterministic engine (swipe + cards + totems + effects + events) | ✅ byte-exact |
| 2 | Playable single-player (board, HUD, hand, cards, totems, scenarios) | ✅ |
| 3 | Validator integration (Socket.IO over WebSocket) | ✅ — Nakama omitted |

## Requirements

- **Godot 4.6.3** (Forward Mobile renderer, portrait).
- **[Bun](https://bun.sh) 1.3+** — only needed to run the validator for online play.
- The `godot_ai` MCP addon is bundled under `addons/` (editor automation; optional).

## Quick start

Open the project in Godot 4.6 and press **Play** (`scenes/main.tscn` is the main
scene). The game runs fully offline — no backend required.

### Controls

| Input | Action |
|---|---|
| Arrow keys / swipe (drag) | Move tiles |
| Tap a card, then tap target tile(s) | Play a power card |
| `0`–`7` | Load a scenario (starting cards + effect spawns) |
| `R` | New game |
| `Esc` | Cancel card targeting |
| `V` | Connect to the validator (online validation) |

Tile-effect borders: freeze = blue, amplify = yellow, black hole = indigo,
lock = grey, decay = green, stone = dark.

## Online play against the validator (optional)

The validator re-runs the same `src/logic` engine and confirms every move. Run it
in DEV_MODE (which skips the Nakama signature check, so Nakama isn't needed):

```bash
tools/run_validator.sh          # serves on http://localhost:5055
```

Then in the game press **`V`**. The top-right shows `validator: ✓ move N ok` as
each move is confirmed; on a hash mismatch the client snaps to the validator's
authoritative state.

## Project layout

```
engine/        Pure deterministic rules engine (no scene/Node deps). The core port.
  rng.gd                seedrandom@3.0.5 ARC4 (53-bit double), bit-exact
  hasher.gd             custom rolling state hash + json-stable-stringify canonical JSON
  random_generator.gd   5-namespace RNG manager
  constants.gd          POWER_CARDS (26) + TOTEM_TYPES (11) catalogs + scalars
  engine.gd             swipe / merge / spawn / combo / score / action executor
  powercards.gd, validation.gd, tile_effects.gd, totems.gd, events.gd, scenarios.gd
game/
  match_controller.gd   MbMatch — owns game state, drives the engine, sends validations
net/
  validator_client.gd   hand-rolled Engine.IO/Socket.IO client over WebSocketPeer
scenes/
  main.gd / main.tscn   the playable scene (HUD, hand, targeting, scenarios, status)
  board_view.gd         board rendering + input + spawn/merge tweens
tests/                  McpTestSuite parity tests + tests/golden/ (vectors from the TS dist)
tools/                  headless verifiers, smokes, and run_validator.sh
GODOT_PORT_PLAN.md      the working plan / architecture / status
```

## Architecture

A hard wall separates **deterministic logic** from **presentation**:

```
input → action → engine/ (pure) → new state + hash → scenes/ render
                                 → net/ validator confirms
```

- `engine/` is pure GDScript: state is a `Dictionary` mirror of the TS
  `SynchronizedGameState`; tiles are a flat row-major `Array` of `Dictionary`s.
  GDScript `Dictionary`/`Array` are reference types, which lets the port reproduce
  the original `merge.ts` in-place-mutation semantics exactly.
- The client plays **optimistically** (applies each move locally for instant
  feedback) and, when online, sends the predicted state hash to the validator. A
  matching hash ACKs on the fast path; a mismatch returns the authoritative state.

## Testing

Two complementary harnesses, both checking parity against vectors generated from
the real TS `@spyre-io/moveborne-logic` dist:

- **Editor suite** (`McpTestSuite` in `res://tests/test_*.gd`) — run via the
  `godot-ai` MCP `test_run` (4 suites: determinism, engine_swipe, playcard, combined).
- **Headless verifiers** (`tools/verify_*.gd`) — no editor needed:

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
      --script res://tools/verify_engine_swipe.gd
  ```

  One per engine module (powercards, validation, tile_effects, totems, events,
  scenarios) plus engine_swipe / playcard / combined / the validator client.

## License / source

This port targets the Moveborne game owned by The Golden Mule. Game design and the
authoritative rules engine live in the `moveborne` repository.
