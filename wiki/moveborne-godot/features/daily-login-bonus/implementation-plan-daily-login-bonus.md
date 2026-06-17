# Implementation plan — Daily Login Bonus

**Status:** draft

## Steps
- [ ] Architecture (2026-06-17) — recommended sequencing: build this AFTER Daily Missions Tier 1 so it reuses the shared Quests client built there. Of the two daily features this is the only one needing new backend infrastructure (the Trackables snap), so it is the heavier lift. Counter-view: it is the lower-friction retention hook (open the app, no gameplay required); if product wants it first, the sole extra prerequisite is the Trackables snapend add below.
- [ ] PREREQUISITE (snapend): the Trackables snap is NOT provisioned on the dev snapend — c4n1awfs currently runs auth, byosnap-metagame, byosnap-validator, inventory, leaderboards, profiles, quests, remote-config, storage. Add `trackables` via a snapend update before the login_calendar XP ladder can be configured in its Settings tool; the escalating calendar does not exist without it. (Quests, Remote Config, and the coins/souls/gems currencies are already live.)
- [ ] Inventory: confirm the coins / souls / gems currencies exist (already provisioned); no catalog items needed for launch.
- [ ] Trackables: create the login_calendar XP ladder — one level per calendar day, each level one XP wide, per-level currency reward, auto-reset on max to loop the cycle.
- [ ] Quests Settings: create the daily_login recurring quest — daily cron 0 0 * * * (UTC), auto-assign on, one counter task open_app with goal 1, reward = +1 trackable login_calendar.
- [ ] Remote Config (App Config): add the daily_login block — enabled flag, cycle_length_days, reset_on_miss=false, and the per-day display calendar table.
- [ ] Confirm in the Settings tools whether Trackables level rewards auto-grant or require a claim; design the client so a single 'Claim today's bonus' covers both the quest claim and any ladder claim.
- [ ] PREREQUISITE (client): neither a Quests client nor a Trackables client exists in game/net/ yet (remote_config_client, inventory_client, leaderboards_client, profile_client, story_progress_client do). Build quests_client.gd (active_quests, task increment, claim_rewards — shared with Daily Missions) and trackables_client.gd (read level/progress), following the static-helpers + coroutine pattern. The daily_login display block rides the existing app-config document via remote_config_client (add a key alongside story_catalog).
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
