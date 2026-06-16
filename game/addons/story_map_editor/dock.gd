@tool
extends Control

## Bottom-panel dock for authoring story-map dot layouts. Pick a world + its
## background texture, then click the canvas to drop the next unplaced level's
## dot and drag an existing dot to move it. Positions are normalized 0..1 against
## the canvas rect — the SAME basis the runtime map (story_map.gd) renders from,
## which fills the body rect with STRETCH_SCALE. Save writes story_maps.json and
## rescans the filesystem.

const Catalog := preload("res://story/story_catalog.gd")
const Layout := preload("res://story/story_map_layout.gd")

const CANVAS_SIZE := Vector2(360, 540)  # 2:3, matching the artgen story-map presets
const HIT_RADIUS := 16.0

var _catalog: Dictionary = {}
var _layout: Dictionary = {}
var _world_id := ""
var _dragging := -1  # index into the current world's dots while dragging, else -1

var _world_opt: OptionButton
var _tex_field: LineEdit
var _canvas: TextureRect
var _overlay: Control
var _unplaced: Label
var _status: Label
var _file_dialog: FileDialog


func _ready() -> void:
	custom_minimum_size = Vector2(0, 600)
	_build_ui()
	_reload()


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# Left: the canvas (texture + dot overlay).
	var left := VBoxContainer.new()
	root.add_child(left)
	_canvas = TextureRect.new()
	_canvas.custom_minimum_size = CANVAS_SIZE
	_canvas.size = CANVAS_SIZE
	_canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_canvas.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_canvas)
	_overlay = Control.new()
	_overlay.custom_minimum_size = CANVAS_SIZE
	_overlay.size = CANVAS_SIZE
	_overlay.position = Vector2.ZERO
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_canvas_input)
	_canvas.add_child(_overlay)

	# Right: controls.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(320, 0)
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

	_unplaced = Label.new()
	_unplaced.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unplaced.custom_minimum_size = Vector2(300, 0)
	right.add_child(_unplaced)

	var btn_row := HBoxContainer.new()
	right.add_child(btn_row)
	var undo := Button.new()
	undo.text = "Remove last dot"
	undo.pressed.connect(_remove_last)
	btn_row.add_child(undo)
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
	help.text = "Click empty canvas: drop the next unplaced level's dot. Drag a dot: move it. Positions are normalized 0..1."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(300, 0)
	right.add_child(help)


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


## The dots array for the current world, creating the map entry if absent.
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


func _load_world() -> void:
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


# ── placement ─────────────────────────────────────────────────────────────────


func _on_canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var hit := _dot_at(e.position)
			if hit >= 0:
				_dragging = hit
			else:
				_place_next(_norm(e.position))
		else:
			_dragging = -1
	elif e is InputEventMouseMotion and _dragging >= 0:
		var d: Dictionary = _dots()[_dragging]
		var n := _norm(e.position)
		d["x"] = n.x
		d["y"] = n.y
		_refresh()


## Normalized 0..1 position against the canvas rect.
func _norm(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x / CANVAS_SIZE.x, 0.0, 1.0),
		clampf(p.y / CANVAS_SIZE.y, 0.0, 1.0))


## Index of the dot under a pixel position, or -1.
func _dot_at(p: Vector2) -> int:
	var dots := _dots()
	for i in range(dots.size()):
		var d: Dictionary = dots[i]
		var px := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))) * CANVAS_SIZE
		if px.distance_to(p) <= HIT_RADIUS:
			return i
	return -1


## Place a dot for the first catalog level in this world that has no dot yet.
func _place_next(n: Vector2) -> void:
	var lid := _next_unplaced()
	if lid == "":
		_status.text = "All levels in this world already have a dot."
		return
	_dots().append({"level_id": lid, "x": snappedf(n.x, 0.001), "y": snappedf(n.y, 0.001)})
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


func _remove_last() -> void:
	var dots := _dots()
	if not dots.is_empty():
		dots.remove_at(dots.size() - 1)
		_refresh()


func _clear_world() -> void:
	_world_map()["dots"] = []
	_refresh()


# ── render ──────────────────────────────────────────────────────────────────


func _refresh() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	var names := {}
	for l in Catalog.ordered_levels(_catalog):
		names[str(l.get("id", ""))] = int(l.get("order", 0)) + 1
	for d in _dots():
		var lid := str(d.get("level_id", ""))
		var px := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))) * CANVAS_SIZE
		var marker := Label.new()
		marker.text = str(names.get(lid, "?"))
		marker.add_theme_color_override("font_color", Color.WHITE)
		marker.add_theme_color_override("font_outline_color", Color(0.5, 0.0, 0.7))
		marker.add_theme_constant_override("outline_size", 6)
		marker.position = px - Vector2(8, 10)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(marker)
	var unplaced := _world_level_ids().filter(func(id): return not _placed_ids().has(id))
	_unplaced.text = "Unplaced (%d): %s" % [unplaced.size(), ", ".join(unplaced)] if not unplaced.is_empty() \
		else "All %d levels placed." % _world_level_ids().size()


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
	f.store_string(JSON.stringify(_layout, "  ") + "\n")
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_status.text = "Saved %s ✓" % Layout.BAKED_PATH
