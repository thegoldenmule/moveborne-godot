extends SceneTree

## Headless verifier for the ui_kit self-update logic (no editor, no network):
##   godot --headless --path . --script res://tools/verify_ui_kit_update.gd
## Proves the version parse/compare helpers and the runner's archive-entry → install
## path mapping + path-safety guard — the bits that decide what gets written where.

const UpdateServiceT := preload("res://addons/ui_kit/update/update_service.gd")
const RunnerT := preload("res://addons/ui_kit/update/update_reload_runner.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true

	# ── UpdateService: version parse + compare ────────────────────────────────
	var cfg_text := "[plugin]\nname=\"UI Kit\"\nversion=\"1.2.3\"\nscript=\"plugin.gd\"\n"
	ok = _check(ok, UpdateServiceT.parse_remote_version(cfg_text) == "1.2.3",
		"parse_remote_version reads the plugin.cfg version")
	ok = _check(ok, UpdateServiceT.parse_remote_version("not a config {") == "",
		"parse_remote_version is empty on unparseable text")
	ok = _check(ok, UpdateServiceT.parse_remote_version("[plugin]\nname=\"x\"\n") == "",
		"parse_remote_version is empty when version is absent")
	ok = _check(ok, UpdateServiceT.is_newer("1.0.1", "1.0.0"), "is_newer: patch bump")
	ok = _check(ok, UpdateServiceT.is_newer("1.1.0", "1.0.9"), "is_newer: minor beats patch")
	ok = _check(ok, UpdateServiceT.is_newer("2.0.0", "1.9.9"), "is_newer: major bump")
	ok = _check(ok, UpdateServiceT.is_newer("0.2", "0.1.9"), "is_newer: shorter remote, zero-filled")
	ok = _check(ok, not UpdateServiceT.is_newer("0.1.0", "0.1.0"), "is_newer: false on equal")
	ok = _check(ok, not UpdateServiceT.is_newer("1.0.0", "1.0.1"), "is_newer: false when older")
	var usvc: Node = UpdateServiceT.new()
	ok = _check(ok, usvc.installed_version() != "",
		"installed_version reads the kit's own plugin.cfg")
	ok = _check(ok, not usvc.is_busy() and not usvc.has_update(),
		"a fresh UpdateService is idle (not busy, no update)")
	usvc.free()

	# ── Runner: archive entry → install path mapping + path-safety guard ──────
	ok = _check(ok, RunnerT._archive_rel("addons/ui_kit/plugin.gd")
		== "addons/ui_kit/plugin.gd", "_archive_rel keeps a direct addon path")
	ok = _check(ok, RunnerT._archive_rel("godot-addons-main/addons/ui_kit/plugin.gd")
		== "addons/ui_kit/plugin.gd", "_archive_rel strips the single archive wrapper")
	ok = _check(ok, RunnerT._archive_rel("godot-addons-main/addons/ui_kit/ui_driver.gd.uid")
		== "addons/ui_kit/ui_driver.gd.uid", "_archive_rel maps .uid files too")
	ok = _check(ok, RunnerT._archive_rel("godot-addons-main/templates/addons/ui_kit/x.gd")
		== "", "_archive_rel rejects a deeper-nested copy")
	ok = _check(ok, RunnerT._archive_rel("godot-addons-main/README.md") == "",
		"_archive_rel drops non-addon files (other addons aren't touched)")
	ok = _check(ok, RunnerT._archive_rel("godot-addons-main/addons/other_addon/plugin.gd") == "",
		"_archive_rel ignores sibling addons in the repo")
	ok = _check(ok, RunnerT._is_safe("addons/ui_kit/plugin.gd"),
		"_is_safe accepts a normal addon path")
	ok = _check(ok, not RunnerT._is_safe("addons/ui_kit/../../../evil.gd"),
		"_is_safe rejects path traversal")
	ok = _check(ok, not RunnerT._is_safe("/abs/addons/ui_kit/x.gd"),
		"_is_safe rejects an absolute path")
	ok = _check(ok, not RunnerT._is_safe("other/thing.gd"),
		"_is_safe rejects a path outside the addon prefix")

	print("VERIFY ui_kit_update: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _check(ok: bool, condition: bool, what: String) -> bool:
	if not condition:
		print("FAIL " + what)
	return ok and condition
