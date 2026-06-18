@tool
extends McpTestSuite

## MbDailyLogin pure presentation logic: the cycle length, the ladder-level →
## calendar-day mapping (with wrap), today/claimed state, the calendar entry +
## reward formatting, and the render strip. No Node/network deps — the same surface
## the headless tools/verify_daily_login_model.gd exercises.

const Model := preload("res://ui/screens/daily_login_model.gd")

var _block := {
	"enabled": true, "version": 1, "cycle_length_days": 7, "reset_on_miss": false,
	"calendar": [
		{"day": 1, "currency": "coins", "amount": 50},
		{"day": 2, "currency": "coins", "amount": 75},
		{"day": 7, "currency": "gems", "amount": 20}],
}


func suite_name() -> String:
	return "daily_login_model"


func test_enabled_and_cycle() -> void:
	assert_true(Model.is_enabled(_block), "enabled block")
	assert_false(Model.is_enabled({"enabled": false}), "disabled block")
	assert_eq(Model.cycle_length(_block), 7, "cycle_length reads the block")
	assert_eq(Model.cycle_length({}), Model.DEFAULT_CYCLE, "cycle_length defaults")
	assert_eq(Model.cycle_length({"cycle_length_days": 0}), 1, "cycle_length clamps to >= 1")


func test_day_for_level_wraps() -> void:
	assert_eq(Model.day_for_level(1, 7), 1, "level 1 -> day 1")
	assert_eq(Model.day_for_level(7, 7), 7, "level 7 -> day 7")
	assert_eq(Model.day_for_level(8, 7), 1, "level 8 wraps -> day 1")
	assert_eq(Model.day_for_level(0, 7), 0, "level 0 -> nothing granted")


func test_today_and_state() -> void:
	assert_eq(Model.today_day(0, 7), 1, "fresh player -> day 1 today")
	assert_eq(Model.today_day(3, 7), 4, "3 claimed -> day 4 today")
	assert_eq(Model.today_day(7, 7), 1, "full cycle wraps -> day 1")
	assert_eq(Model.day_state(2, 3, 7), Model.DayState.CLAIMED, "past day claimed")
	assert_eq(Model.day_state(4, 3, 7), Model.DayState.TODAY, "current day today")
	assert_eq(Model.day_state(5, 3, 7), Model.DayState.UPCOMING, "future day upcoming")


func test_calendar_entry_and_reward() -> void:
	var e := Model.calendar_entry(_block, 7)
	assert_eq(str(e["currency"]), "gems", "reads currency")
	assert_eq(int(e["amount"]), 20, "reads amount")
	assert_eq(int(Model.calendar_entry(_block, 99)["amount"]), 0, "unknown day falls back to 0")
	assert_eq(Model.format_reward({"currency": "coins", "amount": 50}), "+50 coins", "reward chip text")


func test_strip_structure() -> void:
	var strip := Model.strip(_block, 3)
	assert_eq(strip.size(), 7, "one cell per calendar day")
	var todays := 0
	for cell in strip:
		if int(cell["state"]) == Model.DayState.TODAY:
			todays += 1
	assert_eq(todays, 1, "exactly one TODAY cell")
	assert_true(Model.strip({"enabled": false}, 0).is_empty(), "empty strip when disabled")
