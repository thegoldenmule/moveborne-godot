extends SceneTree

const MbTotemsS := preload("res://engine/totems.gd")
const Hasher := preload("res://engine/hasher.gd")
const MbRandomS := preload("res://engine/random_generator.gd")

const GOLDEN_PATH := "res://tests/golden/totems_golden.json"

const SEEDS := {"tile-gen": 12345, "shuffle": 12346, "effect-spawn": 12347, "totem-spawn": 12348, "card-draw": 12349}


func _fail(msg: String) -> void:
	print("FAIL totems: ", msg)
	quit(1)


func _initialize() -> void:
	var txt := FileAccess.get_file_as_string(GOLDEN_PATH)
	if txt == "":
		_fail("could not read golden at " + GOLDEN_PATH)
		return
	var golden = JSON.parse_string(txt)
	if golden == null:
		_fail("could not parse golden JSON")
		return

	var cases: Array = golden["cases"]
	var passed := 0

	for case in cases:
		var name := str(case["name"])
		var state_before: Dictionary = case["stateBefore"]
		var event_before: Dictionary = case["eventBefore"]
		var rng_indices: Dictionary = case["rngIndicesBefore"]

		# Build fresh inputs (JSON.parse gives fresh dicts already, but duplicate deep to be safe).
		var state: Dictionary = state_before.duplicate(true)
		var event: Dictionary = event_before.duplicate(true)

		# Normalize JSON numeric types: JSON.parse_string returns floats for all
		# numbers. The TS golden uses ints for integral fields. We normalize the
		# whole structure to keep ints where values are integral so the hasher
		# (which prints ints without decimals) matches.
		state = _intify(state)
		event = _intify(event)

		var rng := MbRandomS.new(SEEDS, _intify_indices(rng_indices))

		var result: Dictionary = MbTotemsS.process_totem_effects(state, event, rng)

		# Compare state hash.
		var want_hash := str(case["hashAfter"])
		var got_hash := Hasher.hash_value(result)
		if got_hash != want_hash:
			print("  state diff for ", name)
			print("    want canonical: ", Hasher.canonical_stringify(_intify(case["stateAfter"])))
			print("    got  canonical: ", Hasher.canonical_stringify(result))
			_fail("state hash mismatch in case '" + name + "' want=" + want_hash + " got=" + got_hash)
			return

		# Compare mutated event hash.
		var want_event = _intify(case["eventAfter"])
		if Hasher.hash_value(event) != Hasher.hash_value(want_event):
			print("    want event: ", Hasher.canonical_stringify(want_event))
			print("    got  event: ", Hasher.canonical_stringify(event))
			_fail("event mismatch in case '" + name + "'")
			return

		# Compare rng deltas.
		var want_deltas: Dictionary = case["rngIndexDeltas"]
		var got_indices := rng.get_indices()
		var before_indices := _intify_indices(rng_indices)
		for ns in want_deltas.keys():
			var want_d := int(want_deltas[ns])
			var got_d := int(got_indices.get(ns, 0)) - int(before_indices.get(ns, 0))
			if want_d != got_d:
				_fail("rng delta mismatch in case '" + name + "' ns=" + str(ns) + " want=" + str(want_d) + " got=" + str(got_d))
				return

		passed += 1

	# Verify initializeTotemConfig outputs.
	var init_configs: Dictionary = golden["initConfigs"]
	for totem_type in init_configs.keys():
		var want = _intify(init_configs[totem_type])
		var got := MbTotemsS.initialize_totem_config(str(totem_type))
		if Hasher.hash_value(got) != Hasher.hash_value(want):
			print("    want initConfig: ", Hasher.canonical_stringify(want))
			print("    got  initConfig: ", Hasher.canonical_stringify(got))
			_fail("initializeTotemConfig mismatch for '" + str(totem_type) + "'")
			return
		passed += 1

	# Verify custom-config variants.
	var custom: Dictionary = golden["initCustom"]
	var custom_specs := {
		"spawn_booster_2x_custom": ["spawn_booster_2x", {"movesRemaining": 3}],
		"combo_saver_custom": ["combo_saver", {"tallyMarks": 1}],
		"ghost_merge_custom": ["ghost_merge", {"mergesRemaining": 2}],
		"momentum_idol_custom_extra": ["momentum_idol", {"movesRemaining": 0}],
	}
	for key in custom.keys():
		var spec: Array = custom_specs[key]
		var want = _intify(custom[key])
		var got := MbTotemsS.initialize_totem_config(str(spec[0]), spec[1])
		if Hasher.hash_value(got) != Hasher.hash_value(want):
			print("    want customConfig: ", Hasher.canonical_stringify(want))
			print("    got  customConfig: ", Hasher.canonical_stringify(got))
			_fail("initializeTotemConfig (custom) mismatch for '" + key + "'")
			return
		passed += 1

	print("VERIFY totems: PASS (", passed, " cases)")
	quit(0)


# Recursively convert integral floats to ints (JSON.parse_string yields floats).
func _intify(node):
	if node is Dictionary:
		var out := {}
		for k in node.keys():
			out[k] = _intify(node[k])
		return out
	elif node is Array:
		var out := []
		for v in node:
			out.append(_intify(v))
		return out
	elif node is float:
		if node == floor(node) and abs(node) < 1e15:
			return int(node)
		return node
	else:
		return node


func _intify_indices(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[k] = int(d[k])
	return out
