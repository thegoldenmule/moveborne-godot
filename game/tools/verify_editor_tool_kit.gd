extends SceneTree

## Headless verifier for the editor_tool_kit shared bases (no editor, no I/O
## beyond a temp dir):
##   godot --headless --path . --script res://tools/verify_editor_tool_kit.gd
## Proves the bases before any tool depends on them: the ToolService {ok,error}
## contract + dirty flag, ContentStore load / atomic N-target write / validate
## abort / version-bump rollback, and the EditorToolUi builder return types.

const ToolServiceT := preload("res://addons/editor_tool_kit/tool_service.gd")
const ContentStoreT := preload("res://addons/editor_tool_kit/content_store.gd")
const EditorToolUiT := preload("res://addons/editor_tool_kit/editor_tool_ui.gd")
const PaletteT := preload("res://addons/editor_tool_kit/tool_palette.gd")
const ToolThemeT := preload("res://addons/editor_tool_kit/tool_theme.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true
	var tmp := OS.get_cache_dir().path_join("edkit_verify")
	DirAccess.make_dir_recursive_absolute(tmp)

	# ── ToolService: ok / err / dirty ─────────────────────────────────────────
	var svc: Node = ToolServiceT.new()
	ok = _check(ok, svc.ok() == {"ok": true}, "ok() bare is {ok:true}")
	ok = _check(ok, svc.ok({"id": "g1", "n": 2}) == {"ok": true, "id": "g1", "n": 2},
		"ok(data) merges data")
	ok = _check(ok, svc.err("boom") == {"ok": false, "error": "boom"},
		"err(msg) omits zero code")
	ok = _check(ok, svc.err("boom", 400) == {"ok": false, "error": "boom", "code": 400},
		"err(msg, code) carries non-zero code")
	ok = _check(ok, not svc.is_dirty(), "fresh service is clean")
	svc.mark_dirty()
	ok = _check(ok, svc.is_dirty(), "mark_dirty sets dirty")
	svc.clear_dirty()
	ok = _check(ok, not svc.is_dirty(), "clear_dirty clears dirty")
	svc.free()

	# ── ContentStore.load_json ────────────────────────────────────────────────
	ok = _check(ok, ContentStoreT.load_json(tmp.path_join("nope.json")) == {},
		"load_json {} for a missing path")
	var jpath := tmp.path_join("data.json")
	_write(jpath, '{"a": 1, "b": "two"}')
	var loaded: Dictionary = ContentStoreT.load_json(jpath)
	ok = _check(ok, int(loaded.get("a", 0)) == 1 and str(loaded.get("b", "")) == "two",
		"load_json parses an object file")
	_write(tmp.path_join("bad.json"), "not json {")
	ok = _check(ok, ContentStoreT.load_json(tmp.path_join("bad.json")) == {},
		"load_json {} for a corrupt file")

	# ── ContentStore.save_all: atomic N-target write ──────────────────────────
	var t1 := tmp.path_join("out1.txt")
	var t2 := tmp.path_join("out2.txt")
	for p in [t1, t2]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var w: Dictionary = ContentStoreT.save_all(
		[{"path": t1, "text": "one\n"}, {"path": t2, "text": "two\n"}],
		func() -> Array: return [], false)
	ok = _check(ok, w.get("ok", false), "save_all ok for valid targets")
	ok = _check(ok, FileAccess.get_file_as_string(t1) == "one\n"
		and FileAccess.get_file_as_string(t2) == "two\n", "save_all wrote both targets")

	# validate problems abort BEFORE any write
	var t3 := tmp.path_join("out3.txt")
	if FileAccess.file_exists(t3):
		DirAccess.remove_absolute(t3)
	var aborted: Dictionary = ContentStoreT.save_all(
		[{"path": t3, "text": "nope\n"}],
		func() -> Array: return ["bad edit"], false)
	ok = _check(ok, not aborted.get("ok", true) and str(aborted.get("error")) == "bad edit",
		"save_all returns the joined problems")
	ok = _check(ok, not FileAccess.file_exists(t3), "save_all wrote nothing when validate failed")

	# ── ContentStore.bump_then: rollback on write failure ─────────────────────
	var struct := {"catalog_version": 5}
	var good: Dictionary = ContentStoreT.bump_then(struct, "catalog_version",
		func() -> Dictionary: return ContentStoreT.save_all(
			[{"path": tmp.path_join("v.txt"), "text": "x"}],
			func() -> Array: return [], false))
	ok = _check(ok, good.get("ok", false) and int(struct["catalog_version"]) == 6,
		"bump_then commits the bump on success")

	struct = {"catalog_version": 5}
	var bad: Dictionary = ContentStoreT.bump_then(struct, "catalog_version",
		func() -> Dictionary: return ContentStoreT.save_all(
			# an unwritable path (parent dir does not exist) forces the write to fail
			[{"path": "/edkit_nonexistent_dir_zzz/v.txt", "text": "x"}],
			func() -> Array: return [], false))
	ok = _check(ok, not bad.get("ok", true) and int(struct["catalog_version"]) == 5,
		"bump_then rolls the bump back on write failure")

	struct = {"catalog_version": 5}
	ContentStoreT.bump_then(struct, "catalog_version",
		func() -> Dictionary: return {"ok": true}, false)
	ok = _check(ok, int(struct["catalog_version"]) == 5, "bump_then when=false leaves version untouched")

	# ── EditorToolUi: builder return types ────────────────────────────────────
	var split: HSplitContainer = EditorToolUiT.split_root(220, 400)
	ok = _check(ok, split is HSplitContainer and split.get_child_count() == 2,
		"split_root(floors) is an HSplitContainer with two panes")
	ok = _check(ok, split.get_child(0).custom_minimum_size.x == 220
		and split.get_child(1).custom_minimum_size.x == 400, "split_root applies pane floors")
	split.free()
	var bare: HSplitContainer = EditorToolUiT.split_root()
	ok = _check(ok, bare is HSplitContainer and bare.get_child_count() == 0,
		"split_root() bare adds no panes")
	bare.free()
	var hits := [0]
	var hdr: PanelContainer = EditorToolUiT.tool_header("My Tool", "0.1.0", func() -> void: hits[0] += 1)
	var sb := hdr.get_theme_stylebox("panel")
	ok = _check(ok, hdr is PanelContainer and sb is StyleBoxFlat and (sb as StyleBoxFlat).border_width_bottom > 0,
		"tool_header is a PanelContainer framed by a bottom rule")
	var hbar := hdr.get_child(0) as HBoxContainer
	ok = _check(ok, hbar is HBoxContainer and hbar.get_child_count() == 3,
		"tool_header packs title + version + reload when a version is given")
	var title := hbar.get_child(0) as Label
	ok = _check(ok, title.text == "My Tool" and title.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and title.get_theme_color("font_color") == PaletteT.EMPHASIS,
		"tool_header title expands and reads as a heading via the emphasis color (shares the editor-default size)")
	ok = _check(ok, (hbar.get_child(1) as Label).text == "v0.1.0", "tool_header tags the version with a 'v' prefix")
	var reload := hbar.get_child(2) as Button
	ok = _check(ok, reload is Button and reload.pressed.get_connections().size() == 1,
		"tool_header reload button is wired to the handler")
	hdr.free()
	var hdr2: PanelContainer = EditorToolUiT.tool_header("No Version")
	ok = _check(ok, (hdr2.get_child(0) as HBoxContainer).get_child_count() == 2,
		"tool_header omits the version label when version is blank")
	hdr2.free()

	var lw: VBoxContainer = EditorToolUiT.label_wrap("Caption", LineEdit.new())
	ok = _check(ok, lw is VBoxContainer and lw.get_child_count() == 2, "label_wrap is a VBox(label, control)")
	ok = _check(ok, (lw.get_child(1) as Control).size_flags_vertical != Control.SIZE_EXPAND_FILL,
		"label_wrap leaves the control non-expanding vertically by default")
	lw.free()
	var lwv: VBoxContainer = EditorToolUiT.label_wrap("Caption", TextEdit.new(), true)
	ok = _check(ok, (lwv.get_child(1) as Control).size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"label_wrap(fill_v) expands the control vertically")
	lwv.free()
	var fr: HBoxContainer = EditorToolUiT.form_row("Name", LineEdit.new())
	ok = _check(ok, fr is HBoxContainer and fr.get_child_count() == 2, "form_row is an HBox(label, control)")
	fr.free()
	var called := [0]
	var btn: Button = EditorToolUiT.button("Go", func() -> void: called[0] += 1, "tip")
	ok = _check(ok, btn is Button and btn.text == "Go" and btn.tooltip_text == "tip"
		and btn.pressed.get_connections().size() == 1, "button sets text/tooltip and connects the handler")
	var plain: Button = EditorToolUiT.button("Plain")
	ok = _check(ok, plain.pressed.get_connections().is_empty(), "button with no handler leaves pressed unconnected")
	plain.free()
	var bar: HBoxContainer = EditorToolUiT.button_bar([btn, Label.new(), "skip", Button.new()])
	ok = _check(ok, bar is HBoxContainer and bar.get_child_count() == 3, "button_bar packs only the Control items")
	bar.free()
	var sp: SpinBox = EditorToolUiT.spin(1, 6, 2)
	ok = _check(ok, sp is SpinBox and sp.min_value == 1 and sp.max_value == 6 and sp.value == 2
		and sp.step == 1 and sp.size_flags_horizontal != Control.SIZE_EXPAND_FILL, "spin presets range/value, no fill by default")
	sp.free()
	var spf: SpinBox = EditorToolUiT.spin(0, 9, 0, 1.0, true)
	ok = _check(ok, spf.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "spin(fill) expands horizontally")
	spf.free()
	var sl: Label = EditorToolUiT.status_label()
	ok = _check(ok, sl is Label and sl.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"status_label is a wrapping Label")
	sl.free()
	var panel := Panel.new()
	EditorToolUiT.restyle_selected(panel, true)
	ok = _check(ok, panel.has_theme_stylebox_override("panel"), "restyle_selected applies a panel stylebox")
	panel.free()

	# ── EditorToolUi.section: framed, captioned group ─────────────────────────
	var sect: PanelContainer = EditorToolUiT.section("Goals", LineEdit.new())
	ok = _check(ok, sect is PanelContainer, "section is a PanelContainer")
	var sb_sect := sect.get_theme_stylebox("panel") as StyleBoxFlat
	ok = _check(ok, sb_sect != null and sb_sect.border_color == PaletteT.VIOLET
		and sb_sect.get_border_width(SIDE_TOP) == PaletteT.BORDER,
		"section frames with a palette-violet border (per-control override wins over the cascade)")
	var sect_col := sect.get_child(0) as VBoxContainer
	ok = _check(ok, sect_col is VBoxContainer and sect_col.get_child_count() == 2,
		"section holds a VBox(caption, body)")
	var cap := sect_col.get_child(0) as Label
	ok = _check(ok, cap.text == "Goals" and cap.get_theme_font_size("font_size") == PaletteT.H_CAPTION
		and cap.get_theme_color("font_color") == PaletteT.CAPTION,
		"section caption uses the palette caption color + size")
	ok = _check(ok, (sect_col.get_child(1) as Control).size_flags_horizontal == Control.SIZE_EXPAND_FILL,
		"section body fills horizontally")
	sect.free()

	# ── EditorToolTheme.build: cascaded occult-arcade Theme ───────────────────
	var theme := ToolThemeT.build()
	ok = _check(ok, theme is Theme, "build() returns a Theme")
	# Every control type the theme claims to cover must exist with its key states,
	# so no cascaded control renders a missing/black stylebox.
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			ok = _check(ok, theme.has_stylebox(state, type), "theme has %s/%s stylebox" % [type, state])
	for type in ["TabContainer", "TabBar"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			ok = _check(ok, theme.has_stylebox(state, type), "theme has %s/%s stylebox" % [type, state])
	ok = _check(ok, theme.has_stylebox("panel", "TabContainer")
		and theme.has_stylebox("panel", "PanelContainer") and theme.has_stylebox("panel", "Panel"),
		"theme paints TabContainer/PanelContainer/Panel panels")
	for type in ["LineEdit", "TextEdit"]:
		for state in ["normal", "focus", "read_only"]:
			ok = _check(ok, theme.has_stylebox(state, type), "theme has %s/%s stylebox" % [type, state])
	for type in ["Tree", "ItemList"]:
		ok = _check(ok, theme.has_stylebox("panel", type) and theme.has_stylebox("selected", type)
			and theme.has_stylebox("selected_focus", type), "theme covers %s panel + selection" % type)
	ok = _check(ok, theme.has_stylebox("separator", "HSeparator")
		and theme.has_stylebox("separator", "VSeparator"), "theme rules HSeparator/VSeparator")
	ok = _check(ok, theme.has_stylebox("panel", "PopupMenu"), "theme styles the PopupMenu (OptionButton dropdown)")

	# Values are sourced from EditorToolPalette — not hard-coded in the theme.
	var btn_normal := theme.get_stylebox("normal", "Button") as StyleBoxFlat
	ok = _check(ok, btn_normal != null and btn_normal.bg_color == PaletteT.PANEL_BG
		and btn_normal.border_color == PaletteT.VIOLET,
		"Button/normal pulls bg + border from the palette")
	var btn_hover := theme.get_stylebox("hover", "Button") as StyleBoxFlat
	ok = _check(ok, btn_hover != null and btn_hover.border_color == PaletteT.VIOLET_HOVER,
		"Button/hover uses the palette hover violet")
	var hsep := theme.get_stylebox("separator", "HSeparator") as StyleBoxLine
	ok = _check(ok, hsep != null and hsep.color == PaletteT.VIOLET_DEEP,
		"separator rule uses the palette deep violet")
	var vsep := theme.get_stylebox("separator", "VSeparator") as StyleBoxLine
	ok = _check(ok, vsep != null and vsep.vertical, "VSeparator rule is vertical")
	ok = _check(ok, theme.get_color("font_color", "Label") == PaletteT.TEXT,
		"Label font_color is the palette text color")
	ok = _check(ok, theme.get_color("font_selected_color", "TabContainer") == PaletteT.EMPHASIS,
		"selected tab text is the palette emphasis (white)")

	print("VERIFY editor_tool_kit: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(ok: bool, condition: bool, what: String) -> bool:
	if not condition:
		print("FAIL " + what)
	return ok and condition
