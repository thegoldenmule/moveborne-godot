extends CanvasLayer

## Countdown intro (3-2-1-GO!) then handoff to the "Let's Play!" banner. Port of
## countdown.ts; the web's per-frame requestAnimationFrame loops are rewritten as
## time-based tweens (VFX_MAPPING.md §2.7 / §5.8). Cosmetic full-screen overlay at
## match start; frees itself when done.

const Style := preload("res://scenes/style.gd")

var _overlay: ColorRect
var _number: Label
var _ready_lbl: Label


func _ready() -> void:
	layer = 100
	var vp := get_viewport().get_visible_rect().size

	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.size = vp
	_overlay.modulate.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# "Get Ready!" — cream fill, brown outline, 100px above center.
	_ready_lbl = _make_label("Get Ready!", 48, Color("faf8ef"), Color("776e65"), 4, vp)
	_ready_lbl.position.y = -100.0
	add_child(_ready_lbl)

	# The big number — white fill, black outline, screen center.
	_number = _make_label("3", 120, Color.WHITE, Color.BLACK, 6, vp)
	add_child(_number)


func _make_label(text: String, fs: int, fill: Color, outline: Color, ow: int, vp: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.size = vp
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.pivot_offset = vp / 2.0  # scale around screen center
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = load(Style.FONT_PATH)
	ls.font_size = fs
	ls.font_color = fill
	ls.outline_size = ow
	ls.outline_color = outline
	l.label_settings = ls
	return l


## Run the intro, then call `on_done` (the parent shows the banner) and free self.
func play(on_done := Callable()) -> void:
	create_tween().tween_property(_overlay, "modulate:a", 0.7, 0.35)  # fade overlay in
	for n in [3, 2, 1]:
		_number.text = str(n)
		_pulse(_number, 1.5)
		_pulse(_ready_lbl, 1.2)
		await get_tree().create_timer(1.0).timeout
	_number.text = "GO!"
	_ready_lbl.visible = false
	_number.scale = Vector2(2, 2)
	await get_tree().create_timer(0.5).timeout
	var fout := create_tween().set_parallel(true)  # fade out while the number grows
	fout.tween_property(_overlay, "modulate:a", 0.0, 0.45)
	fout.tween_property(_number, "modulate:a", 0.0, 0.45)
	fout.tween_property(_number, "scale", Vector2(3, 3), 0.45)
	await fout.finished
	if on_done.is_valid():
		on_done.call()
	queue_free()


func _pulse(node: Control, from: float) -> void:
	node.scale = Vector2(from, from)
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
