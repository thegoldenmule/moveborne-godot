# Testing plan — Daily Login Bonus

**Status:** ready

## Planned
_None._

## Passed
- Fresh user: open app, claim — assert wallet +day-1 amount and login_calendar level = 1.
- Same user, next daily period: claim — assert wallet +day-2 amount and level = 2 (escalation works).
- Skip a day, then claim — assert progress paused, not reset: the level advances from where it left off (pause-and-continue).
- Reach the final day and claim once more — assert auto-reset loops the ladder back to day 1.
- Same-day double-claim attempt — assert the recurring quest blocks a second claim within the same daily period.
- Editor — load/defaults (verify_daily_login_service.gd): an absent file loads a disabled default (enabled=false, version=1, empty calendar); reload leaves the service not-dirty.
- Editor — calendar CRUD: add_day() appends the next contiguous day; set_day_field writes currency + amount; remove_day() renumbers so days stay 1..N contiguous.
- Editor — validate() negative + positive: flags an invalid currency (not in coins/souls/gems), amount<=0, a duplicate or non-contiguous day, and a day > cycle_length; a clean 7-day calendar yields no hard errors.
- Editor — serialize() round-trip: canonical output is byte-identical across reload (enabled, version, cycle_length_days, reset_on_miss, calendar day-sorted, trailing newline); reload(serialize())==serialize().
- Editor — save_to(): a dirty save bumps version and writes the file; a forced write-failure rolls the version bump back (no double-bump on retry); an invalid block is blocked at the validate stage before any write.
- Editor — provisioning_readout(): emits one login_calendar ladder line per calendar day (level/min_xp/reward) plus the daily_login quest spec, so the operator can paste it into the Snapser console (mirrors Daily Missions' canonical-id readout).
- Model (test_daily_login_model.gd) — day_for_level wraps on cycle_length (level 8 at cycle 7 → day 1); calendar_entry returns a safe fallback for an unknown day; format_reward renders "+50 coins".
- RC extraction — remote_config_client.extract_daily_login returns the daily_login block from an app-config document and {} when the key is absent, without disturbing extract_catalog / extract_daily_missions on the same document.
- Manifest — verify_app_config_manifest.gd passes with the new daily_login entry present (key/file/version_field set, daily_login.json exists, no duplicate key); appconfig.ts emit includes the daily_login key.
- Runtime (structural, headless) — the login-bonus panel, given a daily_login block + a login_calendar level + the daily_login quest, builds the calendar strip with the current day highlighted and surfaces a single Claim only when the quest is claimable.

## Failed
_None._

## References
_None._

## Child pages
_None._
