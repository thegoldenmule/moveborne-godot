@tool
class_name MbTotems
extends RefCounted

## Deterministic totem engine — GDScript port of
## moveborne/src/logic/src/totemLogic.ts. Byte-exact with the TS/validator.
##
## Entry point: process_totem_effects(game_state, game_event, rng). It shallow-
## "deep-clones" totems.active (NEW totem dicts + NEW config dicts, mirroring the
## TS spread), dispatches each totem to its handler by type, mutates game_state
## and/or the game_event dict in place (tileValue, incrementAmount,
## shardsMultiplier, etc.), then runs the despawn pass.
##
## Reference semantics mirror JS: Dictionary/Array are reference types. We
## .duplicate() (shallow) where the TS uses spreads {...} / [...] and mutate in
## place exactly where the TS does. Only ghost_merge consumes RNG (totem-spawn).

const C := preload("res://engine/constants.gd")

# 4x4 board constant used by magnet_core (mirrors TS BOARD_SIZE).
const _MAGNET_BOARD_SIZE := 4

# ----------------------------------------------------------------------------
# factories / helpers
# ----------------------------------------------------------------------------

static func _create_empty_tile(row: int, col: int) -> Dictionary:
	# Mirrors factories.createEmptyTile.
	return {"isEmpty": true, "value": 0, "row": row, "col": col, "status": "normal"}


static func _index_to_row_col(index: int, board_size: int) -> Dictionary:
	# Mirrors board.indexToRowCol.
	return {"row": int(floor(float(index) / float(board_size))), "col": index % board_size}


static func _find_totem_def(totem_type: String) -> Variant:
	# Object.values(TOTEM_TYPES).find(t => t.id === totemType)
	for key in C.TOTEM_TYPES.keys():
		var def: Dictionary = C.TOTEM_TYPES[key]
		if str(def["id"]) == totem_type:
			return def
	return null


static func _is_spawn_booster(totem_type: String) -> bool:
	return totem_type == "spawn_booster_2x" or totem_type == "spawn_booster_4x" or totem_type == "spawn_booster_8x"


static func _get_spawn_booster_priority(totem_type: String) -> int:
	match totem_type:
		"spawn_booster_8x": return 3
		"spawn_booster_4x": return 2
		"spawn_booster_2x": return 1
		_: return 0


# ----------------------------------------------------------------------------
# entry point
# ----------------------------------------------------------------------------

static func process_totem_effects(game_state: Dictionary, game_event: Dictionary, rng) -> Dictionary:
	var totems = game_state.get("totems")
	if totems == null or totems.get("active") == null or (totems["active"] as Array).is_empty():
		return game_state

	# Deep clone state (shallow spread) with NEW totem dicts + NEW config dicts.
	var src_active: Array = totems["active"]
	var cloned_active: Array = []
	for totem in src_active:
		var t: Dictionary = (totem as Dictionary).duplicate()  # {...totem}
		var cfg = totem.get("config")
		if cfg != null:
			t["config"] = (cfg as Dictionary).duplicate()  # {...totem.config}
		else:
			t["config"] = {
				"maxTallyMarks": 0,
				"mergesRemaining": 0,
				"movesRemaining": 0,
				"swipesRemaining": 0,
				"tallyMarks": 0,
				"spawnValue": 0,
			}
		cloned_active.append(t)

	var modified_state := game_state.duplicate()  # {...extendedState}
	var new_totems := (totems as Dictionary).duplicate()  # {...extendedState.totems}
	new_totems["active"] = cloned_active
	modified_state["totems"] = new_totems

	var event_type := str(game_event.get("type", ""))

	if event_type == "TILE_SPAWN":
		# Collect spawn boosters from the active list.
		var spawn_boosters: Array = []
		for totem in modified_state["totems"]["active"]:
			if _is_spawn_booster(str(totem["type"])):
				spawn_boosters.append(totem)

		if not spawn_boosters.is_empty():
			# reduce: highest priority booster (8x > 4x > 2x); reduce with no
			# initial value seeds with the first element.
			var highest: Dictionary = spawn_boosters[0]
			for i in range(1, spawn_boosters.size()):
				var cur: Dictionary = spawn_boosters[i]
				if _get_spawn_booster_priority(str(cur["type"])) > _get_spawn_booster_priority(str(highest["type"])):
					highest = cur
			modified_state = _process_spawn_booster(modified_state, highest, game_event)

			# Process all other non-spawn-booster totems normally.
			for totem in modified_state["totems"]["active"]:
				if not _is_spawn_booster(str(totem["type"])):
					modified_state = _process_totem_by_type(modified_state, totem, game_event, rng)
		else:
			for totem in modified_state["totems"]["active"]:
				modified_state = _process_totem_by_type(modified_state, totem, game_event, rng)
	else:
		for totem in modified_state["totems"]["active"]:
			modified_state = _process_totem_by_type(modified_state, totem, game_event, rng)

	modified_state = _check_totem_despawn_conditions(modified_state, game_event)
	return modified_state


static func _process_totem_by_type(game_state: Dictionary, totem: Dictionary, game_event: Dictionary, rng) -> Dictionary:
	match str(totem["type"]):
		"combo_saver":
			return _process_combo_saver(game_state, totem, game_event)
		"spawn_booster_2x", "spawn_booster_4x", "spawn_booster_8x":
			return _process_spawn_booster(game_state, totem, game_event)
		"momentum_idol":
			return _process_momentum_idol(game_state, totem, game_event)
		"magnet_core":
			return _process_magnet_core(game_state, totem, game_event)
		"void_gate":
			return _process_void_gate(game_state, totem, game_event)
		"ghost_merge":
			return _process_ghost_merge(game_state, totem, game_event, rng)
		"scavenger":
			return _process_scavenger(game_state, totem, game_event)
		"chrono_anchor":
			return _process_chrono_anchor(game_state)
		_:
			return game_state


# ----------------------------------------------------------------------------
# per-totem handlers
# ----------------------------------------------------------------------------

static func _process_combo_saver(game_state: Dictionary, totem: Dictionary, game_event: Dictionary) -> Dictionary:
	if str(game_event.get("type", "")) == "COMBO_BREAK_ATTEMPTED":
		if not totem.has("config") or totem["config"] == null:
			totem["config"] = {}
		var cfg: Dictionary = totem["config"]
		cfg["tallyMarks"] = int(cfg.get("tallyMarks", 0)) + 1

		if game_event.get("previousCombo") != null:
			game_state["comboMultiplier"] = game_event["previousCombo"]

		var totem_def = _find_totem_def(str(totem["type"]))
		var max_tally := 3
		if totem_def != null and totem_def.get("maxTallyMarks") != null:
			max_tally = int(totem_def.get("maxTallyMarks"))
		if int(cfg["tallyMarks"]) >= max_tally:
			var filtered: Array = []
			for t in game_state["totems"]["active"]:
				if str(t["id"]) != str(totem["id"]):
					filtered.append(t)
			game_state["totems"]["active"] = filtered

	return game_state


static func _process_spawn_booster(game_state: Dictionary, totem: Dictionary, game_event: Dictionary) -> Dictionary:
	if str(game_event.get("type", "")) == "TILE_SPAWN":
		var totem_def = _find_totem_def(str(totem["type"]))
		if totem_def != null and totem_def.get("spawnValue") != null and int(totem_def.get("spawnValue")) != 0:
			game_event["tileValue"] = int(totem_def.get("spawnValue"))

		if not totem.has("config") or totem["config"] == null:
			totem["config"] = {}
		var cfg: Dictionary = totem["config"]
		if cfg.has("movesRemaining") and cfg["movesRemaining"] != null:
			cfg["movesRemaining"] = max(0, int(cfg["movesRemaining"]) - 1)

	return game_state


static func _process_momentum_idol(game_state: Dictionary, totem: Dictionary, game_event: Dictionary) -> Dictionary:
	var event_type := str(game_event.get("type", ""))
	if event_type == "COMBO_INCREMENT":
		game_event["incrementAmount"] = int(game_event.get("incrementAmount", 0)) + 1
	elif event_type == "MOVE_COMPLETED":
		var cfg = totem.get("config")
		if cfg != null and cfg.has("movesRemaining") and cfg["movesRemaining"] != null:
			cfg["movesRemaining"] = max(0, int(cfg["movesRemaining"]) - 1)

	return game_state


static func _process_magnet_core(game_state: Dictionary, totem: Dictionary, game_event: Dictionary) -> Dictionary:
	if str(game_event.get("type", "")) == "POST_SPAWN":
		var size := _MAGNET_BOARD_SIZE
		var new_tiles: Array = (game_state["board"]["tiles"] as Array).duplicate()  # [...tiles]

		var center_positions := [
			{"row": 1, "col": 1},
			{"row": 1, "col": 2},
			{"row": 2, "col": 1},
			{"row": 2, "col": 2},
		]

		var moved_tiles := {}  # Set<index>

		var moved := true
		while moved:
			moved = false

			# Gather non-empty tile positions.
			var tile_positions: Array = []
			for row in range(size):
				for col in range(size):
					var tile = new_tiles[row * size + col]
					if tile != null and not tile["isEmpty"]:
						tile_positions.append({
							"row": row,
							"col": col,
							"tile": tile,
							"distance": _magnet_distance_to_center(row, col, center_positions),
						})

			# Sort by distance, farthest first. JS Array.sort is stable (V8);
			# use a stable sort keyed by (-distance, original index).
			_stable_sort_by_distance_desc(tile_positions)

			for tp in tile_positions:
				var row: int = tp["row"]
				var col: int = tp["col"]
				var tile: Dictionary = tp["tile"]
				var nearest := _magnet_nearest_center(row, col, center_positions)

				var new_row := row
				var new_col := col
				var row_diff: int = int(nearest["row"]) - row
				var col_diff: int = int(nearest["col"]) - col

				if abs(row_diff) > abs(col_diff):
					if row_diff > 0:
						new_row = row + 1
					elif row_diff < 0:
						new_row = row - 1
				elif abs(col_diff) > 0:
					if col_diff > 0:
						new_col = col + 1
					elif col_diff < 0:
						new_col = col - 1

				if new_row >= 0 and new_row < size and new_col >= 0 and new_col < size \
						and bool(new_tiles[new_row * size + new_col]["isEmpty"]):
					new_tiles[row * size + col] = _create_empty_tile(row, col)
					new_tiles[new_row * size + new_col] = tile
					moved_tiles[new_row * size + new_col] = true
					moved = true

		# Mark moved tiles as magnetized (preserve "new"/"merged").
		for i in range(new_tiles.size()):
			var nt = new_tiles[i]
			if nt != null and not nt["isEmpty"] and moved_tiles.has(i):
				if str(nt.get("status", "")) != "new" and str(nt.get("status", "")) != "merged":
					var replacement := (nt as Dictionary).duplicate()  # {...newTiles[i]}
					replacement["status"] = "magnetized"
					var old_meta = nt.get("meta")
					replacement["meta"] = (old_meta as Dictionary).duplicate() if old_meta != null else {}
					new_tiles[i] = replacement

		# Update game state with magnetized board.
		game_state = game_state.duplicate()  # {...gameState}
		var new_board := (game_state["board"] as Dictionary).duplicate()  # {...gameState.board}
		new_board["tiles"] = new_tiles
		game_state["board"] = new_board

		if not totem.has("config") or totem["config"] == null:
			totem["config"] = {}
		var cfg: Dictionary = totem["config"]
		if cfg.has("movesRemaining") and cfg["movesRemaining"] != null:
			cfg["movesRemaining"] = max(0, int(cfg["movesRemaining"]) - 1)

	return game_state


static func _magnet_distance_to_center(row: int, col: int, centers: Array) -> int:
	var min_distance := 1 << 30
	for center in centers:
		var d: int = abs(row - int(center["row"])) + abs(col - int(center["col"]))
		min_distance = min(min_distance, d)
	return min_distance


static func _magnet_nearest_center(row: int, col: int, centers: Array) -> Dictionary:
	var nearest: Dictionary = centers[0]
	var min_distance := 1 << 30
	for center in centers:
		var d: int = abs(row - int(center["row"])) + abs(col - int(center["col"]))
		if d < min_distance:
			min_distance = d
			nearest = center
	return nearest


static func _stable_sort_by_distance_desc(arr: Array) -> void:
	# Stable insertion-ish sort: V8 Array.prototype.sort is stable. The TS
	# comparator is (a,b) => b.distance - a.distance. Equal-distance items keep
	# their original (board-scan) order.
	var n := arr.size()
	for i in range(1, n):
		var cur = arr[i]
		var j := i - 1
		# move cur left while predecessor has strictly smaller distance
		while j >= 0 and int(arr[j]["distance"]) < int(cur["distance"]):
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = cur


static func _process_void_gate(game_state: Dictionary, totem: Dictionary, game_event: Dictionary) -> Dictionary:
	if str(game_event.get("type", "")) == "POST_SWIPE":
		if not bool(game_event.get("mergeOccurred", false)):
			var tiles: Array = game_state["board"]["tiles"]
			var lowest_index := -1
			var lowest_value := 1 << 30
			var non_empty_count := 0

			for i in range(tiles.size()):
				var t = tiles[i]
				if t != null and not t["isEmpty"]:
					non_empty_count += 1
					if int(t["value"]) < lowest_value:
						lowest_value = int(t["value"])
						lowest_index = i

			if lowest_index != -1 and non_empty_count > 1:
				var row := int(floor(float(lowest_index) / 4.0))
				var col := lowest_index % 4
				var new_tiles: Array = tiles.duplicate()  # [...tiles]
				new_tiles[lowest_index] = _create_empty_tile(row, col)

				game_state = game_state.duplicate()
				var new_board := (game_state["board"] as Dictionary).duplicate()
				new_board["tiles"] = new_tiles
				game_state["board"] = new_board

		if not totem.has("config") or totem["config"] == null:
			totem["config"] = {}
		var cfg: Dictionary = totem["config"]
		if cfg.has("movesRemaining") and cfg["movesRemaining"] != null:
			cfg["movesRemaining"] = max(0, int(cfg["movesRemaining"]) - 1)

	return game_state


static func _process_ghost_merge(game_state: Dictionary, totem: Dictionary, game_event: Dictionary, rng) -> Dictionary:
	var cfg = totem.get("config")
	if str(game_event.get("type", "")) == "POST_SWIPE" \
			and bool(game_event.get("mergeOccurred", false)) \
			and cfg != null and cfg.has("mergesRemaining") and cfg["mergesRemaining"] != null \
			and int(cfg["mergesRemaining"]) > 0:

		var board_tiles: Array = game_state["board"]["tiles"]

		# Find merged tiles in board order.
		var merged_tiles: Array = []
		for index in range(board_tiles.size()):
			var tile = board_tiles[index]
			if tile != null and str(tile.get("status", "")) == "merged":
				merged_tiles.append({
					"index": index,
					"row": int(floor(float(index) / 4.0)),
					"col": index % 4,
					"value": int(tile["value"]),
				})

		if not merged_tiles.is_empty():
			var first_merge: Dictionary = merged_tiles[0]

			# Find empty cells in board order.
			var empty_cells: Array = []
			for index in range(board_tiles.size()):
				var tile = board_tiles[index]
				if tile != null and bool(tile.get("isEmpty", false)):
					empty_cells.append({
						"index": index,
						"row": int(floor(float(index) / 4.0)),
						"col": index % 4,
					})

			if not empty_cells.is_empty():
				var pick := int(floor(rng.get_random(C.NS_TOTEM_SPAWN) * empty_cells.size()))
				var random_cell: Dictionary = empty_cells[pick]

				var rc := _index_to_row_col(int(random_cell["index"]), int(game_state["board"]["size"]))
				var ghost_tile := {
					"isEmpty": false,
					"value": int(first_merge["value"]),
					"status": "spawned",
					"meta": {"isGhost": true},
					"row": rc["row"],
					"col": rc["col"],
					# effect: undefined in TS -> omitted (dropped by canonical hash).
				}
				# Mutates board.tiles in place (same array reference).
				game_state["board"]["tiles"][int(random_cell["index"])] = ghost_tile

			cfg["mergesRemaining"] = max(0, int(cfg["mergesRemaining"]) - 1)

	return game_state


static func _process_scavenger(game_state: Dictionary, totem: Dictionary, game_event: Dictionary) -> Dictionary:
	var cfg = totem.get("config")
	if str(game_event.get("type", "")) == "POST_SWIPE" \
			and game_event.get("mergedTilesCount") != null \
			and int(game_event["mergedTilesCount"]) > 0 \
			and cfg != null and cfg.has("mergesRemaining") and cfg["mergesRemaining"] != null \
			and int(cfg["mergesRemaining"]) > 0:

		game_event["shardsMultiplier"] = int(game_event.get("shardsMultiplier", 1)) * 2
		cfg["mergesRemaining"] = max(0, int(cfg["mergesRemaining"]) - 1)

	return game_state


static func _process_chrono_anchor(game_state: Dictionary) -> Dictionary:
	return game_state


# ----------------------------------------------------------------------------
# despawn
# ----------------------------------------------------------------------------

static func _check_totem_despawn_conditions(game_state: Dictionary, game_event: Dictionary) -> Dictionary:
	var event_type := str(game_event.get("type", ""))
	var active: Array = game_state["totems"]["active"]
	var kept: Array = []
	for totem in active:
		if _keep_totem(totem, event_type, game_event):
			kept.append(totem)

	if kept.size() != active.size():
		game_state["totems"]["active"] = kept

	return game_state


static func _keep_totem(totem: Dictionary, event_type: String, game_event: Dictionary) -> bool:
	var cfg = totem.get("config")

	# Move-based despawn (only on MOVE_COMPLETED).
	if event_type == "MOVE_COMPLETED" and cfg != null and cfg.has("movesRemaining") and cfg["movesRemaining"] != null:
		return int(cfg["movesRemaining"]) > 0

	# Merge-based despawn (Ghost Merge).
	if event_type == "POST_SWIPE" and bool(game_event.get("mergeOccurred", false)) \
			and cfg != null and cfg.has("mergesRemaining") and cfg["mergesRemaining"] != null:
		return int(cfg["mergesRemaining"]) > 0

	# Tally-based despawn.
	if cfg != null and cfg.has("maxTallyMarks") and cfg["maxTallyMarks"] != null:
		return int(cfg.get("tallyMarks", 0)) < int(cfg["maxTallyMarks"])

	return true


# ----------------------------------------------------------------------------
# initializeTotemConfig
# ----------------------------------------------------------------------------

static func initialize_totem_config(totem_type: String, custom_config: Dictionary = {}) -> Dictionary:
	var totem_def = _find_totem_def(totem_type)
	if totem_def == null:
		push_error("Unknown totem type: " + totem_type)
		return {}

	var config := custom_config.duplicate()  # {...customConfig}

	if totem_def.get("defaultMoves") != null:
		# config.movesRemaining || defaultMoves : JS '||' treats 0/undefined/null as falsy.
		var mr = config.get("movesRemaining")
		config["movesRemaining"] = mr if (mr != null and int(mr) != 0) else int(totem_def.get("defaultMoves"))

	if totem_def.get("defaultSwipes") != null:
		var sr = config.get("swipesRemaining")
		config["swipesRemaining"] = sr if (sr != null and int(sr) != 0) else int(totem_def.get("defaultSwipes"))

	if totem_def.get("defaultMerges") != null:
		var mg = config.get("mergesRemaining")
		config["mergesRemaining"] = mg if (mg != null and int(mg) != 0) else int(totem_def.get("defaultMerges"))

	if totem_def.get("maxTallyMarks") != null:
		var tm = config.get("tallyMarks")
		config["tallyMarks"] = tm if (tm != null and int(tm) != 0) else 0
		config["maxTallyMarks"] = int(totem_def.get("maxTallyMarks"))

	if totem_def.get("spawnValue") != null:
		config["spawnValue"] = int(totem_def.get("spawnValue"))

	return config
