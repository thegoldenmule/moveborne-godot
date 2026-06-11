extends SceneTree

## Regression check for MbHermesClient re-entrant connect: a SECOND
## init_and_connect on the same client instance (the R-key re-register / "V
## after a prior session" path) must establish a fresh socket and register the
## new match — it previously failed with ERR_ALREADY_IN_USE on the reused peer.
##   godot --headless --path . --script res://tools/test_hermes_reconnect.gd

const ClientS := preload("res://net/hermes_client.gd")
const MbEngineS := preload("res://logic/engine.gd")

var _client
var _done := false
var _round := 0


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	_client = ClientS.new()
	root.add_child(_client)
	_client.ready_received.connect(_on_ready)
	_client.validator_error.connect(func(m): _fail("validator_error: " + m))
	create_timer(12.0).timeout.connect(func(): _fail("timeout"))
	_connect_round()


func _connect_round() -> void:
	_round += 1
	var player := "recon_%d" % _round
	# Same client instance, second time around — must not error on the reused peer.
	_client.init_and_connect("ws://localhost:5555/hermes/ws?token=" + player,
		"m_recon_%d" % _round, _make_state(), player)


func _on_ready(_cur: Dictionary) -> void:
	print("[gd] round %d connected + ready" % _round)
	if _round == 1:
		# Immediately reconnect as a different match/identity.
		_connect_round()
	else:
		print("[gd] reconnect established a fresh socket OK")
		_finish(true)


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
	print("HERMES RECONNECT TEST: " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
