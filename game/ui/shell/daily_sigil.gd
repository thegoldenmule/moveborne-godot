extends CanvasLayer

## The floating "Daily" sigil — the Daily Missions entry point. Its own CanvasLayer
## (layer 6) over the shell, owned by AppShell, anchored to the Home screen's right
## edge below the currency bar. Carries a reset countdown + a claimable badge and
## opens the modal Daily Missions panel. Shown only on the Home surface with a live
## Snapser session and the feature flag on; hidden during a match / other tabs.
##
## It owns the data orchestration the panel doesn't: fetch the daily_missions block
## (Remote Config) + the active quests, assign today's rotating subset, claim, and
## fly the reward into the currency bar. Pure presentation logic lives in
## MbDailyMissions (daily_missions_model.gd); the network in MbQuestsClient.

const Reg := preload("res://ui/mcp_ui_reg.gd")
const Model := preload("res://ui/screens/daily_missions_model.gd")
const PanelS := preload("res://ui/screens/daily_missions_panel.gd")
const RemoteConfigS := preload("res://net/remote_config_client.gd")
const SafeArea := preload("res://ui/safe_area.gd")

const FLAG_PATH := "user://daily_missions.cfg"
const SIGIL_SIZE := 56.0
const MARGIN := 12.0

var _auth: Node          # MbSnapserAuth (shared shell session)
var _quests: Node        # MbQuestsClient
var _currency_bar: Node  # for the reward fly + slot pulse (optional)
var _remote_config: Node # MbRemoteConfigClient

var _block: Dictionary = {}
var _quests_cache: Array = []
var _reset_unix := 0
var _refreshing := false
var _busy := false       # an assign/claim round-trip is in flight
var _surface_on := false # shell active AND on the Home tab

var _root: Control
var _btn: Button
var _glyph: Label
var _countdown: Label
var _badge: PanelContainer
var _badge_label: Label
var _coachmark: PanelContainer  # one-time FTUE hint on first appearance
var _panel: CanvasLayer  # DailyMissionsModal


## Pass the shell's shared session + clients. quests/currency_bar may be null in a
## headless build (the sigil then stays inert).
func _init(auth: Node = null, quests: Node = null, currency_bar: Node = null) -> void:
	_auth = auth
	_quests = quests
	_currency_bar = currency_bar


func _ready() -> void:
	layer = 6
	name = "DailySigilLayer"
	visible = false
	if _auth != null:
		_remote_config = RemoteConfigS.new(_auth)
		_remote_config.name = "DailyRemoteConfig"
		add_child(_remote_config)
	_build()
	# The modal lives on its own layer (20); owned here so the shell can hide both.
	_panel = PanelS.new()
	add_child(_panel)
	_panel.claim_requested.connect(_on_claim_requested)
	_panel.claim_all_requested.connect(_on_claim_all_requested)
	get_viewport().size_changed.connect(_apply_layout)


func _build() -> void:
	_root = Control.new()
	_root.name = "SigilRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Own theme: a Control under a CanvasLayer doesn't inherit the brand font.
	var th := Theme.new()
	th.default_font = load(MbStyle.FONT_PATH)
	th.default_font_size = 14
	_root.theme = th
	# This layer is the "home" MbUi screen for the sigil button (-> home.daily),
	# matching the open_daily_missions flow. (Distinct node from the Home tab.)
	Reg.screen(self, "home")
	add_child(_root)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	_root.add_child(stack)

	_btn = Reg.button("daily", stack)  # MbUi: home.daily
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.custom_minimum_size = Vector2(SIGIL_SIZE, SIGIL_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(MbStyle.PRIMARY, 0.18)
	sb.border_color = MbStyle.PRIMARY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(SIGIL_SIZE / 2.0))
	_btn.add_theme_stylebox_override("normal", sb)
	_btn.add_theme_stylebox_override("hover", sb)
	_btn.add_theme_stylebox_override("pressed", sb)
	_btn.pressed.connect(_on_sigil_pressed)

	_glyph = Label.new()
	_glyph.text = "◈"
	_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.add_theme_font_size_override("font_size", 26)
	_glyph.add_theme_color_override("font_color", MbStyle.PRIMARY)
	_btn.add_child(_glyph)

	# Claimable badge, pinned to the button's top-right corner.
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = MbStyle.HIGHLIGHT
	bsb.set_corner_radius_all(9)
	bsb.set_content_margin(SIDE_LEFT, 5)
	bsb.set_content_margin(SIDE_RIGHT, 5)
	bsb.set_content_margin(SIDE_TOP, 1)
	bsb.set_content_margin(SIDE_BOTTOM, 1)
	_badge.add_theme_stylebox_override("panel", bsb)
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.offset_left = -22.0
	_badge.offset_top = -4.0
	_badge.offset_right = 6.0
	_badge.visible = false
	_btn.add_child(_badge)
	_badge_label = Label.new()
	_badge_label.add_theme_font_size_override("font_size", 12)
	_badge_label.add_theme_color_override("font_color", MbStyle.BG)
	_badge.add_child(_badge_label)

	_countdown = Label.new()
	_countdown.text = ""
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 11)
	_countdown.add_theme_color_override("font_color", MbStyle.DIM)
	stack.add_child(_countdown)

	# One-time FTUE coachmark, shown the first time the sigil appears; tap to dismiss.
	_coachmark = PanelContainer.new()
	_coachmark.name = "Coachmark"
	_coachmark.visible = false
	_coachmark.mouse_filter = Control.MOUSE_FILTER_STOP
	var csb := StyleBoxFlat.new()
	csb.bg_color = MbStyle.BOARD
	csb.border_color = MbStyle.PRIMARY
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(6)
	csb.set_content_margin_all(8)
	_coachmark.add_theme_stylebox_override("panel", csb)
	_coachmark.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_dismiss_coachmark())
	var clabel := Label.new()
	clabel.text = "New — Daily Missions: play to earn"
	clabel.add_theme_font_size_override("font_size", 11)
	clabel.add_theme_color_override("font_color", MbStyle.TEXT)
	_coachmark.add_child(clabel)
	_root.add_child(_coachmark)

	_apply_layout()


## Pin the sigil stack to the top-right, below the currency band.
func _apply_layout() -> void:
	if _root == null:
		return
	var vp: Vector2 = _root.get_viewport().get_visible_rect().size
	_root.position = Vector2.ZERO
	_root.size = vp
	var stack: Control = _root.get_node_or_null("Stack")
	if stack == null:
		return
	var top := SafeArea.top_inset(vp.y) + 52.0
	if is_instance_valid(_currency_bar) and _currency_bar.has_method("occupied_height"):
		top = _currency_bar.occupied_height() + MARGIN
	stack.position = Vector2(vp.x - SIGIL_SIZE - MARGIN, top)
	stack.size = Vector2(SIGIL_SIZE, 0)
	if is_instance_valid(_coachmark):
		var cw := 196.0
		_coachmark.custom_minimum_size = Vector2(cw, 0)
		_coachmark.position = Vector2(vp.x - cw - MARGIN, top + SIGIL_SIZE + 28.0)
		_coachmark.size = Vector2(cw, 0)


# --- shell hooks -------------------------------------------------------------


## The shell calls this when it suspends/resumes (set_active) and when the tab
## changes; the sigil shows only on the Home surface with a session + flag on.
func set_surface(active: bool, tab_id: String) -> void:
	_surface_on = active and tab_id == "home"
	_apply_visibility()
	if _surface_on:
		refresh()
	elif _panel != null:
		_panel.close()


func _apply_visibility() -> void:
	visible = _surface_on and Model.is_enabled(_block) and _has_session()
	_maybe_show_coachmark()


## Show the one-time FTUE coachmark the first time the sigil is actually visible.
func _maybe_show_coachmark() -> void:
	if not is_instance_valid(_coachmark):
		return
	var seen := bool(_flag("coachmark_seen", 0))
	if Model.should_show_coachmark(seen, visible):
		_coachmark.visible = true
	elif not visible:
		_coachmark.visible = false


func _dismiss_coachmark() -> void:
	if is_instance_valid(_coachmark):
		_coachmark.visible = false
	_mark_coachmark_seen()


func _has_session() -> bool:
	return _auth != null and _quests != null


# --- data orchestration ------------------------------------------------------


## Fetch the daily_missions block + active quests, assign today's missing subset,
## then update the badge/countdown/visibility. Coroutine; fire-and-forget.
func refresh() -> void:
	if _refreshing or not _has_session():
		return
	_refreshing = true
	await _load_block()
	if Model.is_enabled(_block):
		await _assign_todays_set()
		await _reload_quests()
	_refreshing = false
	_apply_visibility()
	_render_badge()
	_maybe_auto_open()


func _load_block() -> void:
	if _remote_config == null:
		return
	var r: Dictionary = await _remote_config.fetch_app_config()
	if bool(r.get("ok", false)):
		_block = RemoteConfigS.extract_daily_missions(r.get("config", {}))
		GameState.set_daily_missions(_block)


func _reload_quests() -> void:
	var r: Dictionary = await _quests.fetch_active_quests(_quests.TAG_DAILY)
	if bool(r.get("ok", false)):
		_quests_cache = r.get("quests", [])
		_reset_unix = Model.soonest_reset(_quests_cache)


## Assign any of today's pool missions that aren't already active (the anchor is
## auto-assigned server-side). Selection = the static weekday map, UTC.
func _assign_todays_set() -> void:
	await _reload_quests()
	var active := {}
	for q in _quests_cache:
		active[str(q.get("name", ""))] = true
	var weekday := Model.utc_weekday(int(Time.get_unix_time_from_system()))
	for nm in Model.todays_mission_names(_block, weekday):
		if not active.has(nm):
			await _quests.assign_quest(nm)


func _render_badge() -> void:
	if _badge == null:
		return
	var state := Model.badge_state(_quests_cache)
	match state:
		Model.Badge.COUNT:
			_badge.visible = true
			_badge_label.visible = true
			_badge_label.text = str(Model.claimable_count(_quests_cache))
		Model.Badge.DOT:
			_badge.visible = true
			_badge_label.visible = false
		_:
			_badge.visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if _reset_unix <= 0:
		_countdown.text = ""
		return
	var secs := maxi(0, _reset_unix - int(Time.get_unix_time_from_system()))
	_countdown.text = Model.format_countdown(secs)
	var warn := Model.is_warning(secs)
	_countdown.add_theme_color_override("font_color", Color("f5a142") if warn else MbStyle.DIM)
	# Escalate only in the final hour, and only while something is still claimable.
	if warn and Model.claimable_count(_quests_cache) > 0:
		_glyph.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 300.0))
	else:
		_glyph.modulate.a = 1.0


# --- open / claim ------------------------------------------------------------


func _on_sigil_pressed() -> void:
	_open_panel()
	_dismiss_coachmark()


func _open_panel() -> void:
	if _panel != null:
		_panel.open(_block, _quests_cache, int(Time.get_unix_time_from_system()))


func _on_claim_requested(mission_name: String) -> void:
	await _claim(mission_name)
	_after_claims()


func _on_claim_all_requested() -> void:
	if _busy:
		return
	# Snapshot the claimables so re-renders mid-loop don't disturb iteration.
	var names: Array = []
	for q in _quests_cache:
		if Model.card_state(q) == Model.CardState.CLAIMABLE:
			names.append(str(q.get("name", "")))
	for nm in names:
		await _claim(nm)
	_after_claims()


func _claim(mission_name: String) -> void:
	if _busy or _quests == null:
		return
	_busy = true
	var r: Dictionary = await _quests.claim_quest_rewards(mission_name)
	_busy = false
	if not bool(r.get("ok", false)):
		push_warning("Daily Missions: claim %s failed: %s" % [mission_name, r.get("error", "")])
		return
	var granted: Dictionary = r.get("granted", {})
	if not granted.is_empty():
		_fly_reward(granted)
		# The claim grant is a DELTA — add it, don't replace the wallet total.
		GameState.add_currencies(granted)


## Re-fetch after a claim (or batch) so card states, the badge, and the countdown
## reflect the server, then re-render the open panel.
func _after_claims() -> void:
	await _reload_quests()
	_render_badge()
	if _panel != null and _panel.visible:
		_panel.render(_block, _quests_cache, int(Time.get_unix_time_from_system()))


## Genre-standard "coins fly to the balance": a glyph eases from the panel center
## into the matching currency-bar slot, then the slot pulses + count-up re-renders.
func _fly_reward(granted: Dictionary) -> void:
	if not is_instance_valid(_currency_bar) or not _currency_bar.has_method("slot_global_pos"):
		return
	var from_pos := _root.get_viewport().get_visible_rect().size / 2.0
	for nm in granted:
		var fly := CanvasLayer.new()
		fly.layer = 30
		add_child(fly)
		var lbl := Label.new()
		lbl.text = "✦"
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color("f5c542"))
		lbl.position = from_pos
		fly.add_child(lbl)
		var target: Vector2 = _currency_bar.slot_global_pos(nm)
		var tw := lbl.create_tween()
		tw.tween_property(lbl, "position", target, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			if _currency_bar.has_method("pulse_slot"):
				_currency_bar.pulse_slot(nm)
			fly.queue_free())


# --- auto-open + coachmark (local flags) -------------------------------------


## Auto-surface the panel ONLY when a reward is at risk: claimables exist AND either
## it's the first open of this daily period or we're inside the final hour.
func _maybe_auto_open() -> void:
	if _panel == null or _panel.visible or Model.claimable_count(_quests_cache) == 0:
		return
	var secs := Model.seconds_to_reset(_quests_cache, int(Time.get_unix_time_from_system()))
	var first_open := _reset_unix > 0 and _reset_unix != int(_flag("last_auto_period", 0))
	if Model.is_warning(secs) or first_open:
		_set_flag("last_auto_period", _reset_unix)
		_open_panel()


func _mark_coachmark_seen() -> void:
	_set_flag("coachmark_seen", 1)


func _flag(key: String, default):
	var cfg := ConfigFile.new()
	if cfg.load(FLAG_PATH) != OK:
		return default
	return cfg.get_value("daily", key, default)


func _set_flag(key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(FLAG_PATH)
	cfg.set_value("daily", key, value)
	cfg.save(FLAG_PATH)
