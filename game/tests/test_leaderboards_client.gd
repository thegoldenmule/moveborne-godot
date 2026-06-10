@tool
extends McpTestSuite

## MbLeaderboardsClient pure helpers: URL/body construction against the swagger
## (snapser-docs/swagger/leaderboards.swagger3.json), response parsing with JSON
## int/float ambiguity, and the post-match submission gate. No network — the
## live snap is covered by the gateway smoke + e2e passes.

const LbClient := preload("res://net/leaderboards_client.gd")
const AuthS := preload("res://net/snapser_auth.gd")


func suite_name() -> String:
	return "leaderboards_client"


func test_scores_url_top() -> void:
	var url: String = LbClient.scores_url(LbClient.BOARD_DAILY, "top", 10)
	assert_eq(url,
		AuthS.GATEWAY + "/v1/leaderboards/leaderboards/moveborne-daily" +
		"?range=top&count=10&with_metadata=true",
		"GetScores top-10 URL matches the swagger path + required query params")


func test_scores_url_around_with_offset() -> void:
	var url: String = LbClient.scores_url(LbClient.BOARD_WEEKLY, "around", 1, "user-123", 2)
	assert_true(url.begins_with(
		AuthS.GATEWAY + "/v1/leaderboards/leaderboards/moveborne-weekly?range=around&count=1"),
		"around-range URL keeps the required range/count params first")
	assert_true(url.contains("&user_id=user-123"), "optional user_id appended")
	assert_true(url.contains("&offset=2"), "recurring-board offset appended")


func test_score_url_and_body() -> void:
	assert_eq(LbClient.score_url(LbClient.BOARD_MONTHLY, "u-1"),
		AuthS.GATEWAY + "/v1/leaderboards/leaderboards/moveborne-monthly/users/u-1/score",
		"SetScore URL targets the caller's own user path")
	var body = JSON.parse_string(LbClient.score_body(4096, "godot-deadbeef"))
	assert_true(body is Dictionary, "body is JSON object")
	assert_eq(int(body.get("score", -1)), 4096,
		"int score survives the JSON double round-trip")
	assert_eq(str(body.get("user_metadata", {}).get("name", "")), "godot-deadbeef",
		"anon username rides along as the display name")


func test_parse_scores_swagger_shape() -> void:
	# Live wire shape (observed against the real snap): rank arrives as a STRING.
	var rows: Array = LbClient.parse_scores({
		"tier": null,
		"user_scores": [
			{"user_id": "a", "rank": "1", "score": 500.0,
				"user_metadata": {"name": "witch"}},
			{"user_id": "b", "rank": 2.0, "score": 300},
		],
	})
	assert_eq(rows.size(), 2, "both entries parsed, server order kept")
	assert_eq(rows[0], {"user_id": "a", "rank": 1, "score": 500, "name": "witch"},
		"string rank and float score normalize to int")
	assert_eq(rows[1], {"user_id": "b", "rank": 2, "score": 300, "name": ""},
		"missing metadata tolerated; float rank cast to int")


func test_parse_scores_garbage() -> void:
	assert_eq(LbClient.parse_scores(null), [], "non-dict payload -> empty")
	assert_eq(LbClient.parse_scores({"user_scores": null}), [],
		"null user_scores -> empty")
	assert_eq(LbClient.parse_scores({"user_scores": ["nope", 3]}), [],
		"non-dict entries skipped")


func test_should_submit_gate() -> void:
	assert_true(LbClient.should_submit(
		{"mode": "story", "lb_submitted": false, "score": 100}),
		"fresh story result submits")
	assert_true(LbClient.should_submit({"mode": "pvp", "score": 50}),
		"pvp results are board-eligible")
	assert_true(not LbClient.should_submit(
		{"mode": "infinite", "lb_submitted": false, "score": 9999}),
		"Infinite stays off shared boards (design authority model)")
	assert_true(not LbClient.should_submit(
		{"mode": "story", "lb_submitted": true, "score": 100}),
		"consumed result never re-submits")
	assert_true(not LbClient.should_submit({"mode": "story", "score": 0}),
		"zero score skipped")
	assert_true(not LbClient.should_submit({}), "empty result skipped")
