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

## End-user experience (UX)

The sections above specify the plumbing — quests, goals, claims, config. This section specifies what the player sees and touches. The genre reference (Royal Match, Gardenscapes, Homescapes) surfaces dailies and events as a cluster of floating icons with countdown timers on the home/map screen, each opening a progress panel where you check progress and claim rewards. Moveborne adapts that to its own surface: a sparse Home screen (a MOVEBORNE hero plus three play-mode buttons) and a bottom nav that already carries five tabs (Collection, Leaderboard, Home, Guilds, Settings — tight at 360 px). The design below leans on the Home screen's open space and the persistent currency bar rather than adding navigation.

### Entry point — a floating Daily sigil on Home (recommended)

Surface Daily Missions as a single floating sigil button anchored to the right edge of the Home screen, in the empty space beside the hero — an occult seal in brand violet, the Moveborne reading of Royal Match's side-panel event cluster. It carries a reset countdown label (time to the next UTC midnight) and a claimable badge, lives on its own CanvasLayer over the shell (like the currency bar and nav bar), shows on the Home and Story surfaces, and is hidden during a match. Tapping it opens the Daily Missions panel. One icon ships now; the same right-edge rail can later hold Daily Login Bonus and limited-time events. Rejected alternatives: a sixth bottom-nav tab (the rail is already full at 360 px, and a time-limited feature does not belong behind a persistent-navigation metaphor); a chip in the top currency bar (that bar is a full, status-only surface — coins, souls, gems — not an action surface).

```text
+-------------------------------+   top currency bar (persistent)
|  (*) 1,250    (m) 8    (o) 12 |
+-------------------------------+
|                       +-----+ |   floating "Daily" sigil:
|                       | SUN |(2)  own CanvasLayer, Home/Story
|       MOVEBORNE       +-----+ |   only, hidden during a match.
|                        12:34  |   (2) = claimable-count badge
|                               |   12:34 = countdown to reset
|       +---------------+       |
|       |     Story     |       |
|       +---------------+       |
|       |   Infinite    |       |
|       +---------------+       |
|       |  PvP - Soon   |       |
|       +---------------+       |
+-------------------------------+   bottom nav (5 tabs, full)
| Coll  Lead  HOME  Guild  Set  |
+-------------------------------+
```

### The Daily Missions panel

The panel is a modal overlay, not a routed destination — it reuses the existing avatar-picker pattern (a CanvasLayer card over a dimmed scrim, dismissed by a close button or a tap outside), so the shell and nav stay mounted underneath for a quick check-in. Content sits in a ScrollContainer with MbScreenScaffold-style padding (about 312 px usable width at 360 px). The header shows the title, the live reset countdown, and — whenever anything is claimable — a 'claim before reset or rewards are lost' caption, because the Quests snap discards an unclaimed recurring reward at refresh. The body pins the anchor mission at the top in a visually distinct band (it is always present), then lists the day's active pool missions as cards. A 'Claim All' button appears in the footer when two or more missions are claimable, to keep the repeatable daily loop low-friction.

```text
            Daily Missions              [x]
     Resets in 12:34:07  -  claim or lose them
  +-------------------------------------------+
  | ANCHOR | Daily Dozen                      |  pinned, distinct
  |   Play 3 matches        [#######] 3/3      |
  |                                  [ CLAIM ] |  claimable (glow)
  +-------------------------------------------+
  | On a Roll                                 |
  |   Win 3 matches         [#####  ] 2/3      |  in-progress
  |                                    150 (*) |
  +-------------------------------------------+
  | Power Trip                            (v) |
  |   Use 2 power-ups       [#######] done     |  claimed (dimmed)
  |                                 80 (*) (v) |
  +-------------------------------------------+
                [   CLAIM ALL (2)   ]
```

### Mission card states & progress

Each card shows the catalog icon, title, and description (all from the Remote Config display catalog), a progress bar with its count, and a reward chip. A card is in one of three states. In-progress: partial bar, dimmed reward chip, no button. Complete and claimable: full bar, a violet/green claimable glow, and a Claim button. Claimed: collapsed to a spent state (dimmed, a check mark), reward chip greyed, kept visible until the daily reset so the player sees the day's completion. There is no locked state — every active mission is available the moment it appears (locking is a story-map concept, not a daily one). Progress is re-read when the panel opens and whenever the player returns to the shell from a match; it advances from validator-written statistics for match goals once hardening lands, or from client counters at launch.

### Claiming — reward feedback

Tapping Claim posts the quest claim; on success the reward chip's currency icon flies from the card to its slot in the top currency bar (coins to the coin slot, souls to souls, gems to gems), GameState.merge_currencies applies the grant, and the currency bar re-renders on the currencies_changed signal with a short count-up and a pulse on that slot. This is the genre-standard 'coins fly to the balance' beat, and it reuses the persistent currency bar wholesale — no new wallet UI. The card then flips to claimed and the Home sigil badge decrements; when the final claim lands the badge clears. Claim All runs the claims in sequence with staggered flies (or one batched burst) so the payoff stays legible.

### Badge & notification logic

The sigil badge has a strict precedence: a claimable-count chip (the number of complete, unclaimed missions) when that count is at least one; otherwise a soft pulse dot when missions are active but none are claimable yet; otherwise nothing. The strong cue (a number) is reserved for the one state that earns it — you have rewards to collect — while the dot says only 'missions refreshed, go play', and a fully-claimed day shows no cue at all. This follows the UX-restraint rule that persistent bright badges make an interface noisy. The badge is recomputed from the active quests on app open, on return from a match, and after each claim.

### Reset countdown & claim-before-midnight

A single countdown to the next global UTC midnight shows both under the sigil and in the panel header, matching the genre's timer-labelled event buttons; it is the same boundary as Daily Login Bonus and Challenge of the Day and must stay aligned with them. Inside the last hour the countdown switches to an amber warning and, if anything is still claimable, the sigil pulses — the only place the feature escalates its cue. The hard rule that unclaimed rewards are lost at refresh is stated in the panel copy, not just assumed.

### Surfacing on app open & first run

On every app open the client refreshes the badge but does not open the panel — auto-popping a modal on each launch is exactly the friction the daily loop should avoid. The panel auto-surfaces only when rewards are actually at risk: there are claimable missions and either this is the first open of a new daily period or under an hour remains before reset. The first time the sigil ever appears, a one-time coachmark ('New — Daily Missions: play to earn') points at it and dismisses on tap.

### Empty, offline & feature-flag states

All-claimed: the panel keeps the missions visible in their claimed state with a 'come back tomorrow' line and the countdown; the sigil shows no badge. Feature flag off (Remote Config daily_missions.enabled = false): the sigil is hidden entirely and the panel is unreachable, so there is never a dead entry point. No session / Infinite mode: claims require the Snapser gateway, and Infinite is always offline with results that never feed shared statistics, so the sigil is hidden (or inert) without a session, and counter-goal progress made offline cannot be claimed until reconnected. Tiers 2 and 3 change only which missions the config names — the UI is identical across all three rotation tiers.

### Theming, motion & automation hooks

The sigil and cards use the MbStyle tokens: PRIMARY violet for accents and the active glow, BG/BOARD fills for cards, TEXT and DIM for copy, HIGHLIGHT green reserved for the claimable accent, and the currency colors (coins #f5c542, souls #b400ff, gems #42d8f5) for reward chips and their fly targets, all in the Grammara face. Motion is deliberately quick — panel fade/slide in about 200 ms, a card claim glow-and-collapse, an about-400 ms ease-out currency fly into the bar with a slot count-up — because latency is the daily loop's enemy. The sigil's occult-seal treatment ties it to the art direction rather than a generic alert bubble. For automation and the testing plan, register the sigil as home.daily (Reg.texture_button), each claim button as missions.<mission_name>, and Claim All as missions.claim_all, and add MbUi flows open_daily_missions and claim_daily so headless runs can drive the surface.

## Rotation at launch (Snapser-aligned)

Correction to the tiered plan above: Snapser's quest cron is a reset/refresh cadence, not an active-day filter — a recurring quest stays active continuously from its start tick until the next tick, so a weekday cron (0 0 * * 1,4) does not make a mission appear only on Mondays and Thursdays; it merely resets it on those days. Daily variety therefore comes from selection, not cron. Launch mechanism: every pool mission is a daily-reset recurring quest (0 0 * * *) with auto-assign off; the anchor is auto-assigned; the Remote Config daily_missions block holds a static weekday-to-mission-names map plus the display catalog; on app open the client computes today's UTC weekday, assigns that day's named subset via AssignQuest, and displays the anchor plus that subset. This is the 'Remote-Config-driven set' described above, used from day one — fully built-in (Quests + Remote Config), no Scheduler write required. The reset countdown reads each quest's resetsAt field rather than recomputing midnight. A Scheduler/Events-flipped active key (for non-weekday cadences) and per-player randomization in the BYOSnap remain later upgrades.

```json
{
  "daily_missions": {
    "enabled": true,
    "anchor": "mission_anchor_play_3",
    "by_weekday": {
      "0": ["mission_win_2",  "mission_powerup_2", "mission_merge_50"],   // Sun
      "1": ["mission_play_5", "mission_combo_5",   "mission_score_5k"],   // Mon
      "2": ["mission_win_2",  "mission_score_5k",  "mission_combo_5"],    // Tue
      "...": "one entry per UTC weekday; the client picks today's"
    },
    "catalog": { "...": "title / icon / desc / reward per mission, as in the block above" }
  }
}
```

## Out of scope

Per-player randomized rotation, anti-repeat, and difficulty weighting (Tier 3, BYOSnap). Per-player local midnight. Inventory-item rewards (no catalog items provisioned; currency only at launch). The deterministic puzzle content of any mission that modifies rules stays in the rules engine, as with Challenge of the Day. On the UX side, deferred as future growth: a multi-icon event rail (the sigil ships as one icon, with room to grow along the same edge), an activity-point or mission-chest meta layer stacked above the per-mission rewards (Royal Match's stars-to-chest pattern), and any reward type beyond the currency fly-to-wallet.

## Decisions
Global UTC midnight at launch (recommended, pending ratification): the cron boundary is global. Per-player local midnight would require the meta-game BYOSnap and is deferred. Keep Daily Missions, Daily Login Bonus, and Challenge of the Day on the same UTC boundary. Refresh boundary: global UTC midnight (recommended, built-in) or per-player local midnight (needs custom logic)?

Recommended (pending ratification): surface Daily Missions as a single floating 'Daily' sigil on the Home screen — reset countdown plus a claimable-count badge — opening a modal missions panel, with rewards flying into the existing top currency bar. This matches the Royal Match / Gardenscapes floating-event-icon convention, fits Moveborne's sparse Home screen and already-full five-tab nav (so no sixth tab) and its status-only currency bar (so no chip there), and reuses the currency bar for reward feedback (no new wallet UI). The panel auto-surfaces on open only when rewards are at risk of expiring; otherwise the badge carries the signal. A multi-icon event rail and an activity-point/chest meta layer are future growth, not launch. Client surfacing / entry point: a floating 'Daily' sigil on the Home screen (reset countdown + claimable badge) opening a modal panel — recommended — versus a sixth bottom-nav tab versus a chip in the top currency bar; and should the panel auto-open on launch, or only badge unless rewards are at risk of expiring?

Launch rotation (ratified 2026-06-17, supersedes the earlier cron-stagger plan): Snapser quest cron is a reset cadence, not a per-day activation window, so a weekday cron cannot gate daily appearance. Launch on the Remote-Config-driven set — pool missions are daily-reset recurring quests (0 0 * * *) with auto-assign off; the anchor is auto-assigned; a static weekday->mission-names map in the daily_missions Remote Config block drives selection; the client assigns today's subset on open and reads each quest's resetsAt for the countdown. Built-ins only (Quests + Remote Config). Scheduler/Events-curated sets and BYOSnap per-player randomization are later upgrades. Launch = anchor + 3 rotating from a pool of 6, global UTC midnight. Launch rotation tier: Tier 1 fixed weekly cron-stagger (recommended, fully built-in) or Tier 2 Remote-Config-driven set?

## References
_None._

## Child pages
_None._
