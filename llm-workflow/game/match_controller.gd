class_name MbMatch
extends RefCounted

## Local-authoritative match controller: owns the SynchronizedGameState Dictionary
## and advances it through the deterministic engine. This is the offline "mock
## server" path — fully playable with no backend. (Phase 3 swaps this for a
## NetClient that talks to the validator/Nakama.)

const MbEngineS := preload("res://engine/engine.gd")
const MbRandomS := preload("res://engine/random_generator.gd")
const MbScenariosS := preload("res://engine/scenarios.gd")
const C := preload("res://engine/constants.gd")

signal changed

var state: Dictionary = {}
var scenario_name: String = "Endless"


func _base_state(size: int, seed_value: int) -> Dictionary:
	var tiles := []
	for r in range(size):
		for col in range(size):
			tiles.append(MbEngineS.create_empty_tile(r, col))
	return {
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


func _spawn_starting_tiles(count: int) -> void:
	var rng := MbRandomS.new(state["randomSeeds"], state["rngIndices"])
	for i in range(count):
		state = MbEngineS.add_random_tile_with_effects(state, rng)["gameState"]
	state["rngIndices"] = rng.get_indices()


func new_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi() % 1000000
	scenario_name = "Endless"
	state = _base_state(C.DEFAULT_BOARD_SIZE, seed_value)
	# Two starting tiles (mirrors a real match start; advances tile-gen RNG).
	_spawn_starting_tiles(2)
	changed.emit()


## Load a predefined scenario: its starting cards, board size, and effect spawn /
## event rules. Builds the configured board, then spawns two starting tiles
## (which may immediately gain an effect per the scenario's spawn config).
func new_game_scenario(scenario_id: int, seed_value: int = -1) -> void:
	var scen = MbScenariosS.get_scenario(scenario_id)
	if scen == null:
		new_game(seed_value)
		return
	if seed_value < 0:
		seed_value = randi() % 1000000
	scenario_name = "%d · %s" % [scenario_id, str(scen.get("name", "Scenario"))]
	var size := int(scen.get("boardSize", C.DEFAULT_BOARD_SIZE))
	state = _base_state(size, seed_value)

	var cards := []
	var starting: Array = scen.get("startingCards", [])
	for i in range(starting.size()):
		cards.append(MbScenariosS.create_card_instance(str(starting[i]), "card_start_%d" % i))
	state["hand"] = {"cards": cards}

	var cfg := {}
	if scen.has("spawnConfigs"):
		cfg["spawnConfigs"] = scen["spawnConfigs"]
	if scen.has("eventRules"):
		cfg["eventRules"] = scen["eventRules"]
	if scen.has("maxActiveOverrides"):
		cfg["maxActiveOverrides"] = scen["maxActiveOverrides"]
	if not cfg.is_empty():
		state["scenarioConfig"] = cfg

	# Build the configured board (explicit/random placements) then thread RNG forward.
	var rng := MbRandomS.new(state["randomSeeds"], state["rngIndices"])
	var built := MbScenariosS.build_initial_board(scen, size, rng)
	state["board"] = {"tiles": built, "size": size}
	state["rngIndices"] = rng.get_indices()

	_spawn_starting_tiles(2)
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


func spawn_totem(totem_type: String, card_index: int) -> bool:
	var res := MbEngineS.step_totem(state, totem_type, card_index)
	state = res["state"]
	changed.emit()
	return res["success"]
