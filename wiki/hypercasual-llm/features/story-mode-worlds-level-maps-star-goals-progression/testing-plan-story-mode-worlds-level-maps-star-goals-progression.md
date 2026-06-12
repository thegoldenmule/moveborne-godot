# Testing plan — Story Mode — worlds, level maps, star goals & progression

**Status:** draft

## Planned
- Offline/degraded path: with Remote Config unreachable, story_map renders from the baked catalog and cached progress without errors; with the validator unreachable, completion shows no stars granted and the map does not advance (no client-side self-grading).
- Leaderboard regression: a completed story match still submits exactly once to the existing daily/weekly/monthly boards via should_submit (SUBMIT_MODES unchanged), with lb_submitted flag semantics intact.

## Passed
- test_story_catalog.gd (McpTestSuite): baked catalog parses; every level.scenario_id exists in MbScenarios.SCENARIOS; exactly 3 goals per level with valid type ∈ {points, max_tile}, positive thresholds, time_limit_s null-or-positive; world/level order fields form a strict total order (the unlock chain is unambiguous).
- test_remote_config_client.gd (McpTestSuite, pure helpers, no HTTP): app-config URL builder, response JSON → catalog Dictionary parse, catalog_version comparison, and fallback-to-baked-file selection logic.
- test_story_progress_client.gd (McpTestSuite, pure helpers): owner-scoped json-blob URL builder (owner/{user_id}), blob parse, merge semantics — stars are max-monotonic (a 1-star replay after 3 stars keeps 3), rewarded_stars never decreases, next_level_id advances only on stars >= 1.
- tools/verify_story_catalog.gd (headless, extends SceneTree, quit 0/1): loads res://story/story_catalog.json, cross-checks every level against the live MbScenarios table, prints VERIFY story_catalog: PASS/FAIL — CI-runnable like verify_scenarios.gd.
- validator story/goals.test.ts (bun): points goal met/unmet at threshold boundary; max_tile derived correctly from final state.tiles; time-limited goal passes at elapsed_ms <= limit and fails above; stars == count of goals met for all 0/1/2/3 combinations.
- validator story/progress.test.ts (bun): first 2-star completion grants complete + per_star[0..1] and writes {stars: 2, rewarded_stars: 2}; improving replay 2→3 grants only per_star[2]; worse replay grants nothing and keeps stars = 3; unlock (next_level_id) advances only when stars >= 1.
- validator service story-path test (bun, mocked Storage/Inventory s2s): InitMatch with mode=story + level_id stores level_id; CompleteMatch returns story_result_json {level_id, stars, goals, new_stars, rewards, next_level_id}; a second CompleteMatch on the same match returns granted=false with no second grant and no progress rewrite (latch holds).
- Parity regression gate: all pre-existing headless verifiers (verify_engine_swipe, verify_scenarios, verify_combined, verify_validation, …) PASS byte-identical with zero golden changes — proves Story Mode added no game/logic/ drift.
- E2E vs local validator (:5555 via run-validator skill): MbUi.run home → press home.story → story_map shows; pressing a locked level is inert; story_map.play launches main.tscn with the catalog's scenario_id (assert via MbDebug.get_state); after scripted MbDebug swipes + exit, GameState.last_result carries stars; validator MCP get_match_state confirms the match graded; map refresh shows stars and the next level unlocked.
- verify_ui_driver.gd extension (headless): story_map screen and story_map.play/back/level_N controls auto-register via MbUiReg; MbUi.flows() catalog includes the updated start_story and new story_play_next flows and _expand_flow resolves them.

## Failed
_None._

## References
_None._

## Child pages
_None._
