extends SceneTree

## Headless integration check for execute_play_card_action / step_card:
##   godot --headless --path . --script res://tools/verify_playcard.gd

func _initialize() -> void:
	var eng := load("res://engine/engine.gd")
	var arr: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/playcard_golden.json"))
	var ok := true
	var n := 0
	for cs in arr:
		var res: Dictionary = eng.step_card(cs["state"], cs["action"], cs["params"], int(cs["cardIndex"]))
		n += 1
		if res["hash"] != cs["hash"] or res["success"] != cs["success"]:
			print("FAIL %s: hash got=%s want=%s | success got=%s want=%s" % [cs["action"], res["hash"], cs["hash"], str(res["success"]), str(cs["success"])])
			ok = false
			break
	print("VERIFY playcard: %s (%d cases)" % ["PASS" if ok else "FAIL", n])
	quit(0 if ok else 1)
