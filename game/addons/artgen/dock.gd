@tool
extends Control

## ArtGen bottom-panel dock: compose | gallery | detail, plus a settings popup.
## Pure-code UI (no .tscn) — everything binds to the UI-free service, and the
## service's signals keep the gallery live when the MCP bridge drives work.

var service: Node

var _preset_option: OptionButton
var _subject_edit: LineEdit
var _n_spin: SpinBox
var _advanced_toggle: CheckButton
var _advanced_box: VBoxContainer
var _prompt_override: TextEdit
var _model_option: OptionButton
var _model_note: Label
var _style_id_edit: LineEdit
var _parent_label: Label
var _generate_btn: Button
var _status_label: Label

var _search_edit: LineEdit
var _filter_preset: OptionButton
var _filter_state: OptionButton
var _gallery_grid: GridContainer

var _detail_box: VBoxContainer
var _preview_panel: PanelContainer
var _preview_rect: TextureRect
var _checker_toggle: CheckButton
var _meta_label: RichTextLabel
var _category_option: OptionButton
var _name_edit: LineEdit
var _save_btn: Button
var _iterate_btn: Button
var _more_btn: Button
var _discard_btn: Button

var _settings: AcceptDialog
var _key_edit: LineEdit
var _key_status: Label
var _styles_list: ItemList
var _manifest_label: Label

var _selected_id := ""
var _parent_id := ""
var _checker_tex: Texture2D


func _ready() -> void:
	custom_minimum_size.y = 340
	_checker_tex = _make_checkerboard()
	_build_ui()
	if service != null:
		# method callables (not lambdas): they auto-disconnect when the dock is
		# freed, so a late signal from an in-flight generation can't call into
		# a freed control after the plugin is disabled
		service.history_changed.connect(_refresh_gallery)
		service.balance_changed.connect(_on_balance_changed)
		service.generation_started.connect(_on_generation_started)
		service.generation_completed.connect(_on_generation_completed)
		service.generation_failed.connect(_on_generation_failed)
		_populate_presets()
		_populate_models()
		_refresh_gallery()
		_refresh_status()


func _on_balance_changed(_credits: int) -> void:
	_refresh_status()


func _on_generation_started(_info: Dictionary) -> void:
	_refresh_status()


func _on_generation_completed(_records: Array) -> void:
	_refresh_status()


func _on_generation_failed(error: String) -> void:
	_status_label.text = "error: " + error.left(120)


# -- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	split.add_child(_build_compose())

	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	right.add_child(_build_gallery())
	right.add_child(_build_detail())

	_build_settings()


func _build_compose() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 300

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Compose"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var gear := Button.new()
	gear.text = "Settings"
	gear.pressed.connect(_open_settings)
	title_row.add_child(gear)
	box.add_child(title_row)

	_preset_option = OptionButton.new()
	box.add_child(_label_wrap("Preset", _preset_option))

	_subject_edit = LineEdit.new()
	_subject_edit.placeholder_text = "e.g. leaderboard trophy"
	box.add_child(_label_wrap("Subject", _subject_edit))

	_n_spin = SpinBox.new()
	_n_spin.min_value = 1
	_n_spin.max_value = 6
	_n_spin.value = 2
	box.add_child(_label_wrap("Variations", _n_spin))

	_advanced_toggle = CheckButton.new()
	_advanced_toggle.text = "Advanced"
	_advanced_toggle.toggled.connect(func(on: bool) -> void: _advanced_box.visible = on)
	box.add_child(_advanced_toggle)

	_advanced_box = VBoxContainer.new()
	_advanced_box.visible = false
	_prompt_override = TextEdit.new()
	_prompt_override.custom_minimum_size.y = 60
	_prompt_override.placeholder_text = "full prompt override (blank = preset template)"
	_advanced_box.add_child(_label_wrap("Prompt", _prompt_override))
	_model_option = OptionButton.new()
	_model_option.add_item("preset")  # real kinds come from config via _populate_models
	_model_option.item_selected.connect(func(_i: int) -> void: _update_model_note())
	_advanced_box.add_child(_label_wrap("Model", _model_option))
	_model_note = Label.new()
	_model_note.visible = false
	_advanced_box.add_child(_model_note)
	_style_id_edit = LineEdit.new()
	_style_id_edit.placeholder_text = "style_id override / 'none'"
	_advanced_box.add_child(_label_wrap("Style id", _style_id_edit))
	_parent_label = Label.new()
	_parent_label.text = ""
	_advanced_box.add_child(_parent_label)
	box.add_child(_advanced_box)

	_generate_btn = Button.new()
	_generate_btn.text = "Generate"
	_generate_btn.pressed.connect(_on_generate)
	box.add_child(_generate_btn)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = ""
	box.add_child(_status_label)
	return box


func _build_gallery() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = 320

	var filters := HBoxContainer.new()
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "search"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t: String) -> void: _refresh_gallery())
	filters.add_child(_search_edit)
	_filter_preset = OptionButton.new()
	_filter_preset.add_item("all presets")
	_filter_preset.item_selected.connect(func(_i: int) -> void: _refresh_gallery())
	filters.add_child(_filter_preset)
	_filter_state = OptionButton.new()
	for state in ["all", "generated", "saved", "discarded", "error"]:
		_filter_state.add_item(state)
	_filter_state.item_selected.connect(func(_i: int) -> void: _refresh_gallery())
	filters.add_child(_filter_state)
	box.add_child(filters)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gallery_grid = GridContainer.new()
	_gallery_grid.columns = 4
	_gallery_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gallery_grid)
	box.add_child(scroll)
	return box


func _build_detail() -> Control:
	_detail_box = VBoxContainer.new()
	_detail_box.custom_minimum_size.x = 320

	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(256, 256)
	_preview_rect = TextureRect.new()
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_panel.add_child(_preview_rect)
	_detail_box.add_child(_preview_panel)

	_checker_toggle = CheckButton.new()
	_checker_toggle.text = "Checkerboard (transparency)"
	_checker_toggle.toggled.connect(func(_on: bool) -> void: _refresh_detail())
	_detail_box.add_child(_checker_toggle)

	_meta_label = RichTextLabel.new()
	_meta_label.fit_content = true
	_meta_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_meta_label.selection_enabled = true
	_detail_box.add_child(_meta_label)

	var save_row := HBoxContainer.new()
	_category_option = OptionButton.new()
	save_row.add_child(_category_option)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "asset name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_edit)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save)
	save_row.add_child(_save_btn)
	_detail_box.add_child(save_row)

	var action_row := HBoxContainer.new()
	_iterate_btn = Button.new()
	_iterate_btn.text = "Iterate"
	_iterate_btn.pressed.connect(_on_iterate)
	action_row.add_child(_iterate_btn)
	_more_btn = Button.new()
	_more_btn.text = "More variations"
	_more_btn.pressed.connect(_on_more_variations)
	action_row.add_child(_more_btn)
	_discard_btn = Button.new()
	_discard_btn.text = "Discard"
	_discard_btn.pressed.connect(_on_discard)
	action_row.add_child(_discard_btn)
	_detail_box.add_child(action_row)

	_set_detail_enabled(false)
	return _detail_box


func _build_settings() -> void:
	_settings = AcceptDialog.new()
	_settings.title = "ArtGen settings"
	_settings.min_size = Vector2i(520, 420)
	var box := VBoxContainer.new()

	_key_edit = LineEdit.new()
	_key_edit.secret = true
	_key_edit.placeholder_text = "Recraft API key (stored in gitignored editor metadata)"
	box.add_child(_label_wrap("API key", _key_edit))
	var key_row := HBoxContainer.new()
	var validate := Button.new()
	validate.text = "Save && validate"
	validate.pressed.connect(_on_validate_key)
	key_row.add_child(validate)
	_key_status = Label.new()
	key_row.add_child(_key_status)
	box.add_child(key_row)

	var styles_title := Label.new()
	styles_title.text = "Custom styles (account)"
	box.add_child(styles_title)
	_styles_list = ItemList.new()
	_styles_list.custom_minimum_size.y = 120
	box.add_child(_styles_list)
	var refresh_styles := Button.new()
	refresh_styles.text = "Refresh styles"
	refresh_styles.pressed.connect(_on_refresh_styles)
	box.add_child(refresh_styles)

	var manifest_btn := Button.new()
	manifest_btn.text = "Check ai_manifest invariant"
	manifest_btn.pressed.connect(_on_check_manifest)
	box.add_child(manifest_btn)
	_manifest_label = Label.new()
	_manifest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_manifest_label)

	_settings.add_child(box)
	add_child(_settings)


# -- Actions ------------------------------------------------------------------

func _on_generate() -> void:
	var opts := {
		"preset": _preset_option.get_item_text(_preset_option.selected),
		"subject": _subject_edit.text,
		"n": int(_n_spin.value),
	}
	if not _prompt_override.text.strip_edges().is_empty():
		opts["prompt"] = _prompt_override.text.strip_edges()
	if _model_option.selected > 0:
		opts["model"] = _model_option.get_item_text(_model_option.selected)
	if not _style_id_edit.text.strip_edges().is_empty():
		opts["style_id"] = _style_id_edit.text.strip_edges()
	if not _parent_id.is_empty():
		opts["parent_id"] = _parent_id

	_generate_btn.disabled = true
	_status_label.text = "generating…"
	var result: Dictionary = await service.generate(opts)
	_generate_btn.disabled = false
	if result.get("ok", false):
		_parent_id = ""
		_parent_label.text = ""
		var generations: Array = result["generations"]
		if not generations.is_empty():
			_select(str(generations[0]["id"]))
	_refresh_status()
	if not result.get("ok", false):
		# after _refresh_status: pre-flight refusals (e.g. explicit style on
		# v4.x) never emit generation_failed, and even emitted errors would be
		# clobbered by the status rebuild above
		_status_label.text = "error: " + str(result.get("error", "")).left(120)


func _on_save() -> void:
	if _selected_id.is_empty():
		return
	_save_btn.disabled = true
	var result: Dictionary = await service.save_generation(
		_selected_id, _category_option.get_item_text(_category_option.selected),
		_name_edit.text.strip_edges())
	_save_btn.disabled = false
	_status_label.text = ("saved → " + str(result.get("dest"))) if result.get("ok", false) \
			else "save failed: " + str(result.get("error"))
	_refresh_detail()


func _on_iterate() -> void:
	if _selected_id.is_empty():
		return
	var rec: Dictionary = service.get_generation(_selected_id)
	_parent_id = _selected_id
	_parent_label.text = "iterating on " + _selected_id
	_advanced_toggle.button_pressed = true
	_advanced_box.visible = true
	_prompt_override.text = str(rec.get("prompt", ""))
	_subject_edit.text = str(rec.get("subject", ""))
	for i in _preset_option.item_count:
		if _preset_option.get_item_text(i) == str(rec.get("preset", "")):
			_preset_option.selected = i


func _on_more_variations() -> void:
	if _selected_id.is_empty():
		return
	var rec: Dictionary = service.get_generation(_selected_id)
	var opts := {
		"preset": rec.get("preset"), "subject": rec.get("subject"),
		"prompt": rec.get("prompt"), "n": int(_n_spin.value),
		"parent_id": _selected_id,
	}
	_status_label.text = "generating…"
	await service.generate(opts)
	_refresh_status()


func _on_discard() -> void:
	if _selected_id.is_empty():
		return
	service.discard_generation(_selected_id)
	_refresh_detail()


func _open_settings() -> void:
	service.reload_config()  # pick up external presets.json/config.json edits
	_populate_presets()
	_populate_models()
	_key_edit.text = ""
	_key_status.text = "key configured" if service.status()["api_key_configured"] else "no key"
	_settings.popup_centered()
	_on_refresh_styles()


func _on_validate_key() -> void:
	if not _key_edit.text.strip_edges().is_empty():
		service.set_api_key(_key_edit.text.strip_edges())
	_key_status.text = "validating…"
	var resp: Dictionary = await service.client.me()
	if resp.get("ok", false):
		_key_status.text = "valid — %s credits (%s)" % [
			resp["data"].get("credits"), resp["data"].get("email")]
		service._refresh_balance()
	else:
		_key_status.text = "invalid: " + str(resp.get("error")).left(80)


func _on_refresh_styles() -> void:
	_styles_list.clear()
	var resp: Dictionary = await service.client.list_styles()
	if not resp.get("ok", false):
		_styles_list.add_item("error: " + str(resp.get("error")).left(60))
		return
	for style in resp["data"].get("styles", []):
		_styles_list.add_item("%s  (%s, %s)" % [
			style.get("id"), style.get("style"), str(style.get("creation_time")).left(10)])


func _on_check_manifest() -> void:
	var report: Dictionary = service.check_manifest()
	var issues: Array = report["issues"]
	_manifest_label.text = "manifest OK — no issues" if issues.is_empty() \
			else "\n".join(issues)


# -- Refresh ------------------------------------------------------------------

func _populate_presets() -> void:
	_preset_option.clear()
	_filter_preset.clear()
	_filter_preset.add_item("all presets")
	for preset_name in service.presets:
		_preset_option.add_item(preset_name)
		_filter_preset.add_item(preset_name)
	_category_option.clear()
	for cat in service.SAVE_CATEGORIES:
		_category_option.add_item(cat)


## Model kinds come from config.json's models map (config order, v3 kinds
## first), so new kinds reach the dropdown without touching the dock.
func _populate_models() -> void:
	var current := _model_option.get_item_text(_model_option.selected) \
			if _model_option.selected >= 0 else "preset"
	_model_option.clear()
	_model_option.add_item("preset")
	for kind in service.config.get("models", {}):
		_model_option.add_item(str(kind))
	for i in _model_option.item_count:
		if _model_option.get_item_text(i) == current:
			_model_option.selected = i
			break
	_update_model_note()


func _update_model_note() -> void:
	var show: bool = service != null and _model_option.selected > 0 \
			and not service.model_supports_styles(
				_model_option.get_item_text(_model_option.selected))
	_model_note.text = "custom styles ignored (v3-only)" if show else ""
	_model_note.visible = show


func _refresh_status() -> void:
	var stat: Dictionary = service.status()
	var bits := PackedStringArray()
	bits.append("balance: %s" % ("?" if stat["balance"] < 0 else str(stat["balance"])))
	if stat["generating"]:
		bits.append("generating…")
	if not stat["api_key_configured"]:
		bits.append("NO API KEY — open Settings")
	_status_label.text = "  ".join(bits)


func _refresh_gallery() -> void:
	for child in _gallery_grid.get_children():
		child.queue_free()
	var filters := {"search": _search_edit.text}
	if _filter_preset.selected > 0:
		filters["preset"] = _filter_preset.get_item_text(_filter_preset.selected)
	if _filter_state.selected > 0:
		filters["state"] = _filter_state.get_item_text(_filter_state.selected)
	for rec in service.get_history(filters):
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(96, 96)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.texture_normal = service.thumbnail(str(rec["id"]))
		btn.tooltip_text = "%s\n%s — %s\n%s" % [
			rec["id"], rec.get("preset"), rec.get("state"), str(rec.get("subject"))]
		btn.pressed.connect(_select.bind(str(rec["id"])))
		_gallery_grid.add_child(btn)
	if not _selected_id.is_empty():
		_refresh_detail()


func _select(gen_id: String) -> void:
	_selected_id = gen_id
	_refresh_detail()


func _refresh_detail() -> void:
	var rec: Dictionary = service.get_generation(_selected_id)
	if rec.is_empty():
		_set_detail_enabled(false)
		return
	_set_detail_enabled(true)

	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color.BLACK
	if _checker_toggle.button_pressed:
		var tex_box := StyleBoxTexture.new()
		tex_box.texture = _checker_tex
		_preview_panel.add_theme_stylebox_override("panel", tex_box)
	else:
		_preview_panel.add_theme_stylebox_override("panel", style_box)

	var img: Image = service.preview_image(_selected_id, _checker_toggle.button_pressed)
	_preview_rect.texture = ImageTexture.create_from_image(img) if img != null else null

	var lineage_text := ""
	for parent in rec.get("lineage", []):
		lineage_text += " ← " + str(parent["id"])
	_meta_label.text = (
		"[b]%s[/b]  (%s)\npreset: %s   model: %s\nsubject: %s\nprompt: %s\n"
		+ "cost: %s units   post: %s%s%s") % [
		rec["id"], rec.get("state"), rec.get("preset"), rec.get("model"),
		rec.get("subject"), str(rec.get("prompt")).left(220),
		rec.get("cost_units"), str(rec.get("post")),
		("\nsaved → " + str(rec.get("dest"))) if rec.get("state") == "saved" else "",
		("\nlineage: " + lineage_text.trim_prefix(" ← ")) if not lineage_text.is_empty() else ""]
	if _name_edit.text.is_empty():
		_name_edit.text = str(rec.get("subject", "")).replace(" ", "_")


func _set_detail_enabled(enabled: bool) -> void:
	for btn in [_save_btn, _iterate_btn, _more_btn, _discard_btn]:
		btn.disabled = not enabled


# -- Helpers ------------------------------------------------------------------

func _label_wrap(text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	box.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box


func _make_checkerboard() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var light := (x / 8 + y / 8) % 2 == 0
			img.set_pixel(x, y, Color(0.45, 0.45, 0.45) if light else Color(0.25, 0.25, 0.25))
	return ImageTexture.create_from_image(img)
