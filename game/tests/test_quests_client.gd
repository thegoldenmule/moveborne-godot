@tool
extends McpTestSuite

## MbQuestsClient pure helpers: URL/body construction against the Quests swagger
## (snapser-docs/swagger/quests.swagger3.json), response parsing with the *_64
## int64-as-string convention + JSON int/float ambiguity, the claim-grant parse,
## and the claimable predicate. No network — the live snap is covered by a gateway
## e2e pass, like the leaderboards/profile clients.

const Quests := preload("res://net/quests_client.gd")
const AuthS := preload("res://net/snapser_auth.gd")


func suite_name() -> String:
	return "quests_client"


func test_urls_and_body() -> void:
	var g := AuthS.GATEWAY
	assert_eq(Quests.active_quests_url("u1", "daily_mission"),
		g + "/v1/quests/users/u1/active_quests?include_reward_contents=true&tags=daily_mission",
		"GetActiveQuests URL matches the swagger path with the tag filter")
	assert_eq(Quests.active_quests_url("u1"),
		g + "/v1/quests/users/u1/active_quests?include_reward_contents=true",
		"no tag omits the filter")
	assert_eq(Quests.assign_url("u1", "mission_win_2"),
		g + "/v1/quests/users/u1/quests/mission_win_2/assign", "AssignQuest URL")
	assert_eq(Quests.increment_url("u1", "mission_win_2", "win_matches"),
		g + "/v1/quests/users/u1/quests/mission_win_2/tasks/win_matches", "IncrementTaskProgress URL")
	assert_eq(Quests.claim_url("u1", "mission_win_2"),
		g + "/v1/quests/users/u1/quests/mission_win_2/claim_rewards", "ClaimQuestRewards URL")
	var body = JSON.parse_string(Quests.increment_body(3))
	assert_true(body is Dictionary, "increment body is JSON object")
	assert_eq(int(body.get("delta", 0)), 3, "delta carried")
	assert_eq(int(body.get("delta64", 0)), 3, "delta64 carried (int64 field)")


func test_parse_active_quests() -> void:
	var quests: Array = Quests.parse_active_quests({"quests": {
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
	}})
	assert_eq(quests.size(), 2, "both quests parsed from the map")
	var by_name := {}
	for q in quests:
		by_name[q["name"]] = q
	var anchor: Dictionary = by_name["mission_anchor_play_3"]
	assert_eq(int(anchor["resets_at"]), 1700000000, "resets_at parsed from int64 STRING")
	assert_eq(anchor["tags"], ["daily_mission", "anchor"], "tags surfaced")
	assert_eq(int(anchor["tasks"][0]["progress"]), 1, "progress from current_progress_64")
	assert_eq(int(anchor["tasks"][0]["goal"]), 3, "goal from goal_64")
	assert_eq(int(anchor["reward"]["coins"]), 100, "reward summed from reward_currencies")
	assert_eq(int(by_name["mission_win_2"]["resets_at"]), 1700000500, "resets_at parsed from int64 NUMBER")


func test_parse_active_quests_garbage() -> void:
	assert_eq(Quests.parse_active_quests(null), [], "non-dict payload -> empty")
	assert_eq(Quests.parse_active_quests({"quests": "nope"}), [], "non-dict quests map -> empty")
	assert_eq(Quests.parse_active_quests({"quests": {"x": "nope"}}), [], "non-dict quest entries skipped")


func test_parse_claim() -> void:
	assert_eq(Quests.parse_claim({"currencies_granted_64": {"coins": "150"}}), {"coins": 150},
		"reads currencies_granted_64 (int64-string map)")
	assert_eq(Quests.parse_claim({"currencies_granted_64": {"coins": "150"}, "currencies_granted": {"coins": 999}}),
		{"coins": 150}, "the _64 map wins over the deprecated int map")
	assert_eq(Quests.parse_claim({"currencies_granted": {"souls": 5}}), {"souls": 5},
		"falls back to currencies_granted")
	assert_eq(Quests.parse_claim({"currencies_granted_64": {"doubloons": "9"}}), {},
		"unknown currencies dropped")
	assert_eq(Quests.parse_claim(null), {}, "non-dict payload -> empty")


func test_is_claimable() -> void:
	assert_true(Quests.is_claimable({"status": "unclaimed", "tasks": [{"completed": true}]}),
		"unclaimed (task done, reward waiting) is claimable")
	assert_true(not Quests.is_claimable({"status": "completed", "tasks": [{"completed": true}]}),
		"completed (reward already claimed) is not claimable")
	assert_true(not Quests.is_claimable({"status": "assigned", "tasks": [{"completed": false}]}),
		"assigned (in progress) is not claimable")
