extends SceneTree

## Headless end-to-end check of the deployed AWARD path (real network):
## anonymous gateway login -> Hermes WSS -> InitMatch -> ValidateAction
## (one swipe worth >= 10 points so the story reward table yields coins)
## -> CompleteMatch -> assert granted=true and the response balances match
## the Inventory wallet read back over REST.
##   godot --headless --path . --script res://tools/test_snapser_grant.gd
## Regression test for bug-report:mq9v48kl-006b-xxqhck (currencies not
## provisioned in the snapend's Inventory snap; granted lied on failure).

const AuthS := preload("res://net/snapser_auth.gd")
const ClientS := preload("res://net/hermes_client.gd")
const InventoryS := preload("res://net/inventory_client.gd")
const MbEngineS := preload("res://logic/engine.gd")

const SNAPSER_HERMES_WS := "wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws"

var _auth
var _client
var _inventory
var _coins_before := 0
var _done := false


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	create_timer(30.0).timeout.connect(func(): _fail("timeout"))
	_auth = AuthS.new()
	root.add_child(_auth)
	var ok: bool = await _auth.ensure_session()
	if not ok:
		_fail("snapser login failed")
		return
	print("[gd] logged in: user_id=%s" % _auth.user_id)

	_inventory = InventoryS.new()
	root.add_child(_inventory)
	var before: Dictionary = await _inventory.fetch_balances(_auth)
	if before.is_empty():
		_fail("wallet read (before) failed")
		return
	_coins_before = int(before["coins"])
	print("[gd] wallet before: %s" % str(before))

	var starting := _make_state()
	_client = ClientS.new()
	root.add_child(_client)
	_client.ready_received.connect(func(_cur): _on_ready(starting))
	_client.action_validated.connect(_on_validated)
	_client.match_completed.connect(_on_completed)
	_client.validator_error.connect(func(m): _fail("validator_error: " + m))
	_client.init_and_connect(SNAPSER_HERMES_WS + "?token=" + _auth.session_token,
		"gd_grant_%d" % (randi() % 1000000), starting, _auth.user_id)


func _on_ready(starting: Dictionary) -> void:
	var pre_index := int(starting["moveIndex"])
	var res := MbEngineS.step(starting, "left")
	print("[gd] ready; post-swipe score=%d" % int(res["state"]["score"]))
	_client.validate_action(pre_index, {"type": "SWIPE", "payload": {"direction": "left"}}, res["hash"])


func _on_validated(index: int, matched: bool, _state) -> void:
	print("[gd] validate_action(index=%d) -> %s" % [index, "MATCH" if matched else "MISMATCH"])
	if not matched:
		_fail("hash mismatch")
		return
	if not _client.complete_match():
		_fail("complete_match refused (client not ready)")


func _on_completed(resp: Dictionary) -> void:
	print("[gd] complete_match -> %s" % str(resp))
	var rewards: Dictionary = resp.get("rewards", {})
	var balances: Dictionary = resp.get("balances", {})
	if not bool(resp.get("granted", false)):
		_fail("granted=false (award did not credit)")
		return
	if not rewards.has("coins") or int(str(rewards["coins"])) <= 0:
		_fail("no coin reward computed (score too low?)")
		return
	var expected := _coins_before + int(str(rewards["coins"]))
	if not balances.has("coins") or int(str(balances["coins"])) != expected:
		_fail("balances.coins=%s, expected %d" % [str(balances.get("coins")), expected])
		return
	var after: Dictionary = await _inventory.fetch_balances(_auth)
	print("[gd] wallet after: %s" % str(after))
	if int(after.get("coins", 0)) != expected:
		_fail("wallet coins=%d, expected %d" % [int(after.get("coins", 0)), expected])
		return
	_finish(true)


## One swipe left merges the two 64s -> 128 points -> coins floor(128/10) = 12.
func _make_state() -> Dictionary:
	var tiles := []
	for r in range(4):
		for c in range(4):
			tiles.append(MbEngineS.create_empty_tile(r, c))
	tiles[0] = {"isEmpty": false, "value": 64, "row": 0, "col": 0, "status": "normal", "meta": {}}
	tiles[1] = {"isEmpty": false, "value": 64, "row": 0, "col": 1, "status": "normal", "meta": {}}
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
	print("SNAPSER GRANT TEST: " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
