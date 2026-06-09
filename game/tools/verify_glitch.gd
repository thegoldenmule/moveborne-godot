extends SceneTree

## Parity verifier for MbEngine._process_global_effects (globalEffects.ts
## processGlobalEffects). Replays the oracle cases from glitch_golden.json (generated
## from the real TS dist) and asserts both the full state hash AND the effect-spawn
## RNG draw count match byte-for-byte.

const MbEngineS := preload("res://logic/engine.gd")
const Hasher := preload("res://logic/hasher.gd")
const MbRandomS := preload("res://logic/random_generator.gd")

const GOLDEN := "res://tests/golden/glitch_golden.json"


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string(GOLDEN)
	if raw == "":
		print("VERIFY glitch: FAIL (could not read golden %s)" % GOLDEN)
		quit(1)
		return
	var data = JSON.parse_string(raw)
	if data == null or not (data is Dictionary) or not data.has("cases"):
		print("VERIFY glitch: FAIL (golden parse error)")
		quit(1)
		return

	var cases: Array = data["cases"]
	var passed := 0
	for case in cases:
		var name := str(case["name"])
		var input: Dictionary = case["input"]
		var expected_hash := str(case["outputHash"])

		var rng := MbRandomS.new(input["randomSeeds"], input["rngIndices"])
		var result: Dictionary = MbEngineS._process_global_effects(input, rng)

		# RNG draw count (proves the per-effect draw order/count matches).
		var expected_idx = case["rngIndicesAfter"]
		var got_idx := rng.get_indices()
		for ns in (expected_idx as Dictionary).keys():
			if int(expected_idx[ns]) != int(got_idx.get(ns, 0)):
				print("VERIFY glitch: FAIL at '%s': rng[%s] expected %d got %d" % [name, ns, int(expected_idx[ns]), int(got_idx.get(ns, 0))])
				quit(1)
				return

		# Full state hash, including the non-integer float seed + offset.
		var got_hash := Hasher.hash_value(result)
		if got_hash != expected_hash:
			print("VERIFY glitch: FAIL at '%s'" % name)
			print("  expected hash: %s" % expected_hash)
			print("  got hash:      %s" % got_hash)
			print("  expected canonical: %s" % Hasher.canonical_stringify(case["output"]))
			print("  got canonical:      %s" % Hasher.canonical_stringify(result))
			quit(1)
			return
		passed += 1

	print("VERIFY glitch: PASS (%d cases)" % passed)
	quit(0)
