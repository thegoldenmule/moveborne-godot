# Implementation plan — Daily Missions

**Status:** draft

## Steps
- [ ] Inventory: confirm coins / souls / gems currencies; currency-only rewards at launch.
- [ ] Quests Settings: define the mission pool — each mission a recurring daily quest, one task, one goal, one currency reward, tagged daily_mission.
- [ ] Create the anchor mission: recurring daily, auto-assign on, tagged anchor, broad goal (e.g. play 3 matches).
- [ ] Tier-1 rotation: set each pool mission's cron to its weekday(s) so a deterministic subset is active per day; auto-assign on.
- [ ] For win/play goals, point them at validator-written statistics (matches_played, matches_won); coordinate with the validator score/stat-submission work (hardening brief). Until that lands, use counter goals as a bounded-mint placeholder.
- [ ] Remote Config: add the daily_missions block — enabled flag and the per-mission display catalog (title, icon, desc, reward preview).
- [ ] Client: list active missions by tag, render from the Remote Config catalog, show progress, claim each before midnight; surface a claim-before-reset prompt.
- [ ] Tier 2 (follow-on): flip pool auto-assign off, add daily_missions.active to Remote Config, drive it via Scheduler/Events or LiveOps; client assigns the named set.
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
