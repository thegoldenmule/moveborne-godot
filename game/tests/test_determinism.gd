@tool
extends McpTestSuite

## Phase 0 parity gate: proves the GDScript RNG (MbRng) and hash/canonical-JSON
## (MbHasher) reproduce the TS reference byte-for-byte, using golden vectors
## generated from the real npm packages (tests/golden/generate_golden.js).

const GOLDEN_PATH := "res://tests/golden/determinism_golden.json"

# preload by path so the suite loads even before the class_name globals are
# registered in the editor's class cache.
const MbRngS := preload("res://logic/rng.gd")
const MbHasherS := preload("res://logic/hasher.gd")

var _golden: Dictionary = {}


func suite_name() -> String:
	return "determinism"


func suite_setup(_ctx: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		fail_setup("golden file missing: " + GOLDEN_PATH)
		return
	var txt := FileAccess.get_file_as_string(GOLDEN_PATH)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		fail_setup("golden parse failed (got %s)" % type_string(typeof(parsed)))
		return
	_golden = parsed


## IEEE-754 double -> big-endian hex (unambiguous, avoids decimal parse rounding).
func _f64be_hex(x: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, x)  # little-endian
	var out := ""
	for k in range(7, -1, -1):
		out += "%02x" % bytes[k]
	return out


func test_rng_sequences() -> void:
	var rng_golden: Dictionary = _golden["rng"]
	for seed_str in rng_golden.keys():
		var hexes: Array = rng_golden[seed_str]["f64be"]
		var a := MbRngS.make_stream(seed_str)
		for i in range(hexes.size()):
			var got: float = MbRngS.draw(a)
			var got_hex := _f64be_hex(got)
			assert_eq(got_hex, hexes[i], "rng seed=%s i=%d got=%s (%s) want=%s" % [seed_str, i, str(got), got_hex, str(hexes[i])])


func test_hash_strings() -> void:
	var arr: Array = _golden["hash"]
	for entry in arr:
		var got := MbHasherS.hash_string(entry["input"])
		assert_eq(got, entry["hash"], "hash input=%s" % entry["input"])


func test_canonical_roundtrip() -> void:
	var arr: Array = _golden["canonical"]
	for entry in arr:
		var canon: String = entry["canonical"]
		var parsed = JSON.parse_string(canon)
		var reser := MbHasherS.canonical_stringify(parsed)
		assert_eq(reser, canon, "canonical re-serialization mismatch")
		assert_eq(MbHasherS.hash_string(reser), entry["hash"], "canonical hash mismatch")


func test_null_key_omitted() -> void:
	var d := {"a": 1, "b": null, "c": 2}
	var s := MbHasherS.canonical_stringify(d)
	assert_false(s.contains("\"b\""), "null-valued key should be omitted; got: " + s)
	assert_eq(s, "{\n  \"a\": 1,\n  \"c\": 2\n}", "omission formatting")


func test_empty_array_format() -> void:
	var s := MbHasherS.canonical_stringify({"arr": []})
	assert_eq(s, "{\n  \"arr\": [\n  ]\n}", "empty array format")


func _double_from_be_hex(h: String) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	for k in range(8):
		bytes[7 - k] = ("0x" + h.substr(k * 2, 2)).hex_to_int()  # big-endian hex -> little-endian buffer
	return bytes.decode_double(0)


func test_float_formatting() -> void:
	# JS Number->String parity for non-integer floats (e.g. globalEffects filterConfig.seed).
	var path := "res://tests/golden/float_format_golden.json"
	if not FileAccess.file_exists(path):
		fail_setup("missing float golden: " + path)
		return
	var arr: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	for entry in arr:
		var f := _double_from_be_hex(entry["f64be"])
		var got := MbHasherS._num_float(f)
		assert_eq(got, entry["js"], "float %s: got %s want %s" % [entry["f64be"], got, entry["js"]])
