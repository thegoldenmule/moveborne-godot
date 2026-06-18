class_name MbDailyLogin
extends RefCounted

## Pure presentation logic for the Daily Login Bonus calendar, shared by the
## runtime login-bonus panel and the editor's validate()/preview. No Node /
## network / scene deps, so the whole surface is headless-testable
## (tools/verify_daily_login_service.gd + tests/test_daily_login_model.gd) — the
## same "static helpers" discipline as MbDailyMissions and the *_client.gd parsers.
##
## Inputs are the Remote Config daily_login block (see the implementation plan's
## JSON data model) and the login_calendar Trackables level (MbTrackablesClient).
## The block is the DISPLAY mirror; the authoritative grant is the ladder, so the
## "level" here is the number of calendar days the player has already claimed.

## The currency wallets a calendar day may grant (mirrors inventory_client.gd /
## quests_client.gd). The ONE allowed-currency set — the single source of truth
## shared by the runtime panel, the editor currency-picker, and the editor's
## validate().
const CURRENCIES := ["coins", "souls", "gems"]

## Per-currency placeholder glyph (pending generated art) + the render-time
## fallback under the "" key. Lets the strip show a coin/soul/gem mark without
## hardcoding it in the panel.
const CURRENCY_GLYPHS := {
	"coins": "◉", "souls": "✦", "gems": "◆", "": "◈",
}

const DEFAULT_CYCLE := 7

## A calendar cell, relative to the player's ladder position: already granted,
## the one claimable today, or a future day previewed in the strip.
enum DayState { CLAIMED, TODAY, UPCOMING }


## True when the feature is configured on and switched on.
static func is_enabled(block: Dictionary) -> bool:
	return block is Dictionary and bool(block.get("enabled", false))


## The configured cycle length (number of calendar days), clamped to >= 1.
static func cycle_length(block: Dictionary) -> int:
	if not (block is Dictionary):
		return DEFAULT_CYCLE
	return maxi(1, int(block.get("cycle_length_days", DEFAULT_CYCLE)))


## Whether a missed day resets the calendar to day 1 (the punishing variant) or
## simply pauses (the launch default). Display-only here; the authoritative reset
## behavior lives in the ladder's auto_reset config.
static func reset_on_miss(block: Dictionary) -> bool:
	return block is Dictionary and bool(block.get("reset_on_miss", false))


## Sorted calendar day numbers present in the block ([] when absent/malformed).
static func days(block: Dictionary) -> Array:
	var out: Array = []
	var cal = block.get("calendar", []) if block is Dictionary else []
	if cal is Array:
		for e in cal:
			if e is Dictionary and e.has("day"):
				out.append(int(e.get("day", 0)))
	out.sort()
	return out


## The 1-based calendar day a given ladder LEVEL maps to, wrapping on the cycle so
## the ladder loops (auto_reset on_max): level 1 -> day 1, level cycle -> day
## cycle, level cycle+1 -> day 1. Level <= 0 -> 0 (nothing granted yet).
static func day_for_level(level: int, cycle: int) -> int:
	cycle = maxi(1, cycle)
	if level <= 0:
		return 0
	return ((level - 1) % cycle) + 1


## How many days the player has already claimed in the CURRENT cycle (0..cycle-1).
static func claimed_in_cycle(level: int, cycle: int) -> int:
	cycle = maxi(1, cycle)
	return maxi(0, level) % cycle


## The 1-based day whose reward is claimable today (always in [1, cycle]). It is
## the day immediately after the last one claimed in this cycle.
static func today_day(level: int, cycle: int) -> int:
	return claimed_in_cycle(level, cycle) + 1


## The DayState of a calendar day for a player at `level` (drives strip coloring).
static func day_state(day: int, level: int, cycle: int) -> int:
	var claimed := claimed_in_cycle(level, cycle)
	if day <= claimed:
		return DayState.CLAIMED
	if day == claimed + 1:
		return DayState.TODAY
	return DayState.UPCOMING


## A calendar day's reward fields from the block, with safe fallbacks so the strip
## never renders a blank cell. Returns {day, currency, amount}.
static func calendar_entry(block: Dictionary, day: int) -> Dictionary:
	var cal = block.get("calendar", []) if block is Dictionary else []
	if cal is Array:
		for e in cal:
			if e is Dictionary and int(e.get("day", 0)) == day:
				return {
					"day": day,
					"currency": str(e.get("currency", "coins")),
					"amount": int(e.get("amount", 0)),
				}
	return {"day": day, "currency": "coins", "amount": 0}


## "+50 coins" — the reward chip label for a calendar entry.
static func format_reward(entry: Dictionary) -> String:
	return "+%d %s" % [int(entry.get("amount", 0)), str(entry.get("currency", "coins"))]


## The full strip to render: one row per calendar day 1..cycle, each
## {day, currency, amount, state}. Empty when the feature is disabled.
static func strip(block: Dictionary, level: int) -> Array:
	if not is_enabled(block):
		return []
	var cycle := cycle_length(block)
	var out: Array = []
	for d in range(1, cycle + 1):
		var entry := calendar_entry(block, d)
		entry["state"] = day_state(d, level, cycle)
		out.append(entry)
	return out
