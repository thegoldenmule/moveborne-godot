extends Control

## Playable Moveborne (Phase 2): board + HUD + hand (card select & tap-to-target)
## + totem tray, driven by the byte-exact engine via MbMatch. Swipe with arrow
## keys or drag; tap a card then tap target tile(s); R = new game; Esc = cancel.

const MbMatchS := preload("res://game/match_controller.gd")
const BoardViewS := preload("res://scenes/board_view.gd")
const MbValidatorClientS := preload("res://net/validator_client.gd")
const Style := preload("res://scenes/style.gd")
const CountdownS := preload("res://scenes/countdown.gd")

const VALIDATOR_URL := "http://localhost:5055"

# Card -> targeting kind. Totem cards are detected via isTotemCard; time/magnet
# have no engine action (shown as unsupported).
const TARGET := {
	"bomb": "tile", "destroy": "tile", "double": "tile", "split": "tile", "multiply": "tile", "radiate": "tile",
	"clear": "column", "lightning": "column", "vortex": "quadrant",
	"swap": "two", "clone": "two", "teleport": "two",
	"shuffle": "none", "transform": "none",
}

var _match  # MbMatch (untyped to avoid class_name registration flakiness)
var _board
var _net
var _score_val: Label
var _moves_val: Label
var _shards_val: Label
var _combo_lbl: Label             # "{N}X COMBO", shown when combo > 1, pops on increase
var _shown_score := 0             # animated (count-up) score currently displayed
var _shown_combo := 1            # last combo, to detect increases
var _score_tw: Tween
var _scen_label: Label
var _net_label: Label
var _toast: Label
var _hand_box: HBoxContainer
var _totem_box: HBoxContainer
var _fx_layer: CanvasLayer       # screen-space, shake-immune floating text
var _countdown                   # active CountdownS overlay, if any

var _sel_index := -1
var _sel_type := ""
var _target_kind := ""
var _pending: Array = []


func _ready() -> void:
	_match = MbMatchS.new()
	_build_ui()
	_match.changed.connect(_on_changed)
	_match.new_game()
	_play_intro()


func _build_ui() -> void:
	var vp := get_viewport_rect().size
	var board_px: float = clampf(minf(vp.x * 0.92, vp.y * 0.62), 300.0, 720.0)
	# Vertically center the board + hand block in the space below the top bar.
	var top_bar := 120.0
	var hand_h := 150.0
	var gap := 24.0
	var board_y := top_bar + maxf(20.0, (vp.y - top_bar - (board_px + gap + hand_h) - 40.0) / 2.0)
	var hand_top := board_y + board_px + gap

	var th := Theme.new()
	th.default_font = load(Style.FONT_PATH)
	th.default_font_size = 18
	theme = th

	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# HUD stat row: MOVES / SCORE / SHARDS as caption+value widgets (hud.ts HudText).
	var stat_row := HBoxContainer.new()
	stat_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stat_row.offset_top = 30
	stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_row.add_theme_constant_override("separation", 46)
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stat_row)
	_moves_val = _make_stat(stat_row, "MOVES")
	_score_val = _make_stat(stat_row, "SCORE")
	_shards_val = _make_stat(stat_row, "SHARDS")

	# Combo banner (centered, its own band below the stats), shown while combo > 1.
	_combo_lbl = Label.new()
	_combo_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combo_lbl.offset_top = 80
	_combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_lbl.add_theme_font_size_override("font_size", 22)
	_combo_lbl.add_theme_color_override("font_color", Color.WHITE)
	_combo_lbl.add_theme_color_override("font_outline_color", Style.PRIMARY)
	_combo_lbl.add_theme_constant_override("outline_size", 3)
	_combo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_lbl.visible = false
	add_child(_combo_lbl)

	_scen_label = Label.new()
	_scen_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_scen_label.position = Vector2(16, 8)
	_scen_label.add_theme_font_size_override("font_size", 13)
	_scen_label.add_theme_color_override("font_color", Style.DIM)
	_scen_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scen_label)

	_net_label = Label.new()
	_net_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_net_label.position = Vector2(-250, 8)
	_net_label.size = Vector2(234, 18)
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_label.add_theme_font_size_override("font_size", 13)
	_net_label.add_theme_color_override("font_color", Style.DIM)
	_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_label.text = "validator: off"
	add_child(_net_label)

	_net = MbValidatorClientS.new()
	add_child(_net)
	_match.validator = _net
	_net.ready_received.connect(_on_net_ready)
	_net.action_validated.connect(_on_net_validated)
	_net.validator_error.connect(_on_net_error)

	_totem_box = HBoxContainer.new()
	_totem_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_totem_box.offset_top = 110
	_totem_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_totem_box.add_theme_constant_override("separation", 14)
	_totem_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_totem_box)

	_board = BoardViewS.new()
	add_child(_board)
	_board.setup(4, board_px)
	_board.position = Vector2((vp.x - board_px) / 2.0, board_y)
	_board.swiped.connect(_on_swiped)
	_board.cell_tapped.connect(_on_cell_tapped)
	_board.score_popup.connect(_on_score_popup)

	# Screen-space overlay for floating score text (above the board; not shaken).
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 5
	add_child(_fx_layer)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = hand_top + hand_h + 12.0
	_toast.offset_bottom = hand_top + hand_h + 40.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Style.DIM)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.text = "Swipe / arrows to move  ·  tap a card to play  ·  0–7 scenarios  ·  R restart  ·  V validator"
	add_child(_toast)

	_hand_box = HBoxContainer.new()
	_hand_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hand_box.offset_left = 16
	_hand_box.offset_right = -16
	_hand_box.offset_top = hand_top
	_hand_box.offset_bottom = hand_top + hand_h
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 10)
	add_child(_hand_box)


func _on_changed() -> void:
	_board.render(_match.state)
	_rebuild_hand()
	_rebuild_totems()
	_update_hud()


func _on_swiped(direction: String) -> void:
	if _target_kind != "":
		return
	_match.swipe(direction)


## Floating "+score" on each merged tile (input.ts:789): green normally, yellow on
## high combo (>2). board_pos is board-local; offset by the board's rest position.
func _on_score_popup(score: int, board_pos: Vector2, combo: int) -> void:
	var screen_pos: Vector2 = _board.rest_position() + board_pos
	var color := Color("ffff00") if combo > 2 else Color("00ff00")
	Anim.float_text(_fx_layer, screen_pos, "+%d" % score, color, 20, 1.5, 30.0)


## 3-2-1-GO! intro overlay, then the "Let's Play!" banner (engine.ts:744 / 760).
func _play_intro() -> void:
	if _countdown != null and is_instance_valid(_countdown):
		_countdown.queue_free()
	_countdown = CountdownS.new()
	add_child(_countdown)
	_countdown.play(_show_lets_play)


func _show_lets_play() -> void:
	Anim.banner(_fx_layer, "Let's Play!", 1.0, 48)


func _on_cell_tapped(row: int, col: int) -> void:
	if _target_kind == "":
		return
	match _target_kind:
		"tile": _play({"tile": {"row": row, "col": col}})
		"column": _play({"column": col})
		"quadrant": _play({"row": row, "column": col})
		"two":
			_pending.append({"row": row, "col": col})
			if _pending.size() == 1:
				_toast.text = "Tap the second tile for %s" % _sel_type
			else:
				_play(_two_params())


func _two_params() -> Dictionary:
	if _sel_type == "swap":
		return {"tile1": _pending[0], "tile2": _pending[1]}
	return {"sourceTile": _pending[0], "targetTile": _pending[1]}


func _select_card(index: int) -> void:
	var cards: Array = _match.state["hand"]["cards"]
	if index < 0 or index >= cards.size():
		return
	var card: Dictionary = cards[index]
	var type := str(card["type"])
	if bool(card.get("isTotemCard", false)):
		var tt := str((card["spawnsTotem"] as Dictionary)["id"])
		var ok: bool = _match.spawn_totem(tt, index)
		_toast.text = ("Spawned totem: %s" % tt) if ok else "Totem spawn failed"
		_cancel_target()
		return
	if not TARGET.has(type):
		_toast.text = "'%s' has no board action yet" % type
		return
	var kind := str(TARGET[type])
	if kind == "none":
		var ok: bool = _match.play_card(type, {}, index)
		_toast.text = ("Played %s" % type) if ok else "%s: no valid targets" % type
		_cancel_target()
		return
	_sel_index = index
	_sel_type = type
	_target_kind = kind
	_pending = []
	_toast.text = _prompt()
	_rebuild_hand()


func _play(params: Dictionary) -> void:
	var ok: bool = _match.play_card(_sel_type, params, _sel_index)
	_toast.text = ("Played %s" % _sel_type) if ok else "%s: invalid target" % _sel_type
	_cancel_target()


func _cancel_target() -> void:
	_sel_index = -1
	_sel_type = ""
	_target_kind = ""
	_pending = []
	if _board != null:
		_board.set_highlight([])
	_rebuild_hand()


func _prompt() -> String:
	match _target_kind:
		"tile": return "Tap a tile for %s  (Esc to cancel)" % _sel_type
		"column": return "Tap a column for %s  (Esc to cancel)" % _sel_type
		"quadrant": return "Tap top-left of a 2x2 for %s  (Esc to cancel)" % _sel_type
		"two": return "Tap the first tile for %s  (Esc to cancel)" % _sel_type
	return ""


func _rebuild_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()
	var cards: Array = _match.state["hand"]["cards"]
	if cards.is_empty():
		var lbl := Label.new()
		lbl.text = "no cards — merge to earn shards (auto-draws a card at 8)"
		lbl.add_theme_color_override("font_color", Style.DIM)
		lbl.add_theme_font_size_override("font_size", 16)
		_hand_box.add_child(lbl)
		return
	for i in range(cards.size()):
		var card: Dictionary = cards[i]
		var type := str(card["type"])
		var tex := Style.card_texture(type)
		var sel: bool = i == _sel_index
		if tex != null:
			var tb := TextureButton.new()
			tb.texture_normal = tex
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			tb.custom_minimum_size = Vector2(82, 130)
			tb.modulate = Color("ffd54a") if sel else Color.WHITE
			tb.pressed.connect(_select_card.bind(i))
			_hand_box.add_child(tb)
		else:
			var b := Button.new()
			b.custom_minimum_size = Vector2(110, 130)
			b.text = "%s\n%s" % [str(card.get("name", "?")), type]
			b.add_theme_font_size_override("font_size", 13)
			if sel:
				b.modulate = Color("ffd54a")
			b.pressed.connect(_select_card.bind(i))
			_hand_box.add_child(b)


func _rebuild_totems() -> void:
	for c in _totem_box.get_children():
		c.queue_free()
	var totems: Array = _match.state["totems"]["active"]
	for t in totems:
		var type := str((t as Dictionary).get("type", "?"))
		var tex := Style.totem_texture(type)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(42, 42)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.tooltip_text = type
			_totem_box.add_child(tr)
		else:
			var lbl := Label.new()
			lbl.text = "◆ %s" % type
			lbl.add_theme_font_size_override("font_size", 16)
			lbl.add_theme_color_override("font_color", Style.PRIMARY)
			_totem_box.add_child(lbl)


func _update_hud() -> void:
	var st: Dictionary = _match.state
	_moves_val.text = str(int(st["moveIndex"]))
	_shards_val.text = "%d/8" % int(st["shards"])
	_set_score(int(st["score"]))
	_set_combo(int(st["comboMultiplier"]))
	_scen_label.text = "Scenario: %s" % _match.scenario_name


## One HUD stat: a caption (purple) over a value (white, purple-outlined). Returns
## the value Label so the caller can update/animate it.
func _make_stat(parent: Node, caption: String) -> Label:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 16)
	cap.add_theme_color_override("font_color", Style.PRIMARY)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var val := Label.new()
	val.text = "0"
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 22)
	val.add_theme_color_override("font_color", Style.TEXT)
	val.add_theme_color_override("font_outline_color", Style.PRIMARY)
	val.add_theme_constant_override("outline_size", 1)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cap)
	box.add_child(val)
	parent.add_child(box)
	return val


## Score with a count-up tween on increase; snap on reset/correction (new game).
func _set_score(target: int) -> void:
	if target == _shown_score:
		return
	if _score_tw != null and _score_tw.is_running():
		_score_tw.kill()
	if target < _shown_score:
		_shown_score = target
		_score_val.text = str(target)
		return
	_score_tw = create_tween()
	_score_tw.tween_method(_set_score_text, _shown_score, target, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shown_score = target


func _set_score_text(v) -> void:
	_score_val.text = str(int(v))


## Show "{N}X COMBO" while combo > 1; elastic-pop on every increase (hud.ts).
func _set_combo(combo: int) -> void:
	if combo > 1:
		_combo_lbl.text = "%dX COMBO" % combo
		_combo_lbl.visible = true
		if combo > _shown_combo:
			Anim.pop(_combo_lbl)
	else:
		_combo_lbl.visible = false
	_shown_combo = combo


## Screen position of the shard counter — the target for shard doobers (future P4).
func shard_target_pos() -> Vector2:
	return _shards_val.global_position + _shards_val.size / 2.0


func _load_scenario(scenario_id: int) -> void:
	_cancel_target()
	_match.new_game_scenario(scenario_id)
	_toast.text = "Loaded scenario %s" % _match.scenario_name


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT: _key_swipe("left")
			KEY_RIGHT: _key_swipe("right")
			KEY_UP: _key_swipe("up")
			KEY_DOWN: _key_swipe("down")
			KEY_R:
				_cancel_target()
				_match.new_game()
				_play_intro()
			KEY_ESCAPE:
				_cancel_target()
				_toast.text = "Swipe to move  •  tap a card to play  •  0–7 scenarios  •  R = new game"
			KEY_0: _load_scenario(0)
			KEY_1: _load_scenario(1)
			KEY_2: _load_scenario(2)
			KEY_3: _load_scenario(3)
			KEY_4: _load_scenario(4)
			KEY_5: _load_scenario(5)
			KEY_6: _load_scenario(6)
			KEY_7: _load_scenario(7)
			KEY_V: _connect_validator()


func _connect_validator() -> void:
	_cancel_target()
	_match.online = false
	_match.new_game()
	var match_id := "gd_%d" % (randi() % 1000000)
	var player_id := "player_%d" % (randi() % 1000000)
	_net.init_and_connect(VALIDATOR_URL, match_id, _match.state, player_id)
	_net_label.text = "validator: …"
	_toast.text = "Connecting to validator at %s …" % VALIDATOR_URL


func _on_net_ready(_current_state: Dictionary) -> void:
	_match.online = true
	_net_label.text = "validator: on ✓"
	_net_label.add_theme_color_override("font_color", Color("2e9e5b"))
	_toast.text = "Connected — every move is now validated by the server"


func _on_net_validated(index: int, matched: bool, corrected_state) -> void:
	if matched:
		_net_label.text = "validator: ✓ %d" % index
		_net_label.add_theme_color_override("font_color", Color("2e9e5b"))
	else:
		if corrected_state is Dictionary:
			_match.adopt_server_state(corrected_state)
		_net_label.text = "validator: ✗ %d" % index
		_net_label.add_theme_color_override("font_color", Color("c0392b"))
		_toast.text = "Desync at move %d — snapped to validator state" % index


func _on_net_error(message: String) -> void:
	_match.online = false
	_net_label.text = "validator: err"
	_net_label.add_theme_color_override("font_color", Color("c0392b"))
	_toast.text = "Validator: %s" % message


func _key_swipe(direction: String) -> void:
	if _target_kind == "":
		_match.swipe(direction)
