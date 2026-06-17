extends CanvasLayer

## The Daily Missions modal panel — a CanvasLayer card over a dimmed scrim, reusing
## the avatar-picker pattern (settings_tab.gd): full-rect dim that dismisses on tap,
## a centered PanelContainer, auto-hidden until opened. Pure view: it RENDERS from a
## daily_missions block + the normalized active-quest array and EMITS claim intents;
## the owning DailySigil handles the network + currency feedback and re-renders.
##
## MbUi: the layer is screen "daily" (so state().modal == "daily" while open); the
## mission list is a nested screen "missions" so each claim button registers as
## missions.<mission_name> and Claim All as missions.claim_all.

const Reg := preload("res://ui/mcp_ui_reg.gd")
const Model := preload("res://ui/screens/daily_missions_model.gd")

## icon name (Remote Config catalog) -> placeholder glyph, pending generated art
## (artgen), the same stand-in approach as currency_bar's currency glyphs.
const ICON_GLYPHS := {
	"cards": "✦", "trophy": "★", "spark": "✶", "bolt": "✧", "": "◈",
}

signal claim_requested(mission_name: String)
signal claim_all_requested()
signal closed()

var _block: Dictionary = {}
var _quests: Array = []
var _reset_unix := 0

var _panel: PanelContainer
var _countdown: Label
var _caption: Label
var _list: VBoxContainer
var _claim_all_btn: Button


func _ready() -> void:
	layer = 20
	visible = false
	name = "DailyMissionsModal"
	# Its own MbUi screen so the driver reports modal == "daily" while open.
	Reg.screen(self, "daily")
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Controls under a CanvasLayer don't inherit a parent Control's theme, so the
	# brand font won't propagate — set our own (mirrors currency_bar).
	var th := Theme.new()
	th.default_font = load(MbStyle.FONT_PATH)
	th.default_font_size = 16
	root.theme = th

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	# ~312px usable at a 360px surface (MbScreenScaffold's SIDE_PAD budget).
	_panel.custom_minimum_size = Vector2(312, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.BOARD
	sb.border_color = MbStyle.PRIMARY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)

	# Header: title + close.
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "DAILY MISSIONS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", MbStyle.PRIMARY)
	header.add_child(title)
	var close_btn := Reg.button("close", header, "✕")  # MbUi: daily.close
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", MbStyle.DIM)
	close_btn.pressed.connect(close)

	_countdown = Label.new()
	_countdown.add_theme_font_size_override("font_size", 14)
	_countdown.add_theme_color_override("font_color", MbStyle.DIM)
	col.add_child(_countdown)

	_caption = Label.new()
	_caption.text = "Claim before reset or the reward is lost."
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", MbStyle.HIGHLIGHT)
	_caption.visible = false
	col.add_child(_caption)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	# Nested MbUi screen so cards' claim buttons namespace as missions.<name>.
	Reg.screen(_list, "missions")
	scroll.add_child(_list)

	_claim_all_btn = Reg.button("claim_all", _list, "CLAIM ALL")  # MbUi: missions.claim_all
	_claim_all_btn.focus_mode = Control.FOCUS_NONE
	_claim_all_btn.add_theme_color_override("font_color", MbStyle.HIGHLIGHT)
	_claim_all_btn.visible = false
	_claim_all_btn.pressed.connect(func() -> void: claim_all_requested.emit())


# --- public API (driven by DailySigil) ---------------------------------------


## Render the current set and show the modal.
func open(block: Dictionary, quests: Array, now_unix: int) -> void:
	render(block, quests, now_unix)
	visible = true


## Rebuild the cards from a daily_missions block + normalized active quests. now_unix
## is the caller's clock (so the panel's weekday matches the sigil that opened it,
## and tests can inject a deterministic day).
func render(block: Dictionary, quests: Array, now_unix: int) -> void:
	_block = block
	_quests = quests
	_reset_unix = Model.soonest_reset(quests)

	# Clear previous cards but keep the Claim All button (last child, reparented below).
	for child in _list.get_children():
		if child != _claim_all_btn:
			child.queue_free()

	var by_name := {}
	for q in quests:
		by_name[str((q as Dictionary).get("name", ""))] = q

	var weekday := Model.utc_weekday(now_unix)
	var names := Model.todays_mission_names(block, weekday)
	# Fallback: nothing configured but quests exist (offline catalog) — show them all.
	if names.is_empty():
		for q in quests:
			names.append(str((q as Dictionary).get("name", "")))

	var anchor_name := str(block.get("anchor", ""))
	var claimable := Model.claimable_count(quests)
	for nm in names:
		var quest: Dictionary = by_name.get(nm, {})
		_list.add_child(_make_card(nm, quest, nm == anchor_name))

	# Claim All only earns its place when the repeatable loop benefits (>=2 claimable).
	_claim_all_btn.visible = claimable >= 2
	_list.move_child(_claim_all_btn, _list.get_child_count() - 1)

	_caption.visible = claimable >= 1
	_update_countdown()


## Hide the modal.
func close() -> void:
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	if visible:
		_update_countdown()


func _update_countdown() -> void:
	if _countdown == null:
		return
	if _reset_unix <= 0:
		_countdown.text = ""
		return
	var secs := maxi(0, _reset_unix - int(Time.get_unix_time_from_system()))
	_countdown.text = "Resets in " + Model.format_countdown(secs)
	_countdown.add_theme_color_override("font_color",
		Color("f5a142") if Model.is_warning(secs) else MbStyle.DIM)


# --- card builder ------------------------------------------------------------


func _make_card(name: String, quest: Dictionary, is_anchor: bool) -> Control:
	var meta := Model.catalog_entry(_block, name)
	var state := Model.card_state(quest) if not quest.is_empty() else Model.CardState.IN_PROGRESS

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.CELL
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	# Anchor band is visually distinct; a claimable card gets the green accent border.
	sb.border_color = MbStyle.PRIMARY if is_anchor else MbStyle.BOARD
	sb.set_border_width_all(2 if is_anchor else 1)
	if state == Model.CardState.CLAIMABLE:
		sb.border_color = MbStyle.HIGHLIGHT
		sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	if state == Model.CardState.CLAIMED:
		card.modulate = Color(1, 1, 1, 0.55)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	# Icon glyph placeholder.
	var icon := Label.new()
	icon.text = ICON_GLYPHS.get(meta["icon"], ICON_GLYPHS[""])
	icon.custom_minimum_size = Vector2(34, 34)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", MbStyle.HIGHLIGHT if is_anchor else MbStyle.PRIMARY)
	row.add_child(icon)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	row.add_child(body)

	var title := Label.new()
	title.text = ("★ " if is_anchor else "") + str(meta["title"])
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", MbStyle.TEXT)
	body.add_child(title)

	var desc := Label.new()
	desc.text = str(meta["desc"])
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", MbStyle.DIM)
	body.add_child(desc)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = Model.progress_fraction(quest) if not quest.is_empty() else 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	body.add_child(bar)

	# Trailing column: reward chip + (claim button | claimed check).
	var tail := VBoxContainer.new()
	tail.alignment = BoxContainer.ALIGNMENT_CENTER
	tail.add_theme_constant_override("separation", 6)
	row.add_child(tail)

	var reward := Label.new()
	reward.text = str(meta["reward"])
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reward.add_theme_font_size_override("font_size", 12)
	reward.add_theme_color_override("font_color",
		Color("f5c542") if state != Model.CardState.CLAIMED else MbStyle.DIM)
	tail.add_child(reward)

	if state == Model.CardState.CLAIMABLE:
		var claim := Reg.button(name, tail, "CLAIM")  # MbUi: missions.<mission_name>
		claim.focus_mode = Control.FOCUS_NONE
		claim.add_theme_color_override("font_color", MbStyle.HIGHLIGHT)
		claim.pressed.connect(func() -> void: claim_requested.emit(name))
	elif state == Model.CardState.CLAIMED:
		var done := Label.new()
		done.text = "✓ claimed"
		done.add_theme_font_size_override("font_size", 12)
		done.add_theme_color_override("font_color", MbStyle.HIGHLIGHT)
		tail.add_child(done)

	return card
