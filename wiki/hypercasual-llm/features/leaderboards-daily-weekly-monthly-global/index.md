# Feature: Leaderboards — Daily, Weekly, Monthly (Global)

**Status:** shipped

## Summary
Fill out the leaderboard section: daily, weekly, and monthly global high-score boards backed by Snapser's first-party Leaderboards snap — which is already deployed on snapend c4n1awfs (v1.8.0, verified live: a gateway probe returns the snap's own error 9000 'Leaderboard not found') — with the Godot client reading standings and submitting scores through the gateway using the existing anonymous-session auth (Token / User-Id headers from MbSnapserAuth). Backend work is pure configuration: three recurring Global boards (behavior=maximum, sort=descending, scope=external) added to the snapend manifest's leaderboards settings and applied via snapctl snapend apply. Client work: a new HTTP service game/net/leaderboards_client.gd mirroring the proven snapser_auth.gd HTTPRequest pattern, a post-match submission hook on the shell-resume path (Story runs only — the design doc's authority model keeps offline Infinite results off shared boards), and a real Leaderboard tab screen replacing the placeholder stub at shell tab index 1. Scores come from the deterministic engine output (state['score']); game/logic/ is untouched, so determinism parity is unaffected. Validator-reported scores (the design doc's target authority model) are explicitly future work; scope=external is the interim posture and flips when that lands.

## Components affected
- Snapend config (IaC): three recurring global boards (moveborne-daily / moveborne-weekly / moveborne-monthly) defined in the leaderboards snap settings of the c4n1awfs manifest, applied via snapctl snapend apply; manifest committed in-repo as infrastructure-as-code
- game/net/leaderboards_client.gd — MbLeaderboardsClient: fetch_scores (GET range=top|around) + submit_score (PUT SetScore) + submit_pending mode-gate, all via the gateway with MbSnapserAuth.auth_headers()
- game/ui/router/match_state.gd — banked match result enriched with mode + lb_submitted before it lands in GameState.last_result
- game/ui/shell/app_shell.gd — owns MbSnapserAuth + MbLeaderboardsClient, fires submit_pending on shell resume, instantiates the real Leaderboard screen at tab index 1, refresh-on-select hook
- game/ui/screens/leaderboard_tab.gd/.tscn — Daily/Weekly/Monthly toggle, top-10 list, pinned own-rank row, loading/error states, MbStyle occult-arcade theming
- game/tests/ McpTestSuite — request construction, submission gating, response parsing; run via godot-ai test_run

## Design constraints
1. Gateway-stamped auth only: every leaderboards call carries Token + User-Id from MbSnapserAuth.auth_headers(); SetScore targets the caller's own user_id (the gateway binds user-auth writes to the session user — verified by a negative cross-user test).
2. Per-user endpoints only: the batch leaderboards endpoints (/v1/leaderboards/batch/...) are api-key/internal auth; the client PUTs each of the three boards individually.
3. DECIDED — Story-only submission: design/general.md authority model says 'keep offline results off shared surfaces (no leaderboard writes from Infinite)'; submit_pending skips Infinite results. The gate is a single constant, easy to revisit at review.
4. DECIDED — Board semantics: behavior=maximum + PUT SetScore = best single-run score per period (blind re-PUTs safe, server keeps the max); sort=descending, type=global, scope=external (interim: client-writable until the validator reports scores).
5. Board names are load-bearing: client constants must byte-match the snapend config (moveborne-daily / moveborne-weekly / moveborne-monthly); recurrence anchors at UTC midnight — daily 2026-06-10T00:00Z, weekly Monday 2026-06-08T00:00Z, monthly 2026-06-01T00:00Z.
6. No game/logic/ changes: score is existing deterministic engine output (state['score']); headless parity verifiers must still PASS — the feature lives entirely in net / ui / shell layers.
7. HTTPRequest nodes must be inside the scene tree before request() (ERR_UNCONFIGURED otherwise); the leaderboards client is parented to the shell so it survives match-scene teardown, and submission is fire-and-forget — it must never block the router pop/resume.
8. JSON numbers: the swagger score type is double while the engine score is int — submit the numeric score and parse responses tolerating int/float ambiguity (int() casts for display).
9. DECIDED — Display names: submit_score stashes the anon username in user_metadata.name; the list UI prefers the metadata name and falls back to a truncated user_id.
10. DECIDED — Lazy auth: ensure_session() is awaited on first leaderboards use (tab open or pending submit), not at shell startup, so offline Infinite players incur no network call on launch.
11. wiki/ is an emitted mirror — all feature-page edits go through the wiki MCP, never the .md files on disk. snapser-pb/ Go bindings are reference-only and are never wired into the Godot client.

## Open questions
_None._

## Resolved questions
1. **Infinite-mode submission: the authority model forbids leaderboard writes from Infinite (offline = client-trust), yet the Leaderboards design section says boards give Infinite high scores social weight. v1 ships Story-only auto-submit — should Infinite ever submit (opt-in affordance, or once a trust story exists)?** — _DECIDED for v1: Story-only auto-submit (wiki-faithful). In v1 both modes would be equally client-trust, but Story is what the validator will report later, so gating on Story is forward-compatible and honors the written authority model ('no leaderboard writes from Infinite'). The gate is a single constant in submit_pending — if the owner prefers the intent-faithful reading (Infinite high scores carry the social weight), flipping it is a one-line change plus this answer's revision at review._
2. **Migration to validator-reported scores (declared future work): when the validator starts submitting, do the boards flip scope to internal / lock SetScore via User Auth Restrictions (breaking older clients' writes, requiring a client release that removes submit_pending), or do client and validator writes coexist during a transition window? Needs a product/release call when that feature is scheduled.** — _DEFERRED — not a v1 blocker. v1 ships with the decided interim posture (scope=external, client PUT SetScore from Story runs only), and this question's own framing says the cutover mechanics need a product/release call only when validator-reported scoring is actually scheduled. Resolution: re-raise this as a constraint/question on the validator-reported-scores feature brief when that work is planned; the options to weigh then are (a) flip scope to internal + lock SetScore via User Auth Restrictions behind a client release that removes submit_pending, vs (b) a transition window where client and validator writes coexist (safe under behavior=maximum, since the server keeps the max)._

## References
_None._

## Child pages
- [Implementation plan — Leaderboards — Daily, Weekly, Monthly (Global)](implementation-plan:mq8ja3dj-001i-rpjbng)
- [Testing plan — Leaderboards — Daily, Weekly, Monthly (Global)](testing-plan:mq8ja3dj-001j-ghgqgx)
- [Spec — Leaderboards — Daily, Weekly, Monthly (Global)](feature-spec:mq8ja3dj-001k-urfpez)

## Commits
- `14b4e76` feat(leaderboards): daily/weekly/monthly global boards — Snapser snap config + client
