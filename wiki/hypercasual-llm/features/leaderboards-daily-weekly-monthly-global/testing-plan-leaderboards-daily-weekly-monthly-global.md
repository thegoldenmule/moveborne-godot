# Testing plan — Leaderboards — Daily, Weekly, Monthly (Global)

**Status:** draft

## Planned
_None._

## Passed
- fetch_scores builds GET {GATEWAY}/v1/leaderboards/leaderboards/moveborne-daily?range=top&count=10&with_metadata=true with exactly the Token/User-Id headers from MbSnapserAuth.auth_headers(), and parses the response into [{user_id, rank:int (1-based), score, user_metadata}] preserving server order.
- submit_score builds PUT .../leaderboards/{board}/users/{auth.user_id}/score with JSON body {score: <number>, user_metadata: {name: <anon username>}} and surfaces the response {user_id, rank, score}; int score round-trips through JSON double without breaking int display.
- submit_pending gating: a result with mode='story' and lb_submitted=false submits to all three boards exactly once and sets lb_submitted=true; a second submit_pending call is a no-op (no duplicate PUTs); a result with mode='infinite' is skipped entirely (Story-only policy).
- Maximum behavior live: PUT 500 then 300 on the same board within one period → GET range=around returns score 500; PUT 800 → returns 800 (verified against the real gateway).
- Auth path: with a stale/empty user://snapser_session.json, the first leaderboards call triggers MbSnapserAuth.ensure_session() re-login before the request; a non-200 response renders the screen's error state without crashing the shell.
- Tab UI: selecting the Leaderboard tab (index 1) calls refresh() and renders top-10 + own-rank for Daily; toggling Weekly/Monthly refetches with the correct board constant; an unreachable snap shows the error/empty state and the shell stays responsive.
- Match-exit integration: play a Story run online, exit to the shell — match_exited result flows through MatchState into GameState.last_result with mode + lb_submitted added, the router pops, the shell resumes, and the score appears on all three boards; a submission failure (offline) does not block or delay the pop/resume transition.
- Negative auth: a PUT to another user's score path (user_id != session user) through the gateway is rejected — confirms user-auth writes bind to the gateway-stamped User-Id.
- Determinism untouched: headless parity verifiers (e.g. --script res://tools/verify_combined.gd) still print PASS, proving no game/logic/ behavior changed.

## Failed
_None._

## References
_None._

## Child pages
_None._
