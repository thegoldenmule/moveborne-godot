@tool
extends McpTestSuite

## Full-pipeline integration parity: a mixed action sequence (card play, totem
## spawn, swipes) on a board with active tile effects (amplify/black-hole/lock)
## and active totems (momentum idol/scavenger/combo saver), threaded through the
## integrated engine and asserted against the TS oracle
## (tests/golden/combined_golden.json via generate_combined_golden.mjs).

const GOLDEN := "res://tests/golden/combined_golden.json"
const MbEngineS := preload("res://logic/engine.gd")

var _g: Dictionary = {}


func suite_name() -> String:
	return "combined"


func suite_setup(_ctx: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN):
		fail_setup("missing golden: " + GOLDEN)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	if typeof(parsed) != TYPE_DICTIONARY:
		fail_setup("golden parse failed")
		return
	_g = parsed


func test_combined_pipeline() -> void:
	var state: Dictionary = _g["initial"]
	var steps: Array = _g["steps"]
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		var res: Dictionary = {}
		match s["kind"]:
			"swipe": res = MbEngineS.step(state, s["dir"])
			"card": res = MbEngineS.step_card(state, s["action"], s["params"], int(s["cardIndex"]))
			"totem": res = MbEngineS.step_totem(state, s["totemType"], int(s["cardIndex"]))
		assert_eq(res["hash"], s["hash"], "step %d kind=%s mismatch" % [i, s["kind"]])
		state = res["state"]
