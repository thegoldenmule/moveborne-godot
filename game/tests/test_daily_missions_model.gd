@tool
extends McpTestSuite

## MbDailyMissions pure presentation logic: weekday rotation selection, card/badge
## states, the reset countdown, and progress fractions. No Node/network deps — the
## same surface the headless tools/verify_daily_missions.gd exercises.

const Model := preload("res://ui/screens/daily_missions_model.gd")

var _block := {
	"enabled": true, "anchor": "mission_anchor_play_3",
	"by_weekday": {"1": ["mission_play_5", "mission_combo_5", "mission_score_5k"]},
	"catalog": {"mission_play_5": {"title": "Marathon", "desc": "Play 5", "reward": "150 coins"}},
}


func suite_name() -> String:
	return "daily_missions_model"


func test_rotation_selection() -> void:
	# 1700000000 is Tue 2023-11-14 UTC -> weekday 2.
	assert_eq(Model.utc_weekday(1700000000), 2, "utc_weekday returns 0(Sun)..6(Sat)")
	assert_eq(Model.todays_mission_names(_block, 1),
		["mission_anchor_play_3", "mission_play_5", "mission_combo_5", "mission_score_5k"],
		"todays set = anchor + the weekday's pool subset")
	assert_eq(Model.todays_mission_names(_block, 5), ["mission_anchor_play_3"],
		"a weekday with no pool entry still shows the anchor")
	assert_eq(Model.todays_mission_names({"enabled": false, "anchor": "x"}, 1), [],
		"a disabled block yields nothing")


func test_catalog_entry() -> void:
	assert_eq(Model.catalog_entry(_block, "mission_play_5")["title"], "Marathon", "catalog title read")
	assert_eq(Model.catalog_entry(_block, "unknown")["title"], "unknown",
		"uncatalogued name falls back to its name")


func test_card_state_and_badge() -> void:
	var in_prog := {"status": "assigned", "tasks": [{"completed": false, "progress": 1, "goal": 3}]}
	var claimable := {"status": "unclaimed", "tasks": [{"completed": true, "progress": 2, "goal": 2}]}
	var claimed := {"status": "completed", "tasks": [{"completed": true, "progress": 2, "goal": 2}]}
	assert_eq(Model.card_state(in_prog), Model.CardState.IN_PROGRESS, "in-progress")
	assert_eq(Model.card_state(claimable), Model.CardState.CLAIMABLE, "claimable")
	assert_eq(Model.card_state(claimed), Model.CardState.CLAIMED, "claimed")
	assert_eq(Model.claimable_count([in_prog, claimable, claimed]), 1, "one claimable")
	assert_eq(Model.badge_state([in_prog, claimable, claimed]), Model.Badge.COUNT, "claimable -> count")
	assert_eq(Model.badge_state([in_prog]), Model.Badge.DOT, "active-but-none-claimable -> dot")
	assert_eq(Model.badge_state([claimed]), Model.Badge.NONE, "fully claimed -> none")
	assert_eq(Model.badge_state([]), Model.Badge.NONE, "empty -> none")


func test_countdown() -> void:
	var quests := [{"resets_at": 1000}, {"resets_at": 1500}]
	assert_eq(Model.seconds_to_reset(quests, 800), 200, "uses the soonest reset")
	assert_eq(Model.seconds_to_reset(quests, 1200), 0, "a passed reset clamps to 0")
	assert_eq(Model.seconds_to_reset([], 800), 0, "no quests -> 0")
	assert_eq(Model.format_countdown(3661), "01:01:01", "HH:MM:SS")
	assert_eq(Model.format_countdown(-5), "00:00:00", "negative clamps")
	assert_true(Model.is_warning(1800), "inside the final hour warns")
	assert_true(not Model.is_warning(7200), "outside the final hour does not warn")
	assert_true(not Model.is_warning(0), "no reset -> no warning")


func test_coachmark_decision() -> void:
	assert_true(Model.should_show_coachmark(false, true), "unseen + visible -> show once")
	assert_true(not Model.should_show_coachmark(true, true), "already seen -> never again")
	assert_true(not Model.should_show_coachmark(false, false), "hidden sigil -> no coachmark")


func test_progress_fraction() -> void:
	assert_true(abs(Model.progress_fraction({"tasks": [{"completed": false, "progress": 1, "goal": 3}]}) - (1.0 / 3.0)) < 0.001,
		"partial progress")
	assert_eq(Model.progress_fraction({"tasks": [{"completed": true, "progress": 2, "goal": 2}]}), 1.0,
		"completed is full")
	assert_eq(Model.progress_fraction({"tasks": []}), 0.0, "no tasks -> 0")
