extends SceneTree

## Headless parity check for engine/powercards.gd against tests/golden/powercards_golden.json.
## Runs each golden case through the GDScript port and compares tiles (via state hash),
## success, and score. Prints "VERIFY powercards: PASS (N cases)" or a FAIL diff.

const PC := preload("res://logic/powercards.gd")
const Hasher := preload("res://logic/hasher.gd")
const MbRandomS := preload("res://logic/random_generator.gd")


func _initialize() -> void:
	var path := "res://tests/golden/powercards_golden.json"
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		print("FAIL powercards: could not read ", path)
		quit(1)
		return
	var golden = JSON.parse_string(txt)
	if golden == null:
		print("FAIL powercards: could not parse golden JSON")
		quit(1)
		return

	var size := int(golden["size"])
	var cases: Array = golden["cases"]
	var passed := 0

	for case in cases:
		var name := str(case["name"])
		var card := str(case["card"])
		var tiles := _to_tiles(case["tiles_before"])
		var res: Dictionary

		match card:
			"bomb":
				res = PC.perform_power_card_bomb(tiles, _target(case, "tiles_before"), size)
			"destroy":
				res = PC.perform_power_card_destroy(tiles, _target(case, "tiles_before"), size)
			"clear":
				res = PC.perform_power_card_clear(tiles, _col(name), size)
			"double":
				res = PC.perform_power_card_double(tiles, _target(case, "tiles_before"), size)
			"split":
				res = PC.perform_power_card_split(tiles, _pos_for(name), size)
			"multiply":
				res = PC.perform_power_card_multiply(tiles, _pos_for(name), size)
			"lightning":
				res = PC.perform_power_card_lightning(tiles, _col(name), size)
			"radiate":
				res = PC.perform_power_card_radiate(tiles, _pos_for(name), size)
			"clone":
				var sc := _clone_args(name)
				res = PC.perform_power_card_clone(tiles, sc[0], sc[1], size)
			"swap":
				var sw := _swap_args(name)
				res = PC.perform_power_card_swap(tiles, sw[0], sw[1], size)
			"vortex":
				res = PC.perform_power_card_vortex(tiles, _vortex_arg(name), size)
			"teleport":
				var tp := _teleport_args(name)
				res = PC.perform_power_card_teleport(tiles, tp[0], tp[1], size)
			"shuffle":
				var rng: Object = _rng_for(case)
				res = PC.perform_power_card_shuffle(tiles, rng, size)
				if not _check_indices(name, rng, case):
					quit(1)
					return
			"transform":
				var rng2: Object = _rng_for(case)
				res = PC.perform_power_card_transform(tiles, int(case["numEffects"]), rng2, size)
				if not _check_indices(name, rng2, case):
					quit(1)
					return
			_:
				print("FAIL powercards: unknown card type '", card, "' in case ", name)
				quit(1)
				return

		# Compare success and score.
		if bool(res["success"]) != bool(case["success"]):
			print("FAIL powercards [", name, "]: success ", res["success"], " != ", case["success"])
			quit(1)
			return
		if int(res["score"]) != int(case["score"]):
			print("FAIL powercards [", name, "]: score ", res["score"], " != ", case["score"])
			quit(1)
			return

		# Compare tiles via state hash.
		var got_hash := Hasher.hash_value({"tiles": res["tiles"]})
		var want_hash := str(case["hashAfter"])
		if got_hash != want_hash:
			print("FAIL powercards [", name, "]: hash mismatch")
			print("  got  ", got_hash)
			print("  want ", want_hash)
			_print_first_tile_diff(res["tiles"], case["tiles_after"])
			quit(1)
			return

		passed += 1

	print("VERIFY powercards: PASS (", passed, " cases)")
	quit(0)


# Convert golden tile array (parsed JSON) to GDScript tile dicts with int values.
func _to_tiles(arr: Array) -> Array:
	var out: Array = []
	for t in arr:
		out.append(_to_tile(t))
	return out


func _to_tile(t: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for k in t.keys():
		var v = t[k]
		if k == "value" or k == "row" or k == "col":
			d[k] = int(v)
		elif k == "effect":
			d[k] = _normalize(v)
		elif k == "meta":
			d[k] = _normalize(v)
		else:
			d[k] = v
	return d


# Recursively normalize parsed JSON: floats that are integral become ints
# (so hashing matches; JSON.parse_string yields floats for all numbers).
func _normalize(v):
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v.keys():
			d[k] = _normalize(v[k])
		return d
	elif v is Array:
		var a: Array = []
		for item in v:
			a.append(_normalize(item))
		return a
	elif v is float:
		if v == floor(v) and abs(v) < 1e15:
			return int(v)
		return v
	else:
		return v


# Build an MbRandom from the case's recorded seeds + startIndices.
func _rng_for(case: Dictionary) -> Object:
	var rng_info: Dictionary = case["rng"]
	var seeds: Dictionary = {}
	for k in rng_info["seeds"].keys():
		seeds[k] = int(rng_info["seeds"][k])
	var indices: Dictionary = {}
	for k in rng_info["startIndices"].keys():
		indices[k] = int(rng_info["startIndices"][k])
	return MbRandomS.new(seeds, indices)


func _check_indices(name: String, rng: Object, case: Dictionary) -> bool:
	var got: Dictionary = rng.get_indices()
	var want: Dictionary = case["rng"]["endIndices"]
	for k in want.keys():
		if int(got.get(k, 0)) != int(want[k]):
			print("FAIL powercards [", name, "]: rng index '", k, "' ", got.get(k, 0), " != ", want[k])
			return false
	return true


# Position param helpers (mirror the params used in gen_powercards.mjs).
func _target(case: Dictionary, _key: String):
	# Bomb/Destroy/Double pass { row, col } of the intended target.
	return _pos_for(str(case["name"]))


func _pos_for(name: String):
	match name:
		"bomb_value_noeffect": return {"row": 1, "col": 1}
		"bomb_value_witheffect": return {"row": 1, "col": 1}
		"bomb_empty_tile": return {"row": 0, "col": 0}
		"bomb_no_target": return null
		"destroy_value_noeffect": return {"row": 2, "col": 2}
		"destroy_value_witheffect": return {"row": 2, "col": 2}
		"destroy_empty": return {"row": 2, "col": 2}
		"double_value_noeffect": return {"row": 0, "col": 3}
		"double_value_witheffect": return {"row": 0, "col": 3}
		"split_value_gt2": return {"row": 1, "col": 2}
		"split_value_2": return {"row": 1, "col": 2}
		"split_empty": return {"row": 1, "col": 2}
		"multiply_value": return {"row": 1, "col": 3}
		"multiply_empty": return {"row": 1, "col": 3}
		"radiate_center": return {"row": 1, "col": 1}
		"radiate_corner_no_adjacent": return {"row": 0, "col": 0}
		"radiate_empty_center": return {"row": 0, "col": 0}
		_:
			print("FAIL powercards: no pos mapping for ", name)
			return null


func _col(name: String):
	match name:
		"clear_column_mixed": return 1
		"clear_column_alleffects": return 1
		"clear_column_empty": return 2
		"clear_invalid_col": return 9
		"lightning_column": return 2
		"lightning_empty_col": return 0
		"lightning_invalid": return -1
		_:
			print("FAIL powercards: no col mapping for ", name)
			return null


func _clone_args(name: String) -> Array:
	match name:
		"clone_adjacent_empty": return [{"row": 1, "col": 1}, {"row": 1, "col": 2}]
		"clone_target_occupied": return [{"row": 1, "col": 1}, {"row": 1, "col": 2}]
		"clone_not_adjacent": return [{"row": 1, "col": 1}, {"row": 3, "col": 3}]
		"clone_source_empty": return [{"row": 1, "col": 1}, {"row": 1, "col": 2}]
		_:
			print("FAIL powercards: no clone mapping for ", name)
			return [null, null]


func _swap_args(name: String) -> Array:
	match name:
		"swap_two_tiles": return [{"row": 0, "col": 0}, {"row": 3, "col": 3}]
		"swap_one_empty": return [{"row": 0, "col": 0}, {"row": 3, "col": 3}]
		"swap_same_pos": return [{"row": 0, "col": 0}, {"row": 0, "col": 0}]
		_:
			print("FAIL powercards: no swap mapping for ", name)
			return [null, null]


func _vortex_arg(name: String):
	match name:
		"vortex_quadrant": return {"row": 0, "col": 0}
		"vortex_partial_empty": return {"row": 1, "col": 1}
		"vortex_out_of_bounds": return {"row": 3, "col": 3}
		"vortex_no_row": return {}
		_:
			print("FAIL powercards: no vortex mapping for ", name)
			return null


func _teleport_args(name: String) -> Array:
	match name:
		"teleport_to_empty": return [{"row": 0, "col": 0}, {"row": 3, "col": 3}]
		"teleport_target_occupied": return [{"row": 0, "col": 0}, {"row": 3, "col": 3}]
		"teleport_same_pos": return [{"row": 0, "col": 0}, {"row": 0, "col": 0}]
		"teleport_source_empty": return [{"row": 0, "col": 0}, {"row": 1, "col": 1}]
		_:
			print("FAIL powercards: no teleport mapping for ", name)
			return [null, null]


func _print_first_tile_diff(got_tiles: Array, want_tiles: Array) -> void:
	for i in range(max(got_tiles.size(), want_tiles.size())):
		var g = got_tiles[i] if i < got_tiles.size() else null
		var w = want_tiles[i] if i < want_tiles.size() else null
		var gh := Hasher.hash_value(g) if g != null else "<none>"
		var wh := Hasher.hash_value(_normalize(w)) if w != null else "<none>"
		if gh != wh:
			print("  first tile diff at index ", i)
			print("    got  ", JSON.stringify(g))
			print("    want ", JSON.stringify(w))
			return
