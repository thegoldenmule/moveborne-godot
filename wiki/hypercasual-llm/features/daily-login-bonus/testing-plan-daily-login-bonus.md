# Testing plan — Daily Login Bonus

**Status:** draft

## Planned
- Fresh user: open app, claim — assert wallet +day-1 amount and login_calendar level = 1.
- Same user, next daily period: claim — assert wallet +day-2 amount and level = 2 (escalation works).
- Skip a day, then claim — assert progress paused, not reset: the level advances from where it left off (pause-and-continue).
- Reach the final day and claim once more — assert auto-reset loops the ladder back to day 1.
- Same-day double-claim attempt — assert the recurring quest blocks a second claim within the same daily period.

## Passed
_None._

## Failed
_None._

## References
_None._

## Child pages
_None._
