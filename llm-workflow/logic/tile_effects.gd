@tool
class_name MbTileEffects
extends RefCounted

## Tile-effects logic + spawning — GDScript port of
## moveborne/src/logic/src/tileEffectLogic.ts + tileEffectSpawn.ts.
##
## Static funcs; tiles/state are Dictionaries; reference semantics mirror JS
## (Dictionary/Array are reference types). Effects carry a "config" Dictionary
## whose key insertion order matches the TS object literals in factories.ts so
## the canonical-JSON hash is byte-exact.

const C := preload("res://engine/constants.gd")

# ----------------------------------------------------------------------------
# factories.ts createTileEffect — default config per effect type.
# Key insertion order mirrors the TS literals verbatim. config overrides are
# applied via {...defaults, ...config} semantics (override existing, append new).
# ----------------------------------------------------------------------------

static func create_tile_effect(type: String, config = null) -> Dictionary:
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
					"overlayWidth": C.DEFAULT_TILE_SIZE,
					"overlayHeight": C.DEFAULT_TILE_SIZE,
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
					"backgroundWidth": C.DEFAULT_TILE_SIZE + 8,
					"backgroundHeight": C.DEFAULT_TILE_SIZE + 8,
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
					"backgroundWidth": C.DEFAULT_TILE_SIZE + 8,
					"backgroundHeight": C.DEFAULT_TILE_SIZE + 8,
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
					"overlayWidth": C.DEFAULT_TILE_SIZE + 8,
					"overlayHeight": C.DEFAULT_TILE_SIZE + 8,
					"spawnEmitter": "stone-spawn",
					"removalEmitter": "stone-removal",
				},
				"mergeConfig": {
					"valueMultiplier": 1,
					"consumedOnMerge": false,
					"effectStaysAtSource": true,
				},
			}
		_:
			# "none" and the TS default branch share identical config.
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

	# {...effectSpecificConfig, ...config}: override matching keys, append new ones,
	# preserving the defaults' insertion order for existing keys (JS spread semantics).
	if config != null and config is Dictionary:
		for k in (config as Dictionary).keys():
			effect_config[k] = (config as Dictionary)[k]

	return {
		"type": type,
		"active": true,
		"config": effect_config,
	}


# ----------------------------------------------------------------------------
# Spawn configuration (tileEffectLogic.ts)
# ----------------------------------------------------------------------------

static func _disabled_spawn_config() -> Dictionary:
	return {
		"spawnCurve": {
			"type": "constant",
			"baseChance": 0,
		},
		"canSpawnOn": [],
		"canSpawnOnEmpty": false,
		"maxActiveOnBoard": 0,
	}


static func get_spawn_config(effect_type: String, game_state: Dictionary) -> Dictionary:
	var scenario = game_state.get("scenarioConfig", null)
	if scenario != null and scenario is Dictionary:
		var spawn_configs = (scenario as Dictionary).get("spawnConfigs", null)
		if spawn_configs != null and spawn_configs is Dictionary and (spawn_configs as Dictionary).has(effect_type):
			var cfg = (spawn_configs as Dictionary)[effect_type]
			if cfg != null:
				return cfg
	return _disabled_spawn_config()


static func calculate_spawn_chance(curve: Dictionary, move_index: int) -> float:
	var chance: float
	var base_chance := float(curve.get("baseChance", 0))
	var params = curve.get("params", null)

	match str(curve.get("type", "")):
		"constant":
			chance = base_chance
		"linear":
			var rate := 0.001
			if params != null and params is Dictionary and (params as Dictionary).has("linearRate") and (params as Dictionary)["linearRate"] != null:
				rate = float((params as Dictionary)["linearRate"])
			chance = base_chance + rate * move_index
		"exponential":
			var factor := 1.01
			if params != null and params is Dictionary and (params as Dictionary).has("exponentialFactor") and (params as Dictionary)["exponentialFactor"] != null:
				factor = float((params as Dictionary)["exponentialFactor"])
			chance = base_chance * pow(factor, move_index)
		"stepped":
			var steps := []
			if params != null and params is Dictionary and (params as Dictionary).has("steps") and (params as Dictionary)["steps"] != null:
				steps = (params as Dictionary)["steps"]
			chance = base_chance
			for step in steps:
				if move_index >= int((step as Dictionary)["moveIndex"]):
					chance = float((step as Dictionary)["chance"])
		_:
			chance = base_chance

	var min_chance := 0.0
	if curve.has("minChance") and curve["minChance"] != null:
		min_chance = float(curve["minChance"])
	var max_chance := 1.0
	if curve.has("maxChance") and curve["maxChance"] != null:
		max_chance = float(curve["maxChance"])
	return max(min_chance, min(max_chance, chance))


static func should_spawn_effect(effect_type: String, game_state: Dictionary, current_active_count: int, random_generator) -> bool:
	var config := get_spawn_config(effect_type, game_state)

	var max_active := int(config.get("maxActiveOnBoard", 0))
	var scenario = game_state.get("scenarioConfig", null)
	if scenario != null and scenario is Dictionary:
		var overrides = (scenario as Dictionary).get("maxActiveOverrides", null)
		if overrides != null and overrides is Dictionary and (overrides as Dictionary).has(effect_type) and (overrides as Dictionary)[effect_type] != null:
			max_active = int((overrides as Dictionary)[effect_type])

	if current_active_count >= max_active:
		return false

	var spawn_chance := calculate_spawn_chance(config["spawnCurve"], int(game_state.get("moveIndex", 0)))

	return random_generator.get_random(C.NS_EFFECT_SPAWN) < spawn_chance


# ----------------------------------------------------------------------------
# Apply / count / adjacency (tileEffectLogic.ts)
# ----------------------------------------------------------------------------

static func can_apply_effect_to_tile(tile: Dictionary, effect_type: String, game_state: Dictionary) -> bool:
	# Don't apply if tile already has an active non-"none" effect.
	if tile.has("effect") and tile["effect"] != null:
		var eff: Dictionary = tile["effect"]
		if bool(eff.get("active", false)) and str(eff.get("type", "")) != "none":
			return false

	var spawn_config := get_spawn_config(effect_type, game_state)

	if bool(tile.get("isEmpty", false)):
		return bool(spawn_config.get("canSpawnOnEmpty", false))

	return (spawn_config.get("canSpawnOn", []) as Array).has(tile.get("status", "normal"))


static func count_active_effects(game_state: Dictionary, effect_type: String) -> int:
	var count := 0
	for tile in (game_state["board"]["tiles"] as Array):
		if tile != null and (tile as Dictionary).has("effect") and (tile as Dictionary)["effect"] != null:
			var eff: Dictionary = (tile as Dictionary)["effect"]
			if bool(eff.get("active", false)) and str(eff.get("type", "")) == effect_type:
				count += 1
	return count


static func get_adjacent_tiles(game_state: Dictionary, position: Dictionary) -> Array:
	var row := int(position["row"])
	var col := int(position["col"])
	var board_size := int(game_state["board"]["size"])
	var adjacent_positions := []

	if row > 0:
		adjacent_positions.append({"row": row - 1, "col": col})
	if row < board_size - 1:
		adjacent_positions.append({"row": row + 1, "col": col})
	if col > 0:
		adjacent_positions.append({"row": row, "col": col - 1})
	if col < board_size - 1:
		adjacent_positions.append({"row": row, "col": col + 1})

	var tiles: Array = game_state["board"]["tiles"]
	var result := []
	for pos in adjacent_positions:
		var index: int = int(pos["row"]) * board_size + int(pos["col"])
		result.append(tiles[index])
	return result


static func tile_has_effect(tile: Dictionary, effect_type: String) -> bool:
	if not tile.has("effect") or tile["effect"] == null:
		return false
	var eff: Dictionary = tile["effect"]
	return bool(eff.get("active", false)) and str(eff.get("type", "")) == effect_type


static func _remove_effect_from_tile(tile: Dictionary) -> void:
	if tile.has("effect") and tile["effect"] != null:
		(tile["effect"] as Dictionary)["active"] = false


static func apply_effect_to_tile(tile: Dictionary, effect: Dictionary) -> void:
	tile["effect"] = effect


# ----------------------------------------------------------------------------
# FREEZE / merge gating (tileEffectLogic.ts)
# ----------------------------------------------------------------------------

static func can_value_merge(tile: Dictionary) -> bool:
	if not tile.has("effect") or tile["effect"] == null or not bool((tile["effect"] as Dictionary).get("active", false)):
		return true
	return bool((tile["effect"] as Dictionary)["config"]["allowsValueMerge"])


static func process_freeze_removal_from_adjacent_merge(game_state: Dictionary, merged_position: Dictionary) -> Array:
	var removed_positions := []
	var adjacent_tiles := get_adjacent_tiles(game_state, merged_position)

	for tile in adjacent_tiles:
		var td: Dictionary = tile
		if td.has("effect") and td["effect"] != null:
			var eff: Dictionary = td["effect"]
			if bool(eff.get("active", false)) and bool((eff["config"] as Dictionary).get("effectRemovedByAdjacentMerge", false)):
				_remove_effect_from_tile(td)
				removed_positions.append({"row": int(td["row"]), "col": int(td["col"])})

	return removed_positions


static func can_tiles_merge_together(tile1: Dictionary, tile2: Dictionary) -> bool:
	if bool(tile1.get("isEmpty", false)) or bool(tile2.get("isEmpty", false)):
		return false
	if int(tile1["value"]) != int(tile2["value"]):
		return false
	return can_value_merge(tile1) and can_value_merge(tile2)


# ----------------------------------------------------------------------------
# LOCK (tileEffectLogic.ts)
# ----------------------------------------------------------------------------

static func process_lock_trigger_on_merge(tile: Dictionary):
	if not tile_has_effect(tile, "lock"):
		return null

	if not tile.has("effect") or tile["effect"] == null or not (tile["effect"] as Dictionary).has("config"):
		return null

	var config: Dictionary = (tile["effect"] as Dictionary)["config"]
	var remaining_triggers := int(config["remainingTriggers"])

	if remaining_triggers <= 1:
		_remove_effect_from_tile(tile)
		return {"row": int(tile["row"]), "col": int(tile["col"])}

	config["remainingTriggers"] = remaining_triggers - 1
	return null


# ----------------------------------------------------------------------------
# BLACK_HOLE (tileEffectLogic.ts)
# ----------------------------------------------------------------------------

static func is_black_hole_tile(tile: Dictionary) -> bool:
	return tile_has_effect(tile, "black_hole")


static func can_value_move(tile: Dictionary) -> bool:
	if bool(tile.get("isEmpty", false)):
		return false
	if not tile.has("effect") or tile["effect"] == null or not bool((tile["effect"] as Dictionary).get("active", false)):
		return true
	return bool((tile["effect"] as Dictionary)["config"]["allowsValueMovement"])


static func find_black_hole_in_path(tiles: Array, board_size: int, from: Dictionary, to: Dictionary):
	var from_row := int(from["row"])
	var from_col := int(from["col"])
	var to_row := int(to["row"])
	var to_col := int(to["col"])

	var row_dir := 0 if to_row == from_row else (1 if to_row > from_row else -1)
	var col_dir := 0 if to_col == from_col else (1 if to_col > from_col else -1)

	var current_row := from_row + row_dir
	var current_col := from_col + col_dir

	while current_row != to_row or current_col != to_col:
		var index := current_row * board_size + current_col
		var tile: Dictionary = tiles[index]
		if is_black_hole_tile(tile):
			return {"row": current_row, "col": current_col}
		current_row += row_dir
		current_col += col_dir

	return null


static func process_black_hole_destruction(consumed_tile: Dictionary, black_hole_tile: Dictionary) -> Dictionary:
	var score_loss := int(consumed_tile["value"])

	# Make consumed tile empty and clear any effects (delete consumed_tile.effect).
	consumed_tile["isEmpty"] = true
	consumed_tile["value"] = 0
	consumed_tile["status"] = "normal"
	consumed_tile.erase("effect")

	if black_hole_tile.has("effect") and black_hole_tile["effect"] != null and (black_hole_tile["effect"] as Dictionary).has("config"):
		var config: Dictionary = (black_hole_tile["effect"] as Dictionary)["config"]
		config["tilesConsumed"] = int(config["tilesConsumed"]) + 1
		var max_tiles := int(config["maxTilesToImplosion"])
		var should_implode: bool = int(config["tilesConsumed"]) >= max_tiles
		return {"scoreLoss": score_loss, "shouldImplode": should_implode}

	return {"scoreLoss": score_loss, "shouldImplode": false}


# ----------------------------------------------------------------------------
# Merge effect processing (tileEffectLogic.ts)
# ----------------------------------------------------------------------------

static func process_tile_effects_on_merge(tile: Dictionary, base_value: int) -> Dictionary:
	var final_value: int = base_value
	var consumed_effects := []

	if tile.has("effect") and tile["effect"] != null:
		var eff: Dictionary = tile["effect"]
		if bool(eff.get("active", false)) and str(eff.get("type", "")) != "none":
			var merge_config: Dictionary = (eff["config"] as Dictionary)["mergeConfig"]

			final_value = int(final_value * int(merge_config["valueMultiplier"]))

			if bool(merge_config.get("consumedOnMerge", false)):
				var metadata := {
					"multiplier": int(merge_config["valueMultiplier"]),
					"emitter": merge_config.get("consumptionEmitter", null),
				}
				consumed_effects.append({
					"type": str(eff["type"]),
					"row": int(tile["row"]),
					"col": int(tile["col"]),
					"metadata": metadata,
				})
				eff["active"] = false

	return {"finalValue": final_value, "consumedEffects": consumed_effects}


static func get_effect_to_preserve_at_source(tile: Dictionary):
	if not tile.has("effect") or tile["effect"] == null:
		return null
	var eff: Dictionary = tile["effect"]
	if not bool(eff.get("active", false)) or str(eff.get("type", "")) == "none":
		return null

	var merge_config: Dictionary = (eff["config"] as Dictionary)["mergeConfig"]

	if bool(merge_config.get("effectStaysAtSource", false)):
		return eff

	return null


# ----------------------------------------------------------------------------
# Spawning (tileEffectSpawn.ts)
# ----------------------------------------------------------------------------

const ALL_EFFECT_TYPES := ["freeze", "black_hole", "amplify", "amplify_static", "lock", "decay", "stone"]


static func find_valid_spawn_positions(game_state: Dictionary, effect_type: String) -> Array:
	var valid_indices := []
	var tiles: Array = game_state["board"]["tiles"]
	for i in range(tiles.size()):
		if can_apply_effect_to_tile(tiles[i], effect_type, game_state):
			valid_indices.append(i)
	return valid_indices


static func select_spawn_position(game_state: Dictionary, valid_indices: Array, strategy: String, random_generator):
	if valid_indices.is_empty():
		return null

	var tiles: Array = game_state["board"]["tiles"]
	match strategy:
		"random":
			var idx := int(floor(random_generator.get_random(C.NS_EFFECT_SPAWN) * valid_indices.size()))
			return valid_indices[idx]
		"empty":
			var empty_indices := []
			for i in valid_indices:
				if bool((tiles[i] as Dictionary).get("isEmpty", false)):
					empty_indices.append(i)
			if empty_indices.is_empty():
				return null
			var idx := int(floor(random_generator.get_random(C.NS_EFFECT_SPAWN) * empty_indices.size()))
			return empty_indices[idx]
		"highest_value":
			var max_value := -1
			var max_index = valid_indices[0]
			for i in valid_indices:
				var tile: Dictionary = tiles[i]
				if not bool(tile.get("isEmpty", false)) and int(tile["value"]) > max_value:
					max_value = int(tile["value"])
					max_index = i
			return max_index
		_:
			return null


static func attempt_spawn_effect_on_tile(game_state: Dictionary, tile_index: int, random_generator) -> Dictionary:
	var tile: Dictionary = game_state["board"]["tiles"][tile_index]

	for effect_type in ALL_EFFECT_TYPES:
		if not can_apply_effect_to_tile(tile, effect_type, game_state):
			continue

		var active_count := count_active_effects(game_state, effect_type)
		if not should_spawn_effect(effect_type, game_state, active_count, random_generator):
			continue

		# Spawn the effect.
		var effect := create_tile_effect(effect_type)
		var new_tiles: Array = (game_state["board"]["tiles"] as Array).duplicate()
		var new_tile: Dictionary = (new_tiles[tile_index] as Dictionary).duplicate()
		apply_effect_to_tile(new_tile, effect)
		new_tiles[tile_index] = new_tile

		var new_board: Dictionary = (game_state["board"] as Dictionary).duplicate()
		new_board["tiles"] = new_tiles
		var new_game_state := game_state.duplicate()
		new_game_state["board"] = new_board

		return {
			"success": true,
			"gameState": new_game_state,
			"effectSpawned": {
				"type": effect_type,
				"position": {"row": int(tile["row"]), "col": int(tile["col"])},
				"config": effect.get("config", {}),
			},
		}

	return {
		"success": false,
		"gameState": game_state,
	}
