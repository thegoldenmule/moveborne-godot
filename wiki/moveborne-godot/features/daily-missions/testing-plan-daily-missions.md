# Testing plan — Daily Missions

**Status:** draft

## Planned
- Assign today's set (Tier 1 cron or Tier 2 config): assert anchor + the expected weekday missions are active.
- Progress a statistic goal via a validator match result: assert the mission advances server-side with no client write.
- Complete and claim a mission: assert the wallet credited and the mission marked claimed.
- Cross the midnight cron boundary with an unclaimed completed mission: assert the reward is no longer claimable (claim-before-reset) and the set refreshed.

## Passed
- Confirm the anchor mission is present every day across a full rotation cycle.
- UX — sigil presence & badge states: with the feature flag on and a session, the floating Home 'Daily' sigil shows; assert the badge is a claimable-count chip when at least one mission is complete-unclaimed, a soft dot when missions are active but none claimable, and absent when the day is fully claimed.
- UX — open panel & render: tapping the sigil (MbUi flow open_daily_missions) opens the modal; assert the anchor is pinned, the active missions render from the Remote Config catalog (icon/title/desc/reward), and each card's state matches its quest progress.
- UX — claim feedback: claim a completed mission; assert the currency-bar balance updates via GameState.currencies_changed by the reward amount, the card flips to claimed, and the sigil badge decrements; Claim All claims every claimable mission in one action.
- UX — countdown & claim-before-reset prompt: assert the sigil and panel show the UTC reset countdown, the claim-before-reset caption appears whenever something is claimable, and inside the final hour the countdown switches to the amber warning state (with the sigil pulsing if anything is still claimable).
- UX — surfacing on app open: with a claimable reward at risk (first open of the daily period or under 1h to reset) the panel auto-opens on launch; on a normal open it stays closed and only the badge refreshes; the FTUE coachmark shows exactly once on the sigil's first appearance.
- UX — flag-off & offline states: with daily_missions.enabled=false the sigil is hidden and the panel unreachable (no dead entry point); with no Snapser session (including Infinite) the sigil is hidden/inert and offline counter-goal progress cannot be claimed until reconnected.

## Failed
_None._

## References
_None._

## Child pages
_None._
