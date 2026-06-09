@tool
extends McpTestSuite

## Phase 1 spine parity gate: thread the golden's initial state through the
## GDScript engine and assert every per-move state hash matches the TS oracle
## (tests/golden/engine_swipe_golden.json, produced by generate_engine_golden.mjs
## from the real @spyre-io/moveborne-logic dist).

const GOLDEN := "res://tests/golden/engine_swipe_golden.json"
const MbEngineS := preload("res://logic/engine.gd")

var _g: Dictionary = {}


func suite_name() -> String:
	return "engine_swipe"


func suite_setup(_ctx: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN):
		fail_setup("missing golden: " + GOLDEN)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	if typeof(parsed) != TYPE_DICTIONARY:
		fail_setup("golden parse failed")
		return
	_g = parsed


func test_swipe_sequence_hashes() -> void:
	var state: Dictionary = _g["initial"]
	var steps: Array = _g["steps"]
	for i in range(steps.size()):
		var sg: Dictionary = steps[i]
		var dir: String = sg["dir"]
		var res := MbEngineS.step(state, dir)
		assert_eq(
			res["hash"], sg["hash"],
			"step %d dir=%s hash mismatch | scoreAdded got=%s want=%s | cardDrawn got=%s want=%s" % [
				i, dir, str(res["scoreAdded"]), str(sg["scoreAdded"]), str(res["cardDrawn"]), str(sg["cardDrawn"])
			]
		)
		state = res["state"]


func test_metadata_sanity() -> void:
	# Guard the golden itself: 20 steps, cards drawn at 4 and 15.
	assert_eq((_g["steps"] as Array).size(), 20, "expected 20 golden steps")
	var draws := []
	var steps: Array = _g["steps"]
	for i in range(steps.size()):
		if steps[i]["cardDrawn"]:
			draws.append(i)
	assert_eq(draws, [4, 15], "expected card draws at steps 4 and 15")
