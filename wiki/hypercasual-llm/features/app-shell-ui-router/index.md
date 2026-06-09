# Feature: App Shell & UI Router

**Status:** building

## Summary
Replace the boot-straight-into-a-match flow with a persistent app shell and a stack-based UI router. Godot's run/main_scene is repointed from scenes/main.tscn to a new app_shell scene that hosts a Royal-Match-style persistent bottom navigation (Collection · Leaderboard · Home · Guilds · Settings, with the center Home tab emphasized) plus a content region. Home is the only real tab in v1 and presents a central hero view plus three play-mode launchers — Story, Infinite, and PvP. Navigation is driven by a UiRouter autoload that manages a stack of UiState entries, each with an await-able enter/exit lifecycle so screen transitions are first-class: tab selection is a flat selector inside the shell state, while launching a play mode pushes a MatchState that covers the shell. The existing match scene (scenes/main.tscn) is demoted from 'the app' to 'the match screen' via surgical edits — it reads a per-match config Dictionary, emits match_exited, and joins the mb_match group so MCP/LLM automation keeps resolving the live match. The menu layer is authored as composed .tscn scenes + a shared Theme resource (a deliberate modernization away from the all-code match UI), while the parity-locked logic/ engine is never touched. PvP ships gated 'coming soon' because the validator path today is single-player dev validation, not a real two-player match.

## Components affected
- UiRouter (autoload) — stack-based UI state machine. push/pop/replace/reset over a stack of UiState; serializes transitions behind a _busy lock; owns a cover/reveal fade overlay; awaits each state's enter()/exit() so transitions complete before the router proceeds. Back = pop.
- UiState (base class, RefCounted) — one route/screen in the stack. Await-able lifecycle: enter(params)/exit()/suspend()/resume(). Base enter/exit yield one process frame so non-animating states stay valid coroutines (no REDUNDANT_AWAIT). blocks_below marks opaque/modal states so the one beneath suspends.
- ShellState + AppShell (scene) — the persistent root state at the bottom of the stack. app_shell.tscn owns the BottomNav + a ContentHost; tab switching is a flat selector handled inside ShellState (not a router push). suspend() hides the nav + shell during a match; resume() restores them.
- BottomNav (scene) — persistent 5-tab Royal-Match bar. HBoxContainer of 5 toggle Buttons sharing one ButtonGroup (radio selection); center Home emphasized via larger custom_minimum_size + distinct StyleBox + negative top offset to overhang.
- HomeScreen (scene) — the one real tab. Central hero/scene view above three play-mode launchers (Story / Infinite / PvP). On tap, writes GameState.next_match and asks the router to push MatchState; never instances the match itself. PvP button rendered disabled/'coming soon'.
- Placeholder tabs ×4 (scenes) — Collection / Leaderboard / Guilds / Settings, each a one-Control stub (single centered Label) for v1. Settings later drives the existing Quality autoload but stays a placeholder now.
- MatchState (router state) — pushes the existing match scene as a full-screen takeover. async enter(): cover → instance scenes/main.tscn → (main._ready starts the match per mode) → reveal. Connects match_exited → router.pop(). async exit(): cover → queue_free the match → reveal.
- MatchScreen edits (scenes/main.gd) — demote to 'the match screen': read GameState.next_match in _ready and branch Story/Infinite/PvP; add signal match_exited(result) + an in-match Home/Quit button; add_to_group('mb_match'); keep R / 0-7 in-place restart; no double new_game on the PvP path.
- GameState (autoload) — tiny cross-screen state that survives the (non-)scene-swap: next_match (plain Dictionary) + last_result. No currencies/profile/unlocks/Events-bus until a real feature needs them.
- Menu Theme (resource) — a shared Theme.tres for the .tscn menu layer: default font (Grammara), button StyleBoxFlat states, panel styles, and a theme_type_variation for the emphasized Home tab. Applied to the menu scenes; the match scene stays code-built.
- Cover/transition overlay — router-owned black ColorRect on a CanvasLayer for hard cuts (match load/unload). Layer chosen to clear the match's countdown + glitch overlays (both at layer=100); _fx_layer is at layer=5. Self-freeing, is_inside_tree()-guarded.
- MbDebug._scene() reroute (game/mcp_game_api.gd) — once the shell owns current_scene, fall back to get_first_node_in_group('mb_match') filtered by has_method('mcp_match') so game_eval / MCP automation + state-history binding keep working.

## Design constraints
1. Never touch logic/ — it is parity-locked (byte-for-byte with the canonical TS engine). The play-mode system is purely additive at the scene/controller layer. [ADR: Hard wall between deterministic logic and presentation]
2. PvP ships gated 'coming soon'. The online/validator path is single-player move VALIDATION (one player_id, client signature 'dev', DEV_MODE only), not a two-player match; real PvP needs the unintegrated Snapser matchmaking + session token. [ADR: Defer Nakama; ship local-authoritative single-player first]
3. The menu layer is authored as .tscn scenes + a shared Theme resource (a chosen modernization). The match scene (main.gd) stays imperatively code-built and is only surgically edited — do not rewrite its UI.
4. UiState.enter()/exit() must be await-able coroutines so the router awaits transitions. The base enter/exit yield one process frame so non-animating states stay valid coroutines (avoids the REDUNDANT_AWAIT warning) and added nodes are in-tree before animating.
5. The router serializes transitions behind a _busy lock: rapid touches cannot push two states or swap tabs mid-transition (mobile double-tap safety).
6. Per-match config is a plain Dictionary on GameState.next_match (consistent with the untyped SynchronizedGameState mirror ADR), read at the top of main.gd._ready() with an Endless default so scenes/main.tscn still runs standalone. No typed MatchConfig Resource.
7. Match-end is a UI action, not an engine event: logic/ has no win/lose and MbMatch emits only changed/tiles_destroyed. An in-match Home/Quit button emits match_exited(result) → router.pop().
8. PvP must not double-start the match: _connect_validator() already calls _match.new_game(). _ready starts the board only for Story/Infinite and delegates entirely to _connect_validator for PvP.
9. Keep MCP/LLM automation working: main.gd add_to_group('mb_match') in _ready; MbDebug._scene() falls back to the group lookup once the shell (not the match) owns current_scene. [ADR: Design the game to be driven and verified by an LLM]
10. The persistent nav is hidden during a match takeover (the match is a full-screen modal) — 'persistent across the shell', not visible during gameplay. This also sidesteps the toast/hand layout collision in main._build_ui (which anchors off the full viewport with no bottom inset).
11. The cover/transition overlay must use a CanvasLayer layer that does not collide with the match's countdown and glitch overlays (both at layer=100); _fx_layer is at layer=5.
12. Add display/window/stretch/aspect=expand to project.godot (currently absent; with canvas_items + default 'ignore' the 720x1560 base distorts on other aspect-ratio phones). Then re-audit main.gd's fixed Y offsets (top_bar=120, hand_h=150) under expand.
13. Verify CanvasLayer + StyleBoxFlat render correctly under the GL Compatibility renderer on device before relying on them. [ADR: GL Compatibility renderer over Forward+/Forward Mobile]
14. Android Back routes through the router (pop): set_quit_on_go_back(false) + handle NOTIFICATION_WM_GO_BACK_REQUEST on the shell root (two cases only: in-match → Home, on-Home → quit). Don't steal ESC — main.gd uses it to cancel card targeting. iOS has no system Back, so the on-screen Home/Quit button is canonical.

## Open questions
_None._

## Resolved questions
1. **Greenlight to begin implementation (Phases 0–4 in the build plan)? The design, spec, and plan are captured and rest in 'planning'; firing beginImplementation should wait for explicit go-ahead to start writing the shell/router code.** — _Greenlighted by the user ('continue!') on 2026-06-09. Proceeding with implementation Phases 0-4._
2. **Decision — PvP behavior in v1: gated coming-soon, wire the dev-validator path, or omit PvP?** — _Gated coming-soon. The validator path is single-player dev validation (one player_id, signature 'dev', DEV_MODE), not a real two-player match; render the PvP button disabled/badged for now. Real PvP awaits Snapser matchmaking + session token._
3. **Decision — menu layer build style: pure-code house style, or .tscn scenes + a shared Theme resource?** — _.tscn scenes + a shared Theme resource for the menu layer (a deliberate modernization). The match scene stays imperatively code-built and is only surgically edited._
4. **Decision — navigation: a lightweight method-set on the shell, or a real UiRouter with a stackable FSM + async enter?** — _A real UiRouter autoload with a clear, stackable UiState FSM and async (await-able) enter for transitions — explicitly chosen as needed infrastructure (modals, drill-downs, awaited transitions), not over-engineering._

## References
- extends (demotes main.tscn to the match screen) → [Match Controller](architecture:mq1c2vaw-000p-3fdst6)
- uses for the gated PvP path → [Validator Client](architecture:mq1c2wgh-000r-sjn10a)
- extends the presentation layer (reuses Vfx/Anim/Quality) → [Presentation &amp; VFX](architecture:mq1c2xsl-000t-8j2hqc)
- preserves (mb_match group fallback) → [MCP Debug Interface](architecture:mq1c366g-0013-odkry1)
- honors (PvP gated coming-soon) → [Defer Nakama; ship local-authoritative single-player first](decision-record:mq1clpji-0007-t9abfq)
- honors (never touches logic/) → [Hard wall between deterministic logic and presentation](decision-record:mq1cloi4-0005-d7fpa8)
- honors (GL Compatibility verification) → [GL Compatibility renderer over Forward+/Forward Mobile](decision-record:mq1clyer-000j-p8ya0s)
- honors (next_match as a plain Dictionary) → [Game state as an untyped Dictionary mirror of SynchronizedGameState](decision-record:mq1clqiq-0009-klfz9b)
- honors (keeps MCP/LLM automation working) → [Design the game to be driven and verified by an LLM](decision-record:mq1ebq40-0001-hgjnmt)

## Child pages
- [Implementation plan](implementation-plan:mq6xiqwt-0002-gdp1zb)
- [Testing plan](testing-plan:mq6xiqwt-0003-lhtbie)
- [Spec](feature-spec:mq6xiqwt-0004-21rtgi)
- [Design — App Shell & UI Router](feature-spec:mq6xjzqc-001t-uq31eh)
- [Build Plan — App Shell & UI Router](implementation-plan:mq6xk170-001v-hxw2e7)
- [Test Plan — App Shell & UI Router](testing-plan:mq6xk2qt-001x-3oapg4)

## Commits
- `f419dbf` feat(ui): app shell + stack-based UI router + bottom nav — verified boot->Home, tab switching, Story+Infinite launch, in-match Home returns to shell
- `09ace10` feat(ui): mobile hardening — aspect=expand, Android Back -> UiRouter.pop, safe-area nav inset, Grammara font in the menu theme
