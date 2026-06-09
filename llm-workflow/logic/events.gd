@tool
class_name MbEvents
extends RefCounted

## Event System — GDScript port of the Moveborne event trigger state machine and
## event-based spawn processor.
## (moveborne/src/logic/src: eventTriggerState.ts + eventSpawnProcessor.ts).
##
## Covers:
##   reset_triggered_states  (resetTriggeredStates)
##   update_trigger_states   (updateTriggerStates)
##   mark_triggers_activated (markTriggersActivated)  — helper used by spawn processor
##   process_event_spawn_rules (processEventSpawnRules) — COMBO_BREAK / SCORE_UPDATE only
##
## Reference semantics mirror JS: Dictionary/Array are reference types. The trigger
## state machine mutates the EventTriggerState dicts in place exactly where the TS
## does. process_event_spawn_rules constructs NEW dicts/boards where the TS uses
## object spreads, draws from the "effect-spawn" RNG namespace in the same order.

const C := preload("res://logic/constants.gd")

# ----------------------------------------------------------------------------
# Trigger-state progress / condition helpers (eventTriggerState.ts)
# ----------------------------------------------------------------------------

static func _get_progress_for_trigger(game_state: Dictionary, trigger: Dictionary):
	# Returns {current,required} or null.
	match str(trigger.get("event", "")):
		"COMBO_BREAK":
			return {"current": int(game_state["comboMultiplier"]), "required": int(trigger["minCombo"])}
		"SCORE_MILESTONE":
			return {"current": int(game_state["score"]), "required": int(trigger["threshold"])}
		"MERGE_COUNT":
			return {"current": int(game_state.get("totalMerges", 0)), "required": int(trigger["count"])}
		"MOVE_COUNT":
			return {"current": int(game_state["moveIndex"]), "required": int(trigger["moves"])}
		_:
			return null


static func _is_trigger_condition_met(game_state: Dictionary, trigger: Dictionary) -> bool:
	match str(trigger.get("event", "")):
		"COMBO_BREAK":
			return int(game_state["comboMultiplier"]) >= int(trigger["minCombo"])
		"SCORE_MILESTONE":
			return int(game_state["score"]) >= int(trigger["threshold"])
		"MERGE_COUNT":
			return int(game_state.get("totalMerges", 0)) >= int(trigger["count"])
		"MOVE_COUNT":
			return int(game_state["moveIndex"]) >= int(trigger["moves"])
		_:
			return false


static func _set_progress(trigger_state: Dictionary, game_state: Dictionary) -> void:
	# Mirror the TS object property assignment: if progress is undefined the TS
	# still assigns `triggerState.progress = undefined`, which in the canonical
	# JSON drops the key. We mirror by erasing when null, else storing the dict.
	var p = _get_progress_for_trigger(game_state, trigger_state["trigger"])
	if p == null:
		trigger_state.erase("progress")
	else:
		trigger_state["progress"] = p


# ----------------------------------------------------------------------------
# initializeEventTriggerStates (eventTriggerState.ts): build the trigger-state
# machine from a scenario's event rules at match start (the server does this in
# serverFactories.ts). Returns null when there are no rules. undefined-valued TS
# fields (targetPositions / icon / progress) are omitted so the canonical JSON matches.
# ----------------------------------------------------------------------------

static func initialize_event_trigger_states(event_rules, game_state: Dictionary):
	if event_rules == null or (event_rules as Array).is_empty():
		return null
	var out := []
	for i in range((event_rules as Array).size()):
		var rule: Dictionary = event_rules[i]
		var ts := {
			"id": "trigger_%d" % i,
			"trigger": rule["trigger"],
			"effect": rule["effect"],
			"spawnCount": rule["spawnCount"],
			"status": "idle",
		}
		if rule.has("targetPositions") and rule["targetPositions"] != null:
			ts["targetPositions"] = rule["targetPositions"]
		if rule.has("icon") and rule["icon"] != null:
			ts["icon"] = rule["icon"]
		var p = _get_progress_for_trigger(game_state, rule["trigger"])
		if p != null:
			ts["progress"] = p
		out.append(ts)
	return out


# ----------------------------------------------------------------------------
# updateTriggerStates: idle/primed machine (skips triggered)
# ----------------------------------------------------------------------------

static func update_trigger_states(game_state: Dictionary) -> Dictionary:
	if not game_state.has("eventTriggerStates") or game_state["eventTriggerStates"] == null:
		return game_state
	for trigger_state in (game_state["eventTriggerStates"] as Array):
		if str(trigger_state["status"]) == "triggered":
			continue
		var condition_met := _is_trigger_condition_met(game_state, trigger_state["trigger"])
		trigger_state["status"] = "primed" if condition_met else "idle"
		_set_progress(trigger_state, game_state)
	return game_state


# ----------------------------------------------------------------------------
# markTriggersActivated: set listed indices to triggered
# ----------------------------------------------------------------------------

static func mark_triggers_activated(game_state: Dictionary, matching_rule_indices: Array) -> Dictionary:
	if not game_state.has("eventTriggerStates") or game_state["eventTriggerStates"] == null:
		return game_state
	var states: Array = game_state["eventTriggerStates"]
	for index in matching_rule_indices:
		var idx := int(index)
		if idx >= 0 and idx < states.size():
			var trigger_state: Dictionary = states[idx]
			trigger_state["status"] = "triggered"
			_set_progress(trigger_state, game_state)
	return game_state


# ----------------------------------------------------------------------------
# resetTriggeredStates: triggered -> primed/idle based on current conditions
# ----------------------------------------------------------------------------

static func reset_triggered_states(game_state: Dictionary) -> Dictionary:
	if not game_state.has("eventTriggerStates") or game_state["eventTriggerStates"] == null:
		return game_state
	for trigger_state in (game_state["eventTriggerStates"] as Array):
		if str(trigger_state["status"]) == "triggered":
			var condition_met := _is_trigger_condition_met(game_state, trigger_state["trigger"])
			trigger_state["status"] = "primed" if condition_met else "idle"
			_set_progress(trigger_state, game_state)
	return game_state


# ----------------------------------------------------------------------------
# Spawn-position helpers (tileEffectSpawn.ts) — only the subset reachable from
# processEventSpawnRules. Spawn configs come from scenarioConfig.spawnConfigs;
# when absent the DISABLED config (canSpawnOn=[], canSpawnOnEmpty=false) means
# no valid positions, so the rule is skipped.
# ----------------------------------------------------------------------------

const _DISABLED_SPAWN_CONFIG := {
	"spawnCurve": {"type": "constant", "baseChance": 0},
	"canSpawnOn": [],
	"canSpawnOnEmpty": false,
	"maxActiveOnBoard": 0,
}


static func _get_spawn_config(effect_type: String, game_state: Dictionary) -> Dictionary:
	var sc = game_state.get("scenarioConfig", null)
	if sc != null and (sc as Dictionary).has("spawnConfigs"):
		var configs = sc["spawnConfigs"]
		if configs != null and (configs as Dictionary).has(effect_type) and configs[effect_type] != null:
			return configs[effect_type]
	return _DISABLED_SPAWN_CONFIG


static func _can_apply_effect_to_tile(tile: Dictionary, effect_type: String, game_state: Dictionary) -> bool:
	var eff = tile.get("effect", null)
	if eff != null and bool(eff.get("active", false)) and str(eff.get("type", "")) != "none":
		return false
	var spawn_config := _get_spawn_config(effect_type, game_state)
	if bool(tile["isEmpty"]):
		return bool(spawn_config.get("canSpawnOnEmpty", false))
	var can_spawn_on: Array = spawn_config.get("canSpawnOn", [])
	return can_spawn_on.has(str(tile.get("status", "normal")))


static func _find_valid_spawn_positions(game_state: Dictionary, effect_type: String) -> Array:
	var valid_indices := []
	var tiles: Array = game_state["board"]["tiles"]
	for i in range(tiles.size()):
		if _can_apply_effect_to_tile(tiles[i], effect_type, game_state):
			valid_indices.append(i)
	return valid_indices


static func _select_spawn_position(game_state: Dictionary, valid_indices: Array, strategy: String, rng):
	# Returns int tile index or null.
	if valid_indices.is_empty():
		return null
	var tiles: Array = game_state["board"]["tiles"]
	match strategy:
		"random":
			var pick := int(floor(rng.get_random(C.NS_EFFECT_SPAWN) * valid_indices.size()))
			return valid_indices[pick]
		"empty":
			var empty_indices := []
			for i in valid_indices:
				if bool(tiles[i]["isEmpty"]):
					empty_indices.append(i)
			if empty_indices.is_empty():
				return null
			var pick2 := int(floor(rng.get_random(C.NS_EFFECT_SPAWN) * empty_indices.size()))
			return empty_indices[pick2]
		"highest_value":
			var max_value := -1
			var max_index = valid_indices[0]
			for i in valid_indices:
				var tile: Dictionary = tiles[i]
				if not bool(tile["isEmpty"]) and int(tile["value"]) > max_value:
					max_value = int(tile["value"])
					max_index = i
			return max_index
		_:
			return null


# ----------------------------------------------------------------------------
# createTileEffect (factories.ts) — minimal port covering the spawnable types
# that processEventSpawnRules can authoritatively place. Returns {type,active,config}.
# ----------------------------------------------------------------------------

const _TILE_SIZE := 70  # DEFAULT_TILE_SIZE


static func _create_tile_effect(type: String, config = null) -> Dictionary:
	var cfg: Dictionary
	match type:
		"black_hole":
			cfg = {
				"remainingTriggers": 0, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 7, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 1, "removalCost": 7,
				"allowsValueMerge": true, "allowsValueMovement": false,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"overlayTexture": "/assets/tile-effects/black-hole/overlay.png",
					"overlayWidth": 100, "overlayHeight": 100,
					"spawnEmitter": "black-hole-spawn", "activeEmitter": "black-hole-run",
					"removalEmitter": "black-hole-removal",
				},
				"mergeConfig": {"valueMultiplier": 1, "consumedOnMerge": false, "effectStaysAtSource": true},
			}
		"lock":
			cfg = {
				"remainingTriggers": 1, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 1, "removalCost": 0,
				"allowsValueMerge": true, "allowsValueMovement": false,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"overlayTexture": "/assets/tile-effects/lock/overlay.png",
					"overlayWidth": _TILE_SIZE, "overlayHeight": _TILE_SIZE,
					"spawnEmitter": "lock-spawn", "removalEmitter": "lock-removal",
				},
				"mergeConfig": {"valueMultiplier": 1, "consumedOnMerge": false, "effectStaysAtSource": true},
			}
		"decay":
			cfg = {
				"remainingTriggers": 0, "decayRate": 0.5, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 5, "lastDecayMove": 0,
				"multiplier": 1, "removalCost": 0,
				"allowsValueMerge": true, "allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"visual": {"spawnEmitter": "decay-spawn", "removalEmitter": "decay-removal"},
				"mergeConfig": {"valueMultiplier": 1, "consumedOnMerge": false, "effectStaysAtSource": false},
			}
		"amplify":
			cfg = {
				"remainingTriggers": 0, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 2, "removalCost": 0,
				"allowsValueMerge": true, "allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"backgroundTexture": "/assets/tile-effects/amplify/background.png",
					"backgroundWidth": _TILE_SIZE + 8, "backgroundHeight": _TILE_SIZE + 8,
					"spawnEmitter": "amplify-spawn", "activeEmitter": "amplify-run",
					"removalEmitter": "amplify-removal", "showMultiplier": true,
				},
				"mergeConfig": {"valueMultiplier": 2, "consumedOnMerge": true, "consumptionEmitter": "amplify", "effectStaysAtSource": true},
			}
		"amplify_static":
			cfg = {
				"remainingTriggers": 0, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 2, "removalCost": 0,
				"allowsValueMerge": true, "allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"visual": {
					"backgroundTexture": "/assets/tile-effects/amplify/background.png",
					"backgroundWidth": _TILE_SIZE + 8, "backgroundHeight": _TILE_SIZE + 8,
					"spawnEmitter": "amplify-spawn", "activeEmitter": "amplify-run",
					"removalEmitter": "amplify-removal", "showMultiplier": true,
				},
				"mergeConfig": {"valueMultiplier": 2, "consumedOnMerge": false, "consumptionEmitter": "amplify", "effectStaysAtSource": true},
			}
		"freeze":
			cfg = {
				"remainingTriggers": 0, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 1, "removalCost": 0,
				"allowsValueMerge": false, "allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": true,
				"visual": {
					"overlayTexture": "/assets/tile-effects/freeze/overlay.png",
					"overlayWidth": 100, "overlayHeight": 100,
					"spawnEmitter": "freeze-spawn", "activeEmitter": "freeze-run",
					"removalEmitter": "freeze-removal",
				},
				"mergeConfig": {"valueMultiplier": 1, "consumedOnMerge": false, "effectStaysAtSource": false},
			}
		"stone":
			cfg = {
				"remainingTriggers": 0, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 1, "removalCost": 0,
				"allowsValueMerge": false, "allowsValueMovement": false,
				"effectRemovedByAdjacentMerge": true,
				"visual": {
					"overlayTexture": "/assets/tile-effects/stone/overlay.png",
					"overlayWidth": _TILE_SIZE + 8, "overlayHeight": _TILE_SIZE + 8,
					"spawnEmitter": "stone-spawn", "removalEmitter": "stone-removal",
				},
				"mergeConfig": {"valueMultiplier": 1, "consumedOnMerge": false, "effectStaysAtSource": true},
			}
		_:  # "none" and default share the same minimal config
			cfg = {
				"remainingTriggers": 0, "decayRate": 0, "tilesConsumed": 0,
				"maxTilesToImplosion": 0, "decayMoveInterval": 0, "lastDecayMove": 0,
				"multiplier": 1, "removalCost": 0,
				"allowsValueMerge": true, "allowsValueMovement": true,
				"effectRemovedByAdjacentMerge": false,
				"mergeConfig": {"valueMultiplier": 1, "consumedOnMerge": false, "effectStaysAtSource": false},
			}
	# Apply config overrides last (mirror `...config` spread).
	if config != null:
		for k in (config as Dictionary).keys():
			cfg[k] = config[k]
	return {"type": type, "active": true, "config": cfg}


# ----------------------------------------------------------------------------
# spawnTileEffects (authoritative branch only — what processEventSpawnRules uses)
# Returns new gameState dict (board.tiles rebuilt, effects applied).
# ----------------------------------------------------------------------------

static func _spawn_authoritative_effects(game_state: Dictionary, effects: Array) -> Dictionary:
	var board: Dictionary = game_state["board"]
	var new_tiles: Array = (board["tiles"] as Array).duplicate()  # shallow [...tiles]
	var board_size := int(board["size"])
	for effect_def in effects:
		var type: String = str(effect_def["type"])
		var position: Dictionary = effect_def["position"]
		var effect_config = effect_def.get("config", null)
		var index := int(position["row"]) * board_size + int(position["col"])
		if index < 0 or index >= new_tiles.size():
			continue
		var effect := _create_tile_effect(type, effect_config)
		var new_tile: Dictionary = (new_tiles[index] as Dictionary).duplicate()  # {...tile}
		new_tile["effect"] = effect  # applyEffectToTile
		new_tiles[index] = new_tile
	var new_state := game_state.duplicate()  # {...gameState}
	new_state["board"] = board.duplicate()  # {...board}
	new_state["board"]["tiles"] = new_tiles
	return new_state


# ----------------------------------------------------------------------------
# createGlobalEffect (globalEffects.ts) — draws 3 effect-spawn values
# ----------------------------------------------------------------------------

static func _create_global_effect(rule: Dictionary, trigger_id: String, rng):
	if not rule.has("globalEffect") or rule["globalEffect"] == null:
		return null
	var ge: Dictionary = rule["globalEffect"]
	var type = ge["type"]
	var duration := int(ge["duration"])
	var config = ge.get("config", null)

	var effect_id_seed := int(floor(rng.get_random(C.NS_EFFECT_SPAWN) * 1000000))

	var default_config := {
		"slices": 10, "offset": 75, "direction": 0, "fillMode": 0,
		"seed": rng.get_random(C.NS_EFFECT_SPAWN) * 10000,
		"average": false, "minSize": 8, "sampleSize": 512,
	}
	var filter_config := default_config.duplicate()
	if config != null:
		for k in (config as Dictionary).keys():
			filter_config[k] = config[k]

	return {
		"id": "%s_effect_%d" % [trigger_id, effect_id_seed],
		"type": type,
		"movesRemaining": duration,
		"maxMoves": duration,
		"triggerId": trigger_id,
		"filterConfig": filter_config,
	}


# ----------------------------------------------------------------------------
# matchesEventTrigger (eventSpawnProcessor.ts) — only COMBO_BREAK & SCORE_UPDATE
# are routed by the engine, but the full switch is ported for completeness.
# ----------------------------------------------------------------------------

static func _matches_event_trigger(event: Dictionary, trigger: Dictionary) -> bool:
	var ev_type := str(event["type"])
	match str(trigger.get("event", "")):
		"COMBO_BREAK":
			if ev_type == "COMBO_BREAK" or ev_type == "COMBO_BREAK_ATTEMPTED":
				var previous_combo := int(event.get("previousCombo", 0))
				return previous_combo >= int(trigger["minCombo"])
			return false
		"SCORE_MILESTONE":
			return ev_type == "SCORE_UPDATE"
		"MERGE_COUNT":
			return ev_type == "TILE_MERGE"
		"MOVE_COUNT":
			return ev_type == "TURN_END" or ev_type == "MOVE_COMPLETED"
		_:
			return false


# ----------------------------------------------------------------------------
# processEventSpawnRules
# ----------------------------------------------------------------------------

static func process_event_spawn_rules(game_state: Dictionary, event: Dictionary, rules: Array, rng, excluded_positions: Array = []) -> Dictionary:
	var matching_rule_indices := []
	var effects_to_spawn := []

	for rule_index in range(rules.size()):
		var rule: Dictionary = rules[rule_index]
		var matched := _matches_event_trigger(event, rule["trigger"])
		if not matched:
			continue

		var effect_type := str(rule["effect"])
		var spawn_count := int(rule["spawnCount"])
		var target_positions := str(rule.get("targetPositions", "random"))

		var valid_positions := _find_valid_spawn_positions(game_state, effect_type)

		# Filter out positions whose tile matches an excluded (row,col).
		var tiles: Array = game_state["board"]["tiles"]
		var filtered := []
		for tile_index in valid_positions:
			var tile: Dictionary = tiles[tile_index]
			var is_excluded := false
			for excluded_pos in excluded_positions:
				if int(excluded_pos["row"]) == int(tile["row"]) and int(excluded_pos["col"]) == int(tile["col"]):
					is_excluded = true
					break
			if not is_excluded:
				filtered.append(tile_index)
		valid_positions = filtered

		if valid_positions.is_empty():
			continue

		matching_rule_indices.append(rule_index)

		for i in range(spawn_count):
			var tile_index = _select_spawn_position(game_state, valid_positions, target_positions, rng)
			if tile_index == null:
				break
			var tile: Dictionary = tiles[tile_index]
			effects_to_spawn.append({
				"type": effect_type,
				"position": {"row": int(tile["row"]), "col": int(tile["col"])},
			})
			var index_pos := valid_positions.find(tile_index)
			if index_pos > -1:
				valid_positions.remove_at(index_pos)

	var modified_state := game_state
	if not effects_to_spawn.is_empty():
		modified_state = _spawn_authoritative_effects(modified_state, effects_to_spawn)

	if not matching_rule_indices.is_empty():
		modified_state = mark_triggers_activated(modified_state, matching_rule_indices)

	# Create global effects for matching rules.
	for rule_index in matching_rule_indices:
		var rule: Dictionary = rules[rule_index]
		if rule.get("globalEffect", null) != null and modified_state.get("eventTriggerStates", null) != null:
			var states: Array = modified_state["eventTriggerStates"]
			if rule_index >= 0 and rule_index < states.size():
				var trigger_state = states[rule_index]
				if trigger_state != null:
					var global_effect = _create_global_effect(rule, str(trigger_state["id"]), rng)
					if global_effect != null:
						if not modified_state.has("globalEffects") or modified_state["globalEffects"] == null:
							modified_state["globalEffects"] = []
						modified_state["globalEffects"] = (modified_state["globalEffects"] as Array) + [global_effect]

	return modified_state
