class_name MbBoardView
extends Control

## The board: a grid of tile cells styled to match the PixiJS client (MbStyle) —
## dark board, purple grid, black/purple/white tiles with outlined glowing
## numerals, tile-effect overlay sprites. Pointer input becomes swiped(direction)
## or cell_tapped(row, col); spawn/merge pops via tweens.

signal swiped(direction)
signal cell_tapped(row, col)

const Style := preload("res://scenes/style.gd")
const GAP := 10.0
const MIN_SWIPE := 24.0

var _size := 4
var _tile := 0.0
var _cells: Array = []          # [{panel, sb, label, overlay}]
var _prev: Array = []
var _highlight: Array = []
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
	fsb.bg_color = Style.BOARD
	fsb.set_corner_radius_all(12)
	fsb.border_color = Style.PRIMARY
	fsb.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size = Vector2(px, px)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_tile = (px - GAP * (n + 1)) / n
	for r in range(n):
		for c in range(n):
			var panel := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Style.CELL
			sb.set_corner_radius_all(6)
			panel.add_theme_stylebox_override("panel", sb)
			panel.position = Vector2(GAP + c * (_tile + GAP), GAP + r * (_tile + GAP))
			panel.size = Vector2(_tile, _tile)
			panel.pivot_offset = Vector2(_tile / 2.0, _tile / 2.0)
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var overlay := TextureRect.new()
			overlay.size = Vector2(_tile, _tile)
			overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.visible = false
			panel.add_child(overlay)

			var label := Label.new()
			label.size = Vector2(_tile, _tile)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 36)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(label)

			add_child(panel)
			_cells.append({"panel": panel, "sb": sb, "label": label, "overlay": overlay})
			_prev.append(0)


func render(state: Dictionary) -> void:
	var tiles: Array = state["board"]["tiles"]
	for i in range(_cells.size()):
		var t: Dictionary = tiles[i]
		var cell: Dictionary = _cells[i]
		var sb: StyleBoxFlat = cell["sb"]
		var label: Label = cell["label"]
		var overlay: TextureRect = cell["overlay"]
		var v := 0 if bool(t["isEmpty"]) else int(t["value"])

		if v == 0:
			sb.bg_color = Style.CELL
			label.text = ""
		else:
			var ts := Style.tile_style(v)
			sb.bg_color = ts["bg"]
			label.text = str(v)
			label.add_theme_color_override("font_color", ts["fill"])
			label.add_theme_color_override("font_outline_color", ts["outline"])
			label.add_theme_constant_override("outline_size", int(ts["ow"]))
			label.add_theme_font_size_override("font_size", int(ts["fs"]))

		_apply_effect_and_border(sb, overlay, t, v, _highlight.has(i))

		if v != int(_prev[i]) and v != 0:
			_pop(cell["panel"], int(_prev[i]) == 0)
		_prev[i] = v


func set_highlight(indices: Array) -> void:
	_highlight = indices


func _apply_effect_and_border(sb: StyleBoxFlat, overlay: TextureRect, t: Dictionary, v: int, highlighted: bool) -> void:
	var eff_type := ""
	if t.has("effect") and t["effect"] != null:
		var e: Dictionary = t["effect"]
		if bool(e.get("active", false)) and str(e.get("type", "")) != "none":
			eff_type = str(e.get("type", ""))

	var tex: Texture2D = Style.effect_texture(eff_type) if eff_type != "" else null
	if tex != null:
		overlay.texture = tex
		overlay.visible = true
	else:
		overlay.visible = false

	if highlighted:
		sb.border_color = Style.HIGHLIGHT
		sb.set_border_width_all(5)
	elif eff_type != "" and tex == null:
		sb.border_color = _effect_color(eff_type)  # decay has no sprite -> colored border
		sb.set_border_width_all(5)
	elif v == 0:
		var grid := Style.GRID
		grid.a = 0.16
		sb.border_color = grid
		sb.set_border_width_all(2)
	else:
		sb.set_border_width_all(0)


func _pop(panel: Control, spawn: bool) -> void:
	var tw := panel.create_tween()
	if spawn:
		panel.scale = Vector2(0.35, 0.35)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		panel.scale = Vector2.ONE
		tw.tween_property(panel, "scale", Vector2(1.18, 1.18), 0.07)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.07)


func _effect_color(effect_type: String) -> Color:
	match effect_type:
		"decay": return Color("6b8e23")
		_: return Style.PRIMARY


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
