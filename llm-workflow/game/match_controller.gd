class_name MbMatch
extends RefCounted

## Local-authoritative match controller: owns the SynchronizedGameState Dictionary
## and advances it through the deterministic engine. This is the offline "mock
## server" path — fully playable with no backend. (Phase 3 swaps this for a
## NetClient that talks to the validator/Nakama.)

const MbEngineS := preload("res://engine/engine.gd")
const MbRandomS := preload("res://engine/random_generator.gd")
const C := preload("res://engine/constants.gd")

signal changed

var state: Dictionary = {}


func new_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi() % 1000000
	var size := C.DEFAULT_BOARD_SIZE
	var tiles := []
	for r in range(size):
		for col in range(size):
			tiles.append(MbEngineS.create_empty_tile(r, col))
	state = {
		"board": {"tiles": tiles, "size": size},
		"hand": {"cards": []},
		"deck": {"remainingCards": C.DECK_SIZE, "nextCardIndex": 0},
		"score": 0, "shards": 0, "combo": 0, "comboMultiplier": 1,
		"totems": {"active": []},
		"moveIndex": 0,
		"randomSeeds": {
			"tile-gen": seed_value, "shuffle": seed_value + 1, "effect-spawn": seed_value + 2,
			"totem-spawn": seed_value + 3, "card-draw": seed_value + 4,
		},
		"rngIndices": {"tile-gen": 0, "shuffle": 0, "effect-spawn": 0, "totem-spawn": 0, "card-draw": 0},
	}
	# Two starting tiles (mirrors a real match start; advances tile-gen RNG).
	var rng := MbRandomS.new(state["randomSeeds"], state["rngIndices"])
	for i in range(2):
		state = MbEngineS.add_random_tile_with_effects(state, rng)["gameState"]
	state["rngIndices"] = rng.get_indices()
	changed.emit()


## Apply a swipe. Returns whether any tile moved. The engine still produces a new
## state (and spawns a tile) on a non-moving swipe, matching Moveborne behavior.
func swipe(direction: String) -> bool:
	var res := MbEngineS.step(state, direction)
	state = res["state"]
	changed.emit()
	return res["moved"]


func play_card(action: String, params: Dictionary, card_index: int) -> bool:
	var res := MbEngineS.step_card(state, action, params, card_index)
	state = res["state"]
	changed.emit()
	return res["success"]
