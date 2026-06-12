# Feature: Daily Login Bonus

**Status:** draft

## Summary
Reward the player for simply opening the game each day, on an **escalating day-1 → day-N calendar** — the cheapest retention lever on the meta-game roadmap (see Design → Daily Login Bonus).

**Snap mapping (all built-in, no BYOSnap code):** a recurring daily **Quest** is the once-per-day *gate*; a **Trackables XP ladder** is the *escalation curve + reward table*; **Inventory** holds the granted currency; **Remote Config** carries the display calendar and tuning knobs. The escalating calendar — the documented gap ("not built in") — is *composed* from the ladder rather than written as custom logic.

**Authority:** the gate is a client-incremented counter, so the worst case is one day's bonus — a *bounded daily mint*, acceptable at launch under the Design page's Authority Model. Harden to a trusted increment later.

## Components affected
- daily_login gate quest — recurring daily Quest, one counter task (goal = 1), reward grants +1 to the calendar ladder
- login_calendar Trackables XP ladder — one level per calendar day, each level grants that day's currency; auto-resets to loop the cycle
- Remote Config block daily_login — enable flag, cycle length, per-day display table, reward tuning
- Client reward-screen + calendar strip — assign, increment, claim, read new level, render today + upcoming days
- Trusted-increment hook (deferred) — move the once-per-day increment from client to validator/metagame for hardening

## Design constraints
1. Quest rewards are claimed explicitly (ClaimRewardsForQuest); the Quests snap has no silent auto-grant — the claim IS the reward-screen tap.
2. The gate's counter goal is client-incremented at launch; blast radius is one day's bonus (bounded daily mint), acceptable per the Authority Model — harden to a trusted increment later.
3. Launch rewards are currency only — coins, souls, gems are provisioned; no Inventory catalog items exist yet.
4. Calendar advances by claims, not by consecutive calendar days: a missed day pauses progress, it does not reset. Punishing reset-on-miss is the separate Weekly Login Streak feature and needs custom logic.
5. Boundary is global UTC midnight (cron is server-side and global); per-player local midnight is not built-in.
6. Trackables level-reward grant-vs-claim semantics must be confirmed in the Settings tool so the client can surface a single 'Claim today's bonus' action.

## Open questions
1. **Calendar length and reward curve: 7-day or 28-day cycle, and the exact per-day currency amounts?**
2. **On a missed day, pause-and-continue (recommended; fully built-in) or reset to day 1 (needs custom logic)?**
3. **Which currencies fund the bonus — coins for staple days with a gems capstone on the final day?**

## Resolved questions
_None._

## References
_None._

## Child pages
- [Implementation plan — Daily Login Bonus](implementation-plan:mq9xf7gd-0084-1du6pg)
- [Testing plan — Daily Login Bonus](testing-plan:mq9xf7gd-0085-v1nsqi)
- [Spec — Daily Login Bonus](feature-spec:mq9xf7gd-0086-uo1jpm)

## Commits
_None._
