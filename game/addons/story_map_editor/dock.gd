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
const CatalogEdit := preload("res://addons/story_map_editor/catalog_edit.gd")
const Scenarios := preload("res://logic/scenarios.gd")

const CANVAS_SIZE := Vector2(720, 1080)  # 2:3, matching the artgen story-map presets (2× the old size)
const DOT := Vector2(32, 32)

var _catalog: Dictionary = {}
var _layout: Dictionary = {}
var _catalog_dirty := false   # bump catalog_version on the next save when set
var _world_id := ""
var _selected_lid := ""   # the dot the user has selected (shows its level info)
var _arm_lid := ""        # level armed for placement: next empty-canvas click drops THIS dot
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

# Catalog tab
var _cat_tree: Tree
var _cat_form: VBoxContainer   # the selected world/level edit form (rebuilt on selection)
var _cat_sel: Dictionary = {}  # {kind:"world"|"level", world_id, level_id?}
var _scenario_items: Array = []  # [{id:int, label:String}] for the scenario picker


func _ready() -> void:
	custom_minimum_size = Vector2(0, 560)
	_build_ui()
	_reload()


func _build_ui() -> void:
	# A draggable split: the canvas on the left, the tabbed controls on the right.
	# A split keeps the divider where the user puts it, so the right-panel width
	# stays CONSTANT across tab switches (a plain TabContainer otherwise resizes to
	# each tab's content). The right pane has a wide floor so no tab pushes it.
	var root := HSplitContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Left: the canvas in a scroll view (the 2× texture is taller than the panel).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(220, 0)  # the left pane can't be dragged away entirely
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

	# Right: tabbed control region (Catalog / Map dots / Remote Config) + a shared
	# action footer. One "Save all" persists the catalog AND the dot layout.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	# Floor wider than any tab's content min, so switching tabs never re-clamps the
	# divider (constant width). Drag the divider left to widen further.
	right.custom_minimum_size = Vector2(400, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)
	_build_catalog_tab(tabs)
	_build_dots_tab(tabs)
	_build_rc_tab(tabs)

	right.add_child(HSeparator.new())
	var act := HBoxContainer.new()
	right.add_child(act)
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_reload)
	act.add_child(reload)
	var validate := Button.new()
	validate.text = "Validate"
	validate.pressed.connect(_on_validate)
	act.add_child(validate)
	var save := Button.new()
	save.text = "Save all"
	save.pressed.connect(_on_save)
	act.add_child(save)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 0)
	right.add_child(_status)

	# Push the divider fully right so the right pane starts at its floor (400);
	# the user can drag it left to widen. Clamped to the children's min sizes.
	root.split_offset = 4096


## Map-dots tab: world picker, texture, dot select/remove, help. (Placement +
## drag live on the canvas; Save/Validate/Reload are the shared footer.)
func _build_dots_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Map dots"
	tab.add_theme_constant_override("separation", 8)
	tabs.add_child(tab)

	var world_row := HBoxContainer.new()
	tab.add_child(world_row)
	var wl := Label.new()
	wl.text = "World:"
	world_row.add_child(wl)
	_world_opt = OptionButton.new()
	_world_opt.item_selected.connect(_on_world_selected)
	world_row.add_child(_world_opt)

	var tex_row := HBoxContainer.new()
	tab.add_child(tex_row)
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
	_selected_info.custom_minimum_size = Vector2(360, 56)
	tab.add_child(_selected_info)

	var sel_row := HBoxContainer.new()
	tab.add_child(sel_row)
	var remove_sel := Button.new()
	remove_sel.text = "Remove selected dot"
	remove_sel.pressed.connect(_remove_selected)
	sel_row.add_child(remove_sel)
	var clear := Button.new()
	clear.text = "Clear world dots"
	clear.pressed.connect(_clear_world)
	sel_row.add_child(clear)

	_unplaced = Label.new()
	_unplaced.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unplaced.custom_minimum_size = Vector2(360, 0)
	tab.add_child(_unplaced)

	var help := Label.new()
	help.text = "Pick a level in the Catalog tab (or click empty canvas for the next unplaced level) to drop its dot. Click a dot to select it; drag to move."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(360, 0)
	tab.add_child(help)


## Remote Config tab: sync check + publish-payload copy (no write API).
func _build_rc_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Remote Config"
	tab.add_theme_constant_override("separation", 8)
	tabs.add_child(tab)
	var rc_row := HBoxContainer.new()
	tab.add_child(rc_row)
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
	_rc_status.custom_minimum_size = Vector2(360, 0)
	_rc_status.text = "Remote Config has no publish API — 'Copy publish payload' then paste into the Snapser console (app-config v1)."
	tab.add_child(_rc_status)


## Catalog tab: worlds→levels tree + add/remove buttons + the selected entry's
## edit form (rebuilt on selection).
func _build_catalog_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Catalog"
	tab.add_theme_constant_override("separation", 8)
	tabs.add_child(tab)

	var btns := HBoxContainer.new()
	tab.add_child(btns)
	var add_w := Button.new()
	add_w.text = "Add world"
	add_w.pressed.connect(_on_add_world)
	btns.add_child(add_w)
	var add_l := Button.new()
	add_l.text = "Add level"
	add_l.pressed.connect(_on_add_level)
	btns.add_child(add_l)
	var rem := Button.new()
	rem.text = "Remove"
	rem.pressed.connect(_on_remove_cat)
	btns.add_child(rem)

	_cat_tree = Tree.new()
	_cat_tree.hide_root = true
	_cat_tree.custom_minimum_size = Vector2(360, 160)
	_cat_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cat_tree.item_selected.connect(_on_cat_tree_selected)
	tab.add_child(_cat_tree)

	tab.add_child(HSeparator.new())
	var form_scroll := ScrollContainer.new()
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.custom_minimum_size = Vector2(360, 220)
	tab.add_child(form_scroll)
	_cat_form = VBoxContainer.new()
	_cat_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(_cat_form)


# ── data ────────────────────────────────────────────────────────────────────


func _reload() -> void:
	_catalog = Catalog.load_baked()
	_layout = Layout.load_baked()
	if not (_layout is Dictionary) or _layout.is_empty():
		_layout = {"version": 1, "maps": {}}
	if not (_layout.get("maps") is Dictionary):
		_layout["maps"] = {}
	_catalog_dirty = false
	_cat_sel = {}
	_build_scenario_items()
	_refresh_world_opt()
	_refresh_cat_tree()
	_clear_form()
	var worlds := Catalog.ordered_worlds(_catalog)
	if worlds.is_empty():
		_status.text = "No story_catalog.json found."
		return
	_world_id = str(worlds[0].get("id", ""))
	_sync_world_opt()
	_load_world()
	_status.text = "Loaded catalog v%d." % int(_catalog.get("catalog_version", 1))


## Rebuild the dots-tab world dropdown from the catalog (after worlds change),
## keeping the current world selected when it still exists.
func _refresh_world_opt() -> void:
	if _world_opt == null:
		return
	_world_opt.clear()
	for w in Catalog.ordered_worlds(_catalog):
		var i := _world_opt.item_count
		_world_opt.add_item("%s — %s" % [str(w.get("id", "")), str(w.get("name", ""))])
		_world_opt.set_item_metadata(i, str(w.get("id", "")))
	_sync_world_opt()


func _sync_world_opt() -> void:
	if _world_opt == null:
		return
	for i in range(_world_opt.item_count):
		if str(_world_opt.get_item_metadata(i)) == _world_id:
			_world_opt.select(i)
			return


func _build_scenario_items() -> void:
	_scenario_items.clear()
	var ids: Array = Scenarios.SCENARIOS.keys()
	ids.sort()
	for id in ids:
		var sc = Scenarios.get_scenario(int(id))
		var nm := str(sc.get("name", "")) if sc is Dictionary else ""
		_scenario_items.append({"id": int(id), "label": "%d — %s" % [int(id), nm]})


func _on_world_selected(idx: int) -> void:
	var wid := str(_world_opt.get_item_metadata(idx))
	if wid == "":
		return
	_world_id = wid
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


## Place a dot. If a level is ARMED (selected in the Catalog tab) and unplaced in
## this world, place THAT level's dot; otherwise fall back to the next unplaced
## level (the quick "drop them in order" flow).
func _place_next(n: Vector2) -> void:
	var lid := ""
	if _arm_lid != "" and _level_in_world(_arm_lid) and _dot_by_id(_arm_lid).is_empty():
		lid = _arm_lid
	else:
		lid = _next_unplaced()
	if lid == "":
		_status.text = "All levels in this world already have a dot. Drag the dots to position them."
		return
	_dots().append({"level_id": lid, "x": snappedf(n.x, 0.001), "y": snappedf(n.y, 0.001)})
	_arm_lid = ""
	_selected_lid = lid
	_refresh()


func _level_in_world(lid: String) -> bool:
	return _world_level_ids().has(lid)


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
	var problems: Array = Catalog.validate(_catalog) + Layout.validate(_layout, _catalog)
	if problems.is_empty():
		_status.text = "Valid ✓ (catalog + map)"
	else:
		_status.text = "Problems:\n- " + "\n- ".join(problems)


## One Save persists EVERYTHING: the catalog to both the baked (res://) and the
## canonical (validator/content) copies — byte-identical, same serializer — and
## the dot layout. Auto-bumps catalog_version when the catalog changed.
func _on_save() -> void:
	var cat_problems := Catalog.validate(_catalog)
	if not cat_problems.is_empty():
		_status.text = "Catalog invalid — not saved:\n- " + "\n- ".join(cat_problems)
		return
	var layout_problems := Layout.validate(_layout, _catalog)
	if not layout_problems.is_empty():
		_status.text = "Map layout invalid — not saved:\n- " + "\n- ".join(layout_problems)
		return

	var bumped := _catalog_dirty
	var old_v := int(_catalog.get("catalog_version", 1))
	if bumped:
		_catalog["catalog_version"] = old_v + 1
	var catalog_text := CatalogEdit.serialize(_catalog)
	var canonical := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("validator/content/story_catalog.json")
	var layout_text := JSON.stringify(_normalized_layout(), "  ", false) + "\n"
	# Write all three (and short-circuit on the first failure). On ANY failure,
	# roll back the in-memory version bump so a retry recomputes the SAME version
	# (no double-bump) and keep dirty; a partial on-disk write self-heals on the
	# next successful save (baked + canonical get the same bytes again).
	if not (_write_file(Catalog.BAKED_PATH, catalog_text) \
			and _write_file(canonical, catalog_text) \
			and _write_file(Layout.BAKED_PATH, layout_text)):
		_catalog["catalog_version"] = old_v
		return

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_catalog_dirty = false
	_refresh_cat_tree()
	_status.text = "Saved catalog v%d + map ✓ (baked + canonical)%s" % [
		int(_catalog.get("catalog_version", 1)),
		("  — version bumped; publish via the Remote Config tab to reach the deployed validator" if bumped else "")]


func _write_file(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "Could not write %s (err %d)" % [path, FileAccess.get_open_error()]
		return false
	f.store_string(text)
	f.close()
	return true


# ── catalog tab: tree + mutations + form ──────────────────────────────────────


func _mark_dirty() -> void:
	_catalog_dirty = true


func _refresh_cat_tree() -> void:
	if _cat_tree == null:
		return
	_cat_tree.clear()
	var root := _cat_tree.create_item()
	for w in Catalog.ordered_worlds(_catalog):
		var wid := str(w.get("id", ""))
		var wi := _cat_tree.create_item(root)
		wi.set_text(0, "%s — %s" % [wid, str(w.get("name", ""))])
		wi.set_metadata(0, {"kind": "world", "world_id": wid})
		var levels: Array = []
		for l in w.get("levels", []):
			if l is Dictionary:
				levels.append(l)
		levels.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
		for l in levels:
			var li := _cat_tree.create_item(wi)
			li.set_text(0, "#%d  %s — %s" % [int(l.get("order", 0)) + 1, str(l.get("id", "")), str(l.get("name", ""))])
			li.set_metadata(0, {"kind": "level", "world_id": wid, "level_id": str(l.get("id", ""))})


func _on_cat_tree_selected() -> void:
	var item := _cat_tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	_cat_sel = meta
	var wid := str(meta.get("world_id", ""))
	if wid != "" and wid != _world_id:
		_world_id = wid
		_sync_world_opt()
		_load_world()
	if str(meta.get("kind", "")) == "level":
		var lid := str(meta.get("level_id", ""))
		_arm_lid = lid
		if not _dot_by_id(lid).is_empty():
			_select(lid)
		else:
			_status.text = "Armed %s — click the map to place its dot." % lid
		_show_level_form(wid, lid)
	else:
		_arm_lid = ""
		_show_world_form(wid)


func _on_add_world() -> void:
	var w: Dictionary = CatalogEdit.add_world(_catalog)
	_mark_dirty()
	_refresh_world_opt()
	_refresh_cat_tree()
	_status.text = "Added world %s — edit it in the tree." % str(w.get("id", ""))


func _on_add_level() -> void:
	var wid := str(_cat_sel.get("world_id", _world_id))
	if wid == "":
		_status.text = "Select a world (or a level in it) first."
		return
	var l: Dictionary = CatalogEdit.add_level(_catalog, wid)
	if l.is_empty():
		_status.text = "Could not add a level — unknown world %s." % wid
		return
	_mark_dirty()
	_refresh_cat_tree()
	_status.text = "Added level %s to %s — select it, then click the map to place its dot." % [str(l.get("id", "")), wid]


func _on_remove_cat() -> void:
	if _cat_sel.is_empty():
		_status.text = "Select a world or level in the tree to remove."
		return
	if str(_cat_sel.get("kind", "")) == "level":
		var wid := str(_cat_sel.get("world_id", ""))
		var lid := str(_cat_sel.get("level_id", ""))
		CatalogEdit.remove_level(_catalog, wid, lid)
		_remove_dot_for(wid, lid)   # cascade so the layout doesn't keep an orphan dot
		_status.text = "Removed level %s (and its map dot)." % lid
	else:
		var wid := str(_cat_sel.get("world_id", ""))
		var removed: Array = CatalogEdit.remove_world(_catalog, wid)
		if _layout.get("maps") is Dictionary:
			(_layout["maps"] as Dictionary).erase(wid)
		_status.text = "Removed world %s (%d levels + their dots)." % [wid, removed.size()]
	_cat_sel = {}
	_mark_dirty()
	_clear_form()
	_refresh_world_opt()
	_refresh_cat_tree()
	# The active world may have just been removed — re-point it at a surviving
	# world (or none) so _refresh()/_world_map() can't resurrect an orphan entry.
	var worlds := Catalog.ordered_worlds(_catalog)
	var valid := false
	for w in worlds:
		if str(w.get("id", "")) == _world_id:
			valid = true
	if not valid:
		_world_id = str(worlds[0].get("id", "")) if not worlds.is_empty() else ""
		_sync_world_opt()
	if _world_id != "":
		_load_world()
	else:
		_canvas.texture = null
		for c in _overlay.get_children():
			c.queue_free()
		_markers.clear()


# ── catalog tab: the selected world/level edit form ───────────────────────────


func _clear_form() -> void:
	if _cat_form == null:
		return
	for c in _cat_form.get_children():
		c.queue_free()


func _form_row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(78, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_cat_form.add_child(row)


func _spin(minv: float, maxv: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = 1
	s.value = value
	return s


func _show_world_form(wid: String) -> void:
	_clear_form()
	var w: Dictionary = CatalogEdit.get_world(_catalog, wid)
	if w.is_empty():
		return
	var hdr := Label.new()
	hdr.text = "WORLD  %s" % wid   # id is fixed (the dot layout + texture key off it)
	_cat_form.add_child(hdr)
	var name_e := LineEdit.new()
	name_e.text = str(w.get("name", ""))
	name_e.text_changed.connect(func(t):
		CatalogEdit.set_world_field(_catalog, wid, "name", t)
		_mark_dirty()
		_refresh_cat_tree()
		_refresh_world_opt())
	_form_row("Name", name_e)
	var order_s := _spin(0, 999, int(w.get("order", 0)))
	order_s.value_changed.connect(func(v):
		CatalogEdit.set_world_field(_catalog, wid, "order", int(v))
		_mark_dirty()
		_refresh_cat_tree()
		_refresh_world_opt())
	_form_row("Order", order_s)


func _show_level_form(wid: String, lid: String) -> void:
	_clear_form()
	var l: Dictionary = CatalogEdit.get_level(_catalog, wid, lid)
	if l.is_empty():
		return
	var hdr := Label.new()
	hdr.text = "LEVEL  (%s)" % wid
	_cat_form.add_child(hdr)

	var id_e := LineEdit.new()
	id_e.text = lid
	id_e.text_submitted.connect(func(t): _rename_level(wid, lid, t))
	_form_row("Id", id_e)

	var name_e := LineEdit.new()
	name_e.text = str(l.get("name", ""))
	name_e.text_changed.connect(func(t):
		CatalogEdit.set_level_field(_catalog, wid, lid, "name", t)
		_mark_dirty()
		_refresh_cat_tree())
	_form_row("Name", name_e)

	var order_s := _spin(0, 999, int(l.get("order", 0)))
	order_s.value_changed.connect(func(v):
		CatalogEdit.set_level_field(_catalog, wid, lid, "order", int(v))
		_mark_dirty()
		_refresh_cat_tree())
	_form_row("Order", order_s)

	var scen := OptionButton.new()
	var sel_idx := 0
	for i in range(_scenario_items.size()):
		scen.add_item(str(_scenario_items[i].label))
		scen.set_item_metadata(i, int(_scenario_items[i].id))
		if int(_scenario_items[i].id) == int(l.get("scenario_id", 0)):
			sel_idx = i
	scen.select(sel_idx)
	scen.item_selected.connect(func(i):
		CatalogEdit.set_level_field(_catalog, wid, lid, "scenario_id", int(scen.get_item_metadata(i)))
		_mark_dirty())
	_form_row("Scenario", scen)

	var goals_hdr := Label.new()
	goals_hdr.text = "Goals (type · threshold · ⏱)"
	_cat_form.add_child(goals_hdr)
	var goals: Array = l.get("goals", [])
	for gi in range(3):
		_build_goal_row(wid, lid, gi, goals[gi] if gi < goals.size() else {})

	var rew_hdr := Label.new()
	rew_hdr.text = "Rewards (coins · souls · gems)"
	_cat_form.add_child(rew_hdr)
	var rewards = l.get("rewards", {})
	_build_reward_row(wid, lid, "complete", "Complete", rewards.get("complete", {}) if rewards is Dictionary else {})
	var per_star = rewards.get("per_star", []) if rewards is Dictionary else []
	for si in range(3):
		_build_reward_row(wid, lid, "per_star:%d" % si, "★%d" % (si + 1), per_star[si] if si < per_star.size() else {})


func _build_goal_row(wid: String, lid: String, gi: int, goal: Dictionary) -> void:
	var row := HBoxContainer.new()
	var type_o := OptionButton.new()
	type_o.add_item("points")
	type_o.add_item("max_tile")
	type_o.select(1 if str(goal.get("type", "points")) == "max_tile" else 0)
	row.add_child(type_o)
	var thr := SpinBox.new()
	thr.min_value = 1
	thr.max_value = 1000000
	thr.step = 1
	thr.value = int(goal.get("threshold", 100))
	thr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(thr)
	var timed := CheckBox.new()
	var tl = goal.get("time_limit_s", null)
	timed.button_pressed = tl != null
	row.add_child(timed)
	var tlim := SpinBox.new()
	tlim.min_value = 1
	tlim.max_value = 3600
	tlim.step = 1
	tlim.value = int(tl) if tl != null else 60
	tlim.editable = tl != null
	row.add_child(tlim)
	var apply := func():
		tlim.editable = timed.button_pressed
		var g := {
			"type": "max_tile" if type_o.selected == 1 else "points",
			"threshold": int(thr.value),
			"time_limit_s": (int(tlim.value) if timed.button_pressed else null),
		}
		CatalogEdit.set_goal(_catalog, wid, lid, gi, g)
		_mark_dirty()
	type_o.item_selected.connect(func(_i): apply.call())
	thr.value_changed.connect(func(_v): apply.call())
	timed.toggled.connect(func(_p): apply.call())
	tlim.value_changed.connect(func(_v): apply.call())
	_cat_form.add_child(row)


func _build_reward_row(wid: String, lid: String, where: String, label: String, amounts) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(64, 0)
	row.add_child(l)
	var spins := {}
	for cur in ["coins", "souls", "gems"]:
		var s := SpinBox.new()
		s.min_value = 0
		s.max_value = 1000000
		s.step = 1
		s.value = int(amounts.get(cur, 0)) if amounts is Dictionary else 0
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(s)
		spins[cur] = s
	var apply := func():
		var a := {}
		for cur in ["coins", "souls", "gems"]:
			var v := int((spins[cur] as SpinBox).value)
			if v > 0:
				a[cur] = v
		CatalogEdit.set_reward(_catalog, wid, lid, where, a)
		_mark_dirty()
	for cur in spins:
		(spins[cur] as SpinBox).value_changed.connect(func(_v): apply.call())
	_cat_form.add_child(row)


## Rename a level id (globally unique), migrating its map dot's level_id so the
## layout doesn't orphan. Reverts the field on a collision/empty id.
func _rename_level(wid: String, old_id: String, raw: String) -> void:
	var new_id := raw.strip_edges()
	if new_id == old_id:
		return
	if new_id == "" or not CatalogEdit.is_level_id_unique(_catalog, new_id, old_id):
		_status.text = "Level id '%s' is empty or already used — keeping '%s'." % [new_id, old_id]
		_show_level_form(wid, old_id)
		return
	CatalogEdit.set_level_field(_catalog, wid, old_id, "id", new_id)
	for d in _dots_for_world(wid):
		if str(d.get("level_id", "")) == old_id:
			d["level_id"] = new_id
	_mark_dirty()
	_cat_sel = {"kind": "level", "world_id": wid, "level_id": new_id}
	_refresh_cat_tree()
	_refresh()
	_show_level_form(wid, new_id)


func _dots_for_world(wid: String) -> Array:
	var maps = _layout.get("maps", {})
	var m = maps.get(wid, {}) if maps is Dictionary else {}
	return m.get("dots", []) if (m is Dictionary and m.get("dots") is Array) else []


func _remove_dot_for(wid: String, lid: String) -> void:
	var dots := _dots_for_world(wid)
	for i in range(dots.size()):
		if str(dots[i].get("level_id", "")) == lid:
			dots.remove_at(i)
			return


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
