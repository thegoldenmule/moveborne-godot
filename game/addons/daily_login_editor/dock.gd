@tool
extends Control

## Bottom-panel dock for authoring the Daily Login Bonus calendar — a thin VIEW
## over DailyLoginService. Left: the day list + the selected day's edit form
## (currency + amount). Right: the Enabled / reset-on-miss toggles, a cycle-length
## spinner, and a copyable provisioning readout (the login_calendar ladder + the
## daily_login quest) for manual Snapser provisioning. One Save writes
## validator/content/daily_login.json.
##
## All data + mutations + validation + the single-target save live in the service
## (headless-testable); the dock holds only control refs + the current selection,
## and rebuilds the list / readout on `changed` (never the edit form, so typing is
## not interrupted).

const Ui := preload("res://addons/editor_tool_kit/editor_tool_ui.gd")
const Pal := preload("res://addons/editor_tool_kit/tool_palette.gd")
const Model := preload("res://ui/screens/daily_login_model.gd")

var service: Node   # DailyLoginService, injected by the EditorToolPlugin base

var _sel_day := 0   # the calendar day currently shown in the edit form (0 = none)

var _tree: Tree
var _form: VBoxContainer
var _enabled_cb: CheckBox
var _reset_cb: CheckBox
var _cycle_spin: SpinBox
var _readout: TextEdit
var _status: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, 240)
	_build_ui()
	if service != null:
		service.changed.connect(_on_service_changed)
	_reload()


## Coarse refresh: day list + provisioning readout. Deliberately does NOT rebuild
## the edit form (typing is never interrupted) — same as the Daily Missions dock.
func _on_service_changed() -> void:
	_refresh_tree()
	_refresh_readout()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", Pal.SEP)
	add_child(root)

	# The two-column content scrolls, so a short bottom panel can still reach the
	# Save/Validate footer below — and the bottom-panel tab strip stays reachable.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 140)
	root.add_child(scroll)

	var split := Ui.split_root()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(split)

	# Left: day list + add/remove + the selection-driven edit form.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", Pal.SEP)
	split.add_child(left)

	left.add_child(Ui.button_bar([
		Ui.button("+ Day", _on_add),
		Ui.button("Remove", _on_remove),
	]))
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(280, 160)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(Ui.section("Calendar days", _tree, true))

	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(Ui.section("Edit day", _form))

	# Right: enabled + reset + cycle length + the provisioning readout.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Pal.SEP)
	split.add_child(right)

	_enabled_cb = CheckBox.new()
	_enabled_cb.text = "Feature enabled (block.enabled)"
	_enabled_cb.toggled.connect(func(on): service.set_enabled(on))
	right.add_child(_enabled_cb)

	_reset_cb = CheckBox.new()
	_reset_cb.text = "Reset on miss (else pause-and-continue)"
	_reset_cb.toggled.connect(func(on): service.set_reset_on_miss(on))
	right.add_child(_reset_cb)

	_cycle_spin = Ui.spin(1, 60, Model.DEFAULT_CYCLE)
	_cycle_spin.value_changed.connect(func(v): service.set_cycle_length(int(v)))
	right.add_child(Ui.form_row("Cycle days", _cycle_spin, 90.0))

	_readout = TextEdit.new()
	_readout.editable = false
	_readout.custom_minimum_size = Vector2(0, 120)
	var readout_box := VBoxContainer.new()
	readout_box.add_child(_readout)
	readout_box.add_child(Ui.button("Copy readout", _on_copy_readout))
	right.add_child(Ui.section("Provisioning (paste into Snapser: ladder + quest)", readout_box))

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
	_sel_day = 0
	_clear_form()
	_enabled_cb.button_pressed = bool(service.block.get("enabled", false))
	_reset_cb.button_pressed = bool(service.block.get("reset_on_miss", false))
	_cycle_spin.set_value_no_signal(int(service.block.get("cycle_length_days", Model.DEFAULT_CYCLE)))
	_on_service_changed()
	_status.text = "Loaded daily_login v%d (%d days)." % [
		int(service.block.get("version", 1)), service.days().size()]


func _refresh_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	# Keep the cycle spinner in sync — set_cycle_length / add / remove move it.
	if _cycle_spin != null:
		_cycle_spin.set_value_no_signal(int(service.block.get("cycle_length_days", Model.DEFAULT_CYCLE)))
	for day in service.days():
		var e: Dictionary = service.get_day(day)
		var it := _tree.create_item(root)
		it.set_text(0, "Day %d — %s" % [day, Model.format_reward(e)])
		it.set_metadata(0, day)
		if day == _sel_day:
			it.select(0)


func _refresh_readout() -> void:
	if _readout != null:
		_readout.text = service.provisioning_readout()


# ── selection + edit form ────────────────────────────────────────────────────--


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	_sel_day = int(it.get_metadata(0))
	_show_form(_sel_day)


func _clear_form() -> void:
	if _form == null:
		return
	for c in _form.get_children():
		c.queue_free()


func _show_form(day: int) -> void:
	_clear_form()
	if day <= 0:
		return
	var e: Dictionary = service.get_day(day)

	var cur_opt := OptionButton.new()
	var sel := 0
	for i in range(Model.CURRENCIES.size()):
		var nm := str(Model.CURRENCIES[i])
		cur_opt.add_item("%s  %s" % [str(Model.CURRENCY_GLYPHS.get(nm, "")), nm])
		cur_opt.set_item_metadata(i, nm)
		if nm == str(e.get("currency", "")):
			sel = i
	cur_opt.select(sel)
	cur_opt.item_selected.connect(func(i): service.set_day_field(day, "currency", str(cur_opt.get_item_metadata(i))))
	_form.add_child(Ui.form_row("Currency", cur_opt))

	var amt := Ui.spin(0, 100000, int(e.get("amount", 0)))
	amt.value_changed.connect(func(v): service.set_day_field(day, "amount", int(v)))
	_form.add_child(Ui.form_row("Amount", amt))


# ── actions ──────────────────────────────────────────────────────────────────--


func _on_add() -> void:
	var r: Dictionary = service.add_day()   # changed → tree/readout rebuild
	_sel_day = int(r.get("day", 0))
	_show_form(_sel_day)
	_status.text = "Added day %d — set its currency + amount on the left." % _sel_day


func _on_remove() -> void:
	if _sel_day <= 0:
		_status.text = "Select a day to remove."
		return
	var day := _sel_day
	_sel_day = 0
	_clear_form()
	service.remove_day(day)   # changed → rebuilds; renumbers the rest
	_status.text = "Removed day %d (remaining days renumbered)." % day


func _on_copy_readout() -> void:
	DisplayServer.clipboard_set(service.provisioning_readout())
	_status.text = "Copied the login_calendar ladder + daily_login quest — provision them in the Snapser console."


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
	_status.text = "Saved daily_login v%d ✓%s" % [
		int(r.get("version", 1)),
		("  — version bumped; publish via the Remote Config tool" if r.get("bumped", false) else "")]
