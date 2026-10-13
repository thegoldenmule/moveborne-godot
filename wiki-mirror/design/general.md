# General

**Status:** active

## Body
Desired meta-game, monetization, and retention systems for Moveborne, drawn from common patterns in hypercasual and puzzle titles. Entries are reusable, composable systems rather than game-specific features. Each has a short brief plus a note on which Snapser snaps (if any) support it; systems graduate to their own pages under Features when scoped.

## Reward Screens

End-of-run and milestone screens that grant rewards — typically lives, power-ups, and currency. Often paired with player-driven interstitials (watch an ad to double or claim the reward), making them a primary opt-in ad surface.

- **Snaps:** Inventory, Trackables (Energy), Quests.
- **Covers:** granting the rewards — currency and consumable power-ups via Inventory; lives via Trackables Energy (max cap, timed regeneration, optional overflow); reward bundles on quest completion.
- **Gaps:** ad serving and rewarded-interstitial playback (client ad SDK territory), and verifying an ad watch before granting the bonus.

## Ad-Free Version IAP

A one-time purchase that permanently removes forced ads (banners and interstitials). Opt-in rewarded ads usually remain available since players choose them for value.

- **Snaps:** IAP, Inventory.
- **Covers:** receipt validation for Google Play and Apple App Store (plus Steam and Tebex); auto-granting the entitlement as a durable Inventory item, or as a TTL item for a timed ad-free pass; purchase history.
- **Gaps:** actually suppressing ads in the client — there is no ad-mediation integration.

## Persistent Banner Ads

An always-on banner anchored to the screen edge during menus and gameplay. Low revenue per impression but steady volume; layout must reserve safe space for it.

- **Snaps:** none.
- **Covers:** nothing directly — ad serving and mediation come entirely from a third-party ad SDK such as AdMob. Remote Config can toggle banner placement or visibility remotely, but that is the only touchpoint.

## IAPs for Currency and Power-Ups

Direct purchases of soft/hard currency and consumable power-ups. The core monetization loop: currency sinks in-game create demand that the store satisfies.

- **Snaps:** IAP, Inventory.
- **Covers:** store receipt validation with auto-grant on success; currency wallets and the consumable power-up catalog. This is the platform's core monetization path — no significant gaps.

## Starter Pack

A heavily discounted one-time bundle offered to new players (often time-limited after first session) to convert them into first-time payers. Typically the highest-converting SKU in the store.

- **Snaps:** IAP, Inventory, Statistics & Segmentation, Experiments.
- **Covers:** granting the pack's mixed contents as an IAP bundle on validated purchase; targeting a new-player segment via Segmentation or Experiments.
- **Gaps:** no dedicated offers service — one-time-per-player gating and time-limited presentation are game/BYOSnap logic.

## Price-Tiered Packages ($0.99–$99)

A ladder of currency packages spanning the full price range from $0.99 impulse buys to $99 whale tiers, with better value per dollar at higher tiers.

- **Snaps:** IAP, Inventory.
- **Covers:** each store SKU maps to an IAP bundle granting the corresponding currency amount on validated purchase.
- **Gaps:** the price points themselves live in App Store Connect / Google Play Console — Snapser does not manage storefront pricing.

## Bundle Packs

Mixed-content offers combining currency, power-ups, and cosmetics at a discount versus buying separately. Often rotated or personalized to spend history.

- **Snaps:** IAP, Inventory.
- **Covers:** multi-item grants per purchase via IAP bundles; containers, drop tables, and a discount system with eligibility criteria for virtual-currency-priced bundles.
- **Gaps:** rotating or personalizing the offers shown to a player is custom logic (Experiments and Segmentation can help target, but there is no offers service).

## Settings

A settings screen covering save-game management (cloud save/restore), audio controls (music and SFX), help and customer support access, and social account connection with a one-time reward for linking.

- **Snaps:** Storage, Auth, Inventory, GDPR.
- **Covers:** cloud save via Storage (blob/JSON blobs with concurrency control); social connection via Auth connectors (Google, Apple, Facebook, Discord, and more) with the `AssociateLogins` API merging the anonymous account; the link reward granted via Inventory; data access/deletion requests via the GDPR snap.
- **Gaps:** help/customer support — there is no ticketing or helpdesk snap (Inbox is text-only messaging, not a CS system). Audio controls are client-only and need no backend.

## Leaderboards

Ranked score boards — global, friends, and weekly brackets are common. Drives competitive retention and gives high scores in Infinite mode social weight.

- **Snaps:** Leaderboards, Guilds, Social Graph.
- **Covers:** global and tiered (league-style) boards, recurring and non-recurring periods, admin tooling; inter-guild boards via the Guilds snap.
- **Gaps:** friend-scoped boards are not a documented board type — Social Graph supplies friend relationships if a friends view is composed on top.

## Challenge of the Day

A daily curated puzzle or modified-rules run, the same for all players, with its own reward. Creates a daily appointment and a shared talking point.

- **Snaps:** Quests, Remote Config, Events, Scheduler.
- **Covers:** a recurring daily Quest (cron-scheduled) carries the challenge goal and reward; Remote Config delivers the day's puzzle parameters; Events orchestrates activation windows.
- **Gaps:** generating the deterministic daily puzzle itself — that stays in our own rules engine and validator.

## Daily Missions

A rotating set of small daily tasks (play 3 matches, win 4, use a power-up) refreshed every 24 hours, each with a claimable reward — distinct from the single curated Challenge of the Day above. Typically 4–8 active missions drawn from a larger pool, with one anchor mission always present.

- **Snaps:** Quests, Remote Config, Scheduler.
- **Covers:** recurring cron-scheduled Quests with counter, item, currency, statistic, or trackable goals and auto-granted rewards; quests targeted at user segments.
- **Gaps:** rotating which missions appear from the pool, keeping an always-present anchor mission, and choosing global midnight vs per-player midnight are composition decisions — quest activation can be driven by Scheduler or Remote Config, but the rotation logic is ours.

## Achievements / Battle Pass

Long-horizon goal tracks: permanent achievements for lifetime milestones, and a seasonal battle pass with free and premium reward lanes that monetizes engaged players.

- **Snaps:** Quests, Trackables, Statistics, IAP, Events.
- **Covers:** achievements as one-time Quests with counter/statistic goals and rewards; battle-pass progression as a Trackables XP ladder (levels as tiers, automatic level assignment, auto-reset for seasons) fed by quest rewards; the premium unlock sold through IAP.
- **Gaps:** no dedicated battle-pass service — free vs premium reward lanes and season rollover must be composed (Events can schedule season boundaries).

## Events

Time-limited events with their own rules, themes, and reward tracks. Reuses core gameplay with a twist to spike engagement and give lapsed players a reason to return.

- **Snaps:** Events, with Notifications, Remote Config, and Quests as its trigger targets.
- **Covers:** one-time or recurring events with up to 10 milestones; each milestone can trigger push/email blasts, Remote Config overrides, and quest activation/deactivation.
- **Gaps:** Events is a Premium-plan snap, and it does nothing without Notifications, Remote Config, or Quests alongside it.

## Daily Login Bonus

A reward granted simply for opening the game each day, usually on an escalating calendar. The cheapest retention lever to build.

- **Snaps:** Quests, Inventory, Trackables.
- **Covers:** a recurring daily Quest (cron-scheduled) with a counter goal incremented on login, auto-granting currency, items, XP, or energy.
- **Gaps:** an escalating day-1-to-day-N reward calendar is not built in — compose multiple quests or track a day index in Statistics or Storage.

## Weekly Login Streak Bonus

A larger bonus for maintaining consecutive daily logins across a week, resetting (or partially decaying) on a miss. Layers on the daily bonus to reward sustained habit.

- **Snaps:** none dedicated — composable from Statistics, Quests, and Scheduler.
- **Covers:** the streak itself as a Statistics counter, and the weekly reward via a Quest with a statistic goal.
- **Gaps:** reset-on-miss and decay logic is entirely custom — run it via the Scheduler snap or our validator BYOSnap.

## Virtual Currency Economy

A multi-currency economy — typically a soft currency earned through play and a hard currency bought with cash, sometimes plus seasonal points — with sinks such as continues (play again for coins), in-match wagers, and unlock costs giving each currency meaning.

- **Snaps:** Inventory.
- **Covers:** defining multiple currency types and managing each user's wallet; granting and deducting via API; currencies usable as purchase costs for items and containers, as IAP bundle contents, and as quest or trackable rewards.
- **Gaps:** sink design and pricing are game design work; server-authoritative spend validation for in-match sinks (wagers, continues) belongs in our validator so clients cannot mint or double-spend.

## Item Collection & Loadouts

A persistent collection of owned items (power-ups, special cards, boosters — whatever the game ships) with a smaller active set the player takes into a match. Reusable across any game with collectible content.

- **Snaps:** Inventory.
- **Covers:** the item catalog with consumption types (durable, consumable, stackable) and tags/metadata for filtering; per-user inventories; sub-inventories (bags) with a `MoveItemsToSubInventory` API that can model an active loadout versus the reserve collection.
- **Gaps:** loadout rules (size limits, eligibility) and how equipped items affect play are game logic — anything match-affecting must flow through the deterministic rules engine and validator.

## Randomized Rewards (Gacha / Drop Tables)

Randomized item grants — loot boxes, card packs, x1/x10 pulls — priced in virtual currency. The odds live server-side so they are tamper-proof and tunable without a client release.

- **Snaps:** Inventory.
- **Covers:** drop tables with per-item probabilities, delivered through containers the player opens; containers with unlock costs in currency, items, or trackables; discounts with eligibility criteria for running sales on pulls.
- **Gaps:** pity timers, duplicate protection, and odds-disclosure compliance are not documented features — they need custom logic or careful design on top.

## Cosmetics & Equipping

Unlockable visual items (tile skins, board themes, card backs) that players collect, buy, and equip. Pure presentation, so the system composes with any game.

- **Snaps:** Inventory, Profiles.
- **Covers:** cosmetics as durable catalog items, sellable for virtual currency or granted via IAP bundles and drop tables; the equipped selection stored as a profile attribute.
- **Gaps:** rendering and the equip UI are client work; there is no server-side equipped-slot concept beyond what we store in the profile.

## XP & Player Leveling

An account-level XP track — earn XP for entering matches, winning, and finishing challenges — with levels that gate tier-unlock rewards in the lobby. Distinct from a seasonal battle pass, though built from the same machinery.

- **Snaps:** Trackables, Quests.
- **Covers:** XP ladders with levels as numeric ranges, automatic level assignment, and per-level rewards (items, currency, drop tables, energy, even other XP); ladder chaining and optional auto-reset; Quests granting XP as rewards.
- **Gaps:** deciding where XP is emitted is game logic — and grants tied to match results should come from the validator, not the client, to stay cheat-resistant.

## Player Profile

A per-player identity surface — display name, avatar, best stats, achievement highlights — visible to the player and optionally to others.

- **Snaps:** Profiles, Statistics.
- **Covers:** customizable profile attributes with access control (public versus private); lifetime counters from Statistics to surface personal bests.
- **Gaps:** composing the best-achievements summary is an aggregation we build; there is no ready-made public profile page.

## Player Inbox (Dev Messages)

An in-game mailbox for mail from the devs — patch notes, event announcements, apology gifts — and optionally player-to-player or guild messages.

- **Snaps:** Inbox.
- **Covers:** admin-to-user messages, including bulk sends to a user, friends, followers, or a guild; read/unread state; deletion.
- **Gaps:** messages are text-only — no reward attachments, so a claimable gift must be composed as a message plus an Inventory grant keyed to it.

---

## Proposed Meta-Game Service (BYOSnap)

The existing validator BYOSnap is strictly for gameplay validation. The Gaps above share a pattern: trusted custom logic that no snap provides and that does not belong in the validator. The proposal is a second BYOSnap — a meta-game service deployed the same way — that owns that logic, composing the snaps on the player's behalf. This is a scope statement only; no implementation details here. From this page, it needs to implement:

- **Reward Screens** — verifying a rewarded-ad watch before granting the bonus.
- **Starter Pack / Bundle Packs** — offer gating and presentation: one-time-per-player starter pack, time-limited windows, and rotating or personalizing which offers a player sees.
- **Challenge of the Day** — selecting and publishing each day's challenge parameters (the deterministic puzzle itself stays in the rules engine).
- **Daily Missions** — rotating the active mission set from the pool, keeping the anchor mission present, on the chosen midnight boundary.
- **Achievements / Battle Pass** — resolving free versus premium reward lanes and orchestrating season rollover.
- **Daily Login Bonus** — the escalating day-1-to-day-N reward calendar.
- **Weekly Login Streak Bonus** — streak tracking with reset-on-miss or decay.
- **Settings** — the one-time reward grant when a player links a social account.
- **Randomized Rewards** — pity timers and duplicate protection layered over Inventory drop tables.
- **Player Profile** — aggregating the best-achievements summary.
- **Player Inbox** — claimable gifts: pairing a message with its Inventory grant and gating the claim.

**Out of scope:** everything a snap already covers (the Covers bullets above) stays in that snap, and everything match-authoritative — action validation, in-match currency sinks (wagers, continues), and XP grants tied to match results — stays in the gameplay validator. See Validator.

---

## Authority Model — Client vs Server

Snapser defaults to client-authoritative: with only a session token, a client can call the grant/score/progress write APIs on its own account. The Auth snap's User Auth Restrictions tool removes client access per API, leaving Api-Key and Internal (BYOSnap) callers only. The split below weighs each design area on three axes: ease of building it, load it puts on a BYOSnap, and what cheating could affect (blast radius).

- **Weak-link rule:** a reward is only as trustworthy as its least-trusted input — a locked claim on a client-written counter is still cheatable. Prefer currency/item/trackable quest goals (trusted once mints are locked) over counter goals for quests that mint meaningful rewards.
- **Mints vs exchanges:** unconditioned writes (`IncrementUserCurrency`, `GrantItemsToUser`, `GrantDropTable`, `SetScore`, `IncrementUserStatistic`) are the dangerous surface and must be locked. Conditioned exchanges (purchase, container open/unlock, conversion) deduct their cost atomically inside the snap and stay safely client-callable.
- **Existing trusted writer:** the gameplay validator already sits in the match path — match-derived outcomes (scores, match XP, win/play statistics) become server-authoritative at near-zero marginal cost.
- **Infinite is offline:** anything offline play feeds is client-trust by construction; keep offline results off shared surfaces (no leaderboard writes from Infinite).

| Design area | Authority | If cheated, affects | Server load | Ease |
| --- | --- | --- | --- | --- |
| Leaderboard scores | Server — validator submits | everyone (competitive integrity) | none new — rides the match flow | low |
| Match XP, win/play statistics | Server — validator writes | everything downstream: quests, pass, boards | none new | low |
| Currency & item mints | Server-only — lock via User Auth Restrictions | the whole economy and revenue | zero — configuration, not code | trivial |
| Store purchases (IAP receipts) | Snap-enforced — client-callable | revenue — but the signed store receipt is the proof | zero | trivial |
| Virtual-currency purchases, container opens | Snap-enforced — client-callable | nothing — cost deducted atomically | zero | trivial |
| Daily login bonus / streak claims | Snap-enforced — client-callable | bounded daily mint; the session is the login | zero | trivial |
| Daily missions (counter goals) | Client at launch → validator-fed statistics later | bounded daily mint | none → small | low |
| Rewarded-ad grants | Server — ad-network SSV endpoint (deferrable) | unbounded mint if forged | new endpoint, per ad watch | moderate |
| Gacha pity / duplicate protection | Server — only if designed in | fairness and support load, not security | per pull | moderate |
| Cloud save, profile, cosmetics, settings | Client | only the cheater's own account | zero | trivial |
| Offer / starter-pack gating | Client + Remote Config | worst case: a player pays real money twice | zero | trivial |

**Phasing implication:** launch-day server authority is nearly free — lock the mint APIs (configuration), let the validator write match outcomes (already deployed), and lean on snap-enforced conditions for everything else. The proposed meta-game service becomes load-bearing only when rewarded-ad verification, pity systems, or mission rotation beyond the Scheduler's reach arrive — and its player-facing volume is claims per day, not actions per move, so it stays small next to the validator.

## References
_None._

## Child pages
_None._
