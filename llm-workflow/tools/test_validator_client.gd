extends SceneTree

## Headless end-to-end check of MbValidatorClient against a running validator
## (DEV_MODE on :5055):  init -> connect -> ready -> validate_action -> expect MATCH.
##   godot --headless --path . --script res://tools/test_validator_client.gd

const ClientS := preload("res://net/validator_client.gd")
const MbEngineS := preload("res://logic/engine.gd")

var _client
var _done := false


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var starting := _make_state()
	_client = ClientS.new()
	root.add_child(_client)
	_client.ready_received.connect(func(_cur): _on_ready(starting))
	_client.action_validated.connect(_on_validated)
	_client.validator_error.connect(func(m): _fail("validator_error: " + m))
	_client.init_and_connect("http://localhost:5055", "m_gd_1", starting, "p_gd")
	create_timer(10.0).timeout.connect(func(): _fail("timeout"))


func _on_ready(starting: Dictionary) -> void:
	var pre_index := int(starting["moveIndex"])
	var res := MbEngineS.step(starting, "left")
	print("[gd] ready; predicted hash=%s scoreAdded=%s" % [str(res["hash"]).substr(0, 16), str(res["scoreAdded"])])
	_client.validate_action(pre_index, {"type": "SWIPE", "payload": {"direction": "left"}}, res["hash"])


func _on_validated(index: int, matched: bool, _state) -> void:
	print("[gd] validate_action(index=%d) -> %s" % [index, "MATCH" if matched else "MISMATCH"])
	_finish(matched)


func _make_state() -> Dictionary:
	var tiles := []
	for r in range(4):
		for c in range(4):
			tiles.append(MbEngineS.create_empty_tile(r, c))
	tiles[0] = {"isEmpty": false, "value": 2, "row": 0, "col": 0, "status": "normal", "meta": {}}
	tiles[1] = {"isEmpty": false, "value": 2, "row": 0, "col": 1, "status": "normal", "meta": {}}
	return {
		"board": {"tiles": tiles, "size": 4}, "hand": {"cards": []}, "deck": {"remainingCards": 12, "nextCardIndex": 0},
		"score": 0, "shards": 0, "combo": 0, "comboMultiplier": 1, "totems": {"active": []}, "moveIndex": 0,
		"randomSeeds": {"tile-gen": 4242, "shuffle": 4243, "effect-spawn": 4244, "totem-spawn": 4245, "card-draw": 4246},
		"rngIndices": {"tile-gen": 0, "shuffle": 0, "effect-spawn": 0, "totem-spawn": 0, "card-draw": 0},
	}


func _fail(msg: String) -> void:
	if _done:
		return
	print("[gd] FAIL: " + msg)
	_finish(false)


func _finish(ok: bool) -> void:
	if _done:
		return
	_done = true
	print("VALIDATOR GD TEST: " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
