# Testing plan — Daily Missions

**Status:** draft

## Planned
- Assign today's set (Tier 1 cron or Tier 2 config): assert anchor + the expected weekday missions are active.
- Progress a statistic goal via a validator match result: assert the mission advances server-side with no client write.
- Complete and claim a mission: assert the wallet credited and the mission marked claimed.
- Cross the midnight cron boundary with an unclaimed completed mission: assert the reward is no longer claimable (claim-before-reset) and the set refreshed.
- Confirm the anchor mission is present every day across a full rotation cycle.

## Passed
_None._

## Failed
_None._

## References
_None._

## Child pages
_None._
