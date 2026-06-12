# Spec — Daily Missions

**Status:** drafting

## Overview
**A rotating set of 4–8 daily tasks plus one always-present anchor, each a recurring Quest with a claimable currency reward.** The missions themselves are pure Quests config; the only genuinely custom part is rotation — choosing which missions appear each day. This spec ships rotation in tiers: a deterministic weekday cron-stagger now (no custom code), Remote-Config-driven sets next, and true per-player randomization deferred to the meta-game BYOSnap. Win/play goals graduate from client counters to validator-written statistics so the rewards stay cheat-resistant.

## Design
Notation: the JSON below illustrates the documented Quests and Remote Config capabilities, not literal API field names. Exact field names come from each snap's Settings tool and swagger at implementation time.

## Snapser mapping

Each mission is a recurring daily Quest with a single task, a goal, and a currency reward. Quests supplies the goals, the daily refresh, and the explicit claim. Remote Config supplies the mission display catalog and, in the rotation tier, the day's active set. Scheduler or Events can flip that config on a schedule. The only thing no snap provides is the rotation policy itself — which missions to surface today — which is why rotation is staged below.

## A single mission (Quests)

Every mission, anchor or pool, has the same shape: a recurring daily quest, one task, one goal, one reward. The goal type is chosen per mission. Play-count and win-count goals should be statistic goals backed by the gameplay validator; an action like using a power-up can be a counter goal at launch. Rewards are currency from the provisioned wallets.

```json
{
  "name": "mission_win_3",
  "description": "Win 3 matches today.",
  "active": true,
  "auto_assign": false,
  "recurring": true,
  "cron": "0 0 * * *",
  "tags": ["daily_mission", "pool"],
  "tasks": [
    {
      "name": "win_matches",
      "goal": { "type": "statistic", "statistic": "matches_won", "mode": "relative", "target": 3 },
      "rewards": [ { "type": "currency", "currency": "coins", "amount": 150 } ]
    }
  ]
}
```

mode relative means the goal measures progress made during this quest period, not a lifetime absolute — essential for a daily that resets.

## The anchor mission

One mission is always present. It is a recurring daily quest with auto-assign on and an anchor tag, never rotated out. Make it the broad engagement goal, for example play three matches, so every player has at least one reachable daily regardless of the rotation.

```json
{
  "name": "mission_anchor_play_3",
  "auto_assign": true,
  "recurring": true,
  "cron": "0 0 * * *",
  "tags": ["daily_mission", "anchor"],
  "tasks": [
    {
      "name": "play_matches",
      "goal": { "type": "statistic", "statistic": "matches_played", "mode": "relative", "target": 3 },
      "rewards": [ { "type": "currency", "currency": "coins", "amount": 100 } ]
    }
  ]
}
```

## Rotation — Tier 1: weekday cron-stagger (ships now)

The cheapest honest rotation is a fixed weekly schedule encoded entirely in cron expressions. Give each pool mission a cron that only activates it on certain weekdays. Each day a deterministic two to four pool missions are active alongside the anchor, for four to five visible missions. It repeats weekly but varies day to day, needs zero custom code, and refreshes at midnight via cron. Auto-assign can be on for Tier 1 since the cron itself selects what is active.

```text
mission_win_3          cron "0 0 * * 1,4"     # Mon, Thu
mission_combo_x5       cron "0 0 * * 2,5"     # Tue, Fri
mission_powerup_2      cron "0 0 * * 3,6"     # Wed, Sat
mission_score_10k      cron "0 0 * * 0"       # Sun
mission_anchor_play_3  cron "0 0 * * *"       # every day
# each day: anchor + the 1-2 pool missions whose weekday matches
```

## Rotation — Tier 2: Remote-Config-driven set

When LiveOps wants to choose the daily set without weekday math, define the full pool with auto-assign off and let a Remote Config key name the day's active missions. The client reads the key and assigns only the named missions plus the anchor. Who writes the key each day is still built-in: a human in the LiveOps tool, or the Scheduler or Events snap flipping the value on a cron. This gives flexible curation without per-player randomization.

```json
{
  "daily_missions": {
    "enabled": true,
    "anchor": "mission_anchor_play_3",
    "active": ["mission_win_3", "mission_combo_x5", "mission_powerup_2"],
    "catalog": {
      "mission_win_3":         { "title": "On a Roll",      "icon": "trophy", "desc": "Win 3 matches",   "reward": "150 coins" },
      "mission_combo_x5":      { "title": "Chain Reaction", "icon": "spark",  "desc": "Make a 5-chain",  "reward": "120 coins" },
      "mission_powerup_2":     { "title": "Power Trip",     "icon": "bolt",   "desc": "Use 2 power-ups", "reward": "80 coins"  },
      "mission_anchor_play_3": { "title": "Daily Dozen",    "icon": "cards",  "desc": "Play 3 matches",  "reward": "100 coins" }
    }
  }
}
```

The catalog block lets the client render every mission — title, icon, description, reward preview — without hardcoding, and lets you re-theme or retune without a client build.

## Rotation — Tier 3: per-player randomized (deferred to BYOSnap)

True per-player rotation — sample four to eight from the pool per player, weight by difficulty, avoid repeating yesterday's set, keep the anchor pinned — is the documented gap that no snap covers. It belongs to the meta-game BYOSnap, which would compute each player's set and either assign the quests directly or write the per-user Remote Config override the client reads. This is out of scope for the story-loop launch.

## Goal types and authority

Match-derived goals — matches played, matches won, score thresholds — should be statistic goals read from statistics the gameplay validator writes on match completion. That makes the reward as trustworthy as the match path, per the weak-link rule, at near-zero added cost since the validator already sits there. Non-match actions like using a power-up can stay counter goals incremented by the client at launch; their blast radius is one day's small reward. As hardening lands, lock IncrementUserStatistic and the currency mints to server-only callers so neither the statistic feed nor the payout can be forged.

## Refresh, claim, and the midnight boundary

Recurring quests refresh on their cron. Critically, a recurring quest's reward can only be claimed before the next refresh — an unclaimed mission reward is lost at midnight. The client must surface a claim-before-reset prompt and claim on the reward screen. The boundary is a single global cron timezone, UTC recommended, so it is global midnight for everyone. Per-player local midnight is not expressible in cron and would need the BYOSnap. Challenge of the Day shares this same boundary; keep them aligned.

## Client flow

On opening the daily-missions screen, the client lists the active missions, reads their display metadata from Remote Config, and shows live progress. Progress comes from statistic goals the validator advances, or from client increments for counter goals. The player claims each completed mission on the screen, before the daily reset.

```text
GET  /v1/quests/users/{user_id}/active_quests          # filter tags daily_mission / anchor
GET  /v1/remote-config/user-config/{user_id}           # enabled, active set (Tier 2), catalog
# Tier 2 only: assign the named missions
POST /v1/quests/users/{user_id}/quests/{mission}/assign
# progress: statistic goals advance via the validator; counter goals via the client
PUT  /v1/quests/users/{user_id}/quests/{mission}/tasks/{task}
# reward screen, before the midnight reset
POST /v1/quests/users/{user_id}/quests/{mission}/claim_rewards
```

## Out of scope

Per-player randomized rotation, anti-repeat, and difficulty weighting (Tier 3, BYOSnap). Per-player local midnight. Inventory-item rewards (no catalog items provisioned; currency only at launch). The deterministic puzzle content of any mission that modifies rules — that stays in the rules engine, as with Challenge of the Day.

## Decisions
Launch on Tier 1 (recommended, pending ratification): a weekday cron-staggered pool plus the anchor, entirely built-in config, no custom code. Tier 2 Remote-Config sets and Tier 3 per-player randomization are follow-ons that do not block the story-loop launch. Launch rotation tier: Tier 1 fixed weekly cron-stagger (recommended, fully built-in) or Tier 2 Remote-Config-driven set?

Global UTC midnight at launch (recommended, pending ratification): the cron boundary is global. Per-player local midnight would require the meta-game BYOSnap and is deferred. Keep Daily Missions, Daily Login Bonus, and Challenge of the Day on the same UTC boundary. Refresh boundary: global UTC midnight (recommended, built-in) or per-player local midnight (needs custom logic)?

## References
_None._

## Child pages
_None._
