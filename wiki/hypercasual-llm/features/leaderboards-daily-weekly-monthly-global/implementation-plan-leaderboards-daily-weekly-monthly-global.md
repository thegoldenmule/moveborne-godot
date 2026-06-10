# Implementation plan — Leaderboards — Daily, Weekly, Monthly (Global)

**Status:** draft

## Steps
- [x] SNAPEND CONFIG — The leaderboards snap v1.8.0 is already on snapend c4n1awfs (verified live: gateway probe returns the snap's error 9000 'Leaderboard not found'). Add the three board definitions to the manifest settings block (settings[id=leaderboards].data.leaderboards): moveborne-daily / moveborne-weekly / moveborne-monthly — type=global, behavior=maximum, sort=descending, scope=external, recurring with duration 1 day/week/month, start_time anchored at UTC midnight (daily 2026-06-10, weekly Mon 2026-06-08, monthly 2026-06-01). Apply with snapctl snapend apply — platform-side validation confirms the exact enum strings (correct and re-apply if rejected). Commit the manifest in-repo as IaC.
- [x] BACKEND SMOKE — Anonymous login through the gateway, then for each of the three boards: PUT /v1/leaderboards/leaderboards/{board}/users/{user_id}/score with a test score, GET ?range=top&count=10 and ?range=around&user_id=...&count=1. Verify 200s, 1-based ranks, and Maximum behavior (a lower second PUT does not lower the stored score).
- [x] CLIENT SERVICE — Create game/net/leaderboards_client.gd (+ .gd.uid): class_name MbLeaderboardsClient extends Node with an injected MbSnapserAuth. fetch_scores(board, range_kind, count, user_id:='', offset:=0, with_metadata:=true) → GET; submit_score(board, score, user_metadata:={}) → PUT to the caller's own user_id; submit_pending(result) → Story-only gate + PUT all three boards + mark the result consumed (lb_submitted). Mirror snapser_auth.gd's HTTPRequest coroutine pattern (child node → request → await request_completed → parse → queue_free); await ensure_session() before every call.
- [x] EXIT-FLOW HOOK — game/ui/router/match_state.gd._on_match_exited: enrich the banked result with mode (copied from GameState.next_match) and lb_submitted=false before assigning GameState.last_result; no change to main.gd's match_exited emission and none to game/logic/.
- [x] SHELL OWNERSHIP — game/ui/shell/app_shell.gd: create + add_child an MbSnapserAuth and an MbLeaderboardsClient in _ready(); on shell resume after a match pops, fire-and-forget submit_pending(GameState.last_result) so submission survives the match scene teardown and never blocks the router transition.
- [x] UI SCREEN — Create game/ui/screens/leaderboard_tab.gd/.tscn: Daily/Weekly/Monthly toggle bound to the BOARD_* constants, scrollable top-10 rows (rank, name, score), pinned own-rank row (range=around), loading/error/empty states, MbStyle occult-arcade theming; expose refresh().
- [x] SHELL WIRING — app_shell.gd screen-build loop: an index-1 branch instantiates the real LeaderboardScene (preload, like HomeScene) and hands it the shell's auth + leaderboards client; _select_tab() calls refresh() on screens exposing it when they become visible.
- [x] TESTS + REIMPORT — filesystem_manage reimport all new/changed .gd paths; add a McpTestSuite under game/tests/ covering URL/query/body construction for fetch_scores/submit_score, submit_pending gating (Story-only + lb_submitted idempotence), and response parsing of the swagger shapes; run via godot-ai test_run.
- [x] E2E VERIFY — Run the game: a Story online run → exit to shell → score lands on all three boards (Leaderboard tab shows it; cross-check with a gateway curl GET). An Infinite run → no submission. Headless parity verifiers still print PASS. Commit directly to main per repo convention.

## Data models & interfaces
```json
// settings[id=leaderboards].data.leaderboards in the c4n1awfs snapend manifest
// (field names from snapser-pb/leaderboards Leaderboard proto; enum strings
// validated server-side at `snapctl snapend apply` time)
[
  { "name": "moveborne-daily",   "description": "Best run score today (UTC)",
    "behavior": "maximum", "sort": "descending", "scope": "external",
    "type": "global", "start_time": 1781049600, "duration": 1, "time_unit": "days" },
  { "name": "moveborne-weekly",  "description": "Best run score this week (Mon UTC)",
    "behavior": "maximum", "sort": "descending", "scope": "external",
    "type": "global", "start_time": 1780876800, "duration": 1, "time_unit": "weeks" },
  { "name": "moveborne-monthly", "description": "Best run score this month (UTC)",
    "behavior": "maximum", "sort": "descending", "scope": "external",
    "type": "global", "start_time": 1780272000, "duration": 1, "time_unit": "months" }
]
```

```gdscript
## game/net/leaderboards_client.gd — client API + wire shapes for the Snapser
## Leaderboards snap (snapser-docs/swagger/leaderboards.swagger3.json), reached
## via the gateway like the validator BYOSnap.
class_name MbLeaderboardsClient
extends Node

const BASE := MbSnapserAuth.GATEWAY + "/v1/leaderboards"

## Board names — must byte-match the snapend config on c4n1awfs.
const BOARD_DAILY := "moveborne-daily"
const BOARD_WEEKLY := "moveborne-weekly"
const BOARD_MONTHLY := "moveborne-monthly"
const BOARDS := [BOARD_DAILY, BOARD_WEEKLY, BOARD_MONTHLY]

var _auth: MbSnapserAuth  # injected; await _auth.ensure_session() per call

## GetScores — GET {BASE}/leaderboards/{board}
##   ?range=top|bottom|around&count=N[&user_id=..][&offset=K][&with_metadata=true]
## Response: { "user_scores": [ { "user_id": String, "rank": int (1-based),
##   "score": float, "user_metadata": Dictionary } ], "tier": null }
func fetch_scores(board: String, range_kind: String, count: int,
		user_id := "", offset := 0, with_metadata := true) -> Dictionary:
	return {}  # coroutine: HTTPRequest GET with _auth.auth_headers()

## SetScore — PUT {BASE}/leaderboards/{board}/users/{user_id}/score
## Body: { "score": float, "user_metadata": { "name": String } }
## behavior=maximum keeps the period's best, so blind PUTs are safe.
## Response: { "user_id": String, "rank": int, "score": float }
func submit_score(board: String, score: int, user_metadata := {}) -> Dictionary:
	return {}  # coroutine: PUT, user_id == _auth.user_id

## Post-match entry point: Story-only gate, PUTs all three boards once
## (idempotent via result.lb_submitted), fire-and-forget from the shell.
func submit_pending(result: Dictionary) -> void:
	pass
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
