class_name MbBoardView
extends Control

## The board: builds a grid of tile cells, renders from engine state with spawn/
## merge pop tweens, and turns pointer input into either a `swiped(direction)` or
## a `cell_tapped(row, col)` (tap = small movement; drag = swipe).

signal swiped(direction)
signal cell_tapped(row, col)

const GAP := 10.0
const MIN_SWIPE := 24.0

var _size := 4
var _tile := 0.0
var _cells: Array = []          # [{panel, sb, label}]
var _prev: Array = []           # previous value per cell (for change detection)
var _highlight: Array = []      # indices currently highlighted
var _press = null


func setup(n: int, px: float) -> void:
	_size = n
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	for c in get_children():
		c.queue_free()
	_cells.clear()
	_prev.clear()

	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color("bbada0")
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size = Vector2(px, px)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_tile = (px - GAP * (n + 1)) / n
	for r in range(n):
		for c in range(n):
			var panel := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("cdc1b4")
			sb.set_corner_radius_all(6)
			panel.add_theme_stylebox_override("panel", sb)
			panel.position = Vector2(GAP + c * (_tile + GAP), GAP + r * (_tile + GAP))
			panel.size = Vector2(_tile, _tile)
			panel.pivot_offset = Vector2(_tile / 2.0, _tile / 2.0)
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var label := Label.new()
			label.size = Vector2(_tile, _tile)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", int(_tile * 0.36))
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(label)

			add_child(panel)
			_cells.append({"panel": panel, "sb": sb, "label": label})
			_prev.append(0)


func render(state: Dictionary) -> void:
	var tiles: Array = state["board"]["tiles"]
	for i in range(_cells.size()):
		var t: Dictionary = tiles[i]
		var cell: Dictionary = _cells[i]
		var sb: StyleBoxFlat = cell["sb"]
		var label: Label = cell["label"]
		var v := 0 if bool(t["isEmpty"]) else int(t["value"])
		if v == 0:
			sb.bg_color = Color("cdc1b4")
			label.text = ""
		else:
			sb.bg_color = _tile_color(v)
			label.text = str(v)
			label.add_theme_color_override("font_color", Color("776e65") if v <= 4 else Color("f9f6f2"))
		_effect_border(sb, t, _highlight.has(i))
		if v != int(_prev[i]) and v != 0:
			_pop(cell["panel"], int(_prev[i]) == 0)
		_prev[i] = v


func set_highlight(indices: Array) -> void:
	_highlight = indices


func _pop(panel: Control, spawn: bool) -> void:
	var tw := panel.create_tween()
	if spawn:
		panel.scale = Vector2(0.35, 0.35)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		panel.scale = Vector2.ONE
		tw.tween_property(panel, "scale", Vector2(1.18, 1.18), 0.07)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.07)


func _effect_border(sb: StyleBoxFlat, t: Dictionary, highlighted: bool) -> void:
	if highlighted:
		sb.set_border_width_all(5)
		sb.border_color = Color("2ecc71")
		return
	var has_eff := t.has("effect") and t["effect"] != null and bool((t["effect"] as Dictionary).get("active", false)) and str((t["effect"] as Dictionary).get("type", "")) != "none"
	if has_eff:
		sb.set_border_width_all(5)
		sb.border_color = _effect_color(str((t["effect"] as Dictionary).get("type", "")))
	else:
		sb.set_border_width_all(0)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press = mb.position
	elif _press != null:
		var start: Vector2 = _press
		var d: Vector2 = mb.position - start
		_press = null
		if d.length() < MIN_SWIPE:
			var rc = _cell_at(start)
			if rc != null:
				cell_tapped.emit(rc[0], rc[1])
		elif absf(d.x) > absf(d.y):
			swiped.emit("right" if d.x > 0 else "left")
		else:
			swiped.emit("down" if d.y > 0 else "up")


func _cell_at(local: Vector2):
	var step := _tile + GAP
	var c := int((local.x - GAP) / step)
	var r := int((local.y - GAP) / step)
	if r < 0 or r >= _size or c < 0 or c >= _size:
		return null
	var x0 := GAP + c * step
	var y0 := GAP + r * step
	if local.x < x0 or local.x > x0 + _tile or local.y < y0 or local.y > y0 + _tile:
		return null
	return [r, c]


func _tile_color(v: int) -> Color:
	match v:
		2: return Color("eee4da")
		4: return Color("ede0c8")
		8: return Color("f2b179")
		16: return Color("f59563")
		32: return Color("f67c5f")
		64: return Color("f65e3b")
		128: return Color("edcf72")
		256: return Color("edcc61")
		512: return Color("edc850")
		1024: return Color("edc53f")
		2048: return Color("edc22e")
		_: return Color("3c3a32")


func _effect_color(effect_type: String) -> Color:
	match effect_type:
		"black_hole": return Color("4b0082")
		"freeze": return Color("4aa6ff")
		"amplify", "amplify_static": return Color("ffd000")
		"lock": return Color("8a8a8a")
		"decay": return Color("6b8e23")
		"stone": return Color("5a5a5a")
		_: return Color("ffffff")
