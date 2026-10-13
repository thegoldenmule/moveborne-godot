# Spec — Daily Login Bonus

**Status:** sealed

## Overview
**Reward the player for opening the game each day, on an escalating day-1 → day-N calendar** — built entirely from built-in Snapser snaps, no BYOSnap code. A recurring daily **Quest** is the once-per-day gate; a **Trackables XP ladder** is the escalation curve and reward table; **Inventory** holds the granted currency; **Remote Config** carries the display calendar and tuning. The clever bit: the quest's daily cron is the rate-limiter (it completes at most once per day) and its reward is +1 progress on the ladder, so each day advances exactly one calendar step and grants that step's reward.

## Design
Notation: the JSON below illustrates the documented Quests, Trackables, and Remote Config capabilities, not the literal API field names. Exact field names come from each snap's Settings tool and swagger at implementation time.

## Snapser mapping

Four built-in snaps compose the feature; none of it needs the meta-game BYOSnap. Quests provides the once-per-day gate and the explicit claim. Trackables provides the escalating reward table as an XP ladder. Inventory holds the wallet the rewards land in. Remote Config carries the display calendar and tuning so reward values and the visual strip can change without a client build.

## The once-per-day gate (Quests)

Define one recurring daily quest. It auto-assigns to every player, refreshes at midnight UTC on a daily cron, and carries a single task with a counter goal of 1, incremented once when the player opens the app that day. Completing the task makes the quest claimable. The quest's reward is not currency directly; it is plus-one progress on the login_calendar trackable. Because the quest can complete only once per daily period, it is the rate-limiter that guarantees at most one calendar advance per day, with no client-side enforcement needed.

```json
{
  "name": "daily_login",
  "description": "Open the game today to advance your login calendar.",
  "active": true,
  "auto_assign": true,
  "recurring": true,
  "cron": "0 0 * * *",
  "tags": ["daily_login", "retention"],
  "audience": "all_users",
  "tasks": [
    {
      "name": "open_app",
      "goal": { "type": "counter", "mode": "absolute", "target": 1 },
      "rewards": [
        { "type": "trackable", "trackable": "login_calendar", "amount": 1 }
      ]
    }
  ]
}
```

## The escalating calendar (Trackables XP ladder)

Model the calendar as an XP ladder named login_calendar with one level per calendar day. Each level is one XP wide, so each plus-one from the daily quest crosses exactly one threshold and assigns the next level. Each level carries that day's reward, coins on staple days and a larger grant such as gems on the capstone day. After the final level the ladder auto-resets to zero and chains back to day one, making it a repeating cycle. Reward values live here as the authoritative grant; Remote Config mirrors them only for display. Amounts shown are placeholders for product tuning, not a committed economy.

```json
{
  "name": "login_calendar",
  "kind": "xp",
  "auto_assign_level": true,
  "auto_reset": "on_max",
  "levels": [
    { "level": 1, "min_xp": 1, "reward": { "currency": "coins", "amount": 50 } },
    { "level": 2, "min_xp": 2, "reward": { "currency": "coins", "amount": 75 } },
    { "level": 3, "min_xp": 3, "reward": { "currency": "coins", "amount": 100 } },
    { "level": 4, "min_xp": 4, "reward": { "currency": "coins", "amount": 150 } },
    { "level": 5, "min_xp": 5, "reward": { "currency": "coins", "amount": 200 } },
    { "level": 6, "min_xp": 6, "reward": { "currency": "coins", "amount": 300 } },
    { "level": 7, "min_xp": 7, "reward": { "currency": "gems",  "amount": 20 } }
  ]
}
```

## Why a quest gates a ladder

Splitting the two responsibilities is what makes the escalating calendar expressible with built-ins. The ladder alone cannot enforce once-per-day; a client could pour progress into it. The quest alone cannot escalate; a single recurring quest has exactly one reward definition. Composed, the quest's daily cron supplies the once-per-day rate limit and the ladder supplies the per-day escalation and reward table. This is the documented composition for the gap that the calendar is not built in.

## Remote Config role

Remote Config carries two things: a feature flag and the display calendar. The display table lets the client render the seven-day strip with today highlighted and upcoming rewards previewed, without hardcoding values, and lets LiveOps retune the preview and toggle the feature without a client build. The authoritative grant remains the ladder; keep the two in sync through the admin tools. Read it from the user-config endpoint so a future per-segment override, for example a richer calendar for a returning-player segment, is possible.

```json
{
  "daily_login": {
    "enabled": true,
    "cycle_length_days": 7,
    "reset_on_miss": false,
    "calendar": [
      { "day": 1, "currency": "coins", "amount": 50 },
      { "day": 2, "currency": "coins", "amount": 75 },
      { "day": 3, "currency": "coins", "amount": 100 },
      { "day": 4, "currency": "coins", "amount": 150 },
      { "day": 5, "currency": "coins", "amount": 200 },
      { "day": 6, "currency": "coins", "amount": 300 },
      { "day": 7, "currency": "gems", "amount": 20 }
    ]
  }
}
```

## Client flow

On app open, the client ensures the daily quest is assigned (auto-assign covers this), increments the open_app task once, then surfaces the reward screen. The player taps Claim, which claims the quest reward; that grants plus-one to the ladder, which assigns the next level and grants that day's currency. The client then re-reads the trackable to learn the new level and renders the calendar strip from the Remote Config display table.

```text
# once per day, on app open
GET  /v1/quests/users/{user_id}/active_quests
PUT  /v1/quests/users/{user_id}/quests/daily_login/tasks/open_app
# reward screen -> player taps Claim
POST /v1/quests/users/{user_id}/quests/daily_login/claim_rewards
# reflect the new state
GET  /v1/trackables/users/{user_id}/login_calendar
GET  /v1/remote-config/user-config/{user_id}
```

## Authority and anti-cheat

The open_app counter is client-incremented at launch, so a determined player can claim a day they did not earn. The blast radius is one day's bonus, a bounded daily mint, which the Authority Model accepts at launch. When hardening lands, move the increment to a trusted writer: the gameplay validator on a verified session start, or the meta-game BYOSnap on a verified login. Because the reward path is currency, also lock IncrementUserCurrency to server-only callers as part of the hardening pass so the ladder grant cannot be replayed directly. See the Server-authoritative hardening brief.

## Out of scope

Reset-on-miss and streak decay are deliberately excluded; this calendar pauses on a gap and resumes, it does not punish. The punishing weekly streak with reset and decay is the separate Weekly Login Streak Bonus feature and needs custom logic in the meta-game BYOSnap. Per-player local midnight is also out of scope; the cron boundary is global UTC.

## Post-Daily-Missions reality (2026-06-18)

This brief was written before Daily Missions shipped; the surfaces it once had to build now exist. The shared MbQuestsClient (assign / increment / claim) is reused unchanged. The app-config manifest (validator/content/app_config.manifest.json) plus the one generic appconfig.ts publisher aggregate every Remote Config content block into a single document, so daily_login.json is added with a one-line manifest append and published by the existing Remote Config editor — no per-feature tooling. The editor_tool_kit framework and the daily_missions_editor tool establish the exact ToolService + dock + ContentStore pattern this feature's editor mirrors. The runtime claim reuses daily_sigil's reward-reveal ceremony and GameState.add_currencies. What is genuinely new here is the authoring tool and the day-1..day-N calendar content it produces.

## Authoring: the Daily Login Bonus editor

A fully-functioning in-editor tool — addons/daily_login_editor — is a first-class part of this feature, built on editor_tool_kit exactly as daily_missions_editor is. A headless-testable DailyLoginService(ToolService) owns the calendar: per-day CRUD, currency/amount per day, the enabled / cycle_length_days / reset_on_miss knobs, a validate() (currency in {coins,souls,gems}; amount>0; days 1..cycle_length, contiguous, unique), a canonical serialize() (stable key order, integer-coerced, trailing newline so repeated saves are byte-identical), and a version-bump save() via ContentStore.bump_then + save_all that writes the single committed validator/content/daily_login.json. A thin dock view renders the day list, a per-day form, the enable/cycle/reset controls, and a copyable provisioning readout, rebuilding on the service's changed signal. The tool only writes the content blob; publishing it to Remote Config is the Remote Config tool's job, and the live ladder + quest are provisioned by pasting the readout into the Snapser console — neither Trackables nor Quests has a write API, the same manual-provisioning seam Daily Missions uses.

```text
# provisioning_readout() — copied to the clipboard, pasted into the Snapser console
# (Trackables + Quests have no write API, mirroring Daily Missions' canonical-id readout)

# Trackables ladder — login_calendar  (kind: xp, auto_assign_level, auto_reset: on_max)
  level 1  min_xp 1  reward coins 50
  level 2  min_xp 2  reward coins 75
  level 3  min_xp 3  reward coins 100
  level 4  min_xp 4  reward coins 150
  level 5  min_xp 5  reward coins 200
  level 6  min_xp 6  reward coins 300
  level 7  min_xp 7  reward gems  20

# Quest — daily_login  (recurring, daily cron 0 0 * * *, auto_assign, tags [daily_login])
  task open_app  goal 1 (counter)
  reward → +1 trackable login_calendar   (the ladder grants the day's currency, not the quest)
```

## As-built backend (2026-06-18) — supersedes the "1 XP / +1" description above

Provisioning the live backend on c4n1awfs surfaced two corrections to the design above. (1) The Snapser Trackables console ENFORCES non-overlapping level ranges, so each calendar day is a 2-XP-wide level (Day1 [0,1], Day2 [2,3], … Day7 [12,13]) rather than 1 XP wide. Overlapping ranges (e.g. [0,1],[1,2]) are rejected by the settings importer with an opaque "trackables: settings import failed". (2) Consequently the daily_login quest grants +2 XP per claim (reward_xp count=2) so each claim crosses exactly one level boundary and advances one calendar day; the day's currency is granted server-side via the level's level_completion_rewards. The runtime therefore positions the calendar by the trackable's current_level.index (which the ladder computes from XP), NOT raw XP.

Provisioning path: snapctl CAN import the trackables xp_settings ladder via the snapend manifest (snapctl snapend apply) as long as ranges are non-overlapping — my initial "console-only" conclusion was wrong; overlapping ranges, not a CLI limitation, were the blocker. The Trackables snap was added with the snapser MCP update_snapend (it auto-provisions the service definition + databases); the daily_login quest and the login_calendar ladder were applied via snapctl. Verified end-to-end on a fresh user: the quest claim grants +2 ladder XP → Day1 completion → +50 coins in the Inventory wallet; driving the ladder through all seven days grants 50/75/100/150/200/300 coins then 20 gems on Day7, and auto_reset_on_complete loops back to Day1. Missed days pause (the ladder XP persists; reset_on_miss=false), consistent with the launch decision.

```json
// LIVE login_calendar XP ladder (Trackables settings) — non-overlapping 2-XP-wide levels
{
  "name": "login_calendar", "scope": "external", "default_xp": "0", "auto_reset_on_complete": true,
  "levels": [
    { "index": 0, "name": "Day1", "start": "0",  "end": "1",  "level_completion_rewards": { "currencies": { "coins": "50"  } } },
    { "index": 1, "name": "Day2", "start": "2",  "end": "3",  "level_completion_rewards": { "currencies": { "coins": "75"  } } },
    { "index": 2, "name": "Day3", "start": "4",  "end": "5",  "level_completion_rewards": { "currencies": { "coins": "100" } } },
    { "index": 3, "name": "Day4", "start": "6",  "end": "7",  "level_completion_rewards": { "currencies": { "coins": "150" } } },
    { "index": 4, "name": "Day5", "start": "8",  "end": "9",  "level_completion_rewards": { "currencies": { "coins": "200" } } },
    { "index": 5, "name": "Day6", "start": "10", "end": "11", "level_completion_rewards": { "currencies": { "coins": "300" } } },
    { "index": 6, "name": "Day7", "start": "12", "end": "13", "level_completion_rewards": { "currencies": { "gems":  "20"  } } }
  ]
}

// daily_login quest — the reward is +2 ladder XP (NOT currency; the ladder grants currency on level completion)
{ "name": "daily_login", "type": "recurring", "cron_expr": "0 0 * * *", "auto_assign": true,
  "tags": ["daily_login"], "reward_xp": [{ "name": "login_calendar", "count": 2 }],
  "tasks": [{ "name": "open_app", "goal": 1 }] }
```

## Decisions
Launch default (recommended, pending ratification): pause-and-continue. The calendar advances only when claimed and never resets on a missed day, keeping the entire feature on built-in snap config. A punishing reset-on-miss would require the meta-game BYOSnap to track consecutive-day state and is split into the Weekly Login Streak Bonus feature. On a missed day, pause-and-continue (recommended; fully built-in) or reset to day 1 (needs custom logic)?

Ratified 2026-06-18: keep the Trackables login_calendar XP ladder as the escalation backend rather than reframing to a Quests pool. It preserves the elegant single-quest gate (the daily cron rate-limits; the ladder escalates and holds the reward table) and keeps the entire grant path on built-in snaps. The one cost is provisioning the Trackables snap before the live grant works — a snapend update, not code. The editor, content block, model, verifier, and runtime UI are all built to this design and verify headlessly now; only the live end-to-end grant is gated on that provisioning. Backend escalation mechanism: keep the Trackables `login_calendar` XP ladder (requires provisioning the Trackables snap), or reframe to a pure Quests pool (one quest per calendar day, no new snap) now that Daily Missions proved that pattern in production?

Shipped a 7-day cycle (cycle length = number of login_calendar ladder levels), with per-day rewards 50 / 75 / 100 / 150 / 200 / 300 coins (days 1–6) then 20 gems on day 7. These are placeholder tuning values — the RC display calendar is editable in the daily_login_editor and the authoritative amounts live on the ladder levels, so the curve can be retuned without a client build. Calendar length and reward curve: 7-day or 28-day cycle, and the exact per-day currency amounts?

Shipped coins for the staple days (1–6) and a gems capstone on day 7 (50/75/100/150/200/300 coins → 20 gems). All launch currencies (coins/souls/gems) are selectable per day in the editor; this is the launch curve, not a committed economy. Which currencies fund the bonus — coins for staple days with a gems capstone on the final day?

## References
_None._

## Child pages
_None._
