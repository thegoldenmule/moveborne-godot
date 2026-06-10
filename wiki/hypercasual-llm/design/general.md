# General

**Status:** active

## Body
Desired meta-game, monetization, and retention features for Moveborne, drawn from common patterns in hypercasual and puzzle titles. Each entry is a short brief plus a note on which Snapser snap (if any) supports it; features graduate to their own pages under Features when scoped.

## Reward Screens

End-of-run and milestone screens that grant rewards — typically lives, power-ups, and currency. Often paired with player-driven interstitials (watch an ad to double or claim the reward), making them a primary opt-in ad surface.

Snapser: partially supported. The Inventory snap grants the rewards themselves (currency, consumable power-ups), and Trackables provides an Energy resource purpose-built for lives (max cap, timed regeneration, optional overflow). Not covered: ad serving — rewarded interstitials need a client-side ad SDK, and verifying an ad watch before granting the bonus is custom logic.

## Ad-Free Version IAP

A one-time purchase that permanently removes forced ads (banners and interstitials). Opt-in rewarded ads usually remain available since players choose them for value.

Snapser: supported by the IAP snap, which validates Google Play and Apple App Store receipts (plus Steam and Tebex) and auto-grants inventory items on success — the ad-free entitlement works as a durable Inventory item. Not covered: actually suppressing ads in the client; there is no ad-mediation integration.

## Persistent Banner Ads

An always-on banner anchored to the screen edge during menus and gameplay. Low revenue per impression but steady volume; layout must reserve safe space for it.

Snapser: no Snapser service covers ad serving or mediation — banners come entirely from a third-party ad SDK such as AdMob. Remote Config can toggle banner placement or visibility remotely, but that is the only touchpoint.

## IAPs for Currency and Power-Ups

Direct purchases of soft/hard currency and consumable power-ups. The core monetization loop: currency sinks in-game create demand that the store satisfies.

Snapser: well supported. The IAP snap validates store receipts and auto-grants on success; the Inventory snap manages the currency wallet and the consumable power-up catalog items being granted.

## Starter Pack

A heavily discounted one-time bundle offered to new players (often time-limited after first session) to convert them into first-time payers. Typically the highest-converting SKU in the store.

Snapser: mostly supported. An IAP bundle can grant the pack's mixed contents on purchase, and Statistics & Segmentation (or Experiments) can target a new-player segment. Not covered: there is no dedicated offers service — one-time-per-player gating and time-limited presentation are game/BYOSnap logic.

## Price-Tiered Packages ($0.99–$99)

A ladder of currency packages spanning the full price range from $0.99 impulse buys to $99 whale tiers, with better value per dollar at higher tiers.

Snapser: supported by the IAP snap — each store SKU maps to an IAP bundle granting the corresponding currency amount. Not covered: the price points themselves live in App Store Connect / Google Play Console; Snapser does not manage storefront pricing.

## Bundle Packs

Mixed-content offers combining currency, power-ups, and cosmetics at a discount versus buying separately. Often rotated or personalized to spend history.

Snapser: supported. IAP bundles grant multiple items and currencies per purchase, and the Inventory snap adds containers, drop tables, and a discount system with eligibility criteria for virtual-currency-priced bundles.

## Settings

A settings screen covering save-game management (cloud save/restore), audio controls (music and SFX), help and customer support access, and social account connection with a one-time reward for linking.

Snapser: mixed coverage. Storage covers cloud save (blob/JSON blobs with concurrency control). Auth covers social connection: its connectors (Google, Apple, Facebook, Discord, etc.) plus the AssociateLogins API merge an anonymous account into a social login, with the link reward granted via Inventory. Audio controls are client-only. Not covered: help/customer support — there is no ticketing or helpdesk snap (the GDPR snap handles data access/deletion requests; Inbox is text-only messaging, not a CS system).

## Leaderboards

Ranked score boards — global, friends, and weekly brackets are common. Drives competitive retention and gives high scores in Infinite mode social weight.

Snapser: fully supported by the Leaderboards snap — global and tiered (league-style) boards, recurring and non-recurring periods, with admin tooling; the Guilds snap adds inter-guild leaderboards. Friend-scoped boards are not a documented board type; the Social Graph snap manages friend relationships if a friends view is composed on top.

## Challenge of the Day

A daily curated puzzle or modified-rules run, the same for all players, with its own reward. Creates a daily appointment and a shared talking point.

Snapser: supported by composition. A recurring daily Quest (cron-scheduled) carries the challenge goal and reward; Remote Config can deliver the day's puzzle parameters; the Events snap can orchestrate activation windows. Not covered: generating the deterministic daily puzzle itself — that stays in our own rules engine and validator.

## Achievements / Battle Pass

Long-horizon goal tracks: permanent achievements for lifetime milestones, and a seasonal battle pass with free and premium reward lanes that monetizes engaged players.

Snapser: supported by composition. Achievements map to one-time Quests with counter/statistic goals and rewards. A battle pass maps to a Trackables XP ladder (levels as tiers, automatic level assignment, auto-reset for seasons) fed by quest rewards, with the premium unlock sold through IAP. Not covered: there is no dedicated battle-pass service — free vs premium reward lanes and season rollover must be composed (Events can schedule season boundaries).

## Events

Time-limited events with their own rules, themes, and reward tracks. Reuses core gameplay with a twist to spike engagement and give lapsed players a reason to return.

Snapser: directly supported by the Events snap — one-time or recurring events with up to 10 milestones, each able to trigger push/email blasts (Notifications), Remote Config overrides, and quest activation/deactivation. Caveats: it is a Premium-plan snap, and it is only useful alongside the Notifications, Remote Config, or Quests snaps.

## Daily Login Bonus

A reward granted simply for opening the game each day, usually on an escalating calendar. The cheapest retention lever to build.

Snapser: partially supported. A recurring daily Quest (cron-scheduled) with a counter goal incremented on login auto-grants the reward — currency, items, XP, or energy. Not covered: an escalating day-1-to-day-N reward calendar is not built in; it must be composed from multiple quests or a day index tracked in Statistics or Storage.

## Weekly Login Streak Bonus

A larger bonus for maintaining consecutive daily logins across a week, resetting (or partially decaying) on a miss. Layers on the daily bonus to reward sustained habit.

Snapser: no direct support — there is no streak service. Composable: track the streak as a Statistics counter, reward it via a Quest with a statistic goal, and run the reset-on-miss logic via the Scheduler snap or our validator BYOSnap; that decay/reset logic is entirely custom.

## References
_None._

## Child pages
_None._
