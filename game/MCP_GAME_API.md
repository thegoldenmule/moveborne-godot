# MCP_GAME_API.md — `MbDebug`, the game-semantic control layer

`MbDebug` is the Godot analog of the TypeScript game's `window.__moveborne` debug API.
It lets an LLM (or any automation) **drive the running game by game concepts** — swipe
a direction, read the board, play a card with targeting — instead of by pixel taps and
scene-tree walks. Plays route through the real UI scene, so the board, hand, and VFX
animate exactly as they do for a human player.

- **Implementation:** `game/mcp_game_api.gd` (autoload singleton `MbDebug`) +
  thin `mcp_*` wrappers on `scenes/main.gd`.
- **Mirrors:** `moveborne/src/game/components/match/Play.tsx` (`window.__moveborne`).
- **Parity-safe:** nothing under `logic/` is touched; `MbDebug` only calls the
  already-tested `MbMatch` / `main.gd` paths. See `CLAUDE.md` for the parity rules.

> **For driving the menus** (navigate screens, press buttons, run scripted UI
> sequences) use `MbUi`, the navigation analog of `MbDebug` — see **`MCP_UI_API.md`**.
> `MbDebug` owns in-match board/cards; `MbUi` owns everything around the match.

---

## How to invoke

Every call goes through the **godot-ai MCP `game_eval`** command, which runs a GDScript
snippet inside the running game process and returns the (JSON-serialized) result.

1. **Start the game** first: `mcp__godot-ai__project_run` (or open `scenes/main.tscn`
   and Play). `MbDebug` is only live while the game is running.
2. **Call it** with a snippet that returns a value (use `return` to get data back):

   ```gdscript
   return MbDebug.is_ready()          # readiness
   return MbDebug.get_state()         # full state
   MbDebug.swipe("up")                # mutate (no return needed)
   return MbDebug.play_card(2)        # -> {"status":"awaiting_selection","selection_mode":"tile"}
   return MbDebug.select_tile(1, 3)   # -> {"status":"complete"}
   ```

3. **See the result** of a mutation with `mcp__godot-ai__editor_screenshot`
   (`source:"game"`) — the board/hand will have animated.

When no match scene is live, every method returns
`{"ok": false, "reason": "not_ready"}` instead of erroring.

---

## Method reference

### Readiness
| Method | Returns | Notes |
| --- | --- | --- |
| `is_ready()` | `bool` | True when a match is live with a board. Analog of `__moveborne.isReady`. |

### Movement (mutating — routes through the UI, animates)
| Method | Returns |
| --- | --- |
| `up()` / `down()` / `left()` / `right()` | `{ok, moved, move_index}` |
| `swipe(direction)` | `{ok, moved, move_index}` — `direction` ∈ `"up"/"down"/"left"/"right"` |

`moved` is whether any tile actually shifted; the engine still advances state (and may
spawn a tile) on a non-moving swipe, matching Moveborne. Any in-progress card selection
is cancelled before the swipe.

### Reads (non-mutating)
| Method | Returns |
| --- | --- |
| `get_state()` | full synchronized state `Dictionary` (see **State shape**) |
| `get_board()` | `{tiles: [...row-major...], size}` |
| `get_cards()` | `[{index, id, type, name}]` — the hand |
| `get_playable_cards()` | `[{index, type, name, selection_mode}]` — only currently-playable cards |
| `get_tile(row, col)` | tile `Dictionary`, or `null` if empty / out of range |

### History (mirrors `__moveborne.getHistory/getSnapshot/getHistoryCount`)
| Method | Returns |
| --- | --- |
| `get_history()` | `Array` of state snapshots, oldest first |
| `get_snapshot(move_index)` | the snapshot whose `moveIndex == move_index`, or `null` |
| `get_history_count()` | `int` |

`MbDebug` captures a deep-copied snapshot on every committed move (it listens to
`MbMatch.changed`). History resets automatically when a new game/scenario starts.

### Cards (mutating — two-step targeting, through the UI)
| Method | Returns |
| --- | --- |
| `play_card(card_index)` | `{status, selection_mode?, message}` (see below) |
| `select_tile(row, col)` | `{status, ...}` |
| `select_column(col)` | `{status, ...}` |
| `select_card(card_index)` | alias of `play_card` |
| `cancel()` | `{ok}` — abort an in-progress selection |

`play_card` returns one of:
- `{status:"complete"}` — totem card or no-target card (`shuffle`, `transform`) played
  immediately.
- `{status:"awaiting_selection", selection_mode:"tile"|"column"|"quadrant"|"two"}` —
  the card needs target(s); supply them with `select_tile` / `select_column` (see the
  **Power-card** table for how many taps each kind needs).
- `{status:"error", message}` — invalid index or a card with no board action yet.

### Lifecycle
| Method | Returns |
| --- | --- |
| `new_game(seed = -1)` | `{ok, scenario, move_index}` — fresh Endless game (with intro) |
| `load_scenario(id, seed = -1)` | `{ok, scenario, board_size, move_index}` |

Pass an explicit `seed` for a reproducible match (the engine is deterministic).

### Utility
| Method | Returns |
| --- | --- |
| `inspect()` | compact summary `{scenario, move_index, score, shards, combo_multiplier, cards, board_size, non_empty_tiles, history_count}` |
| `help()` | `String` listing the commands |

---

## `__moveborne` (JS) ↔ `MbDebug` (GDScript) mapping

| `window.__moveborne` | `MbDebug` | Notes |
| --- | --- | --- |
| `isReady` (getter) | `is_ready()` | method, not a property |
| `up/down/left/right/swipe` | same (snake unchanged) | |
| `getState` | `get_state` | |
| `getBoard` | `get_board` | |
| `getCards` | `get_cards` | |
| `getPlayableCards` | `get_playable_cards` | |
| `getTile` | `get_tile` | |
| `getHistory` | `get_history` | |
| `getSnapshot` | `get_snapshot` | |
| `getHistoryCount` | `get_history_count` | |
| `playCard` | `play_card` | **two-step** (see below) |
| `selectTile` | `select_tile` | |
| `selectColumn` | `select_column` | |
| `selectCard` | `select_card` | alias of `play_card` |
| `help` / `inspect` | `help` / `inspect` | |
| — | `new_game` / `load_scenario` / `cancel` | Godot extras (scenario/intro driven by `main.gd`) |

---

## Power-card action & param reference

The LLM does **not** build param dicts by hand — `play_card` + `select_*` handle that
via `main.gd`'s `TARGET` map. This table shows what each card needs.

| Card `type` | `selection_mode` | Taps after `play_card` | Underlying engine params |
| --- | --- | --- | --- |
| `bomb` | `tile` | 1 tile | `{tile:{row,col}}` |
| `destroy` | `tile` | 1 tile | `{tile:{row,col}}` |
| `double` | `tile` | 1 tile | `{tile:{row,col}}` |
| `split` | `tile` | 1 tile (value ≥ 4) | `{tile:{row,col}}` |
| `multiply` | `tile` | 1 tile | `{tile:{row,col}}` |
| `radiate` | `tile` | 1 tile (3×3 AoE) | `{tile:{row,col}}` |
| `clear` | `column` | 1 cell in column | `{column}` |
| `lightning` | `column` | 1 cell in column | `{column}` |
| `vortex` | `quadrant` | 1 cell = 2×2 top-left | `{row, column}` |
| `swap` | `two` | 2 tiles | `{tile1, tile2}` |
| `clone` | `two` | 2 tiles (target empty) | `{sourceTile, targetTile}` |
| `teleport` | `two` | 2 tiles (target empty) | `{sourceTile, targetTile}` |
| `shuffle` | `none` | 0 — plays at once | `{}` |
| `transform` | `none` | 0 — plays at once | `{}` |
| _totem cards_ | `totem` | 0 — spawns a totem | via `spawn_totem` |

`time` / `magnet` cards have no engine action yet and are reported as unplayable.

---

## State shape (from `MbMatch._base_state`, `game/match_controller.gd`)

```
state = {
  board:  { tiles: [ tile, ... ],  size: int },     # tiles are row-major: idx = row*size + col
  hand:   { cards: [ card, ... ] },
  deck:   { remainingCards: int, nextCardIndex: int },
  score:  int,
  shards: int,                # 0–8; auto-draws a card at 8
  combo:  int,                # deprecated — do not use
  comboMultiplier: int,
  moveIndex: int,             # +1 per action (+2 when an auto-draw fires during a swipe)
  totems: { active: [ ... ] },
  randomSeeds: { "tile-gen":int, "shuffle":int, "effect-spawn":int, "totem-spawn":int, "card-draw":int },
  rngIndices:  { ... same 5 namespaces ... },
  # scenario-only: scenarioConfig, eventTriggerStates, globalEffects
}
```

**Tile** (`logic/engine.gd`): `{ isEmpty, value, row, col, status, meta, effect? }`
— `value` is a power of two; `effect` is present on tiles with an active effect
(`lock`, `freeze`, `black_hole`, …). Empty cells have `isEmpty: true`.

**Card**: `{ id, type, name?, isTotemCard?, spawnsTotem?:{id}, ... }` — `type` is the
power-card action string from the table above.

---

## Scenario ids (`load_scenario`)

| id | What |
| --- | --- |
| `0`–`7` | Built-in scenarios (starting cards / board / effect spawns) |
| `17` | "Fracture" — COMBO_BREAK ≥ 3 spawns the full-screen glitch global effect |
| `101` | Starts with a black-hole tile (consume-fly test) |

---

## Worked example (a scripted session)

```gdscript
# 1. Load a scenario and look at the board.
MbDebug.load_scenario(3)
return MbDebug.inspect()                 # {scenario, move_index:0, board_size, ...}

# 2. Read the board / hand.
return MbDebug.get_board()
return MbDebug.get_playable_cards()      # [{index, type, name, selection_mode}, ...]

# 3. Make a few moves (screenshot between to watch the animation).
MbDebug.swipe("up")
MbDebug.swipe("left")

# 4. Play a targeted card: bomb -> awaiting_selection:tile -> supply a tile.
return MbDebug.play_card(0)              # {"status":"awaiting_selection","selection_mode":"tile"}
return MbDebug.select_tile(2, 1)         # {"status":"complete"}

# 5. Inspect history.
return MbDebug.get_history_count()       # grows by 1 per committed move
return MbDebug.get_snapshot(2)           # state at moveIndex == 2
```

Drive screenshots with `mcp__godot-ai__editor_screenshot` (`source:"game"`) after each
mutating call to confirm the UI reacted.

---

## Known differences from `__moveborne`

- **Naming:** snake_case (`get_state`) vs camelCase (`getState`); `isReady` is a method
  (`is_ready()`), not a property.
- **Two-step `play_card`:** moveborne's `help()` advertises a one-call
  `playCard(cardIndex, row, col)`, but its actual implementation — and `MbDebug` — is
  the two-step `play_card(i)` → `select_tile/select_column`. `MbDebug` mirrors the real
  behavior, not the idealized help text.
- **History owner:** moveborne keeps `stateHistory` in the engine; `MbDebug` captures
  it in the facade (snapshot-on-`changed`). Same surface, different bookkeeping.
- **Extras:** `MbDebug` adds `new_game` / `load_scenario` / `cancel`, since scenarios
  and the intro are driven by the Godot scene rather than a separate harness.
