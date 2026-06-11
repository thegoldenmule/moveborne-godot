extends Control

## Playable Moveborne (Phase 2): board + HUD + hand (card select & tap-to-target)
## + totem tray, driven by the byte-exact engine via MbMatch. Swipe with arrow
## keys or drag; tap a card then tap target tile(s); R = new game; Esc = cancel.

const MbMatchS := preload("res://game/match_controller.gd")
const BoardViewS := preload("res://scenes/board_view.gd")
const MbHermesClientS := preload("res://net/hermes_client.gd")
const MbSnapserAuthS := preload("res://net/snapser_auth.gd")
const Style := preload("res://scenes/style.gd")
const CountdownS := preload("res://scenes/countdown.gd")
const DooberS := preload("res://scenes/doober.gd")
const GlitchS := preload("res://scenes/glitch.gd")
const GlowShader := preload("res://scenes/glow_text.gdshader")

## Local dev validator (the V-key debug shortcut; tools/run_validator.sh): the
## validator's Hermes-emulation WS endpoint — same envelope as the gateway.
const LOCAL_VALIDATOR_WS := "ws://localhost:5555/hermes/ws"
## Snapser Hermes WSS endpoint: auth is the ?token= query param (session token),
## so this also works from web exports, where WS upgrade headers are blocked.
const SNAPSER_HERMES_WS := "wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws"

## Horizontal breathing room from the screen edges for the HUD (and a guard against
## the bottom nav / device notches eating UI). Logical px (canvas_items stretch).
const SCREEN_MARGIN := 18.0

## Emitted when the player leaves the match (in-match Home/Quit button). The shell's
## MatchState listens for this and pops back to Home. No-op when run standalone.
signal match_exited(result: Dictionary)

# Card -> targeting kind. Totem cards are detected via isTotemCard; time/magnet
# have no engine action (shown as unsupported).
const TARGET := {
	"bomb": "tile", "destroy": "tile", "double": "tile", "split": "tile", "multiply": "tile", "radiate": "tile",
	"clear": "column", "lightning": "column", "vortex": "quadrant",
	"swap": "two", "clone": "two", "teleport": "two",
	"shuffle": "none", "transform": "none",
}

# Hand fan layout (hand.ts): cards arc + rotate instead of a flat row.
const FAN_RADIUS := 130.0
const FAN_SPREAD := PI / 6.0     # ~30deg total spread
const FAN_OVERLAP := 0.62        # horizontal overlap fraction (web 0.7)
const FAN_CARD_W := 86.0

var _match  # MbMatch (untyped to avoid class_name registration flakiness)
var _board
var _net
var _auth   # MbSnapserAuth — anonymous Snapser session for the deployed validator
var _mode := "infinite"   # this match's play mode (selects the validator's reward table)
var _completing := false  # quit pressed; settling rewards with the validator
var _score_val: Label
var _moves_val: Label
var _shards_val: Label
var _combo_lbl: Label             # "{N}X COMBO", shown when combo > 1, pops on increase
var _shown_score := 0             # animated (count-up) score currently displayed
var _shown_combo := 1            # last combo, to detect increases
var _score_tw: Tween
var _shown_shards := 0            # displayed shards; filled as doobers land
var _doobers_pending := 0        # in-flight shard doobers
var _hud_glow: ShaderMaterial    # shared white glow for HUD value labels
var _net_label: Label
var _toast: Label
var _hand_box: Control           # plain container; cards are fanned by hand
var _totem_box: HBoxContainer
var _fx_layer: CanvasLayer       # screen-space, shake-immune floating text
var _countdown                   # active CountdownS overlay, if any
var _glitch                      # full-screen glitch overlay (GlitchS)
var _fan_center: Vector2         # hand-box-local origin for the card fan

var _sel_index := -1
var _sel_type := ""
var _target_kind := ""
var _pending: Array = []


func _ready() -> void:
	# Joined so MbDebug._scene() can resolve us via group lookup once the app shell
	# (not this match) owns current_scene. See game/mcp_game_api.gd.
	add_to_group("mb_match")
	# Per-match config handed in by the shell's MatchState (or Endless default when
	# this scene is launched standalone). Plain Dictionary, mirrors how state is passed.
	var cfg: Dictionary = GameState.next_match if not GameState.next_match.is_empty() else {"mode": "infinite"}
	_mode = str(cfg.get("mode", "infinite"))
	_match = MbMatchS.new()
	_build_ui()
	_match.changed.connect(_on_changed)
	_match.tiles_destroyed.connect(_on_tiles_destroyed)
	# Start the board per mode. Infinite is always offline; Story (and PvP) always
	# play against the Snapser-deployed validator: start the board locally, then
	# sign in + register the starting state with the server (_connect_snapser).
	match str(cfg.get("mode", "infinite")):
		"story":
			_match.new_game_scenario(int(cfg.get("scenario_id", 0)), int(cfg.get("seed", -1)))
			_connect_snapser()
		"pvp":
			_match.new_game(int(cfg.get("seed", -1)))
			_connect_snapser()
		_:
			_match.new_game(int(cfg.get("seed", -1)))
	_play_intro()


func _build_ui() -> void:
	var vp := get_viewport_rect().size
	var margin := SCREEN_MARGIN
	var safe_top := _top_safe_inset()        # device notch / status bar inset (0 on desktop)
	var board_px: float = clampf(minf(vp.x * 0.92, vp.y * 0.62), 300.0, 720.0)
	# Top HUD band (below the notch): a Home row, the stat row, the combo banner, then
	# totems. The board + hand block is vertically centered in the leftover space below.
	var top_bar := safe_top + 154.0
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
	stat_row.offset_left = margin
	stat_row.offset_right = -margin
	stat_row.offset_top = safe_top + 56.0
	stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Tight separation so all three captions (wide brand font) fit inside the edge
	# margins; at 46 the SHARDS column overflowed the right edge.
	stat_row.add_theme_constant_override("separation", 18)
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stat_row)
	_moves_val = _make_stat(stat_row, "MOVES")
	_score_val = _make_stat(stat_row, "SCORE")
	_shards_val = _make_stat(stat_row, "SHARDS")

	# Combo banner (centered, its own band below the stats), shown while combo > 1.
	_combo_lbl = Label.new()
	_combo_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combo_lbl.offset_left = margin
	_combo_lbl.offset_right = -margin
	_combo_lbl.offset_top = safe_top + 106.0
	_combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_lbl.add_theme_font_size_override("font_size", 22)
	_combo_lbl.add_theme_color_override("font_color", Color.WHITE)
	_combo_lbl.add_theme_color_override("font_outline_color", Style.PRIMARY)
	_combo_lbl.add_theme_constant_override("outline_size", 3)
	_combo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_lbl.visible = false
	add_child(_combo_lbl)

	# Validator status — a quiet top-right indicator, hidden until online play engages
	# (press V / launch a PvP match). Kept out of the way during normal offline play.
	_net_label = Label.new()
	_net_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_net_label.offset_left = margin
	_net_label.offset_right = -margin
	_net_label.offset_top = safe_top + 14.0
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_label.add_theme_font_size_override("font_size", 13)
	_net_label.add_theme_color_override("font_color", Style.DIM)
	_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_label.text = "validator: off"
	_net_label.visible = false
	add_child(_net_label)

	_net = MbHermesClientS.new()
	add_child(_net)
	_match.validator = _net
	_net.ready_received.connect(_on_net_ready)
	_net.action_validated.connect(_on_net_validated)
	_net.validator_error.connect(_on_net_error)

	_auth = MbSnapserAuthS.new()
	add_child(_auth)

	_totem_box = HBoxContainer.new()
	_totem_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_totem_box.offset_left = margin
	_totem_box.offset_right = -margin
	_totem_box.offset_top = safe_top + 136.0
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
	_board.shard_earned.connect(_on_shard_earned)

	# Screen-space overlay for floating score text (above the board; not shaken).
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 5
	add_child(_fx_layer)

	# Full-screen glitch overlay (driven by globalEffects during the Fracture scenario).
	_glitch = GlitchS.new()
	add_child(_glitch)

	# Toast: gameplay prompts + feedback ("Tap a tile for bomb", "Played split"). Empty
	# at rest — no standing instructions cluttering the board.
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_left = margin
	_toast.offset_right = -margin
	_toast.offset_top = hand_top + hand_h + 12.0
	_toast.offset_bottom = hand_top + hand_h + 40.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Style.DIM)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.text = ""
	add_child(_toast)

	_hand_box = Control.new()
	_hand_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hand_box.offset_left = 16
	_hand_box.offset_right = -16
	_hand_box.offset_top = hand_top
	_hand_box.offset_bottom = hand_top + hand_h
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # cards handle their own clicks
	add_child(_hand_box)
	# Fan origin in hand-box-local coords: card centers land ~65px down, peaking middle.
	_fan_center = Vector2((vp.x - 32.0) / 2.0, 65.0 + FAN_RADIUS)

	# In-match Home button — pinned to the very top-left (below the notch), styled like
	# the game's cards/board: dark body + purple border, rounded, brand font. Emits
	# match_exited so the shell's MatchState pops back.
	var home_btn := Button.new()
	home_btn.text = "‹ Home"
	home_btn.focus_mode = Control.FOCUS_NONE
	home_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	home_btn.position = Vector2(margin, safe_top + 8.0)
	home_btn.custom_minimum_size = Vector2(0, 34)
	home_btn.add_theme_font_size_override("font_size", 15)
	_style_home_button(home_btn)
	home_btn.pressed.connect(_on_home_pressed)
	add_child(home_btn)


func _on_changed() -> void:
	_board.render(_match.state)
	_rebuild_hand()
	_rebuild_totems()
	_update_hud()
	_update_glitch()


## Show the full-screen glitch when a glitch global effect is active (MED/HIGH).
func _update_glitch() -> void:
	var fc = _active_glitch_config()
	if fc != null and Quality.glow_enabled():
		_glitch.apply(fc)
	else:
		_glitch.clear()


func _active_glitch_config():
	var ge = _match.state.get("globalEffects", null)
	if ge == null or (ge as Array).is_empty():
		return null
	for e in ge:
		if str((e as Dictionary).get("type", "")) == "glitch":
			return (e as Dictionary).get("filterConfig", null)
	return null


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


## Black-hole consume: fly each consumed tile into the hole that ate it (P8). The
## engine tags destroyed tiles with destroyedBy={type:black_hole, position}.
func _on_tiles_destroyed(destroyed: Array) -> void:
	for d in destroyed:
		var db = (d as Dictionary).get("destroyedBy", null)
		if db != null and str((db as Dictionary).get("type", "")) == "black_hole":
			var pos: Dictionary = d["position"]
			var bh: Dictionary = db["position"]
			_board.black_hole_fly(int(pos["row"]), int(pos["col"]), int(d["value"]), int(bh["row"]), int(bh["col"]))


## 3-2-1-GO! intro overlay, then the "Let's Play!" banner (engine.ts:744 / 760).
func _play_intro() -> void:
	if _countdown != null and is_instance_valid(_countdown):
		_countdown.queue_free()
	_countdown = CountdownS.new()
	add_child(_countdown)
	_countdown.play(_show_lets_play)


func _show_lets_play() -> void:
	Anim.banner(_fx_layer, "Let's Play!", 1.0, 48)


## Leave the match: tell the shell (via match_exited) to pop back to Home. There is
## no engine game-over, so this button IS the match-end source. No-op when the scene
## runs standalone (no listener connected).
##
## When online, the quit first settles the match with the validator
## (complete_match): the server computes currency rewards from ITS validated
## state and awards them s2s, so the grant can't be inflated client-side. The
## ack (or a short timeout, so a dead socket can't trap the player in the
## match) is awaited before popping; granted balances merge into GameState for
## an instant top-bar update, and the shell re-reads on resume as the fallback.
func _on_home_pressed() -> void:
	if _completing:
		return
	_completing = true
	if _match.online and _net != null and _net.complete_match():
		var done := [false]
		var on_completed := func(resp: Dictionary) -> void:
			done[0] = true
			var balances = resp.get("balances", {})
			if balances is Dictionary and not balances.is_empty():
				GameState.merge_currencies(balances)
		_net.match_completed.connect(on_completed, CONNECT_ONE_SHOT)
		# Wait for the ack, but never trap the player on a dead socket.
		var waited := 0.0
		while not done[0] and waited < 2.0:
			waited += get_process_delta_time()
			await get_tree().process_frame
		if not done[0]:
			push_warning("Match settlement timed out — shell refresh will reconcile balances")
	match_exited.emit({
		"scenario": _match.scenario_name,
		"score": int(_match.state.get("score", 0)),
		"move_index": int(_match.state.get("moveIndex", 0)),
		"reason": "quit",
	})
	# Standalone (no listener) the emit is a no-op — re-arm the button.
	_completing = false


## Style the in-match Home button to match the game's surfaces: a dark rounded body
## with a purple border (mirrors the power-card / nav look), brighter on hover/press.
func _style_home_button(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Style.BOARD
	sb.set_corner_radius_all(8)
	sb.border_color = Style.PRIMARY
	sb.set_border_width_all(2)
	sb.set_content_margin(SIDE_LEFT, 14)
	sb.set_content_margin(SIDE_RIGHT, 14)
	sb.set_content_margin(SIDE_TOP, 4)
	sb.set_content_margin(SIDE_BOTTOM, 4)
	var hover := sb.duplicate()
	hover.bg_color = Color(Style.PRIMARY, 0.20)
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_color_override("font_color", Style.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)


## Top device-safe inset (notch / status bar) in logical px, so the Home row and HUD
## clear it; resolves to 0 on desktop/editor. get_display_safe_area() is reported in
## GLOBAL screen coordinates, so we make it window-relative by subtracting the window
## position — otherwise a multi-monitor desktop yields a huge bogus inset. Clamped to a
## sane fraction of the viewport so a surprising reading can never wreck the layout.
func _top_safe_inset() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var phys_top := float(safe.position.y - DisplayServer.window_get_position().y)
	if phys_top <= 0.0:
		return 0.0
	# Physical px -> logical (canvas) px via the viewport/window height ratio.
	var vp_y := get_viewport_rect().size.y
	return minf(phys_top * vp_y / float(win.y), vp_y * 0.15)


## Tap handler / MCP target supplier. Returns a status Dictionary (the board's
## cell_tapped signal connection discards it; MbDebug consumes it).
func _on_cell_tapped(row: int, col: int) -> Dictionary:
	if _target_kind == "":
		return {"status": "error", "message": "no card awaiting a target"}
	match _target_kind:
		"tile": return _play({"tile": {"row": row, "col": col}})
		"column": return _play({"column": col})
		"quadrant": return _play({"row": row, "column": col})
		"two":
			_pending.append({"row": row, "col": col})
			if _pending.size() == 1:
				_toast.text = "Tap the second tile for %s" % _sel_type
				return {"status": "awaiting_selection", "selection_mode": "two",
					"message": "tap the second tile for %s" % _sel_type}
			return _play(_two_params())
	return {"status": "error", "message": "unknown target kind '%s'" % _target_kind}


func _two_params() -> Dictionary:
	if _sel_type == "swap":
		return {"tile1": _pending[0], "tile2": _pending[1]}
	return {"sourceTile": _pending[0], "targetTile": _pending[1]}


## Begin playing the card at `index`. Returns a status Dictionary:
##   {status:"complete"}            — totem / no-target card played immediately
##   {status:"awaiting_selection",  — needs targets; selection_mode is the kind
##    selection_mode:"tile"|"column"|"quadrant"|"two"}
##   {status:"error", message}      — invalid index or unsupported card
## The hand button's pressed signal discards the return; MbDebug consumes it.
func _select_card(index: int) -> Dictionary:
	var cards: Array = _match.state["hand"]["cards"]
	if index < 0 or index >= cards.size():
		return {"status": "error", "message": "invalid card index %d" % index}
	var card: Dictionary = cards[index]
	var type := str(card["type"])
	if bool(card.get("isTotemCard", false)):
		var tt := str((card["spawnsTotem"] as Dictionary)["id"])
		var ok: bool = _match.spawn_totem(tt, index)
		_toast.text = ("Spawned totem: %s" % tt) if ok else "Totem spawn failed"
		_cancel_target()
		return {"status": "complete" if ok else "error", "totem": tt,
			"message": ("spawned totem %s" % tt) if ok else "totem spawn failed"}
	if not TARGET.has(type):
		_toast.text = "'%s' has no board action yet" % type
		return {"status": "error", "message": "'%s' has no board action yet" % type}
	var kind := str(TARGET[type])
	if kind == "none":
		var ok: bool = _match.play_card(type, {}, index)
		_toast.text = ("Played %s" % type) if ok else "%s: no valid targets" % type
		_cancel_target()
		return {"status": "complete" if ok else "error", "card_type": type,
			"message": ("played %s" % type) if ok else "%s: no valid targets" % type}
	_sel_index = index
	_sel_type = type
	_target_kind = kind
	_pending = []
	_toast.text = _prompt()
	_rebuild_hand()
	return {"status": "awaiting_selection", "selection_mode": kind, "card_type": type,
		"message": _prompt()}


func _play(params: Dictionary) -> Dictionary:
	var type := _sel_type  # _cancel_target() clears _sel_type, so capture it first
	var ok: bool = _match.play_card(_sel_type, params, _sel_index)
	_toast.text = ("Played %s" % _sel_type) if ok else "%s: invalid target" % _sel_type
	_cancel_target()
	return {"status": "complete" if ok else "error", "card_type": type,
		"message": ("played %s" % type) if ok else "%s: invalid target" % type}


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
		lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		lbl.offset_top = 40
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # wrap within the hand box, don't run off-edge
		_hand_box.add_child(lbl)
		return
	var n := cards.size()
	var csize := Vector2(88, 130)
	for i in range(n):
		var card: Dictionary = cards[i]
		var type := str(card["type"])
		var sel: bool = i == _sel_index
		var supported: bool = TARGET.has(type) or bool(card.get("isTotemCard", false))
		var btn := _make_card(card, csize)
		btn.z_index = i  # later cards overlap on top
		btn.pressed.connect(_select_card.bind(i))
		_hand_box.add_child(btn)
		# Fan placement: arc + rotation; the selected card straightens and lifts out.
		var fan := _fan_pos(i, n)
		var center: Vector2 = _fan_center + fan["pos"]
		var rot: float = fan["rot"]
		if sel:
			rot = 0.0
			center.y -= 22.0
		btn.rotation = rot
		btn.position = center - csize / 2.0
		_card_juice(btn, sel, supported)


## Arc position + rotation for card `index` of `total` (hand.ts calculateFanPosition).
func _fan_pos(index: int, total: int) -> Dictionary:
	if total <= 1:
		return {"pos": Vector2(0.0, -FAN_RADIUS), "rot": 0.0}
	var angle_per := FAN_SPREAD / float(total - 1)
	var a := -FAN_SPREAD / 2.0 + index * angle_per
	var arc := Vector2(sin(a) * FAN_RADIUS, -cos(a) * FAN_RADIUS)
	var base_spacing := FAN_CARD_W * (1.0 - FAN_OVERLAP)
	var x_off := index * base_spacing - (total - 1) * base_spacing / 2.0
	return {"pos": Vector2(arc.x + x_off, arc.y), "rot": a}


## A physical-looking card (power-card-display.ts): dark rounded body + purple
## border, the art, and a purple nameplate with the title. The Button handles clicks.
func _make_card(card: Dictionary, csize: Vector2) -> Button:
	var type := str(card["type"])
	var btn := Button.new()
	btn.custom_minimum_size = csize
	btn.size = csize
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Style.BOARD               # dark card body
	sb.set_corner_radius_all(8)
	sb.border_color = Style.PRIMARY
	sb.set_border_width_all(2)
	if Quality.glow_enabled():              # purple glow halo around the card (MED/HIGH)
		sb.shadow_color = Color(Style.PRIMARY, 0.45)
		sb.shadow_size = 7
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sb)

	var tex := Style.card_texture(type)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 5
		art.offset_top = 5
		art.offset_right = -5
		art.offset_bottom = -22   # leave room for the nameplate
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(art)

	# Purple nameplate strip + black title at the bottom.
	var plate := Panel.new()
	plate.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	plate.offset_left = 3
	plate.offset_right = -3
	plate.offset_top = -19
	plate.offset_bottom = -3
	var psb := StyleBoxFlat.new()
	psb.bg_color = Style.PRIMARY
	psb.set_corner_radius_all(3)
	plate.add_theme_stylebox_override("panel", psb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(plate)

	var name_lbl := Label.new()
	name_lbl.text = str(card.get("name", type))
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color.BLACK)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(name_lbl)
	return btn


## Card feel: yellow + lifted/pulsing when selected, dimmed when it has no board
## action, scale-on-hover otherwise.
func _card_juice(btn: Control, selected: bool, supported: bool) -> void:
	btn.pivot_offset = btn.custom_minimum_size / 2.0  # scale/rotate around center
	if selected:
		btn.z_index = 100  # selected card sits in front of the fan
		btn.modulate = Color("ffd54a")
	elif not supported:
		btn.modulate = Color(0.6, 0.6, 0.6, 0.55)  # dim: no board action yet
	else:
		btn.modulate = Color.WHITE
	btn.mouse_entered.connect(_card_hover.bind(btn, true, selected))
	btn.mouse_exited.connect(_card_hover.bind(btn, false, selected))
	if selected:
		btn.scale = Vector2(1.12, 1.12)
		var tw := btn.create_tween().set_loops()  # gentle idle pulse (freed with the button)
		tw.tween_property(btn, "scale", Vector2(1.18, 1.18), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _card_hover(btn: Control, entering: bool, selected: bool) -> void:
	if selected or not is_instance_valid(btn):
		return
	var to := Vector2(1.08, 1.08) if entering else Vector2.ONE
	btn.create_tween().tween_property(btn, "scale", to, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	_set_shards(int(st["shards"]))
	_set_score(int(st["score"]))
	_set_combo(int(st["comboMultiplier"]))
	_apply_hud_glow(_moves_val, 1)
	_apply_hud_glow(_score_val, 1)
	_apply_hud_glow(_shards_val, 1)


func _hud_glow_material() -> ShaderMaterial:
	if _hud_glow == null:
		_hud_glow = ShaderMaterial.new()
		_hud_glow.shader = GlowShader
		_hud_glow.set_shader_parameter("glow_color", Color.WHITE)
		_hud_glow.set_shader_parameter("glow_width", 0.28)
	return _hud_glow


## White MSDF glow on a HUD value label (MED/HIGH); plain outline on LOW.
func _apply_hud_glow(lbl: Label, base_outline: int) -> void:
	if Quality.glow_enabled():
		lbl.material = _hud_glow_material()
		lbl.add_theme_constant_override("outline_size", 0)
	else:
		lbl.material = null
		lbl.add_theme_constant_override("outline_size", base_outline)


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


## Hold the shard count while doobers are in flight (they fill it on arrival); snap
## on a decrease (auto-draw 8->0 reset) or when nothing is flying.
func _set_shards(target: int) -> void:
	if target < _shown_shards or _doobers_pending <= 0:
		_shown_shards = target
	_shards_val.text = "%d/8" % _shown_shards


## Show "{N}X COMBO" while combo > 1; elastic-pop on every increase (hud.ts).
func _set_combo(combo: int) -> void:
	if combo > 1:
		_combo_lbl.text = "%dX COMBO" % combo
		_combo_lbl.visible = true
		_apply_hud_glow(_combo_lbl, 3)
		if combo > _shown_combo:
			Anim.pop(_combo_lbl)
	else:
		_combo_lbl.visible = false
	_shown_combo = combo


## Screen position of the shard counter — the target for shard doobers.
func shard_target_pos() -> Vector2:
	return _shards_val.global_position + _shards_val.size / 2.0


## One merged tile earned a shard: fly a doober from the tile to the shard counter
## on the shake-immune fx layer (fx/doober.ts). board_pos is board-local.
func _on_shard_earned(board_pos: Vector2) -> void:
	var d := DooberS.new()
	_fx_layer.add_child(d)
	_doobers_pending += 1
	d.arrived.connect(_on_doober_arrived)
	d.fly(_board.rest_position() + board_pos, shard_target_pos())


## A doober reached the counter: tick the displayed shards up one (clamped to the
## real total, so an auto-draw reset mid-flight can't overshoot).
func _on_doober_arrived() -> void:
	_doobers_pending = maxi(0, _doobers_pending - 1)
	_shown_shards = mini(_shown_shards + 1, int(_match.state["shards"]))
	_shards_val.text = "%d/8" % _shown_shards


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
				# When online, a bare new_game() would desync (the validator still
				# holds the old match) — re-register the fresh state as a new match.
				if _match.online:
					_match.online = false
					_match.new_game()
					_cancel_target()
					_start_net(_net_ws_url, _net_player_id, _net_token)
				else:
					_cancel_target()
					_match.new_game()
				_play_intro()
			KEY_ESCAPE:
				_cancel_target()
				_toast.text = ""
			KEY_0: _load_scenario(0)
			KEY_1: _load_scenario(1)
			KEY_2: _load_scenario(2)
			KEY_3: _load_scenario(3)
			KEY_4: _load_scenario(4)
			KEY_5: _load_scenario(5)
			KEY_6: _load_scenario(6)
			KEY_7: _load_scenario(7)
			KEY_V: _connect_validator()
			KEY_Q: _cycle_quality()
			KEY_B: _load_scenario(101)  # test scenario: starts with a black-hole tile
			KEY_G: _load_scenario(17)   # "Fracture": COMBO_BREAK >=3 spawns the screen glitch


func _cycle_quality() -> void:
	Quality.cycle()
	_on_changed()  # refresh board (twist/tile glow) + hand (card glow) for the new tier
	_board.refresh_run_fx()  # start/stop continuous loops for the new tier (no moveIndex change)
	_toast.text = "VFX quality: %s  (Q to cycle)" % Quality.level_name()


## Dev shortcut (V key): restart Endless against the LOCAL validator (:5555).
func _connect_validator() -> void:
	# new_game() BEFORE _cancel_target(): _cancel_target -> _rebuild_hand reads
	# _match.state["hand"], so the state must exist first.
	_match.online = false
	_match.new_game()
	_cancel_target()
	# No gateway in front of the local validator, so the ?token= param IS the
	# self-stamped player id. Locally this is a consistency check, not real auth.
	var player_id := "player_%d" % (randi() % 1000000)
	_start_net(LOCAL_VALIDATOR_WS, player_id, player_id)


## Story/PvP: anonymous Snapser sign-in, then register the CURRENT match state with
## the deployed validator. The board must already be started (new_game[_scenario])
## — that state is what the server replays from. Coroutine; runs detached.
func _connect_snapser() -> void:
	_match.online = false
	_net_label.visible = true
	_net_label.text = "validator: signing in…"
	var ok: bool = await _auth.ensure_session()
	if not ok:
		_on_net_error("Snapser sign-in failed")
		return
	_start_net(SNAPSER_HERMES_WS, _auth.user_id, _auth.session_token)


var _net_ws_url := ""            # last validator target, so R can re-register
var _net_player_id := ""
var _net_token := ""


func _start_net(ws_url: String, player_id: String, token: String) -> void:
	_net_ws_url = ws_url
	_net_player_id = player_id
	_net_token = token
	var match_id := "gd_%d" % (randi() % 1000000)
	# uri_encode the token: a Snapser session token can carry URL-reserved chars
	# (+ / =), which would otherwise corrupt the ?token= value at the gateway.
	_net.init_and_connect(ws_url + "?token=" + token.uri_encode(), match_id, _match.state, player_id, _mode)
	_net_label.visible = true
	_net_label.text = "validator: …"
	_toast.text = "Connecting to validator at %s …" % ws_url


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


# ──────────────────────────────────────────────────────────────────────────────
# MCP / LLM control surface (game-semantic). These public wrappers are driven by
# the MbDebug autoload (game/mcp_game_api.gd) — see MCP_GAME_API.md. They reuse the
# exact targeting state machine the player uses (TARGET / _select_card /
# _on_cell_tapped / _play), so plays animate the board, hand, and VFX normally.
# ──────────────────────────────────────────────────────────────────────────────

## The live match controller (MbMatch), for read access + history binding.
func mcp_match():
	return _match

## Swipe a direction. Cancels any pending card selection first (an automated driver
## shouldn't get wedged mid-target). Returns {ok, moved, move_index}.
func mcp_swipe(direction: String) -> Dictionary:
	if _target_kind != "":
		_cancel_target()
	var moved: bool = _match.swipe(direction)
	return {"ok": true, "moved": moved, "move_index": int(_match.state["moveIndex"])}

## Begin playing the hand card at `index`. See _select_card for the return shape.
func mcp_play_card(index: int) -> Dictionary:
	return _select_card(index)

## Supply a tile/quadrant target (or first/second tile of a two-target card) to the
## card currently awaiting selection. See _on_cell_tapped for the return shape.
func mcp_select_target(row: int, col: int) -> Dictionary:
	return _on_cell_tapped(row, col)

## Supply a column target to the card currently awaiting a column. Row is ignored.
func mcp_select_column(col: int) -> Dictionary:
	return _on_cell_tapped(0, col)

## Cancel the in-progress card selection (clears highlights, re-fans the hand).
func mcp_cancel() -> void:
	_cancel_target()

## Cards playable right now: totem cards + any card whose type has a board action.
## Returns [{index, type, name, selection_mode}] (selection_mode "totem" for totems).
func mcp_playable_cards() -> Array:
	var out: Array = []
	var cards: Array = _match.state["hand"]["cards"]
	for i in range(cards.size()):
		var card: Dictionary = cards[i]
		var type := str(card["type"])
		if bool(card.get("isTotemCard", false)):
			out.append({"index": i, "type": type, "name": str(card.get("name", type)),
				"selection_mode": "totem"})
		elif TARGET.has(type):
			out.append({"index": i, "type": type, "name": str(card.get("name", type)),
				"selection_mode": str(TARGET[type])})
	return out

## Start a fresh Endless game (optionally seeded), with the 3-2-1-GO! intro.
func mcp_new_game(seed_value: int = -1) -> Dictionary:
	_cancel_target()
	_match.new_game(seed_value)
	_play_intro()
	return {"ok": true, "scenario": _match.scenario_name,
		"move_index": int(_match.state["moveIndex"])}

## Load a built-in scenario (0–7, 17 "Fracture", 101 black-hole), optionally seeded.
func mcp_load_scenario(scenario_id: int, seed_value: int = -1) -> Dictionary:
	_cancel_target()
	_match.new_game_scenario(scenario_id, seed_value)
	_toast.text = "Loaded scenario %s" % _match.scenario_name
	return {"ok": true, "scenario": _match.scenario_name,
		"board_size": int(_match.state["board"]["size"]),
		"move_index": int(_match.state["moveIndex"])}
