extends SceneTree

## Headless parity harness for engine/tile_effects.gd (MbTileEffects) against
## tests/golden/tile_effects_golden.json (generated from the real TS bundle).
##   godot --headless --path . --script res://tools/verify_tile_effects.gd

const TE := preload("res://logic/tile_effects.gd")
const Hasher := preload("res://logic/hasher.gd")
const MbRandomS := preload("res://logic/random_generator.gd")

var _fail_msg := ""


func _initialize() -> void:
	var txt := FileAccess.get_file_as_string("res://tests/golden/tile_effects_golden.json")
	var g: Dictionary = JSON.parse_string(txt)
	var cases: Array = g["cases"]
	var by_name := {}
	for c in cases:
		by_name[(c as Dictionary)["name"]] = c

	var total := 0
	var ok := true

	# Helper closures are not allowed for statics; dispatch by name.
	for name in ["createTileEffect", "canValueMove", "canValueMerge", "canTilesMergeTogether",
			"isBlackHoleTile", "findBlackHoleInPath", "processBlackHoleDestruction",
			"processLockTriggerOnMerge", "processTileEffectsOnMerge", "getEffectToPreserveAtSource",
			"processFreezeRemovalFromAdjacentMerge", "attemptSpawnEffectOnTile"]:
		var n := _run_case(name, by_name[name])
		if n < 0:
			ok = false
			break
		total += n

	if ok:
		print("VERIFY tile_effects: PASS (%d cases)" % total)
		quit(0)
	else:
		print("VERIFY tile_effects: FAIL %s" % _fail_msg)
		quit(1)


# Builders mirroring the JS gen helpers.
func _empty_tile(r: int, c: int) -> Dictionary:
	return {"isEmpty": true, "value": 0, "row": r, "col": c, "status": "normal"}


func _val_tile(r: int, c: int, v: int, status := "normal") -> Dictionary:
	return {"isEmpty": false, "value": v, "row": r, "col": c, "status": status, "meta": {}}


func _with_effect(tile: Dictionary, type: String, cfg = null) -> Dictionary:
	var t := tile.duplicate(true)
	t["effect"] = TE.create_tile_effect(type, cfg)
	return t


func _cmp(got, want, label: String) -> bool:
	var hg := Hasher.hash_value(got)
	var hw := Hasher.hash_value(want)
	if hg != hw:
		_fail_msg = "%s: got %s want %s\n  GOT=%s\n  WANT=%s" % [label, hg, hw, JSON.stringify(got), JSON.stringify(want)]
		return false
	return true


func _run_case(name: String, case: Dictionary) -> int:
	match name:
		"createTileEffect":
			return _verify_factory(case)
		"canValueMove":
			return _verify_can_value_move(case)
		"canValueMerge":
			return _verify_can_value_merge(case)
		"canTilesMergeTogether":
			return _verify_can_tiles_merge(case)
		"isBlackHoleTile":
			return _verify_is_black_hole(case)
		"findBlackHoleInPath":
			return _verify_find_bh(case)
		"processBlackHoleDestruction":
			return _verify_bh_destruction(case)
		"processLockTriggerOnMerge":
			return _verify_lock(case)
		"processTileEffectsOnMerge":
			return _verify_effects_on_merge(case)
		"getEffectToPreserveAtSource":
			return _verify_preserve(case)
		"processFreezeRemovalFromAdjacentMerge":
			return _verify_freeze_removal(case)
		"attemptSpawnEffectOnTile":
			return _verify_spawn(case)
	_fail_msg = "unknown case " + name
	return -1


func _verify_factory(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var n := 0
	for type in ["freeze", "black_hole", "amplify", "amplify_static", "lock", "decay", "stone", "none"]:
		var got := TE.create_tile_effect(type)
		if not _cmp(got, want[type], "createTileEffect %s" % type):
			return -1
		n += 1
	# overrides
	if not _cmp(TE.create_tile_effect("black_hole", {"removalCost": 3, "customKey": 42}), want["black_hole_override"], "createTileEffect black_hole_override"):
		return -1
	n += 1
	if not _cmp(TE.create_tile_effect("lock", {"remainingTriggers": 5}), want["lock_override"], "createTileEffect lock_override"):
		return -1
	n += 1
	return n


func _verify_can_value_move(case: Dictionary) -> int:
	var inputs: Dictionary = case["inputs"]
	var want: Dictionary = case["result"]
	var n := 0
	for k in inputs.keys():
		var got := TE.can_value_move(inputs[k])
		if got != bool(want[k]):
			_fail_msg = "canValueMove[%s] got %s want %s" % [k, got, want[k]]
			return -1
		n += 1
	return n


func _verify_can_value_merge(case: Dictionary) -> int:
	var inputs: Dictionary = case["inputs"]
	var want: Dictionary = case["result"]
	var n := 0
	for k in inputs.keys():
		var got := TE.can_value_merge(inputs[k])
		if got != bool(want[k]):
			_fail_msg = "canValueMerge[%s] got %s want %s" % [k, got, want[k]]
			return -1
		n += 1
	return n


func _verify_can_tiles_merge(case: Dictionary) -> int:
	var inputs: Dictionary = case["inputs"]
	var want: Dictionary = case["result"]
	var n := 0
	for k in inputs.keys():
		var pair: Array = inputs[k]
		var got := TE.can_tiles_merge_together(pair[0], pair[1])
		if got != bool(want[k]):
			_fail_msg = "canTilesMergeTogether[%s] got %s want %s" % [k, got, want[k]]
			return -1
		n += 1
	return n


func _verify_is_black_hole(case: Dictionary) -> int:
	var inputs: Dictionary = case["inputs"]
	var want: Dictionary = case["result"]
	var n := 0
	for k in inputs.keys():
		var got := TE.is_black_hole_tile(inputs[k])
		if got != bool(want[k]):
			_fail_msg = "isBlackHoleTile[%s] got %s want %s" % [k, got, want[k]]
			return -1
		n += 1
	return n


func _verify_find_bh(case: Dictionary) -> int:
	var inputs: Dictionary = case["inputs"]
	var want: Dictionary = case["result"]
	var n := 0
	for k in inputs.keys():
		var inp: Dictionary = inputs[k]
		var got = TE.find_black_hole_in_path(inp["tiles"], 4, inp["from"], inp["to"])
		var wanted = want[k]  # null or {row,col}
		if not _cmp(got, wanted, "findBlackHoleInPath[%s]" % k):
			return -1
		n += 1
	return n


func _verify_bh_destruction(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var n := 0
	# normal
	if true:
		var consumed := _with_effect(_val_tile(1, 1, 16), "amplify")
		var bh := _with_effect(_val_tile(0, 0, 2), "black_hole")
		var ret := TE.process_black_hole_destruction(consumed, bh)
		var w: Dictionary = want["normal"]
		if not _cmp(consumed, w["consumedAfter"], "bhDestruction.normal.consumed"): return -1
		if not _cmp(bh, w["blackHoleAfter"], "bhDestruction.normal.bh"): return -1
		if not _cmp(ret, w["ret"], "bhDestruction.normal.ret"): return -1
		n += 1
	# implosion
	if true:
		var consumed := _val_tile(2, 2, 8)
		var bh := _with_effect(_val_tile(0, 0, 2), "black_hole", {"tilesConsumed": 6, "maxTilesToImplosion": 7})
		var ret := TE.process_black_hole_destruction(consumed, bh)
		var w: Dictionary = want["implosion"]
		if not _cmp(consumed, w["consumedAfter"], "bhDestruction.implosion.consumed"): return -1
		if not _cmp(bh, w["blackHoleAfter"], "bhDestruction.implosion.bh"): return -1
		if not _cmp(ret, w["ret"], "bhDestruction.implosion.ret"): return -1
		n += 1
	# noConfig
	if true:
		var consumed := _val_tile(2, 2, 32)
		var bh := _val_tile(0, 0, 2)
		var ret := TE.process_black_hole_destruction(consumed, bh)
		var w: Dictionary = want["noConfig"]
		if not _cmp(consumed, w["consumedAfter"], "bhDestruction.noConfig.consumed"): return -1
		if not _cmp(bh, w["blackHoleAfter"], "bhDestruction.noConfig.bh"): return -1
		if not _cmp(ret, w["ret"], "bhDestruction.noConfig.ret"): return -1
		n += 1
	return n


func _verify_lock(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var n := 0
	if true:
		var t := _with_effect(_val_tile(0, 0, 2), "lock", {"remainingTriggers": 3})
		var ret = TE.process_lock_trigger_on_merge(t)
		var w: Dictionary = want["decrement"]
		if not _cmp(t, w["after"], "lock.decrement.after"): return -1
		if not _cmp(ret, w["ret"], "lock.decrement.ret"): return -1
		n += 1
	if true:
		var t := _with_effect(_val_tile(1, 1, 2), "lock", {"remainingTriggers": 1})
		var ret = TE.process_lock_trigger_on_merge(t)
		var w: Dictionary = want["removeAtOne"]
		if not _cmp(t, w["after"], "lock.removeAtOne.after"): return -1
		if not _cmp(ret, w["ret"], "lock.removeAtOne.ret"): return -1
		n += 1
	if true:
		var t := _val_tile(2, 2, 2)
		var ret = TE.process_lock_trigger_on_merge(t)
		var w: Dictionary = want["noLock"]
		if not _cmp(t, w["after"], "lock.noLock.after"): return -1
		if not _cmp(ret, w["ret"], "lock.noLock.ret"): return -1
		n += 1
	return n


func _verify_effects_on_merge(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var n := 0
	var specs := [
		["amplify", "amplify", 8, 8],
		["amplifyStatic", "amplify_static", 8, 8],
		["blackHole", "black_hole", 8, 8],
		["noEffect", "", 8, 16],
		["inactiveAmplify", "amplify_inactive", 8, 8],
	]
	for spec in specs:
		var key: String = spec[0]
		var kind: String = spec[1]
		var base: int = spec[3]
		var t: Dictionary
		if kind == "":
			t = _val_tile(0, 0, spec[2])
		elif kind == "amplify_inactive":
			t = _with_effect(_val_tile(0, 0, spec[2]), "amplify")
			(t["effect"] as Dictionary)["active"] = false
		else:
			t = _with_effect(_val_tile(0, 0, spec[2]), kind)
		var ret := TE.process_tile_effects_on_merge(t, base)
		var w: Dictionary = want[key]
		if not _cmp(t, w["after"], "effectsOnMerge.%s.after" % key): return -1
		if not _cmp(ret, w["ret"], "effectsOnMerge.%s.ret" % key): return -1
		n += 1
	return n


func _verify_preserve(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var n := 0
	var specs := {
		"amplifyStays": "amplify",
		"freezeNoStay": "freeze",
		"blackHoleStays": "black_hole",
		"noEffect": "",
		"decayNoStay": "decay",
	}
	for key in specs.keys():
		var kind: String = specs[key]
		var t: Dictionary
		if kind == "":
			t = _val_tile(0, 0, 2)
		else:
			t = _with_effect(_val_tile(0, 0, 2), kind)
		var got = TE.get_effect_to_preserve_at_source(t)
		if not _cmp(got, want[key], "preserve.%s" % key): return -1
		n += 1
	return n


func _verify_freeze_removal(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var size := 4
	var tiles := []
	for r in range(size):
		for c in range(size):
			tiles.append(_val_tile(r, c, 2))
	var effect_map := {1: "freeze", 4: "stone", 6: "amplify", 9: "black_hole"}
	for idx in effect_map.keys():
		var i: int = idx
		tiles[i] = _with_effect(_val_tile(int(i / size), i % size, 2), effect_map[idx])
	var gs := {"board": {"tiles": tiles, "size": size}}
	var removed := TE.process_freeze_removal_from_adjacent_merge(gs, {"row": 1, "col": 1})
	if not _cmp(removed, want["removed"], "freezeRemoval.removed"): return -1
	if not _cmp(gs["board"]["tiles"], want["boardAfter"], "freezeRemoval.boardAfter"): return -1
	return 1


func _verify_spawn(case: Dictionary) -> int:
	var want: Dictionary = case["result"]
	var n := 0
	var size := 4

	# Each scenario rebuilds the exact gameState the JS gen used.
	var keys := ["guaranteedFreeze", "zeroChance", "maxActiveZero", "noScenario",
		"orderingFreezeThenBH", "linearOverride", "tileHasEffect", "emptySteppedDecay"]
	for key in keys:
		var gs := _spawn_state(key, size)
		var seeds: Dictionary = gs["randomSeeds"]
		var indices: Dictionary = gs["rngIndices"]
		var rng := MbRandomS.new(seeds, indices)
		var before := int(rng.get_indices()["effect-spawn"])
		var res := TE.attempt_spawn_effect_on_tile(gs, 5, rng)
		var after := int(rng.get_indices()["effect-spawn"])
		var delta := after - before
		var w: Dictionary = want[key]
		if res["success"] != bool(w["success"]):
			_fail_msg = "spawn.%s.success got %s want %s" % [key, res["success"], w["success"]]
			return -1
		if delta != int(w["rngDelta"]):
			_fail_msg = "spawn.%s.rngDelta got %d want %d" % [key, delta, int(w["rngDelta"])]
			return -1
		var got_state_hash := Hasher.hash_value(res["gameState"])
		if got_state_hash != str(w["gameStateHash"]):
			_fail_msg = "spawn.%s.gameStateHash got %s want %s\n  STATE=%s" % [key, got_state_hash, w["gameStateHash"], JSON.stringify(res["gameState"])]
			return -1
		var got_tiles_hash := Hasher.hash_value(res["gameState"]["board"]["tiles"])
		if got_tiles_hash != str(w["tilesHash"]):
			_fail_msg = "spawn.%s.tilesHash got %s want %s" % [key, got_tiles_hash, w["tilesHash"]]
			return -1
		var got_eff = res.get("effectSpawned", null)
		if not _cmp(got_eff, w["effectSpawned"], "spawn.%s.effectSpawned" % key):
			return -1
		n += 1
	return n


func _spawn_state(key: String, size: int) -> Dictionary:
	var tiles := []
	for r in range(size):
		for c in range(size):
			tiles.append(_val_tile(r, c, 2))
	var scenario = null
	var move_index := 0

	match key:
		"guaranteedFreeze":
			scenario = {"spawnConfigs": {"freeze": {"spawnCurve": {"type": "constant", "baseChance": 1}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5}}}
		"zeroChance":
			scenario = {"spawnConfigs": {"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5}}}
		"maxActiveZero":
			scenario = {"spawnConfigs": {"freeze": {"spawnCurve": {"type": "constant", "baseChance": 1}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 0}}}
		"noScenario":
			scenario = null
		"orderingFreezeThenBH":
			scenario = {"spawnConfigs": {
				"freeze": {"spawnCurve": {"type": "constant", "baseChance": 0}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
				"black_hole": {"spawnCurve": {"type": "constant", "baseChance": 1}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5},
			}}
		"linearOverride":
			scenario = {
				"spawnConfigs": {"lock": {"spawnCurve": {"type": "linear", "baseChance": 0.0, "params": {"linearRate": 0.5}, "maxChance": 1}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 0}},
				"maxActiveOverrides": {"lock": 3},
			}
			move_index = 4
		"tileHasEffect":
			scenario = {"spawnConfigs": {"freeze": {"spawnCurve": {"type": "constant", "baseChance": 1}, "canSpawnOn": ["normal"], "canSpawnOnEmpty": false, "maxActiveOnBoard": 5}}}
			tiles[5] = _with_effect(_val_tile(1, 1, 2), "amplify")
		"emptySteppedDecay":
			scenario = {"spawnConfigs": {"decay": {"spawnCurve": {"type": "stepped", "baseChance": 0, "params": {"steps": [{"moveIndex": 2, "chance": 0.0}, {"moveIndex": 5, "chance": 1.0}]}}, "canSpawnOn": [], "canSpawnOnEmpty": true, "maxActiveOnBoard": 5}}}
			tiles[5] = _empty_tile(1, 1)
			move_index = 6

	var gs := {
		"board": {"tiles": tiles, "size": size},
		"hand": {"cards": []}, "deck": {"remainingCards": 12, "nextCardIndex": 0},
		"score": 0, "shards": 0, "combo": 0, "comboMultiplier": 1, "totems": {"active": []}, "moveIndex": move_index,
		"randomSeeds": {"tile-gen": 1, "shuffle": 2, "effect-spawn": 777, "totem-spawn": 4, "card-draw": 5},
		"rngIndices": {"tile-gen": 0, "shuffle": 0, "effect-spawn": 0, "totem-spawn": 0, "card-draw": 0},
	}
	if scenario != null:
		gs["scenarioConfig"] = scenario
	return gs
