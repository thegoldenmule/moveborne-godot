extends SceneTree

## Headless parity check for engine/scenarios.gd against tests/golden/scenarios_golden.json.
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##     --path <repo> --script res://tools/verify_scenarios.gd 2>&1 | grep -E 'VERIFY|FAIL'

const Scn := preload("res://logic/scenarios.gd")
const Hasher := preload("res://logic/hasher.gd")
const MbRandomS := preload("res://logic/random_generator.gd")


func _initialize() -> void:
	var path := "res://tests/golden/scenarios_golden.json"
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		print("FAIL: could not read %s" % path)
		quit(1)
		return
	var golden = JSON.parse_string(text)
	if golden == null:
		print("FAIL: could not parse golden JSON")
		quit(1)
		return

	var seeds: Dictionary = golden["seeds"]
	var total := 0
	var failed := false

	# --- buildInitialBoard for each scenario with an initialBoard ---
	for case in golden["boards"]:
		total += 1
		var sid := int(case["scenarioId"])
		var board_size := int(case["boardSize"])
		var sc = Scn.get_scenario(sid)
		if sc == null or not sc.has("initialBoard"):
			print("FAIL: scenario %d missing initialBoard in GDScript table" % sid)
			failed = true
			break
		var start_indices := _to_indices(case["startIndices"])
		var rng := MbRandomS.new(seeds, start_indices)
		var tiles := Scn.build_initial_board(sc["initialBoard"], board_size, rng)
		var board := {"tiles": tiles, "size": board_size}
		var got_hash := Hasher.hash_value({"board": board})
		if got_hash != str(case["hash"]):
			print("FAIL: scenario %d board hash mismatch got=%s want=%s" % [sid, got_hash, str(case["hash"])])
			failed = true
			break
		# verify RNG draw count/order matched (endIndices)
		var got_idx := rng.get_indices()
		if int(got_idx[Scn.C.NS_TILE_GEN]) != int(case["endIndices"]["tile-gen"]):
			print("FAIL: scenario %d tile-gen index got=%d want=%d" % [sid, int(got_idx[Scn.C.NS_TILE_GEN]), int(case["endIndices"]["tile-gen"])])
			failed = true
			break

	# --- empty-grid (config-less) boards ---
	if not failed:
		for case in golden["emptyGridCases"]:
			total += 1
			var board_size := int(case["boardSize"])
			var rng := MbRandomS.new(seeds, _fresh_indices())
			var tiles := Scn.build_initial_board({}, board_size, rng)
			var board := {"tiles": tiles, "size": board_size}
			var got_hash := Hasher.hash_value({"board": board})
			if got_hash != str(case["hash"]):
				print("FAIL: empty grid size %d hash mismatch got=%s want=%s" % [board_size, got_hash, str(case["hash"])])
				failed = true
				break

	# --- createTileEffect (defaults + overrides) ---
	if not failed:
		for case in golden["effectCases"]:
			total += 1
			var type := str(case["type"])
			var config = case["config"]  # null or Dictionary
			var eff := Scn.create_tile_effect(type, config)
			var got_hash := Hasher.hash_value(eff)
			if got_hash != str(case["hash"]):
				print("FAIL: createTileEffect type=%s config=%s hash mismatch got=%s want=%s" % [type, str(config), got_hash, str(case["hash"])])
				failed = true
				break

	# --- createEmptyTile ---
	if not failed:
		for case in golden["emptyTileCases"]:
			total += 1
			var t := Scn.create_empty_tile(int(case["row"]), int(case["col"]))
			var got_hash := Hasher.hash_value(t)
			if got_hash != str(case["hash"]):
				print("FAIL: createEmptyTile (%d,%d) hash mismatch got=%s want=%s" % [int(case["row"]), int(case["col"]), got_hash, str(case["hash"])])
				failed = true
				break

	# --- validateBoardSize ---
	if not failed:
		for case in golden["boardSizeCases"]:
			total += 1
			var got := Scn.validate_board_size(int(case["input"]))
			if got != int(case["output"]):
				print("FAIL: validateBoardSize(%d) got=%d want=%d" % [int(case["input"]), got, int(case["output"])])
				failed = true
				break

	if failed:
		print("VERIFY scenarios: FAIL")
		quit(1)
	else:
		print("VERIFY scenarios: PASS (%d cases)" % total)
		quit(0)


func _fresh_indices() -> Dictionary:
	return {"tile-gen": 0, "shuffle": 0, "effect-spawn": 0, "totem-spawn": 0, "card-draw": 0}


func _to_indices(d) -> Dictionary:
	var out := {}
	for k in (d as Dictionary).keys():
		out[k] = int(d[k])
	return out
