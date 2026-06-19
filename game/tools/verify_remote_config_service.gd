extends SceneTree

## Headless verifier for RemoteConfigService — the Remote Config aggregation logic,
## exercised WITHOUT the editor:
##   godot --headless --path . --script res://tools/verify_remote_config_service.gd
## Covers the pure surface (build_document order/skip, versions, validate's
## missing-file / missing-version / duplicate-key / empty-manifest cases) driven
## against a temp manifest, the real committed manifest (loaded via reload() →
## res://remote_config_editor.config.json) aggregating the committed blocks, and
## copy_publish_payload's validate gate. The check_sync shell-out (live bun) is NOT
## exercised here. Writes only to a temp dir.

const ServiceT := preload("res://addons/remote_config_editor/remote_config_service.gd")

var _ok := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var svc: Node = ServiceT.new()
	root.add_child(svc)

	var tmp := OS.get_cache_dir().path_join("rc_verify")
	DirAccess.make_dir_recursive_absolute(tmp)

	# ── a clean two-entry manifest (beta deliberately at version 0) ──────────────
	_write(tmp.path_join("manifest.json"), JSON.stringify({
		"app_config_version": "v1",
		"entries": [
			{"key": "alpha", "file": "alpha.json", "version_field": "v", "label": "Alpha"},
			{"key": "beta", "file": "beta.json", "version_field": "version", "label": "Beta"},
		]}, "  "))
	_write(tmp.path_join("alpha.json"), JSON.stringify({"v": 3, "x": 1}))
	_write(tmp.path_join("beta.json"), JSON.stringify({"version": 0, "y": 2}))
	svc.reload_from(tmp.path_join("manifest.json"), tmp, "validator/content")

	var doc: Dictionary = svc.build_document()
	_check("build_document keys in manifest order", doc.keys() == ["alpha", "beta"])
	_check("build_document carries each blob", int(doc["alpha"]["x"]) == 1 and int(doc["beta"]["y"]) == 2)
	_check("app_config_version read", svc.app_config_version() == "v1")
	var vers: Array = svc.versions()
	_check("versions present + reads the per-entry field (incl version 0)",
		vers.size() == 2 and bool(vers[0]["present"]) and int(vers[0]["version"]) == 3 and int(vers[1]["version"]) == 0)
	_check("clean manifest validates []", svc.validate() == [])

	# ── missing version field ───────────────────────────────────────────────────
	_write(tmp.path_join("manifest.json"), JSON.stringify({"app_config_version": "v1", "entries": [
		{"key": "alpha", "file": "alpha.json", "version_field": "nope", "label": "Alpha"}]}, "  "))
	svc.reload_from(tmp.path_join("manifest.json"), tmp, "validator/content")
	_check("validate flags a missing version field",
		svc.validate().has("alpha: missing integer version field \"nope\""))

	# ── missing content file ────────────────────────────────────────────────────
	_write(tmp.path_join("manifest.json"), JSON.stringify({"app_config_version": "v1", "entries": [
		{"key": "ghost", "file": "ghost.json", "version_field": "v", "label": "Ghost"}]}, "  "))
	svc.reload_from(tmp.path_join("manifest.json"), tmp, "validator/content")
	_check("validate flags a missing content file",
		svc.validate().has("ghost: content file not found (validator/content/ghost.json)"))
	_check("build_document skips a missing blob", svc.build_document().is_empty())

	# ── duplicate key ───────────────────────────────────────────────────────────
	_write(tmp.path_join("manifest.json"), JSON.stringify({"app_config_version": "v1", "entries": [
		{"key": "alpha", "file": "alpha.json", "version_field": "v", "label": "A"},
		{"key": "alpha", "file": "beta.json", "version_field": "version", "label": "B"}]}, "  "))
	svc.reload_from(tmp.path_join("manifest.json"), tmp, "validator/content")
	_check("validate flags a duplicate key", svc.validate().has("alpha: duplicate key in manifest"))

	# ── missing manifest hard-fails (no fallback list) ──────────────────────────
	svc.reload_from(tmp.path_join("does_not_exist.json"), tmp, "validator/content")
	_check("missing manifest -> build_document is empty", svc.build_document().is_empty())
	_check("missing manifest -> validate reports it",
		svc.validate().size() == 1 and str(svc.validate()[0]).begins_with("manifest missing or has no entries"))
	_check("copy refuses an invalid document", not svc.copy_publish_payload().get("ok", true))

	# ── the REAL committed manifest aggregates both live blocks ──────────────────
	svc.reload()
	var real: Dictionary = svc.build_document()
	_check("real manifest aggregates story_catalog", real.has("story_catalog"))
	_check("real manifest aggregates daily_missions", real.has("daily_missions"))
	_check("committed blobs validate clean", svc.validate() == [])
	var cp: Dictionary = svc.copy_publish_payload()
	_check("copy_publish_payload ok on the committed set", cp.get("ok", false) and int(cp.get("count", 0)) >= 2)

	svc.queue_free()
	print("VERIFY remote_config_service: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
