extends Control
## The Settings tab: the player profile (Snapser Profiles snap) plus local device
## preferences. The profile zone (avatar + display name + identity) is server-
## backed and hides when there's no Snapser session; the client-settings zone
## (audio / SFX / haptics) and the account zone are always available and never
## touch the network. The shell injects auth + a profile client and calls
## refresh() each time the tab becomes visible; profile load is lazy + cached.

const ProfileClientS := preload("res://net/profile_client.gd")
const AvatarsS := preload("res://ui/avatars.gd")
const LocalSettingsS := preload("res://ui/local_settings.gd")
const ScreenScaffoldS := preload("res://addons/ui_kit/ui_screen_scaffold.gd")
const Reg := preload("res://addons/ui_kit/ui_reg.gd")

const AVATAR_TILE := 64
const AVATAR_PICK := 56
const AVATAR_COLS := 4

var _auth: MbSnapserAuth
var _profiles: Node  # MbProfileClient

var _settings: Dictionary = {}
var _avatar_id := ""
var _loaded_profile := false
var _fetch_id := 0

# Built widgets (UI is built in code, like home/leaderboard screens).
var _col: VBoxContainer
var _profile_box: VBoxContainer
var _avatar_btn: TextureButton
var _avatar_modal: CanvasLayer
var _avatar_grid: GridContainer
var _name_edit: LineEdit
var _profile_status: Label
var _identity: Label
var _offline_note: Label
var _account_name: Label


## Injected by the shell before the scene enters the tree.
func setup(auth: MbSnapserAuth, profiles: Node) -> void:
	_auth = auth
	_profiles = profiles


func _ready() -> void:
	_settings = LocalSettingsS.load_settings()
	_build()


func _build() -> void:
	# Shared padded, max-width frame (same as Leaderboard); a scroll fills it and
	# the content column scrolls within.
	var scaffold := ScreenScaffoldS.new()
	add_child(scaffold)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scaffold.add_child(scroll)

	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 16)
	scroll.add_child(_col)

	_add_title("SETTINGS")
	_build_profile_section()
	_build_client_section()
	_build_account_section()


# --- Profile zone (server-backed) --------------------------------------------


func _build_profile_section() -> void:
	_add_header("Profile")
	_profile_box = VBoxContainer.new()
	_profile_box.add_theme_constant_override("separation", 10)
	_col.add_child(_profile_box)

	# Avatar tile + display-name editor side by side.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_profile_box.add_child(row)

	_avatar_btn = Reg.texture_button("avatar")  # UiDriver: settings.avatar opens the picker
	_avatar_btn.custom_minimum_size = Vector2(AVATAR_TILE, AVATAR_TILE)
	_avatar_btn.ignore_texture_size = true
	_avatar_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_avatar_btn.pressed.connect(_on_avatar_tile_pressed)
	row.add_child(_avatar_btn)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 6)
	row.add_child(name_col)

	name_col.add_child(_dim_label("Display name", 13))
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 8)
	name_col.add_child(edit_row)
	_name_edit = Reg.line_edit("name")  # UiDriver: settings.name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = ProfileClientS.DISPLAY_NAME_MAX
	_name_edit.placeholder_text = "your handle"
	_name_edit.text_submitted.connect(func(_t): _on_save_name())
	edit_row.add_child(_name_edit)
	var save_btn := Reg.button("save_name", null, "Save")  # UiDriver: settings.save_name
	save_btn.pressed.connect(_on_save_name)
	edit_row.add_child(save_btn)

	_profile_status = _dim_label("", 12)
	name_col.add_child(_profile_status)

	_identity = _dim_label("", 12)
	_profile_box.add_child(_identity)

	# Shown instead of the profile box when there's no session.
	_offline_note = _dim_label("Sign-in unavailable — profile hidden.", 14)
	_offline_note.visible = false
	_col.add_child(_offline_note)

	# The avatar picker is a modal overlay (built once, hidden until the tile is
	# tapped) — not inline, so it never reflows the page or adds a scrollbar.
	_build_avatar_modal()


## A centered modal panel of avatar choices on a dimmed full-screen backdrop, on
## its own CanvasLayer above the nav/currency chrome. Tapping the backdrop or a
## choice closes it; it also auto-closes if the Settings tab is hidden.
func _build_avatar_modal() -> void:
	_avatar_modal = CanvasLayer.new()
	_avatar_modal.layer = 20
	_avatar_modal.visible = false
	# Its own UiDriver screen ("avatar"): the picks register under it as avatar.<id>,
	# and the driver reports it as the active modal while it's open.
	Reg.screen(_avatar_modal, "avatar")
	add_child(_avatar_modal)
	visibility_changed.connect(func() -> void:
		if not visible:
			_hide_avatar_modal())

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar_modal.add_child(root)

	# Dimmed backdrop; a tap anywhere off the panel dismisses.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_hide_avatar_modal())
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.BOARD
	sb.border_color = MbStyle.PRIMARY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var h := Label.new()
	h.text = "CHOOSE AVATAR"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", MbStyle.PRIMARY)
	box.add_child(h)

	_avatar_grid = GridContainer.new()
	_avatar_grid.columns = AVATAR_COLS
	_avatar_grid.add_theme_constant_override("h_separation", 10)
	_avatar_grid.add_theme_constant_override("v_separation", 10)
	for id in AvatarsS.IDS:
		_avatar_grid.add_child(_make_avatar_pick(id))
	box.add_child(_avatar_grid)


func _show_avatar_modal() -> void:
	_highlight_picked()
	_avatar_modal.visible = true


func _hide_avatar_modal() -> void:
	if _avatar_modal != null:
		_avatar_modal.visible = false


func _make_avatar_pick(id: String) -> TextureButton:
	var b := Reg.texture_button(id)  # UiDriver: avatar.<id>
	b.custom_minimum_size = Vector2(AVATAR_PICK, AVATAR_PICK)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.texture_normal = AvatarsS.texture(id)
	b.modulate = Color(1, 1, 1, 0.6)
	b.pressed.connect(_on_avatar_pick.bind(id))
	return b


func _on_avatar_tile_pressed() -> void:
	_show_avatar_modal()


func _on_avatar_pick(id: String) -> void:
	_avatar_id = id
	_avatar_btn.texture_normal = AvatarsS.texture(id)
	_hide_avatar_modal()
	_highlight_picked()
	await _persist({ProfileClientS.ATTR_AVATAR: id}, "Avatar saved.")


func _highlight_picked() -> void:
	for i in _avatar_grid.get_child_count():
		var b := _avatar_grid.get_child(i) as TextureButton
		var picked := AvatarsS.IDS[i] == _avatar_id
		b.modulate = Color.WHITE if picked else Color(1, 1, 1, 0.6)


func _on_save_name() -> void:
	var clean := ProfileClientS.sanitize_display_name(_name_edit.text)
	if not ProfileClientS.is_valid_display_name(clean):
		_profile_status.text = "Enter 1–%d characters." % ProfileClientS.DISPLAY_NAME_MAX
		return
	_name_edit.text = clean
	await _persist({ProfileClientS.ATTR_DISPLAY_NAME: clean}, "Saved.")


## PATCH a partial profile, reflecting success into the cache + canonical handle.
func _persist(attrs: Dictionary, ok_msg: String) -> void:
	if _profiles == null:
		return
	_profile_status.text = "Saving…"
	var res: Dictionary = await _profiles.save_profile(attrs)
	if not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		_profile_status.text = "Save failed — %s" % str(res.get("error", "error"))
		return
	_profile_status.text = ok_msg
	# Merge the change into the cached profile + canonical handle.
	GameState.merge_profile(attrs)
	if attrs.has(ProfileClientS.ATTR_DISPLAY_NAME):
		_auth.set_profile_name(str(attrs[ProfileClientS.ATTR_DISPLAY_NAME]))


# --- Client settings zone (local, offline-safe) ------------------------------


func _build_client_section() -> void:
	_add_header("Sound & Haptics")
	# UiDriver ids are the user-facing names (music/sfx); the storage key differs (master).
	_col.add_child(_slider_row("Music", "master", "music"))
	_col.add_child(_slider_row("Effects", "sfx", "sfx"))

	var hap := Reg.check("haptics", null, "Haptics")  # UiDriver: settings.haptics
	hap.button_pressed = bool(_settings.get("haptics", true))
	hap.add_theme_color_override("font_color", MbStyle.TEXT)
	hap.toggled.connect(func(on):
		_settings["haptics"] = on
		LocalSettingsS.save_settings(_settings))
	_col.add_child(hap)


func _slider_row(label: String, key: String, id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lb := _dim_label(label, 14)
	lb.custom_minimum_size = Vector2(80, 0)
	row.add_child(lb)
	var slider := Reg.slider(id)  # UiDriver: settings.<id>
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(_settings.get(key, 1.0))
	slider.value_changed.connect(func(v):
		_settings[key] = v
		LocalSettingsS.save_settings(_settings)
		LocalSettingsS.apply_audio(_settings))
	row.add_child(slider)
	return row


# --- Account zone ------------------------------------------------------------


func _build_account_section() -> void:
	_add_header("Account")
	_account_name = _dim_label("", 14)
	_col.add_child(_account_name)
	var out := Reg.button("sign_out", null, "Sign out")  # UiDriver: settings.sign_out
	out.pressed.connect(_on_sign_out)
	_col.add_child(out)


func _on_sign_out() -> void:
	if _auth != null:
		_auth.sign_out()
	GameState.set_profile({})
	_avatar_id = ""
	_loaded_profile = false
	_show_offline("Signed out.")
	_refresh_account()


# --- Lifecycle: lazy profile load --------------------------------------------


## Called by the shell when the tab becomes visible.
func refresh() -> void:
	_refresh_account()
	if _profiles == null:
		_show_offline("Offline — profile unavailable.")
		return
	if _loaded_profile:
		return
	_reload_profile()


func _refresh_account() -> void:
	if _account_name == null:
		return
	var uname := _auth.username() if _auth != null else ""
	_account_name.text = "Signed in as %s" % uname if uname != "" else "Not signed in."


func _reload_profile() -> void:
	_fetch_id += 1
	var fid := _fetch_id
	_set_profile_visible(true)
	_profile_status.text = "Loading profile…"
	var res: Dictionary = await _profiles.fetch_profile()
	if fid != _fetch_id or not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		_show_offline("Sign-in unavailable — profile hidden.")
		return
	_loaded_profile = true
	var attrs: Dictionary = res.get("profile", {})
	# First-run seed: a profile with no display_name gets one from the anon
	# username so leaderboard handles never regress to blank, then the player
	# can rename. Upsert it so the seed persists.
	if str(attrs.get("display_name", "")) == "":
		attrs["display_name"] = _auth.username()
		await _profiles.save_profile({ProfileClientS.ATTR_DISPLAY_NAME: attrs["display_name"]}, true)
		if fid != _fetch_id or not is_inside_tree():
			return
	_apply_profile(attrs)
	_profile_status.text = ""


func _apply_profile(attrs: Dictionary) -> void:
	GameState.set_profile(attrs)
	var dname := str(attrs.get("display_name", ""))
	_auth.set_profile_name(dname)
	_name_edit.text = dname
	_avatar_id = AvatarsS.resolve_id(str(attrs.get("avatar_id", "")))
	_avatar_btn.texture_normal = AvatarsS.texture(_avatar_id)
	_highlight_picked()
	var uid := _auth.user_id
	_identity.text = "id: %s" % (uid.substr(0, 8) if uid.length() > 8 else uid)


func _set_profile_visible(on: bool) -> void:
	if _profile_box != null:
		_profile_box.visible = on
	if _offline_note != null:
		_offline_note.visible = not on


func _show_offline(msg: String) -> void:
	_set_profile_visible(false)
	if _offline_note != null:
		_offline_note.text = msg


# --- small builders ----------------------------------------------------------


func _add_title(text: String) -> void:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", MbStyle.PRIMARY)
	_col.add_child(t)


func _add_header(text: String) -> void:
	var h := Label.new()
	h.text = text.to_upper()
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", MbStyle.PRIMARY)
	_col.add_child(h)


func _dim_label(text: String, size: int) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", MbStyle.DIM)
	return lb
