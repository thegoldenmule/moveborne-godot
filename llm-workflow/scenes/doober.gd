extends Node2D

## Shard doober: a cyan diamond that arcs from a merged tile to the shard counter,
## then pops and frees itself. Port of fx/doober.ts — the tween-manager/RAF chain
## rewritten as create_tween. Lives on a screen-space layer (shake-immune). The arc
## is emergent: x uses cubicInOut and y uses cubicOut over the same 600ms (NOT a
## bezier). See VFX_MAPPING.md §5.6.

var _icon: Node2D   # scaled for the pulse/pop (separate from position-animated self)


func _ready() -> void:
	_icon = Node2D.new()
	add_child(_icon)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0)])
	poly.color = Color("00ffff")  # cyan shard
	_icon.add_child(poly)
	var line := Line2D.new()
	line.points = PackedVector2Array([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0), Vector2(0, -8)])
	line.width = 2.0
	line.default_color = Color.WHITE
	_icon.add_child(line)


func fly(start: Vector2, target: Vector2) -> void:
	position = start
	modulate.a = 0.0

	# Phase 1: fade in quickly.
	create_tween().tween_property(self, "modulate:a", 1.0, 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Phase 2: fly with an arc — x cubicInOut + y cubicOut, in parallel, over 600ms.
	var fly_tw := create_tween().set_parallel(true)
	fly_tw.tween_property(self, "position:x", target.x, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fly_tw.tween_property(self, "position:y", target.y, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Phase 3: pulse 1 -> 1.3 -> 1 over the flight.
	var pulse := create_tween()
	pulse.tween_property(_icon, "scale", Vector2(1.3, 1.3), 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_icon, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# Phase 4: at arrival, pop (scale -> 2 backOut) + fade out, then free.
	var pop := create_tween()
	pop.tween_interval(0.6)
	pop.tween_property(_icon, "scale", Vector2(2, 2), 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.parallel().tween_property(self, "modulate:a", 0.0, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pop.chain().tween_callback(queue_free)
