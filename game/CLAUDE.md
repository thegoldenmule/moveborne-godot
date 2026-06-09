# CLAUDE.md — working notes for this repo

Godot 4.6 (GDScript) port of **Moveborne** (a 2048-style merge puzzle). See
`README.md` for the overview and `GODOT_PORT_PLAN.md` for architecture + status.

## Prime directive: determinism parity

The `logic/` code is a **byte-for-byte deterministic port** of the TypeScript
`@spyre-io/moveborne-logic` package: it computes the **same state hashes** as the TS
engine and the validator service. (Why this matters, plus the optimistic-reconciliation
model it buys, is recorded in the ADRs `byte-for-byte-determinism-parity-…` and
`optimistic-client-updates-…` under `../wiki/hypercasual-llm/adrs/`.) Treat the parity
tests as load-bearing:

- **Never change `logic/` behavior without re-running the parity tests.** If a
  golden hash changes, you broke compatibility — figure out why before committing.
- The TS source is the **source of truth**: `~/projects/thegoldenmule/moveborne/src/logic/src`
  (rules) and `src/game/engine/scenarios.ts` (scenario table). **Code beats spec**
  (`moveborne/spec/game/*.md` is a guide and sometimes diverges).
- When porting/extending logic, mirror the TS exactly — including iteration order,
  RNG draw order/count per namespace, and which fields are present in state.

## Repo map

```
logic/   pure rules engine (no Node/scene deps). class_name Mb* + static funcs.
          rng.gd, hasher.gd, random_generator.gd, constants.gd, engine.gd,
          powercards.gd, validation.gd, tile_effects.gd, totems.gd, events.gd, scenarios.gd
game/     match_controller.gd (MbMatch): state + new_game/swipe/play_card/spawn_totem,
          optional validator hookup.
net/      validator_client.gd (MbValidatorClient): Engine.IO/Socket.IO over WebSocketPeer.
scenes/   main.gd/.tscn (playable scene), board_view.gd (render + input + tweens).
tests/    McpTestSuite parity tests; tests/golden/ holds vectors + the *.mjs generators.
tools/    verify_*.gd (headless parity), smoke_*.gd, run_validator.sh.
```

## How the engine works (mental model)

The state shape, the engine contract (`MbEngine.step / step_card / step_totem` + the
validator's caller-overrides), the 5 RNG namespaces, and the hashing are documented in
full in the wiki — read these before editing `logic/`:
`../wiki/hypercasual-llm/architecture/client/rules-engine.md`,
`.../client/determinism-primitives.md`, and the **Data model** section of
`.../client/index.md`.

The one trap worth inlining, because GDScript makes it easy to get wrong: **reference
semantics.** `Dictionary`/`Array` are reference types like JS objects/arrays — the port
reproduces `merge.ts` with shallow `.duplicate()` (mirroring `[...arr]`/`{...obj}`),
in-place tile mutation where the TS mutates, and fresh dicts for merged/spawned tiles.
**Do not deep-copy unless the TS does** — it changes identity/aliasing and breaks hashes.

## Editing + testing loop

Write `.gd` files (Write tool or editor), then **`filesystem_manage reimport`** the
changed paths so the editor sees them.

Run parity tests two ways:

```bash
# Headless (no editor) — one per module/integration:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --script res://tools/verify_engine_swipe.gd      # VERIFY ...: PASS/FAIL

# Editor suite (McpTestSuite) — via the godot-ai MCP:  test_run
```

**Always run the relevant verifier(s) after touching `logic/`.** When adding new
logic, generate an oracle from the real TS dist (the `tests/golden/*.mjs` generators
import a copy of `moveborne/src/logic/dist/index.js` with `seedrandom` +
`json-stable-stringify` installed), dump expected hashes, and assert them in a
verifier/suite — never hand-write expected values.

## Running things

- **Game:** open in Godot 4.6 and Play, or via MCP `project_run` + `editor_screenshot`
  (`source:"game"`). Inject input with `game_manage input_key` — note keys are
  **names** (`"Left"`, `"V"`), not keycodes; `input_mouse` uses `event:"button"` +
  `position`. `get_ui_elements` returns exact rects for clicking.
- **Drive the game by game concepts** (swipe / read board / play card): use the
  `MbDebug` autoload via `game_eval` (e.g. `return MbDebug.get_state()`), the Godot
  analog of the TS `window.__moveborne`. Full reference: **`MCP_GAME_API.md`**.
- **Validator:** `tools/run_validator.sh` (DEV_MODE, `:5555`) wraps this repo's
  self-contained `validator/` (the `workspace:*` logic dep is the committed prebuilt
  dist), or `cd ../validator && bun run dev`. Endpoints + the MCP debug tools are in
  `../validator/README.md` and `../validator/src/validator/CLAUDE.md`.

## GDScript gotchas (learned the hard way)

- `str(float)` caps at ~14 significant digits and won't round-trip. Use
  `MbHasher._num_float` (shortest round-trip, JS-compatible) for any hashed float.
  Keep integral state values as `int`.
- `%g` / `%.17g` are **not** valid in GDScript `%` formatting — use `%s` / `str()`.
- `Engine` is a reserved native class name — don't use it as an identifier (the
  engine script is referenced as `MbEngineS := preload(...)` in tests/scenes).
- `class_name` globals do **not** register from `reimport` alone — tests/scenes
  reference engine classes via `preload("res://logic/x.gd")`. A full editor scan
  registers the `Mb*` globals.
- `McpTestSuite`: every `test_*` must make ≥1 assertion or it auto-fails; name
  throwaway nodes `_McpTest*`.
- Headless scripts: `extends SceneTree`, do work in `_initialize()` and `quit(code)`.
  Anything needing the tree (e.g. `HTTPRequest.request()`, which else returns
  `ERR_UNCONFIGURED`) must run after the tree is ready — defer with
  `_start.call_deferred()`. There's no `timeout` on macOS; use `--quit-after N`.
- JSON parsing yields int or float ambiguously; the canonical serializer handles
  integer-valued floats, and the engine `int()`-casts reads — keep that robustness.

## Conventions

- **Git: commit directly to `main`.** Never create a feature branch and never ask
  to — `git add` + `git commit` on `main` as-is.
- Engine classes are `class_name Mb<Thing>` with static functions; no Node/scene
  references in `logic/`.
- Commit `.gd.uid` files alongside their scripts (Godot stable references).
- Keep `GODOT_PORT_PLAN.md` and the project memory up to date as phases progress.
- Don't add features the engine can't back deterministically; if unsure whether a
  change preserves parity, prove it with a golden before committing.
