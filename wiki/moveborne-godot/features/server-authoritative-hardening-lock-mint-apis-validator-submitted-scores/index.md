# Feature: Server-authoritative hardening — lock mint APIs + validator-submitted scores

**Status:** draft

## Summary
Make the three already-live Snapser systems — the **validator**, the **Inventory currency wallets**, and the **Leaderboards** — trustworthy by closing the client-authoritative gap. Snapser defaults to client-authoritative: with only a session token, a client can call the mint and score-write APIs on its own account. Two moves, mostly configuration: lock the mint APIs to server-only callers via the Auth snap's **User Auth Restrictions**, and route leaderboard scores and match statistics through the gameplay **validator**, which already sits in the match path (the CompleteMatch credit path proven in 94f3a0f / b500fdb).

**Deferred by decision (2026-06-11):** the leaderboard/competitive half needs matchmaking, which is PvP, which is saved for later — so the score-submission work is scheduled alongside that. Captured here so it is not lost. The **mint lock is config-only** and worth doing before any real economy exposure, independent of PvP. Full rationale: Design page → Authority Model — Client vs Server.

## Components affected
- Lock mint APIs via Auth User Auth Restrictions — IncrementUserCurrency, GrantItemsToUser, GrantDropTable, SetScore, IncrementUserStatistic — leaving Api-Key and Internal (BYOSnap) callers only
- Validator submits leaderboard scores on match completion (rides the existing CompleteMatch hook)
- Validator writes match XP and win/play statistics (feeds quests, battle pass, boards)
- Keep Infinite (offline) results off all shared boards and statistics

## Design constraints
1. The mint lock is configuration, not code — zero added server load.
2. Score and statistic writes ride the existing CompleteMatch path proven in 94f3a0f / b500fdb — near-zero marginal cost.
3. Conditioned exchanges (purchases, container opens) stay client-callable; only unconditioned mints are locked.
4. Blocked-by: leaderboard/competitive surfaces need matchmaking (PvP), which is deferred — so the score-submission half is scheduled with that work.

## Open questions
1. **Turn the mint lock on before exposing any real economy or competitive surface — confirm the trigger point.**

## Resolved questions
_None._

## References
_None._

## Child pages
- [Implementation plan — Server-authoritative hardening — lock mint APIs + validator-submitted scores](implementation-plan:mq9xfhki-008k-36hi2b)
- [Testing plan — Server-authoritative hardening — lock mint APIs + validator-submitted scores](testing-plan:mq9xfhki-008l-6m9iq5)
- [Spec — Server-authoritative hardening — lock mint APIs + validator-submitted scores](feature-spec:mq9xfhki-008m-11y4hq)

## Commits
_None._
