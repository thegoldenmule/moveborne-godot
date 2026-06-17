# Implementation plan — Daily Missions

**Status:** draft

## Steps
- [ ] Architecture (2026-06-17) — recommended to build BEFORE Daily Login Bonus: Tier 1 ships on the dev snapend (c4n1awfs) as-is — quests, remote-config, and the coins/souls/gems currencies are all already provisioned; no new snap is required (Daily Login Bonus must first add the Trackables snap). Tier 1 also exercises the freshly-shipped story loop (play/win goals). Both features share the Quests client built here.
- [ ] PREREQUISITE (client): no Quests client exists in game/net/ yet — build quests_client.gd (list active_quests by tag, increment task, claim_rewards) following the existing *_client.gd static-helpers + coroutine pattern; shared with Daily Login Bonus. The Remote Config display catalog rides the existing app-config document via remote_config_client (add a daily_missions key alongside story_catalog).
- [ ] Inventory: confirm coins / souls / gems currencies; currency-only rewards at launch.
- [ ] Quests Settings: define the mission pool — each mission a recurring daily quest, one task, one goal, one currency reward, tagged daily_mission.
- [ ] Create the anchor mission: recurring daily, auto-assign on, tagged anchor, broad goal (e.g. play 3 matches).
- [ ] Rotation (launch, Snapser-aligned): quest cron is a RESET cadence, not an active-day filter — a weekday cron does not gate daily appearance. Set every pool mission to a daily-reset recurring cron (0 0 * * *) with auto-assign OFF, keep the anchor auto-assign ON, and put a static weekday→mission-names map (+ display catalog) in the Remote Config daily_missions block. On app open the client computes today's UTC weekday, AssignQuest's that day's subset, and shows anchor + subset; the reset countdown reads each quest's resetsAt. Built-ins only (Quests + Remote Config, both live) — no Scheduler write, no BYOSnap. Later upgrades: a Scheduler/Events-flipped active key for non-weekday cadences, then per-player randomization in the meta-game BYOSnap (Tier 3, kept below).
- [ ] For win/play goals, point them at validator-written statistics (matches_played, matches_won); coordinate with the validator score/stat-submission work (hardening brief). Until that lands, use counter goals as a bounded-mint placeholder.
- [ ] Provisioning note for the statistic-goal step: the Statistics snap is also NOT on the snapend, and the validator does not yet emit matches_played / matches_won — statistic goals are blocked on BOTH provisioning the Statistics snap AND the validator stat-write on CompleteMatch (Server-authoritative hardening brief). Launch Tier 1 on client counter goals (bounded daily mint) and graduate to statistic goals when hardening lands.
- [ ] Remote Config: add the daily_missions block — enabled flag and the per-mission display catalog (title, icon, desc, reward preview).
- [ ] Client: list active missions by tag, render from the Remote Config catalog, show progress, claim each before midnight; surface a claim-before-reset prompt.
- [ ] Client UX (sigil): build the floating Home 'Daily' sigil on its own CanvasLayer over the shell (Home/Story surfaces only; hidden during a match and when Remote Config daily_missions.enabled is false) — an occult-seal button in MbStyle.PRIMARY with a reset-countdown label and a claimable badge (precedence: claimable-count chip > soft dot when missions are merely active > nothing). Register it as home.daily via Reg.texture_button. See the spec's UX section.
- [ ] Client UX (panel): build the Daily Missions modal overlay using the existing avatar-picker pattern (CanvasLayer card + dimmed scrim; dismiss on close or tap-outside) — a ScrollContainer with MbScreenScaffold padding; header with the live UTC countdown and a claim-before-reset caption; the anchor pinned at top in a distinct band; per-mission cards (catalog icon/title/desc + progress bar + reward chip) in in-progress / claimable / claimed states; a Claim All footer when two or more are claimable.
- [ ] Client UX (claim feedback, surfacing, automation): on claim_rewards success, fly the reward's currency icon into the matching top-currency-bar slot, then GameState.merge_currencies + the currencies_changed re-render (count-up + pulse) — no new wallet UI — and decrement the sigil badge. Refresh the badge on app open, on return from a match, and after each claim; auto-open the panel only when claimables exist AND (first open of the daily period OR under 1h to reset); show a one-time FTUE coachmark on the sigil's first appearance. Register each claim button as missions.<mission_name> and Claim All as missions.claim_all, and add MbUi flows open_daily_missions and claim_daily.
- [ ] Tier 3 (deferred): per-player randomized rotation, anti-repeat, and weighting in the meta-game BYOSnap.

## Data models & interfaces
_None yet._

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
