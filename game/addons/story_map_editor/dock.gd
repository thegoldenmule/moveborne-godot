@tool
extends Control

## Bottom-panel dock for authoring story-map dot layouts — now a thin VIEW over
## StoryMapService. Pick a world + its background texture; each level shows as a
## numbered dot you can CLICK to select and DRAG to move. Click empty canvas to
## drop the next unplaced level's dot. Positions are normalized 0..1 against the
## canvas rect — the SAME basis the runtime map (story_map.gd) renders from with
## STRETCH_SCALE.
##
## All data (catalog + layout), mutations, validation, the byte-identical save,
## and the Remote Config helpers live in StoryMapService (headless-testable). The
## dock holds only control refs + interaction state (selection / arm / drag), and
## rebuilds world picker + tree + markers when the service emits `changed`.

const Catalog := preload("res://story/story_catalog.gd")
const Scenarios := preload("res://logic/scenarios.gd")
const Ui := preload("res://addons/editor_tool_kit/editor_tool_ui.gd")
const Pal := preload("res://addons/editor_tool_kit/tool_palette.gd")

const CANVAS_SIZE := Vector2(720, 1080)  # 2:3, matching the artgen story-map presets (2× the old size)
const DOT := Vector2(32, 32)

var service: Node   # StoryMapService, injected by the EditorToolPlugin base

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
	# method callable (not a lambda): auto-disconnects when the dock frees, so a
	# late signal can't fire into a freed view.
	if service != null:
		service.changed.connect(_on_service_changed)
	_reload()


## Coarse refresh driven by the service: world picker + catalog tree + markers.
## Deliberately does NOT rebuild the edit form (so typing in a field is never
## interrupted) and is never emitted mid-drag (move_dot is quiet).
func _on_service_changed() -> void:
	_refresh_world_opt()
	_refresh_cat_tree()
	_refresh()


func _build_ui() -> void:
	# A draggable split: the canvas on the left, the tabbed controls on the right.
	var root := Ui.split_root()  # full-rect HSplitContainer (shared builder)
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
	right.add_theme_constant_override("separation", Pal.SEP)
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
	right.add_child(Ui.button_bar([
		Ui.button("Reload", _reload),
		Ui.button("Validate", _on_validate),
		Ui.button("Save all", _on_save),
	]))

	_status = Ui.status_label()
	right.add_child(_status)

	# Push the divider fully right so the right pane starts at its floor (400);
	# the user can drag it left to widen. Clamped to the children's min sizes.
	root.split_offset = 4096


## Map-dots tab: world picker, texture, dot select/remove, help. (Placement +
## drag live on the canvas; Save/Validate/Reload are the shared footer.)
func _build_dots_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Map dots"
	tab.add_theme_constant_override("separation", Pal.SEP)
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
	_tex_field.placeholder_text = "res://assets/generated/maps/….tres"
	_tex_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tex_field.text_submitted.connect(func(t): _set_texture(t))
	tex_row.add_child(_tex_field)
	tex_row.add_child(Ui.button("Pick…", _open_texture_dialog))

	_selected_info = Label.new()
	_selected_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_info.custom_minimum_size = Vector2(360, 56)
	tab.add_child(_selected_info)

	tab.add_child(Ui.button_bar([
		Ui.button("Remove selected dot", _remove_selected),
		Ui.button("Clear world dots", _clear_world),
	]))

	_unplaced = Ui.status_label()
	tab.add_child(_unplaced)

	var help := Ui.status_label()
	help.text = "Pick a level in the Catalog tab (or click empty canvas for the next unplaced level) to drop its dot. Click a dot to select it; drag to move."
	tab.add_child(help)


## Remote Config tab: sync check + publish-payload copy (no write API).
func _build_rc_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Remote Config"
	tab.add_theme_constant_override("separation", Pal.SEP)
	tabs.add_child(tab)
	tab.add_child(Ui.button_bar([
		Ui.button("Check sync", _check_catalog_sync),
		Ui.button("Copy publish payload", _copy_publish_payload),
	]))
	_rc_status = Ui.status_label()
	_rc_status.text = "Remote Config has no publish API — 'Copy publish payload' then paste into the Snapser console (app-config v1)."
	tab.add_child(_rc_status)


## Catalog tab: worlds→levels tree + add/remove buttons + the selected entry's
## edit form (rebuilt on selection).
func _build_catalog_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Catalog"
	tab.add_theme_constant_override("separation", Pal.SEP)
	tabs.add_child(tab)

	tab.add_child(Ui.button_bar([
		Ui.button("Add world", _on_add_world),
		Ui.button("Add level", _on_add_level),
		Ui.button("Remove", _on_remove_cat),
	]))

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


# ── data / world selection ────────────────────────────────────────────────────


func _reload() -> void:
	service.reload()   # loads catalog+layout, picks the first world
	_cat_sel = {}
	_build_scenario_items()
	_refresh_world_opt()
	_refresh_cat_tree()
	_clear_form()
	var worlds := Catalog.ordered_worlds(service.catalog)
	if worlds.is_empty():
		_status.text = "No story_catalog.json found."
		return
	_sync_world_opt()
	_load_world()
	_status.text = "Loaded catalog v%d." % int(service.catalog.get("catalog_version", 1))


## Rebuild the dots-tab world dropdown from the catalog, keeping the current world
## selected when it still exists.
func _refresh_world_opt() -> void:
	if _world_opt == null:
		return
	_world_opt.clear()
	for w in Catalog.ordered_worlds(service.catalog):
		var i := _world_opt.item_count
		_world_opt.add_item("%s — %s" % [str(w.get("id", "")), str(w.get("name", ""))])
		_world_opt.set_item_metadata(i, str(w.get("id", "")))
	_sync_world_opt()


func _sync_world_opt() -> void:
	if _world_opt == null:
		return
	for i in range(_world_opt.item_count):
		if str(_world_opt.get_item_metadata(i)) == service.world_id:
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
	service.select_world(wid)
	_load_world()


func _load_world() -> void:
	_drag_lid = ""
	_selected_lid = ""
	var tex: String = service.texture_for(service.world_id) if service.world_id != "" else ""
	_tex_field.text = tex
	_apply_canvas_texture(tex)
	_refresh()


func _set_texture(path: String) -> void:
	service.set_texture(service.world_id, path)
	_apply_canvas_texture(path)
	_refresh()


func _apply_canvas_texture(path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		_canvas.texture = load(path)
	else:
		_canvas.texture = null


func _open_texture_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_RESOURCES
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		# Point at the artgen GenTexture slot (.tres), not a raw image — so the
		# map follows artgen permutation swaps (uid-stable).
		_file_dialog.filters = PackedStringArray(["*.tres ; Texture resource"])
		_file_dialog.file_selected.connect(func(p):
			_tex_field.text = p
			_set_texture(p))
		add_child(_file_dialog)
	const MAPS_DIR := "res://assets/generated/maps"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(MAPS_DIR)):
		_file_dialog.current_dir = MAPS_DIR
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
		if service.dot_by_id(service.world_id, lid).is_empty():
			_drag_lid = ""
			return
		var n := _norm(_overlay.get_local_mouse_position())
		service.move_dot(service.world_id, lid, n.x, n.y)   # quiet: no rebuild mid-drag
		_place_marker(lid)       # move the existing node — do NOT rebuild
		_refresh_info()


## Normalized 0..1 position against the canvas rect.
func _norm(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x / CANVAS_SIZE.x, 0.0, 1.0), clampf(p.y / CANVAS_SIZE.y, 0.0, 1.0))


func _select(lid: String) -> void:
	_selected_lid = lid
	_restyle_markers()
	_refresh_info()


## Place a dot. If a level is ARMED (selected in the Catalog tab) and unplaced in
## this world, place THAT level's dot; otherwise the next unplaced level.
func _place_next(n: Vector2) -> void:
	var lid := ""
	if _arm_lid != "" and service.level_in_world(service.world_id, _arm_lid) \
			and service.dot_by_id(service.world_id, _arm_lid).is_empty():
		lid = _arm_lid
	else:
		lid = service.next_unplaced(service.world_id)
	if lid == "":
		_status.text = "All levels in this world already have a dot. Drag the dots to position them."
		return
	service.place_dot(service.world_id, lid, n.x, n.y)   # changed → _refresh renders it
	_arm_lid = ""
	_select(lid)


func _remove_selected() -> void:
	if _selected_lid == "":
		_status.text = "No dot selected."
		return
	var lid := _selected_lid
	_selected_lid = ""
	service.remove_dot(service.world_id, lid)   # changed → _refresh


func _clear_world() -> void:
	_selected_lid = ""
	service.clear_world_dots(service.world_id)   # changed → _refresh


# ── render ──────────────────────────────────────────────────────────────────


## Rebuild every dot marker from the data (structural changes only — never call
## this mid-drag; _place_marker moves an existing marker in place).
func _refresh() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	_markers.clear()
	if service.world_id == "":
		_canvas.texture = null
		_unplaced.text = ""
		_refresh_info()
		return
	var names := _level_numbers()
	for d in service.dots_for_world(service.world_id):
		var lid := str(d.get("level_id", ""))
		var m := _make_marker(lid, int(names.get(lid, 0)))
		_overlay.add_child(m)
		_markers[lid] = m
		_place_marker(lid)
	_restyle_markers()
	_refresh_info()
	var unplaced: Array = service.world_level_ids(service.world_id).filter(
		func(id): return not service.placed_ids(service.world_id).has(id))
	_unplaced.text = "Unplaced (%d): %s" % [unplaced.size(), ", ".join(unplaced)] if not unplaced.is_empty() \
		else "All %d levels placed." % service.world_level_ids(service.world_id).size()


func _level_numbers() -> Dictionary:
	var names := {}
	for l in Catalog.ordered_levels(service.catalog):
		names[str(l.get("id", ""))] = int(l.get("order", 0)) + 1
	return names


func _make_marker(lid: String, num: int) -> Control:
	var m := Control.new()
	m.custom_minimum_size = DOT
	m.size = DOT
	m.pivot_offset = DOT * 0.5  # scale the selection pop from the dot's center
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.tooltip_text = "%s — %s" % [lid, str(Catalog.get_level(service.catalog, lid).get("name", ""))]
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ui.restyle_selected(panel, false, int(DOT.x / 2.0))
	m.add_child(panel)
	var lbl := Label.new()
	lbl.text = str(num)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Pal.EMPHASIS)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(lbl)
	m.gui_input.connect(_on_dot_input.bind(lid))
	return m


func _place_marker(lid: String) -> void:
	if not _markers.has(lid):
		return
	var d: Dictionary = service.dot_by_id(service.world_id, lid)
	var px := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))) * CANVAS_SIZE
	(_markers[lid] as Control).position = px - DOT * 0.5


func _restyle_markers() -> void:
	for lid in _markers:
		var m: Control = _markers[lid]
		var panel := m.get_child(0) as Panel
		if panel != null:
			Ui.restyle_selected(panel, lid == _selected_lid, int(DOT.x / 2.0))
		m.scale = Vector2(1.25, 1.25) if lid == _selected_lid else Vector2.ONE


func _refresh_info() -> void:
	if _selected_lid == "" or service.dot_by_id(service.world_id, _selected_lid).is_empty():
		_selected_info.text = "No dot selected.\nClick a dot to select it; drag to move."
		return
	var d: Dictionary = service.dot_by_id(service.world_id, _selected_lid)
	var lvl := Catalog.get_level(service.catalog, _selected_lid)
	var num := int(lvl.get("order", 0)) + 1
	_selected_info.text = "Selected  #%d  %s\n%s\n(x %.3f, y %.3f)" % [
		num, _selected_lid, str(lvl.get("name", "?")), float(d.get("x", 0.0)), float(d.get("y", 0.0))]


func _on_validate() -> void:
	var problems: Array = service.validate()
	if problems.is_empty():
		_status.text = "Valid ✓ (catalog + map)"
	else:
		_status.text = "Problems:\n- " + "\n- ".join(problems)


## One Save persists EVERYTHING via the service: the catalog to both the baked
## (res://) and canonical (validator/content) copies — byte-identical — and the
## dot layout. Auto-bumps catalog_version when the catalog changed.
func _on_save() -> void:
	var r: Dictionary = service.save()
	if not r.get("ok", false):
		match str(r.get("stage", "")):
			"catalog":
				_status.text = "Catalog invalid — not saved:\n- " + "\n- ".join(r["problems"])
			"layout":
				_status.text = "Map layout invalid — not saved:\n- " + "\n- ".join(r["problems"])
			_:
				_status.text = str(r.get("error", "Save failed"))
		return
	_refresh_cat_tree()
	_status.text = "Saved catalog v%d + map ✓ (baked + canonical)%s" % [
		int(r.get("version", 1)),
		("  — version bumped; publish via the Remote Config tab to reach the deployed validator" if r.get("bumped", false) else "")]


# ── catalog tab: tree + mutations + form ──────────────────────────────────────


func _refresh_cat_tree() -> void:
	if _cat_tree == null:
		return
	_cat_tree.clear()
	var root := _cat_tree.create_item()
	for w in Catalog.ordered_worlds(service.catalog):
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
	if wid != "" and wid != service.world_id:
		service.select_world(wid)
		_sync_world_opt()
		_load_world()
	if str(meta.get("kind", "")) == "level":
		var lid := str(meta.get("level_id", ""))
		_arm_lid = lid
		if not service.dot_by_id(service.world_id, lid).is_empty():
			_select(lid)
		else:
			_status.text = "Armed %s — click the map to place its dot." % lid
		_show_level_form(wid, lid)
	else:
		_arm_lid = ""
		_show_world_form(wid)


func _on_add_world() -> void:
	var w: Dictionary = service.add_world()   # changed → world picker + tree refresh
	_status.text = "Added world %s — edit it in the tree." % str(w.get("id", ""))


func _on_add_level() -> void:
	var wid := str(_cat_sel.get("world_id", service.world_id))
	if wid == "":
		_status.text = "Select a world (or a level in it) first."
		return
	var l: Dictionary = service.add_level(wid)   # adds level + dot near last; changed
	if l.is_empty():
		_status.text = "Could not add a level — unknown world %s." % wid
		return
	var lid := str(l.get("id", ""))
	# Switch the map to this world so the new dot is visible, then select it.
	if wid != service.world_id:
		service.select_world(wid)
		_sync_world_opt()
		_load_world()
	if not service.dot_by_id(service.world_id, lid).is_empty():
		_select(lid)
	_arm_lid = ""
	_status.text = "Added level %s with a dot near the last — drag it to position." % lid


func _on_remove_cat() -> void:
	if _cat_sel.is_empty():
		_status.text = "Select a world or level in the tree to remove."
		return
	if str(_cat_sel.get("kind", "")) == "level":
		var wid := str(_cat_sel.get("world_id", ""))
		var lid := str(_cat_sel.get("level_id", ""))
		service.remove_level(wid, lid)   # cascades the dot; changed
		_status.text = "Removed level %s (and its map dot)." % lid
	else:
		var wid := str(_cat_sel.get("world_id", ""))
		var removed: Array = service.remove_world(wid)   # erases map + re-points world; changed
		_status.text = "Removed world %s (%d levels + their dots)." % [wid, removed.size()]
	_cat_sel = {}
	_clear_form()
	_sync_world_opt()
	# remove_world may have re-pointed the active world (or cleared it: the changed
	# handler already blanked the canvas/markers in that case).
	if service.world_id != "":
		_load_world()


# ── catalog tab: the selected world/level edit form ───────────────────────────


func _clear_form() -> void:
	if _cat_form == null:
		return
	for c in _cat_form.get_children():
		c.queue_free()


func _show_world_form(wid: String) -> void:
	_clear_form()
	var w: Dictionary = service.get_world(wid)
	if w.is_empty():
		return
	var hdr := Label.new()
	hdr.text = "WORLD  %s" % wid   # id is fixed (the dot layout + texture key off it)
	_cat_form.add_child(hdr)
	var name_e := LineEdit.new()
	name_e.text = str(w.get("name", ""))
	name_e.text_changed.connect(func(t): service.set_world_field(wid, "name", t))
	_cat_form.add_child(Ui.form_row("Name", name_e))
	var order_s := Ui.spin(0, 999, int(w.get("order", 0)))
	order_s.value_changed.connect(func(v): service.set_world_field(wid, "order", int(v)))
	_cat_form.add_child(Ui.form_row("Order", order_s))


func _show_level_form(wid: String, lid: String) -> void:
	_clear_form()
	var l: Dictionary = service.get_level(wid, lid)
	if l.is_empty():
		return
	var hdr := Label.new()
	hdr.text = "LEVEL  (%s)" % wid
	_cat_form.add_child(hdr)

	var id_e := LineEdit.new()
	id_e.text = lid
	id_e.text_submitted.connect(func(t): _rename_level(wid, lid, t))
	_cat_form.add_child(Ui.form_row("Id", id_e))

	var name_e := LineEdit.new()
	name_e.text = str(l.get("name", ""))
	name_e.text_changed.connect(func(t): service.set_level_field(wid, lid, "name", t))
	_cat_form.add_child(Ui.form_row("Name", name_e))

	var order_s := Ui.spin(0, 999, int(l.get("order", 0)))
	order_s.value_changed.connect(func(v): service.set_level_field(wid, lid, "order", int(v)))
	_cat_form.add_child(Ui.form_row("Order", order_s))

	var scen := OptionButton.new()
	var sel_idx := 0
	for i in range(_scenario_items.size()):
		scen.add_item(str(_scenario_items[i].label))
		scen.set_item_metadata(i, int(_scenario_items[i].id))
		if int(_scenario_items[i].id) == int(l.get("scenario_id", 0)):
			sel_idx = i
	scen.select(sel_idx)
	scen.item_selected.connect(func(i):
		service.set_level_field(wid, lid, "scenario_id", int(scen.get_item_metadata(i))))
	_cat_form.add_child(Ui.form_row("Scenario", scen))

	# Goals + Rewards each read as a framed group (Ui.section) rather than a header
	# label over a loose run of rows — the rows are built into the section body.
	var goals_body := VBoxContainer.new()
	var goals: Array = l.get("goals", [])
	for gi in range(3):
		_build_goal_row(wid, lid, gi, goals[gi] if gi < goals.size() else {}, goals_body)
	_cat_form.add_child(Ui.section("Goals (type · threshold · ⏱)", goals_body))

	var rew_body := VBoxContainer.new()
	var rewards = l.get("rewards", {})
	_build_reward_row(wid, lid, "complete", "Complete", rewards.get("complete", {}) if rewards is Dictionary else {}, rew_body)
	var per_star = rewards.get("per_star", []) if rewards is Dictionary else []
	for si in range(3):
		_build_reward_row(wid, lid, "per_star:%d" % si, "★%d" % (si + 1), per_star[si] if si < per_star.size() else {}, rew_body)
	_cat_form.add_child(Ui.section("Rewards (coins · souls · gems)", rew_body))


func _build_goal_row(wid: String, lid: String, gi: int, goal: Dictionary, target: Container) -> void:
	var row := HBoxContainer.new()
	var type_o := OptionButton.new()
	type_o.add_item("points")
	type_o.add_item("max_tile")
	type_o.select(1 if str(goal.get("type", "points")) == "max_tile" else 0)
	row.add_child(type_o)
	var thr := Ui.spin(1, 1000000, int(goal.get("threshold", 100)), 1.0, true)
	row.add_child(thr)
	var timed := CheckBox.new()
	var tl = goal.get("time_limit_s", null)
	timed.button_pressed = tl != null
	row.add_child(timed)
	var tlim := Ui.spin(1, 3600, int(tl) if tl != null else 60)
	tlim.editable = tl != null
	row.add_child(tlim)
	var apply := func():
		tlim.editable = timed.button_pressed
		var g := {
			"type": "max_tile" if type_o.selected == 1 else "points",
			"threshold": int(thr.value),
			"time_limit_s": (int(tlim.value) if timed.button_pressed else null),
		}
		service.set_goal(wid, lid, gi, g)
	type_o.item_selected.connect(func(_i): apply.call())
	thr.value_changed.connect(func(_v): apply.call())
	timed.toggled.connect(func(_p): apply.call())
	tlim.value_changed.connect(func(_v): apply.call())
	target.add_child(row)


func _build_reward_row(wid: String, lid: String, where: String, label: String, amounts, target: Container) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(64, 0)
	row.add_child(l)
	var spins := {}
	for cur in ["coins", "souls", "gems"]:
		var s := Ui.spin(0, 1000000, int(amounts.get(cur, 0)) if amounts is Dictionary else 0, 1.0, true)
		row.add_child(s)
		spins[cur] = s
	var apply := func():
		var a := {}
		for cur in ["coins", "souls", "gems"]:
			var v := int((spins[cur] as SpinBox).value)
			if v > 0:
				a[cur] = v
		service.set_reward(wid, lid, where, a)
	for cur in spins:
		(spins[cur] as SpinBox).value_changed.connect(func(_v): apply.call())
	target.add_child(row)


## Rename a level id (globally unique), migrating its map dot via the service.
## Reverts the field (restores the form) on a collision/empty id.
func _rename_level(wid: String, old_id: String, raw: String) -> void:
	var r: Dictionary = service.rename_level(wid, old_id, raw)
	if not r.get("ok", false):
		_status.text = str(r.get("error", ""))
		_show_level_form(wid, old_id)
		return
	var new_id := str(r.get("new_id", old_id))
	if new_id == old_id:
		return
	_cat_sel = {"kind": "level", "world_id": wid, "level_id": new_id}
	_show_level_form(wid, new_id)


# ── Catalog ⇄ Remote Config ──────────────────────────────────────────────────


## Shell out (via the service) to the canonical TS comparator and report drift.
func _check_catalog_sync() -> void:
	_rc_status.text = "Checking live Remote Config (committed v%d)…" % int(Catalog.load_baked().get("catalog_version", 0))
	var r: Dictionary = service.check_catalog_sync()
	if int(r.get("code", -1)) == 0:
		_rc_status.text = "In sync ✓ (committed v%d)\n%s" % [int(r.get("committed", 0)), str(r.get("text", ""))]
	elif int(r.get("code", -1)) == -1:
		_rc_status.text = "Could not run bun. In a terminal: `cd validator && bun run tools/story-appconfig.ts verify`"
	else:
		_rc_status.text = "DRIFT or error (exit %d):\n%s" % [int(r.get("code", 0)), str(r.get("text", ""))]


## Copy the {"story_catalog": <committed>} JSON to the clipboard (via the service)
## for a manual paste into the Snapser console App Config.
func _copy_publish_payload() -> void:
	var r: Dictionary = service.copy_publish_payload()
	if not r.get("ok", false):
		_rc_status.text = "No committed catalog found."
		return
	_rc_status.text = "Copied {story_catalog:…} (v%d) to clipboard — paste into the Snapser console App Config (version v1)." % int(r.get("version", 0))
