# Design — App Shell & UI Router

**Status:** drafting

## Overview
This feature turns Moveborne from a game that boots straight into a match into an app with a persistent shell and a real navigation layer. The load-bearing pieces are a UiRouter autoload (a stack-based UI state machine whose transitions are awaited) and a UiState lifecycle contract, plus a Royal-Match-style bottom nav and a Home screen that launches matches. This page is the design; the sibling Build Plan lists the steps and the Test Plan the cases.

## Design
## Current state

project.godot sets the run/main-scene to res://scenes/main.tscn, a single full-rect Control whose main.gd (~780 lines) builds the entire board UI imperatively and, in ready(), immediately constructs an MbMatch, calls new-game(), and plays the intro. There is no shell, no router, no concept of a screen — main IS the game. logic/ is a parity-locked deterministic engine and must not change. The match has no engine-level end (MbMatch emits only the changed and tiles-destroyed signals), so returning to the shell must be a UI action.

## Architecture at a glance

A new app-shell scene becomes the run/main-scene. A UiRouter autoload owns a stack of UiState entries; the stack is the navigation depth. At rest the stack is just the ShellState, which hosts the bottom nav and a content host and switches tabs internally (a flat selector — tabs are NOT a stack). Launching a play mode pushes a MatchState that covers the shell. Android Back, the in-match Home button, and future modals all resolve to a router pop().

```text
stack (bottom -> top)         meaning
[ShellState]                  on the shell (Home / other tabs)
[ShellState, MatchState]      in a match (shell suspended, nav hidden)
[ShellState, MatchState, X]   a dialog / modal over a match (future)
                          ^ Back / pop() removes the top
```

## UiRouter — a stack-based UI FSM

UiRouter is a Node autoload. Every transition (push/pop/replace/reset) is serialized behind a busy flag so a double-tap cannot start two transitions, and the router awaits the relevant state's enter()/exit() so an async transition finishes before control returns. States parent their root Control into a router-owned CanvasLayer (the content-root); the topmost opaque state covers those beneath. A separate high-layer fade overlay (above the match's layer-100 overlays) provides hard cuts.

```gdscript
extends Node
## UiRouter (autoload): a stack-based UI state machine. The stack IS the nav history;
## Back = pop. Transitions are serialized behind _busy, and enter()/exit() are awaited
## so a state can run an async transition before the router proceeds.
signal changed(top: UiState)

var _stack: Array[UiState] = []
var _busy := false
var content_root: CanvasLayer          # states parent their screens here

func _ready() -> void:
    content_root = CanvasLayer.new()
    content_root.layer = 1
    add_child(content_root)

func top() -> UiState:
    return _stack.back() if not _stack.is_empty() else null

func push(state: UiState, params := {}) -> void:
    if _busy: return                   # ignore taps mid-transition
    _busy = true
    var below := top()
    if below: below.suspend()
    _stack.push_back(state)
    await state.enter(params)          # <-- awaited transition
    changed.emit(state)
    _busy = false

func pop() -> void:
    if _busy or _stack.size() <= 1: return
    _busy = true
    var leaving: UiState = _stack.pop_back()
    await leaving.exit()               # <-- awaited transition
    top().resume()
    changed.emit(top())
    _busy = false

func reset(state: UiState, params := {}) -> void:
    if _busy: return
    _busy = true
    while not _stack.is_empty():
        await _stack.pop_back().exit()
    _stack.push_back(state)
    await state.enter(params)
    changed.emit(state)
    _busy = false

# Hard-cut fade for big swaps (match load/unload). On its own CanvasLayer ABOVE the
# match's countdown/glitch overlays (layer=100).
var _fade: ColorRect
func _ensure_fade() -> void:
    if _fade: return
    var cl := CanvasLayer.new(); cl.layer = 200
    var r := ColorRect.new()
    r.color = Color.BLACK; r.modulate.a = 0.0
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    r.set_anchors_preset(Control.PRESET_FULL_RECT)
    cl.add_child(r); add_child(cl); _fade = r
func cover(d := 0.18) -> void:
    _ensure_fade()
    var t := create_tween(); t.tween_property(_fade, "modulate:a", 1.0, d)
    await t.finished
func reveal(d := 0.18) -> void:
    _ensure_fade()
    var t := create_tween(); t.tween_property(_fade, "modulate:a", 0.0, d)
    await t.finished
```

## UiState — the per-screen lifecycle

UiState is a thin RefCounted controller (the FSM entry), distinct from the Control scene it shows. Lifecycle: enter(params) when it becomes top, exit() when it leaves, suspend() when another state covers it, resume() when it is uncovered. enter and exit are await-able; the base implementations yield one process frame so even a state that does no animation is a valid coroutine (no redundant-await warning) and any nodes it added are in-tree before it animates. The blocks-below flag (default true) tells the router the state beneath should suspend.

```gdscript
class_name UiState
extends RefCounted
## One route/screen in the UiRouter stack. Hooks are await-able: the router awaits
## enter()/exit(), so a hook may run an async transition. Override what you need.

## True if this state fully covers the one below (takeover/modal): the router
## suspends the state beneath it. False for transparent overlays.
var blocks_below := true

## Becomes top (push/replace). Base yields one frame so every enter() is a valid
## coroutine and added nodes are in-tree before animating. Override to build + fade in.
func enter(_params: Dictionary) -> void:
    await Engine.get_main_loop().process_frame

## Leaves the stack (pop/replace). Override to fade out + free owned nodes.
func exit() -> void:
    await Engine.get_main_loop().process_frame

## Another state was pushed over this one (it stays in the stack).
func suspend() -> void: pass

## This state is uncovered again after the one above it popped.
func resume() -> void: pass
```

## Async enter/exit: transitions are awaited

Because GDScript await suspends on a coroutine and returns immediately on a plain value, the router's await of state.enter(params) works uniformly whether or not the state animates. A state runs its own in/out transition inside enter()/exit(); the router additionally exposes cover()/reveal() for hard cuts (e.g. loading the match). MatchState shows the pattern — it is also where the existing match scene is mounted and freed:

```gdscript
class_name MatchState
extends UiState
## Pushes the existing match scene (scenes/main.tscn) as a full-screen takeover.
const MATCH_SCENE := "res://scenes/main.tscn"
var _root: Node            # UiRouter.content_root
var _scene: Node

func _init(content_root: Node) -> void:
    _root = content_root

func enter(params: Dictionary) -> void:
    GameState.next_match = params
    await UiRouter.cover()                       # fade to black (awaited)
    _scene = load(MATCH_SCENE).instantiate()     # main._ready reads next_match + starts the match
    _root.add_child(_scene)
    _scene.match_exited.connect(_on_match_exited)
    await Engine.get_main_loop().process_frame   # let the board build
    await UiRouter.reveal()

func exit() -> void:
    await UiRouter.cover()
    if is_instance_valid(_scene):
        _scene.queue_free()                      # frees MbMatch ref + validator Node + CanvasLayers
    await UiRouter.reveal()

func _on_match_exited(result: Dictionary) -> void:
    GameState.last_result = result
    UiRouter.pop()                               # back to the shell
```

## Tabs vs. takeover

Two distinct motions, deliberately separated. (1) Tab selection is a flat radio choice inside ShellState: the five nav Buttons share a ButtonGroup; pressing one toggles which tab screen is visible in the content host. No router transition, no current-scene change — the shell is the current scene all session, so nav and autoloads never reload, and tab swaps need no animation. (2) A match is a one-deep modal: Home calls router push(MatchState, cfg); the router suspends ShellState (whose suspend() hides the nav and the shell), covers, loads the match, reveals. The in-match Home/Quit button or Android Back pops it, and the ShellState resume() restores the nav.

## The match handoff

Home writes the per-match config to GameState.next-match (a plain Dictionary with mode, scenario-id, seed, online, and validator-url) and pushes MatchState. The match's ready() reads it and branches — and critically does NOT double-start the match on the PvP path, because connect-validator() already calls new-game():

```gdscript
func _ready() -> void:
    var cfg: Dictionary = GameState.next_match if not GameState.next_match.is_empty() else {"mode": "infinite"}
    _match = MbMatchS.new()
    _build_ui(cfg.get("online", false))             # gate the MbValidatorClient on online
    _match.changed.connect(_on_changed)
    _match.tiles_destroyed.connect(_on_tiles_destroyed)
    add_to_group("mb_match")                         # so MbDebug._scene() still resolves the live match
    match cfg.get("mode", "infinite"):
        "story":
            _match.new_game_scenario(int(cfg.get("scenario_id", 0)))
        "pvp":
            _connect_validator()                     # already calls _match.new_game() internally
        _:
            _match.new_game()                        # infinite / Endless
    _play_intro()
```

Match-end is a UI action (there is no engine game-over). A new in-match Home/Quit button emits the match-exited signal with the result; MatchState catches it, banks GameState.last-result, and pops. Same-mode Play Again uses the existing in-place R / 0-7 restart instead of a teardown plus re-instance.

```gdscript
signal match_exited(result: Dictionary)

func _on_home_button_pressed() -> void:
    match_exited.emit({
        "scenario": scenario_name,
        "score": int(_match.state.get("score", 0)),
        "move_index": int(_match.state.get("moveIndex", 0)),
        "reason": "quit",
    })
```

## Menu layer: .tscn + Theme

The shell, nav, Home, and placeholder tabs are authored as composed .tscn scenes referencing a shared Theme resource (res://ui/theme/moveborne-ui.theme) — a deliberate modernization away from the all-code match UI. The Theme carries the Grammara font, button StyleBoxFlat states, panel styles, and a theme-type-variation for the emphasized Home tab. The match scene (main.gd) stays code-built and is only surgically edited. New menu code lives under res://ui/ to keep it separate from res://scenes/ (the match/board code); res:// resolves from the game/ project root.

## Mobile & GL Compatibility

Portrait 720x1560, canvas-items stretch at scale 2.0. Add the display/window/stretch/aspect setting = expand (currently absent → the base distorts on other aspect ratios) and re-audit main.gd's fixed Y offsets (top-bar=120, hand-h=150). Anchor the nav to the bottom-wide preset and inset it for safe areas via a MarginContainer fed from DisplayServer get-display-safe-area() converted from physical pixels into stretch space, plus a fixed 16-24px bottom pad for the iOS home indicator (re-run on the size-changed signal). The cover overlay sits on a CanvasLayer above the match's countdown and glitch overlays (both at layer 100). Use Button (not TouchScreenButton) — it receives emulated mouse from touch; keep finger-sized hit areas. Verify CanvasLayer and StyleBoxFlat under the GL Compatibility renderer on device; gate any glow on the Quality autoload.

## What Godot gives vs. what we build

Native: manual scene instancing (add-child / queue-free — the persistent-shell pattern), ButtonGroup radio selection, the Theme and StyleBox system, autoload singletons, GDScript await for async transitions, the Android Back notification plus set-quit-on-go-back, and DisplayServer safe-area queries. Built by us: the router/stack FSM, screen transitions, the emphasized-center bottom nav (TabContainer's engine-rendered tabs cannot express a raised center tab), and the match handoff. The full-scene swap change-scene-to-file is deliberately avoided — it frees the whole current scene and would destroy the persistent nav.

## Out of scope / future

Real two-player PvP (Snapser matchmaking plus session token); resume-into-match after an app kill (nothing about an in-flight match is persisted — a killed app returns to Home); fleshing out the four placeholder tabs (Settings onto the Quality autoload is the likely first); button and transition SFX; threaded/background match loading (add a loading overlay only if a real hitch is measured on device).

## Decisions
_No decisions recorded yet._

## References
_None._

## Child pages
_None._
