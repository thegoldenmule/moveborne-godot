# Spec — Leaderboards — Daily, Weekly, Monthly (Global)

**Status:** sealed

## Overview
Daily, weekly, and monthly global high-score boards backed by Snapser's first-party Leaderboards snap on snapend c4n1awfs, read and written by the Godot client through the gateway using the existing anonymous-session auth (Token / User-Id headers from MbSnapserAuth). Shipped in commit 14b4e76: backend work is pure snapend configuration (IaC manifest), client work is a new HTTP service plus a real Leaderboard tab replacing the placeholder stub. game/logic/ is untouched — scores are existing deterministic engine output — so determinism parity is unaffected.

## Design
## Backend (configuration only)

Three recurring Global boards — moveborne-daily, moveborne-weekly, moveborne-monthly — defined in the leaderboards snap settings of the committed snapend manifest (infrastructure-as-code) and applied via snapctl snapend apply. Board semantics: behavior=maximum plus PUT SetScore gives the best single-run score per period (blind re-PUTs are safe, the server keeps the max); sort=descending, type=global, scope=external (interim, client-writable until validator-reported scores land). Recurrence anchors at UTC midnight: daily 2026-06-10, weekly Monday 2026-06-08, monthly 2026-06-01. Board names are load-bearing — client constants byte-match the snapend config.

## Client service, shell wiring, UI

A new gateway HTTP service mirrors the proven anonymous-auth client pattern: one call fetches standings (GET, top or around ranges) and one submits a score (PUT SetScore, always to the session user's own id — the gateway binds user-auth writes to the session user). A pending-submit gate runs on the shell-resume path after a match pops: Story results are PUT to each of the three boards individually (the batch endpoints are api-key auth), Infinite results are skipped, and the banked result is marked consumed so re-submission is idempotent. Auth is lazy: the session is ensured on first leaderboards use (tab open or pending submit), not at shell startup, so offline Infinite players incur no network call on launch. The request node is parented to the shell so it survives match-scene teardown, and submission is fire-and-forget — it never blocks the router pop or resume. Score parsing tolerates int and float ambiguity (the swagger score type is double, the engine score is int); submissions stash the anon username in the user metadata name field and the list UI falls back to a truncated user id.

```text
game/net/leaderboards_client.gd — class_name MbLeaderboardsClient (injected MbSnapserAuth)
  fetch_scores(board, range_kind, count, ...)  # GET range=top|around
  submit_score(board, score, user_metadata)    # PUT SetScore, own user_id only
  submit_pending(result)                       # Story-only gate; PUTs all three boards; sets lb_submitted
  BOARD_DAILY / BOARD_WEEKLY / BOARD_MONTHLY   # byte-match the snapend config
game/ui/router/match_state.gd — banked result enriched with mode + lb_submitted
game/ui/shell/app_shell.gd — owns MbSnapserAuth + MbLeaderboardsClient; fires submit_pending
  on shell resume; instantiates the real Leaderboard screen at tab index 1; refresh-on-select
game/ui/screens/leaderboard_tab.gd/.tscn — Daily/Weekly/Monthly toggle, top-10 list,
  pinned own-rank row (range=around), loading/error/empty states, MbStyle theming
game/tests/test_leaderboards_client.gd — McpTestSuite: request construction, submission
  gating, response parsing (run via godot-ai test_run)
```

## Decisions
Story-only auto-submit for v1: the pending-submit gate skips Infinite results, honoring the written authority model (no leaderboard writes from Infinite). Story is what the validator will report later, so gating on Story is forward-compatible. The gate is a single constant; if product prefers the intent-faithful reading (Infinite high scores carry the social weight), flipping it is a one-line change. Infinite-mode submission: the authority model forbids leaderboard writes from Infinite (offline = client-trust), yet the Leaderboards design section says boards give Infinite high scores social weight. v1 ships Story-only auto-submit — should Infinite ever submit (opt-in affordance, or once a trust story exists)?

Migration to validator-reported scores is deferred; it is not a v1 blocker. v1 ships the interim posture: scope=external with client PUTs from Story runs only. The cutover mechanics are a product and release call to make when validator-reported scoring is scheduled: either flip scope to internal and lock SetScore via User Auth Restrictions behind a client release that removes the client submit path, or run a transition window where client and validator writes coexist (safe under behavior=maximum, the server keeps the max). Re-raise on that feature's brief. Migration to validator-reported scores (declared future work): when the validator starts submitting, do the boards flip scope to internal / lock SetScore via User Auth Restrictions (breaking older clients' writes, requiring a client release that removes submit_pending), or do client and validator writes coexist during a transition window? Needs a product/release call when that feature is scheduled.

## References
_None._

## Child pages
_None._
