@tool
class_name MbEngine
extends RefCounted

## Deterministic swipe engine — GDScript port of the Moveborne rules spine
## (moveborne/src/logic/src: merge.ts, actionExecutor.ts, shards.ts, cardDraw.ts).
##
## SCOPE (Phase 1 spine): swipe / merge / spawn / combo / score / shards / auto-draw,
## with tile-effects, totems, events and global-effects as faithful no-op stubs
## (they consume no RNG and add no state when inactive — verified against the TS
## oracle). The breadth workflow fills the stubs in. State is a Dictionary mirror
## of SynchronizedGameState; reference semantics match JS (Dictionary/Array are
## reference types), so the exact merge.ts mutation behavior is reproduced.

const C := preload("res://engine/constants.gd")
const Hasher := preload("res://engine/hasher.gd")
const MbRandomS := preload("res://engine/random_generator.gd")

# ----------------------------------------------------------------------------
# board helpers (board.ts / factories.ts)
# ----------------------------------------------------------------------------

static func create_empty_tile(row: int, col: int) -> Dictionary:
	return {"isEmpty": true, "value": 0, "row": row, "col": col, "status": "normal"}


# ----------------------------------------------------------------------------
# swipe (merge.ts swipeLeft/Right/Up/Down — no-effect spine fast path)
# Each returns {moved, score, count}. `t` is mutated in place (shared dict refs).
# ----------------------------------------------------------------------------

static func _swipe_left(t: Array, merged: Dictionary, size: int) -> Dictionary:
	var moved := false
	var score := 0
	var count := 0
	for row in range(size):
		for col in range(1, size):
			var tile = t[row * size + col]
			if tile == null or tile["isEmpty"]:
				continue
			var target := col
			for check in range(col - 1, -1, -1):
				var ct = t[row * size + check]
				if ct["isEmpty"]:
					target = check
				elif int(ct["value"]) == int(tile["value"]) and not merged.has(row * size + check):
					target = check
					break
				else:
					break
			if target != col:
				moved = true
				var r := _apply(t, merged, size, row * size + col, row * size + target, tile, row, col, row, target)
				if r >= 0:
					score += r
					count += 1
	return {"moved": moved, "score": score, "count": count}


static func _swipe_right(t: Array, merged: Dictionary, size: int) -> Dictionary:
	var moved := false
	var score := 0
	var count := 0
	for row in range(size):
		for col in range(size - 2, -1, -1):
			var tile = t[row * size + col]
			if tile == null or tile["isEmpty"]:
				continue
			var target := col
			for check in range(col + 1, size):
				var ct = t[row * size + check]
				if ct["isEmpty"]:
					target = check
				elif int(ct["value"]) == int(tile["value"]) and not merged.has(row * size + check):
					target = check
					break
				else:
					break
			if target != col:
				moved = true
				var r := _apply(t, merged, size, row * size + col, row * size + target, tile, row, col, row, target)
				if r >= 0:
					score += r
					count += 1
	return {"moved": moved, "score": score, "count": count}


static func _swipe_up(t: Array, merged: Dictionary, size: int) -> Dictionary:
	var moved := false
	var score := 0
	var count := 0
	for col in range(size):
		for row in range(1, size):
			var tile = t[row * size + col]
			if tile == null or tile["isEmpty"]:
				continue
			var target := row
			for check in range(row - 1, -1, -1):
				var ct = t[check * size + col]
				if ct["isEmpty"]:
					target = check
				elif int(ct["value"]) == int(tile["value"]) and not merged.has(check * size + col):
					target = check
					break
				else:
					break
			if target != row:
				moved = true
				var r := _apply(t, merged, size, row * size + col, target * size + col, tile, row, col, target, col)
				if r >= 0:
					score += r
					count += 1
	return {"moved": moved, "score": score, "count": count}


static func _swipe_down(t: Array, merged: Dictionary, size: int) -> Dictionary:
	var moved := false
	var score := 0
	var count := 0
	for col in range(size):
		for row in range(size - 2, -1, -1):
			var tile = t[row * size + col]
			if tile == null or tile["isEmpty"]:
				continue
			var target := row
			for check in range(row + 1, size):
				var ct = t[check * size + col]
				if ct["isEmpty"]:
					target = check
				elif int(ct["value"]) == int(tile["value"]) and not merged.has(check * size + col):
					target = check
					break
				else:
					break
			if target != row:
				moved = true
				var r := _apply(t, merged, size, row * size + col, target * size + col, tile, row, col, target, col)
				if r >= 0:
					score += r
					count += 1
	return {"moved": moved, "score": score, "count": count}


static func _apply(t: Array, merged: Dictionary, size: int, src_idx: int, tgt_idx: int, tile: Dictionary, row: int, col: int, tgt_row: int, tgt_col: int) -> int:
	# Returns the merged tile's value on a merge, or -1 on a plain move.
	var tgt: Dictionary = t[tgt_idx]
	if not tgt["isEmpty"] and int(tgt["value"]) == int(tile["value"]):
		var fv := int(tile["value"]) * 2
		t[tgt_idx] = {"isEmpty": false, "value": fv, "status": "merged", "meta": {}, "row": tgt_row, "col": tgt_col}
		t[src_idx] = create_empty_tile(row, col)
		merged[tgt_idx] = true
		return fv
	else:
		tile["row"] = tgt_row
		tile["col"] = tgt_col
		t[tgt_idx] = tile
		t[src_idx] = create_empty_tile(row, col)
		return -1


static func perform_swipe(state: Dictionary, direction: String, _rng) -> Dictionary:
	# process_totem_effects(PRE_SWIPE) — no-op for the spine.
	var board: Dictionary = state["board"]
	var size: int = int(board["size"])
	var new_tiles: Array = (board["tiles"] as Array).duplicate()  # shallow: shares tile dict refs
	for tile in new_tiles:
		if tile != null:
			tile["status"] = "normal"
	var merged := {}
	var sr: Dictionary
	match direction:
		"left": sr = _swipe_left(new_tiles, merged, size)
		"right": sr = _swipe_right(new_tiles, merged, size)
		"up": sr = _swipe_up(new_tiles, merged, size)
		"down": sr = _swipe_down(new_tiles, merged, size)
		_: sr = {"moved": false, "score": 0, "count": 0}
	var result := state.duplicate()
	result["board"] = board.duplicate()
	result["board"]["tiles"] = new_tiles
	# POST_SWIPE / MOVE_COMPLETED / SWIPE_COMPLETED totems + event spawn — no-op spine.
	return {"gameState": result, "moved": sr["moved"], "score": sr["score"], "mergedTilesCount": sr["count"]}


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
		var has_effect := tl.has("effect") and tl["effect"] != null and bool(tl["effect"].get("active", false)) and str(tl["effect"].get("type", "")) != "none"
		if tl["isEmpty"] and not has_effect:
			empties.append(i)
	if empties.is_empty():
		return {"gameState": state}
	var ri: int = empties[int(floor(rng.get_random(C.NS_TILE_GEN) * empties.size()))]
	var value: int = 2 if rng.get_random(C.NS_TILE_GEN) < 0.9 else 4
	# process_totem_effects(TILE_SPAWN) — no-op; value unchanged.
	var new_tiles: Array = tiles.duplicate()
	new_tiles[ri] = {"isEmpty": false, "value": value, "status": "new", "meta": {}, "row": int(ri / size), "col": ri % size}
	var result := state.duplicate()
	result["board"] = board.duplicate()
	result["board"]["tiles"] = new_tiles
	# POST_SPAWN totem + attemptSpawnEffectOnTile — no-op (no scenario spawn configs, no RNG).
	return {"gameState": result}


static func update_combo_multiplier(state: Dictionary, merged_count: int, _rng) -> Dictionary:
	var s := state.duplicate()
	if merged_count == 0:
		# Combo break; no Combo Saver totem -> reset to 0. (No eventRules -> no spawn.)
		s["comboMultiplier"] = 0
	else:
		# No Momentum Idol -> increment equals merged_count.
		s["comboMultiplier"] = int(state["comboMultiplier"]) + merged_count
	return s


static func calculate_combo_score(base_score: int, combo_multiplier: int) -> int:
	if combo_multiplier <= 0:
		return base_score
	return base_score * combo_multiplier


static func calculate_shards(current: int, to_add: int) -> int:
	return min(current + to_add, C.SHARDS_PER_CARD)


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
# action executor (actionExecutor.ts executeSwipeAction)
# ----------------------------------------------------------------------------

static func execute_swipe_action(state: Dictionary, direction: String, rng) -> Dictionary:
	# reset_triggered_states — no-op spine.
	var result := perform_swipe(state, direction, rng)
	if result["moved"]:
		var ns: Dictionary = result["gameState"]
		ns = update_combo_multiplier(ns, int(result["mergedTilesCount"]), rng)
		var total_score: int
		if int(result["score"]) >= 0:
			total_score = calculate_combo_score(int(result["score"]), int(ns["comboMultiplier"]))
		else:
			total_score = int(result["score"])
		# mergedTilesCount>0: POST_SWIPE totem (shard multiplier) — no-op, multiplier stays 1.
		var shards_to_add: int = int(result["mergedTilesCount"])
		var add_res := add_random_tile_with_effects(ns, rng)
		ns = add_res["gameState"]
		# update_trigger_states — no-op.
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
		# process_global_effects(MOVE_COMPLETED) — no-op spine.
		return {"newState": ns, "scoreAdded": total_score, "shardsAdded": shards_to_add, "moved": true, "cardDrawn": card_drawn, "drawnCard": drawn_card}
	else:
		var ns: Dictionary = result["gameState"]
		ns = update_combo_multiplier(ns, 0, rng)
		# FAILED_SWIPE totem — no-op.
		var add_res := add_random_tile_with_effects(ns, rng)
		ns = add_res["gameState"]
		# process_global_effects — no-op.
		return {"newState": ns, "scoreAdded": 0, "shardsAdded": 0, "moved": false, "cardDrawn": false, "drawnCard": null}


# ----------------------------------------------------------------------------
# step convenience: construct rng, execute, apply the validator/client caller
# overrides (accumulated score, rngIndices, moveIndex+2-on-draw), return next + hash.
# ----------------------------------------------------------------------------

static func step(state: Dictionary, direction: String) -> Dictionary:
	var rng := MbRandomS.new(state["randomSeeds"], state["rngIndices"])
	var res := execute_swipe_action(state, direction, rng)
	var ns: Dictionary = res["newState"]
	var next := ns.duplicate()
	next["score"] = int(ns["score"]) + int(res["scoreAdded"])
	next["rngIndices"] = rng.get_indices()
	next["moveIndex"] = int(state["moveIndex"]) + (2 if res["cardDrawn"] else 1)
	return {"state": next, "hash": Hasher.hash_value(next), "scoreAdded": res["scoreAdded"], "cardDrawn": res["cardDrawn"], "moved": res["moved"]}
