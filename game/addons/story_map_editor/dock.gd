@tool
extends Control

## Bottom-panel dock for authoring story-map dot layouts. Pick a world + its
## background texture; each level shows as a numbered dot you can CLICK to select
## (the panel shows which level it is) and DRAG to move. Click empty canvas to
## drop the next unplaced level's dot. Positions are normalized 0..1 against the
## canvas rect — the SAME basis the runtime map (story_map.gd) renders from with
## STRETCH_SCALE. Save writes story_maps.json and rescans the filesystem.

const Catalog := preload("res://story/story_catalog.gd")
const Layout := preload("res://story/story_map_layout.gd")

const CANVAS_SIZE := Vector2(720, 1080)  # 2:3, matching the artgen story-map presets (2× the old size)
const DOT := Vector2(32, 32)

var _catalog: Dictionary = {}
var _layout: Dictionary = {}
var _world_id := ""
var _selected_lid := ""   # the dot the user has selected (shows its level info)
var _drag_lid := ""       # the dot currently being dragged, "" when idle
var _markers: Dictionary = {}  # level_id -> the dot Control on the overlay

var _world_opt: OptionButton
var _tex_field: LineEdit
var _canvas: TextureRect
var _overlay: Control
var _selected_info: Label
var _unplaced: Label
var _status: Label
var _file_dialog: FileDialog
var _rc_status: Label   # Catalog ⇄ Remote Config sync panel


func _ready() -> void:
	custom_minimum_size = Vector2(0, 560)
	_build_ui()
	_reload()


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# Left: the canvas in a scroll view (the 2× texture is taller than the panel).
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	# A fixed-size texture (never stretched by the container) with the dot overlay
	# pinned to it via anchors, so canvas pixels and dot pixels always agree.
	_canvas = TextureRect.new()
	_canvas.custom_minimum_size = CANVAS_SIZE
	_canvas.size = CANVAS_SIZE
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_canvas.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_canvas.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_canvas)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)  # tracks the canvas rect exactly
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP        # empty clicks place dots
	_overlay.gui_input.connect(_on_overlay_input)
	_canvas.add_child(_overlay)

	# Right: controls.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(320, 0)
	right.size_flags_vertical = Control.SIZE_FILL
	root.add_child(right)

	var title := Label.new()
	title.text = "STORY MAP — DOT PLACEMENT"
	right.add_child(title)

	var world_row := HBoxContainer.new()
	right.add_child(world_row)
	var wl := Label.new()
	wl.text = "World:"
	world_row.add_child(wl)
	_world_opt = OptionButton.new()
	_world_opt.item_selected.connect(_on_world_selected)
	world_row.add_child(_world_opt)

	var tex_row := HBoxContainer.new()
	right.add_child(tex_row)
	_tex_field = LineEdit.new()
	_tex_field.placeholder_text = "res://assets/generated/maps/…png"
	_tex_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tex_field.text_submitted.connect(func(t): _set_texture(t))
	tex_row.add_child(_tex_field)
	var pick := Button.new()
	pick.text = "Pick…"
	pick.pressed.connect(_open_texture_dialog)
	tex_row.add_child(pick)

	_selected_info = Label.new()
	_selected_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_info.custom_minimum_size = Vector2(300, 56)
	right.add_child(_selected_info)

	var sel_row := HBoxContainer.new()
	right.add_child(sel_row)
	var remove_sel := Button.new()
	remove_sel.text = "Remove selected"
	remove_sel.pressed.connect(_remove_selected)
	sel_row.add_child(remove_sel)

	_unplaced = Label.new()
	_unplaced.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unplaced.custom_minimum_size = Vector2(300, 0)
	right.add_child(_unplaced)

	var btn_row := HBoxContainer.new()
	right.add_child(btn_row)
	var clear := Button.new()
	clear.text = "Clear world"
	clear.pressed.connect(_clear_world)
	btn_row.add_child(clear)

	var act_row := HBoxContainer.new()
	right.add_child(act_row)
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_reload)
	act_row.add_child(reload)
	var validate := Button.new()
	validate.text = "Validate"
	validate.pressed.connect(_on_validate)
	act_row.add_child(validate)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_on_save)
	act_row.add_child(save)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	right.add_child(_status)

	var help := Label.new()
	help.text = "Click a dot to select it (its level shows above). Drag a dot to move it. Click empty canvas to drop the next unplaced level's dot."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(300, 0)
	right.add_child(help)

	# ── Catalog ⇄ Remote Config (the story catalog, distinct from dot layout) ──
	right.add_child(HSeparator.new())
	var rc_title := Label.new()
	rc_title.text = "STORY CATALOG ⇄ REMOTE CONFIG"
	right.add_child(rc_title)
	var rc_row := HBoxContainer.new()
	right.add_child(rc_row)
	var rc_check := Button.new()
	rc_check.text = "Check sync"
	rc_check.pressed.connect(_check_catalog_sync)
	rc_row.add_child(rc_check)
	var rc_copy := Button.new()
	rc_copy.text = "Copy publish payload"
	rc_copy.pressed.connect(_copy_publish_payload)
	rc_row.add_child(rc_copy)
	_rc_status = Label.new()
	_rc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rc_status.custom_minimum_size = Vector2(300, 0)
	_rc_status.text = "The catalog has no publish API — 'Copy publish payload' then paste into the Snapser console."
	right.add_child(_rc_status)


# ── data ────────────────────────────────────────────────────────────────────


func _reload() -> void:
	_catalog = Catalog.load_baked()
	_layout = Layout.load_baked()
	if not (_layout is Dictionary) or _layout.is_empty():
		_layout = {"version": 1, "maps": {}}
	if not (_layout.get("maps") is Dictionary):
		_layout["maps"] = {}
	_world_opt.clear()
	var worlds := Catalog.ordered_worlds(_catalog)
	for w in worlds:
		_world_opt.add_item("%s — %s" % [str(w.get("id", "")), str(w.get("name", ""))])
	if worlds.is_empty():
		_status.text = "No story_catalog.json found."
		return
	_world_opt.select(0)
	_world_id = str(worlds[0].get("id", ""))
	_load_world()
	_status.text = "Loaded."


func _on_world_selected(idx: int) -> void:
	var worlds := Catalog.ordered_worlds(_catalog)
	if idx < 0 or idx >= worlds.size():
		return
	_world_id = str(worlds[idx].get("id", ""))
	_load_world()


## The map entry for the current world, creating it if absent.
func _world_map() -> Dictionary:
	var maps: Dictionary = _layout["maps"]
	if not (maps.get(_world_id) is Dictionary):
		maps[_world_id] = {"texture": "", "dots": []}
	var m: Dictionary = maps[_world_id]
	if not (m.get("dots") is Array):
		m["dots"] = []
	return m


func _dots() -> Array:
	return _world_map()["dots"]


func _dot_by_id(lid: String) -> Dictionary:
	for d in _dots():
		if str(d.get("level_id", "")) == lid:
			return d
	return {}


func _load_world() -> void:
	_drag_lid = ""
	_selected_lid = ""
	var m := _world_map()
	_tex_field.text = str(m.get("texture", ""))
	_set_texture(_tex_field.text)
	_refresh()


func _set_texture(path: String) -> void:
	_world_map()["texture"] = path
	if path != "" and ResourceLoader.exists(path):
		_canvas.texture = load(path)
	else:
		_canvas.texture = null
	_refresh()


func _open_texture_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_RESOURCES
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.filters = PackedStringArray(["*.png ; PNG", "*.webp ; WebP", "*.jpg ; JPG"])
		_file_dialog.file_selected.connect(func(p):
			_tex_field.text = p
			_set_texture(p))
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


# ── placement + selection + drag ──────────────────────────────────────────────


## Empty-canvas click: drop the next unplaced level's dot there. Clicks on a dot
## are consumed by that dot (see _on_dot_input), so they never reach here.
func _on_overlay_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		_place_next(_norm(e.position))


## Per-dot input: press selects + starts a drag, motion (button held) moves it.
func _on_dot_input(e: InputEvent, lid: String) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_select(lid)
			_drag_lid = lid
		else:
			_drag_lid = ""
	elif e is InputEventMouseMotion and _drag_lid == lid:
		if (e.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_drag_lid = ""
			return
		var d := _dot_by_id(lid)
		if d.is_empty():
			_drag_lid = ""
			return
		var n := _norm(_overlay.get_local_mouse_position())
		d["x"] = snappedf(n.x, 0.001)
		d["y"] = snappedf(n.y, 0.001)
		_place_marker(lid)       # move the existing node — do NOT rebuild mid-drag
		_refresh_info()


## Normalized 0..1 position against the canvas rect.
func _norm(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x / CANVAS_SIZE.x, 0.0, 1.0), clampf(p.y / CANVAS_SIZE.y, 0.0, 1.0))


func _select(lid: String) -> void:
	_selected_lid = lid
	_restyle_markers()
	_refresh_info()


## Place a dot for the first catalog level in this world that has no dot yet.
func _place_next(n: Vector2) -> void:
	var lid := _next_unplaced()
	if lid == "":
		_status.text = "All levels in this world already have a dot. Drag the dots to position them."
		return
	_dots().append({"level_id": lid, "x": snappedf(n.x, 0.001), "y": snappedf(n.y, 0.001)})
	_selected_lid = lid
	_refresh()


func _world_level_ids() -> Array:
	var out: Array = []
	for l in Catalog.ordered_levels(_catalog):
		if str(l.get("world_id", "")) == _world_id:
			out.append(str(l.get("id", "")))
	return out


func _placed_ids() -> Dictionary:
	var seen := {}
	for d in _dots():
		seen[str(d.get("level_id", ""))] = true
	return seen


func _next_unplaced() -> String:
	var placed := _placed_ids()
	for lid in _world_level_ids():
		if not placed.has(lid):
			return lid
	return ""


func _remove_selected() -> void:
	if _selected_lid == "":
		_status.text = "No dot selected."
		return
	var dots := _dots()
	for i in range(dots.size()):
		if str(dots[i].get("level_id", "")) == _selected_lid:
			dots.remove_at(i)
			break
	_selected_lid = ""
	_refresh()


func _clear_world() -> void:
	_world_map()["dots"] = []
	_selected_lid = ""
	_refresh()


# ── render ──────────────────────────────────────────────────────────────────


## Rebuild every dot marker from the data (structural changes only — never call
## this mid-drag; _place_marker moves an existing marker in place).
func _refresh() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	_markers.clear()
	var names := _level_numbers()
	for d in _dots():
		var lid := str(d.get("level_id", ""))
		var m := _make_marker(lid, int(names.get(lid, 0)))
		_overlay.add_child(m)
		_markers[lid] = m
		_place_marker(lid)
	_restyle_markers()
	_refresh_info()
	var unplaced := _world_level_ids().filter(func(id): return not _placed_ids().has(id))
	_unplaced.text = "Unplaced (%d): %s" % [unplaced.size(), ", ".join(unplaced)] if not unplaced.is_empty() \
		else "All %d levels placed." % _world_level_ids().size()


func _level_numbers() -> Dictionary:
	var names := {}
	for l in Catalog.ordered_levels(_catalog):
		names[str(l.get("id", ""))] = int(l.get("order", 0)) + 1
	return names


func _make_marker(lid: String, num: int) -> Control:
	var m := Control.new()
	m.custom_minimum_size = DOT
	m.size = DOT
	m.pivot_offset = DOT * 0.5  # scale the selection pop from the dot's center
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.tooltip_text = "%s — %s" % [lid, str(Catalog.get_level(_catalog, lid).get("name", ""))]
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _dot_style(false))
	m.add_child(panel)
	var lbl := Label.new()
	lbl.text = str(num)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(lbl)
	m.gui_input.connect(_on_dot_input.bind(lid))
	return m


func _dot_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.1, 0.92)
	sb.set_corner_radius_all(int(DOT.x / 2.0))
	sb.set_border_width_all(3 if selected else 2)
	sb.border_color = Color("44ff88") if selected else Color("b400ff")
	return sb


func _place_marker(lid: String) -> void:
	if not _markers.has(lid):
		return
	var d := _dot_by_id(lid)
	var px := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))) * CANVAS_SIZE
	(_markers[lid] as Control).position = px - DOT * 0.5


func _restyle_markers() -> void:
	for lid in _markers:
		var m: Control = _markers[lid]
		var panel := m.get_child(0) as Panel
		if panel != null:
			panel.add_theme_stylebox_override("panel", _dot_style(lid == _selected_lid))
		m.scale = Vector2(1.25, 1.25) if lid == _selected_lid else Vector2.ONE


func _refresh_info() -> void:
	if _selected_lid == "" or _dot_by_id(_selected_lid).is_empty():
		_selected_info.text = "No dot selected.\nClick a dot to select it; drag to move."
		return
	var d := _dot_by_id(_selected_lid)
	var lvl := Catalog.get_level(_catalog, _selected_lid)
	var num := int(lvl.get("order", 0)) + 1
	_selected_info.text = "Selected  #%d  %s\n%s\n(x %.3f, y %.3f)" % [
		num, _selected_lid, str(lvl.get("name", "?")), float(d.get("x", 0.0)), float(d.get("y", 0.0))]


func _on_validate() -> void:
	var problems := Layout.validate(_layout, _catalog)
	if problems.is_empty():
		_status.text = "Valid ✓"
	else:
		_status.text = "Problems:\n- " + "\n- ".join(problems)


func _on_save() -> void:
	var problems := Layout.validate(_layout, _catalog)
	if not problems.is_empty():
		_status.text = "Not saved — fix:\n- " + "\n- ".join(problems)
		return
	var f := FileAccess.open(Layout.BAKED_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "Could not open %s for writing." % Layout.BAKED_PATH
		return
	# sort_keys=false (3rd arg) keeps our stable order — the default TRUE would
	# alphabetize (maps before version, dots before texture) and churn the file.
	f.store_string(JSON.stringify(_normalized_layout(), "  ", false) + "\n")
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_status.text = "Saved %s ✓" % Layout.BAKED_PATH


## A stable, normalized copy of the layout for serialization: integer `version`
## (JSON round-tripping otherwise promotes it to 1.0), and a fixed key order
## (version, maps; per world texture, dots; per dot level_id, x, y) with dot
## coordinates snapped to 0.001 — so saves produce clean, churn-free diffs.
func _normalized_layout() -> Dictionary:
	var maps_in: Dictionary = _layout.get("maps", {})
	var maps_out := {}
	for wid in maps_in:
		var m: Dictionary = maps_in[wid]
		var dots_out: Array = []
		for d in m.get("dots", []):
			dots_out.append({
				"level_id": str(d.get("level_id", "")),
				"x": snappedf(float(d.get("x", 0.0)), 0.001),
				"y": snappedf(float(d.get("y", 0.0)), 0.001),
			})
		maps_out[wid] = {"texture": str(m.get("texture", "")), "dots": dots_out}
	return {"version": int(_layout.get("version", 1)), "maps": maps_out}


# ── Catalog ⇄ Remote Config ──────────────────────────────────────────────────


## Reuse the canonical TS comparator (key-order-insensitive) instead of
## reimplementing it: shell out to `bun tools/story-appconfig.ts verify`, which
## anon-logs in, GETs the live app-config, and deep-compares it to the committed
## catalog. Blocking (a manual button); falls back to a terminal hint if bun
## isn't on PATH.
func _check_catalog_sync() -> void:
	var committed := int(Catalog.load_baked().get("catalog_version", 0))
	_rc_status.text = "Checking live Remote Config (committed v%d)…" % committed
	var script := ProjectSettings.globalize_path("res://").path_join(
		"../validator/src/validator/tools/story-appconfig.ts")
	var out: Array = []
	var code := OS.execute("bun", [script, "verify"], out, true)
	var text := "\n".join(out).strip_edges() if out.size() > 0 else ""
	if code == 0:
		_rc_status.text = "In sync ✓ (committed v%d)\n%s" % [committed, text]
	elif code == -1:
		_rc_status.text = "Could not run bun. In a terminal: `cd validator && bun run tools/story-appconfig.ts verify`"
	else:
		_rc_status.text = "DRIFT or error (exit %d):\n%s" % [code, text]


## Put the exact {"story_catalog": <committed>} JSON on the clipboard for a manual
## paste into the Snapser console App Config tool (Remote Config has no write API).
func _copy_publish_payload() -> void:
	var catalog := Catalog.load_baked()
	if catalog.is_empty():
		_rc_status.text = "No committed catalog found."
		return
	var payload := JSON.stringify({"story_catalog": catalog}, "  ")
	DisplayServer.clipboard_set(payload)
	_rc_status.text = "Copied {story_catalog:…} (v%d) to clipboard — paste into the Snapser console App Config (version v1)." % int(catalog.get("catalog_version", 0))
