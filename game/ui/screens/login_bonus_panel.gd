extends CanvasLayer

## The Daily Login Bonus modal — a CanvasLayer card over a dimmed scrim, reusing
## the Daily Missions modal pattern: full-rect dim that dismisses on tap, a centered
## PanelContainer, auto-hidden until opened. Pure view: it RENDERS the calendar
## strip from a daily_login block + the player's login_calendar level + whether the
## daily_login quest is claimable, and EMITS a single claim intent. The owning
## LoginBonus controller handles the network + reward ceremony and re-renders.
##
## UiDriver: the layer is screen "login_bonus" (so state().modal == "login_bonus" while
## open); the claim button registers as login_bonus.claim, close as login_bonus.close.

const Reg := preload("res://addons/ui_kit/ui_reg.gd")
const Model := preload("res://ui/screens/daily_login_model.gd")

signal claim_requested()
signal closed()

var _block: Dictionary = {}
var _level := 0
var _claimable := false

var _panel: PanelContainer
var _title: Label
var _strip: HFlowContainer
var _claim_btn: Button
var _footer: Label


func _ready() -> void:
	layer = 20
	visible = false
	name = "LoginBonusModal"
	# Its own UiDriver screen so the driver reports modal == "login_bonus" while open.
	Reg.screen(self, "login_bonus")
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Controls under a CanvasLayer don't inherit a parent Control's theme, so set
	# our own brand font (mirrors daily_missions_panel / currency_bar).
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
	_panel.custom_minimum_size = Vector2(312, 0)   # ~312px usable at a 360px surface
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
	_title = Label.new()
	_title.text = "DAILY LOGIN"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", MbStyle.PRIMARY)
	header.add_child(_title)
	var close_btn := Reg.button("close", header, "✕")  # UiDriver: login_bonus.close
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", MbStyle.DIM)
	close_btn.pressed.connect(close)

	# The calendar strip — one cell per day, wrapping for longer cycles.
	_strip = HFlowContainer.new()
	_strip.add_theme_constant_override("h_separation", 8)
	_strip.add_theme_constant_override("v_separation", 8)
	col.add_child(_strip)

	_footer = Label.new()
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", MbStyle.DIM)
	col.add_child(_footer)

	_claim_btn = Reg.button("claim", col, "CLAIM TODAY'S BONUS")  # UiDriver: login_bonus.claim
	_claim_btn.focus_mode = Control.FOCUS_NONE
	_claim_btn.add_theme_color_override("font_color", MbStyle.HIGHLIGHT)
	_claim_btn.pressed.connect(func() -> void: claim_requested.emit())


# --- public API (driven by LoginBonus) ---------------------------------------


## Render the calendar and show the modal.
func open(block: Dictionary, level: int, claimable: bool) -> void:
	render(block, level, claimable)
	visible = true


## Rebuild the strip from a daily_login block + the login_calendar level + whether
## today's bonus is claimable.
func render(block: Dictionary, level: int, claimable: bool) -> void:
	_block = block
	_level = level
	_claimable = claimable

	for c in _strip.get_children():
		c.queue_free()

	var cycle := Model.cycle_length(block)
	var today := Model.today_day(level, cycle)
	for entry in Model.strip(block, level):
		_strip.add_child(_make_cell(entry))

	if claimable:
		_footer.text = "Day %d is ready — claim before tomorrow's reset." % today
		_claim_btn.visible = true
	else:
		_footer.text = "Come back tomorrow for day %d." % today
		_claim_btn.visible = false


## Hide the modal.
func close() -> void:
	visible = false
	closed.emit()


# --- cell builder ------------------------------------------------------------


func _make_cell(entry: Dictionary) -> Control:
	var state := int(entry.get("state", Model.DayState.UPCOMING))
	var is_today := state == Model.DayState.TODAY
	var is_claimed := state == Model.DayState.CLAIMED

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(64, 78)
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.CELL
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	sb.border_color = MbStyle.HIGHLIGHT if is_today else MbStyle.BOARD
	sb.set_border_width_all(2 if is_today else 1)
	cell.add_theme_stylebox_override("panel", sb)
	if is_claimed:
		cell.modulate = Color(1, 1, 1, 0.5)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	cell.add_child(box)

	var day_lbl := Label.new()
	day_lbl.text = "Day %d" % int(entry.get("day", 0))
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_lbl.add_theme_font_size_override("font_size", 11)
	day_lbl.add_theme_color_override("font_color", MbStyle.HIGHLIGHT if is_today else MbStyle.DIM)
	box.add_child(day_lbl)

	var glyph := Label.new()
	glyph.text = "✓" if is_claimed else str(Model.CURRENCY_GLYPHS.get(str(entry.get("currency", "")), Model.CURRENCY_GLYPHS[""]))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", MbStyle.PRIMARY if not is_claimed else MbStyle.HIGHLIGHT)
	box.add_child(glyph)

	var amt := Label.new()
	amt.text = "+%d" % int(entry.get("amount", 0))
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amt.add_theme_font_size_override("font_size", 12)
	amt.add_theme_color_override("font_color", Color("f5c542") if not is_claimed else MbStyle.DIM)
	box.add_child(amt)

	return cell
