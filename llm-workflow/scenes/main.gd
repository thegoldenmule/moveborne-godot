extends Control

## Playable Moveborne scene (Phase 2 vertical slice): builds the board + HUD
## procedurally, renders from the engine state, and drives swipes from keyboard
## (arrows) and touch/mouse drag. New game on R.

const MbMatchS := preload("res://game/match_controller.gd")

const BOARD_PX := 520.0
const GAP := 10.0
const MIN_SWIPE := 24.0

var _match: MbMatch
var _cells: Array = []          # flat row-major: [{sb: StyleBoxFlat, label: Label}]
var _size: int = 4
var _hud: Label
var _toast: Label
var _board: Control
var _press_pos = null


func _ready() -> void:
	_match = MbMatchS.new()
	_build_ui()
	_match.changed.connect(_render)
	_match.new_game()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("faf8ef")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.position = Vector2(0, 18)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color("776e65"))
	add_child(_hud)

	_board = Control.new()
	_board.custom_minimum_size = Vector2(BOARD_PX, BOARD_PX)
	_board.size = Vector2(BOARD_PX, BOARD_PX)
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.position = Vector2(-BOARD_PX / 2.0, -BOARD_PX / 2.0)
	add_child(_board)

	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color("bbada0")
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size = Vector2(BOARD_PX, BOARD_PX)
	_board.add_child(frame)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.position = Vector2(0, -40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color("9c8b7a"))
	_toast.text = "Swipe or arrow keys to move  •  R for new game"
	add_child(_toast)

	_build_board()


func _build_board() -> void:
	for c in _cells:
		(c["label"].get_parent() as Node).queue_free()
	_cells.clear()
	var tile := (BOARD_PX - GAP * (_size + 1)) / _size
	for r in range(_size):
		for col in range(_size):
			var panel := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("cdc1b4")
			sb.set_corner_radius_all(6)
			panel.add_theme_stylebox_override("panel", sb)
			panel.position = Vector2(GAP + col * (tile + GAP), GAP + r * (tile + GAP))
			panel.size = Vector2(tile, tile)
			_board.add_child(panel)

			var label := Label.new()
			label.size = Vector2(tile, tile)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 40)
			panel.add_child(label)

			_cells.append({"sb": sb, "label": label})


func _render() -> void:
	var st: Dictionary = _match.state
	if st.is_empty():
		return
	_size = int(st["board"]["size"])
	if _cells.size() != _size * _size:
		_build_board()
	var tiles: Array = st["board"]["tiles"]
	for i in range(_cells.size()):
		var t: Dictionary = tiles[i]
		var cell: Dictionary = _cells[i]
		var sb: StyleBoxFlat = cell["sb"]
		var label: Label = cell["label"]
		if bool(t["isEmpty"]):
			sb.bg_color = Color("cdc1b4")
			label.text = ""
		else:
			var v := int(t["value"])
			sb.bg_color = _tile_color(v)
			label.text = str(v)
			label.add_theme_color_override("font_color", Color("776e65") if v <= 4 else Color("f9f6f2"))
		_apply_effect_border(sb, t)
	_hud.text = "Score  %d        Combo  x%d        Shards  %d/8        Moves  %d" % [
		int(st["score"]), int(st["comboMultiplier"]), int(st["shards"]), int(st["moveIndex"])
	]


func _apply_effect_border(sb: StyleBoxFlat, t: Dictionary) -> void:
	var has_eff := t.has("effect") and t["effect"] != null and bool((t["effect"] as Dictionary).get("active", false)) and str((t["effect"] as Dictionary).get("type", "")) != "none"
	var w := 5 if has_eff else 0
	sb.border_width_left = w
	sb.border_width_right = w
	sb.border_width_top = w
	sb.border_width_bottom = w
	if has_eff:
		sb.border_color = _effect_color(str((t["effect"] as Dictionary).get("type", "")))


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT: _do("left")
			KEY_RIGHT: _do("right")
			KEY_UP: _do("up")
			KEY_DOWN: _do("down")
			KEY_R: _match.new_game()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
		elif _press_pos != null:
			_swipe_from(_press_pos, event.position)
			_press_pos = null


func _swipe_from(a: Vector2, b: Vector2) -> void:
	var d := b - a
	if d.length() < MIN_SWIPE:
		return
	if absf(d.x) > absf(d.y):
		_do("right" if d.x > 0 else "left")
	else:
		_do("down" if d.y > 0 else "up")


func _do(direction: String) -> void:
	_match.swipe(direction)
