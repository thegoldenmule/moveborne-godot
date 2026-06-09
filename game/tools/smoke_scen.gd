extends SceneTree
func _initialize():
	var m = load("res://game/match_controller.gd").new()
	for sid in [0,1,4]:
		m.new_game_scenario(sid, 555)
		var cards = m.state["hand"]["cards"].size()
		var hascfg = m.state.has("scenarioConfig")
		var nonempty = 0
		for t in m.state["board"]["tiles"]:
			if not t["isEmpty"]: nonempty += 1
		print("scenario %d (%s): %d cards, %d tiles, scenarioConfig=%s" % [sid, m.scenario_name, cards, nonempty, hascfg])
	# play a card from scenario 1 hand
	m.new_game_scenario(1, 555)
	print("hand before: ", m.state["hand"]["cards"].map(func(c): return c["type"]))
	print("SCEN SMOKE: OK")
	quit(0)
