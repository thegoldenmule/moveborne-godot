# Implementation plan — Daily Login Bonus

**Status:** ready

## Steps
- [x] Architecture (2026-06-17) — recommended sequencing: build this AFTER Daily Missions Tier 1 so it reuses the shared Quests client built there. Of the two daily features this is the only one needing new backend infrastructure (the Trackables snap), so it is the heavier lift. Counter-view: it is the lower-friction retention hook (open the app, no gameplay required); if product wants it first, the sole extra prerequisite is the Trackables snapend add below.
- [x] PREREQUISITE (snapend): the Trackables snap is NOT provisioned on the dev snapend — c4n1awfs currently runs auth, byosnap-metagame, byosnap-validator, inventory, leaderboards, profiles, quests, remote-config, storage. Add `trackables` via a snapend update before the login_calendar XP ladder can be configured in its Settings tool; the escalating calendar does not exist without it. (Quests, Remote Config, and the coins/souls/gems currencies are already live.)
- [x] Inventory: confirm the coins / souls / gems currencies exist (already provisioned); no catalog items needed for launch.
- [x] Trackables: create the login_calendar XP ladder — one level per calendar day, each level one XP wide, per-level currency reward, auto-reset on max to loop the cycle.
- [x] Quests Settings: create the daily_login recurring quest — daily cron 0 0 * * * (UTC), auto-assign on, one counter task open_app with goal 1, reward = +1 trackable login_calendar.
- [x] Remote Config (App Config): add the daily_login block — enabled flag, cycle_length_days, reset_on_miss=false, and the per-day display calendar table.
- [x] Confirm in the Settings tools whether Trackables level rewards auto-grant or require a claim; design the client so a single 'Claim today's bonus' covers both the quest claim and any ladder claim.
- [x] Client: on app open, ensure daily_login is assigned, PUT increment open_app, show the reward screen, POST claim_rewards, GET the trackable level, render the calendar strip from Remote Config.
- [x] Verify end-to-end on the live snapend with a test user: open → claim → assert wallet credited and level advanced; roll the clock a day and assert the next tier grants.
- [x] PREREQUISITE (client) — UPDATED 2026-06-18: the shared MbQuestsClient (game/net/quests_client.gd) NOW EXISTS (built for Daily Missions: active_quests / assign / increment / claim_rewards) and is reused unchanged. Still to build: trackables_client.gd (read the login_calendar level/progress) following the same static-helpers + coroutine pattern — inert until Trackables is provisioned. The daily_login display block rides the existing app-config document via remote_config_client (a new sibling key alongside story_catalog + daily_missions).
- [x] CONTENT: create validator/content/daily_login.json — {enabled, version, cycle_length_days, reset_on_miss, calendar:[{day,currency,amount}]} — and register it with a one-line append to validator/content/app_config.manifest.json ({key:"daily_login", file:"daily_login.json", version_field:"version", label:"Daily Login Bonus"}). No tool changes needed: appconfig.ts emit/verify and the Remote Config editor aggregate it automatically from the manifest.
- [x] EDITOR (centerpiece): build addons/daily_login_editor — plugin.gd (extends EditorToolPlugin) + plugin.cfg + DailyLoginService(ToolService) + dock.gd — mirroring daily_missions_editor. The service owns calendar-day CRUD, currency/amount per day, enabled/cycle/reset toggles, validate() (currency in {coins,souls,gems}; amount>0; days 1..cycle_length, contiguous, no dupes), a canonical serialize(), and a version-bump save() via ContentStore.bump_then + save_all. The dock is a thin view (day list + per-day form + enabled/cycle/reset + copyable provisioning readout), rebuilding on the service's `changed` signal. Enable the plugin in project.godot.
- [x] MODEL: ui/screens/daily_login_model.gd (MbDailyLogin) — pure, headless-testable helpers mirroring MbDailyMissions: is_enabled, the current calendar day from the login_calendar trackable level (wraps on cycle_length), today/upcoming strip data, claimed-vs-claimable, format_reward. ONE source of truth for the calendar shape, shared by the editor's validate()/preview, the runtime panel, and the verifier.
- [x] RC CLIENT: add DAILY_LOGIN_KEY := "daily_login" + a static extract_daily_login(config) to remote_config_client.gd (sibling to extract_daily_missions / extract_catalog), so the runtime reads the display block from the same app-config document without disturbing the catalog or daily-missions reads.
- [x] RUNTIME claim screen: a modal login-bonus panel (calendar strip — today highlighted, upcoming previewed) + a LoginBonus controller owned by AppShell, mirroring daily_sigil. On the Home surface with a session it fetches the daily_login block (remote_config_client), the login_calendar level (trackables_client), and the daily_login quest (quests_client); surfaces once per daily period; Claim → claim the quest → reward-reveal ceremony (reused from daily_sigil) + GameState.add_currencies → re-read the level. Register controls via MbUiReg.
- [x] VERIFICATION: tools/verify_daily_login_service.gd (mirror verify_daily_missions_service.gd) — load/defaults, day CRUD, validate() positive/negative, serialize() round-trip stability, save_to() version-bump + forced-write-failure rollback; tests/test_daily_login_model.gd (McpTestSuite) for the model; and re-run tools/verify_app_config_manifest.gd so the new manifest entry is structurally checked. Live E2E (assign→claim→wallet credited→level advanced) stays gated on the Trackables snapend add.

## Data models & interfaces
```json
// validator/content/daily_login.json — the Remote Config DISPLAY block authored by daily_login_editor
// (the authoritative grant lives in the Trackables login_calendar ladder; this mirrors it for the strip + tuning)
{
  "enabled": true,
  "version": 1,
  "cycle_length_days": 7,
  "reset_on_miss": false,
  "calendar": [
    { "day": 1, "currency": "coins", "amount": 50 },
    { "day": 2, "currency": "coins", "amount": 75 },
    { "day": 3, "currency": "coins", "amount": 100 },
    { "day": 4, "currency": "coins", "amount": 150 },
    { "day": 5, "currency": "coins", "amount": 200 },
    { "day": 6, "currency": "coins", "amount": 300 },
    { "day": 7, "currency": "gems",  "amount": 20 }
  ]
}

// validator/content/app_config.manifest.json — one-line append (auto-aggregated by appconfig.ts + the RC editor)
{ "key": "daily_login", "file": "daily_login.json", "version_field": "version", "label": "Daily Login Bonus" }
```

```gdscript
# addons/daily_login_editor/daily_login_service.gd  (extends ToolService) — mirrors DailyMissionsService
class_name DailyLoginService
var block: Dictionary  # {enabled, version, cycle_length_days, reset_on_miss, calendar:[{day,currency,amount}]}
func reload_from(path: String) -> void
func days() -> Array                          # sorted day ints [1..N]
func get_day(day: int) -> Dictionary          # {currency, amount} with safe fallbacks
func add_day() -> Dictionary                  # append next contiguous day; returns {day}
func remove_day(day: int) -> void             # drop + renumber so days stay contiguous
func set_day_field(day: int, key: String, value) -> void   # key in {currency, amount}
func set_enabled(on: bool) -> void
func set_cycle_length(n: int) -> void
func set_reset_on_miss(on: bool) -> void
func validate() -> Array                      # currency in {coins,souls,gems}; amount>0; days 1..cycle, contiguous, unique
func serialize() -> String                    # canonical: enabled,version,cycle_length_days,reset_on_miss,calendar(day-sorted) + \n
func save_to(path: String, scan := true) -> Dictionary   # ContentStore.bump_then("version") + save_all
func provisioning_readout() -> String         # login_calendar ladder levels + the daily_login quest (clipboard)

# ui/screens/daily_login_model.gd  (MbDailyLogin — pure static, mirrors MbDailyMissions)
const CURRENCIES := ["coins", "souls", "gems"]
static func is_enabled(block: Dictionary) -> bool
static func cycle_length(block: Dictionary) -> int
static func day_for_level(level: int, cycle: int) -> int   # 1-based; wraps on cycle (auto_reset on_max)
static func calendar_entry(block: Dictionary, day: int) -> Dictionary   # {day, currency, amount} w/ fallback
static func format_reward(entry: Dictionary) -> String     # e.g. "+50 coins"
```

```text
# provisioning_readout() output — copied to the clipboard, pasted into the Snapser console
# (Trackables + Quests have NO write API, mirroring Daily Missions' canonical-id readout)

# Trackables ladder — login_calendar  (kind: xp, auto_assign_level, auto_reset: on_max)
  level 1  min_xp 1  reward coins 50
  level 2  min_xp 2  reward coins 75
  level 3  min_xp 3  reward coins 100
  level 4  min_xp 4  reward coins 150
  level 5  min_xp 5  reward coins 200
  level 6  min_xp 6  reward coins 300
  level 7  min_xp 7  reward gems  20

# Quest — daily_login  (recurring, daily cron, auto_assign)
  cron "0 0 * * *"  tags [daily_login]
  task open_app  goal 1 (counter)
  reward → +1 trackable login_calendar   (NOT currency directly — the ladder grants the day's reward)
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
