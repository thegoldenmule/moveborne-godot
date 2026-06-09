@tool
class_name MbScenarios
extends RefCounted

## Scenario table + board construction + effect/card factories — GDScript port of
## moveborne/src/logic/src/boardBuilder.ts (buildInitialBoard/setTileAt/validateBoardConfig)
## and factories.ts (createEmptyTile/createTileEffect), plus the authoritative scenario
## TABLE from moveborne/src/game/engine/scenarios.ts (getScenario/validateBoardSize) and
## the createCardInstance factory from moveborne/src/game/engine/factories.ts.
##
## Reference semantics mirror JS: Dictionary/Array are reference types. setTileAt mutates the
## empty tile dict in place (so a placed tile is an empty tile with isEmpty/value/effect set —
## it carries NO "meta" field and keeps status "normal"). Object literals (createTileEffect /
## createEmptyTile) create NEW dicts. RNG: tile-gen namespace, two draws per random tile
## (position then value), in board order — same as boardBuilder.ts.

const C := preload("res://engine/constants.gd")


# ----------------------------------------------------------------------------
# factories.ts — createEmptyTile / createTileEffect
# ----------------------------------------------------------------------------

static func create_empty_tile(row: int = 0, col: int = 0) -> Dictionary:
	return {"isEmpty": true, "value": 0, "row": row, "col": col, "status": "normal"}


## Mirror of TS `...config` spread: shallow-overwrite top-level keys of `base` with `config`.
## (Not a deep merge — matches JS object spread semantics.)
static func _apply_config(base: Dictionary, config) -> Dictionary:
	if config == null:
		return base
	for k in (config as Dictionary).keys():
		base[k] = config[k]
	return base


static func create_tile_effect(type: String, config = null) -> Dictionary:
	var ts: int = C.DEFAULT_TILE_SIZE
	var effect_config: Dictionary
	match type:
		"black_hole":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 7,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 7,
				"allowsValueMerge": true,
				"allowsValueMovement": false,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"overlayTexture": "/assets/tile-effects/black-hole/overlay.png",
					"overlayWidth": 100,
					"overlayHeight": 100,
					"spawnEmitter": "black-hole-spawn",
					"activeEmitter": "black-hole-run",
					"removalEmitter": "black-hole-removal",
				},
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": true,
				},
			}
		"lock":
			effect_config = {
				"remainingTriggers": 1,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 0,
				"allowsValueMerge": true,
				"allowsValueMovement": false,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"overlayTexture": "/assets/tile-effects/lock/overlay.png",
					"overlayWidth": ts,
					"overlayHeight": ts,
					"spawnEmitter": "lock-spawn",
					"removalEmitter": "lock-removal",
				},
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": true,
				},
			}
		"decay":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0.5,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 5,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 0,
				"allowsValueMerge": true,
				"allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"spawnEmitter": "decay-spawn",
					"removalEmitter": "decay-removal",
				},
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": false,
				},
			}
		"amplify":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 2,
				"removalCost": 0,
				"allowsValueMerge": true,
				"allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"backgroundTexture": "/assets/tile-effects/amplify/background.png",
					"backgroundWidth": ts + 8,
					"backgroundHeight": ts + 8,
					"spawnEmitter": "amplify-spawn",
					"activeEmitter": "amplify-run",
					"removalEmitter": "amplify-removal",
					"showMultiplier": true,
				},
				"mergeConfig": {
					"valueMultiplier": 2,
					"consumedOnMerge": true,
					"consumptionEmitter": "amplify",
					"effectStaysAtSource": true,
				},
			}
		"amplify_static":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 2,
				"removalCost": 0,
				"allowsValueMerge": true,
				"allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"backgroundTexture": "/assets/tile-effects/amplify/background.png",
					"backgroundWidth": ts + 8,
					"backgroundHeight": ts + 8,
					"spawnEmitter": "amplify-spawn",
					"activeEmitter": "amplify-run",
					"removalEmitter": "amplify-removal",
					"showMultiplier": true,
				},
				"mergeConfig": {
					"valueMultiplier": 2,
					"consumedOnMerge": false,
					"consumptionEmitter": "amplify",
					"effectStaysAtSource": true,
				},
			}
		"freeze":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 0,
				"allowsValueMerge": false,
				"allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": true,
				"visual": {
					"overlayTexture": "/assets/tile-effects/freeze/overlay.png",
					"overlayWidth": 100,
					"overlayHeight": 100,
					"spawnEmitter": "freeze-spawn",
					"activeEmitter": "freeze-run",
					"removalEmitter": "freeze-removal",
				},
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": false,
				},
			}
		"stone":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 0,
				"allowsValueMerge": false,
				"allowsValueMovement": false,
				"effectRemovedByAdjacentMerge": true,
				"visual": {
					"overlayTexture": "/assets/tile-effects/stone/overlay.png",
					"overlayWidth": ts + 8,
					"overlayHeight": ts + 8,
					"spawnEmitter": "stone-spawn",
					"removalEmitter": "stone-removal",
				},
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": true,
				},
			}
		"none":
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 0,
				"allowsValueMerge": true,
				"allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": false,
				},
			}
		_:
			effect_config = {
				"remainingTriggers": 0,
				"decayRate": 0,
				"tilesConsumed": 0,
				"maxTilesToImplosion": 0,
				"decayMoveInterval": 0,
				"lastDecayMove": 0,
				"multiplier": 1,
				"removalCost": 0,
				"allowsValueMerge": true,
				"allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": false,
				},
			}

	effect_config = _apply_config(effect_config, config)
	return {"type": type, "active": true, "config": effect_config}


static func create_freeze_effect() -> Dictionary:
	return create_tile_effect("freeze")


static func create_black_hole_effect(removal_cost = null) -> Dictionary:
	if removal_cost != null:
		return create_tile_effect("black_hole", {"removalCost": removal_cost})
	return create_tile_effect("black_hole")


static func create_amplify_effect() -> Dictionary:
	return create_tile_effect("amplify")


static func create_stone_effect() -> Dictionary:
	return create_tile_effect("stone")


# ----------------------------------------------------------------------------
# game/engine/factories.ts — createCardInstance
# NOTE: NON-DETERMINISTIC in the TS (id = `card_${Date.now()}_${Math.random()...}`),
# so its id cannot be byte-exact with the server. We reproduce the shape (a shallow
# copy of the POWER_CARDS definition with an `id` field). Caller supplies the id
# (or we synthesize a unique-ish one) — this is the only part of the module that is
# intentionally not hash-verified against the oracle.
# ----------------------------------------------------------------------------

static func create_card_instance(type: String, id_override = null) -> Dictionary:
	var definition: Dictionary = C.POWER_CARDS[type]
	var card: Dictionary = definition.duplicate(true)
	if id_override != null:
		card["id"] = str(id_override)
	else:
		card["id"] = "card_%d_%d" % [Time.get_ticks_msec(), randi()]
	return card


# ----------------------------------------------------------------------------
# boardBuilder.ts — validateBoardConfig / setTileAt / getEmptyPositions / buildInitialBoard
# ----------------------------------------------------------------------------

static func _is_power_of_two(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0


static func validate_board_config(config: Dictionary, board_size: int) -> void:
	if config.has("tiles") and config["tiles"] != null:
		var positions := {}
		for placement in (config["tiles"] as Array):
			var pos: Dictionary = placement["position"]
			var row: int = int(pos["row"])
			var col: int = int(pos["col"])
			if row < 0 or row >= board_size or col < 0 or col >= board_size:
				push_error("Tile position (%d, %d) is out of bounds for board size %d" % [row, col, board_size])
				return
			var pos_key := "%d,%d" % [row, col]
			if positions.has(pos_key):
				push_error("Duplicate tile placement at position (%d, %d)" % [row, col])
				return
			positions[pos_key] = true
			var value: int = int(placement["config"]["value"])
			if not _is_power_of_two(value):
				push_error("Tile value %d at position (%d, %d) is not a power of 2" % [value, row, col])
				return

	if config.has("randomTiles") and config["randomTiles"] != null:
		var rt: Dictionary = config["randomTiles"]
		var count: int = int(rt["count"])
		var values: Array = rt["values"]
		if count < 0:
			push_error("Random tile count must be non-negative, got %d" % count)
			return
		if values.is_empty():
			push_error("Random tile values array cannot be empty")
			return
		for value in values:
			if not _is_power_of_two(int(value)):
				push_error("Random tile value %d is not a power of 2" % int(value))
				return
		var total_positions: int = board_size * board_size
		var explicit_tile_count: int = 0
		if config.has("tiles") and config["tiles"] != null:
			explicit_tile_count = (config["tiles"] as Array).size()
		var available_positions: int = total_positions - explicit_tile_count
		if count > available_positions:
			push_error("Cannot place %d random tiles on board with %d available positions" % [count, available_positions])
			return


## Mutates the empty tile dict at `position` in place: isEmpty=false, value set, optional effect.
## (No "meta" field added; status stays "normal".)
static func set_tile_at(tiles: Array, board_size: int, position: Dictionary, config: Dictionary) -> void:
	var row: int = int(position["row"])
	var col: int = int(position["col"])
	if row < 0 or row >= board_size or col < 0 or col >= board_size:
		push_error("Position (%d, %d) is out of bounds for board size %d" % [row, col, board_size])
		return
	var index: int = row * board_size + col
	var tile: Dictionary = tiles[index]
	tile["isEmpty"] = false
	tile["value"] = int(config["value"])
	if config.has("effect") and config["effect"] != null:
		var eff: Dictionary = config["effect"]
		var eff_cfg = eff.get("config", null)
		tile["effect"] = create_tile_effect(str(eff["type"]), eff_cfg)


static func _get_empty_positions(tiles: Array, avoid_positions: Array) -> Array:
	var empty_positions := []
	for tile in tiles:
		if not tile["isEmpty"]:
			continue
		var is_avoided := false
		for pos in avoid_positions:
			if int(pos["row"]) == int(tile["row"]) and int(pos["col"]) == int(tile["col"]):
				is_avoided = true
				break
		if not is_avoided:
			empty_positions.append({"row": int(tile["row"]), "col": int(tile["col"])})
	return empty_positions


## Build initial board state. `random_gen` is an MbRandom; draws from "tile-gen".
static func build_initial_board(config: Dictionary, board_size: int, random_gen) -> Array:
	validate_board_config(config, board_size)

	var tiles: Array = []
	for r in range(board_size):
		for c in range(board_size):
			tiles.append(create_empty_tile(r, c))

	if config.has("tiles") and config["tiles"] != null:
		for placement in (config["tiles"] as Array):
			set_tile_at(tiles, board_size, placement["position"], placement["config"])

	if config.has("randomTiles") and config["randomTiles"] != null:
		var rt: Dictionary = config["randomTiles"]
		var count: int = int(rt["count"])
		var values: Array = rt["values"]
		var avoid_positions: Array = rt["avoidPositions"] if rt.has("avoidPositions") and rt["avoidPositions"] != null else []
		var empty_positions := _get_empty_positions(tiles, avoid_positions)

		if empty_positions.size() < count:
			push_error("Not enough empty positions for random tiles. Requested %d, available %d" % [count, empty_positions.size()])
			return tiles

		for i in range(count):
			var random_index: int = int(floor(random_gen.get_random(C.NS_TILE_GEN) * empty_positions.size()))
			var position: Dictionary = empty_positions[random_index]
			empty_positions.remove_at(random_index)
			var random_value_index: int = int(floor(random_gen.get_random(C.NS_TILE_GEN) * values.size()))
			var value: int = int(values[random_value_index])
			set_tile_at(tiles, board_size, position, {"value": value})

	return tiles


# ----------------------------------------------------------------------------
# game/engine/scenarios.ts — validateBoardSize / getScenario / SCENARIOS table
# ----------------------------------------------------------------------------

static func validate_board_size(board_size: int) -> int:
	return max(C.MIN_BOARD_SIZE, min(C.MAX_BOARD_SIZE, board_size))


static var SCENARIOS: Dictionary = _build_scenarios()


## Returns the scenario config Dictionary, or null for unknown / negative ids
## (mirrors getScenario returning undefined).
static func get_scenario(scenario_id: int):
	if scenario_id < 0:
		return null
	return SCENARIOS.get(scenario_id, null)


static func _build_scenarios() -> Dictionary:
	return {
		0: {
			"id": 0,
			"name": "Tutorial - Freeze Focus",
			"description": "Only freeze effects spawn at high rate. Practice dealing with frozen tiles.",
			"boardSize": 4,
			"startingCards": ["destroy", "shuffle", "energy_catalyst"],
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.1}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
		},
		1: {
			"id": 1,
			"name": "Amplify Challenge",
			"description": "Heavy amplify and freeze spawns. Practice chaining amplified merges.",
			"boardSize": 4,
			"startingCards": ["bomb", "swap"],
			"spawnConfigs": {
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.08}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.05}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
		},
		2: {
			"id": 2,
			"name": "Lock Mayhem",
			"description": "Locks spawn frequently. Master unlocking tiles through merges.",
			"boardSize": 4,
			"startingCards": ["bomb", "lightning"],
			"spawnConfigs": {
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.12}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
			},
		},
		3: {
			"id": 3,
			"name": "Stone Garden",
			"description": "Stone tiles everywhere. Use power cards strategically to clear paths.",
			"boardSize": 4,
			"startingCards": ["destroy", "bomb", "clear"],
			"spawnConfigs": {
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.08}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 6},
			},
		},
		4: {
			"id": 4,
			"name": "Black Hole Gauntlet",
			"description": "Black holes spawn from the start. Avoid them or spend shards to remove.",
			"boardSize": 4,
			"startingCards": ["teleport", "swap"],
			"spawnConfigs": {
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 0.05}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": true, "maxActiveOnBoard": 1},
			},
		},
		5: {
			"id": 5,
			"name": "Decay Rush",
			"description": "Tiles decay rapidly. Keep the board moving to avoid losing tiles.",
			"boardSize": 4,
			"startingCards": ["shuffle", "double"],
			"spawnConfigs": {
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.12}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
			},
		},
		6: {
			"id": 6,
			"name": "Effect Chaos",
			"description": "All effects enabled with high spawn rates. Total chaos mode!",
			"boardSize": 4,
			"startingCards": ["bomb", "destroy", "shuffle"],
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.03}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.09}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.12}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.06}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.06}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 0.015}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": true, "maxActiveOnBoard": 2},
			},
		},
		7: {
			"id": 7,
			"name": "Combo Punisher",
			"description": "Breaking combos spawns freeze effects. Keep your combo alive or face the consequences!",
			"boardSize": 4,
			"startingCards": ["destroy", "swap"],
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.015}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
			"eventRules": [
				{"trigger": {"event": "COMBO_BREAK", "minCombo": 2}, "effect": "freeze", "spawnCount": 1, "targetPositions": "random", "icon": "/assets/event-spawners/icon-combo-punisher.png"},
			],
		},
		8: {
			"id": 8,
			"name": "Rising Tide",
			"description": "As your score grows, the board fights back. Lock effects spawn at each score milestone!",
			"boardSize": 4,
			"startingCards": ["bomb", "teleport"],
			"spawnConfigs": {
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.02}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 2},
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.005}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
			"eventRules": [
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 500}, "effect": "lock", "spawnCount": 1, "targetPositions": "highest_value", "icon": "/assets/event-spawners/icon-rising-tide.png"},
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 1000}, "effect": "lock", "spawnCount": 2, "targetPositions": "highest_value", "icon": "/assets/event-spawners/icon-rising-tide.png"},
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 2000}, "effect": "freeze", "spawnCount": 2, "targetPositions": "random", "icon": "/assets/event-spawners/icon-rising-tide.png"},
			],
		},
		9: {
			"id": 9,
			"name": "Merge Mania",
			"description": "Every 5 merges spawns amplify on your highest tiles. Chain merges for massive rewards!",
			"boardSize": 4,
			"startingCards": ["clone", "double"],
			"spawnConfigs": {
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.009}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 6},
			},
			"eventRules": [
				{"trigger": {"event": "MERGE_COUNT", "count": 5}, "effect": "amplify", "spawnCount": 1, "targetPositions": "highest_value", "icon": "/assets/event-spawners/icon-merge-mania.png"},
				{"trigger": {"event": "MERGE_COUNT", "count": 10}, "effect": "amplify", "spawnCount": 2, "targetPositions": "highest_value", "icon": "/assets/event-spawners/icon-merge-mania.png"},
			],
		},
		10: {
			"id": 10,
			"name": "The Gauntlet",
			"description": "Effects intensify every 10 moves. Survive the escalating challenge!",
			"boardSize": 4,
			"startingCards": ["destroy", "shuffle", "bomb"],
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.005}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.015}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 2},
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.02}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 2},
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.01}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 2},
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.01}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 2},
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 0.0025}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": true, "maxActiveOnBoard": 1},
			},
			"eventRules": [
				{"trigger": {"event": "MOVE_COUNT", "moves": 10}, "effect": "freeze", "spawnCount": 2, "targetPositions": "random", "icon": "/assets/event-spawners/icon-gauntlet.png"},
				{"trigger": {"event": "MOVE_COUNT", "moves": 20}, "effect": "lock", "spawnCount": 2, "targetPositions": "highest_value", "icon": "/assets/event-spawners/icon-gauntlet.png"},
				{"trigger": {"event": "MOVE_COUNT", "moves": 30}, "effect": "stone", "spawnCount": 2, "targetPositions": "random", "icon": "/assets/event-spawners/icon-gauntlet.png"},
				{"trigger": {"event": "MOVE_COUNT", "moves": 40}, "effect": "decay", "spawnCount": 3, "targetPositions": "random", "icon": "/assets/event-spawners/icon-gauntlet.png"},
			],
		},
		11: {
			"id": 11,
			"name": "Score Hunter",
			"description": "Reach score milestones to unlock amplify effects. High risk, high reward!",
			"boardSize": 4,
			"startingCards": ["radiate", "lightning"],
			"spawnConfigs": {
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.045}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.015}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
			"eventRules": [
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 250}, "effect": "amplify", "spawnCount": 1, "targetPositions": "random", "icon": "/assets/event-spawners/icon-score-hunter.png"},
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 500}, "effect": "amplify", "spawnCount": 2, "targetPositions": "empty", "icon": "/assets/event-spawners/icon-score-hunter.png"},
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 1000}, "effect": "amplify", "spawnCount": 2, "targetPositions": "random", "icon": "/assets/event-spawners/icon-score-hunter.png"},
			],
		},
		12: {
			"id": 12,
			"name": "Frozen Wasteland",
			"description": "Combo breaks spawn freezes, but merges thaw the board with amplify. Balance is key!",
			"boardSize": 4,
			"startingCards": ["bomb", "destroy", "swap"],
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.02}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.06}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
			"eventRules": [
				{"trigger": {"event": "COMBO_BREAK", "minCombo": 2}, "effect": "freeze", "spawnCount": 2, "targetPositions": "random", "icon": "/assets/event-spawners/icon-frozen-wasteland.png"},
				{"trigger": {"event": "MERGE_COUNT", "count": 8}, "effect": "amplify", "spawnCount": 1, "targetPositions": "highest_value", "icon": "/assets/event-spawners/icon-frozen-wasteland.png"},
				{"trigger": {"event": "SCORE_MILESTONE", "threshold": 800}, "effect": "freeze", "spawnCount": 3, "targetPositions": "random", "icon": "/assets/event-spawners/icon-frozen-wasteland.png"},
			],
		},
		13: {
			"id": 13,
			"name": "Four Corners",
			"description": "Start with 16s in all corners with freeze effects.",
			"boardSize": 4,
			"startingCards": ["swap", "teleport"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 16, "effect": {"type": "freeze"}}},
					{"position": {"row": 0, "col": 3}, "config": {"value": 16, "effect": {"type": "freeze"}}},
					{"position": {"row": 3, "col": 0}, "config": {"value": 16, "effect": {"type": "freeze"}}},
					{"position": {"row": 3, "col": 3}, "config": {"value": 16, "effect": {"type": "freeze"}}},
				],
				"randomTiles": {"count": 2, "values": [2]},
			},
		},
		14: {
			"id": 14,
			"name": "The Wall",
			"description": "Stone effects block the middle column.",
			"boardSize": 4,
			"startingCards": ["bomb", "destroy"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 2}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 1, "col": 2}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 2, "col": 2}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 3, "col": 2}, "config": {"value": 2, "effect": {"type": "stone"}}},
				],
				"randomTiles": {"count": 2, "values": [2]},
			},
		},
		15: {
			"id": 15,
			"name": "High Stakes",
			"description": "Start with high-value tiles and random additions.",
			"boardSize": 4,
			"startingCards": ["shuffle"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 1, "col": 1}, "config": {"value": 64, "effect": {"type": "amplify"}}},
					{"position": {"row": 1, "col": 2}, "config": {"value": 32, "effect": {"type": "lock"}}},
				],
				"randomTiles": {"count": 3, "values": [2, 4], "avoidPositions": [{"row": 1, "col": 1}, {"row": 1, "col": 2}]},
			},
		},
		16: {
			"id": 16,
			"name": "Amplified Corners",
			"description": "Start with 16s in all corners with amplify_static effects. Permanent 2x multipliers!",
			"boardSize": 4,
			"startingCards": ["clone", "double"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 2, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 0, "col": 3}, "config": {"value": 4, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 3, "col": 0}, "config": {"value": 8, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 3, "col": 3}, "config": {"value": 16, "effect": {"type": "amplify_static"}}},
				],
				"randomTiles": {"count": 2, "values": [2]},
			},
		},
		17: {
			"id": 17,
			"name": "Fracture",
			"description": "Break combos to trigger screen glitch effects. Survive the visual chaos.",
			"boardSize": 4,
			"startingCards": ["destroy", "shuffle"],
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.03}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
			"eventRules": [
				{"trigger": {"event": "COMBO_BREAK", "minCombo": 3}, "effect": "freeze", "spawnCount": 1, "targetPositions": "random", "icon": "/assets/event-spawners/icon-fracture.png", "globalEffect": {"type": "glitch", "duration": 10, "config": {"slices": 10, "offset": 5}}},
			],
		},
		100: {
			"id": 100,
			"name": "Test: Freeze Effect",
			"description": "Test freeze effect behavior. Frozen tiles cannot merge but can move. Adjacent merges remove freeze.",
			"boardSize": 4,
			"startingCards": ["destroy", "bomb"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 4, "effect": {"type": "freeze"}}},
					{"position": {"row": 0, "col": 1}, "config": {"value": 4, "effect": {"type": "freeze"}}},
					{"position": {"row": 1, "col": 0}, "config": {"value": 8}},
					{"position": {"row": 1, "col": 1}, "config": {"value": 8}},
				],
				"randomTiles": {"count": 2, "values": [2, 4]},
			},
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.5}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
			},
		},
		101: {
			"id": 101,
			"name": "Test: Black Hole Effect",
			"description": "Test black hole behavior. Black holes consume tiles that move through them. Costs 7 shards to remove.",
			"boardSize": 4,
			"startingCards": ["swap", "teleport"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 1, "col": 1}, "config": {"value": 2, "effect": {"type": "black_hole"}}},
					{"position": {"row": 0, "col": 0}, "config": {"value": 8}},
					{"position": {"row": 0, "col": 3}, "config": {"value": 8}},
					{"position": {"row": 3, "col": 0}, "config": {"value": 4}},
					{"position": {"row": 3, "col": 3}, "config": {"value": 4}},
				],
				"randomTiles": {"count": 2, "values": [2]},
			},
			"spawnConfigs": {
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 0.5}, "canSpawnOn": ["normal", "new", "spawned"], "canSpawnOnEmpty": true, "maxActiveOnBoard": 2},
			},
			"initialShards": 20,
		},
		102: {
			"id": 102,
			"name": "Test: Amplify Effect",
			"description": "Test amplify effect behavior. Merging into amplified tiles doubles the result and consumes the effect.",
			"boardSize": 4,
			"startingCards": ["clone", "double"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 4, "effect": {"type": "amplify"}}},
					{"position": {"row": 0, "col": 1}, "config": {"value": 8, "effect": {"type": "amplify"}}},
					{"position": {"row": 1, "col": 0}, "config": {"value": 4}},
					{"position": {"row": 1, "col": 1}, "config": {"value": 8}},
				],
				"randomTiles": {"count": 2, "values": [2, 4]},
			},
			"spawnConfigs": {
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.5}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
			},
		},
		103: {
			"id": 103,
			"name": "Test: Amplify Static Effect",
			"description": "Test amplify_static effect. Like amplify but the effect is NOT consumed on merge - permanent 2x multiplier!",
			"boardSize": 4,
			"startingCards": ["clone", "radiate"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 1, "col": 1}, "config": {"value": 8, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 1, "col": 2}, "config": {"value": 16, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 2, "col": 1}, "config": {"value": 4}},
					{"position": {"row": 2, "col": 2}, "config": {"value": 8}},
				],
				"randomTiles": {"count": 2, "values": [2, 4]},
			},
			"spawnConfigs": {},
		},
		104: {
			"id": 104,
			"name": "Test: Lock Effect",
			"description": "Test lock effect behavior. Locked tiles cannot move but can merge. Lock breaks after 1 merge.",
			"boardSize": 4,
			"startingCards": ["bomb", "lightning"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 4, "effect": {"type": "lock"}}},
					{"position": {"row": 0, "col": 1}, "config": {"value": 4, "effect": {"type": "lock"}}},
					{"position": {"row": 1, "col": 0}, "config": {"value": 8, "effect": {"type": "lock"}}},
					{"position": {"row": 1, "col": 1}, "config": {"value": 4}},
				],
				"randomTiles": {"count": 2, "values": [2, 4]},
			},
			"spawnConfigs": {
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.5}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
		},
		105: {
			"id": 105,
			"name": "Test: Decay Effect",
			"description": "Test decay effect behavior. Tiles with decay lose half their value every 5 moves.",
			"boardSize": 4,
			"startingCards": ["shuffle", "destroy"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 32, "effect": {"type": "decay"}}},
					{"position": {"row": 0, "col": 1}, "config": {"value": 16, "effect": {"type": "decay"}}},
					{"position": {"row": 1, "col": 0}, "config": {"value": 8, "effect": {"type": "decay"}}},
				],
				"randomTiles": {"count": 3, "values": [2, 4]},
			},
			"spawnConfigs": {
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.2}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
			},
		},
		106: {
			"id": 106,
			"name": "Test: Stone Effect",
			"description": "Test stone effect behavior. Stone tiles cannot move or merge. Adjacent merges remove stone.",
			"boardSize": 4,
			"startingCards": ["destroy", "bomb", "lightning"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 1, "col": 1}, "config": {"value": 4, "effect": {"type": "stone"}}},
					{"position": {"row": 1, "col": 2}, "config": {"value": 4, "effect": {"type": "stone"}}},
					{"position": {"row": 2, "col": 1}, "config": {"value": 8, "effect": {"type": "stone"}}},
					{"position": {"row": 0, "col": 0}, "config": {"value": 8}},
					{"position": {"row": 0, "col": 3}, "config": {"value": 8}},
				],
				"randomTiles": {"count": 2, "values": [2]},
			},
			"spawnConfigs": {
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.25}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
		},
		200: {
			"id": 200,
			"name": "Test: 5x5 Board",
			"description": "Test scenario with 5x5 board size.",
			"boardSize": 5,
			"startingCards": ["destroy", "shuffle", "bomb"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 2}},
					{"position": {"row": 0, "col": 4}, "config": {"value": 2}},
					{"position": {"row": 4, "col": 0}, "config": {"value": 2}},
					{"position": {"row": 4, "col": 4}, "config": {"value": 2}},
				],
				"randomTiles": {"count": 3, "values": [2, 4]},
			},
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.06}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.07}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.04}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
		},
		201: {
			"id": 201,
			"name": "Test: 6x6 Board",
			"description": "Test scenario with 6x6 board size.",
			"boardSize": 6,
			"startingCards": ["swap", "teleport", "clone"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 4}},
					{"position": {"row": 0, "col": 5}, "config": {"value": 4}},
					{"position": {"row": 5, "col": 0}, "config": {"value": 4}},
					{"position": {"row": 5, "col": 5}, "config": {"value": 4}},
				],
				"randomTiles": {"count": 4, "values": [2, 4]},
			},
			"spawnConfigs": {
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.08}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.05}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.06}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.04}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
			},
		},
		202: {
			"id": 202,
			"name": "Test: 8x8 Board",
			"description": "Test scenario with 8x8 board size - maximum supported size.",
			"boardSize": 8,
			"startingCards": ["shuffle", "energy_catalyst"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 1, "col": 1}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 2, "col": 2}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 3, "col": 3}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 4, "col": 4}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 5, "col": 5}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 6, "col": 6}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 7, "col": 7}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 0, "col": 7}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 1, "col": 6}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 2, "col": 5}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 3, "col": 4}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 4, "col": 3}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 5, "col": 2}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 6, "col": 1}, "config": {"value": 2, "effect": {"type": "stone"}}},
					{"position": {"row": 7, "col": 0}, "config": {"value": 2, "effect": {"type": "stone"}}},
				],
				"randomTiles": {"count": 6, "values": [2, 4]},
			},
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.04}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 6},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.05}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 6},
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.06}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.03}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.03}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 0.01}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": true, "maxActiveOnBoard": 2},
			},
			"initialShards": 15,
		},
		300: {
			"id": 300,
			"name": "All Effects Showcase",
			"description": "8x8 board starting with one of every tile effect. Perfect for testing all mechanics!",
			"boardSize": 8,
			"startingCards": ["bomb", "destroy", "shuffle", "swap", "teleport"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 4, "effect": {"type": "freeze"}}},
					{"position": {"row": 0, "col": 1}, "config": {"value": 4, "effect": {"type": "black_hole"}}},
					{"position": {"row": 0, "col": 2}, "config": {"value": 4, "effect": {"type": "amplify"}}},
					{"position": {"row": 0, "col": 3}, "config": {"value": 4, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 0, "col": 4}, "config": {"value": 4, "effect": {"type": "lock"}}},
					{"position": {"row": 0, "col": 5}, "config": {"value": 4, "effect": {"type": "decay"}}},
					{"position": {"row": 0, "col": 6}, "config": {"value": 4, "effect": {"type": "stone"}}},
				],
				"randomTiles": {"count": 12, "values": [2, 4, 8], "avoidPositions": [
					{"row": 0, "col": 0}, {"row": 0, "col": 1}, {"row": 0, "col": 2}, {"row": 0, "col": 3},
					{"row": 0, "col": 4}, {"row": 0, "col": 5}, {"row": 0, "col": 6},
				]},
			},
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.035}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 6},
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 0.015}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": true, "maxActiveOnBoard": 2},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.045}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 6},
				"amplify_static": {"spawnCurve": {"type": "constant", "baseChance": 0.01}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.05}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.025}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.025}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
			},
			"initialShards": 20,
		},
		301: {
			"id": 301,
			"name": "Transmute Card Test",
			"description": "Test the transmute power card with various tile effects. Multiple cards with different numEffects values.",
			"boardSize": 6,
			"startingCards": ["transform", "transform", "transform"],
			"initialBoard": {
				"tiles": [
					{"position": {"row": 0, "col": 0}, "config": {"value": 4, "effect": {"type": "freeze"}}},
					{"position": {"row": 0, "col": 1}, "config": {"value": 4, "effect": {"type": "freeze"}}},
					{"position": {"row": 0, "col": 2}, "config": {"value": 8, "effect": {"type": "lock"}}},
					{"position": {"row": 0, "col": 3}, "config": {"value": 8, "effect": {"type": "lock"}}},
					{"position": {"row": 1, "col": 0}, "config": {"value": 2, "effect": {"type": "amplify"}}},
					{"position": {"row": 1, "col": 1}, "config": {"value": 2, "effect": {"type": "amplify"}}},
					{"position": {"row": 1, "col": 2}, "config": {"value": 4, "effect": {"type": "stone"}}},
					{"position": {"row": 1, "col": 3}, "config": {"value": 4, "effect": {"type": "stone"}}},
					{"position": {"row": 2, "col": 0}, "config": {"value": 8, "effect": {"type": "decay"}}},
					{"position": {"row": 2, "col": 1}, "config": {"value": 8, "effect": {"type": "decay"}}},
					{"position": {"row": 2, "col": 2}, "config": {"value": 2, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 2, "col": 3}, "config": {"value": 2, "effect": {"type": "amplify_static"}}},
					{"position": {"row": 3, "col": 0}, "config": {"value": 4}},
					{"position": {"row": 3, "col": 1}, "config": {"value": 4}},
					{"position": {"row": 3, "col": 2}, "config": {"value": 8}},
				],
				"randomTiles": {"count": 3, "values": [2, 4]},
			},
			"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0.05}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"lock": {"spawnCurve": {"type": "constant", "baseChance": 0.04}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 4},
				"amplify": {"spawnCurve": {"type": "constant", "baseChance": 0.03}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
				"stone": {"spawnCurve": {"type": "constant", "baseChance": 0.03}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
				"decay": {"spawnCurve": {"type": "constant", "baseChance": 0.02}, "canSpawnOn": ["normal", "spawned", "new"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 3},
			},
			"initialShards": 20,
		},
	}
