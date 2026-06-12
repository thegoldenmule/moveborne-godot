# Spec — Story Mode — worlds, level maps, star goals & progression

**Status:** drafting

## Overview
Story Mode gives Moveborne a worlds-and-levels campaign: a linear, candy-crush-style map per world, three-goal levels graded 0–3 stars by the validator, star-gated progression (≥1 star unlocks the next level), per-level rewards, and fully data-driven content. Content is served from Snapser Remote Config with a baked client fallback; per-user progress lives in a Snapser Storage json-blob written only by the validator. Every new rule lives outside the deterministic engine, so byte-for-byte hash parity with the TS dist is untouched.

## Design
## Player experience

The Story button on home opens the story map instead of immediately launching scenario 0 (today home.gd:48 hardcodes that launch). The map shows the current world as a linear path of level nodes: completed levels show their earned stars (0–3), the next playable level is highlighted, and levels beyond it are locked and inert. Tapping Play launches the match for that level's scenario through the existing match flow. On return, a result overlay shows per-goal pass/fail, stars earned, rewards granted, and — when at least one star was earned — the next level unlocking on the map. Completing a world's last level advances to the next world.

Each level defines exactly three goals. A goal is either points (final score at or above a threshold) or max_tile (highest tile value on the final board at or above a threshold), and may optionally carry a time limit in seconds. Meeting one goal earns one star; meeting all three earns three stars. At least one star is required to unlock the next level. Replays can only improve a level's recorded stars, never lower them.

## Content catalog and pipeline

All worlds and levels are described in one committed JSON document, content/story_catalog.json. The same file is uploaded verbatim to the Snapser Remote Config snap as app-config (the live source the client fetches on story entry), baked into the client at game/story/story_catalog.json as the offline/dev fallback, and loaded by the validator to grade matches. A catalog_version field guards against drift between the three surfaces. Levels reference existing MbScenarios ids (0–17) only; genuinely new level mechanics require TS-first scenario authoring plus regenerated golden vectors and are out of scope for v1.

## Grading and stars — validator-authoritative

The engine and the hashed SynchronizedGameState are untouched: goal evaluation happens only at CompleteMatch in the validator, against the final validated state. Score comes from state.score, max tile from the final tiles, and elapsed time is server wall-clock from StoredMatch.created_at to CompleteMatch arrival. Because validator match state is in-memory, grading must complete in-session. The validator returns a story_result_json payload inside CompleteMatchResponse; the client renders it without recomputing anything.

```json
// story_result_json — returned in CompleteMatchResponse (JSON-in-proto convention)
{
  "level_id": "w1_l1",
  "stars": 2,
  "goals": [
    { "goal": { "type": "points", "threshold": 500, "time_limit_s": null }, "met": true,  "value": 740 },
    { "goal": { "type": "points", "threshold": 1500, "time_limit_s": null }, "met": false, "value": 740 },
    { "goal": { "type": "max_tile", "threshold": 256, "time_limit_s": 180 }, "met": true,  "value": 256 }
  ],
  "new_stars": 2,
  "rewards": { "coins": 55 },
  "next_level_id": "w1_l2",
  "unlocked": true
}
```

## Progress storage, unlocks, rewards

Per-user progress lives in a Storage-snap user-scoped json-blob (story_progress), written only by the validator via s2s and read by the client to draw the map. Stars are max-monotonic; rewarded_stars is the idempotency watermark so a replay grants only newly earned star tiers; next_level_id advances when a level first reaches one star. Currency rewards are granted through the existing Inventory s2s path and the returned balances merge into GameState.currencies exactly as today. The per-match rewards_granted latch is kept, so a duplicate CompleteMatch neither double-grants nor rewrites progress.

## Wire contract changes

Two additive proto fields on existing messages: InitMatchRequest.level_id (stored on StoredMatch for story matches) and CompleteMatchResponse.story_result_json (a canonical-JSON string, per the JSON-in-proto convention). Godobuf bindings are regenerated into game/net/proto/ per its README. The deployed external port is unchanged, and the validator deploys before the client per the existing wire-contract rule.

## Client architecture

A new StoryMapState router state sits between ShellState and MatchState; home.story pushes it. The story_map screen renders from GameState.story_catalog and GameState.story_progress, both fetched on entry (Remote Config with baked fallback; the Storage blob read-only via MbStoryProgressClient). StoryMapState builds GameState.next_match with mode story, level_id, scenario_id, seed, and the goals copied from the catalog for an in-match display-only HUD, then launches MatchState; on resume it refreshes progress and shows the result overlay from GameState.last_result. All controls register through MbUiReg (story_map.play, story_map.back, story_map.level_N) and MbUi.FLOWS gains an updated start_story plus a new story_play_next flow, keeping the screen drivable headlessly.

## Security

Clients never write progress: the Storage blob is s2s-only, grading uses only validator-held state and timestamps, and match ownership keeps the gateway-stamped player binding. This keeps the star system from widening the open user-auth self-grant hardening finding.

## Out of scope for v1

New scenario mechanics (TS-first authoring plus goldens), per-level leaderboards (would need new board provisioning), surfacing stars on profiles, PvP interactions, and offline story progression. Infinite mode is untouched and remains fully offline.

Also out of scope for v1: a pause mechanic that suspends the wall-clock timer for timed goals (planned later; until then timed goals run on raw validator wall-clock).

## Decisions
Level identity does NOT use the dormant SynchronizedGameState.level field. Any hashed-state shape change breaks byte-for-byte parity with the TS dist and every golden vector. Level identity travels as match-registration metadata: InitMatchRequest.level_id → StoredMatch.level_id, echoed back in story_result_json. Should level identity ride in the dormant SynchronizedGameState.level field instead of new wire metadata?

Star grading is validator-authoritative. CompleteMatch grades its own validated final state plus server wall-clock elapsed time; the client only renders story_result_json. The progress blob is written s2s-only and is read-only to clients, so stars, unlocks, and rewards cannot be forged. Where are stars graded — client or validator?

One committed catalog (content/story_catalog.json) is the single source of truth: uploaded verbatim to Remote Config app-config, baked into the client as fallback, and loaded by the validator for grading. catalog_version detects drift between surfaces. One content catalog or separate per-surface level definitions (client / validator / Remote Config)?

Progress store: Storage-snap user json-blob written s2s by the validator. Quests stays the pattern for daily features; the two coexist separately. (User decision 2026-06-12.) Progress store choice (platform commitment): Storage-snap user json-blob written s2s by the validator (this plan's default — single document, atomic watermark, read-only client) vs modeling each level as a one-time Quests-snap quest (the Daily Missions spec's precedent uses Quests + Remote Config). Both shape provisioning and all later metagame features — needs a call before provisioning.

Reward economy: catalog per-star/completion rewards fully replace the floor(score/10) story branch in validator rewards.ts. Amounts are tuned in content/story_catalog.json. Reward economy tuning: concrete per-star and completion amounts per level, and whether the existing story coins = floor(score/10) (validator rewards.ts, marked pending game-design tuning) survives as a base alongside catalog rewards or is fully replaced.

Timed goals use raw validator wall-clock (created_at to CompleteMatch arrival), no tolerance. A pause mechanic that suspends the timer is a later version, not v1. Time-requirement semantics: validator wall-clock (created_at → CompleteMatch arrival) is the only forge-proof signal, but it penalizes connection stalls and pauses — accept wall-clock with a tolerance, or defer timed goals to a later pass? (A move-count proxy would change nothing in the engine but alters design intent.)

v1 content: 3 worlds of 15 levels each (45 total), built only from existing scenarios. World 1 is ice/freeze-only; each later world introduces an additional mechanic; difficulty escalates via goal thresholds on scenario repeats. v1 content scope: how many worlds/levels at launch, and the exact mapping of the 18 existing scenarios (Tutorial/Amplify/…/Fracture) onto the world map? Genuinely NEW level mechanics require TS-first scenario authoring plus regenerated goldens — out of v1 scope?

Offline: the Story button gates with a connect-to-play message when unauthenticated/offline. No offline story play in v1. Offline Story behavior: today Story implicitly requires Snapser sign-in; when offline should the Story button (a) gate with a connect-to-play message, or (b) allow playing the unlocked level with zero stars/rewards/progress recorded?

Stars display only inside story_map for v1; no Profiles-snap attribute or social surfaces. Star display surface: should earned stars/world progress also surface outside story_map (e.g. a Profiles-snap attribute like total_stars next to display_name/avatar_id/title for social surfaces), or stay private to the progress blob for v1?

## References
_None._

## Child pages
_None._
