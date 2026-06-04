extends Node

## Vfx — particle-effect dispatcher (autoload). Mirrors the web client's revolt-fx
## `createEffect({type, x, y})`: spawns a one-shot particle burst from a preset
## table into a caller-provided layer. Presentation-only — never touches engine
## state. See VFX_MAPPING.md §5.2 / §6.
##
## First cut uses CPUParticles2D, not GPUParticles2D: ~20 short-lived particles
## per merge is negligible on CPU, and its 2D-native emission (spread = 180 ->
## full-circle radial burst) is far simpler to drive correctly from pure GDScript
## than a 3D-oriented ParticleProcessMaterial. A GPU port is a later optimization
## (roadmap P2/P11); the streak/anisotropic emitters are deferred (P11).

const FRAME_DIR := "res://assets/fx/frames/"

# Preset table mirroring assets/fx/bundles/custom-1/effects.json. Durations are
# already in seconds (revolt-fx JSON is seconds). shape: "point" | "disc";
# blend: "add" | "normal"; grow: scale ramps small->big (spawn pop) vs big->small
# (burst shrink). vmin/vmax = initial speed px/s; radius = emission disc radius.
const EMITTERS := {
	"new-tile":     {frame = "plus",        count = 5,  life = 0.5,  color = "b400ff", blend = "add", shape = "point", vmin = 0.0,   vmax = 0.0,   smin = 0.6, smax = 2.6, radius = 0.0,  grow = true},
	"merge":        {frame = "plus",        count = 18, life = 0.28, color = "b400ff", blend = "add", shape = "disc",  vmin = 200.0, vmax = 560.0, smin = 0.4, smax = 0.9, radius = 6.0,  grow = false},
	"delete":       {frame = "x",           count = 10, life = 0.4,  color = "b400ff", blend = "add", shape = "disc",  vmin = 60.0,  vmax = 220.0, smin = 0.4, smax = 1.0, radius = 28.0, grow = false},
	"bomb-explode": {frame = "plus",        count = 12, life = 0.55, color = "b400ff", blend = "add", shape = "disc",  vmin = 90.0,  vmax = 280.0, smin = 0.5, smax = 1.2, radius = 20.0, grow = false},
	"purge-column": {frame = "plus",        count = 20, life = 0.5,  color = "b400ff", blend = "add", shape = "disc",  vmin = 120.0, vmax = 420.0, smin = 0.4, smax = 1.0, radius = 10.0, grow = false},
	"amplify":      {frame = "plus",        count = 10, life = 0.5,  color = "fedc56", blend = "add", shape = "point", vmin = 0.0,   vmax = 40.0,  smin = 0.5, smax = 1.6, radius = 4.0,  grow = true},
	# deck-ready is not dispatched yet — awaits a ported deck-display (deck-display.ts:124).
	"deck-ready":   {frame = "deck-symbol", count = 5,  life = 0.5,  color = "b400ff", blend = "add", shape = "point", vmin = 0.0,   vmax = 0.0,   smin = 0.5, smax = 2.2, radius = 0.0,  grow = true},
}

var _tex_cache := {}
var _grow_curve: Curve
var _shrink_curve: Curve
var _fade: Gradient


## Spawn the named one-shot burst at `pos` (in `layer`'s local space). No-op for
## an unknown effect name or a null layer.
func create_effect(effect_name: String, pos: Vector2, layer: Node) -> void:
	if not EMITTERS.has(effect_name) or layer == null:
		return
	var e: Dictionary = EMITTERS[effect_name]
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = int(e["count"])
	p.lifetime = float(e["life"])
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.texture = _frame(str(e["frame"]))
	p.direction = Vector2(0, -1)
	p.spread = 180.0  # +/-180deg = full-circle radial burst
	p.initial_velocity_min = float(e["vmin"])
	p.initial_velocity_max = float(e["vmax"])
	p.gravity = Vector2.ZERO
	if str(e["shape"]) == "disc":
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = maxf(0.01, float(e["radius"]))
	else:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.scale_amount_min = float(e["smin"])
	p.scale_amount_max = float(e["smax"])
	p.scale_amount_curve = _scale_curve(bool(e["grow"]))
	p.color = Color(str(e["color"]))
	p.color_ramp = _fade_gradient()
	if str(e["blend"]) == "add":
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	layer.add_child(p)
	# free the node once the one-shot burst has fully finished
	p.finished.connect(p.queue_free)
	p.emitting = true


func _frame(frame_name: String) -> Texture2D:
	if _tex_cache.has(frame_name):
		return _tex_cache[frame_name]
	var path := FRAME_DIR + frame_name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[frame_name] = tex
	return tex


func _scale_curve(grow: bool) -> Curve:
	if grow:
		if _grow_curve == null:
			_grow_curve = Curve.new()
			_grow_curve.add_point(Vector2(0.0, 0.05))
			_grow_curve.add_point(Vector2(1.0, 1.0))
		return _grow_curve
	if _shrink_curve == null:
		_shrink_curve = Curve.new()
		_shrink_curve.add_point(Vector2(0.0, 1.0))
		_shrink_curve.add_point(Vector2(1.0, 0.0))
	return _shrink_curve


func _fade_gradient() -> Gradient:
	if _fade == null:
		_fade = Gradient.new()
		_fade.set_offset(0, 0.0)
		_fade.set_color(0, Color(1, 1, 1, 0.9))
		_fade.set_offset(1, 1.0)
		_fade.set_color(1, Color(1, 1, 1, 0.0))
	return _fade
