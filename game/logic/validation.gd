@tool
class_name MbValidation
extends RefCounted

## Validation predicates — GDScript port of moveborne/src/logic/src/validation.ts.
##
## Pure boolean functions over the flat `tiles` Array (row-major, length = boardSize^2).
## boardSize is derived as sqrt(tiles.length). Each predicate determines card target
## legality / playability and is byte-for-byte equivalent to its TS counterpart.
##
## Tile dicts mirror SynchronizedTileState: {isEmpty, value, row, col, status, [effect]}.
## An effect dict is {type, active, config, ...}; ".effect?.active" maps to a guarded
## lookup of the "active" field, ".effect" truthiness maps to "has a non-null effect".
##
## NOTE: like the TS, the position predicates that call getTile WITHOUT first checking
## isValidPosition (split/multiply/radiate/cloneSource/cloneTarget/lightning/teleport*/
## bomb/destroy/double, and clear-column) will index out of range for OOB args, matching
## the TS `throw new Error("Invalid row or column")`. Callers pass in-range positions.

# ---------------------------------------------------------------------------
# board helpers (board.ts)
# ---------------------------------------------------------------------------

static func _is_valid_position(row: int, col: int, board_size: int) -> bool:
	return row >= 0 and row < board_size and col >= 0 and col < board_size


static func _get_tile(tiles: Array, row: int, col: int, board_size: int) -> Dictionary:
	# Mirrors getTile: throws on invalid position. We surface the same intent via
	# an assertion; callers (and the golden) only ever pass in-range coordinates.
	assert(_is_valid_position(row, col, board_size), "Invalid row or column")
	return tiles[row * board_size + col]


static func _board_size(tiles: Array) -> int:
	return int(round(sqrt(float(tiles.size()))))


# An effect's truthiness: present and non-null (mirrors JS `tile.effect`).
static func _has_effect(tile: Dictionary) -> bool:
	return tile.has("effect") and tile["effect"] != null


# Mirrors JS `tile.effect?.active` truthiness: false when no effect, else the field.
static func _effect_active(tile: Dictionary) -> bool:
	if not _has_effect(tile):
		return false
	var eff = tile["effect"]
	return bool((eff as Dictionary).get("active", false))


# ---------------------------------------------------------------------------
# hasValid* predicates (whole-board playability)
# ---------------------------------------------------------------------------

static func has_valid_split_tiles(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	for row in range(board_size):
		for col in range(board_size):
			var tile := _get_tile(tiles, row, col, board_size)
			if not tile["isEmpty"] and int(tile["value"]) > 2:
				return true
	return false


static func has_valid_multiply_tiles(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	for row in range(board_size):
		for col in range(board_size):
			var tile := _get_tile(tiles, row, col, board_size)
			if not tile["isEmpty"]:
				return true
	return false


static func has_valid_shuffle_tiles(tiles: Array) -> bool:
	var tile_count := 0
	for i in range(tiles.size()):
		if not (tiles[i] as Dictionary)["isEmpty"]:
			tile_count += 1
	return tile_count >= 2


static func has_valid_lightning_tiles(tiles: Array) -> bool:
	for i in range(tiles.size()):
		if not (tiles[i] as Dictionary)["isEmpty"]:
			return true
	return false


static func has_valid_radiate_tiles(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	for row in range(board_size):
		for col in range(board_size):
			var center_tile := _get_tile(tiles, row, col, board_size)
			if center_tile["isEmpty"]:
				continue
			var adjacent := [
				[row - 1, col - 1], [row - 1, col], [row - 1, col + 1],
				[row, col - 1], [row, col + 1],
				[row + 1, col - 1], [row + 1, col], [row + 1, col + 1],
			]
			for pos in adjacent:
				if not _is_valid_position(pos[0], pos[1], board_size):
					continue
				var adjacent_tile := _get_tile(tiles, pos[0], pos[1], board_size)
				if not adjacent_tile["isEmpty"]:
					return true
	return false


static func has_valid_clone_tiles(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	for row in range(board_size):
		for col in range(board_size):
			var tile := _get_tile(tiles, row, col, board_size)
			if tile["isEmpty"]:
				continue
			var adjacent := [
				[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1],
			]
			for pos in adjacent:
				if not _is_valid_position(pos[0], pos[1], board_size):
					continue
				var adjacent_tile := _get_tile(tiles, pos[0], pos[1], board_size)
				if adjacent_tile["isEmpty"]:
					return true
	return false


static func has_valid_swap_tiles(tiles: Array) -> bool:
	var tile_count := 0
	for i in range(tiles.size()):
		if not (tiles[i] as Dictionary)["isEmpty"]:
			tile_count += 1
	return tile_count >= 2


static func has_valid_vortex_tiles(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	for row in range(board_size - 1):
		for col in range(board_size - 1):
			if not _is_valid_position(row, col, board_size):
				continue
			if not _is_valid_position(row, col + 1, board_size):
				continue
			if not _is_valid_position(row + 1, col, board_size):
				continue
			if not _is_valid_position(row + 1, col + 1, board_size):
				continue
			var top_left := _get_tile(tiles, row, col, board_size)
			var top_right := _get_tile(tiles, row, col + 1, board_size)
			var bottom_left := _get_tile(tiles, row + 1, col, board_size)
			var bottom_right := _get_tile(tiles, row + 1, col + 1, board_size)
			if not top_left["isEmpty"] or not top_right["isEmpty"] \
					or not bottom_left["isEmpty"] or not bottom_right["isEmpty"]:
				return true
	return false


static func has_valid_teleport_tiles(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	var has_source := false
	var has_empty := false
	for row in range(board_size):
		for col in range(board_size):
			var tile := _get_tile(tiles, row, col, board_size)
			if not tile["isEmpty"]:
				has_source = true
			elif tile["isEmpty"]:
				has_empty = true
	return has_source and has_empty


static func has_valid_bomb_tiles(tiles: Array) -> bool:
	for i in range(tiles.size()):
		var tile := tiles[i] as Dictionary
		if not tile["isEmpty"] or _has_effect(tile):
			return true
	return false


static func has_valid_destroy_tiles(tiles: Array) -> bool:
	for i in range(tiles.size()):
		var tile := tiles[i] as Dictionary
		if not tile["isEmpty"] and not _effect_active(tile):
			return true
	return false


static func has_valid_clear_columns(tiles: Array) -> bool:
	var board_size := _board_size(tiles)
	for col in range(board_size):
		for row in range(board_size):
			var tile := _get_tile(tiles, row, col, board_size)
			if not tile["isEmpty"] and not _effect_active(tile):
				return true
	return false


static func has_valid_double_tiles(tiles: Array) -> bool:
	for i in range(tiles.size()):
		var tile := tiles[i] as Dictionary
		if not tile["isEmpty"] and not _effect_active(tile):
			return true
	return false


static func has_valid_transform_tiles(tiles: Array) -> bool:
	for i in range(tiles.size()):
		var tile := tiles[i] as Dictionary
		if _has_effect(tile) and str((tile["effect"] as Dictionary).get("type", "")) != "none":
			return true
	return false


# ---------------------------------------------------------------------------
# isValid* predicates (single position / column)
# ---------------------------------------------------------------------------

static func is_valid_swap_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	if not _is_valid_position(row, col, board_size):
		return false
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"]


static func is_valid_vortex_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	if row >= board_size - 1 or col >= board_size - 1:
		return false
	var top_left := _get_tile(tiles, row, col, board_size)
	var top_right := _get_tile(tiles, row, col + 1, board_size)
	var bottom_left := _get_tile(tiles, row + 1, col, board_size)
	var bottom_right := _get_tile(tiles, row + 1, col + 1, board_size)
	return not top_left["isEmpty"] or not top_right["isEmpty"] \
			or not bottom_left["isEmpty"] or not bottom_right["isEmpty"]


static func is_valid_split_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"] and int(tile["value"]) > 2


static func is_valid_multiply_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"]


static func is_valid_radiate_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	if tile["isEmpty"]:
		return false
	var adjacent := [
		[row - 1, col - 1], [row - 1, col], [row - 1, col + 1],
		[row, col - 1], [row, col + 1],
		[row + 1, col - 1], [row + 1, col], [row + 1, col + 1],
	]
	for pos in adjacent:
		if not _is_valid_position(pos[0], pos[1], board_size):
			continue
		var adjacent_tile := _get_tile(tiles, pos[0], pos[1], board_size)
		if not adjacent_tile["isEmpty"]:
			return true
	return false


static func is_valid_clone_source_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	if tile["isEmpty"]:
		return false
	var adjacent := [
		[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1],
	]
	for pos in adjacent:
		if not _is_valid_position(pos[0], pos[1], board_size):
			continue
		var adjacent_tile := _get_tile(tiles, pos[0], pos[1], board_size)
		if adjacent_tile["isEmpty"]:
			return true
	return false


# sourcePos is a Dictionary {row, col} or null. Mirrors the TS adjacency check.
static func is_valid_clone_target_position(tiles: Array, row: int, col: int, source_pos) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	if not tile["isEmpty"]:
		return false
	if source_pos != null:
		var sp := source_pos as Dictionary
		var is_adjacent: bool = abs(int(sp["row"]) - row) + abs(int(sp["col"]) - col) == 1
		return is_adjacent
	return true


static func is_valid_lightning_column(tiles: Array, _row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	for r in range(board_size):
		var tile := _get_tile(tiles, r, col, board_size)
		if not tile["isEmpty"]:
			return true
	return false


static func is_valid_teleport_source_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"]


static func is_valid_teleport_target_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return bool(tile["isEmpty"])


static func is_valid_bomb_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"] or _has_effect(tile)


static func is_valid_destroy_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"] and not _effect_active(tile)


static func is_valid_clear_column(tiles: Array, col: int) -> bool:
	var board_size := _board_size(tiles)
	for row in range(board_size):
		var tile := _get_tile(tiles, row, col, board_size)
		if not tile["isEmpty"] and not _effect_active(tile):
			return true
	return false


static func is_valid_double_position(tiles: Array, row: int, col: int) -> bool:
	var board_size := _board_size(tiles)
	var tile := _get_tile(tiles, row, col, board_size)
	return not tile["isEmpty"] and not _effect_active(tile)
