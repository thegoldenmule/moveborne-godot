extends SceneTree

## Combined integration check — effects (amplify/black-hole/lock) + totems
## (momentum idol/scavenger/combo saver) + card play + totem spawn, threaded
## through the full pipeline:
##   godot --headless --path . --script res://tools/verify_combined.gd

func _initialize() -> void:
	var eng := load("res://engine/engine.gd")
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/combined_golden.json"))
	var state: Dictionary = g["initial"]
	var steps: Array = g["steps"]
	var ok := true
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		var res: Dictionary = {}
		match s["kind"]:
			"swipe": res = eng.step(state, s["dir"])
			"card": res = eng.step_card(state, s["action"], s["params"], int(s["cardIndex"]))
			"totem": res = eng.step_totem(state, s["totemType"], int(s["cardIndex"]))
		var tag = s.get("dir", s.get("action", s.get("totemType", "?")))
		if res["hash"] != s["hash"]:
			print("FAIL step %d %s:%s got=%s want=%s" % [i, s["kind"], str(tag), res["hash"], s["hash"]])
			ok = false
			break
		state = res["state"]
	print("VERIFY combined: %s (%d steps)" % ["PASS" if ok else "FAIL", steps.size()])
	quit(0 if ok else 1)
