@tool
class_name MbPowerCards
extends RefCounted

## Power card board mutations — GDScript port of
## moveborne/src/logic/src/powerCards.ts (the 14 performPowerCard* functions).
##
## Each takes the flat row-major `tiles` Array of tile Dictionaries (+ params +
## board size; shuffle/transform also take an MbRandom), and returns
## {"tiles": Array, "success": bool, "score": int}. Failure paths may also carry
## an "error" string (mirrors the TS), but only tiles/success/score are verified.
##
## Reference semantics match JS: `clear_tile_statuses` shallow-copies the array
## and mutates the shared non-empty tile dicts in place (status -> "normal");
## object literals become NEW dicts; spreads (`...tile`) become shallow .duplicate().
##
## Non-empty tiles produced by these ops carry "meta": {} exactly where the TS
## object literals include `meta: {}`. The `effect` key is included only when the
## source tile carried one (null/undefined effect keys are omitted, matching JS
## JSON dropping `undefined`). Spawned/destroyed empties carry no "meta".

const C := preload("res://engine/constants.gd")

# ----------------------------------------------------------------------------
# board helpers (board.ts)
# ----------------------------------------------------------------------------

static func _create_empty_tile(row: int, col: int) -> Dictionary:
	return {"isEmpty": true, "value": 0, "row": row, "col": col, "status": "normal"}


static func _index_to_row_col(index: int, board_size: int) -> Dictionary:
	return {"row": int(floor(float(index) / board_size)), "col": index % board_size}


static func _is_valid_position(row, col, board_size: int) -> bool:
	if row == null or col == null:
		return false
	return row >= 0 and row < board_size and col >= 0 and col < board_size


static func _get_tile(tiles: Array, row: int, col: int, board_size: int) -> Dictionary:
	return tiles[row * board_size + col]


static func _set_tile(tiles: Array, tile: Dictionary, board_size: int) -> void:
	tiles[int(tile["row"]) * board_size + int(tile["col"])] = tile


# clearTileStatuses: shallow-copy array, mutate shared non-empty tile dicts in place.
static func _clear_tile_statuses(tiles: Array) -> Array:
	var cleared: Array = tiles.duplicate()
	for tile in cleared:
		if tile != null and not tile["isEmpty"]:
			tile["status"] = "normal"
	return cleared


# Helper: build a non-empty tile dict, including "effect" only if `effect` is non-null.
static func _tile_with_optional_effect(d: Dictionary, effect) -> Dictionary:
	if effect != null:
		d["effect"] = effect
	return d


# Helper: shallow-duplicate a tile, dropping a null "effect" key so canonical
# serialization matches JS (undefined effect omitted).
static func _dup_tile(tile: Dictionary) -> Dictionary:
	var d: Dictionary = tile.duplicate()
	if d.has("effect") and d["effect"] == null:
		d.erase("effect")
	return d


# ----------------------------------------------------------------------------
# SPLIT
# ----------------------------------------------------------------------------

static func perform_power_card_split(tiles: Array, tile_pos, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if tile_pos == null or tile_pos.get("row") == null or tile_pos.get("col") == null:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile position not provided"}

	var row := int(tile_pos["row"])
	var col := int(tile_pos["col"])
	if not _is_valid_position(row, col, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile position out of bounds"}

	var tile_data := _get_tile(new_tiles, row, col, board_size)
	if tile_data["isEmpty"] or int(tile_data["value"]) <= 2:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var split_value := int(tile_data["value"]) / 2
	var nt := _tile_with_optional_effect(
		{"value": split_value, "status": "split", "meta": {}, "row": row, "col": col, "isEmpty": false},
		tile_data.get("effect"))
	_set_tile(new_tiles, nt, board_size)
	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# MULTIPLY
# ----------------------------------------------------------------------------

static func perform_power_card_multiply(tiles: Array, tile_pos, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if tile_pos == null or tile_pos.get("row") == null or tile_pos.get("col") == null:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile position not provided"}

	var row := int(tile_pos["row"])
	var col := int(tile_pos["col"])
	if not _is_valid_position(row, col, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile position out of bounds"}

	var tile_data := _get_tile(new_tiles, row, col, board_size)
	if tile_data["isEmpty"] or not _truthy(tile_data.get("value")):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var multiplied := int(tile_data["value"]) * 2
	var nt := _tile_with_optional_effect(
		{"value": multiplied, "status": "multiplied", "meta": {}, "row": row, "col": col, "isEmpty": false},
		tile_data.get("effect"))
	_set_tile(new_tiles, nt, board_size)
	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# SHUFFLE (consumes SHUFFLE rng)
# ----------------------------------------------------------------------------

static func perform_power_card_shuffle(tiles: Array, rng, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	var existing: Array = []
	for i in range(new_tiles.size()):
		if not new_tiles[i]["isEmpty"]:
			var copy: Dictionary = (new_tiles[i] as Dictionary).duplicate()
			copy["status"] = "shuffled"
			existing.append(copy)

	if existing.is_empty():
		return {"tiles": new_tiles, "success": false, "score": 0}

	for i in range(new_tiles.size()):
		var rc := _index_to_row_col(i, board_size)
		new_tiles[i] = _create_empty_tile(int(rc["row"]), int(rc["col"]))

	# Fisher-Yates on existing tiles.
	for i in range(existing.size() - 1, 0, -1):
		var j := int(floor(rng.get_random(C.NS_SHUFFLE) * (i + 1)))
		var tmp = existing[i]
		existing[i] = existing[j]
		existing[j] = tmp

	var available: Array = []
	for i in range(new_tiles.size()):
		available.append(i)

	# Fisher-Yates on positions.
	for i in range(available.size() - 1, 0, -1):
		var j := int(floor(rng.get_random(C.NS_SHUFFLE) * (i + 1)))
		var tmp = available[i]
		available[i] = available[j]
		available[j] = tmp

	for i in range(existing.size()):
		var target_index := int(available[i])
		var rc := _index_to_row_col(target_index, board_size)
		var placed: Dictionary = (existing[i] as Dictionary).duplicate()
		placed["row"] = int(rc["row"])
		placed["col"] = int(rc["col"])
		new_tiles[target_index] = placed

	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# LIGHTNING
# ----------------------------------------------------------------------------

static func perform_power_card_lightning(tiles: Array, column, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if column == null or int(column) < 0 or int(column) >= board_size:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Invalid column"}

	var col := int(column)
	var has_valid := false
	for row in range(board_size):
		var tile := _get_tile(new_tiles, row, col, board_size)
		if _truthy(tile.get("value")):
			has_valid = true
			break
	if not has_valid:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var total_score := 0
	for row in range(board_size):
		var tile := _get_tile(new_tiles, row, col, board_size)
		if not tile["isEmpty"]:
			var new_value := int(tile["value"]) * 2
			var nt := _tile_with_optional_effect(
				{"isEmpty": false, "row": row, "col": col, "value": new_value, "status": "lightning", "meta": {}},
				tile.get("effect"))
			_set_tile(new_tiles, nt, board_size)
			total_score += new_value

	return {"tiles": new_tiles, "success": true, "score": total_score}


# ----------------------------------------------------------------------------
# RADIATE
# ----------------------------------------------------------------------------

static func perform_power_card_radiate(tiles: Array, tile_pos, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if tile_pos == null or tile_pos.get("row") == null or tile_pos.get("col") == null:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile position not provided"}

	var prow := int(tile_pos["row"])
	var pcol := int(tile_pos["col"])
	if not _is_valid_position(prow, pcol, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile position out of bounds"}

	var center := _get_tile(new_tiles, prow, pcol, board_size)
	if not _truthy(center.get("value")):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var adjacent := [
		[prow - 1, pcol - 1], [prow - 1, pcol], [prow - 1, pcol + 1],
		[prow, pcol - 1], [prow, pcol + 1],
		[prow + 1, pcol - 1], [prow + 1, pcol], [prow + 1, pcol + 1],
	]

	var total_score := 0
	var affected := 0
	for pos in adjacent:
		var r: int = pos[0]
		var c: int = pos[1]
		if not _is_valid_position(r, c, board_size):
			continue
		var adj := _get_tile(new_tiles, r, c, board_size)
		if not adj["isEmpty"]:
			var new_value := int(adj["value"]) * 2
			var nt := _tile_with_optional_effect(
				{"value": new_value, "status": "radiated", "meta": {}, "row": r, "col": c, "isEmpty": false},
				adj.get("effect"))
			_set_tile(new_tiles, nt, board_size)
			total_score += new_value
			affected += 1

	if affected == 0:
		return {"tiles": new_tiles, "success": false, "score": 0}

	return {"tiles": new_tiles, "success": true, "score": total_score}


# ----------------------------------------------------------------------------
# CLONE
# ----------------------------------------------------------------------------

static func perform_power_card_clone(tiles: Array, source_pos, target_pos, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if source_pos == null or source_pos.get("row") == null or source_pos.get("col") == null \
			or target_pos == null or target_pos.get("row") == null or target_pos.get("col") == null:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Source or target tile position not provided"}

	var sr := int(source_pos["row"])
	var sc := int(source_pos["col"])
	var tr := int(target_pos["row"])
	var tc := int(target_pos["col"])
	if not _is_valid_position(sr, sc, board_size) or not _is_valid_position(tr, tc, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Source or target tile position out of bounds"}

	var source := _get_tile(new_tiles, sr, sc, board_size)
	if source["isEmpty"]:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var target := _get_tile(new_tiles, tr, tc, board_size)
	if not target["isEmpty"]:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var is_adjacent := absi(sr - tr) + absi(sc - tc) == 1
	if not is_adjacent:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var nt := _tile_with_optional_effect(
		{"value": int(source["value"]), "status": "cloned", "meta": {}, "row": tr, "col": tc, "isEmpty": false},
		source.get("effect"))
	_set_tile(new_tiles, nt, board_size)
	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# SWAP
# ----------------------------------------------------------------------------

static func perform_power_card_swap(tiles: Array, tile1, tile2, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if tile1 == null or tile1.get("row") == null or tile1.get("col") == null \
			or tile2 == null or tile2.get("row") == null or tile2.get("col") == null:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile positions not provided"}

	var r1 := int(tile1["row"])
	var c1 := int(tile1["col"])
	var r2 := int(tile2["row"])
	var c2 := int(tile2["col"])
	if not _is_valid_position(r1, c1, board_size) or not _is_valid_position(r2, c2, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Tile positions out of bounds"}

	if r1 == r2 and c1 == c2:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var data1 := _get_tile(new_tiles, r1, c1, board_size)
	var data2 := _get_tile(new_tiles, r2, c2, board_size)
	if data1["isEmpty"] or data2["isEmpty"]:
		return {"tiles": new_tiles, "success": false, "score": 0}

	# data2 -> position 1 (with status "swapped", meta {}). data2 is non-empty here.
	var new1 := _dup_tile(data2)
	new1["row"] = r1
	new1["col"] = c1
	new1["status"] = "swapped"
	new1["meta"] = {}
	_set_tile(new_tiles, new1, board_size)

	# data1 -> position 2.
	var new2 := _dup_tile(data1)
	new2["row"] = r2
	new2["col"] = c2
	new2["status"] = "swapped"
	new2["meta"] = {}
	_set_tile(new_tiles, new2, board_size)

	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# VORTEX (2x2 clockwise rotation)
# ----------------------------------------------------------------------------

static func perform_power_card_vortex(tiles: Array, quadrant_pos, board_size: int) -> Dictionary:
	if quadrant_pos == null or quadrant_pos.get("row") == null or quadrant_pos.get("col") == null:
		return {"tiles": tiles, "success": false, "score": 0, "error": "Row or column not provided"}

	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	var qr := int(quadrant_pos["row"])
	var qc := int(quadrant_pos["col"])
	if not _is_valid_position(qr, qc, board_size) \
			or not _is_valid_position(qr + 1, qc + 1, board_size) \
			or not _is_valid_position(qr + 1, qc, board_size) \
			or not _is_valid_position(qr, qc + 1, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Invalid quadrant position"}

	var top_left := _get_tile(new_tiles, qr, qc, board_size)
	var top_right := _get_tile(new_tiles, qr, qc + 1, board_size)
	var bottom_left := _get_tile(new_tiles, qr + 1, qc, board_size)
	var bottom_right := _get_tile(new_tiles, qr + 1, qc + 1, board_size)

	# Clockwise rotation via spreads (...tile) -> NEW dicts with new row/col.
	var n_tl := _dup_tile(top_left)
	n_tl["row"] = qr
	n_tl["col"] = qc + 1
	_set_tile(new_tiles, n_tl, board_size)  # topLeft -> topRight

	var n_tr := _dup_tile(top_right)
	n_tr["row"] = qr + 1
	n_tr["col"] = qc + 1
	_set_tile(new_tiles, n_tr, board_size)  # topRight -> bottomRight

	var n_br := _dup_tile(bottom_right)
	n_br["row"] = qr + 1
	n_br["col"] = qc
	_set_tile(new_tiles, n_br, board_size)  # bottomRight -> bottomLeft

	var n_bl := _dup_tile(bottom_left)
	n_bl["row"] = qr
	n_bl["col"] = qc
	_set_tile(new_tiles, n_bl, board_size)  # bottomLeft -> topLeft

	# Mark all four rotated (mutate in place; tiles always present).
	_get_tile(new_tiles, qr, qc, board_size)["status"] = "rotated"
	_get_tile(new_tiles, qr, qc + 1, board_size)["status"] = "rotated"
	_get_tile(new_tiles, qr + 1, qc, board_size)["status"] = "rotated"
	_get_tile(new_tiles, qr + 1, qc + 1, board_size)["status"] = "rotated"

	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# TELEPORT
# ----------------------------------------------------------------------------

static func perform_power_card_teleport(tiles: Array, source_pos, target_pos, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if source_pos == null or source_pos.get("row") == null or source_pos.get("col") == null \
			or target_pos == null or target_pos.get("row") == null or target_pos.get("col") == null:
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Source or target tile position not provided"}

	var sr := int(source_pos["row"])
	var sc := int(source_pos["col"])
	var tr := int(target_pos["row"])
	var tc := int(target_pos["col"])
	if not _is_valid_position(sr, sc, board_size) or not _is_valid_position(tr, tc, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0, "error": "Source or target tile position out of bounds"}

	if sr == tr and sc == tc:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var source := _get_tile(new_tiles, sr, sc, board_size)
	if source["isEmpty"]:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var target := _get_tile(new_tiles, tr, tc, board_size)
	if not target["isEmpty"]:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var nt := _tile_with_optional_effect(
		{"value": int(source["value"]), "status": "teleported", "meta": {}, "row": tr, "col": tc, "isEmpty": false},
		source.get("effect"))
	_set_tile(new_tiles, nt, board_size)
	_set_tile(new_tiles, _create_empty_tile(sr, sc), board_size)
	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# BOMB
# ----------------------------------------------------------------------------

static func perform_power_card_bomb(tiles: Array, target_tile, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if target_tile == null:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var row = target_tile.get("row")
	var col = target_tile.get("col")
	if not _is_valid_position(row, col, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var tile := _get_tile(new_tiles, int(row), int(col), board_size)
	if tile["isEmpty"] and not _truthy(tile.get("effect")):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var negative_score := 0 if tile["isEmpty"] else -int(tile["value"])

	# {...tile, isEmpty:true, value:0, effect:undefined, status:"bombed"}
	# -> NEW dict from spread, then overwrite. effect:undefined => omit key.
	var nt := _dup_tile(tile)
	nt["isEmpty"] = true
	nt["value"] = 0
	nt.erase("effect")
	nt["status"] = "bombed"
	_set_tile(new_tiles, nt, board_size)

	return {"tiles": new_tiles, "success": true, "score": negative_score}


# ----------------------------------------------------------------------------
# DESTROY
# ----------------------------------------------------------------------------

static func perform_power_card_destroy(tiles: Array, target_tile, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if target_tile == null:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var row = target_tile.get("row")
	var col = target_tile.get("col")
	if not _is_valid_position(row, col, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var tile := _get_tile(new_tiles, int(row), int(col), board_size)
	# Verify tile has a value but NO effect.
	if tile["isEmpty"] or _truthy(tile.get("effect")):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var negative_score := -int(tile["value"])

	# {...tile, isEmpty:true, value:0, status:"destroyed"}
	var nt := _dup_tile(tile)
	nt["isEmpty"] = true
	nt["value"] = 0
	nt["status"] = "destroyed"
	_set_tile(new_tiles, nt, board_size)

	return {"tiles": new_tiles, "success": true, "score": negative_score}


# ----------------------------------------------------------------------------
# CLEAR (Purge Column)
# ----------------------------------------------------------------------------

static func perform_power_card_clear(tiles: Array, column, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if column == null or int(column) < 0 or int(column) >= board_size:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var col := int(column)
	var has_clearable := false
	for row in range(board_size):
		var tile := _get_tile(new_tiles, row, col, board_size)
		if not tile["isEmpty"] and not _truthy(tile.get("effect")):
			has_clearable = true
			break
	if not has_clearable:
		return {"tiles": new_tiles, "success": false, "score": 0}

	for row in range(board_size):
		var tile := _get_tile(new_tiles, row, col, board_size)
		if not tile["isEmpty"] and not _truthy(tile.get("effect")):
			# {...tile, isEmpty:true, value:0, status:"purged"}
			var nt := _dup_tile(tile)
			nt["isEmpty"] = true
			nt["value"] = 0
			nt["status"] = "purged"
			_set_tile(new_tiles, nt, board_size)

	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# DOUBLE (Amplify)
# ----------------------------------------------------------------------------

static func perform_power_card_double(tiles: Array, target_tile, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	if target_tile == null:
		return {"tiles": new_tiles, "success": false, "score": 0}

	var row = target_tile.get("row")
	var col = target_tile.get("col")
	if not _is_valid_position(row, col, board_size):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var tile := _get_tile(new_tiles, int(row), int(col), board_size)
	if tile["isEmpty"] or _truthy(tile.get("effect")):
		return {"tiles": new_tiles, "success": false, "score": 0}

	var new_value := int(tile["value"]) * 2

	# {...tile, value:newValue, status:"amplified"}
	var nt := _dup_tile(tile)
	nt["value"] = new_value
	nt["status"] = "amplified"
	_set_tile(new_tiles, nt, board_size)

	return {"tiles": new_tiles, "success": true, "score": new_value}


# ----------------------------------------------------------------------------
# TRANSFORM (consumes SHUFFLE rng — note: NOT effect-spawn, per powerCards.ts)
# ----------------------------------------------------------------------------

static func perform_power_card_transform(tiles: Array, num_effects: int, rng, board_size: int) -> Dictionary:
	var cleared := _clear_tile_statuses(tiles)
	var new_tiles: Array = cleared.duplicate()

	var with_effects: Array = []
	for i in range(new_tiles.size()):
		var eff = new_tiles[i].get("effect")
		if eff != null and str(eff.get("type", "")) != "none":
			with_effects.append(i)

	if with_effects.is_empty():
		return {"tiles": new_tiles, "success": false, "score": 0}

	for i in range(with_effects.size() - 1, 0, -1):
		var j := int(floor(rng.get_random(C.NS_SHUFFLE) * (i + 1)))
		var tmp = with_effects[i]
		with_effects[i] = with_effects[j]
		with_effects[j] = tmp

	var n := mini(num_effects, with_effects.size())
	for k in range(n):
		var index := int(with_effects[k])
		var rc := _index_to_row_col(index, board_size)
		var tile := _get_tile(new_tiles, int(rc["row"]), int(rc["col"]), board_size)
		# {...tile, effect:undefined, status:"normal"}
		var nt := _dup_tile(tile)
		nt.erase("effect")
		nt["status"] = "normal"
		_set_tile(new_tiles, nt, board_size)

	return {"tiles": new_tiles, "success": true, "score": 0}


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

# JS truthiness for value/effect checks: null, 0, "", false are falsy.
static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0
	if v is String:
		return v != ""
	return true
