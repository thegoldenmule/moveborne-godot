# Spec — Daily Login Bonus

**Status:** drafting

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

## Decisions
Launch default (recommended, pending ratification): pause-and-continue. The calendar advances only when claimed and never resets on a missed day, keeping the entire feature on built-in snap config. A punishing reset-on-miss would require the meta-game BYOSnap to track consecutive-day state and is split into the Weekly Login Streak Bonus feature. On a missed day, pause-and-continue (recommended; fully built-in) or reset to day 1 (needs custom logic)?

## References
_None._

## Child pages
_None._
