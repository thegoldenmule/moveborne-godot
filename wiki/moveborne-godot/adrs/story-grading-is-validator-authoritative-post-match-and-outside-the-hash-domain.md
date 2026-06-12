# ADR-22: Story grading is validator-authoritative, post-match, and outside the hash domain

**Status:** accepted

## Metadata
- **Date:** 2026-06-12
- **Scope:** validator + game client (story mode)
- **Deciders:** Benjamin Jordan

## Context
Story mode needed three-goal star grading, rewards, and unlock progression on top of a deterministic engine whose hashed SynchronizedGameState is a byte-for-byte parity domain with the TS dist (golden vectors, deployed validator). The state even carries a dormant level field that tempts reuse. Any state-shape or rule change breaks every golden hash and desyncs the deployed validator, so the question was where story rules could live at all.

## Decision
All story rules live OUTSIDE game/logic/ and the hashed state. Goals are graded only at CompleteMatch, by the validator, against its own validated final state (score, max tile on the final board) plus server wall-clock elapsed time from StoredMatch.created_at. The dormant SynchronizedGameState.level field stays deliberately unused.

Level identity travels as match-registration metadata: InitMatchRequest.level_id is bound at init (unknown ids rejected) and the grade returns as CompleteMatchResponse.story_result_json per the JSON-in-proto wire convention.

Because the starting state is client-supplied, story inits enforce a fresh-state guard: score 0, moveIndex 0, and a starting board whose max tile is at most 64 AND strictly below every max_tile goal threshold of the level. Exact scenario-board reconstruction is deferred until the scenario table exists server-side.

## Consequences
Determinism parity is untouched: every golden vector and parity verifier passes byte-identical, and story content changes never require engine redeploy coordination.

The client can only display claims (goal HUD, result overlay); it cannot inflate a grade — it only chooses when to settle. Timed goals run on raw validator wall-clock; a timer-suspending pause mechanic is post-v1.

Grading must complete in-session because validator match state is in-memory; an abandoned match loses its grade, consistent with existing reward behavior.

The 64-tile cap in the fresh-state guard is a data-coupled constant: adding a scenario with a larger fixed starting tile requires revisiting the guard (tracked on the implementation plan).

## Relations
_None._
