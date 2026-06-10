extends Control
## Persistent shell: a bottom nav (5 tabs) + a content host showing the selected
## tab screen. Tabs are a flat radio selector (NOT a router push). Launching a play
## mode pushes a MatchState via the UiRouter. Hidden (with its nav) while a match
## covers it.

const MatchStateS := preload("res://ui/router/match_state.gd")
const HomeScene := preload("res://ui/screens/home.tscn")
const PlaceholderScene := preload("res://ui/screens/placeholder_tab.tscn")

const HOME_INDEX := 2
const TAB_LABELS := ["Collection", "Leaderboard", "Home", "Guilds", "Settings"]
const TAB_ICONS: Array[Texture2D] = [
	preload("res://assets/generated/icons/collections_icon.svg"),
	preload("res://assets/generated/icons/leaderboard_ticon.svg"),
	preload("res://assets/generated/icons/home_icon.svg"),
	preload("res://assets/generated/icons/guilds_icon.svg"),
	preload("res://assets/generated/icons/settings_icon.svg"),
]
const NAV_HEIGHT := 96.0
const TAB_ICON_SIZE := 60
const TAB_ICON_SELECTED_SCALE := 1.65
const TAB_ICON_POP_Y := 16.0  # selected icon center, px below the bar's top edge
const HOME_ICON_SIZE := 112
const HOME_ICON_LIFT := 11.0  # home icon center, px above the button's center

@onready var _content: Control = $Content
@onready var _nav_layer: CanvasLayer = $NavLayer
@onready var _nav_bar: PanelContainer = $NavLayer/NavBar
@onready var _row: HBoxContainer = $NavLayer/NavBar/Row
@onready var _tabs: Array = [
	$NavLayer/NavBar/Row/TabCollection,
	$NavLayer/NavBar/Row/TabLeaderboard,
	$NavLayer/NavBar/Row/TabHome,
	$NavLayer/NavBar/Row/TabGuilds,
	$NavLayer/NavBar/Row/TabSettings,
]

var _screens: Array = []
var _tab_icons: Array = []   # TextureRect per side tab (null at HOME_INDEX)
var _tab_labels: Array = []  # Label per side tab (null at HOME_INDEX)
var _current_tab := HOME_INDEX
var _bg: ColorRect


func _ready() -> void:
	# Wire the brand font into the shared menu theme (theme_manage can't set it).
	if theme != null:
		theme.default_font = load(MbStyle.FONT_PATH)
		theme.default_font_size = 18

	# A Control parented under a CanvasLayer doesn't reliably inherit the viewport
	# size from anchors alone, so size the shell + content host explicitly.
	var vp := get_viewport_rect().size
	# Top-left anchors (equal-opposite) + explicit size: fills the viewport without
	# the "size overridden by anchors" warning that full-rect + explicit size emits.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = vp
	_content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_content.position = Vector2.ZERO
	_content.size = vp

	# Dark app background behind the content (the brand near-black).
	_bg = ColorRect.new()
	_bg.color = MbStyle.BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	move_child(_bg, 0)
	_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_bg.size = vp

	# Nav on its own higher CanvasLayer so its buttons win the GUI-input race over the
	# full-screen content Controls (which otherwise swallow taps in the bottom strip).
	_nav_layer.layer = 5

	# Nav bar pinned full-width to the bottom. Sized explicitly: a Control under a
	# CanvasLayer doesn't resolve BOTTOM_WIDE anchors to the viewport reliably (it
	# would collapse to its content width instead).
	_nav_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_apply_safe_area()
	get_viewport().size_changed.connect(_on_viewport_resized)
	var nav_sb := StyleBoxFlat.new()
	nav_sb.bg_color = MbStyle.BOARD
	nav_sb.border_color = MbStyle.PRIMARY
	nav_sb.set_border_width(SIDE_TOP, 2)
	nav_sb.set_content_margin_all(0)
	nav_sb.set_content_margin(SIDE_TOP, 2)
	_nav_bar.add_theme_stylebox_override("panel", nav_sb)
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_row.add_theme_constant_override("separation", 0)

	# Build the five tab screens into the content host (Home is real; rest stubs).
	for i in range(5):
		var screen: Control
		if i == HOME_INDEX:
			screen = HomeScene.instantiate()
			screen.play_mode_selected.connect(_on_play_mode_selected)
		else:
			screen = PlaceholderScene.instantiate()
			screen.set_title(TAB_LABELS[i])
		_content.add_child(screen)
		screen.position = Vector2.ZERO
		screen.size = vp
		_screens.append(screen)

	# Radio selection across the five tab buttons; each takes an equal share of the
	# full bar width (Home a wider share), exactly one active. Side-tab icons are
	# overlay TextureRects (not Button.icon) so the selected one can scale up and
	# pop past the bar frame — a Button clamps its own icon inside its rect.
	var group := ButtonGroup.new()
	for i in range(5):
		var b: Button = _tabs[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 72)
		_style_nav_button(b)
		b.pressed.connect(_select_tab.bind(i))
		if i == HOME_INDEX:
			_tab_icons.append(null)
			_tab_labels.append(null)
		else:
			_tab_icons.append(_make_tab_icon(b, TAB_ICONS[i]))
			_tab_labels.append(_make_tab_label(b, TAB_LABELS[i]))

	# Emphasize the center Home tab: wider share, icon-only (no label), an
	# oversized overlay icon lifted to break the bar frame (a Button.icon would be
	# clamped inside the button rect), and a pulsing additive violet halo behind it.
	var home_btn: Button = _tabs[HOME_INDEX]
	home_btn.size_flags_stretch_ratio = 1.5
	var home_ic := _make_tab_icon(home_btn, TAB_ICONS[HOME_INDEX])
	home_ic.modulate = Color.WHITE
	var hh := HOME_ICON_SIZE / 2.0
	home_ic.offset_left = -hh
	home_ic.offset_right = hh
	home_ic.offset_top = -hh - HOME_ICON_LIFT
	home_ic.offset_bottom = hh - HOME_ICON_LIFT
	_add_home_glow(home_btn)

	# Deferred: the icon tween targets read button sizes, which the HBoxContainer
	# only resolves on its (queued) sort — selecting now would bake stale rects.
	_select_tab.call_deferred(HOME_INDEX)
	home_btn.button_pressed = true


func _select_tab(index: int) -> void:
	_current_tab = index
	for i in range(_screens.size()):
		_screens[i].visible = (i == index)
	# Selected side tab: icon grows and pops up past the bar frame, label shows
	# beneath it. Unselected tabs collapse back to a centered base-size icon.
	# (Home is always icon-only — its glow is the emphasis.)
	var half := TAB_ICON_SIZE / 2.0
	for i in range(_tabs.size()):
		if i == HOME_INDEX:
			continue
		var b: Button = _tabs[i]
		var ic: TextureRect = _tab_icons[i]
		var lb: Label = _tab_labels[i]
		var selected := (i == index)
		lb.visible = selected
		var target_scale := Vector2.ONE * (TAB_ICON_SELECTED_SCALE if selected else 1.0)
		var target_mod := Color.WHITE if selected else Color(1, 1, 1, 0.55)
		# Anchors are all-center with a center pivot, so position is the icon's
		# top-left and position + half is its visual center whatever the scale.
		var center_y := TAB_ICON_POP_Y if selected else b.size.y * 0.5
		var target_pos := Vector2(b.size.x * 0.5 - half, center_y - half)
		var old: Tween = ic.get_meta("tw") if ic.has_meta("tw") else null
		if old != null:
			old.kill()
		var tw := ic.create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_BACK if selected else Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_property(ic, "scale", target_scale, 0.18)
		tw.tween_property(ic, "position", target_pos, 0.18)
		tw.tween_property(ic, "modulate", target_mod, 0.18)
		ic.set_meta("tw", tw)


## Overlay icon for a side tab: center-anchored at base size with a center pivot,
## so _select_tab can tween scale/position freely (incl. past the button rect —
## neither the Button nor the NavBar clips children).
func _make_tab_icon(btn: Button, tex: Texture2D) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = tex
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = Color(1, 1, 1, 0.55)
	btn.add_child(ic)
	var half := TAB_ICON_SIZE / 2.0
	ic.anchor_left = 0.5
	ic.anchor_top = 0.5
	ic.anchor_right = 0.5
	ic.anchor_bottom = 0.5
	ic.offset_left = -half
	ic.offset_top = -half
	ic.offset_right = half
	ic.offset_bottom = half
	ic.pivot_offset = Vector2(half, half)
	return ic


## Bottom-anchored label for a side tab; visible only while the tab is selected.
func _make_tab_label(btn: Button, text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 10)
	lb.add_theme_color_override("font_color", MbStyle.TEXT)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.visible = false
	btn.add_child(lb)
	lb.anchor_left = 0.0
	lb.anchor_right = 1.0
	lb.anchor_top = 1.0
	lb.anchor_bottom = 1.0
	lb.offset_left = 0.0
	lb.offset_right = 0.0
	lb.offset_top = -26.0
	lb.offset_bottom = -8.0
	return lb


func _on_play_mode_selected(cfg: Dictionary) -> void:
	if UiRouter.is_busy():
		return
	UiRouter.push(MatchStateS.new(UiRouter.content_root), cfg)


## Called by ShellState on suspend/resume. Hides BOTH the Control subtree and the
## nav CanvasLayer (a CanvasLayer does not inherit a parent Control's visibility).
func set_active(v: bool) -> void:
	visible = v
	_nav_layer.visible = v


## Flat nav-bar look: transparent tabs with dim text; the selected (toggled) tab
## gets a subtle purple highlight + bright text. Overrides the themed Button box.
func _style_nav_button(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("focus", empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	b.add_theme_stylebox_override("hover", hover)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(MbStyle.PRIMARY, 0.20)
	sel.set_corner_radius_all(10)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_color_override("font_color", MbStyle.DIM)
	b.add_theme_color_override("font_hover_color", MbStyle.TEXT)
	b.add_theme_color_override("font_pressed_color", MbStyle.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", MbStyle.TEXT)


## A soft violet halo behind the Home icon: oversized additive copies of the icon
## texture, centered in the button, alpha-pulsing forever. Additive blend means they
## only brighten, so draw order over the button's own icon doesn't matter.
func _add_home_glow(btn: Button) -> void:
	# [scale of the halo vs the icon, peak alpha, trough alpha]
	for layer in [[1.25, 0.9, 0.45], [1.6, 0.5, 0.2]]:
		var halo_size: float = HOME_ICON_SIZE * layer[0]
		var glow := TextureRect.new()
		glow.texture = TAB_ICONS[HOME_INDEX]
		glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		glow.modulate = Color(MbStyle.PRIMARY, layer[2])
		btn.add_child(glow)
		glow.anchor_left = 0.5
		glow.anchor_top = 0.5
		glow.anchor_right = 0.5
		glow.anchor_bottom = 0.5
		glow.offset_left = -halo_size / 2.0
		glow.offset_top = -halo_size / 2.0 - HOME_ICON_LIFT
		glow.offset_right = halo_size / 2.0
		glow.offset_bottom = halo_size / 2.0 - HOME_ICON_LIFT
		var tw := glow.create_tween().set_loops()
		tw.tween_property(glow, "modulate:a", layer[1], 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glow, "modulate:a", layer[2], 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Raise the nav bar above the device's bottom safe inset (iOS home indicator /
## Android gesture bar). On desktop/editor the safe area equals the window, so this
## resolves to a no-op (pad = 0).
func _apply_safe_area() -> void:
	var vp := get_viewport_rect().size
	var pad := _bottom_safe_inset()
	_nav_bar.size = Vector2(vp.x, NAV_HEIGHT)
	_nav_bar.position = Vector2(0.0, vp.y - NAV_HEIGHT - pad)


func _bottom_safe_inset() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var phys_bottom := float(win.y) - float(safe.position.y + safe.size.y)
	if phys_bottom <= 0.0:
		return 0.0
	# Physical px -> logical (canvas) px via the viewport/window height ratio.
	return phys_bottom * get_viewport_rect().size.y / float(win.y)


## Re-fill on viewport resize (aspect=expand changes the logical size per device).
func _on_viewport_resized() -> void:
	var vp := get_viewport_rect().size
	size = vp
	_content.size = vp
	if is_instance_valid(_bg):
		_bg.size = vp
	for s in _screens:
		if is_instance_valid(s):
			s.size = vp
	_apply_safe_area()
	# Re-derive icon rects once the nav buttons settle at their new widths.
	_select_tab.call_deferred(_current_tab)
