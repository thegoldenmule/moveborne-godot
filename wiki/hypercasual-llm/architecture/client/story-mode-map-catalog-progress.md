# Story Mode (map, catalog, progress)

**Status:** current

## Kind
subsystem

## Summary
The client half of Story Mode: a router-stacked world map (StoryMapState + the story_map screen) that renders worlds, levels, stars, and locks from the content catalog plus the server-written progress blob, launches catalog levels through the unchanged MbMatch/validator flow, and surfaces the validator's grade as a level-result overlay.

## Purpose
Give the player a candy-crush style progression surface without touching the deterministic match core. Everything here is account/meta presentation — the engine, the hashed state, and the match loop are exactly what Infinite uses.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
- **depends-on** → [Validator Client](architecture:mq1c2wgh-000r-sjn10a) — level_id rides InitMatch; story_result_json rides the completion ack (Hermes envelope)
- **depends-on** → [Story Grading & Progress](architecture:mqbe244j-00h7-q7z2dt) — renders the progress blob and grades this validator module writes

## Code references
- class `MbStoryCatalog` in `game/story/story_catalog.gd`
- class `StoryMapState` in `game/ui/router/story_map_state.gd`
- `game/ui/screens/story_map.gd`
- class `MbRemoteConfigClient` in `game/net/remote_config_client.gd`
- class `MbStoryProgressClient` in `game/net/story_progress_client.gd`
- `game/story/story_catalog.json`
- `game/tools/verify_story_e2e.gd`

## Data model
GameState gains story_catalog and story_progress caches (account-tier, never hashed). The catalog shape is story_catalog.json: worlds (ordered) of levels (ordered) with scenario_id, exactly three goals (points | max_tile, optional time_limit_s), and per-star + completion rewards. Progress mirrors the validator blob: {catalog_version, levels: {id: {stars, best_score, rewarded_stars, completed_at}}, next_level_id}. MbStoryCatalog owns the pure helpers: ordered_levels / get_level, the unlock frontier (compute_next_level / is_level_unlocked), goal_text / goal_met / max_tile_value (the display mirror of the validator grader), and match_cfg.

## Usage
home.story pushes StoryMapState (stack [Shell, StoryMap], then [Shell, StoryMap, Match] during a level). On entry the screen signs in anonymously and fetches the catalog (MbRemoteConfigClient app-config, falling back to the baked res://story/story_catalog.json) and progress (MbStoryProgressClient, read-only); story is online-only and gates behind a connect-to-play panel otherwise. Play builds GameState.next_match {mode: story, level_id, scenario_id, goals}; scenes/main.gd threads level_id into InitMatch and renders a display-only goal HUD; the completion ack's story_result_json is banked into GameState.last_result, and the map shows it on resume, re-fetches progress, and flushes pending leaderboard results. Automation: MbUi goto(story) lands on the interactable map; flows start_story and story_play_next; headless E2E via tools/verify_story_e2e.gd (MB_E2E_DEPLOYED=1 targets the live snapend).

## Invariants & constraints
- The client never writes progress and never grades authoritatively: stars and unlocks render from the validator-written blob; the in-match goal HUD and result overlay are display claims only.
- A remote catalog is adopted only when structurally valid and its catalog_version is at least the baked copy (a stale or malformed remote payload cannot downgrade a shipped client).
- The unlock frontier is recomputed client-side from catalog order — a stale blob next_level_id can never wedge the map.
- Story moves are gated until validator registration completes so the registered starting state stays fresh; the gate clears on connection error (offline degrades to unrecorded play, never a locked board).

## Synced commit
88f0457
