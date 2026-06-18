# Implementation plan — Daily Missions

**Status:** ready

## Steps
- [x] Architecture (2026-06-17) — recommended to build BEFORE Daily Login Bonus: Tier 1 ships on the dev snapend (c4n1awfs) as-is — quests, remote-config, and the coins/souls/gems currencies are all already provisioned; no new snap is required (Daily Login Bonus must first add the Trackables snap). Tier 1 also exercises the freshly-shipped story loop (play/win goals). Both features share the Quests client built here.
- [x] PREREQUISITE (client): no Quests client exists in game/net/ yet — build quests_client.gd (list active_quests by tag, increment task, claim_rewards) following the existing *_client.gd static-helpers + coroutine pattern; shared with Daily Login Bonus. The Remote Config display catalog rides the existing app-config document via remote_config_client (add a daily_missions key alongside story_catalog).
- [x] Inventory: confirm coins / souls / gems currencies; currency-only rewards at launch.
- [x] Quests Settings: define the mission pool — each mission a recurring daily quest, one task, one goal, one currency reward, tagged daily_mission.
- [x] Create the anchor mission: recurring daily, auto-assign on, tagged anchor, broad goal (e.g. play 3 matches).
- [x] Rotation (launch, Snapser-aligned): quest cron is a RESET cadence, not an active-day filter — a weekday cron does not gate daily appearance. Set every pool mission to a daily-reset recurring cron (0 0 * * *) with auto-assign OFF, keep the anchor auto-assign ON, and put a static weekday→mission-names map (+ display catalog) in the Remote Config daily_missions block. On app open the client computes today's UTC weekday, AssignQuest's that day's subset, and shows anchor + subset; the reset countdown reads each quest's resetsAt. Built-ins only (Quests + Remote Config, both live) — no Scheduler write, no BYOSnap. Later upgrades: a Scheduler/Events-flipped active key for non-weekday cadences, then per-player randomization in the meta-game BYOSnap (Tier 3, kept below).
- [x] For win/play goals, point them at validator-written statistics (matches_played, matches_won); coordinate with the validator score/stat-submission work (hardening brief). Until that lands, use counter goals as a bounded-mint placeholder.
- [x] Provisioning note for the statistic-goal step: the Statistics snap is also NOT on the snapend, and the validator does not yet emit matches_played / matches_won — statistic goals are blocked on BOTH provisioning the Statistics snap AND the validator stat-write on CompleteMatch (Server-authoritative hardening brief). Launch Tier 1 on client counter goals (bounded daily mint) and graduate to statistic goals when hardening lands.
- [x] Remote Config: add the daily_missions block — enabled flag and the per-mission display catalog (title, icon, desc, reward preview).
- [x] Client: list active missions by tag, render from the Remote Config catalog, show progress, claim each before midnight; surface a claim-before-reset prompt.
- [x] Client UX (sigil): build the floating Home 'Daily' sigil on its own CanvasLayer over the shell (Home/Story surfaces only; hidden during a match and when Remote Config daily_missions.enabled is false) — an occult-seal button in MbStyle.PRIMARY with a reset-countdown label and a claimable badge (precedence: claimable-count chip > soft dot when missions are merely active > nothing). Register it as home.daily via Reg.texture_button. See the spec's UX section.
- [x] Client UX (panel): build the Daily Missions modal overlay using the existing avatar-picker pattern (CanvasLayer card + dimmed scrim; dismiss on close or tap-outside) — a ScrollContainer with MbScreenScaffold padding; header with the live UTC countdown and a claim-before-reset caption; the anchor pinned at top in a distinct band; per-mission cards (catalog icon/title/desc + progress bar + reward chip) in in-progress / claimable / claimed states; a Claim All footer when two or more are claimable.
- [x] Client UX (claim feedback, surfacing, automation): on claim_rewards success, fly the reward's currency icon into the matching top-currency-bar slot, then GameState.merge_currencies + the currencies_changed re-render (count-up + pulse) — no new wallet UI — and decrement the sigil badge. Refresh the badge on app open, on return from a match, and after each claim; auto-open the panel only when claimables exist AND (first open of the daily period OR under 1h to reset); show a one-time FTUE coachmark on the sigil's first appearance. Register each claim button as missions.<mission_name> and Claim All as missions.claim_all, and add MbUi flows open_daily_missions and claim_daily.

## Data models & interfaces
```json
// Remote Config app-config document — the daily_missions block rides ALONGSIDE
// story_catalog (same doc; MbRemoteConfigClient.extract_daily_missions reads it,
// never disturbing extract_catalog). enabled gates the whole feature. anchor is the
// always-auto-assigned mission. by_weekday has STRING UTC-weekday keys "0"(Sun).."6"(Sat),
// each an array of 3 pool mission names (anchor + 3 = 4 visible/day; clean 2-day cycle).
// catalog maps EVERY mission name -> display metadata (client renders from this, never
// hardcodes). Quest goals/targets/rewards live in Snapser Quests Settings (ops), not here;
// reward here is a display preview string only.
{
  "daily_missions": {
    "enabled": true,
    "version": 1,
    "anchor": "mission_anchor_play_3",
    "by_weekday": {
      "0": ["mission_win_2",   "mission_powerup_2", "mission_merge_50"],
      "1": ["mission_play_5",  "mission_combo_5",   "mission_score_5k"],
      "2": ["mission_win_2",   "mission_score_5k",  "mission_combo_5"],
      "3": ["mission_play_5",  "mission_powerup_2", "mission_merge_50"],
      "4": ["mission_win_2",   "mission_combo_5",   "mission_powerup_2"],
      "5": ["mission_play_5",  "mission_score_5k",  "mission_merge_50"],
      "6": ["mission_win_2",   "mission_play_5",    "mission_powerup_2"]
    },
    "catalog": {
      "mission_anchor_play_3": {"title": "Daily Dozen",    "icon": "cards",  "desc": "Play 3 matches",        "reward": "100 coins"},
      "mission_win_2":         {"title": "On a Roll",      "icon": "trophy", "desc": "Win 2 matches",         "reward": "150 coins"},
      "mission_play_5":        {"title": "Marathon",       "icon": "cards",  "desc": "Play 5 matches",        "reward": "150 coins"},
      "mission_score_5k":      {"title": "High Roller",    "icon": "spark",  "desc": "Score 5,000 in a match", "reward": "120 coins"},
      "mission_combo_5":       {"title": "Chain Reaction", "icon": "spark",  "desc": "Make a 5-tile merge",    "reward": "120 coins"},
      "mission_powerup_2":     {"title": "Power Trip",     "icon": "bolt",   "desc": "Use 2 power-ups",       "reward": "80 coins"},
      "mission_merge_50":      {"title": "Merge Master",   "icon": "bolt",   "desc": "Merge 50 tiles today",  "reward": "100 coins"}
    }
  }
}
```

```gdscript
# game/net/quests_client.gd — MbQuestsClient extends Node, _init(auth). Mirrors the
# leaderboards/inventory 3-layer pattern: pure static helpers (unit-testable, no network)
# + child-of-self HTTPRequest coroutines carrying _auth.auth_headers(). Endpoints from
# snapser-docs/swagger/quests.swagger3.json (verbs CONFIRMED against the swagger).

const BASE := MbSnapserAuth.GATEWAY + "/v1/quests"
const TAG_DAILY := "daily_mission"

# --- pure static helpers ---
static func active_quests_url(user_id: String, tags := "") -> String   # GET .../users/{uid}/active_quests?tags=daily_mission
static func assign_url(user_id: String, quest: String) -> String       # POST .../quests/{quest}/assign
static func increment_url(user_id: String, quest: String, task: String) -> String  # PUT  .../tasks/{task}
static func claim_url(user_id: String, quest: String) -> String        # POST .../quests/{quest}/claim_rewards
static func increment_body(delta: int) -> String                       # {"delta": d, "delta64": d}

# parse_active_quests(questsUserQuests) -> Array of normalized quest dicts:
#   { name:String, status:String, resets_at:int (unix s, from resets_at int64 str/num),
#     tags:Array[String],
#     tasks:Array[{ name:String, completed:bool, progress:int, goal:int }]   # prefer *_64 then plain
#     reward:{coins:int, souls:int, gems:int} }  # summed from reward_currencies (count_64 pref)
static func parse_active_quests(data) -> Array

# parse_claim(questsClaimQuestRewardsResponse) -> partial {coins/souls/gems:int} for
# GameState.merge_currencies; prefer currencies_granted_64 (string map) over currencies_granted.
static func parse_claim(data) -> Dictionary

# is_claimable(quest) -> true when a task is completed and status != "claimed".
static func is_claimable(quest: Dictionary) -> bool

# --- coroutines (await) -> {ok, ..., error} ---
func fetch_active_quests(tags := TAG_DAILY) -> Dictionary   # {ok, quests:Array, error}
func assign_quest(quest: String) -> Dictionary             # {ok, error}
func increment_task(quest: String, task: String, delta := 1) -> Dictionary  # {ok, error}
func claim_quest_rewards(quest: String) -> Dictionary      # {ok, granted:{coins,souls,gems}, error}
```

```gdscript
# game/ui/screens/daily_missions_model.gd — MbDailyMissions (pure static, headless-testable).
# All presentation logic that the sigil + panel share, with NO Node/network deps, so a
# tools/verify_daily_missions_model.gd can assert it via CLI.

enum CardState { IN_PROGRESS, CLAIMABLE, CLAIMED }
enum Badge { NONE, DOT, COUNT }

# UTC weekday 0(Sun)..6(Sat) from a unix-seconds clock (injectable for tests).
static func utc_weekday(now_unix: int) -> int

# anchor + by_weekday[str(weekday)] from a daily_missions block -> ordered Array[String]
# (anchor first). Empty when disabled/absent.
static func todays_mission_names(block: Dictionary, weekday: int) -> Array

# A normalized quest (from MbQuestsClient.parse_active_quests) -> CardState.
static func card_state(quest: Dictionary) -> int

# Count of claimable quests; badge_state -> Badge (COUNT when >=1 claimable, DOT when any
# active-but-none-claimable, NONE when fully claimed / empty).
static func claimable_count(quests: Array) -> int
static func badge_state(quests: Array) -> int

# Seconds until the soonest reset (min resets_at - now), clamped at 0. Drives the countdown;
# under 3600 -> the panel/sigil show the amber warning + pulse.
static func seconds_to_reset(quests: Array, now_unix: int) -> int
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
