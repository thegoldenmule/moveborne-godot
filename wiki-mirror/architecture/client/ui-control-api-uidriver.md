# UI Control API (UiDriver)

**Status:** current

## Kind
module

## Summary
`UiDriver` is the UI/navigation analog of **MbDebug** — the menu-driving counterpart to MbDebug's gameplay-driving (MbDebug owns in-match board/cards; UiDriver owns everything around the match). An autoload singleton (`UiDriver`) driven via the godot-ai MCP `game_eval`, it gives explicit, named access to every screen and button plus **deterministic ordered sequences**: navigate to any screen by name, press any registered control by stable id, and run scripted step lists — all through the real router + screens, so transitions, fades, and screen builds happen exactly as they do for a player.

UiDriver is **game-agnostic**: it ships in the generic **`ui_kit`** addon (`addons/ui_kit/`, sourced from `github.com/thegoldenmule/godot-addons`) alongside `UiRouter`, `UiState`, `UiScreenScaffold`, and `UiReg`. The driver knows no Moveborne screens/modes/flows; everything game-specific is supplied by the **AppShell** acting as the **`ui_nav_host`** (a node in that group implementing an `mcp_*` contract). See [[architecture:mqayf7o4-001y-dyr6k0]]'s Data model for the registration model and the host contract.

## Purpose
Gameplay was already drivable semantically (MbDebug), but the **menu/shell layer had no semantic driver** — reaching a screen or pressing a button meant reading pixel rects and clicking coordinates: slow, layout-dependent, and **not deterministic** (async tweens, generic/auto node names, duplicate names like the avatar picks). UiDriver closes that gap. Two facts make it clean: the navigation layer (`UiRouter`) is an **async stack-FSM** whose push/pop await their lifecycle hooks + the cover/reveal fades, and `game_eval` itself awaits the eval coroutine — so `await UiDriver.goto(...)` / `run([...])` return only once the destination is actually live. Control ids come from **UiReg** (registration as a byproduct of construction), so the catalog is self-maintaining.

A second goal: **reusability**. The driver, router, state base, scaffold, and registration factory carry no game knowledge, so they were lifted into the standalone, self-updating `ui_kit` addon for reuse across projects. The game keeps only the *content* — its tabs, play modes, named flows, the story-map readiness wait, and the `swipe` step — on the AppShell `ui_nav_host`.

## Design notes
```gdscript
# A scripted session (run via game_eval).
return UiDriver.state()                 # {screen:"home", route:["shell"], ...}
return UiDriver.actions()               # home.* + nav.*

# Open Settings, set the avatar + volume, rename:
return await UiDriver.run([
    {"flow": "set_avatar", "params": {"id": "skull_avatar_05"}},
    {"set": "settings.music", "to": 0.4},
    {"text": "settings.name", "to": "Spectre"},
    "press:settings.save_name",
])

# Start a match and play (UI -> gameplay handoff; swipe is a host custom verb -> MbDebug):
return await UiDriver.run(["goto:home", "flow:start_infinite", "swipe:up", "swipe:left"])
return MbDebug.inspect()            # MbDebug owns in-match board/cards

return await UiDriver.goto("shell")     # leave (validator completion + router pop, awaited)
```

```gdscript
# Make a new control addressable — registration via UiReg, a byproduct of building it.
const Reg := preload("res://addons/ui_kit/ui_reg.gd")
Reg.screen(self, "settings")                       # mark a screen root (group + id)
var save  := Reg.button("save_name", parent, "Save")    # -> Button, registered
var music := Reg.slider("music", parent)                # -> HSlider
var hap   := Reg.check("haptics", parent, "Haptics")    # -> CheckButton
Reg.adopt(_story, "story")                         # adopt a .tscn / pre-built node
# It then appears in UiDriver.actions() and is pressable by id — no hand-written set_meta.
```

Known edges. (1) press() does not await router transitions — it emits the control's signal and returns; a launcher's push or the match exit runs async, so use goto()/run() for awaited navigation (run settles after each press, which covers a launcher push). (2) One-frame visibility race: right after a modal opens, actions() may briefly omit its controls until it settles; press()/resolve() are unaffected (they ignore visibility), so sequences are reliable. (3) The driver resolves the host and the router via groups (ui_nav_host / ui_router), not a global identifier, so it works regardless of the autoload names the consuming project chose, and its pure surface (catalog/actions/press) runs even outside the full app — e.g. the headless verifier tools/verify_ui_driver.gd, which stands up a fake ui_nav_host.

## Components
_No components._

## Dependencies
- **depends-on** → [Game Control API (MbDebug)](architecture:mqay9c1u-0013-wu1lcn) — Hands the custom `swipe` run() step to the host (AppShell) via mcp_step, which routes it to MbDebug — so one run() sequence can navigate and play. The driver has no direct dependency on MbDebug anymore.

## Code references
- file `UiDriver (autoload, ui_kit addon)` in `game/addons/ui_kit/ui_driver.gd`
- class `UiReg` in `game/addons/ui_kit/ui_reg.gd`
- file `headless smoke` in `game/tools/verify_ui_driver.gd`

## Data model
`actions()` is the discovery surface: each entry is `{id, kind, enabled, visible, + value/on/text}`, with `kind ∈ button | toggle | slider | text | texture_button`, filtered to visible+in-tree unless `all`. `state()` returns `{busy, route:[…], route_depth, tab, screen, modal, modals, match_ready}` — `route` maps each router state name through the host's `mcp_route_label`; `screen` is the active overlay label (e.g. `match`/`story_map`) while one is live, else the active tab id; `modal`/`modals` are **data-driven** — any visible registered screen that is neither the current tab nor a router-state screen (e.g. `avatar`, `daily`, `login_bonus`).

**Registration (UiReg, `addons/ui_kit/ui_reg.gd`):** registration is a byproduct of construction — screens build their actionable controls through `UiReg` (or hand it an existing `.tscn` node via `adopt`), and each control is recorded on the **live tree** (a `ui_id` meta + the `ui_control` group, with the screen root grouped under `ui_screen`). A control belongs to its **nearest** `ui_screen` ancestor, so a modal nested under another screen (the avatar picker under Settings) forms its own screen. The driver walks that live tree, so the registry is self-cleaning (the freed match scene drops out) with no central state. Factories cover the actionable kinds only (Button / TextureButton / CheckButton / HSlider / LineEdit) and return the bare control so the screen keeps its own styling.

**The `ui_nav_host` contract.** The driver is generic; the game's shell joins the `ui_nav_host` group and supplies the content via `mcp_*` methods. Required: `mcp_select_tab(id)`, `mcp_current_tab_id()`, `mcp_start_match(cfg)`. Optional (each with a generic fallback): `mcp_nav_tabs()`, `mcp_nav_modes()`, `mcp_mode_cfg(id)`, `mcp_target_active(id)`, `mcp_exit_to_shell()`, `mcp_route_label(name)`, `mcp_wait_ready(target)`, `mcp_match_ready()`, `mcp_flows()`, `mcp_expand_flow(name, params)`, and `mcp_step(verb, arg)` for custom run() verbs (Moveborne: `swipe` → MbDebug). In Moveborne this contract is implemented by `AppShell`.

## Usage
Every call goes through the godot-ai MCP `game_eval`. Navigation is **async** — `game_eval` awaits the eval coroutine, so `await UiDriver.goto(...)` returns only once the destination screen is live (the router transition + ~0.18s fades complete).

1. **Start the game** (`project_run`; main scene `ui/boot.tscn` → the shell). `UiDriver` is live whenever the shell (the `ui_nav_host`) is mounted (`UiDriver.is_ready()`).
2. **Call it** (use `await` for anything that navigates) — e.g. `return UiDriver.state()`, `return UiDriver.actions()`, `return await UiDriver.goto("settings")`, `UiDriver.press("settings.avatar")`, `return await UiDriver.run([...])`. A worked sequence is in **Design notes**.
3. **See the result** with `editor_screenshot` (`source:"game"`).

### Reads (non-mutating)
| Method | Returns |
| --- | --- |
| `is_ready()` | bool — true when the shell (`ui_nav_host`) is mounted |
| `state()` | `{busy, route:[…], route_depth, tab, screen, modal, modals, match_ready}` — the one situational read |
| `screens()` | static catalog of `goto` targets (`tabs`, `modes`, `surfaces`), sourced from the host |
| `actions(all=false)` | **the discovery surface** for `press`: every pressable thing on the live screen, by id |
| `flows()` | **the named-flow catalog** for `flow`: `{name, params, summary, steps}` per flow (host-supplied) |
| `help()` | command summary |

`actions()` returns, per control, `{id, kind, enabled, visible, + value/on/text}` with `kind ∈ button \| toggle \| slider \| text \| texture_button`, filtered to visible+in-tree unless `all`. **Never guess an id — read it from `actions()`.** Likewise, **never guess a flow — read it from `flows()`** (each entry carries its `params` and a `steps` preview).

### Navigation (awaited)
| Method | Returns |
| --- | --- |
| `goto(target)` | navigate to a screen by name; returns `state()` once it's live |

`target` is a tab (`collection`/`leaderboard`/`home`/`guilds`/`settings`), a mode (`story`/`infinite`), or a surface (`shell`/`back` to exit a match). The host decides what's a tab vs a mode (`mcp_nav_tabs`/`mcp_nav_modes`) and whether the target is already live (`mcp_target_active`); `goto` exits any active overlay first (`mcp_exit_to_shell`), then selects the tab / launches the mode, awaiting throughout, and finally runs the host's optional post-nav readiness wait (`mcp_wait_ready`, e.g. the story map's catalog fetch). Leaving a match runs the same validator-completion + router-pop path the in-match exit button does.

### Control invocation (not awaited — see Design notes)
| Method | Returns |
| --- | --- |
| `press(id, force=false)` | activate a button / texture-button / toggle |
| `toggle(id, on=true)` | set a CheckButton on/off |
| `set_value(id, v)` | set a slider (Range) value |
| `set_text(id, s, submit=false)` | set a LineEdit; `submit` fires `text_submitted` |

`press` resolves an id from the registry **regardless of visibility** and emits the control's real signal. It does **not** await router transitions — use `goto` (or a `run` step) to start/leave a match deterministically.

### Sequences & flows (awaited)
| Method | Returns |
| --- | --- |
| `run(steps, opts={})` | run an ordered list of steps; returns a per-step trace |
| `flow(name, params={})` | expand + run a named flow (see `flows()`); returns the `run` trace |

`run` stops on the first failed step unless `opts.continue_on_error`. Each trace entry is `{ok, step, result/sub, screen_after}`.

**Step forms** (strings for the common case, dicts when a value is needed):

| String | Dict | Effect |
| --- | --- | --- |
| `"goto:settings"` / `"tab:home"` / `"start:story"` | `{goto:"settings"}` | navigate (awaited) |
| `"exit"` | — | `goto("shell")` — leave a match |
| `"press:home.story"` | `{press:"home.story", force?}` | press, then settle |
| `"toggle:settings.haptics"` | `{toggle:"settings.haptics", on:false}` | set a toggle |
| — | `{set:"settings.music", to:0.3}` | slider value |
| — | `{text:"settings.name", to:"Spectre", submit?}` | text field |
| `"swipe:up"` | `{swipe:"up"}` | a **custom verb** — the driver hands any unrecognized verb to the host's `mcp_step(verb, arg)`; Moveborne routes `swipe` to MbDebug (gameplay) |
| `"wait:0.5"` | `{wait:0.5}` | sleep N seconds |
| `"flow:start_story"` | `{flow:"set_avatar", params:{id:"skull_avatar_03"}}` | run a named flow |

**Named flows** (call `flows()` for the live catalog; supplied by the host's `mcp_flows`/`mcp_expand_flow`): `start_story`, `story_play_next`, `start_infinite`, `open_settings`, `open_leaderboard`, `open_daily_missions`, `claim_daily`, `exit_match`, `sign_out`, `set_avatar{id}`, `rename{name}`, `set_volume{music?, sfx?}`.

### Screen & id catalog
Ids are `"<screen>.<control>"`. The live set always comes from `actions()`; this is the map of what exists.

| Screen | Ids |
| --- | --- |
| `nav` (bottom bar) | `nav.collection` `nav.leaderboard` `nav.home` `nav.guilds` `nav.settings` |
| `home` | `home.story` `home.infinite` `home.pvp` (disabled) `home.daily` |
| `settings` | `settings.avatar` `settings.name` `settings.save_name` `settings.music` `settings.sfx` `settings.haptics` `settings.sign_out` |
| `avatar` (modal) | `avatar.skull_avatar_01` … `avatar.skull_avatar_12` |
| `leaderboard` | `leaderboard.daily` `leaderboard.weekly` `leaderboard.monthly` |
| `match` | `match.exit` |
| `collection` / `guilds` | placeholder screens — no controls yet |

## Invariants & constraints
- Control ids are recorded on the live tree by UiReg (a ui_id meta + ui_control group; screen root grouped ui_screen) — self-cleaning, so the freed match scene drops out and there is no central registry to prune. New actionable controls register as a byproduct of construction, never a hand-written set_meta.
- Navigation is deterministic: UiRouter push/pop await their lifecycle hooks + cover/reveal fades and game_eval awaits the eval coroutine, so await goto()/run() return only once the destination screen is live — no screenshots-to-confirm, no sleep-and-hope.
- The UiDriver/UiRouter/UiReg/UiScreenScaffold code is game-agnostic and lives in the generic `ui_kit` addon (sourced from github.com/thegoldenmule/godot-addons, self-updating in place). All Moveborne-specific navigation — tabs, play modes, named flows, the story-map readiness wait, the swipe step — lives on the AppShell `ui_nav_host`, never in the driver.

## Synced commit
717bea1
