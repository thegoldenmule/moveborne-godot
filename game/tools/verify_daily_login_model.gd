extends SceneTree

## Headless verifier for MbDailyLogin — the pure Daily Login calendar model:
##   godot --headless --path . --script res://tools/verify_daily_login_model.gd
## Covers is_enabled, cycle_length, day_for_level wrapping, claimed_in_cycle /
## today_day, day_state, calendar_entry fallback, format_reward, and the strip
## (length == cycle, exactly one TODAY cell, the claimed/upcoming split). No Node /
## network deps — the same surface the runtime panel renders from.

const Model := preload("res://ui/screens/daily_login_model.gd")

var _ok := true

const BLOCK := {
	"enabled": true, "version": 1, "cycle_length_days": 7, "reset_on_miss": false,
	"calendar": [
		{"day": 1, "currency": "coins", "amount": 50},
		{"day": 2, "currency": "coins", "amount": 75},
		{"day": 3, "currency": "coins", "amount": 100},
		{"day": 4, "currency": "coins", "amount": 150},
		{"day": 5, "currency": "coins", "amount": 200},
		{"day": 6, "currency": "coins", "amount": 300},
		{"day": 7, "currency": "gems", "amount": 20}]}


func _initialize() -> void:
	# enabled / disabled
	_check("is_enabled true on an enabled block", Model.is_enabled(BLOCK))
	_check("is_enabled false when disabled", not Model.is_enabled({"enabled": false}))
	_check("is_enabled false on {}", not Model.is_enabled({}))

	# cycle length
	_check("cycle_length reads the block", Model.cycle_length(BLOCK) == 7)
	_check("cycle_length defaults to 7", Model.cycle_length({}) == Model.DEFAULT_CYCLE)
	_check("cycle_length clamps to >= 1", Model.cycle_length({"cycle_length_days": 0}) == 1)

	# day_for_level — wraps on the cycle
	_check("day_for_level 1 -> day 1", Model.day_for_level(1, 7) == 1)
	_check("day_for_level 7 -> day 7", Model.day_for_level(7, 7) == 7)
	_check("day_for_level 8 wraps -> day 1", Model.day_for_level(8, 7) == 1)
	_check("day_for_level 0 -> 0 (nothing granted)", Model.day_for_level(0, 7) == 0)

	# claimed_in_cycle / today_day
	_check("today_day at level 0 is day 1", Model.today_day(0, 7) == 1)
	_check("today_day at level 3 is day 4", Model.today_day(3, 7) == 4)
	_check("today_day wraps at a full cycle", Model.today_day(7, 7) == 1)
	_check("claimed_in_cycle at level 3 is 3", Model.claimed_in_cycle(3, 7) == 3)

	# day_state at level 3 (days 1-3 claimed, day 4 today, day 5+ upcoming)
	_check("day_state CLAIMED for a past day", Model.day_state(2, 3, 7) == Model.DayState.CLAIMED)
	_check("day_state TODAY for the current day", Model.day_state(4, 3, 7) == Model.DayState.TODAY)
	_check("day_state UPCOMING for a future day", Model.day_state(5, 3, 7) == Model.DayState.UPCOMING)

	# calendar_entry + fallback
	var e := Model.calendar_entry(BLOCK, 7)
	_check("calendar_entry reads currency + amount", str(e["currency"]) == "gems" and int(e["amount"]) == 20)
	var fb := Model.calendar_entry(BLOCK, 99)
	_check("calendar_entry falls back for an unknown day", int(fb["amount"]) == 0)

	# format_reward
	_check("format_reward renders +N currency",
		Model.format_reward({"currency": "coins", "amount": 50}) == "+50 coins")

	# strip structure — what the panel renders
	var strip := Model.strip(BLOCK, 3)
	_check("strip length == cycle", strip.size() == 7)
	var todays := 0
	var claimed := 0
	for cell in strip:
		match int(cell["state"]):
			Model.DayState.TODAY: todays += 1
			Model.DayState.CLAIMED: claimed += 1
	_check("strip has exactly one TODAY cell", todays == 1)
	_check("strip CLAIMED count == claimed_in_cycle", claimed == Model.claimed_in_cycle(3, 7))
	_check("strip is empty when disabled", Model.strip({"enabled": false}, 0).is_empty())

	print("VERIFY daily_login_model: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
