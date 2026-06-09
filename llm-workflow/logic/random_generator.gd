@tool
class_name MbRandom
extends RefCounted

## 5-namespace deterministic RNG, mirroring moveborne/src/logic/src/random.ts.
## Each namespace is an independent seedrandom(ARC4) stream seeded by the integer
## seed as a base-10 string; state is restored by replaying `index` draws.

const Rng := preload("res://logic/rng.gd")

var _streams: Dictionary = {}
var _indices: Dictionary = {}


func _init(seeds: Dictionary, indices: Dictionary) -> void:
	for ns in seeds.keys():
		var seed_int := int(seeds[ns])
		var idx := int(indices.get(ns, 0))
		var stream := Rng.make_stream(str(seed_int))
		for i in range(idx):
			Rng.draw(stream)
		_streams[ns] = stream
		_indices[ns] = idx


## Draw the next double in [0,1) for the given namespace and advance its index.
func get_random(ns: String) -> float:
	var v := Rng.draw(_streams[ns])
	_indices[ns] = int(_indices[ns]) + 1
	return v


func get_indices() -> Dictionary:
	return _indices.duplicate()
