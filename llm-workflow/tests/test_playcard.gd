@tool
extends McpTestSuite

## PLAY_CARD integration parity: each golden case runs a card through
## MbEngine.step_card and asserts the resulting state hash matches the TS oracle
## (tests/golden/playcard_golden.json via generate_playcard_golden.mjs).

const GOLDEN := "res://tests/golden/playcard_golden.json"
const MbEngineS := preload("res://engine/engine.gd")

var _cases: Array = []


func suite_name() -> String:
	return "playcard"


func suite_setup(_ctx: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN):
		fail_setup("missing golden: " + GOLDEN)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	if typeof(parsed) != TYPE_ARRAY:
		fail_setup("golden parse failed")
		return
	_cases = parsed


func test_playcard_hashes() -> void:
	for cs in _cases:
		var res := MbEngineS.step_card(cs["state"], cs["action"], cs["params"], int(cs["cardIndex"]))
		assert_eq(res["success"], cs["success"], "card %s success mismatch" % cs["action"])
		assert_eq(res["hash"], cs["hash"], "card %s hash mismatch (scoreAdded got=%s want=%s)" % [cs["action"], str(res["scoreAdded"]), str(cs["scoreAdded"])])
