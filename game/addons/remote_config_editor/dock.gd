@tool
extends Control

## Bottom-panel dock for the Remote Config tool — a thin VIEW over
## RemoteConfigService. Shows the registry as a key / file / version / present
## table, previews the WHOLE app-config/v1 document that will be published, copies
## that full payload to the clipboard (a console paste can never drop a sibling
## key), and runs Check Sync (per-key drift) via the generic appconfig.ts.
##
## All aggregation / validation / verify lives in the service (headless-testable);
## the dock holds only control refs and re-renders on `changed`. The enforced
## tool header (title + version + reload) is mounted by EditorToolPlugin.

const Ui := preload("res://addons/editor_tool_kit/editor_tool_ui.gd")
const Pal := preload("res://addons/editor_tool_kit/tool_palette.gd")

var service: Node   # RemoteConfigService, injected by the EditorToolPlugin base

var _table: Tree
var _preview: TextEdit
var _sync: Label
var _status: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, 480)
	_build_ui()
	# Method callable (not a lambda): auto-disconnects when the dock frees, so a
	# late signal can't fire into a freed view.
	if service != null:
		service.changed.connect(_on_service_changed)
	_reload()


func _on_service_changed() -> void:
	_refresh_table()
	_refresh_preview()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", Pal.SEP)
	add_child(root)

	# A draggable vertical split: the keys table on top, the publish-payload
	# preview below, so the operator can give either pane more room.
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_table = Tree.new()
	_table.columns = 4
	_table.column_titles_visible = true
	_table.hide_root = true
	_table.custom_minimum_size = Vector2(0, 90)
	_table.set_column_title(0, "Key")
	_table.set_column_title(1, "File")
	_table.set_column_title(2, "Version")
	_table.set_column_title(3, "Present")
	var keys_section := Ui.section("App-config keys (validator/content/app_config.manifest.json)", _table, true)
	keys_section.size_flags_stretch_ratio = 0.4   # start compact; the preview gets the rest
	split.add_child(keys_section)

	_preview = TextEdit.new()
	_preview.editable = false
	_preview.custom_minimum_size = Vector2(0, 120)
	split.add_child(Ui.section("Publish payload — the WHOLE app-config document", _preview, true))

	root.add_child(Ui.button_bar([
		Ui.button("Reload", _reload),
		Ui.button("Copy publish payload", _on_copy),
		Ui.button("Check sync", _on_check_sync),
	]))

	_sync = Ui.status_label()
	root.add_child(Ui.section("Sync (live ⇄ committed)", _sync))

	_status = Ui.status_label()
	root.add_child(_status)


# ── data ───────────────────────────────────────────────────────────────────────


func _reload() -> void:
	service.reload()   # emits `changed`; _on_service_changed rebuilds the view
	var v := str(service.app_config_version())
	if service.validate().is_empty():
		_status.text = "Loaded manifest (app-config/%s) — %d block(s), ready to publish." % [
			v, service.versions().size()]
	else:
		_status.text = "Loaded manifest (app-config/%s) — see Sync for problems before publishing." % v
	_sync.text = "Run Check sync to compare the live Remote Config to the committed blobs."


func _refresh_table() -> void:
	if _table == null:
		return
	_table.clear()
	var root := _table.create_item()
	for row in service.versions():
		var it := _table.create_item(root)
		it.set_text(0, str(row.get("key", "")))
		it.set_text(1, str(row.get("file", "")))
		it.set_text(2, ("v%d" % int(row.get("version", 0))) if bool(row.get("has_version", true)) else "v?")
		var present := bool(row.get("present", false))
		it.set_text(3, "✓" if present else "✗ missing")
		it.set_custom_color(3, Pal.GREEN_SEL if present else Pal.ERROR)


func _refresh_preview() -> void:
	if _preview == null:
		return
	_preview.text = JSON.stringify(service.build_document(), "  ")


# ── actions ──────────────────────────────────────────────────────────────────--


func _on_copy() -> void:
	var r: Dictionary = service.copy_publish_payload()
	if not r.get("ok", false):
		_status.text = "Not copied — fix these first:\n- " + str(r.get("error", "")).replace("\n", "\n- ")
		return
	_status.text = "Copied the full app-config document (%d key(s), %d bytes) — paste into the Snapser console App Config, version %s." % [
		int(r.get("count", 0)), int(r.get("bytes", 0)), str(service.app_config_version())]


func _on_check_sync() -> void:
	_sync.text = "Checking live Remote Config…"
	var r: Dictionary = service.check_sync()
	if int(r.get("code", -1)) == -1:
		_sync.text = "Could not run bun. In a terminal: `cd validator && bun run appconfig:verify`"
		return
	var results: Array = r.get("results", [])
	if results.is_empty():
		var why: String = str(r.get("error", ""))
		_sync.text = "Could not verify (exit %d)%s — is the snap provisioned and app-config published?\n%s" % [
			int(r.get("code", 0)), (" — " + why) if why != "" else "", str(r.get("text", ""))]
		return
	var lines: Array = []
	for res in results:
		var key := str((res as Dictionary).get("key", ""))
		var st := str((res as Dictionary).get("status", "?"))
		match st:
			"match":
				lines.append("✓ %s — in sync (v%s)" % [key, str((res as Dictionary).get("committed_version", "?"))])
			"drift":
				lines.append("✗ %s — DRIFT (live v%s / committed v%s)" % [
					key, str((res as Dictionary).get("live_version", "?")), str((res as Dictionary).get("committed_version", "?"))])
			"absent":
				lines.append("✗ %s — ABSENT from the live app-config" % key)
			_:
				lines.append("? %s — %s" % [key, st])
	var ok := bool(r.get("ok", false))
	_sync.text = ("All blocks in sync ✓\n" if ok else "Drift — re-copy + paste to republish:\n") + "\n".join(lines)
