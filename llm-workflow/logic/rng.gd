@tool
class_name MbRng
extends RefCounted

## Byte-exact port of npm `seedrandom@3.0.5` default export (ARC4, 53-bit double).
##
## Reference source vendored at: tests/golden/seedrandom-3.0.5-reference.js
## Parity vectors: tests/golden/determinism_golden.json (asserted by tests/test_determinism.gd)
##
## The Moveborne rules engine seeds 5 independent streams by integer seed
## converted to a base-10 string (e.g. seed 4 -> "4"). State is restored by
## re-seeding and replaying N draws (no opaque state blob).

const MASK := 255

const TWO48 := 281474976710656.0   # 256^6  = 2^48  (startdenom)
const TWO52 := 4503599627370496.0  # 2^52              (significance)
const TWO53 := 9007199254740992.0  # 2^53              (overflow)


## A single ARC4 stream with seedrandom's RC4-drop[256] constructor warmup.
class Arc4:
	extends RefCounted

	var i: int = 0
	var j: int = 0
	var S: Array = []

	func _init(key: Array) -> void:
		var keylen: int = key.size()
		if keylen == 0:
			key = [0]
			keylen = 1
		S.resize(256)
		for k in range(256):
			S[k] = k
		var jj: int = 0
		for k in range(256):
			var t: int = S[k]
			jj = MASK & (jj + int(key[k % keylen]) + t)
			S[k] = S[jj]
			S[jj] = t
		# RC4-drop[256]: discard the first 256 outputs. The accumulated return
		# value overflows int64 here but is intentionally discarded; only the
		# i/j/S permutation state matters.
		g(256)

	## Next `count` ARC4 outputs concatenated as one integer in [0, 256^count).
	func g(count: int) -> int:
		var t: int
		var r: int = 0
		var ii: int = i
		var jj: int = j
		var s: Array = S
		var c: int = count
		while c > 0:
			c -= 1
			ii = MASK & (ii + 1)
			t = s[ii]
			jj = MASK & (jj + t)
			var sj: int = s[jj]
			s[ii] = sj
			s[jj] = t
			r = r * 256 + int(s[MASK & (sj + t)])
		i = ii
		j = jj
		return r


## Build an ARC4 stream from a (base-10) string seed.
static func make_stream(seed_string: String) -> Arc4:
	return Arc4.new(_mixkey(seed_string))


## seedrandom's default prng(): a random double in [0,1) with randomness in
## every mantissa bit. Mirrors the reference line-for-line; every intermediate
## is exactly representable as an IEEE-754 double, so this matches JS bit-exact.
static func draw(a: Arc4) -> float:
	var n: float = float(a.g(6))
	var d: float = TWO48
	var x: float = 0.0
	while n < TWO52:
		n = (n + x) * 256.0
		d *= 256.0
		x = float(a.g(1))
	while n >= TWO53:
		n = n / 2.0
		d = d / 2.0
		x = float(int(x) >> 1)
	return (n + x) / d


## seedrandom's mixkey(): folds the seed string into an ARC4 key array.
## For base-10 integer seeds this reduces to the array of digit char codes.
static func _mixkey(seed_string: String) -> Array:
	var key: Array = []
	var smear: int = 0
	var j: int = 0
	var n: int = seed_string.length()
	while j < n:
		var idx: int = MASK & j
		var kv: int = 0
		if idx < key.size():
			kv = int(key[idx])
		smear = smear ^ (kv * 19)
		var cc: int = seed_string.unicode_at(j)
		while key.size() <= idx:
			key.append(0)
		key[idx] = MASK & (smear + cc)
		j += 1
	return key
