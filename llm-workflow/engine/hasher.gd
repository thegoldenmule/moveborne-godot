@tool
class_name MbHasher
extends RefCounted

## Canonical JSON serializer (compatible with `json-stable-stringify(x,{space:2})`)
## plus the custom 8-lane rolling state hash from moveborne/src/logic/src/hashing.ts.
##
## NOTE: the upstream function is named `sha256` but is NOT real SHA-256 — it is a
## non-cryptographic rolling hash. The synchronous custom hash is what
## `computeStateHash` uses and what the wire protocol compares.
## Parity vectors: tests/golden/determinism_golden.json.

# Lane init values are the real SHA-256 IVs; lane shift amounts as in hashing.ts.
const IV := [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
const SHIFTS := [5, 7, 11, 13, 17, 19, 23, 29]


## Emulate JS `x | 0`: wrap to a signed 32-bit integer.
static func _to_int32(v: int) -> int:
	v = v & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	return v


## The custom rolling hash over the UTF-8 bytes of `s`. 64 lowercase hex chars.
static func hash_string(s: String) -> String:
	var data: PackedByteArray = s.to_utf8_buffer()
	var h: Array = []
	for lane in range(8):
		h.append(_to_int32(IV[lane]))
	var count: int = data.size()
	for idx in range(count):
		var b: int = data[idx]
		for lane in range(8):
			var hv: int = h[lane]
			h[lane] = _to_int32((hv << SHIFTS[lane]) - hv + b)
	var out: String = ""
	for lane in range(8):
		out += "%08x" % (h[lane] & 0xFFFFFFFF)
	return out


## Hash a value via its canonical serialization (the state-hash entry point).
static func hash_value(value) -> String:
	return hash_string(canonical_stringify(value))


## Serialize a Variant to canonical JSON identical to json-stable-stringify with
## {space:2}: keys sorted lexicographically at every depth, 2-space indent,
## arrays in order, and dictionary keys with a null value OMITTED (mirrors JS
## dropping `undefined`-valued fields).
static func canonical_stringify(value) -> String:
	return _ser(value, 0)


static func _ser(node, level: int) -> String:
	# Returns "" to signal an omitted value (null) so callers can drop the key.
	if node == null:
		return ""
	var indent: String = "\n" + "  ".repeat(level)
	if node is Array:
		var parts: Array = []
		for i in range(node.size()):
			var item: String = _ser(node[i], level + 1)
			if item == "":
				item = "null"
			parts.append(indent + "  " + item)
		return "[" + ",".join(parts) + indent + "]"
	elif node is Dictionary:
		var keys: Array = node.keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			var sv: String = _ser(node[k], level + 1)
			if sv == "":
				continue
			parts.append(indent + "  " + _quote(str(k)) + ": " + sv)
		return "{" + ",".join(parts) + indent + "}"
	else:
		return _leaf(node)


static func _leaf(node) -> String:
	if node is bool:
		return "true" if node else "false"
	if node is int:
		return str(node)
	if node is float:
		return _num_float(node)
	if node is String or node is StringName:
		return _quote(str(node))
	return _quote(str(node))


## Format a float like JS JSON.stringify: integer-valued floats print without a
## decimal point; otherwise shortest round-trip. (Deeper float-format parity with
## JS String(n) is a Phase 1 hardening item once more golden vectors exist.)
static func _num_float(f: float) -> String:
	if not is_finite(f):
		return "null"
	if f == floor(f) and abs(f) < 1e15:
		return str(int(f))
	return str(f)


## JSON string quoting matching JSON.stringify for our (ASCII) data.
static func _quote(s: String) -> String:
	var out: String = "\""
	for i in range(s.length()):
		var c: int = s.unicode_at(i)
		if c == 0x22:
			out += "\\\""
		elif c == 0x5C:
			out += "\\\\"
		elif c == 0x08:
			out += "\\b"
		elif c == 0x09:
			out += "\\t"
		elif c == 0x0A:
			out += "\\n"
		elif c == 0x0C:
			out += "\\f"
		elif c == 0x0D:
			out += "\\r"
		elif c < 0x20:
			out += "\\u%04x" % c
		else:
			out += String.chr(c)
	out += "\""
	return out
