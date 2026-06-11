# MCP_UI_API.md — `MbUi`, the screen/button control layer

`MbUi` is the UI/navigation analog of [`MbDebug`](MCP_GAME_API.md). Where `MbDebug`
drives **gameplay** (swipe, play cards, read the board), `MbUi` drives the **shell**:
navigate to any screen by name, press any registered control by stable id, and run
**deterministic ordered sequences**. It lets an LLM (or any automation) drive the app's
menus the way a player taps them — through the real router + screens, so transitions,
fades, and screen builds happen exactly as they do for a human.

- **Driver:** `game/mcp_ui_api.gd` (autoload singleton `MbUi`).
- **Registry:** `ui/mcp_ui_reg.gd` (`MbUiReg`) — how controls become addressable.
- **Split:** `MbUi` = navigation + non-gameplay buttons; `MbDebug` = in-match board/cards.
  A `run()` sequence can do both (it delegates `swipe:` to `MbDebug`).

---

## How to invoke

Every call goes through the **godot-ai MCP** `editor_manage(op="game_eval")`, which runs a
GDScript snippet inside the running game and returns the JSON result. Navigation is
**async** — `game_eval` awaits the eval coroutine, so `await MbUi.goto(...)` returns only
once the destination screen is actually live (the router's transition + fades complete).

1. **Start the game:** `project_run` (main scene = `ui/boot.tscn` → the shell). `MbUi` is
   live whenever the shell is mounted (`MbUi.is_ready()`).
2. **Call it** (use `await` for anything that navigates):

   ```gdscript
   return MbUi.state()                       # where am I?
   return MbUi.actions()                     # every pressable id on this screen
   return await MbUi.goto("settings")        # awaited — returns when settings is live
   return MbUi.press("settings.avatar")      # open the avatar picker
   return await MbUi.run([                    # a deterministic sequence
       "goto:settings",
       {"set": "settings.music", "to": 0.3},
       "flow:start_story",
       "swipe:up",
   ])
   ```

3. **See the result** with `editor_screenshot` (`source:"game"`).

---

## Method reference

### Reads (non-mutating)
| Method | Returns |
| --- | --- |
| `is_ready()` | `bool` — true when the shell is mounted |
| `state()` | `{busy, route:[…], route_depth, tab, screen, modal, match_ready}` — the one situational read |
| `screens()` | static catalog of `goto` targets (`tabs`, `modes`, `surfaces`) |
| `actions(all=false)` | **the discovery surface**: every pressable thing on the live screen, by id (see below) |
| `help()` | command summary |

`actions()` walks the live registry and returns, per control:
`{id, kind, enabled, visible, + value/on/text}`, where `kind` ∈
`button | toggle | slider | text | texture_button`. Filtered to visible+in-tree unless
`all` is true. **Never guess an id — read it from `actions()`.**

### Navigation (awaited)
| Method | Returns |
| --- | --- |
| `goto(target)` | navigate to a screen by name; returns `state()` once it's live |

`target` is a tab (`collection`/`leaderboard`/`home`/`guilds`/`settings`), a mode
(`story`/`infinite`), or a surface (`shell`/`back` to exit a match). `goto` pops a match
first when needed, then selects the tab / launches the mode, awaiting throughout. Leaving a
match runs the same validator-completion + router-pop path the in-match exit button does.

### Control invocation (not awaited — see note)
| Method | Returns |
| --- | --- |
| `press(id, force=false)` | activate a button/texture-button/toggle |
| `toggle(id, on=true)` | set a CheckButton on/off |
| `set_value(id, v)` | set a slider (Range) value |
| `set_text(id, s, submit=false)` | set a LineEdit; `submit` fires `text_submitted` |

`press` resolves an id from the registry **regardless of visibility** (so you can target a
control that's about to be revealed), and emits the control's real signal. It does **not**
await router transitions — to start a match or leave one deterministically, use `goto`
(or a `run` step, which settles after each press).

### Sequences & flows (awaited)
| Method | Returns |
| --- | --- |
| `run(steps, opts={})` | run an ordered list of steps; returns a per-step trace |
| `flow(name, params={})` | expand + run a named flow; returns the `run` trace |

`run` stops on the first failed step unless `opts.continue_on_error`. Each trace entry is
`{ok, step, result/sub, screen_after}`.

**Step forms** (strings for the common case, dicts when a value is needed):

| String | Dict | Effect |
| --- | --- | --- |
| `"goto:settings"` / `"tab:home"` / `"start:story"` | `{goto:"settings"}` | navigate (awaited) |
| `"exit"` | — | `goto("shell")` — leave a match |
| `"press:home.story"` | `{press:"home.story", force?}` | press, then settle |
| `"toggle:settings.haptics"` | `{toggle:"settings.haptics", on:false}` | set a toggle |
| — | `{set:"settings.music", to:0.3}` | slider value |
| — | `{text:"settings.name", to:"Spectre", submit?}` | text field |
| `"swipe:up"` | `{swipe:"up"}` | gameplay (delegates to `MbDebug`) |
| `"wait:0.5"` | `{wait:0.5}` | sleep N seconds |
| `"flow:start_story"` | `{flow:"set_avatar", params:{id:"skull_avatar_03"}}` | run a named flow |

**Named flows:** `start_story`, `start_infinite`, `open_settings`, `open_leaderboard`,
`exit_match`, `sign_out`, `set_avatar{id}`, `rename{name}`, `set_volume{music?, sfx?}`.

---

## Screen & id catalog

Ids are `"<screen>.<control>"`. The live set always comes from `actions()`; this is the map
of what exists.

| Screen | Ids |
| --- | --- |
| `nav` (bottom bar) | `nav.collection` `nav.leaderboard` `nav.home` `nav.guilds` `nav.settings` |
| `home` | `home.story` `home.infinite` `home.pvp` (disabled) |
| `settings` | `settings.avatar` `settings.name` `settings.save_name` `settings.music` `settings.sfx` `settings.haptics` `settings.sign_out` |
| `avatar` (modal) | `avatar.skull_avatar_01` … `avatar.skull_avatar_12` |
| `leaderboard` | `leaderboard.daily` `leaderboard.weekly` `leaderboard.monthly` |
| `match` | `match.exit` |
| `collection` / `guilds` | (placeholder screens — no controls yet) |

`screen` (in `state()`) is `match` while a match is live, else the active tab id. `modal`
is `avatar` while the picker is open, else `""`.

---

## Making new controls addressable — `MbUiReg`

Registration is a **byproduct of construction**: screens build their actionable controls
through `MbUiReg` (or hand it an existing `.tscn` node via `adopt`). Each control is recorded
on the **live tree** — an `mcp_id` meta + group, with the screen root grouped under
`mcp_screen`. The driver walks that live tree, so the registry is self-cleaning (the freed
match scene drops out) and there is no central state to maintain.

```gdscript
const Reg := preload("res://ui/mcp_ui_reg.gd")

Reg.screen(self, "settings")                       # mark a screen root (group + id)
var save  := Reg.button("save_name", parent, "Save")    # -> Button, registered
var music := Reg.slider("music", parent)                # -> HSlider
var hap   := Reg.check("haptics", parent, "Haptics")    # -> CheckButton
var name  := Reg.line_edit("name", parent)              # -> LineEdit
var pick  := Reg.texture_button(id, parent, tex)        # -> TextureButton
Reg.adopt(_story, "story")                         # adopt a .tscn / pre-built node
```

A control belongs to its **nearest** `mcp_screen` ancestor, so a modal nested under another
screen (the avatar picker under Settings) forms its own screen. Factories cover the
actionable kinds only (Button / TextureButton / CheckButton / HSlider / LineEdit) and return
the bare control so the screen keeps doing its own styling.

---

## Worked example (a scripted session)

```gdscript
# 1. Where am I, and what can I press?
return MbUi.state()                 # {screen:"home", route:["shell"], …}
return MbUi.actions()               # home.* + nav.*

# 2. Open Settings, set the avatar + volume, rename.
return await MbUi.run([
    {"flow": "set_avatar", "params": {"id": "skull_avatar_05"}},
    {"set": "settings.music", "to": 0.4},
    {"text": "settings.name", "to": "Spectre"},
    "press:settings.save_name",
])

# 3. Start a match and play a few moves (UI → gameplay handoff).
return await MbUi.run(["goto:home", "flow:start_infinite", "swipe:up", "swipe:left"])
return MbDebug.inspect()            # MbDebug owns in-match board/cards

# 4. Leave the match (validator completion + router pop, awaited).
return await MbUi.goto("shell")
```

Drive `editor_screenshot` (`source:"game"`) between steps to confirm the UI reacted.

---

## Verification

- **Headless smoke:** `tools/verify_ui_driver.gd` exercises `MbUiReg` + the driver's
  catalog / actions / press / set on a hand-built tree (no autoloads/scenes):
  `Godot --headless --path . --script res://tools/verify_ui_driver.gd` → `VERIFY ui_driver: PASS`.
- **Live session:** `project_run`, then drive `MbUi` via `game_eval` as above.

---

## Notes / known edges

- **`press` doesn't await transitions.** It emits the control's signal and returns; a
  launcher's router push or the match exit runs async. Use `goto`/`run` for awaited
  navigation. (`run` settles after each press, which covers a launcher push.)
- **One-frame visibility race.** Right after a modal opens, `actions()` may briefly omit its
  controls until it settles; `press`/`resolve` are unaffected (they ignore visibility), so
  sequences are reliable.
- **Autoloads by path.** The driver resolves `UiRouter` / `MbDebug` via
  `get_node_or_null("/root/…")` (not the global identifier), so the script compiles and its
  pure surface runs even outside the full app (the headless verifier).
