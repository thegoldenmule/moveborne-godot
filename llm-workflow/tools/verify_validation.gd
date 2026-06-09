extends SceneTree

## Headless parity harness for the validation predicates port.
##   godot --headless --path . --script res://tools/verify_validation.gd

const V := preload("res://logic/validation.gd")

func _dispatch(predicate: String, tiles: Array, c: Dictionary) -> bool:
	var args: Array = c.get("args", [])
	match predicate:
		# has* (whole-board)
		"hasValidSplitTiles": return V.has_valid_split_tiles(tiles)
		"hasValidMultiplyTiles": return V.has_valid_multiply_tiles(tiles)
		"hasValidShuffleTiles": return V.has_valid_shuffle_tiles(tiles)
		"hasValidLightningTiles": return V.has_valid_lightning_tiles(tiles)
		"hasValidRadiateTiles": return V.has_valid_radiate_tiles(tiles)
		"hasValidCloneTiles": return V.has_valid_clone_tiles(tiles)
		"hasValidSwapTiles": return V.has_valid_swap_tiles(tiles)
		"hasValidVortexTiles": return V.has_valid_vortex_tiles(tiles)
		"hasValidTeleportTiles": return V.has_valid_teleport_tiles(tiles)
		"hasValidBombTiles": return V.has_valid_bomb_tiles(tiles)
		"hasValidDestroyTiles": return V.has_valid_destroy_tiles(tiles)
		"hasValidClearColumns": return V.has_valid_clear_columns(tiles)
		"hasValidDoubleTiles": return V.has_valid_double_tiles(tiles)
		"hasValidTransformTiles": return V.has_valid_transform_tiles(tiles)
		# isValid* position/column (args = [row,col] or [col] or with sourcePos)
		"isValidSwapPosition": return V.is_valid_swap_position(tiles, int(args[0]), int(args[1]))
		"isValidVortexPosition": return V.is_valid_vortex_position(tiles, int(args[0]), int(args[1]))
		"isValidSplitPosition": return V.is_valid_split_position(tiles, int(args[0]), int(args[1]))
		"isValidMultiplyPosition": return V.is_valid_multiply_position(tiles, int(args[0]), int(args[1]))
		"isValidRadiatePosition": return V.is_valid_radiate_position(tiles, int(args[0]), int(args[1]))
		"isValidCloneSourcePosition": return V.is_valid_clone_source_position(tiles, int(args[0]), int(args[1]))
		"isValidCloneTargetPosition":
			var sp = c.get("sourcePos", null)
			return V.is_valid_clone_target_position(tiles, int(args[0]), int(args[1]), sp)
		"isValidLightningColumn": return V.is_valid_lightning_column(tiles, int(args[0]), int(args[1]))
		"isValidTeleportSourcePosition": return V.is_valid_teleport_source_position(tiles, int(args[0]), int(args[1]))
		"isValidTeleportTargetPosition": return V.is_valid_teleport_target_position(tiles, int(args[0]), int(args[1]))
		"isValidBombPosition": return V.is_valid_bomb_position(tiles, int(args[0]), int(args[1]))
		"isValidDestroyPosition": return V.is_valid_destroy_position(tiles, int(args[0]), int(args[1]))
		"isValidClearColumn": return V.is_valid_clear_column(tiles, int(args[0]))
		"isValidDoublePosition": return V.is_valid_double_position(tiles, int(args[0]), int(args[1]))
		_:
			push_error("Unknown predicate: %s" % predicate)
			return false


func _initialize() -> void:
	var txt := FileAccess.get_file_as_string("res://tests/golden/validation_golden.json")
	var g: Dictionary = JSON.parse_string(txt)
	var boards: Dictionary = g["boards"]
	var cases: Array = g["cases"]
	var ok := true
	var n := 0
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var tiles: Array = boards[c["board"]]
		var got := _dispatch(c["predicate"], tiles, c)
		var want := bool(c["result"])
		if got != want:
			print("FAIL case %d board=%s predicate=%s args=%s sourcePos=%s got=%s want=%s" % [
				i, c["board"], c["predicate"], str(c.get("args", [])), str(c.get("sourcePos", null)), str(got), str(want)])
			ok = false
			break
		n += 1
	print("VERIFY validation: %s (%d cases)" % ["PASS" if ok else "FAIL", n])
	quit(0 if ok else 1)
