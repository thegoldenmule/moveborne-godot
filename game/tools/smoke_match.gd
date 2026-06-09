extends SceneTree

## Headless smoke for the playable match loop (MbMatch):
##   godot --headless --path . --script res://tools/smoke_match.gd

func _initialize() -> void:
	var m = load("res://game/match_controller.gd").new()
	m.new_game(999)
	var tiles: Array = m.state["board"]["tiles"]
	var nonempty := 0
	for t in tiles:
		if not bool(t["isEmpty"]):
			nonempty += 1
	var ok_start := nonempty == 2
	print("new_game: %d starting tiles (expect 2) -> %s" % [nonempty, "OK" if ok_start else "FAIL"])

	var mi0 := int(m.state["moveIndex"])
	for d in ["left", "up", "right", "down", "left", "up", "right", "down", "left", "down"]:
		m.swipe(d)
	var mi1 := int(m.state["moveIndex"])
	var advanced := mi1 > mi0
	print("after swipes: moveIndex %d -> %d (advanced=%s)  score=%d  shards=%d" % [mi0, mi1, advanced, int(m.state["score"]), int(m.state["shards"])])

	print("SMOKE: %s" % ["PASS" if (ok_start and advanced) else "FAIL"])
	quit(0 if (ok_start and advanced) else 1)
