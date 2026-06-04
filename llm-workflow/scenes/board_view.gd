class_name MbBoardView
extends Control

## The board: a grid of tile cells styled to match the PixiJS client (MbStyle) —
## dark board, purple grid, black/purple/white tiles with outlined glowing
## numerals, tile-effect overlay sprites. Pointer input becomes swiped(direction)
## or cell_tapped(row, col); spawn/merge pops via tweens.

signal swiped(direction)
signal cell_tapped(row, col)
## A tile merged: per-tile score contribution + board-local center + combo, for
## a floating "+score" popup spawned on a shake-immune layer by the parent.
signal score_popup(score, board_pos, combo)

const Style := preload("res://scenes/style.gd")
const GAP := 10.0
const MIN_SWIPE := 24.0

var _size := 4
var _tile := 0.0
var _cells: Array = []          # [{panel, sb, label, overlay, flash_tw}]
var _prev: Array = []
var _highlight: Array = []
var _press = null

# VFX — status-driven particle bursts + merge flash + value-scaled screenshake,
# mirroring board.ts. Gated on moveIndex so re-renders/resizes emit nothing.
var _vfx_layer: Node2D
var _last_move_index := -1

# Screenshake (board.ts:677): one decaying random jitter per move, scaled by the
# total merged value. Shakes this board Control's position; the HUD (in the parent)
# stays put. Captures rest position on the first frame of a fresh shake.
var _shaking := false
var _base_pos := Vector2.ZERO
var _shake_t := 0.0
var _shake_dur := 0.0
var _shake_intensity := 0.0


func setup(n: int, px: float) -> void:
	_size = n
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	for c in get_children():
		c.queue_free()
	_cells.clear()
	_prev.clear()
	_last_move_index = -1
	_shaking = false  # rest pos re-captured lazily on the next shake

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
			_cells.append({"panel": panel, "sb": sb, "label": label, "overlay": overlay, "flash_tw": null})
			_prev.append(0)

	# Board-local FX layer: particle coords == panel.position + tile/2. Drawn on
	# top of the cells; shakes with the board since it's a child of this Control.
	_vfx_layer = Node2D.new()
	_vfx_layer.z_index = 50
	add_child(_vfx_layer)


func render(state: Dictionary) -> void:
	# Re-setup if the engine board changed size (a scenario can be 5/6/8), and reset
	# the VFX gate on a fresh game (moveIndex went backwards). Mirrors board.ts's
	# handleBoardSizeChange + a fresh BoardController per match. Without the reset, an
	# R-restart / scenario-load leaves the moveIndex gate stale and merge VFX silently
	# dead until moveIndex climbs back past the previous game's value.
	var bs := int(state["board"].get("size", _size))
	if bs != _size:
		setup(bs, custom_minimum_size.x)
	var move_index := int(state.get("moveIndex", 0))
	if move_index < _last_move_index:
		_reset_render_state()

	# moveIndex gate + per-move dedup, mirroring board.ts: VFX fire at most once
	# per move; visuals always update so re-renders stay correct.
	var is_new_move := move_index > _last_move_index
	if is_new_move:
		_last_move_index = move_index
	var shown := {}            # board.ts tileEffectsShown (per-move set of keys)
	var total_merge_value := 0
	var combo := int(state.get("comboMultiplier", 1))

	var tiles: Array = state["board"]["tiles"]
	for i in range(_cells.size()):
		var t: Dictionary = tiles[i]
		var cell: Dictionary = _cells[i]
		var sb: StyleBoxFlat = cell["sb"]
		var label: Label = cell["label"]
		var overlay: TextureRect = cell["overlay"]

		# A fresh direct bg set must win over any in-flight white-flash tween.
		if cell["flash_tw"] != null and cell["flash_tw"].is_running():
			cell["flash_tw"].kill()

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

		if is_new_move:
			total_merge_value += _trigger_tile_vfx(t, i, cell, shown, combo)

		if v != int(_prev[i]) and v != 0:
			_pop(cell["panel"], int(_prev[i]) == 0)
		_prev[i] = v

	if is_new_move and total_merge_value > 0:
		# intensity = min(5 + totalMergeValue/32 * 0.5, 20); 200ms (board.ts:677)
		_shake(minf(5.0 + float(total_merge_value) / 32.0 * 0.5, 20.0), 0.2)


func set_highlight(indices: Array) -> void:
	_highlight = indices


## Reset per-game render/VFX state without rebuilding cells (same-size new game).
func _reset_render_state() -> void:
	_last_move_index = -1
	for i in range(_prev.size()):
		_prev[i] = 0
	if _shaking:
		position = _base_pos
		_shaking = false


## The board's resting (un-shaken) position, so popups anchor to the tile center
## even if a previous merge's shake is still decaying.
func rest_position() -> Vector2:
	return _base_pos if _shaking else position


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


## Fire status-driven particle bursts for one tile; returns its merged value
## contribution (0 unless this tile merged this move). Mirrors board.ts statuses.
func _trigger_tile_vfx(t: Dictionary, i: int, cell: Dictionary, shown: Dictionary, combo: int) -> int:
	var status := str(t.get("status", "normal"))
	var row := i / _size
	var col := i % _size
	var panel: Control = cell["panel"]
	var center: Vector2 = panel.position + Vector2(_tile / 2.0, _tile / 2.0)
	match status:
		"bombed":
			_fire_once(shown, "bombed-%d-%d" % [row, col], "bomb-explode", center)
		"destroyed":
			_fire_once(shown, "destroyed-%d-%d" % [row, col], "delete", center)
		"purged":
			# once per column, at the column center (row 1.5), like board.ts
			var cx := GAP + col * (_tile + GAP) + _tile / 2.0
			var cy := GAP + 1.5 * (_tile + GAP) + _tile / 2.0
			_fire_once(shown, "purged-col-%d" % col, "purge-column", Vector2(cx, cy))
		"amplified":
			_fire_once(shown, "amplified-%d-%d" % [row, col], "amplify", center)
		"new":
			_fire_once(shown, "new-%d-%d" % [row, col], "new-tile", center)
		"merged":
			var key := "merged-%d-%d" % [row, col]
			if not shown.has(key):
				shown[key] = true
				Vfx.create_effect("merge", center, _vfx_layer)
				_flash(cell)
				# per-tile score = calculateComboScore(value, combo) (merge.ts:1237)
				var value := int(t.get("value", 0))
				var tile_score := value if combo <= 0 else value * combo
				score_popup.emit(tile_score, center, combo)
				return value
	return 0


func _fire_once(shown: Dictionary, key: String, effect: String, pos: Vector2) -> void:
	if shown.has(key):
		return
	shown[key] = true
	Vfx.create_effect(effect, pos, _vfx_layer)


## Flash a merged cell white, then ease its bg back to the tile color (0.75s cubicOut).
func _flash(cell: Dictionary) -> void:
	var sb: StyleBoxFlat = cell["sb"]
	var target_bg: Color = sb.bg_color  # the tile bg just set by render()
	sb.bg_color = Color.WHITE
	var tw := create_tween()
	cell["flash_tw"] = tw
	tw.tween_property(sb, "bg_color", target_bg, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _shake(intensity: float, duration_s: float) -> void:
	if not _shaking:
		_base_pos = position  # board is static between shakes -> current pos is rest
		_shaking = true
	else:
		position = _base_pos
	_shake_intensity = intensity
	_shake_dur = duration_s
	_shake_t = 0.0


func _process(delta: float) -> void:
	if not _shaking:
		return
	_shake_t += delta
	var x := clampf(_shake_t / _shake_dur, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - x, 3.0)         # cubicOut (ease.ts)
	var amp := _shake_intensity * (1.0 - eased)  # intensity * (1 - cubicOut(t))
	position = _base_pos + Vector2((randf() - 0.5) * 2.0 * amp, (randf() - 0.5) * 2.0 * amp)
	if x >= 1.0:
		position = _base_pos
		_shaking = false


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
