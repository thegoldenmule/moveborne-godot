# Test Plan — App Shell & UI Router

**Status:** draft

## Planned
- Boot lands on Home with the bottom nav visible and Home selected — NO match starts at boot.
- Tapping each nav tab (Collection/Leaderboard/Guilds/Settings) shows its placeholder screen and highlights that tab; Home returns to the Home screen. Selection is exclusive (one ButtonGroup).
- The center Home tab renders emphasized (larger/raised) relative to the other four tabs.
- Tapping Infinite starts an Endless match (board appears); the in-match Home/Quit button returns to the shell on Home with the nav restored.
- Tapping Story starts the selected scenario via new_game_scenario(id) — the correct scenario loads (verify against the MbScenarios table).
- The PvP button is visibly gated ('coming soon') and does not start a live match.
- Rapid double-tap on a play-mode button starts EXACTLY ONE match (router _busy lock holds); rapid tab taps during a transition do not corrupt state.
- After returning from a match, GameState.last_result is populated and the match instance is freed — no leaked MbMatch / MbValidatorClient Node / match CanvasLayers (check node count).
- Same-mode 'Play Again' (R / in-place restart) restarts WITHOUT teardown+re-instance of the whole match scene.
- MCP automation: after boot AND during a match, MbDebug.get_state() / game_eval resolves the live match via the mb_match group fallback.
- scenes/main.tscn still runs standalone (Endless default) when launched directly, with no shell present.
- Android Back: in a match -> returns to Home; on Home -> quits (or prompts). ESC still cancels card targeting in-match (not stolen by the shell).
- On a non-1560 aspect phone with stretch/aspect=expand, the shell + nav lay out without distortion; safe-area insets keep the nav above the iOS home indicator and below the notch.
- Under GL Compatibility on device: nav StyleBoxFlat, ContentHost, and the cover fade overlay (layer 200) render correctly, and the fade sits above the in-match countdown/glitch (layer 100).

## Passed
_None._

## Failed
_None._

## References
_None._

## Child pages
_None._
