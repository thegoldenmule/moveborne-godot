extends SceneTree

## Standalone headless parity harness (no editor required), for CI and for
## workflow agents to self-verify a port without contending on the live editor:
##   godot --headless --path . --script res://tools/verify_engine_swipe.gd

func _initialize() -> void:
	var eng := load("res://engine/engine.gd")
	var txt := FileAccess.get_file_as_string("res://tests/golden/engine_swipe_golden.json")
	var g: Dictionary = JSON.parse_string(txt)
	var state: Dictionary = g["initial"]
	var steps: Array = g["steps"]
	var ok := true
	for i in range(steps.size()):
		var sg: Dictionary = steps[i]
		var res: Dictionary = eng.step(state, sg["dir"])
		if res["hash"] != sg["hash"]:
			print("FAIL step %d dir=%s got=%s want=%s" % [i, sg["dir"], res["hash"], sg["hash"]])
			ok = false
			break
		state = res["state"]
	print("VERIFY: %s (%d steps)" % ["PASS" if ok else "FAIL", steps.size()])
	quit(0 if ok else 1)
