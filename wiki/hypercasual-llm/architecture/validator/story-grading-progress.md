# Story Grading & Progress

**Status:** current

## Kind
module

## Summary
The validator's story module: catalog loading and validation, post-match goal grading, and the per-user progress blob (Storage s2s) with watermarked, cas-guarded reward grants on CompleteMatch.

## Purpose
Make stars, unlocks, and star rewards server-authoritative without touching the deterministic engine or the hashed state. Grading consumes only validator-held inputs: the validated final state, server wall-clock elapsed time, and the committed catalog.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
- **depends-on** → [Match State Store](architecture:mq1c31rb-000x-6l2ehj) — StoredMatch carries level_id, created_at (wall-clock base), and the rewards_granted latch

## Code references
- function `getLevel` in `validator/src/validator/story/catalog.ts`
- function `gradeLevel` in `validator/src/validator/story/goals.ts`
- function `applyGrade` in `validator/src/validator/story/progress.ts`
- `validator/src/validator/story/types.ts`
- class `StorageClient` in `validator/src/validator/snaps/storage.ts`
- function `completeMatch` in `validator/src/validator/service.ts`
- `validator/content/story_catalog.json`

## Data model
story/types.ts: StoryCatalog → StoryWorld → StoryLevel (existing scenario_id, exactly three StoryGoals of type points | max_tile with optional time_limit_s, per-star + completion reward amounts); StoryGradeResult (stars = count of goals met); StoryProgress {catalog_version, levels: {id: LevelProgress {stars, best_score, rewarded_stars, completed_at}}, next_level_id}; StoryResult — the story_result_json payload {level_id, stars, goals, new_stars, rewards, next_level_id, unlocked}. Catalog reward amounts are plain numbers, stringified at the Inventory edge per the *_64 convention.

## Usage
InitMatch binds level_id for story matches (unknown ids rejected) and enforces the fresh-state guard on the client-supplied starting state (score 0, moveIndex 0, max tile <= 64 and strictly below the level's max_tile goal thresholds). CompleteMatch — after the per-match rewards_granted latch — runs gradeLevel(final state, elapsed_ms), reads the story_progress blob (readJsonBlob; a failed read aborts persistence), checks isLevelUnlocked against the frontier, merges via applyGrade (max-monotonic stars, rewarded_stars watermark, frontier recompute), writes back with the cas token, grants only the newly earned tier deltas through the Inventory s2s path, and returns story_result_json. Local dev runs with both s2s transports disabled: grades report, rewards withhold. Covered by the story-goals / story-progress / service-story bun suites and the game-side headless E2E.

## Invariants & constraints
- Grading inputs are validator-held only — the client chooses WHEN to settle, never WHAT is graded.
- A failed progress READ aborts persistence and granting; a transient failure is never treated as no-progress-yet (that would wipe the blob and reset every watermark).
- Writes are cas-guarded: a concurrent completion loses the write and its grant is withheld, so the same star tier can never double-mint.
- rewarded_stars never decreases and gates every grant; the completion reward grants exactly once; stars are max-monotonic.
- A locked level (beyond the recomputed unlock frontier) grades but neither grants nor persists.
- A story match without a level_id grants nothing — catalog star rewards fully replaced the flat story reward table.

## Synced commit
88f0457
