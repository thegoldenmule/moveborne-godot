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
const NAV_HEIGHT := 96.0

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

	# Nav bar pinned to the bottom of the viewport (raised above the safe-area inset).
	_nav_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_apply_safe_area()
	get_viewport().size_changed.connect(_on_viewport_resized)
	var nav_sb := StyleBoxFlat.new()
	nav_sb.bg_color = MbStyle.BOARD
	nav_sb.border_color = MbStyle.PRIMARY
	nav_sb.set_border_width(SIDE_TOP, 2)
	_nav_bar.add_theme_stylebox_override("panel", nav_sb)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 6)

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

	# Radio selection across the five tab buttons (exactly one active).
	var group := ButtonGroup.new()
	for i in range(5):
		var b: Button = _tabs[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.text = TAB_LABELS[i]
		b.custom_minimum_size = Vector2(62, 70)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_select_tab.bind(i))

	# Emphasize the center Home tab (larger).
	var home_btn: Button = _tabs[HOME_INDEX]
	home_btn.custom_minimum_size = Vector2(96, 86)
	home_btn.add_theme_font_size_override("font_size", 17)

	_select_tab(HOME_INDEX)
	home_btn.button_pressed = true


func _select_tab(index: int) -> void:
	for i in range(_screens.size()):
		_screens[i].visible = (i == index)


func _on_play_mode_selected(cfg: Dictionary) -> void:
	if UiRouter.is_busy():
		return
	UiRouter.push(MatchStateS.new(UiRouter.content_root), cfg)


## Called by ShellState on suspend/resume. Hides BOTH the Control subtree and the
## nav CanvasLayer (a CanvasLayer does not inherit a parent Control's visibility).
func set_active(v: bool) -> void:
	visible = v
	_nav_layer.visible = v


## Raise the nav bar above the device's bottom safe inset (iOS home indicator /
## Android gesture bar). On desktop/editor the safe area equals the window, so this
## resolves to a no-op (pad = 0).
func _apply_safe_area() -> void:
	var pad := _bottom_safe_inset()
	_nav_bar.offset_top = -(NAV_HEIGHT + pad)
	_nav_bar.offset_bottom = -pad


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
