@tool
extends Control

## Bottom-panel dock for authoring Daily Missions — a thin VIEW over
## DailyMissionsService. Left: the mission list + the selected mission's edit form
## (title / icon / description / reward, id rename). Right: the Enabled toggle, the
## anchor picker, the 7-day rotation grid (one toggle chip per mission, the anchor
## pinned as a disabled lead chip), and a copyable mission-id readout for manual
## Quest provisioning. One Save writes validator/content/daily_missions.json.
##
## All data + mutations + validation + the single-target save live in the service
## (headless-testable); the dock holds only control refs + the current selection,
## and rebuilds the tree / anchor / grid on `changed` (never the edit form, so
## typing is not interrupted).

const Ui := preload("res://addons/editor_tool_kit/editor_tool_ui.gd")
const Pal := preload("res://addons/editor_tool_kit/tool_palette.gd")
const Model := preload("res://ui/screens/daily_missions_model.gd")

const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

var service: Node   # DailyMissionsService, injected by the EditorToolPlugin base

var _sel_id := ""   # the mission currently shown in the edit form

var _tree: Tree
var _form: VBoxContainer
var _enabled_cb: CheckBox
var _anchor_opt: OptionButton
var _grid: VBoxContainer
var _readout: TextEdit
var _status: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, 520)
	_build_ui()
	if service != null:
		service.changed.connect(_on_service_changed)
	_reload()


## Coarse refresh: tree + anchor picker + rotation grid. Deliberately does NOT
## rebuild the edit form (typing is never interrupted) — same as the Story Map dock.
func _on_service_changed() -> void:
	_refresh_tree()
	_refresh_anchor()
	_refresh_grid()
	_refresh_readout()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", Pal.SEP)
	add_child(root)

	var split := Ui.split_root()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	# Left: mission list + add/remove + the selection-driven edit form.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", Pal.SEP)
	split.add_child(left)

	left.add_child(Ui.button_bar([
		Ui.button("+ Mission", _on_add),
		Ui.button("Remove", _on_remove),
	]))
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(280, 160)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(Ui.section("Missions", _tree, true))

	var form_scroll := ScrollContainer.new()
	form_scroll.custom_minimum_size = Vector2(280, 180)
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(_form)
	left.add_child(Ui.section("Edit mission", form_scroll, true))

	# Right: enabled + anchor + rotation grid + provisioning readout.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Pal.SEP)
	split.add_child(right)

	_enabled_cb = CheckBox.new()
	_enabled_cb.text = "Feature enabled (block.enabled)"
	_enabled_cb.toggled.connect(func(on): service.set_enabled(on))
	right.add_child(_enabled_cb)

	_anchor_opt = OptionButton.new()
	_anchor_opt.item_selected.connect(_on_anchor_selected)
	right.add_child(Ui.section("Anchor (shown first every day)", _anchor_opt))

	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 6)
	right.add_child(Ui.section("Rotation — tap a mission to add/remove it that day", _grid, true))

	_readout = TextEdit.new()
	_readout.editable = false
	_readout.custom_minimum_size = Vector2(0, 80)
	var readout_box := VBoxContainer.new()
	readout_box.add_child(_readout)
	readout_box.add_child(Ui.button("Copy ids", _on_copy_ids))
	right.add_child(Ui.section("Mission ids (provision matching Quests in Snapser)", readout_box))

	split.split_offset = 4096   # start the right pane at its floor; draggable left

	root.add_child(HSeparator.new())
	root.add_child(Ui.button_bar([
		Ui.button("Reload", _reload),
		Ui.button("Validate", _on_validate),
		Ui.button("Save", _on_save),
	]))
	_status = Ui.status_label()
	root.add_child(_status)


# ── data ───────────────────────────────────────────────────────────────────────


func _reload() -> void:
	service.reload()
	_sel_id = ""
	_clear_form()
	_enabled_cb.button_pressed = bool(service.block.get("enabled", false))
	_on_service_changed()
	_status.text = "Loaded daily_missions v%d (%d missions)." % [
		int(service.block.get("version", 1)), service.mission_ids().size()]


func _refresh_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	for id in service.mission_ids():
		var m: Dictionary = service.get_mission(id)
		var it := _tree.create_item(root)
		var anchor: bool = id == str(service.block.get("anchor", ""))
		it.set_text(0, "%s%s — %s" % ["★ " if anchor else "", id, str(m.get("title", ""))])
		it.set_metadata(0, id)
		if id == _sel_id:
			it.select(0)


func _refresh_anchor() -> void:
	if _anchor_opt == null:
		return
	_anchor_opt.clear()
	_anchor_opt.add_item("(none)")
	_anchor_opt.set_item_metadata(0, "")
	var cur := str(service.block.get("anchor", ""))
	for id in service.mission_ids():
		var i := _anchor_opt.item_count
		_anchor_opt.add_item(id)
		_anchor_opt.set_item_metadata(i, id)
		if id == cur:
			_anchor_opt.select(i)


func _refresh_grid() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var ids: Array = service.mission_ids()
	var anchor: String = str(service.block.get("anchor", ""))
	for d in range(7):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = WEEKDAYS[d]
		lbl.custom_minimum_size = Vector2(34, 0)
		row.add_child(lbl)
		var chips := HFlowContainer.new()
		chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(chips)
		if anchor != "":
			var ach := Button.new()
			ach.text = "★ " + anchor
			ach.disabled = true
			ach.tooltip_text = "anchor — shown first every day"
			chips.add_child(ach)
		var present := {}
		for id in service.weekday_ids(d):
			present[str(id)] = true
		for id in ids:
			if id == anchor:
				continue
			var chip := Button.new()
			chip.toggle_mode = true
			chip.text = id
			chip.button_pressed = present.has(id)
			chip.toggled.connect(_on_chip_toggled.bind(d, id))
			chips.add_child(chip)
		_grid.add_child(row)


func _refresh_readout() -> void:
	if _readout != null:
		_readout.text = service.canonical_id_readout()


# ── selection + edit form ────────────────────────────────────────────────────--


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	_sel_id = str(it.get_metadata(0))
	_show_form(_sel_id)


func _clear_form() -> void:
	if _form == null:
		return
	for c in _form.get_children():
		c.queue_free()


func _show_form(id: String) -> void:
	_clear_form()
	if id == "" or service.get_mission(id).is_empty():
		return
	var m: Dictionary = service.get_mission(id)

	var id_e := LineEdit.new()
	id_e.text = id
	id_e.text_submitted.connect(func(t): _rename(id, t))
	_form.add_child(Ui.form_row("Id", id_e))

	var title_e := LineEdit.new()
	title_e.text = str(m.get("title", ""))
	title_e.text_changed.connect(func(t): service.set_mission_field(id, "title", t))
	_form.add_child(Ui.form_row("Title", title_e))

	var icon_opt := OptionButton.new()
	var names := Model.icon_names()
	var sel := 0
	for i in range(names.size()):
		var nm := str(names[i])
		icon_opt.add_item("%s  %s" % [str(Model.ICON_GLYPHS.get(nm, "")), nm])
		icon_opt.set_item_metadata(i, nm)
		if nm == str(m.get("icon", "")):
			sel = i
	icon_opt.select(sel)
	icon_opt.item_selected.connect(func(i): service.set_mission_field(id, "icon", str(icon_opt.get_item_metadata(i))))
	_form.add_child(Ui.form_row("Icon", icon_opt))

	var desc_e := LineEdit.new()
	desc_e.text = str(m.get("desc", ""))
	desc_e.text_changed.connect(func(t): service.set_mission_field(id, "desc", t))
	_form.add_child(Ui.form_row("Desc", desc_e))

	var reward_e := LineEdit.new()
	reward_e.text = str(m.get("reward", ""))
	reward_e.placeholder_text = "e.g. 100 coins"
	reward_e.text_changed.connect(func(t): service.set_mission_field(id, "reward", t))
	_form.add_child(Ui.form_row("Reward", reward_e))


func _rename(old_id: String, raw: String) -> void:
	var r: Dictionary = service.rename_mission(old_id, raw)
	if not r.get("ok", false):
		_status.text = str(r.get("error", ""))
		_show_form(old_id)
		return
	_sel_id = str(r.get("new_id", old_id))
	_show_form(_sel_id)


# ── actions ──────────────────────────────────────────────────────────────────--


func _on_add() -> void:
	var r: Dictionary = service.add_mission()   # changed → tree/anchor/grid rebuild
	_sel_id = str(r.get("id", ""))
	_show_form(_sel_id)
	_status.text = "Added %s — edit it on the left, then add it to weekdays on the right." % _sel_id


func _on_remove() -> void:
	if _sel_id == "":
		_status.text = "Select a mission to remove."
		return
	var id := _sel_id
	_sel_id = ""
	_clear_form()
	service.remove_mission(id)   # changed → rebuilds; cascades out of weekdays + anchor
	_status.text = "Removed %s (and its weekday/anchor references)." % id


func _on_anchor_selected(idx: int) -> void:
	service.set_anchor(str(_anchor_opt.get_item_metadata(idx)))


func _on_chip_toggled(pressed: bool, wd: int, id: String) -> void:
	if pressed:
		service.add_weekday(wd, id)
	else:
		service.remove_weekday(wd, id)


func _on_copy_ids() -> void:
	DisplayServer.clipboard_set(service.canonical_id_readout())
	_status.text = "Copied %d mission ids — provision matching Quests in the Snapser console." % service.mission_ids().size()


func _on_validate() -> void:
	var problems: Array = service.validate()
	if problems.is_empty():
		_status.text = "Valid ✓"
	else:
		_status.text = "Problems:\n- " + "\n- ".join(problems)


func _on_save() -> void:
	var r: Dictionary = service.save()
	if not r.get("ok", false):
		match str(r.get("stage", "")):
			"validate":
				_status.text = "Not saved — fix:\n- " + "\n- ".join(r["problems"])
			_:
				_status.text = str(r.get("error", "Save failed"))
		return
	_status.text = "Saved daily_missions v%d ✓%s" % [
		int(r.get("version", 1)),
		("  — version bumped; publish via the Remote Config tool" if r.get("bumped", false) else "")]
