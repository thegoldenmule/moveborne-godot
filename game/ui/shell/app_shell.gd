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
const QuestsClientS := preload("res://net/quests_client.gd")
const DailySigilS := preload("res://ui/shell/daily_sigil.gd")
const LoginBonusS := preload("res://ui/shell/login_bonus.gd")
## UiDriver control registry (preloaded, not the class_name global, so the headless
## verifier that instances the shell doesn't depend on a full editor scan).
const Reg := preload("res://addons/ui_kit/ui_reg.gd")
## Shared device safe-area math (preloaded, not the class_name global — see safe_area.gd).
const SafeArea := preload("res://ui/safe_area.gd")
## Avatar catalog (for the set_avatar flow's default id).
const AvatarsS := preload("res://ui/avatars.gd")

const HOME_INDEX := 2
const LEADERBOARD_INDEX := 1
const SETTINGS_INDEX := 4
const TAB_LABELS := ["Collection", "Leaderboard", "Home", "Guilds", "Settings"]
## Stable screen ids (UiDriver), aligned by index with TAB_LABELS / _tabs.
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
var _quests: Node  # MbQuestsClient (Daily Missions; shares the shell session)
var _daily: CanvasLayer  # floating Daily Missions sigil + modal (own layers, like the bar)
var _login_bonus: CanvasLayer  # Daily Login Bonus controller + modal (own layer)


func _ready() -> void:
	# Discoverable by the UiDriver (addons/ui_kit/ui_driver.gd) as the UiNavHost —
	# the shell is the navigation hub: tab selection, match launch, flows, and the
	# custom "swipe" step all route through its mcp_* methods (see the section below).
	add_to_group("ui_nav_host")
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
	# The bottom nav is its own UiDriver "screen": its tab buttons register as
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

	# Quests client + the floating Daily Missions sigil/panel (own layers, like the
	# bar), sharing the shell session. The sigil shows only on the Home surface and
	# is driven by _select_tab / set_active below.
	_quests = QuestsClientS.new(_auth)
	_quests.name = "QuestsClient"
	add_child(_quests)
	_daily = DailySigilS.new(_auth, _quests, _currency_bar)
	add_child(_daily)
	# Daily Login Bonus: a once-per-day modal calendar on the Home surface, sharing
	# the same session + clients + reward ceremony as the Daily sigil.
	_login_bonus = LoginBonusS.new(_auth, _quests, _currency_bar)
	add_child(_login_bonus)

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
		# Mark it as an UiDriver screen root; its own controls (home launchers, settings
		# widgets, …) register themselves under this id via UiReg.
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
		# UiDriver: pressing nav.<screen id> selects that tab.
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
	# The Daily sigil floats only over Home; surface it (or hide it) per the tab.
	if is_instance_valid(_daily):
		_daily.set_surface(visible, SCREEN_IDS[index] if index < SCREEN_IDS.size() else "")
	if is_instance_valid(_login_bonus):
		_login_bonus.set_surface(visible, SCREEN_IDS[index] if index < SCREEN_IDS.size() else "")
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
	# The Daily sigil hides with the shell during a match and re-checks its badge on
	# resume (only when resuming onto the Home tab).
	if is_instance_valid(_daily):
		_daily.set_surface(v, mcp_current_tab_id())
	if is_instance_valid(_login_bonus):
		_login_bonus.set_surface(v, mcp_current_tab_id())
	if v and _leaderboards != null:
		_leaderboards.submit_pending(GameState.last_result)
	if v and is_instance_valid(_daily):
		_daily.record_match_result(GameState.last_result)


## Submit the banked result to the leaderboards now. Called by StoryMapState on
## resume — while the player chains story levels the shell stays suspended, and
## a second launch would overwrite GameState.last_result before the shell's own
## set_active(true) flush ever ran. submit_pending's lb_submitted flag keeps
## this exactly-once with the shell-resume path.
func flush_pending_result() -> void:
	if _leaderboards != null:
		_leaderboards.submit_pending(GameState.last_result)
	if is_instance_valid(_daily):
		_daily.record_match_result(GameState.last_result)


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
	return SafeArea.bottom_inset(get_viewport_rect().size.y)


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


# ── UiNavHost surface (the ui_kit UiDriver contract) ─────────────────────────
# Thin, semantic entry points for the generic UiDriver (addons/ui_kit/ui_driver.gd).
# They reuse the same paths a real tap takes — the nav radio + _select_tab, and the
# play-mode launcher — so automation drives the shell exactly as a player does.
# This is where ALL the Moveborne-specific navigation knowledge lives (the tabs,
# the play modes, the named flows, the story-map readiness wait, the swipe step);
# the driver itself is game-agnostic.


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


## Selectable shell tabs (goto(tab)).
func mcp_nav_tabs() -> Array:
	return SCREEN_IDS.duplicate()


## Launchable play modes (goto(mode)). Story opens the world map; Infinite is a
## direct match. PvP is gated/omitted.
func mcp_nav_modes() -> Array:
	return ["story", "infinite"]


## The match config a mode launches with (passed to mcp_start_match).
func mcp_mode_cfg(mode: String) -> Dictionary:
	return {"mode": mode.to_lower()}


## Is the given goto target already the live screen? (Lets the driver no-op a
## redundant navigation instead of tearing down + rebuilding.)
func mcp_target_active(target: String) -> bool:
	var t := target.to_lower()
	if UiRouter.stack_depth() <= 1:
		# On the shell: a tab target is active iff it's the current tab.
		return SCREEN_IDS.has(t) and mcp_current_tab_id() == t
	var top_name := _top_state_name()
	if t == "story" or t == "story_map":
		return top_name == "StoryMapState"
	if top_name == "MatchState":
		return t == str(GameState.next_match.get("mode", ""))
	return false


## Pop any active overlay/match back to the base shell, awaited. A match leaves via
## its own mcp_exit (validator completion + the match_exited pop); the map pops
## directly.
func mcp_exit_to_shell() -> void:
	var tree := get_tree()
	var guard := 0
	while UiRouter.stack_depth() > 1 and guard < 12:
		guard += 1
		while UiRouter.is_busy():
			await tree.process_frame
		var before := UiRouter.stack_depth()
		if _top_state_name() == "MatchState":
			var scene = tree.get_first_node_in_group("mb_match")
			if scene != null and scene.has_method("mcp_exit"):
				await scene.mcp_exit()
			else:
				UiRouter.pop()
		else:
			UiRouter.pop()
		# The pop is async / signal-driven — wait until the stack actually shrinks.
		var waited := 0.0
		while UiRouter.stack_depth() >= before and waited < 6.0:
			await tree.process_frame
			waited += 0.016


## Map a router state name to the driver's route/screen label.
func mcp_route_label(state_name: String) -> String:
	match state_name:
		"MatchState":
			return "match"
		"StoryMapState":
			return "story_map"
		"ShellState":
			return "shell"
	return state_name.trim_suffix("State").to_lower()


## Is gameplay interactable right now? (Drives state().match_ready.)
func mcp_match_ready() -> bool:
	return _mbdebug_ready()


## Post-navigation readiness wait, awaited. Story: the map fetches catalog/progress
## detached after the reveal — wait until Play is enabled (or the offline retry is
## up) so a following press:story_map.play is deterministic. Infinite: wait until
## the board is live.
func mcp_wait_ready(target: String) -> void:
	var t := target.to_lower()
	var tree := get_tree()
	if t == "story" or t == "story_map":
		var ready := func() -> bool:
			for a in UiDriver.actions():
				var id := str(a.get("id", ""))
				if id == "story_map.play" and bool(a.get("enabled", false)):
					return true
				if id == "story_map.retry" and bool(a.get("visible", false)):
					return true
			return false
		var waited := 0.0
		while not ready.call() and waited < 10.0:
			await tree.process_frame
			waited += 0.016
	elif t == "infinite":
		var waited := 0.0
		while not _mbdebug_ready() and waited < 5.0:
			await tree.process_frame
			waited += 0.016


## The named-flow catalog (the discovery surface for flow()/flows()).
func mcp_flows() -> Array:
	return [
		{"name": "start_story", "params": [], "summary": "Open the Story world map."},
		{"name": "story_play_next", "params": [], "summary": "Open the Story map and play the next unlocked level."},
		{"name": "start_infinite", "params": [], "summary": "Launch an Infinite match."},
		{"name": "open_settings", "params": [], "summary": "Switch to the Settings tab."},
		{"name": "open_leaderboard", "params": [], "summary": "Switch to the Leaderboard tab."},
		{"name": "open_daily_missions", "params": [], "summary": "Open the Daily Missions panel (Home sigil)."},
		{"name": "claim_daily", "params": [], "summary": "Open Daily Missions and Claim All claimable rewards."},
		{"name": "exit_match", "params": [], "summary": "Leave the current match, back to the shell."},
		{"name": "sign_out", "params": [], "summary": "Settings -> Sign out."},
		{"name": "set_avatar", "params": ["id"], "summary": "Open Settings and pick avatar <id> (e.g. skull_avatar_05)."},
		{"name": "rename", "params": ["name"], "summary": "Set the display name to <name> and save."},
		{"name": "set_volume", "params": ["music?", "sfx?"], "summary": "Set the music and/or sfx volume sliders."},
	]


## Expand a named flow to run() steps (interpolating params), or null if unknown.
func mcp_expand_flow(name: String, params: Dictionary):
	match name:
		"start_story":
			return ["goto:story"]
		"story_play_next":
			return ["goto:story", "press:story_map.play"]
		"start_infinite":
			return ["goto:infinite"]
		"open_settings":
			return ["goto:settings"]
		"open_leaderboard":
			return ["goto:leaderboard"]
		"open_daily_missions":
			return ["goto:home", "press:home.daily"]
		"claim_daily":
			return ["goto:home", "press:home.daily", "press:missions.claim_all"]
		"exit_match":
			return ["goto:shell"]
		"sign_out":
			return ["goto:settings", "press:settings.sign_out"]
		"set_avatar":
			var id := str(params.get("id", AvatarsS.default_id()))
			return ["goto:settings", "press:settings.avatar", "press:avatar.%s" % id]
		"rename":
			return ["goto:settings",
				{"text": "settings.name", "to": str(params.get("name", ""))},
				"press:settings.save_name"]
		"set_volume":
			var s: Array = ["goto:settings"]
			if params.has("music"):
				s.append({"set": "settings.music", "to": float(params["music"])})
			if params.has("sfx"):
				s.append({"set": "settings.sfx", "to": float(params["sfx"])})
			return s
	return null


## Custom run() step verbs the driver hands off. "swipe:<dir>" drives the board via
## MbDebug (gameplay), so in-match automation runs through the same UiDriver.run().
func mcp_step(verb, arg) -> Dictionary:
	match str(verb):
		"swipe":
			var d := get_node_or_null("/root/MbDebug")
			if d == null:
				return {"ok": false, "reason": "no_mbdebug"}
			return d.swipe(str(arg))
	return {"ok": false, "reason": "unknown_verb", "verb": str(verb)}


func _top_state_name() -> String:
	var t = UiRouter.top()
	return t.state_name() if t != null else ""


func _mbdebug_ready() -> bool:
	var d := get_node_or_null("/root/MbDebug")
	return d != null and d.is_ready()
