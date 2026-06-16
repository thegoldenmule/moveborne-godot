# Moveborne → Godot 4.6 Port — Implementation Plan

> Status: **planning**. Derived from a 15-agent investigation of `~/projects/thegoldenmule/moveborne`
> (TS rules engine `src/logic`, PixiJS client `src/game`, Nakama Go server `src/server`, Bun validator `src/validator`, spec `spec/game`).
> This file is the working checklist. Code in the original repo is the **source of truth** over the markdown specs.

---

## 1. What we're porting

**Moveborne** is a 2048-style swipe-merge puzzle with layered tactics:
- Swipe a 4×4–8×8 board; matching tiles merge (value ×2), build combos, earn score + shards.
- **Tile effects** (8): `none`, `freeze`, `black_hole`, `amplify`, `amplify_static`, `lock`, `decay`, `stone`.
- **Power cards** (26 types) played from a 3-card hand: bomb, destroy, clear, swap, teleport, vortex, double, lightning, radiate, shuffle, split, clone, multiply, transform, + totem-spawners.
- **Totems** (11 types, max 3 active): persistent passive modifiers (combo-saver, spawn-boosters 2×/4×/8×, momentum-idol, magnet-core, void-gate, ghost-merge, scavenger, chrono-anchor…).
- **Scoring**: combo multiplier grows by #tiles merged per swipe; shards (1/merge, cap 8) auto-draw a card and can be spent (7) to clear black holes.
- **Events**: triggers on combo-break / score-milestone / merge-count / move-count spawn effects.
- **Scenarios**: ~25 predefined configs (tutorials 0–6, challenges 7–12, tests 100–106, board-size 200–202).
- **Match wrapper**: 3-minute timer, 3-second countdown, optimistic client + authoritative reconciliation.

---

## 2. Source-of-truth map (what to read while porting each piece)

| Godot subsystem | Authoritative TS / spec |
|---|---|
| Deterministic RNG | `src/logic/src/random.ts` (npm `seedrandom@3.0.5`) |
| State hash + canonical JSON | `src/logic/src/hashing.ts` (custom hash + `json-stable-stringify`) |
| Core data model | `src/logic/src/types.ts`, `constants.ts`, `index.ts` |
| Board / movement / merge | `board.ts`, `merge.ts`, `gameLogic.ts` + `spec/game/board.md` |
| Tile effects | `tileEffectLogic.ts`, `tileEffectSpawn.ts` + `spec/game/tile-effects.md` |
| Power cards | `powerCards.ts`, `cardDraw.ts`, `validation.ts` + `spec/game/power-card*.md` |
| Totems | `totemLogic.ts` + `spec/game/totems.md` |
| Scoring / combos / shards | `shards.ts`, `gameLogic.ts` + `spec/game/scoring.md` |
| Events | `eventSpawnProcessor.ts`, `eventTriggerState.ts` + `spec/game/events.md` |
| Scenarios / board build | **`src/game/engine/scenarios.ts`** (source of truth), `boardBuilder.ts`, `factories.ts` |
| Action pipeline | `actionExecutor.ts`, `globalEffects.ts` |
| Rendering / FX (to replace) | `src/game/engine/render/*`, `fx/*`, `animation/*` |
| Controllers / input | `src/game/engine/controllers/*`, `engine.ts`, `core/event-bus.ts` |
| Client↔server sync | `src/game/engine/server/*`, `utils/*`, `js-sdk/core/*` |
| Nakama integration | `src/server/**` (Go runtime module), `spec/server/**` |
| Validator | `src/validator/**`, `spec/validator/**` |

---

## 3. Target architecture in Godot

**Hard wall between deterministic logic and presentation.** One-way data flow:
`input → action → GameEngine (pure) → new state + events → presentation reconciles (tweens/particles/shaders)`.

### Autoloads (pure GDScript, RefCounted-backed, zero scene refs in logic)
- **`RNG`** — seedrandom-compatible namespaced ARC4 PRNG (5 streams: `tile-gen`, `shuffle`, `effect-spawn`, `totem-spawn`, `card-draw`).
- **`Hasher`** — `canonical_stringify()` + the custom 8-lane rolling hash.
- **`GameEngine`** — `apply_action(state, action) -> {state, events}`. State is nested `Dictionary`/`Array` mirroring `SynchronizedGameState` with **exact key names** and **load-bearing array order**.
- **`NetClient`** — Nakama HTTP/RPC + realtime socket; (optionally) validator HTTP + Socket.IO. Owns the optimistic operation queue + reconciliation.
- **`EventBus`** — small signal hub mirroring the TS EventBus (`operation` out; `MATCH_START`/`GAME_STATE`/`MATCH_END` in).

### Presentation scenes
- `Main` (Control/Node2D root) → `Board` (instances a reusable `Tile.tscn`) + `CanvasLayer` HUD (score/combo/shards Labels) + `Hand` (HBoxContainer of `Card` Controls) + totem tray.
- FX: `GPUParticles2D` bursts (spawn/merge/destroy/bomb/lightning), `AnimationPlayer` per tile (pop/spawn/shake/slide), `ShaderMaterial` overlays (freeze/decay/stone) + full-screen **glitch** `ColorRect` on a top CanvasLayer driven by `GlobalEffectState.filterConfig`.
- Input: `InputEventScreenTouch`/`ScreenDrag` (or emulated mouse) on a STOP-mouse_filter full-rect Control → reduce gesture to a **direction enum only** (no coords leak into state) → one-gesture-one-SWIPE, debounced while animating / round-trip pending.

### Tooling
- Author scenes/scripts via the **`godot-ai` MCP** (`node_create`, `scene_manage`, `script_create/patch`, `autoload_manage`, `animation_manage`, `particle_manage`, `material_manage`, `signal_manage`, `input_map_manage`, `project_run`, `test_run`, `editor_screenshot`).
- Tests = `res://tests/test_*.gd` subclasses of `McpTestSuite` (built-in runner, **not** GUT). Every test must make ≥1 assertion or it auto-fails; name throwaway nodes `_McpTest*`.
- **In-editor authoring tools** build on `addons/editor_tool_kit/` — shared bases (`EditorToolPlugin` + `ToolService` + dock, optional `BridgeServer`, plus the `ContentStore` / `EditorToolUi` helpers). A tool is a *service + a view*: the service owns state/mutations/save and stays headless-testable (no `Control`/`EditorInterface` deps), the dock renders. Consumers: `addons/artgen/` (with a `:4848` MCP bridge) and `addons/story_map_editor/` (dock-only). Recipe: `addons/editor_tool_kit/README.md`.

---

## 4. The crux: determinism (highest risk, do first)

The client runs the engine locally and computes a **state hash**; the validator (which reuses the *same* `src/logic`) re-derives state + hash and either confirms or sends corrected authoritative state. **A perfect port matches every move (smooth optimistic play); an imperfect port still yields a correct, playable game (it just snaps to server state).** So determinism is a polish/UX axis, not a correctness gate — but we want it tight.

Three things must be reproduced **byte-for-byte**:

1. **RNG — `seedrandom@3.0.5` default (ARC4).**
   - Per namespace: `seedrandom(seed.toString())` (base-10 string of the int seed → keyed by its ASCII bytes, e.g. seed `4` → byte `0x34`).
   - The **default** callable returns a **53-bit double**: `n = arc4.g(6)` over `startdenom = 256^6`, extended by a significance loop (`while n < 2^52`) drawing single bytes, then an overflow normalize — returns `(n + x) / d`. (It is **not** the 32-bit `.quick()`/`.int32()` variant.) ⚠️ The two investigation agents disagreed 32-bit vs 53-bit — **resolve empirically** (see step 0).
   - State is restored by **re-seeding + replaying `index` draws** (no opaque state blob). Per-stream draw **count and order** must match TS exactly.
   - Consumption patterns: `floor(rng()*count)` for index selection; `rng() < threshold` for probability (e.g. new tile `<0.9 ? 2 : 4`). Strict `<` on exact float bits.

2. **State hash — custom 8-lane rolling hash (NOT real SHA-256, despite the name).**
   - Lanes h0..h7 init to the SHA-256 IVs; per UTF-8 byte: `h = ((h << k) - h + byte) | 0` with shifts `5,7,11,13,17,19,23,29`.
   - Output: `(h >>> 0).toString(16).padStart(8,'0')` × 8 → 64 hex chars.
   - GDScript (64-bit ints): emulate `|0` (signed 32-bit wrap) and `>>>0` (mask `& 0xFFFFFFFF`).
   - ⚠️ There is also an **async** path using *real* WebCrypto SHA-256 — different output. Confirm the sync custom hash is what the wire protocol compares.

3. **Canonical JSON — `json-stable-stringify(state, {space: 2})`.**
   - Keys sorted lexicographically (UTF-16 code unit) at every depth; 2-space pretty-print; arrays keep order; `undefined`/missing optional fields **omitted**; numbers via JS `String(n)` (ints no `.0`, floats shortest round-trip).
   - Do **not** use Godot `JSON.stringify` (no key sort, different spacing/number format). Write a custom recursive serializer. **Number→string formatting is the #1 landmine** — keep counts/scores/board values as ints; the only non-integer floats in synced state are `globalEffects[].filterConfig.seed/offset` (confirm whether globalEffects is in the hashed state).

**Other exact-match rules:** `moveIndex += 2` when a swipe auto-draws a card (else `+1`); `score = newState.score + scoreAdded` accumulated by the caller; RNG draw sequences differ between the *moved* and *not-moved* swipe branches; `processGlobalEffects` consumes **2 `effect-spawn` draws per surviving effect, 0 for expiring** (in array order).

**Validation method:** generate **golden vectors** from the real TS package (run it once in Node) — first ~50 RNG outputs per namespace/seed, and `computeStateHash` of known states — and assert byte-equality in GDScript `McpTestSuite` tests. Then replay the repo's history fixtures (`src/game/fixtures/history/*.json`) through the GDScript engine and assert identical hashes per move.

---

## 5. Backend reality check (important — affects "reuse the server")

- **`src/server` is a Nakama runtime module** (`heroiclabs/nakama-common`): device auth, Turnkey/Movement web3 wallet, matchmaking + brackets, glicko2 elo, leaderboards, daily/rewards, economy, realtime socket transport, clock-sync, match lifecycle. **All of this infra is reusable.**
- **BUT its in-match handler is named `"hangman"` with hangman opcodes** (`OpCodeLetter`, `OpCodeLetterCorrect`, `OpCodeMatchRoundSolved`…). It does **not** contain tile-merge gameplay. The `moveborne` namespace + `hangman` MatchName looks like a fork/rename-in-progress.
- The reference web client does **not** play through Nakama match opcodes — it plays the gameplay loop through the **Validator** (`src/validator`, Bun + Socket.IO), which imports the same `src/logic`. Documented flow: Nakama signs the starting state → client inits the validator → client validates each move over Socket.IO → client submits signed moves back to Nakama.
- **There is no maintained official Nakama GDScript SDK for Godot 4.x**, and **Godot has no native Socket.IO client.** Both wire protocols would be hand-rolled (HTTP/RPC + realtime envelope for Nakama; Engine.IO/Socket.IO over `WebSocketPeer` for the validator).

➡️ **Open question for the project owner:** what is the intended *online* gameplay path for Moveborne — the validator (+Nakama orchestration), or a new Moveborne Nakama match handler? Until that's settled, the plan front-loads the **fully-playable local-authoritative** build (no backend dependency), which is valuable on its own and identical in logic to the eventual networked build.

---

## 6. Phased roadmap

### Phase 0 — Determinism foundation  ✅ COMPLETE (2026-06-03)
- [x] Generate golden vectors from real TS packages → `tests/golden/determinism_golden.json` (+ `generate_golden.js`, vendored `seedrandom-3.0.5-reference.js`).
- [x] Resolved: default `seedrandom()` returns the **53-bit double** (`g(6)` + significance loop), not 32-bit.
- [x] `logic/rng.gd` (`class_name MbRng`): ARC4 KSA + RC4-drop[256] + 53-bit `draw()` + `mixkey`. **Proven bit-exact** (180 assertions: 9 seeds × 20 draws via f64 big-endian comparison).
- [x] `logic/hasher.gd` (`class_name MbHasher`): canonical serializer (sorted keys, 2-space, JS number format, **`[\n  ]` empty array**, **null-key omission**) + 8-lane rolling hash. **Proven exact** (hash + canonical round-trip vectors).
- [x] `tests/test_determinism.gd` (`McpTestSuite`): **5 tests, 197 assertions, all green** via the godot-ai `test_run`.
- Design note: `RNG`/`Hasher` implemented as static `class_name` utility classes (pure functions) rather than autoloads — cleaner and directly testable editor-side. The stateful `GameEngine`/`NetClient` autoloads come in Phase 1/3. A 5-namespace `RandomGenerator` wrapper (TS `random.ts` parity) is added in Phase 1.
- Housekeeping: `MbRng`/`MbHasher` register as global `class_name`s on the next full editor scan; the suite uses `preload()` meanwhile, so nothing is blocked.

### Phase 1 — Pure deterministic engine (GDScript)
**Spine ✅ DONE (2026-06-03)** — swipe-only path proven byte-exact against the TS dist oracle:
- `logic/constants.gd` (`MbConstants`): full `POWER_CARDS` (26, insertion-ordered) + `TOTEM_TYPES` (11) catalogs + scalars.
- `logic/random_generator.gd` (`MbRandom`): 5-namespace RNG on `MbRng`, reseed+replay.
- `logic/engine.gd` (`MbEngine`): `perform_swipe` (4 dirs), spawn (2 tile-gen draws, 90/10), combo, score, shards, auto-draw, `execute_swipe_action` + caller overrides (score accumulate, rngIndices, moveIndex+2-on-draw). Tile-effects/totems/events/global-effects are faithful **no-op stubs** (verified to consume 0 RNG / add 0 state when inactive).
- `tests/test_engine_swipe.gd`: threads a 20-move golden (with 2 card draws) → **every per-move state hash matches** (`tests/golden/engine_swipe_golden.json`, via `generate_engine_golden.mjs`). Full suite: **7 tests / 2 suites green**.
- Key finding: real board states are **clean row-major**; reference-semantics (`Dictionary`/`Array` are GDScript reference types) reproduce the JS `merge.ts` mutation behavior for free.

**Breadth modules ✅ PORTED + VERIFIED (2026-06-03)** — 6-agent parallel workflow, each self-verified headlessly against dist-generated goldens (~5,470 parity cases):
- [x] `logic/powercards.gd` (`MbPowerCards`) — 14 `performPowerCard*` (46 cases). *transform/shuffle consume the `shuffle` namespace, not effect-spawn.*
- [x] `logic/validation.gd` (`MbValidation`) — 28 target/playability predicates (5244 cases).
- [x] `logic/tile_effects.gd` (`MbTileEffects`) — merge/move gating, black hole, on-merge, effect spawn (64 cases).
- [x] `logic/totems.gd` (`MbTotems`) — `processTotemEffects` + 11 totem handlers (57 cases). *swipe-durations not implemented in code; uses moves/merges/tallyMarks.*
- [x] `logic/events.gd` (`MbEvents`) — trigger machine + event spawn (17 cases). *only `COMBO_BREAK` + `SCORE_UPDATE` routed.*
- [x] `logic/scenarios.gd` (`MbScenarios`) — `buildInitialBoard` + scenario table + factories (45 cases).
- [x] `MbHasher` float formatting upgraded to JS shortest-round-trip (globalEffects `filterConfig.seed` now hashes correctly).

**Integration ✅ — engine functionally complete (2026-06-03):**
- [x] **PLAY_CARD** — `execute_play_card_action` + `step_card` (8-case oracle green; combo-reset rules, card splice, shuffle RNG).
- [x] **Swipe-pipeline integration** — `perform_swipe` rewritten to the full `merge.ts` logic calling `MbTileEffects` (black-hole path destruction, merge/move gating, on-merge amplify/lock consumption, effect preserve/transfer, freeze removal); all `processTotemEffects` hooks → `MbTotems`; `MbEvents` (reset/updateTriggerStates + COMBO_BREAK/SCORE_UPDATE spawn) + `attempt_spawn_effect_on_tile` wired.
- [x] **SPAWN_TOTEM** — `execute_spawn_totem_action` + `step_totem` (deterministic id `totem_{moveIndex+1}_{type}`).
- [x] **Combined parity gate** — oracle with active amplify/black-hole/lock effects + momentum-idol/scavenger/combo-saver totems + card play + totem spawn → every hash matches. **Editor suite: 10 tests / 4 suites green** (combined, determinism, engine_swipe, playcard); 7 headless module verifiers green.
- [ ] *Deferred (minor):* `globalEffects.ts` tick (no-op stub until a scenario spawns Glitch full-screen effects); wire `MbScenarios.build_initial_board` for local match start; replay `src/game/fixtures/history/*.json` as extra validation.

➡️ **Phase 1 (deterministic engine) is done.** SWIPE + PLAY_CARD + SPAWN_TOTEM with all subsystems active, byte-exact vs the TS engine/validator. Next: **Phase 2 — the playable Godot scene.**

### Phase 2 — Playable single-player (local-authoritative)  *(major milestone)*
**Playable slice ✅ (2026-06-03)** — renders + responds, driven by the byte-exact engine, no backend:
- [x] `game/match_controller.gd` (`MbMatch`): local "mock server" — `new_game` (4×4 + 2 spawned tiles), `swipe`/`play_card` through `MbEngine`.
- [x] `scenes/main.gd` + `main.tscn` (set as main scene): procedural 2048-style board + HUD (score/combo/shards/moves), tile colors by value + effect borders.
- [x] Swipe input (arrow keys + touch/mouse drag → direction enum) → `MbEngine.step`.
- [x] Verified live via godot-ai MCP: board+HUD render; injected swipes slide tiles, merge 2→4, update score/shards (screenshot confirmed). `tools/smoke_match.gd` headless smoke PASS.

**Phase 2 ✅ feature-complete (2026-06-03):**
- [x] Hand UI (`scenes/main.gd` card row) + card selection + tap-to-target play (single tile / column / quadrant / two-tile / no-target / totem-spawn) via a targeting state machine; card consumed + HUD/board update verified live (bomb cleared a tile).
- [x] Totem tray (active totems) + totem-spawn from totem cards (`spawn_totem`).
- [x] `scenes/board_view.gd` (`MbBoardView`): rendering + **spawn/merge pop tweens** + effect-colored borders (freeze=blue, amplify=yellow, black-hole=indigo, …) + pointer→swipe/tap.
- [x] Scenario picker: keys `0–7` load `MbScenarios` configs (startingCards + spawnConfigs + eventRules) via `new_game_scenario`; verified live (scenario 1 dealt bomb+swap, effects spawned during play).
- [~] *Optional polish:* **particle/shader FX** — see **`VFX_MAPPING.md`** (full Moveborne→Godot VFX reference + roadmap). Shipped (2026-06-04, verified live): status/`moveIndex`-driven trigger arch in `board_view`, the `Vfx` autoload (CPUParticles2D dispatcher + `EMITTERS` table) + board `_vfx_layer`, and the **merge feedback trio** (purple burst + white bg-flash + value-scaled board shake) [roadmap P0a+P1]. Started: particle presets for new/bomb/destroy/purge/amplify [P2, partial]. Still TODO: tile-effect emitters, glow shaders, full-screen glitch, HUD/doober/floating-text, slide animations.

➡️ **Phase 2 is a complete, playable single-player game** (swipe + cards + totems + effects + scenarios), no backend, driven by the byte-exact engine. Next: **Phase 3 — networking** (or the optional Phase 2 FX polish).

### Phase 3 — Networking
**Validator integration ✅ (2026-06-03) — Nakama omitted per owner.**
- [x] **Validator client** — `net/hermes_client.gd` (`MbHermesClient`): **protobuf Hermes envelope over `WebSocketPeer`** (godobuf bindings in `net/proto/`). One codepath for both targets: local validator's Hermes-emulation WS or the deployed gateway Hermes WSS (`?token=` auth). InitMatch → ready, ValidateAction (mid-correlated) → match keeps optimistic / mismatch adopts authoritative state, CompleteMatch settles rewards. (Replaced the original hand-rolled Engine.IO/Socket.IO client.)
- [x] **Wired into the game** — `match_controller.gd` sends a `validate_action` per committed swipe/card/totem; `main.gd` `V` connects, status label shows ✓/✗ per move.
- [x] **Run the validator** locally (no gateway; the client self-stamps the `User-Id` the validator binds to): `tools/run_validator.sh` wraps this repo's self-contained `validator/` (Bun workspace; the `workspace:*` logic dep satisfied via the committed prebuilt dist). Health on `:5555`.
- [x] **Live parity verified**: the validator confirmed the running Godot game's moves with `hash_match=true` (moves 0/1/2); UI shows "validator: ✓ move N ok". The byte-exact engine means the optimistic fast-path hits every move.
- [ ] *Deferred:* Nakama client (auth/matchmaking) — omitted by choice; full `NetClient` optimistic core (op queue cap 10 + backpressure, rollback/replay) — current path adopts server state directly on mismatch, sufficient for single-player-vs-validator.

➡️ **The Godot client now plays against the real validator service, no Nakama.**

### Phase 4 — Polish & parity
- [ ] VFX/polish per **`VFX_MAPPING.md`** roadmap: HUD build + `Anim` helper (P0b/c), particle Wave 1 finish (P2), countdown/banner (P3), floating text + doober (P4), combo pop + glow shaders (P5–P6), `Quality` tiers (P7), black-hole + full-screen glitch (P8/P10, glitch needs `engine.gd:293 _process_global_effects` completed — golden-verified), streak shader (P11).
- [ ] Cross-client parity harness (shared history fixtures).
- [ ] Mobile build verification (Forward Mobile shader compile); optional web export.

---

## 7. Known divergences & gotchas (code beats spec)
1. **Scenarios source of truth = `src/game/engine/scenarios.ts`**, which diverges from `spec/game/scenarios.md`.
2. **Decay value-reduction is NOT implemented** — only its movement/merge flags are active.
3. **Totem swipe-based durations are NOT implemented** — durations use `movesRemaining`/`mergesRemaining`/`tallyMarks`.
4. **Only `COMBO_BREAK` + `SCORE_UPDATE` events are routed** to the spawner (others speced but inert).
5. **Only Glitch (global, in synced state), Glow (high-value tiles), Twist (black hole) filters exist**; most of `full-screen-effects.md` is an unimplemented brainstorm.
6. **Two engine copies**: `src/logic/src` (shared, used by the validator — rules authority) vs `src/game/engine` (client copy + rendering/controllers/scenarios). Port rules from `src/logic`; UI/scenarios from `src/game`.
7. **`seedrandom` default = 53-bit double** (resolve vs 32-bit empirically before trusting anything downstream).
8. **Sync custom hash** (not real SHA-256) is what `computeStateHash` uses — confirm it's the wire hash.
9. **`moveIndex += 2`** on auto-draw; **score accumulation** (`newState.score + scoreAdded`) done by the action-executor caller.
10. Pending-op replay orders by `Date.now()` (same-ms ties undefined) — prefer ordering by `moveIndex`/monotonic counter in the port.

---

## 8. Decisions (locked 2026-06-03)
- **v1 scope**: ✅ **Local-authoritative single-player first** (Phases 0–2). Networking deferred to Phase 3.
- **v1 content**: ✅ **Vertical slice first** — core swipe/merge/score + a handful of tile effects, a few power cards, and one totem, on 1–2 scenarios; prove the full pipeline end-to-end, then expand to all 8 effects / 26 cards / 11 totems / ~25 scenarios.
- **Target platform**: ✅ **Native mobile + desktop (dev)**. No web export for v1 (revisit later for parity testing).
- **Online gameplay authority** (Phase 3): ✅ **Validator + Nakama** — Nakama orchestrates (device auth / Turnkey web3 / matchmaking / economy / leaderboards), the Validator service (`src/validator`, reusing `src/logic`) is the move authority over Socket.IO, exactly as the web client does. Both transports (Nakama HTTP+socket, validator Socket.IO/Engine.IO) will be hand-rolled over `HTTPRequest`/`WebSocketPeer`.

### Immediate next steps (Phase 0)
1. Generate golden vectors from the real TS: `seedrandom@3.0.5` outputs per namespace/seed, `computeStateHash` of sample states, `json-stable-stringify` samples.
2. Resolve seedrandom default = 32-bit vs 53-bit against the vectors.
3. Stand up + verify `RNG` and `Hasher` autoloads against the vectors (GDScript `McpTestSuite`).
