extends SceneTree

## Headless checks for the Daily Missions feature's pure helpers and that all its
## new scripts/scenes compile + load offline.
##   godot --headless --path . --script res://tools/verify_daily_missions.gd
##
## The live Quests/Remote-Config snaps (gateway round-trip) are NOT covered here —
## they require the quests provisioned on the snapend and are verified by a gateway
## smoke/e2e pass, like the leaderboards/profile clients. Prints
## VERIFY daily_missions: PASS/FAIL (N checks); exit 0/1.

const Quests := preload("res://net/quests_client.gd")
const Model := preload("res://ui/screens/daily_missions_model.gd")
const RcClient := preload("res://net/remote_config_client.gd")
const Auth := preload("res://net/snapser_auth.gd")
const GameStateS := preload("res://ui/game_state.gd")

var _ok := true
var _n := 0


func _check(cond: bool, msg: String) -> void:
	_n += 1
	if not cond:
		_ok = false
		print("FAIL: %s" % msg)


func _initialize() -> void:
	_run()


## Async so freshly-added nodes get a frame for their deferred _ready() before the
## instantiate/render checks (same reason verify_ui_driver awaits a frame).
func _run() -> void:
	_test_quests_urls()
	_test_parse_active_quests()
	_test_parse_claim()
	_test_is_claimable()
	_test_model_rotation()
	_test_model_states_badge()
	_test_model_countdown()
	_test_progress_fraction()
	_test_remote_config_daily()
	_test_game_state_daily()
	_test_coachmark_decision()
	await _test_compiles()
	print("VERIFY daily_missions: %s (%d checks)" % ["PASS" if _ok else "FAIL", _n])
	quit(0 if _ok else 1)


func _test_quests_urls() -> void:
	var g := Auth.GATEWAY
	_check(Quests.active_quests_url("u1", "daily_mission") ==
		g + "/v1/quests/users/u1/active_quests?include_reward_contents=true&tags=daily_mission",
		"active_quests_url builds the swagger path with the tag filter")
	_check(Quests.active_quests_url("u1") ==
		g + "/v1/quests/users/u1/active_quests?include_reward_contents=true",
		"active_quests_url with no tag omits the filter")
	_check(Quests.assign_url("u1", "mission_win_2") ==
		g + "/v1/quests/users/u1/quests/mission_win_2/assign", "assign_url targets the owner path")
	_check(Quests.increment_url("u1", "mission_win_2", "win_matches") ==
		g + "/v1/quests/users/u1/quests/mission_win_2/tasks/win_matches", "increment_url targets the task")
	_check(Quests.claim_url("u1", "mission_win_2") ==
		g + "/v1/quests/users/u1/quests/mission_win_2/claim_rewards", "claim_url targets claim_rewards")
	var body = JSON.parse_string(Quests.increment_body(3))
	_check(body is Dictionary and int(body.get("delta", 0)) == 3 and int(body.get("delta64", 0)) == 3,
		"increment_body emits both delta and delta64")


func _test_parse_active_quests() -> void:
	var payload := {
		"quests": {
			"mission_anchor_play_3": {
				"status": "active", "resets_at": "1700000000", "tags": ["daily_mission", "anchor"],
				"tasks": {"play_matches": {
					"completed": false, "current_progress_64": "1", "goal_64": "3",
					"current_progress": 1, "goal": 3}},
				"reward_currencies": [{"name": "coins", "count": 100, "count_64": "100"}],
			},
			"mission_win_2": {
				"status": "completed", "resets_at": 1700000500, "tags": ["daily_mission", "pool"],
				"tasks": {"win_matches": {"completed": true, "current_progress_64": "2", "goal_64": "2"}},
				"reward_currencies": [{"name": "coins", "count_64": "150"}],
			},
		},
	}
	var quests: Array = Quests.parse_active_quests(payload)
	_check(quests.size() == 2, "both quests parsed from the questsUserQuests map")
	var by_name := {}
	for q in quests:
		by_name[q["name"]] = q
	var anchor: Dictionary = by_name.get("mission_anchor_play_3", {})
	_check(int(anchor.get("resets_at", 0)) == 1700000000, "resets_at parses from an int64 STRING")
	_check(anchor.get("tags", []) == ["daily_mission", "anchor"], "tags surfaced")
	_check(anchor.get("tasks", [])[0]["progress"] == 1 and anchor.get("tasks", [])[0]["goal"] == 3,
		"task progress/goal read from the *_64 fields")
	_check(int(anchor.get("reward", {}).get("coins", 0)) == 100, "reward currency summed (count_64)")
	var win: Dictionary = by_name.get("mission_win_2", {})
	_check(int(win.get("resets_at", 0)) == 1700000500, "resets_at parses from an int64 NUMBER")
	_check(int(win.get("reward", {}).get("coins", 0)) == 150, "reward sums even without count_64-vs-count drift")
	_check(Quests.parse_active_quests(null) == [], "non-dict payload -> empty")
	_check(Quests.parse_active_quests({"quests": "nope"}) == [], "non-dict quests map -> empty")


func _test_parse_claim() -> void:
	_check(Quests.parse_claim({"currencies_granted_64": {"coins": "150"}}) == {"coins": 150},
		"parse_claim reads currencies_granted_64")
	_check(Quests.parse_claim({"currencies_granted_64": {"coins": "150"}, "currencies_granted": {"coins": 999}})
		== {"coins": 150}, "the int64-string map wins over the deprecated int map")
	_check(Quests.parse_claim({"currencies_granted": {"souls": 5}}) == {"souls": 5},
		"falls back to currencies_granted when no _64 map")
	_check(Quests.parse_claim({"currencies_granted_64": {"doubloons": "9"}}) == {},
		"unknown currencies dropped")
	_check(Quests.parse_claim(null) == {} and Quests.parse_claim({}) == {}, "garbage -> empty")


func _test_is_claimable() -> void:
	var done := {"status": "completed", "tasks": [{"completed": true}]}
	var claimed := {"status": "rewards_claimed", "tasks": [{"completed": true}]}
	var prog := {"status": "active", "tasks": [{"completed": false}]}
	_check(Quests.is_claimable(done), "completed + unclaimed is claimable")
	_check(not Quests.is_claimable(claimed), "already-claimed is not claimable")
	_check(not Quests.is_claimable(prog), "in-progress is not claimable")


func _test_model_rotation() -> void:
	var block := {
		"enabled": true, "anchor": "mission_anchor_play_3",
		"by_weekday": {"1": ["mission_play_5", "mission_combo_5", "mission_score_5k"]},
		"catalog": {"mission_play_5": {"title": "Marathon", "desc": "Play 5", "reward": "150 coins"}},
	}
	# utc_weekday wraps Godot's Time; 1700000000 is Tue 2023-11-14 UTC -> weekday 2.
	_check(Model.utc_weekday(1700000000) == 2, "utc_weekday returns 0(Sun)..6(Sat)")
	_check(Model.todays_mission_names(block, 1) ==
		["mission_anchor_play_3", "mission_play_5", "mission_combo_5", "mission_score_5k"],
		"todays_mission_names = anchor + the weekday's pool subset")
	_check(Model.todays_mission_names(block, 5) == ["mission_anchor_play_3"],
		"a weekday with no pool entry still shows the anchor")
	_check(Model.todays_mission_names({"enabled": false, "anchor": "x"}, 1) == [],
		"a disabled block yields no missions")
	var entry := Model.catalog_entry(block, "mission_play_5")
	_check(entry["title"] == "Marathon" and entry["reward"] == "150 coins", "catalog_entry reads display metadata")
	_check(Model.catalog_entry(block, "unknown")["title"] == "unknown",
		"an uncatalogued name falls back to its name as the title")


func _test_model_states_badge() -> void:
	var in_prog := {"status": "active", "tasks": [{"completed": false, "progress": 1, "goal": 3}]}
	var claimable := {"status": "completed", "tasks": [{"completed": true, "progress": 2, "goal": 2}]}
	var claimed := {"status": "rewards_claimed", "tasks": [{"completed": true, "progress": 2, "goal": 2}]}
	_check(Model.card_state(in_prog) == Model.CardState.IN_PROGRESS, "in-progress card state")
	_check(Model.card_state(claimable) == Model.CardState.CLAIMABLE, "claimable card state")
	_check(Model.card_state(claimed) == Model.CardState.CLAIMED, "claimed card state")
	_check(Model.claimable_count([in_prog, claimable, claimed]) == 1, "one claimable in the set")
	_check(Model.badge_state([in_prog, claimable, claimed]) == Model.Badge.COUNT, "claimable -> count badge")
	_check(Model.badge_state([in_prog]) == Model.Badge.DOT, "active-but-none-claimable -> dot")
	_check(Model.badge_state([claimed]) == Model.Badge.NONE, "fully claimed -> no badge")
	_check(Model.badge_state([]) == Model.Badge.NONE, "empty set -> no badge")


func _test_model_countdown() -> void:
	var quests := [{"resets_at": 1000}, {"resets_at": 1500}]
	_check(Model.seconds_to_reset(quests, 800) == 200, "countdown uses the SOONEST reset")
	_check(Model.seconds_to_reset(quests, 1200) == 0, "a passed reset clamps to 0")
	_check(Model.seconds_to_reset([], 800) == 0, "no quests -> 0")
	_check(Model.seconds_to_reset([{"resets_at": 0}], 800) == 0, "no reset value -> 0")
	_check(Model.format_countdown(3661) == "01:01:01", "format_countdown is HH:MM:SS")
	_check(Model.format_countdown(-5) == "00:00:00", "negative clamps to zero")
	_check(Model.is_warning(1800) and not Model.is_warning(7200) and not Model.is_warning(0),
		"warning window is the final hour only")


func _test_progress_fraction() -> void:
	_check(abs(Model.progress_fraction({"tasks": [{"completed": false, "progress": 1, "goal": 3}]}) - (1.0 / 3.0)) < 0.001,
		"partial progress fraction")
	_check(Model.progress_fraction({"tasks": [{"completed": true, "progress": 2, "goal": 2}]}) == 1.0,
		"completed task is full")
	_check(Model.progress_fraction({"tasks": [{"completed": false, "progress": 0, "goal": 0}]}) == 1.0,
		"a zero-goal task counts complete")
	_check(Model.progress_fraction({"tasks": []}) == 0.0, "no tasks -> 0")


func _test_remote_config_daily() -> void:
	var config := {"story_catalog": {"catalog_version": 2}, "daily_missions": {"enabled": true, "anchor": "a"}}
	_check(RcClient.extract_daily_missions(config) == {"enabled": true, "anchor": "a"},
		"daily_missions extracted from the shared app-config doc")
	_check(int(RcClient.extract_catalog(config).get("catalog_version", 0)) == 2,
		"story catalog still extracts alongside daily_missions")
	_check(RcClient.extract_daily_missions({}) == {}, "absent key -> empty")
	_check(RcClient.extract_daily_missions({"daily_missions": "nope"}) == {}, "non-dict block -> empty")


func _test_game_state_daily() -> void:
	var gs = GameStateS.new()
	gs.set_daily_missions({"enabled": true, "anchor": "x"})
	_check(bool(gs.daily_missions.get("enabled", false)), "GameState caches the daily_missions block")
	# Claim grants are DELTAS: add_currencies adds, merge_currencies replaces.
	gs.set_currencies({"coins": 100, "souls": 0, "gems": 0})
	gs.add_currencies({"coins": 150})
	_check(int(gs.currencies["coins"]) == 250, "add_currencies ADDS a claim delta to the wallet")
	gs.merge_currencies({"coins": 160})
	_check(int(gs.currencies["coins"]) == 160, "merge_currencies REPLACES (validator full-total ack)")
	gs.free()


func _test_coachmark_decision() -> void:
	_check(Model.should_show_coachmark(false, true), "unseen + visible -> show the coachmark")
	_check(not Model.should_show_coachmark(true, true), "already-seen -> never show again")
	_check(not Model.should_show_coachmark(false, false), "hidden sigil -> no coachmark")


func _test_compiles() -> void:
	var sigil = load("res://ui/shell/daily_sigil.gd")
	_check(sigil != null, "daily_sigil.gd compiles")
	var panel = load("res://ui/screens/daily_missions_panel.gd")
	_check(panel != null, "daily_missions_panel.gd compiles")
	# The shell (+ currency bar) carry the integration edits — loading the scene
	# parses the attached scripts, so a syntax error there fails this check.
	_check(load("res://ui/shell/app_shell.tscn") != null, "app_shell scene + script compile")
	_check(load("res://ui/shell/currency_bar.gd") != null, "currency_bar.gd compiles")
	_check(load("res://net/quests_client.gd") != null, "quests_client.gd compiles")
	# Instantiate the panel + sigil offline (no auth/quests) — they must build without
	# error. Await a frame so their deferred _ready() (and _build) runs first.
	var pinst = panel.new()
	get_root().add_child(pinst)
	var inst = sigil.new()
	get_root().add_child(inst)
	await process_frame
	pinst.render({"enabled": true, "anchor": "a", "catalog": {}}, [], 0)
	_check(is_instance_valid(pinst), "panel builds + renders an empty set without error")
	_check(is_instance_valid(inst), "daily sigil builds offline (no session) without error")
	# No session: requesting the Home surface must leave the sigil hidden/inert (no
	# dead entry point) — the offline half of the flag-off/offline case.
	inst.set_surface(true, "home")
	await process_frame
	_check(not inst.visible, "with no session the sigil stays hidden on the Home surface")
	var cm = inst.get_node_or_null("SigilRoot/Coachmark")
	_check(cm != null and not cm.visible, "the FTUE coachmark stays hidden while the sigil is hidden")
	pinst.free()
	inst.free()
