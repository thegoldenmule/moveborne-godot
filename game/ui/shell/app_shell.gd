extends Control
## Persistent shell: a bottom nav (5 tabs) + a content host showing the selected
## tab screen. Tabs are a flat radio selector (NOT a router push). Launching a play
## mode pushes a MatchState via the UiRouter. Hidden (with its nav) while a match
## covers it.

const MatchStateS := preload("res://ui/router/match_state.gd")
const StoryMapStateS := preload("res://ui/router/story_map_state.gd")
const HomeScene := preload("res://ui/screens/home.tscn")
const PlaceholderScene := preload("res://ui/screens/placeholder_tab.tscn")
const LeaderboardScene := preload("res://ui/screens/leaderboard_tab.tscn")
const SnapserAuthS := preload("res://net/snapser_auth.gd")
const LeaderboardsClientS := preload("res://net/leaderboards_client.gd")
const ProfileClientS := preload("res://net/profile_client.gd")
const SettingsScene := preload("res://ui/screens/settings_tab.tscn")
const LocalSettingsS := preload("res://ui/local_settings.gd")
const CurrencyBarS := preload("res://ui/shell/currency_bar.gd")
## MbUi control registry (preloaded, not the class_name global, so the headless
## verifier that instances the shell doesn't depend on a full editor scan).
const Reg := preload("res://ui/mcp_ui_reg.gd")

const HOME_INDEX := 2
const LEADERBOARD_INDEX := 1
const SETTINGS_INDEX := 4
const TAB_LABELS := ["Collection", "Leaderboard", "Home", "Guilds", "Settings"]
## Stable screen ids (MbUi), aligned by index with TAB_LABELS / _tabs.
const SCREEN_IDS := ["collection", "leaderboard", "home", "guilds", "settings"]
# GenTexture refs (art/gen_texture.gd): drop-in Texture2D wrappers carrying
# provenance, swappable in the ArtGen dock without touching this binding.
const TAB_ICONS: Array[Texture2D] = [
	preload("res://assets/generated/icons/collections_icon.tres"),
	preload("res://assets/generated/icons/leaderboard_ticon.tres"),
	preload("res://assets/generated/icons/home_icon.tres"),
	preload("res://assets/generated/icons/guilds_icon.tres"),
	preload("res://assets/generated/icons/settings_icon.tres"),
]
# Layout/look knobs are @export so they can be tuned in the Inspector at edit time
# and live in the Remote scene tree while the game runs. Each setter re-applies its
# effect immediately (guarded so it no-ops before the nav is built), so dragging a
# value in the Remote inspector reflows the bar/icons/halo without a restart.

@export_group("Nav Bar")
@export var nav_height: float = 96.0:
	set(value):
		nav_height = value
		if is_node_ready():
			_apply_safe_area()
			_layout_content()

@export_group("Side Tabs")
## Base (unselected) side-tab icon size, in px.
@export var tab_icon_size: int = 60:
	set(value):
		tab_icon_size = value
		if is_node_ready():
			_apply_tab_icon_geometry()
			_select_tab(_current_tab)
## How much the selected side-tab icon grows (1.0 = no growth).
@export var tab_icon_selected_scale: float = 1.65:
	set(value):
		tab_icon_selected_scale = value
		if is_node_ready():
			_select_tab(_current_tab)
## Selected side-tab icon center, px below the bar's top edge (the upward "pop").
@export var tab_icon_pop_y: float = 16.0:
	set(value):
		tab_icon_pop_y = value
		if is_node_ready():
			_select_tab(_current_tab)

@export_group("Home Tab")
## Home icon size when selected, in px.
@export var home_icon_size: int = 96:
	set(value):
		home_icon_size = value
		_apply_home_icon_geometry()
		if is_node_ready():
			_select_tab(_current_tab)
## Home icon center, px above the button's center (the upward "pop" when selected).
@export var home_icon_lift: float = 11.0:
	set(value):
		home_icon_lift = value
		_apply_home_icon_geometry()
		if is_node_ready():
			_select_tab(_current_tab)
## Unselected Home shrinks to this fraction of home_icon_size (~side-tab size at 0.62).
@export var home_icon_base_scale: float = 0.62:
	set(value):
		home_icon_base_scale = value
		if is_node_ready():
			_select_tab(_current_tab)

@export_group("Home Glow")
## Inner halo extent as a multiple of the home icon size.
@export var home_glow_inner_spread: float = 1.25:
	set(value):
		home_glow_inner_spread = value
		_apply_home_icon_geometry()
## Outer halo extent as a multiple of the home icon size.
@export var home_glow_outer_spread: float = 1.6:
	set(value):
		home_glow_outer_spread = value
		_apply_home_icon_geometry()

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
var _home_icon: TextureRect       # center Home overlay icon (size driven by home_icon_size)
var _home_glows: Array = []       # [{node: TextureRect, scale: float}] halo layers behind it
var _auth: MbSnapserAuth
var _leaderboards: Node  # MbLeaderboardsClient (preloaded — fresh class_name globals need a full editor scan)
var _profiles: Node  # MbProfileClient (Settings tab; shares the shell session)
var _currency_bar: CanvasLayer  # top coins/souls/gems band (own layer, like the nav)


func _ready() -> void:
	# Discoverable by the MbUi driver (game/mcp_ui_api.gd) — the shell is the
	# navigation hub: tab selection + match launch route through its mcp_* methods.
	add_to_group("mcp_shell")
	# Apply saved local prefs (audio buses) at boot, before any sound plays.
	LocalSettingsS.apply_audio(LocalSettingsS.load_settings())

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
	# The content host is inset into the gap between the top currency band and the
	# bottom nav bar by _layout_content() (called once the chrome exists below);
	# screens parented here then simply fill that safe region.
	_content.set_anchors_preset(Control.PRESET_TOP_LEFT)

	# Dark app background behind the content (the brand near-black).
	_bg = ColorRect.new()
	_bg.name = "Background"
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
	# The bottom nav is its own MbUi "screen": its tab buttons register as
	# nav.<screen id> (see the tab-config loop below).
	Reg.screen(_nav_bar, "nav")

	# Snapser session + leaderboards client, owned by the shell so they survive
	# match-scene teardown. Sign-in is lazy (first leaderboards call), so offline
	# players incur no network on launch.
	_auth = SnapserAuthS.new()
	_auth.name = "SnapserAuth"
	add_child(_auth)
	_leaderboards = LeaderboardsClientS.new(_auth)
	_leaderboards.name = "LeaderboardsClient"
	add_child(_leaderboards)
	_profiles = ProfileClientS.new(_auth)
	_profiles.name = "ProfileClient"
	add_child(_profiles)

	# Persistent top currency bar (coins/souls/gems), sharing the shell session.
	# (It names itself "CurrencyLayer" in its own _ready.)
	_currency_bar = CurrencyBarS.new(_auth)
	add_child(_currency_bar)

	# Now that both chrome layers exist, inset the content host into the gap
	# between them so every screen lays out clear of the top band and bottom nav.
	_layout_content()

	# Build the five tab screens into the content host (Home + Leaderboard are
	# real; the rest stubs).
	for i in range(5):
		var screen: Control
		if i == HOME_INDEX:
			screen = HomeScene.instantiate()
			screen.play_mode_selected.connect(_on_play_mode_selected)
		elif i == LEADERBOARD_INDEX:
			screen = LeaderboardScene.instantiate()
			screen.setup(_auth, _leaderboards)
		elif i == SETTINGS_INDEX:
			screen = SettingsScene.instantiate()
			screen.setup(_auth, _profiles)
		else:
			screen = PlaceholderScene.instantiate()
			screen.set_title(TAB_LABELS[i])
		# Name each screen host after its tab so the tree stays legible (placeholder
		# instances otherwise collide on their shared scene-root name).
		screen.name = "%sTab" % TAB_LABELS[i]
		# Mark it as an MbUi screen root; its own controls (home launchers, settings
		# widgets, …) register themselves under this id via MbUiReg.
		Reg.screen(screen, SCREEN_IDS[i])
		_content.add_child(screen)
		screen.position = Vector2.ZERO
		screen.size = _content.size
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
		# MbUi: pressing nav.<screen id> selects that tab.
		Reg.adopt(b, SCREEN_IDS[i])
		if i == HOME_INDEX:
			_tab_icons.append(null)
			_tab_labels.append(null)
		else:
			_tab_icons.append(_make_tab_icon(b, TAB_ICONS[i]))
			_tab_labels.append(_make_tab_label(b, TAB_LABELS[i]))

	# The center Home tab: wider share, icon-only (no label), an overlay icon that —
	# like the side tabs — grows to full size and lifts past the bar frame when
	# selected (a Button.icon would be clamped inside the rect), backed by a pulsing
	# additive violet halo that lights up only while selected. _tween_home_icon drives
	# the selected/unselected states; _apply_home_icon_geometry sizes the resting pose.
	var home_btn: Button = _tabs[HOME_INDEX]
	home_btn.size_flags_stretch_ratio = 1.5
	var home_ic := _make_tab_icon(home_btn, TAB_ICONS[HOME_INDEX])
	_home_icon = home_ic
	_add_home_glow(home_btn)
	_apply_home_icon_geometry()

	# Deferred: the icon tween targets read button sizes, which the HBoxContainer
	# only resolves on its (queued) sort — selecting now would bake stale rects.
	_select_tab.call_deferred(HOME_INDEX)
	home_btn.button_pressed = true


func _select_tab(index: int) -> void:
	_current_tab = index
	for i in range(_screens.size()):
		_screens[i].visible = (i == index)
	# Screens that expose refresh() refetch when they become the visible tab.
	var shown: Control = _screens[index] if index < _screens.size() else null
	if shown != null and shown.has_method("refresh"):
		shown.refresh()
	# Selected tab: icon grows and pops up past the bar frame, label shows beneath it.
	# Unselected tabs collapse back to a centered base-size icon. Home follows the same
	# rule (it's icon-only, and its halo lights up only while selected).
	var half := tab_icon_size / 2.0
	for i in range(_tabs.size()):
		var b: Button = _tabs[i]
		var selected := (i == index)
		if i == HOME_INDEX:
			_tween_home_icon(b, selected)
			continue
		var ic: TextureRect = _tab_icons[i]
		var lb: Label = _tab_labels[i]
		lb.visible = selected
		var target_scale := Vector2.ONE * (tab_icon_selected_scale if selected else 1.0)
		var target_mod := Color.WHITE if selected else Color(1, 1, 1, 0.55)
		# Anchors are all-center with a center pivot, so position is the icon's
		# top-left and position + half is its visual center whatever the scale.
		var center_y := tab_icon_pop_y if selected else b.size.y * 0.5
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


## Home icon selection, mirroring the side-tab tween: dim + shrunk to base scale when
## unselected, growing to full home_icon_size (lifted past the bar) + white + halo-lit
## when selected. The icon's center pivot (set in _apply_home_icon_geometry) keeps it
## centered through the scale. The halo is gated via self_modulate so its alpha pulse
## (which owns modulate.a) keeps running underneath.
func _tween_home_icon(b: Button, selected: bool) -> void:
	if not is_instance_valid(_home_icon):
		return
	var hhalf := home_icon_size / 2.0
	var center_y := (b.size.y * 0.5 - home_icon_lift) if selected else b.size.y * 0.5
	var target_pos := Vector2(b.size.x * 0.5 - hhalf, center_y - hhalf)
	var target_scale := Vector2.ONE if selected else Vector2.ONE * home_icon_base_scale
	var target_mod := Color.WHITE if selected else Color(1, 1, 1, 0.55)
	var old: Tween = _home_icon.get_meta("tw") if _home_icon.has_meta("tw") else null
	if old != null:
		old.kill()
	var tw := _home_icon.create_tween().set_parallel(true) \
		.set_trans(Tween.TRANS_BACK if selected else Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(_home_icon, "scale", target_scale, 0.18)
	tw.tween_property(_home_icon, "position", target_pos, 0.18)
	tw.tween_property(_home_icon, "modulate", target_mod, 0.18)
	_home_icon.set_meta("tw", tw)
	for g in _home_glows:
		var node: TextureRect = g["node"]
		if not is_instance_valid(node):
			continue
		node.create_tween().tween_property(node, "self_modulate:a", 1.0 if selected else 0.0, 0.18)


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
	var half := tab_icon_size / 2.0
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
	# Story goes through the world map (which picks the level and pushes the
	# match itself); other modes launch a match directly.
	if str(cfg.get("mode", "")) == "story" and not cfg.has("level_id"):
		UiRouter.push(StoryMapStateS.new(UiRouter.content_root), cfg)
		return
	UiRouter.push(MatchStateS.new(UiRouter.content_root), cfg)


## Called by ShellState on suspend/resume. Hides BOTH the Control subtree and the
## nav CanvasLayer (a CanvasLayer does not inherit a parent Control's visibility).
## On resume, the freshly banked match result (if any) is flushed to the
## leaderboards fire-and-forget — submit_pending gates by mode and a consumed
## flag, and never blocks the router transition.
func set_active(v: bool) -> void:
	visible = v
	_nav_layer.visible = v
	if _currency_bar != null:
		_currency_bar.visible = v
		if v:
			# Post-match fallback: re-read balances on every shell resume (the
			# match_rewards ack already merged the granted deltas optimistically).
			_currency_bar.refresh()
	if v and _leaderboards != null:
		_leaderboards.submit_pending(GameState.last_result)


## Submit the banked result to the leaderboards now. Called by StoryMapState on
## resume — while the player chains story levels the shell stays suspended, and
## a second launch would overwrite GameState.last_result before the shell's own
## set_active(true) flush ever ran. submit_pending's lb_submitted flag keeps
## this exactly-once with the shell-resume path.
func flush_pending_result() -> void:
	if _leaderboards != null:
		_leaderboards.submit_pending(GameState.last_result)


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
	# Two halo layers, [peak alpha, trough alpha] each (inner first, then outer).
	# Their size (the "spread") is exported and applied by _apply_home_icon_geometry;
	# _home_glows preserves this inner→outer order so the spreads map by index.
	for layer in [[0.9, 0.45], [0.5, 0.2]]:
		var glow := TextureRect.new()
		glow.texture = TAB_ICONS[HOME_INDEX]
		glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		glow.modulate = Color(MbStyle.PRIMARY, layer[1])
		btn.add_child(glow)
		glow.anchor_left = 0.5
		glow.anchor_top = 0.5
		glow.anchor_right = 0.5
		glow.anchor_bottom = 0.5
		_home_glows.append({"node": glow})
		var tw := glow.create_tween().set_loops()
		tw.tween_property(glow, "modulate:a", layer[0], 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glow, "modulate:a", layer[1], 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Re-fit the center Home icon and its halo layers to the current home_icon_size /
## home_icon_lift. Called once on build and again from the @export setters, so the
## values can be tuned live (editor or Remote inspector) and update immediately.
## No-ops until the icon exists (the setters fire during property init, pre-_ready).
func _apply_home_icon_geometry() -> void:
	if not is_instance_valid(_home_icon):
		return
	var hh := home_icon_size / 2.0
	_home_icon.offset_left = -hh
	_home_icon.offset_right = hh
	_home_icon.offset_top = -hh - home_icon_lift
	_home_icon.offset_bottom = hh - home_icon_lift
	# Pivot at the icon's center so _tween_home_icon's scale grows/shrinks in place.
	_home_icon.pivot_offset = Vector2(hh, hh)
	# Halo spreads map to the inner→outer order _add_home_glow appended them in.
	var spreads := [home_glow_inner_spread, home_glow_outer_spread]
	for i in range(_home_glows.size()):
		var node: TextureRect = _home_glows[i]["node"]
		if not is_instance_valid(node):
			continue
		var spread: float = spreads[i] if i < spreads.size() else home_glow_outer_spread
		var halo: float = home_icon_size * spread
		node.offset_left = -halo / 2.0
		node.offset_top = -halo / 2.0 - home_icon_lift
		node.offset_right = halo / 2.0
		node.offset_bottom = halo / 2.0 - home_icon_lift


## Re-fit each side-tab icon's base (unselected) rect + center pivot to tab_icon_size,
## so a live size change reflows them before _select_tab re-tweens scale/position.
## Skips HOME_INDEX (null in _tab_icons — the Home icon is sized by home_icon_size).
func _apply_tab_icon_geometry() -> void:
	var half := tab_icon_size / 2.0
	for ic in _tab_icons:
		if not is_instance_valid(ic):
			continue
		ic.offset_left = -half
		ic.offset_top = -half
		ic.offset_right = half
		ic.offset_bottom = half
		ic.pivot_offset = Vector2(half, half)


## Raise the nav bar above the device's bottom safe inset (iOS home indicator /
## Android gesture bar). On desktop/editor the safe area equals the window, so this
## resolves to a no-op (pad = 0).
func _apply_safe_area() -> void:
	var vp := get_viewport_rect().size
	var pad := _bottom_safe_inset()
	_nav_bar.size = Vector2(vp.x, nav_height)
	_nav_bar.position = Vector2(0.0, vp.y - nav_height - pad)


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


## Position the content host in the gap between the top currency band and the
## bottom nav bar, and size every tab screen to fill it. This is the single
## place chrome insets are accounted for — screens never compensate themselves,
## so nothing slides under the band or the nav. Recomputed on viewport resize.
func _layout_content() -> void:
	var vp := get_viewport_rect().size
	var top_chrome := 0.0
	if is_instance_valid(_currency_bar):
		top_chrome = _currency_bar.occupied_height()
	var bottom_chrome := nav_height + _bottom_safe_inset()
	_content.position = Vector2(0.0, top_chrome)
	_content.size = Vector2(vp.x, maxf(0.0, vp.y - top_chrome - bottom_chrome))
	for s in _screens:
		if is_instance_valid(s):
			s.position = Vector2.ZERO
			s.size = _content.size


## Re-fill on viewport resize (aspect=expand changes the logical size per device).
func _on_viewport_resized() -> void:
	var vp := get_viewport_rect().size
	size = vp
	if is_instance_valid(_bg):
		_bg.size = vp
	_apply_safe_area()
	_layout_content()
	# Re-derive icon rects once the nav buttons settle at their new widths.
	_select_tab.call_deferred(_current_tab)


# ── MbUi control surface ──────────────────────────────────────────────────────
# Thin, semantic entry points for the MbUi driver (game/mcp_ui_api.gd). They
# reuse the same paths a real tap takes — the nav radio + _select_tab, and the
# play-mode launcher — so automation drives the shell exactly as a player does.


## Switch to the tab with the given screen id ("home"/"settings"/…). Sets the
## nav radio (keeps the bottom-bar highlight in sync) and runs the tab swap.
## Returns false for an unknown id.
func mcp_select_tab(id: String) -> bool:
	var index := SCREEN_IDS.find(id)
	if index < 0:
		return false
	# Set the radio visual (ButtonGroup unselects the others); _select_tab does the
	# actual screen swap + refresh (button_pressed alone doesn't emit `pressed`).
	(_tabs[index] as Button).button_pressed = true
	_select_tab(index)
	return true


## The screen id of the currently selected tab.
func mcp_current_tab_id() -> String:
	return SCREEN_IDS[_current_tab] if _current_tab < SCREEN_IDS.size() else ""


## Launch a play mode (pushes a MatchState via the router), same path as tapping
## a Home launcher. `cfg` is the match config dict, e.g. {"mode":"story","scenario_id":0}.
func mcp_start_match(cfg: Dictionary) -> void:
	_on_play_mode_selected(cfg)
