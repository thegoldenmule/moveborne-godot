extends SceneTree

## Parity verifier for MbEvents.initialize_event_trigger_states
## (eventTriggerState.ts initializeEventTriggerStates). Replays the oracle cases
## from event_init_golden.json (generated from the real TS dist) and asserts the
## resulting eventTriggerStates hash byte-for-byte.

const MbEventsS := preload("res://engine/events.gd")
const Hasher := preload("res://engine/hasher.gd")

const GOLDEN := "res://tests/golden/event_init_golden.json"


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string(GOLDEN)
	if raw == "":
		print("VERIFY event_init: FAIL (could not read golden %s)" % GOLDEN)
		quit(1)
		return
	var data = JSON.parse_string(raw)
	if data == null or not (data is Dictionary) or not data.has("cases"):
		print("VERIFY event_init: FAIL (golden parse error)")
		quit(1)
		return

	var cases: Array = data["cases"]
	var passed := 0
	for case in cases:
		var name := str(case["name"])
		var rules = case["eventRules"]
		var state: Dictionary = case["state"]
		var expected_hash := str(case["outputHash"])

		var result = MbEventsS.initialize_event_trigger_states(rules, state)
		var got_hash := Hasher.hash_value({"ets": result})
		if got_hash != expected_hash:
			print("VERIFY event_init: FAIL at '%s'" % name)
			print("  expected hash: %s" % expected_hash)
			print("  got hash:      %s" % got_hash)
			print("  got canonical: %s" % Hasher.canonical_stringify({"ets": result}))
			quit(1)
			return
		passed += 1

	print("VERIFY event_init: PASS (%d cases)" % passed)
	quit(0)
