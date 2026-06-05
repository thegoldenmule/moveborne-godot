extends CanvasLayer

## Full-screen glitch overlay. A BackBufferCopy captures the rendered game into the
## back-buffer; the ColorRect re-samples it through glitch.gdshader (sliced offsets
## + chromatic aberration). Driven by the live globalEffects[0].filterConfig — hidden
## when no glitch effect is active. See VFX_MAPPING.md §5.5.

const GlitchShader := preload("res://scenes/glitch.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 100
	var vp := get_viewport().get_visible_rect().size

	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	_mat = ShaderMaterial.new()
	_mat.shader = GlitchShader
	_rect = ColorRect.new()
	_rect.position = Vector2.ZERO
	_rect.size = vp
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)

	visible = false


## Show the glitch driven by a filterConfig dict (slices / offset / direction / seed).
func apply(fc: Dictionary) -> void:
	var vp := get_viewport().get_visible_rect().size
	_rect.size = vp
	_mat.set_shader_parameter("screen_size", vp)
	_mat.set_shader_parameter("slices", float(fc.get("slices", 10)))
	_mat.set_shader_parameter("offset_px", float(fc.get("offset", 15)))
	_mat.set_shader_parameter("direction_deg", float(fc.get("direction", 0)))
	_mat.set_shader_parameter("seed", float(fc.get("seed", 0)))
	visible = true


func clear() -> void:
	visible = false
