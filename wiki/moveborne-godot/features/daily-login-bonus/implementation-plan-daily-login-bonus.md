# Implementation plan — Daily Login Bonus

**Status:** draft

## Steps
- [ ] Inventory: confirm the coins / souls / gems currencies exist (already provisioned); no catalog items needed for launch.
- [ ] Trackables: create the login_calendar XP ladder — one level per calendar day, each level one XP wide, per-level currency reward, auto-reset on max to loop the cycle.
- [ ] Quests Settings: create the daily_login recurring quest — daily cron 0 0 * * * (UTC), auto-assign on, one counter task open_app with goal 1, reward = +1 trackable login_calendar.
- [ ] Remote Config (App Config): add the daily_login block — enabled flag, cycle_length_days, reset_on_miss=false, and the per-day display calendar table.
- [ ] Confirm in the Settings tools whether Trackables level rewards auto-grant or require a claim; design the client so a single 'Claim today's bonus' covers both the quest claim and any ladder claim.
- [ ] Client: on app open, ensure daily_login is assigned, PUT increment open_app, show the reward screen, POST claim_rewards, GET the trackable level, render the calendar strip from Remote Config.
- [ ] Verify end-to-end on the live snapend with a test user: open → claim → assert wallet credited and level advanced; roll the clock a day and assert the next tier grants.
- [ ] Deferred hardening: move the open_app increment to a trusted writer and lock IncrementUserCurrency (see the Server-authoritative hardening brief) before any public release.

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
