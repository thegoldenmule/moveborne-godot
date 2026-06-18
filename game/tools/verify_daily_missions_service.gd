extends SceneTree

## Headless verifier for DailyMissionsService — the Daily Missions authoring logic,
## exercised WITHOUT the editor:
##   godot --headless --path . --script res://tools/verify_daily_missions_service.gd
## Covers load/defaults + by_weekday normalization, mission CRUD, the rename
## cascade (catalog key + every weekday + anchor), rotation edits, validate()
## positive/negative (incl. the icon allow-set + empty reward + warnings),
## serialize() round-trip stability, and the single-target save with a
## forced-write-failure version-bump rollback. Writes only to a temp dir.

const ServiceT := preload("res://addons/daily_missions_editor/daily_missions_service.gd")
const Model := preload("res://ui/screens/daily_missions_model.gd")

var _ok := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var svc: Node = ServiceT.new()
	root.add_child(svc)

	var tmp := OS.get_cache_dir().path_join("dm_verify")
	DirAccess.make_dir_recursive_absolute(tmp)
	var missing := tmp.path_join("nope_daily_missions.json")
	if FileAccess.file_exists(missing):
		DirAccess.remove_absolute(missing)

	# ── load / defaults / normalization ─────────────────────────────────────────
	svc.reload_from(missing)
	_check("absent file -> disabled default", not bool(svc.block.get("enabled", true)))
	_check("default version 1", int(svc.block.get("version", 0)) == 1)
	_check("by_weekday normalized to 7 string keys",
		(svc.block["by_weekday"] as Dictionary).size() == 7 and svc.block["by_weekday"].has("6"))
	_check("not dirty after reload", not svc.is_dirty())

	# ── mission CRUD ─────────────────────────────────────────────────────────────
	var id1 := str(svc.add_mission().get("id", ""))
	_check("add_mission returns a placeholder id", id1 == "mission_new")
	_check("add_mission marks dirty", svc.is_dirty())
	var id2 := str(svc.add_mission().get("id", ""))
	_check("second add gets a unique id", id2 == "mission_new_2")
	svc.set_mission_field(id1, "title", "Daily Dozen")
	svc.set_mission_field(id1, "icon", "trophy")
	svc.set_mission_field(id1, "reward", "100 coins")
	_check("set_mission_field writes", str(svc.get_mission(id1).get("title", "")) == "Daily Dozen"
		and str(svc.get_mission(id1).get("icon", "")) == "trophy")

	# ── rotation + rename cascade ───────────────────────────────────────────────
	svc.add_weekday(1, id1)
	svc.add_weekday(1, id1)   # idempotent
	_check("add_weekday adds once", svc.weekday_ids(1).count(id1) == 1)
	svc.set_anchor(id1)
	_check("set_anchor", str(svc.block.get("anchor", "")) == id1)
	var rr: Dictionary = svc.rename_mission(id1, "mission_play_3")
	_check("rename ok", rr.get("ok", false) and str(rr.get("new_id", "")) == "mission_play_3")
	_check("rename rekeys the catalog",
		svc.get_mission("mission_play_3").get("title", "") == "Daily Dozen"
		and not (svc.block["catalog"] as Dictionary).has(id1))
	_check("rename cascades into the weekday", svc.weekday_ids(1).has("mission_play_3") and not svc.weekday_ids(1).has(id1))
	_check("rename cascades into the anchor", str(svc.block.get("anchor", "")) == "mission_play_3")
	_check("rename rejects a collision", not svc.rename_mission(id2, "mission_play_3").get("ok", true))
	svc.remove_mission("mission_play_3")
	_check("remove erases the catalog entry", not (svc.block["catalog"] as Dictionary).has("mission_play_3"))
	_check("remove cascades out of the weekday", not svc.weekday_ids(1).has("mission_play_3"))
	_check("remove clears the anchor", str(svc.block.get("anchor", "")) == "")

	# ── validate (positive + negative) ──────────────────────────────────────────
	svc.block = {"enabled": true, "version": 1, "anchor": "a",
		"by_weekday": {"0": [], "1": ["a"], "2": [], "3": [], "4": [], "5": [], "6": []},
		"catalog": {"a": {"title": "A", "icon": "cards", "desc": "d", "reward": "100 coins"}}}
	_check("valid block has no hard errors", svc._errors() == [])
	_check("validate warns about empty weekdays",
		svc.validate().has("warning: weekday 0 has no missions"))
	svc.block["catalog"]["a"]["icon"] = "bogus"
	svc.block["catalog"]["a"]["reward"] = "  "
	svc.block["by_weekday"]["2"] = ["ghost"]
	svc.block["anchor"] = "missing"
	var errs: Array = svc._errors()
	_check("validate flags an invalid icon", _has_prefix(errs, "a: invalid icon"))
	_check("validate flags an empty reward", errs.has("a: empty reward"))
	_check("validate flags an unknown weekday id", errs.has("weekday 2: unknown mission \"ghost\""))
	_check("validate flags an unknown anchor", errs.has("anchor: unknown mission \"missing\""))

	# ── icon allow-set excludes the render fallback ─────────────────────────────
	_check("icon_names excludes the \"\" fallback",
		Model.icon_names().has("cards") and not Model.icon_names().has(""))

	# ── serialize round-trip stability ──────────────────────────────────────────
	svc.block = {"enabled": true, "version": 2, "anchor": "a",
		"by_weekday": {"0": ["a"], "1": ["b", "a"], "2": [], "3": [], "4": [], "5": [], "6": []},
		"catalog": {
			"b": {"title": "B", "icon": "bolt", "desc": "bb", "reward": "80 coins"},
			"a": {"title": "A", "icon": "cards", "desc": "aa", "reward": "100 coins"}}}
	var s1: String = svc.serialize()
	var rt := tmp.path_join("rt.json")
	_write(rt, s1)
	svc.reload_from(rt)
	_check("serialize round-trips byte-identical", svc.serialize() == s1)
	var parsed = JSON.parse_string(s1)
	_check("serialize sorts catalog ids", (parsed["catalog"] as Dictionary).keys() == ["a", "b"])
	_check("serialize keeps weekday list order", parsed["by_weekday"]["1"] == ["b", "a"])

	# ── save_to: success + version bump, then a write-failure rollback ──────────
	var out := tmp.path_join("dm_out.json")
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	svc.reload_from(rt)
	svc.mark_dirty()
	var v0 := int(svc.block.get("version", 1))
	var r: Dictionary = svc.save_to(out, false)
	_check("save_to succeeds", r.get("ok", false))
	_check("save_to bumps the dirty version", r.get("bumped", false) and int(svc.block["version"]) == v0 + 1)
	_check("save_to wrote the file", FileAccess.file_exists(out))

	svc.reload_from(rt)
	svc.mark_dirty()
	var v1 := int(svc.block.get("version", 1))
	var rf: Dictionary = svc.save_to("/dm_nonexistent_dir_zzz/x.json", false)
	_check("save_to fails on an unwritable path", not rf.get("ok", true) and str(rf.get("stage", "")) == "write")
	_check("a failed save rolls back the bump", int(svc.block["version"]) == v1)

	# ── save_to refuses an invalid block ────────────────────────────────────────
	svc.block["catalog"]["a"]["icon"] = "bogus"
	var ri: Dictionary = svc.save_to(out, false)
	_check("save_to blocks on validation errors", not ri.get("ok", true) and str(ri.get("stage", "")) == "validate")

	svc.queue_free()
	print("VERIFY daily_missions_service: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _has_prefix(arr: Array, prefix: String) -> bool:
	for s in arr:
		if str(s).begins_with(prefix):
			return true
	return false


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
