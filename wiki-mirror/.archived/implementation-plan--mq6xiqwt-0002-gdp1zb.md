# Implementation plan

**Status:** ready

## Steps
- [x] Phase 0 — In scenes/main.gd._ready(), read GameState.next_match (default {mode:'infinite'}) and branch: Story -> _match.new_game_scenario(scenario_id); Infinite/default -> _match.new_game(); PvP -> _connect_validator() ONLY (no extra new_game, since _connect_validator already calls it).
- [x] Phase 0 — Add `signal match_exited(result)` to main.gd plus an in-match Home/Quit button that emits it; keep the existing R / 0-7 keys for in-place restart (no teardown).
- [x] Phase 0 — In main.gd._ready() call add_to_group('mb_match'); update MbDebug._scene() (game/mcp_game_api.gd L66-78) to fall back to get_tree().get_first_node_in_group('mb_match') filtered by has_method('mcp_match').
- [x] Phase 0 — VERIFY: scenes/main.tscn still runs standalone (Endless default), and MCP game_eval + state-history still resolve the live match. No logic/ change (parity untouched).
- [x] Phase 1 — Add res://ui/game_state.gd autoload (next_match: Dictionary, last_result: Dictionary); register GameState in project.godot [autoload] alongside Vfx/Anim/Quality/MbDebug.
- [x] Phase 1 — Add display/window/stretch/aspect=expand to project.godot; re-audit main.gd's fixed Y offsets (top_bar=120, hand_h=150) on a couple of phone aspect ratios under expand.
- [x] Phase 2 — Add res://ui/router/ui_state.gd (base lifecycle enter/exit/suspend/resume + blocks_below) and res://ui/router/app_router.gd (autoload: _stack, _busy, push/pop/replace/reset, content_root CanvasLayer at layer 1, cover/reveal fade on a layer-200 CanvasLayer). Register UiRouter autoload.
- [x] Phase 2 — VERIFY: drive two dummy UiStates (push then pop) and confirm enter()/exit() are awaited (transition completes before control returns) and the _busy lock rejects a re-entrant push.
- [x] Phase 3 — Create res://ui/theme/moveborne_ui.theme: Grammara font, button StyleBoxFlat states (normal/hover/pressed/disabled), panel styles, and a 'HomeTab' theme_type_variation for the emphasized center tab.
- [x] Phase 3 — Build app_shell.tscn (root Control + ContentHost + BottomNav) and ShellState. bottom_nav.tscn = HBoxContainer of 5 toggle Buttons sharing one ButtonGroup; center Home emphasized (larger custom_minimum_size + HomeTab variation + negative top offset to overhang).
- [x] Phase 3 — Build home.tscn (central hero view + Story/Infinite/PvP launchers; PvP rendered disabled/badged 'coming soon') and four placeholder tab scenes (collection/leaderboard/guilds/settings), each a single centered Label.
- [x] Phase 3 — Repoint project.godot run/main_scene to res://ui/shell/app_shell.tscn; on boot UiRouter.reset(ShellState.new()). App boots to Home; the shell's flat selector toggles tab screens in ContentHost (no router transition for tabs).
- [x] Phase 4 — Add MatchState. Home play buttons write GameState.next_match and call UiRouter.push(MatchState.new(UiRouter.content_root), cfg). enter() covers -> instances scenes/main.tscn -> reveals; ShellState.suspend() hides the nav. Connect match_exited -> UiRouter.pop() -> queue_free -> ShellState.resume().
- [x] Phase 4 — Android Back on the shell root: get_tree().set_quit_on_go_back(false) + _notification(NOTIFICATION_WM_GO_BACK_REQUEST) -> UiRouter.pop() when in a match, else quit on Home. Do not steal ESC (main.gd uses it for cancel-card).
- [x] Phase 4 — Safe-area insets: wrap nav/content in a MarginContainer fed from DisplayServer.get_display_safe_area() converted to stretch space + a fixed ~16-24px iOS bottom pad; re-run on the size_changed signal.
- [x] Phase 4 — VERIFY on device under GL Compatibility: nav StyleBoxFlat, ContentHost, and the cover overlay (layer 200) render correctly and the fade sits above the in-match countdown/glitch (layer 100). Optional: gate MbValidatorClient creation in _build_ui on cfg.online; add button/transition SFX.
- [x] Deferred (measure-first) — threaded/background match loading via ResourceLoader.load_threaded_request + a progress overlay ONLY if synchronous load('res://scenes/main.tscn').instantiate() actually hitches on device. Likely skipped.

## Data models & interfaces
```gdscript
extends Node
## GameState (autoload). Tiny cross-screen state that survives the (non-)scene-swap.
## Deliberately minimal: NO currencies/profile/unlocks/Events-bus until a real feature needs them.

## Per-match launch config, read by scenes/main.gd._ready(). Plain Dictionary
## (consistent with the untyped SynchronizedGameState mirror). Shape:
##   { "mode": "story"|"infinite"|"pvp", "scenario_id": int, "seed": int,
##     "online": bool, "validator_url": String }
var next_match: Dictionary = {}

## Result banked by MatchState on match_exited (score, scenario, reason, ...).
var last_result: Dictionary = {}
```

```gdscript
class_name ShellState
extends UiState
## The persistent root state: owns app_shell.tscn (bottom nav + content host),
## instanced once into UiRouter.content_root. Tabs switch INSIDE the shell
## (a flat selector), so tab changes are NOT router pushes.
var _shell: Control

func _init() -> void:
    blocks_below = false                       # nothing sits below the shell

func enter(_params: Dictionary) -> void:
    if not is_instance_valid(_shell):
        _shell = load("res://ui/shell/app_shell.tscn").instantiate()
        UiRouter.content_root.add_child(_shell)
    _shell.show(); _shell.set_nav_visible(true)
    await Engine.get_main_loop().process_frame

func suspend() -> void:                        # a match is covering us
    _shell.hide(); _shell.set_nav_visible(false)

func resume() -> void:                         # match popped; we are top again
    _shell.show(); _shell.set_nav_visible(true)
```

## Open questions
_None._

## Resolved questions
1. **Folder layout: put the new menu layer under res://ui/ (router/, shell/, screens/, theme/) and keep res://scenes/ for the match/board code — confirm, or prefer everything under res://scenes/ per the current convention?** — _Confirmed and shipped: the menu layer lives under res://ui/ (router/, shell/, screens/, theme/); res://scenes/ keeps the match/board code._
2. **Should the match scene later move to res://scenes/match/ for symmetry, or stay at res://scenes/main.tscn to minimize churn and keep test/tool paths stable?** — _Left at res://scenes/main.tscn to minimize churn and keep test/tool paths stable. A move to res://scenes/match/ is optional future tidy-up, not done._

## References
_None._

## Child pages
_None._
