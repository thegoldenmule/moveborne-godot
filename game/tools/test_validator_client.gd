extends SceneTree

## Headless end-to-end check of MbHermesClient against a running validator on
## :5555, through its Hermes-emulation WS endpoint (the ?token= param is the
## self-stamped player id):
##   InitMatch -> ValidateAction (MATCH) -> tampered ValidateAction (MISMATCH,
##   authoritative state returned) -> CompleteMatch (settles once).
##   godot --headless --path . --script res://tools/test_validator_client.gd

const ClientS := preload("res://net/hermes_client.gd")
const MbEngineS := preload("res://logic/engine.gd")
const HasherS := preload("res://logic/hasher.gd")

var _client
var _done := false
var _phase := 0
var _state: Dictionary = {}


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	_state = _make_state()
	_client = ClientS.new()
	root.add_child(_client)
	_client.ready_received.connect(_on_ready)
	_client.action_validated.connect(_on_validated)
	_client.match_completed.connect(_on_completed)
	_client.validator_error.connect(func(m): _fail("validator_error: " + m))
	# Local validator has no gateway, so the token IS the player id.
	_client.init_and_connect("ws://localhost:5555/hermes/ws?token=p_gd", "m_gd_1", _state, "p_gd")
	create_timer(10.0).timeout.connect(func(): _fail("timeout"))


func _on_ready(_cur: Dictionary) -> void:
	_phase = 1
	var pre_index := int(_state["moveIndex"])
	var res := MbEngineS.step(_state, "left")
	_state = res["state"]
	print("[gd] ready; predicted hash=%s scoreAdded=%s" % [str(res["hash"]).substr(0, 16), str(res["scoreAdded"])])
	_client.validate_action(pre_index, {"type": "SWIPE", "payload": {"direction": "left"}}, res["hash"])


func _on_validated(index: int, matched: bool, state) -> void:
	print("[gd] validate_action(index=%d) -> %s" % [index, "MATCH" if matched else "MISMATCH"])
	if _phase == 1:
		if not matched:
			_fail("expected MATCH on honest hash")
			return
		# Now claim a bogus hash: the validator must answer MISMATCH and return
		# its authoritative state for adoption.
		_phase = 2
		var pre_index := int(_state["moveIndex"])
		var res := MbEngineS.step(_state, "right")
		_state = res["state"]
		_client.validate_action(pre_index, {"type": "SWIPE", "payload": {"direction": "right"}}, "tampered")
	elif _phase == 2:
		if matched:
			_fail("expected MISMATCH on tampered hash")
			return
		if not (state is Dictionary) or not state.has("board"):
			_fail("mismatch did not return the authoritative state")
			return
		# The authoritative state must hash to what the engine predicted.
		var server_hash: String = HasherS.hash_value(state)
		var local_hash: String = HasherS.hash_value(_state)
		if server_hash != local_hash:
			_fail("authoritative state hash %s != local %s" % [server_hash.substr(0, 12), local_hash.substr(0, 12)])
			return
		print("[gd] mismatch returned authoritative state (hash verified)")
		_phase = 3
		if not _client.complete_match():
			_fail("complete_match refused while ready")


func _on_completed(resp: Dictionary) -> void:
	print("[gd] complete_match -> rewards=%s granted=%s" % [JSON.stringify(resp.get("rewards", {})), str(resp.get("granted"))])
	_finish(_phase == 3)


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
