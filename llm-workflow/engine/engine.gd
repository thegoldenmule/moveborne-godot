@tool
class_name MbEngine
extends RefCounted

## Deterministic engine — GDScript port of the Moveborne rules core
## (moveborne/src/logic/src: merge.ts, actionExecutor.ts, shards.ts, cardDraw.ts),
## wiring the verified subsystem modules (tile effects, totems, events, power cards).
##
## State is a Dictionary mirror of SynchronizedGameState; tiles = flat row-major
## Array of tile Dicts. GDScript Dictionary/Array are reference types, so JS [...]/
## {...}/in-place-mutation semantics from merge.ts are reproduced exactly.

const C := preload("res://engine/constants.gd")
const Hasher := preload("res://engine/hasher.gd")
const MbRandomS := preload("res://engine/random_generator.gd")
const PC := preload("res://engine/powercards.gd")
const TE := preload("res://engine/tile_effects.gd")
const TT := preload("res://engine/totems.gd")
const EV := preload("res://engine/events.gd")

# ----------------------------------------------------------------------------
# board helpers (board.ts / factories.ts)
# ----------------------------------------------------------------------------

static func create_empty_tile(row: int, col: int) -> Dictionary:
	return {"isEmpty": true, "value": 0, "row": row, "col": col, "status": "normal"}


static func _event_rules(state: Dictionary):
	if state.has("scenarioConfig") and state["scenarioConfig"] != null:
		var sc: Dictionary = state["scenarioConfig"]
		if sc.has("eventRules") and sc["eventRules"] != null:
			return sc["eventRules"]
	return null


# ----------------------------------------------------------------------------
# swipe (merge.ts swipeLeft/Right/Up/Down + performSwipe) — full effect handling
# ----------------------------------------------------------------------------

static func _iter_order(size: int, direction: String) -> Array:
	var out := []
	match direction:
		"left":
			for row in range(size):
				for col in range(1, size):
					out.append([row, col])
		"right":
			for row in range(size):
				for col in range(size - 2, -1, -1):
					out.append([row, col])
		"up":
			for col in range(size):
				for row in range(1, size):
					out.append([row, col])
		"down":
			for col in range(size):
				for row in range(size - 2, -1, -1):
					out.append([row, col])
	return out


static func _scan_cells(size: int, row: int, col: int, direction: String) -> Array:
	var out := []
	match direction:
		"left":
			for c in range(col - 1, -1, -1):
				out.append([row, c])
		"right":
			for c in range(col + 1, size):
				out.append([row, c])
		"up":
			for r in range(row - 1, -1, -1):
				out.append([r, col])
		"down":
			for r in range(row + 1, size):
				out.append([r, col])
	return out


static func _resolve(t: Array, merged: Dictionary, size: int, row: int, col: int, tr: int, tc: int, destroyed: Array, removed_locks: Array) -> Dictionary:
	var src := row * size + col
	var tgt := tr * size + tc
	var tile: Dictionary = t[src]
	var target_tile: Dictionary = t[tgt]

	var target_is_barrier := TE.is_black_hole_tile(target_tile)
	var bh_pos = null
	if not target_is_barrier:
		bh_pos = TE.find_black_hole_in_path(t, size, {"row": row, "col": col}, {"row": tr, "col": tc})

	if target_is_barrier or bh_pos != null:
		var bh_position: Dictionary = ({"row": tr, "col": tc} if target_is_barrier else bh_pos)
		var bh_tile: Dictionary = t[int(bh_position["row"]) * size + int(bh_position["col"])]
		var dr := TE.process_black_hole_destruction(tile, bh_tile)
		destroyed.append({"position": {"row": row, "col": col}, "value": int(dr["scoreLoss"]), "destroyedBy": {"type": "black_hole", "position": bh_position}})
		if bool(dr["shouldImplode"]) and bh_tile.has("effect") and bh_tile["effect"] != null:
			(bh_tile["effect"] as Dictionary)["active"] = false
		t[src] = create_empty_tile(row, col)
		return {"score": 0, "scoreLoss": int(dr["scoreLoss"]), "count": 0}

	if not bool(target_tile["isEmpty"]) and int(target_tile["value"]) == int(tile["value"]) and TE.can_tiles_merge_together(tile, target_tile):
		var base_value := int(tile["value"]) * 2
		var mr := TE.process_tile_effects_on_merge(target_tile, base_value)
		var lock_removed = TE.process_lock_trigger_on_merge(target_tile)
		if lock_removed != null:
			removed_locks.append(lock_removed)
		var merged_tile := {"isEmpty": false, "value": int(mr["finalValue"]), "status": "merged", "meta": {}, "row": tr, "col": tc}
		if target_tile.has("effect") and target_tile["effect"] != null and bool((target_tile["effect"] as Dictionary).get("active", false)):
			merged_tile["effect"] = target_tile["effect"]
		t[tgt] = merged_tile
		var src_pres = TE.get_effect_to_preserve_at_source(tile)
		var empty := create_empty_tile(row, col)
		if src_pres != null:
			empty["effect"] = src_pres
		t[src] = empty
		merged[tgt] = true
		return {"score": int(mr["finalValue"]), "scoreLoss": 0, "count": 1}
	else:
		var src_pres = TE.get_effect_to_preserve_at_source(tile)
		var tgt_transfer = TE.get_effect_to_preserve_at_source(target_tile)
		tile["row"] = tr
		tile["col"] = tc
		if src_pres != null:
			tile.erase("effect")
		if tgt_transfer != null:
			tile["effect"] = tgt_transfer
		t[tgt] = tile
		var empty := create_empty_tile(row, col)
		if src_pres != null:
			empty["effect"] = src_pres
		t[src] = empty
		return {"score": 0, "scoreLoss": 0, "count": 0}


static func _swipe(t: Array, merged: Dictionary, size: int, direction: String, destroyed: Array, removed_locks: Array) -> Dictionary:
	var moved := false
	var score := 0
	var score_loss := 0
	var count := 0
	for cell in _iter_order(size, direction):
		var row: int = cell[0]
		var col: int = cell[1]
		var tile = t[row * size + col]
		if tile == null or bool(tile["isEmpty"]):
			continue
		if not TE.can_value_move(tile):
			continue
		var tr := row
		var tc := col
		for scell in _scan_cells(size, row, col, direction):
			var cr: int = scell[0]
			var cc: int = scell[1]
			var ct: Dictionary = t[cr * size + cc]
			if TE.is_black_hole_tile(ct):
				tr = cr
				tc = cc
				continue
			if bool(ct["isEmpty"]):
				tr = cr
				tc = cc
			elif int(ct["value"]) == int(tile["value"]) and not merged.has(cr * size + cc) and TE.can_tiles_merge_together(tile, ct):
				tr = cr
				tc = cc
				break
			else:
				break
		if tr == row and tc == col:
			continue
		moved = true
		var rr := _resolve(t, merged, size, row, col, tr, tc, destroyed, removed_locks)
		score += int(rr["score"])
		score_loss += int(rr["scoreLoss"])
		count += int(rr["count"])
	return {"moved": moved, "score": score, "scoreLoss": score_loss, "count": count}


static func perform_swipe(state: Dictionary, direction: String, rng) -> Dictionary:
	var result := TT.process_totem_effects(state, {"type": "PRE_SWIPE", "direction": direction}, rng)
	var board: Dictionary = result["board"]
	var size: int = int(board["size"])
	var new_tiles: Array = (board["tiles"] as Array).duplicate()
	for tile in new_tiles:
		if tile != null:
			tile["status"] = "normal"
	var merged := {}
	var destroyed := []
	var removed_locks := []
	var sr: Dictionary
	if direction in ["left", "right", "up", "down"]:
		sr = _swipe(new_tiles, merged, size, direction, destroyed, removed_locks)
	else:
		sr = {"moved": false, "score": 0, "scoreLoss": 0, "count": 0}
	var net_score: int = int(sr["score"]) - int(sr["scoreLoss"])

	result = result.duplicate()
	result["board"] = board.duplicate()
	result["board"]["tiles"] = new_tiles

	var removed_effect_positions: Array = removed_locks.duplicate()
	if int(sr["count"]) > 0:
		for i in range(new_tiles.size()):
			var tl: Dictionary = new_tiles[i]
			if str(tl.get("status", "")) == "merged":
				var fr := TE.process_freeze_removal_from_adjacent_merge(result, {"row": int(i / size), "col": i % size})
				for p in fr:
					removed_effect_positions.append(p)

	result = TT.process_totem_effects(result, {"type": "POST_SWIPE", "mergeOccurred": int(sr["count"]) > 0, "tilesSpawned": 0, "direction": direction}, rng)
	result = TT.process_totem_effects(result, {"type": "MOVE_COMPLETED"}, rng)
	result = TT.process_totem_effects(result, {"type": "SWIPE_COMPLETED", "direction": direction}, rng)

	if net_score > 0:
		var rules = _event_rules(result)
		if rules != null and (rules as Array).size() > 0:
			result = EV.process_event_spawn_rules(result, {"type": "SCORE_UPDATE", "value": net_score}, rules, rng, removed_effect_positions)

	return {"gameState": result, "moved": sr["moved"], "score": net_score, "mergedTilesCount": sr["count"], "destroyed": destroyed}


# ----------------------------------------------------------------------------
# spawn / combo / score (merge.ts)
# ----------------------------------------------------------------------------

static func add_random_tile_with_effects(state: Dictionary, rng) -> Dictionary:
	var board: Dictionary = state["board"]
	var tiles: Array = board["tiles"]
	var size: int = int(board["size"])
	var empties := []
	for i in range(tiles.size()):
		var tl: Dictionary = tiles[i]
		var has_effect := tl.has("effect") and tl["effect"] != null and bool((tl["effect"] as Dictionary).get("active", false)) and str((tl["effect"] as Dictionary).get("type", "")) != "none"
		if bool(tl["isEmpty"]) and not has_effect:
			empties.append(i)
	if empties.is_empty():
		return {"gameState": state}
	var ri: int = empties[int(floor(rng.get_random(C.NS_TILE_GEN) * empties.size()))]
	var value: int = 2 if rng.get_random(C.NS_TILE_GEN) < 0.9 else 4

	var spawn_event := {"type": "TILE_SPAWN", "tileValue": value, "position": {"row": int(ri / size), "col": ri % size}}
	var modified := TT.process_totem_effects(state, spawn_event, rng)
	var final_value: int = int(spawn_event.get("tileValue", 0))

	var new_tiles: Array = (modified["board"]["tiles"] as Array).duplicate()
	new_tiles[ri] = {"isEmpty": false, "value": final_value, "status": "new", "meta": {}, "row": int(ri / size), "col": ri % size}
	modified = modified.duplicate()
	modified["board"] = (modified["board"] as Dictionary).duplicate()
	modified["board"]["tiles"] = new_tiles

	modified = TT.process_totem_effects(modified, {"type": "POST_SPAWN", "spawnedPosition": ri, "spawnedValue": final_value}, rng)

	var spawn_result := TE.attempt_spawn_effect_on_tile(modified, ri, rng)
	if bool(spawn_result.get("success", false)) and spawn_result.get("effectSpawned", null) != null:
		var es: Dictionary = spawn_result["effectSpawned"]
		modified = TT.process_totem_effects(spawn_result["gameState"], {"type": "TILE_EFFECT_APPLIED", "effectApplied": {"type": es["type"], "position": es.get("position", null), "config": es.get("config", null)}}, rng)
		return {"gameState": modified}
	return {"gameState": spawn_result["gameState"]}


static func update_combo_multiplier(state: Dictionary, merged_count: int, rng) -> Dictionary:
	if merged_count == 0:
		var previous_combo := int(state["comboMultiplier"])
		var reset_state := state.duplicate()
		reset_state["comboMultiplier"] = 0
		var modified := TT.process_totem_effects(reset_state, {"type": "COMBO_BREAK_ATTEMPTED", "previousCombo": previous_combo}, rng)
		modified = EV.update_trigger_states(modified)
		if int(modified["comboMultiplier"]) == 0 and previous_combo > 0:
			var rules = _event_rules(state)
			if rules != null and (rules as Array).size() > 0:
				modified = EV.process_event_spawn_rules(modified, {"type": "COMBO_BREAK", "previousCombo": previous_combo}, rules, rng)
		return modified
	var increment_event := {"type": "COMBO_INCREMENT", "incrementAmount": merged_count}
	var modified := TT.process_totem_effects(state, increment_event, rng)
	var final_increment := int(increment_event.get("incrementAmount", merged_count))
	modified = modified.duplicate()
	modified["comboMultiplier"] = int(state["comboMultiplier"]) + final_increment
	modified = EV.update_trigger_states(modified)
	return modified


static func calculate_combo_score(base_score: int, combo_multiplier: int) -> int:
	if combo_multiplier <= 0:
		return base_score
	return base_score * combo_multiplier


static func calculate_shards(current: int, to_add: int) -> int:
	return min(current + to_add, C.SHARDS_PER_CARD)


# globalEffects.ts processGlobalEffects(MOVE_COMPLETED): tick each global effect.
# Decrement movesRemaining (drop the effect at 0 — with NO rng draw), else reseed +
# ramp the filter from 2 ordered effect-spawn draws per surviving effect.
static func _process_global_effects(state: Dictionary, rng) -> Dictionary:
	if not state.has("globalEffects") or state["globalEffects"] == null or (state["globalEffects"] as Array).is_empty():
		return state
	var ns := state.duplicate()
	var out := []
	for effect in (ns["globalEffects"] as Array):
		var e: Dictionary = effect
		var new_remaining: int = maxi(0, int(e["movesRemaining"]) - 1)
		if new_remaining == 0:
			continue  # TS returns null -> filtered out; no rng drawn
		var new_seed: float = rng.get_random(C.NS_EFFECT_SPAWN) * 10000.0
		var offset_variation: float = 15.0 + rng.get_random(C.NS_EFFECT_SPAWN) * 10.0
		var ne := e.duplicate()
		ne["movesRemaining"] = new_remaining
		var fc := (e["filterConfig"] as Dictionary).duplicate()
		fc["seed"] = new_seed
		fc["offset"] = offset_variation
		ne["filterConfig"] = fc
		out.append(ne)
	ns["globalEffects"] = out
	return ns


# ----------------------------------------------------------------------------
# card draw (cardDraw.ts)
# ----------------------------------------------------------------------------

static func can_draw_card(state: Dictionary) -> bool:
	return int(state["shards"]) >= C.SHARDS_PER_CARD \
		and (state["hand"]["cards"] as Array).size() < C.MAX_HAND_SIZE \
		and int(state["deck"]["remainingCards"]) > 0


static func draw_card_from_deck(rng, draw_index: int) -> Dictionary:
	var cards: Array = C.POWER_CARDS_VALUES
	var idx: int = int(floor(rng.get_random(C.NS_CARD_DRAW) * cards.size()))
	var card: Dictionary = (cards[idx] as Dictionary).duplicate(true)
	card["id"] = "card_draw_%d" % draw_index
	return card


# ----------------------------------------------------------------------------
# action executor (actionExecutor.ts)
# ----------------------------------------------------------------------------

static func execute_swipe_action(state: Dictionary, direction: String, rng) -> Dictionary:
	var working := EV.reset_triggered_states(state)
	var result := perform_swipe(working, direction, rng)
	if result["moved"]:
		var ns: Dictionary = result["gameState"]
		ns = update_combo_multiplier(ns, int(result["mergedTilesCount"]), rng)
		var total_score: int
		if int(result["score"]) >= 0:
			total_score = calculate_combo_score(int(result["score"]), int(ns["comboMultiplier"]))
		else:
			total_score = int(result["score"])
		var shards_to_add: int = int(result["mergedTilesCount"])
		if int(result["mergedTilesCount"]) > 0:
			var shard_event := {"type": "POST_SWIPE", "mergedTilesCount": int(result["mergedTilesCount"]), "mergeOccurred": true, "shardsMultiplier": 1, "direction": direction}
			ns = TT.process_totem_effects(ns, shard_event, rng)
			shards_to_add = int(result["mergedTilesCount"]) * int(shard_event.get("shardsMultiplier", 1))
		var add_res := add_random_tile_with_effects(ns, rng)
		ns = add_res["gameState"]
		ns = EV.update_trigger_states(ns)
		ns = ns.duplicate()
		ns["shards"] = calculate_shards(int(ns["shards"]), shards_to_add)
		var card_drawn := false
		var drawn_card = null
		if can_draw_card(ns):
			drawn_card = draw_card_from_deck(rng, int(ns["deck"]["nextCardIndex"]))
			ns = ns.duplicate()
			ns["hand"] = {"cards": (ns["hand"]["cards"] as Array) + [drawn_card]}
			ns["shards"] = 0
			var deck := (ns["deck"] as Dictionary).duplicate()
			deck["nextCardIndex"] = int(ns["deck"]["nextCardIndex"]) + 1
			deck["remainingCards"] = int(ns["deck"]["remainingCards"]) - 1
			ns["deck"] = deck
			card_drawn = true
		ns = _process_global_effects(ns, rng)
		return {"newState": ns, "scoreAdded": total_score, "shardsAdded": shards_to_add, "moved": true, "cardDrawn": card_drawn, "drawnCard": drawn_card, "destroyed": result.get("destroyed", [])}
	else:
		var ns: Dictionary = result["gameState"]
		ns = update_combo_multiplier(ns, 0, rng)
		ns = TT.process_totem_effects(ns, {"type": "FAILED_SWIPE", "direction": direction}, rng)
		var add_res := add_random_tile_with_effects(ns, rng)
		ns = add_res["gameState"]
		ns = _process_global_effects(ns, rng)
		return {"newState": ns, "scoreAdded": 0, "shardsAdded": 0, "moved": false, "cardDrawn": false, "drawnCard": null, "destroyed": []}


static func execute_play_card_action(state: Dictionary, action: String, action_data: Dictionary, card_index: int, rng) -> Dictionary:
	var ns := state.duplicate()
	var tiles: Array = ns["board"]["tiles"]
	var size: int = int(ns["board"]["size"])
	var reset_combo := true
	var r: Dictionary = {"success": false, "tiles": tiles, "score": 0}
	match action:
		"split": r = PC.perform_power_card_split(tiles, action_data.get("tile"), size)
		"multiply": r = PC.perform_power_card_multiply(tiles, action_data.get("tile"), size)
		"shuffle":
			r = PC.perform_power_card_shuffle(tiles, rng, size)
			reset_combo = false
		"lightning": r = PC.perform_power_card_lightning(tiles, action_data.get("column"), size)
		"radiate": r = PC.perform_power_card_radiate(tiles, action_data.get("tile"), size)
		"clone": r = PC.perform_power_card_clone(tiles, action_data.get("sourceTile"), action_data.get("targetTile"), size)
		"swap": r = PC.perform_power_card_swap(tiles, action_data.get("tile1"), action_data.get("tile2"), size)
		"vortex":
			r = PC.perform_power_card_vortex(tiles, {"row": action_data.get("row"), "col": action_data.get("column")}, size)
			reset_combo = false
		"teleport":
			r = PC.perform_power_card_teleport(tiles, action_data.get("sourceTile"), action_data.get("targetTile"), size)
			reset_combo = false
		"bomb": r = PC.perform_power_card_bomb(tiles, action_data.get("tile"), size)
		"destroy": r = PC.perform_power_card_destroy(tiles, action_data.get("tile"), size)
		"clear": r = PC.perform_power_card_clear(tiles, action_data.get("column"), size)
		"double": r = PC.perform_power_card_double(tiles, action_data.get("tile"), size)
		"transform":
			var num_effects := 1
			for c in (ns["hand"]["cards"] as Array):
				if c.get("type") == "transform":
					num_effects = int(c.get("value", 1))
					break
			r = PC.perform_power_card_transform(tiles, num_effects, rng, size)
		_:
			return {"success": false, "newState": state, "scoreAdded": 0, "error": "unknown_card_action"}
	if not bool(r.get("success", false)):
		return {"success": false, "newState": ns, "scoreAdded": 0, "error": "invalid_" + action}
	var board := (ns["board"] as Dictionary).duplicate()
	board["tiles"] = r["tiles"]
	ns["board"] = board
	if reset_combo:
		ns["combo"] = 0
	var cards := (ns["hand"]["cards"] as Array)
	if card_index >= 0 and card_index < cards.size():
		var nc := cards.duplicate()
		nc.remove_at(card_index)
		ns["hand"] = {"cards": nc}
	ns = EV.update_trigger_states(ns)
	return {"success": true, "newState": ns, "scoreAdded": int(r["score"]), "error": null}


static func execute_spawn_totem_action(state: Dictionary, totem_type: String, card_index: int) -> Dictionary:
	var ns := state.duplicate()
	var cards := (ns["hand"]["cards"] as Array)
	if card_index < 0 or card_index >= cards.size():
		return {"success": false, "newState": state, "scoreAdded": 0, "error": "Invalid card index: %d" % card_index}
	var totem_id := "totem_%d_%s" % [int(ns["moveIndex"]) + 1, totem_type]
	var new_totem := {"id": totem_id, "type": totem_type, "config": TT.initialize_totem_config(totem_type), "name": totem_type, "description": totem_type, "active": true}
	ns["totems"] = {"active": (ns["totems"]["active"] as Array) + [new_totem]}
	var nc := cards.duplicate()
	nc.remove_at(card_index)
	ns["hand"] = {"cards": nc}
	return {"success": true, "newState": ns, "scoreAdded": 0}


# ----------------------------------------------------------------------------
# step convenience: construct rng, execute, apply the validator/client caller
# overrides (accumulated score, rngIndices, moveIndex), return next + hash.
# ----------------------------------------------------------------------------

static func step(state: Dictionary, direction: String) -> Dictionary:
	var rng := MbRandomS.new(state["randomSeeds"], state["rngIndices"])
	var res := execute_swipe_action(state, direction, rng)
	var ns: Dictionary = res["newState"]
	var next := ns.duplicate()
	next["score"] = int(ns["score"]) + int(res["scoreAdded"])
	next["rngIndices"] = rng.get_indices()
	next["moveIndex"] = int(state["moveIndex"]) + (2 if res["cardDrawn"] else 1)
	return {"state": next, "hash": Hasher.hash_value(next), "scoreAdded": res["scoreAdded"], "cardDrawn": res["cardDrawn"], "moved": res["moved"], "destroyed": res.get("destroyed", [])}


static func step_card(state: Dictionary, action: String, action_data: Dictionary, card_index: int) -> Dictionary:
	var rng := MbRandomS.new(state["randomSeeds"], state["rngIndices"])
	var res := execute_play_card_action(state, action, action_data, card_index, rng)
	var ns: Dictionary = res["newState"]
	var next := ns.duplicate()
	next["score"] = int(ns["score"]) + int(res["scoreAdded"])
	next["rngIndices"] = rng.get_indices()
	next["moveIndex"] = int(state["moveIndex"]) + 1
	return {"state": next, "hash": Hasher.hash_value(next), "success": res["success"], "scoreAdded": res["scoreAdded"]}


static func step_totem(state: Dictionary, totem_type: String, card_index: int) -> Dictionary:
	var res := execute_spawn_totem_action(state, totem_type, card_index)
	var ns: Dictionary = res["newState"]
	var next := ns.duplicate()
	next["rngIndices"] = (state["rngIndices"] as Dictionary).duplicate()
	next["moveIndex"] = int(state["moveIndex"]) + 1
	return {"state": next, "hash": Hasher.hash_value(next), "success": res["success"]}
