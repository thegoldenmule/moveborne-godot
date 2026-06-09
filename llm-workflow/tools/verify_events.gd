extends SceneTree

const MbEventsS := preload("res://logic/events.gd")
const Hasher := preload("res://logic/hasher.gd")
const MbRandomS := preload("res://logic/random_generator.gd")

const GOLDEN := "res://tests/golden/events_golden.json"


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string(GOLDEN)
	if raw == "":
		print("VERIFY events: FAIL (could not read golden %s)" % GOLDEN)
		quit(1)
		return
	var data = JSON.parse_string(raw)
	if data == null or not (data is Dictionary) or not data.has("cases"):
		print("VERIFY events: FAIL (golden parse error)")
		quit(1)
		return

	var cases: Array = data["cases"]
	var passed := 0
	for case in cases:
		var fn := str(case["fn"])
		var name := str(case["name"])
		var input: Dictionary = case["input"]
		var expected_hash := str(case["outputHash"])

		var result: Dictionary
		match fn:
			"updateTriggerStates":
				result = MbEventsS.update_trigger_states(input)
			"resetTriggeredStates":
				result = MbEventsS.reset_triggered_states(input)
			"processEventSpawnRules":
				var event: Dictionary = case["event"]
				var rules: Array = case["rules"]
				var rng := MbRandomS.new(input["randomSeeds"], input["rngIndices"])
				var excluded = case.get("excludedPositions", null)
				if excluded == null:
					result = MbEventsS.process_event_spawn_rules(input, event, rules, rng)
				else:
					result = MbEventsS.process_event_spawn_rules(input, event, rules, rng, excluded)
				# Verify RNG delta matches the golden.
				var expected_idx = case["rngIndicesAfter"]
				var got_idx := rng.get_indices()
				for ns in (expected_idx as Dictionary).keys():
					if int(expected_idx[ns]) != int(got_idx.get(ns, 0)):
						print("VERIFY events: FAIL at case '%s' (%s): rng[%s] expected %d got %d" % [name, fn, ns, int(expected_idx[ns]), int(got_idx.get(ns, 0))])
						quit(1)
						return
			_:
				print("VERIFY events: FAIL (unknown fn %s in case %s)" % [fn, name])
				quit(1)
				return

		# Global-effect cases carry a non-integer float `seed`. The double we
		# compute is bit-identical to the oracle (asserted below), but the proven
		# MbHasher's _num_float uses str(float), which truncates non-integer
		# floats (a documented Phase-1 hardening item we must NOT patch here).
		# So for those cases we (a) assert each seed is bit-equal to the golden,
		# then (b) hash-compare with seeds normalized to a stable token on BOTH
		# sides so the hasher's float-format limitation cancels out exactly.
		var expected_out = case["output"]
		var has_global := result.has("globalEffects") and result["globalEffects"] != null and (result["globalEffects"] as Array).size() > 0
		if has_global:
			if not _verify_seeds_bit_equal(name, result, expected_out):
				quit(1)
				return
			var got_hash_n := Hasher.hash_value(_normalize_seeds(result))
			var exp_hash_n := Hasher.hash_value(_normalize_seeds(expected_out))
			if got_hash_n != exp_hash_n:
				print("VERIFY events: FAIL at case '%s' (%s) [seed-normalized hash mismatch]" % [name, fn])
				print("  expected: %s" % Hasher.canonical_stringify(_normalize_seeds(expected_out)))
				print("  got:      %s" % Hasher.canonical_stringify(_normalize_seeds(result)))
				quit(1)
				return
			passed += 1
			continue

		var got_hash := Hasher.hash_value(result)
		if got_hash != expected_hash:
			print("VERIFY events: FAIL at case '%s' (%s)" % [name, fn])
			print("  expected hash: %s" % expected_hash)
			print("  got hash:      %s" % got_hash)
			print("  expected canonical:%s" % Hasher.canonical_stringify(expected_out))
			print("  got canonical:%s" % Hasher.canonical_stringify(result))
			quit(1)
			return
		passed += 1

	print("VERIFY events: PASS (%d cases)" % passed)
	quit(0)


# Deep-copy the state and replace every globalEffects[i].filterConfig.seed with a
# stable string token (so the hasher's float-format limitation cancels on both sides).
func _normalize_seeds(state: Dictionary) -> Dictionary:
	var s := state.duplicate(true)
	if s.has("globalEffects") and s["globalEffects"] != null:
		for ge in (s["globalEffects"] as Array):
			if ge is Dictionary and ge.has("filterConfig") and (ge["filterConfig"] as Dictionary).has("seed"):
				ge["filterConfig"]["seed"] = "<SEED>"
	return s


# Assert each computed globalEffects[i].filterConfig.seed is bit-equal to the golden.
func _verify_seeds_bit_equal(name: String, got: Dictionary, expected) -> bool:
	var got_ge: Array = got["globalEffects"]
	var exp_ge: Array = (expected as Dictionary).get("globalEffects", [])
	if got_ge.size() != exp_ge.size():
		print("VERIFY events: FAIL at case '%s' [globalEffects count %d != %d]" % [name, got_ge.size(), exp_ge.size()])
		return false
	for i in range(got_ge.size()):
		var gs: float = got_ge[i]["filterConfig"]["seed"]
		var es: float = exp_ge[i]["filterConfig"]["seed"]
		if gs != es:
			print("VERIFY events: FAIL at case '%s' [seed[%d] %.17g != %.17g]" % [name, i, gs, es])
			return false
	return true
