# Feature: Daily Missions

**Status:** draft

## Summary
A rotating set of 4–8 small daily tasks — *play 3 matches, win 4, use a power-up* — refreshed every 24h, each with a claimable reward, with one always-present **anchor** mission. Distinct from the single curated Challenge of the Day.

**Snap mapping:** each mission is a recurring daily **Quest** (one task, one goal, one currency reward); **Remote Config** carries the mission display catalog and, in the rotation tier, the day's active set; **Scheduler/Events** or the meta-game BYOSnap drive rotation when it graduates beyond a fixed weekly schedule.

**Two tiers ship the value incrementally:** Tier 1 is pure built-in config (anchor + a weekday cron-staggered pool, deterministic, no custom code) and ships now; Tier 2 adds Remote-Config-driven set selection; true randomized per-player rotation is the documented BYOSnap gap, deferred. **Authority:** win/play goals should become validator-fed statistic goals to stay cheat-resistant; counter goals are a bounded daily mint at launch.

## Components affected
- Mission quest pool — N recurring daily Quests, each one task + goal + currency reward, tagged daily_mission
- Anchor mission — one always-auto-assigned recurring daily Quest, tagged anchor, never rotated out
- Tier-1 rotation — weekday-staggered crons so a deterministic subset is active each day
- Tier-2 rotation — Remote Config daily_missions.active names the day's set; Scheduler/Events or LiveOps flips it
- Remote Config mission catalog — per-quest display metadata (title, icon, description, reward preview)
- Validator statistics feed (hardening) — win/play goals read validator-written statistics instead of client counters
- Client daily-missions screen — list active missions, show progress, claim before reset

## Design constraints
1. Recurring-quest rewards must be claimed before the next daily refresh or they are lost (Quests snap behavior) — the client must surface a claim-before-midnight prompt.
2. Goals that mint meaningful rewards should be statistic goals fed by the validator (win/play counts), not client-written counter goals — the weak-link rule. Low-value missions may use counter goals at launch (bounded daily mint).
3. Launch rewards are currency only — coins, souls, gems provisioned; no Inventory catalog items yet.
4. True randomized per-player rotation, anti-repeat, and weighting are NOT built-in — that is the documented rotation gap and belongs to the meta-game BYOSnap (Tier 3).
5. The refresh boundary is global UTC midnight (server-side cron); per-player local midnight needs custom logic.

## Open questions
1. **Launch rotation tier: Tier 1 fixed weekly cron-stagger (recommended, fully built-in) or Tier 2 Remote-Config-driven set?**
2. **Refresh boundary: global UTC midnight (recommended, built-in) or per-player local midnight (needs custom logic)?**
3. **Pool size, the exact mission list, and per-mission reward values?**
4. **How many missions visible per day — anchor + how many rotating (target 4–8 total)?**

## Resolved questions
_None._

## References
_None._

## Child pages
- [Implementation plan — Daily Missions](implementation-plan:mq9xf8xd-008c-jpg7kq)
- [Testing plan — Daily Missions](testing-plan:mq9xf8xe-008d-lwizqu)
- [Spec — Daily Missions](feature-spec:mq9xf8xe-008e-5xkugp)

## Commits
_None._
