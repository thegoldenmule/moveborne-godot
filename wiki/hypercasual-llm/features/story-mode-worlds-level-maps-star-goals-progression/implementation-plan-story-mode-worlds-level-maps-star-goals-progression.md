# Implementation plan — Story Mode — worlds, level maps, star goals & progression

**Status:** draft

## Steps
- [x] Provision platform prerequisites: add remote-config and storage snaps to snapend c4n1awfs (snapser MCP update_snapend / snapctl) and reflect them in snapser/snapend-manifest.json; smoke GET /v1/remote-config/app-config/{version} and an owner-scoped Storage json-blob through the gateway using the snapser-validator skill. BLOCKED on the open progress-store question (Storage blob vs Quests).
- [x] Author content/story_catalog.json — worlds → levels mapped onto existing MbScenarios.SCENARIOS ids (0–17), 3 goals each, per-star rewards; add a small uploader script (tools/ or validator/tools/) that pushes it to Remote Config app-config; bake the same file at game/story/story_catalog.json as the client fallback; commit the catalog.
- [x] Build the validator story module — validator/src/validator/story/catalog.ts (load + validate the committed catalog), story/goals.ts (pure gradeLevel: score, max-tile-from-tiles, elapsed_ms vs time_limit_s → 0–3 stars), story/progress.ts (Storage s2s json-blob read/merge/write with max-stars + rewarded_stars watermark + next_level_id unlock, patterned on snaps/inventory.ts); extend types.ts StoredMatch with level_id; rewire the rewards.ts story branch to catalog-driven per-star deltas (replacing floor(score/10), pending the economy decision).
- [x] Extend the wire contract — add InitMatchRequest.level_id and CompleteMatchResponse.story_result_json to validator/protos/moveborne/validator/v1/validator_messages.proto; regenerate godobuf bindings into game/net/proto/ per its README; update service.ts InitMatch to store level_id (story mode only; ownership rules unchanged).
- [x] Implement the CompleteMatch story path in validator/src/validator/service.ts — keep the rewards_granted latch; grade via story/goals.ts; compute new-star reward deltas against rewarded_stars; grant via the existing Inventory incrementUserCurrency s2s; persist the progress blob via story/progress.ts; return story_result_json + balances. Cover with bun tests (goals.test.ts, progress.test.ts, service story-path test) and bun run type-check.
- [x] Build the client data layer — game/net/remote_config_client.gd (MbRemoteConfigClient) and game/net/story_progress_client.gd (MbStoryProgressClient) with static pure helpers (URL/body/parse) + awaitable network coroutines per the leaderboards_client.gd template; game/story/story_catalog.gd parser/lookups (pure, NOT in game/logic/); add story_catalog/story_progress caches + story_progress_changed signal to game/ui/game_state.gd; fetch catalog (Remote Config → baked fallback) and progress on story entry.
- [x] Build the map flow — new game/ui/router/story_map_state.gd (StoryMapState extends ui_state.gd) and game/ui/screens/story_map.gd/.tscn: linear per-world level path with stars/locks/next-level highlight and Play, all controls registered via Reg.adopt/Reg.screen (story_map.play, story_map.back, story_map.level_N); rewire home.gd:48 so home.story pushes StoryMapState instead of launching {mode: story, scenario_id: 0} directly.
- [x] Thread the level through the match — StoryMapState builds GameState.next_match = {mode: story, level_id, scenario_id, seed, goals}; scenes/main.gd passes level_id into hermes_client.init_and_connect()/InitMatchRequest and renders a goal-progress HUD (display only — engine untouched); hermes_client.gd complete_match() parses story_result_json; match_state.gd._on_match_exited tags last_result with level_id/stars/goals/rewards.
- [x] Build the level-result presentation — on pop back to StoryMapState, show a result overlay (stars earned, per-goal pass/fail, rewards granted, next level unlocked) from GameState.last_result, then refresh the map from the re-fetched progress blob; merge returned balances into GameState.currencies as today (main.gd complete-match await path unchanged).
- [x] Wire test/driver surfaces — add story flows to MbUi.FLOWS in game/game/mcp_ui_api.gd (updated start_story → home.story → story_map → play; new story_play_next) with _expand_flow support; add McpTestSuite suites game/tests/test_story_catalog.gd, test_remote_config_client.gd, test_story_progress_client.gd; add headless game/tools/verify_story_catalog.gd (catalog ↔ MbScenarios cross-check); extend tools/verify_ui_driver.gd for the new screen registrations.
- [x] Verify and ship — run ALL existing parity verifiers unchanged (engine_swipe, scenarios, combined, validation, …) to prove zero game/logic/ drift; E2E against the local validator (run-validator skill, :5555 Hermes-emulation, validator MCP get_match_state/simulate_action) driving MbUi+MbDebug headlessly; then deploy the validator BYOSnap (build context validator/, external port unchanged), upload the catalog to Remote Config, live-smoke through the gateway; the user verifies the UI visually.
- [ ] Post-review cleanup (deferred from /code-review high; non-blocking): (a) hoist the duplicated HTTPRequest round-trip helper now copied across remote_config_client.gd / story_progress_client.gd / leaderboards_client.gd / profile_client.gd; (b) extract the duplicated s2s transport resolution shared by snaps/inventory.ts and snaps/storage.ts; (c) route post-match result flushing through an event/autoload instead of StoryMapState's mcp_shell group lookup; (d) consider deriving the init-guard tile cap from data instead of the 64 constant once the scenario table lives server-side.

## Data models & interfaces
```json
// content/story_catalog.json — the ONE canonical level/world definition.
// Committed to git; uploaded verbatim to Snapser Remote Config app-config;
// baked into the client at res://story/story_catalog.json as offline/dev fallback;
// loaded by the validator (validator/src/validator/story/catalog.ts) for grading.
// scenario_id MUST reference an existing MbScenarios.SCENARIOS entry (parity-hashed; unchanged).
{
  "catalog_version": 1,
  "worlds": [
    {
      "id": "w1",
      "name": "World 1",
      "order": 0,
      "levels": [
        {
          "id": "w1_l1",
          "order": 0,
          "scenario_id": 0,
          "name": "Freeze Focus",
          "goals": [
            { "type": "points",   "threshold": 500,  "time_limit_s": null },
            { "type": "points",   "threshold": 1500, "time_limit_s": null },
            { "type": "max_tile", "threshold": 256,  "time_limit_s": 180 }
          ],
          "rewards": {
            "complete": { "coins": 25 },
            "per_star": [ { "coins": 10 }, { "coins": 20 }, { "gems": 1 } ]
          }
        }
      ]
    }
  ]
}
```

```json
// Per-user progress — Snapser Storage snap user-scoped json-blob:
// PUT/GET /v1/storage/owner/{user_id}/{access_type}/json-blobs/story_progress
// Written ONLY by the validator via s2s on CompleteMatch (anti-forgery);
// the client (MbStoryProgressClient) reads it to render the map.
// rewarded_stars is the idempotency watermark: replays grant per_star rewards
// only for stars ABOVE this value; stars never decreases (max semantics).
{
  "catalog_version": 1,
  "levels": {
    "w1_l1": { "stars": 3, "best_score": 2210, "rewarded_stars": 3, "completed_at": "2026-06-12T18:00:00Z" },
    "w1_l2": { "stars": 1, "best_score": 740,  "rewarded_stars": 1, "completed_at": "2026-06-12T18:20:00Z" }
  },
  "next_level_id": "w1_l3"
}
```

```typescript
// validator/src/validator/story/types.ts (new) — grading model.
// Pure, post-match, OUTSIDE the determinism hash domain (no engine/state-shape changes).
import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";
import type { CurrencyDeltas } from "../types";

export type StoryGoalType = "points" | "max_tile";

export interface StoryGoal {
  type: StoryGoalType;
  threshold: number;          // points: state.score >= threshold; max_tile: max tile value on final board >= threshold
  time_limit_s: number | null; // if set, goal counts only when elapsed_ms <= time_limit_s * 1000
}

export interface StoryLevel {
  id: string;
  order: number;
  scenario_id: number;        // existing MbScenarios id — engine config unchanged
  name: string;
  goals: [StoryGoal, StoryGoal, StoryGoal];
  rewards: { complete: CurrencyDeltas; per_star: [CurrencyDeltas, CurrencyDeltas, CurrencyDeltas] };
}

export interface GoalResult { goal: StoryGoal; met: boolean; value: number; }

// story/goals.ts: stars = count of goals met (1 goal = 1 star, all 3 = 3 stars).
// elapsed_ms = CompleteMatch arrival time - StoredMatch.created_at (server wall-clock).
export interface StoryGradeResult { stars: 0 | 1 | 2 | 3; goals: GoalResult[]; }
export declare function gradeLevel(
  level: StoryLevel,
  finalState: SynchronizedGameState,
  elapsedMs: number,
): StoryGradeResult;

// types.ts StoredMatch gains: level_id?: string (set at InitMatch when mode === "story").
// Proto additions (validator_messages.proto, then godobuf regen into game/net/proto/):
//   InitMatchRequest      += string level_id;
//   CompleteMatchResponse += string story_result_json;  // JSON-in-proto wire convention
// story_result_json payload: { level_id, stars, goals: GoalResult[], new_stars, rewards, next_level_id, unlocked }
```

```gdscript
## game/ui/game_state.gd additions — account-tier caches, mirroring currencies/profile.
## NOT part of SynchronizedGameState, never hashed (hard-wall ADR).

## Parsed story catalog: Remote Config app-config when reachable, else the baked
## res://story/story_catalog.json fallback. Shape = content/story_catalog.json.
var story_catalog: Dictionary = {}

## Mirror of the Storage-snap story_progress json-blob (client READ-ONLY;
## the validator is the sole writer). Shape = the progress blob above.
var story_progress: Dictionary = {}

signal story_progress_changed(progress: Dictionary)

## next_match for a story launch (built by StoryMapState, consumed by scenes/main.gd):
##   { "mode": "story", "level_id": "w1_l1", "scenario_id": 0, "seed": int,
##     "goals": Array }   # goals copied from the catalog for in-match HUD display only
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
