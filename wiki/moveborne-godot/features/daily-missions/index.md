# Feature: Daily Missions

**Status:** draft

## Summary
A rotating set of daily tasks — *play 3 matches, win 2, use a power-up* — refreshed every 24h, each with a claimable currency reward, with one always-present **anchor** mission. Distinct from the single curated Challenge of the Day.

**Snap mapping:** each mission is a recurring daily **Quest** (one task, one goal, one currency reward); **Remote Config** carries the display catalog and the day's active set; **Inventory** holds the currency. All built-in — no BYOSnap.

**Rotation (Snapser-aligned):** quest cron is a *reset cadence*, not an active-day filter, so daily variety comes from the client selecting today's subset from a **static weekday→missions map in Remote Config** (pool auto-assign off + AssignQuest; anchor auto-assigned). Launch = anchor + 3 rotating from a pool of 6, global UTC reset. Scheduler/Events-curated sets and true per-player randomization (the BYOSnap gap) are later upgrades.

**Authority:** match win/play goals become validator-fed statistic goals to stay cheat-resistant; counter goals are a bounded daily mint at launch.

## Components affected
- Mission quest pool — N recurring daily Quests, each one task + goal + currency reward, tagged daily_mission
- Anchor mission — one always-auto-assigned recurring daily Quest, tagged anchor, never rotated out
- Remote Config mission catalog — per-quest display metadata (title, icon, description, reward preview)
- Validator statistics feed (hardening) — win/play goals read validator-written statistics instead of client counters
- Client daily-missions screen — list active missions, show progress, claim before reset
- Home-screen Daily sigil (floating entry point) — own CanvasLayer over the shell on Home/Story, an occult-seal button carrying a reset countdown and a claimable-count badge; hidden during a match and when the feature flag is off
- Daily Missions panel (modal overlay) — avatar-picker-style CanvasLayer card: header countdown + claim-before-reset warning, pinned anchor mission, per-mission cards (icon/title/desc/progress/reward), and a Claim All footer
- Reward-claim feedback — currency-icon fly from the card into the persistent top currency bar, then GameState.merge_currencies + currencies_changed re-render (no new wallet UI)
- Rotation (launch) — static weekday→mission-names map in the Remote Config daily_missions block; the client selects today's subset by UTC weekday and AssignQuest's it (pool auto-assign off; anchor auto-assigned). Quest cron is daily reset only, not an active-day filter. Scheduler/Events flipping the active key, then per-player randomization in the BYOSnap, are later upgrades.

## Design constraints
1. Recurring-quest rewards must be claimed before the next daily refresh or they are lost (Quests snap behavior) — the client must surface a claim-before-midnight prompt.
2. Goals that mint meaningful rewards should be statistic goals fed by the validator (win/play counts), not client-written counter goals — the weak-link rule. Low-value missions may use counter goals at launch (bounded daily mint).
3. Launch rewards are currency only — coins, souls, gems provisioned; no Inventory catalog items yet.
4. True randomized per-player rotation, anti-repeat, and weighting are NOT built-in — that is the documented rotation gap and belongs to the meta-game BYOSnap (Tier 3).
5. The refresh boundary is global UTC midnight (server-side cron); per-player local midnight needs custom logic.
6. Entry point must NOT add a sixth bottom-nav tab — the shell already carries five (Collection / Leaderboard / Home / Guilds / Settings), tight at 360 px; surface via the Home screen's open space plus a badge instead.
7. Reward feedback reuses the existing currency bar (currency_bar.gd + GameState.merge_currencies / currencies_changed); the panel is a modal over the shell (avatar-picker pattern), not a routed screen or a new nav destination.
8. Badge restraint: a claimable-count chip only when rewards are collectable, a soft dot when missions are merely active, nothing when the day is fully claimed; escalate (amber timer + pulse) only inside the final hour before reset.

## Open questions
_None._

## Resolved questions
1. **Launch rotation tier: Tier 1 fixed weekly cron-stagger (recommended, fully built-in) or Tier 2 Remote-Config-driven set?** — _Launch on the Remote-Config-driven daily set — NOT a weekday cron-stagger. Snapser quest cron is a reset/refresh cadence, not an active-day filter (docs: cron 'used to start/reset the recurring quest'; a recurring quest is active continuously from its start tick to the next), so a weekday cron cannot make a mission appear only on certain days. Correct built-in approach: every pool mission is a daily-reset recurring quest (cron 0 0 * * *) with auto-assign OFF; the anchor is auto-assign ON; a STATIC weekday->mission-names map (+ display catalog) lives in the Remote Config daily_missions block; on app open the client computes today's UTC weekday and AssignQuest's that day's subset (+ anchor). Real day-to-day rotation, built-ins only (Quests + Remote Config, both live), no Scheduler write and no BYOSnap. Minimal fallback = a fixed daily set. Later upgrades: Scheduler/Events flipping the active key for non-weekday cadences; per-player randomization in the BYOSnap._
2. **Refresh boundary: global UTC midnight (recommended, built-in) or per-player local midnight (needs custom logic)?** — _Global UTC midnight (cron 0 0 * * *). Snapser cron is server-side and global with no per-user timezone, so per-player local midnight is not expressible in built-ins (would need the BYOSnap). Keep Daily Missions, Daily Login Bonus, and Challenge of the Day on the same boundary. The client shows the exact countdown from each quest's resetsAt field (returned by GetActiveQuests/AssignQuest) rather than recomputing midnight._
3. **Pool size, the exact mission list, and per-mission reward values?** — _Pool of 6 + 1 anchor, currency-only (coins; gems reserved for the login-bonus capstone/premium so the daily loop doesn't dilute them). Single-task quests. At launch every goal is a COUNTER goal (client-incremented via IncrementTaskProgress, bounded daily mint); the match-derived ones graduate to Statistic goals once the Statistics snap + validator stat-writes land. Anchor (auto-assign, daily): Daily Dozen — Play 3 matches — 100 coins. Pool (auto-assign off, daily): On a Roll — Win 2 matches — 150; Marathon — Play 5 matches — 150; High Roller — Score 5,000 in one match — 120; Chain Reaction — Make a 5-tile merge — 120; Power Trip — Use 2 power-ups — 80; Merge Master — Merge 50 tiles in a day — 100. Values are tunable via the Remote Config catalog (~460 coins/day if all four daily are cleared)._
4. **How many missions visible per day — anchor + how many rotating (target 4–8 total)?** — _Four visible per day: the anchor + 3 rotating drawn from the pool of 6 (a clean 2-day cycle, varied via the weekday map). Four is within the 4-8 target, reachable in a normal session, and keeps the Claim-All payoff legible. The static weekday map names the 3 pool missions for each UTC weekday._
5. **Client surfacing / entry point: a floating 'Daily' sigil on the Home screen (reset countdown + claimable badge) opening a modal panel — recommended — versus a sixth bottom-nav tab versus a chip in the top currency bar; and should the panel auto-open on launch, or only badge unless rewards are at risk of expiring?** — _Ratified 2026-06-17: floating Home 'Daily' sigil + claimable badge opening a modal panel (no sixth nav tab, no currency-bar chip); the panel auto-surfaces on open only when rewards are at risk of expiring (first open of the period or <1h to reset), otherwise badge-only._

## References
_None._

## Child pages
- [Implementation plan — Daily Missions](implementation-plan:mq9xf8xd-008c-jpg7kq)
- [Testing plan — Daily Missions](testing-plan:mq9xf8xe-008d-lwizqu)
- [Spec — Daily Missions](feature-spec:mq9xf8xe-008e-5xkugp)

## Commits
_None._
