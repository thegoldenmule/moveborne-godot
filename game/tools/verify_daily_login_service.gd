extends SceneTree

## Headless verifier for DailyLoginService — the Daily Login Bonus authoring logic,
## exercised WITHOUT the editor:
##   godot --headless --path . --script res://tools/verify_daily_login_service.gd
## Covers load/defaults, calendar CRUD (add/remove + renumber), set_cycle_length,
## validate() positive/negative (currency allow-set, amount>0, duplicate +
## non-contiguous days), serialize() round-trip stability, the single-target save
## with a forced-write-failure version-bump rollback, and the provisioning readout.
## Writes only to a temp dir.

const ServiceT := preload("res://addons/daily_login_editor/daily_login_service.gd")
const Model := preload("res://ui/screens/daily_login_model.gd")

var _ok := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var svc: Node = ServiceT.new()
	root.add_child(svc)

	var tmp := OS.get_cache_dir().path_join("dl_verify")
	DirAccess.make_dir_recursive_absolute(tmp)
	var missing := tmp.path_join("nope_daily_login.json")
	if FileAccess.file_exists(missing):
		DirAccess.remove_absolute(missing)

	# ── load / defaults ──────────────────────────────────────────────────────────
	svc.reload_from(missing)
	_check("absent file -> disabled default", not bool(svc.block.get("enabled", true)))
	_check("default version 1", int(svc.block.get("version", 0)) == 1)
	_check("default calendar empty", (svc.block.get("calendar", []) as Array).is_empty())
	_check("not dirty after reload", not svc.is_dirty())

	# ── calendar CRUD ────────────────────────────────────────────────────────────
	var d1 := int(svc.add_day().get("day", 0))
	_check("add_day returns day 1", d1 == 1)
	_check("add_day marks dirty", svc.is_dirty())
	var d2 := int(svc.add_day().get("day", 0))
	var d3 := int(svc.add_day().get("day", 0))
	_check("subsequent adds are contiguous", d2 == 2 and d3 == 3)
	_check("cycle_length tracks calendar size", int(svc.block.get("cycle_length_days", 0)) == 3)
	svc.set_day_field(1, "currency", "gems")
	svc.set_day_field(1, "amount", 25)
	_check("set_day_field writes currency + amount",
		str(svc.get_day(1).get("currency", "")) == "gems" and int(svc.get_day(1).get("amount", 0)) == 25)

	# remove the middle day -> the rest renumber to stay contiguous 1..N
	svc.set_day_field(3, "amount", 99)
	svc.remove_day(2)
	_check("remove_day renumbers to contiguous", svc.days() == [1, 2])
	_check("remove_day keeps the survivor's data (old day 3 -> day 2)",
		int(svc.get_day(2).get("amount", 0)) == 99)
	_check("cycle_length follows a removal", int(svc.block.get("cycle_length_days", 0)) == 2)

	# set_cycle_length grows then shrinks
	svc.set_cycle_length(5)
	_check("set_cycle_length grows the calendar", svc.days() == [1, 2, 3, 4, 5])
	svc.set_cycle_length(3)
	_check("set_cycle_length shrinks the calendar", svc.days() == [1, 2, 3])

	# ── validate: positive ───────────────────────────────────────────────────────
	svc.block = {"enabled": true, "version": 1, "cycle_length_days": 2, "reset_on_miss": false,
		"calendar": [
			{"day": 1, "currency": "coins", "amount": 50},
			{"day": 2, "currency": "gems", "amount": 20}]}
	_check("a clean calendar has no hard errors", svc._errors() == [])

	# ── validate: negative ───────────────────────────────────────────────────────
	svc.block = {"enabled": true, "version": 1, "cycle_length_days": 3, "reset_on_miss": false,
		"calendar": [
			{"day": 1, "currency": "doubloons", "amount": 50},
			{"day": 2, "currency": "coins", "amount": 0},
			{"day": 4, "currency": "coins", "amount": 10}]}
	var errs: Array = svc._errors()
	_check("validate flags an invalid currency", _has_prefix(errs, "day 1: invalid currency"))
	_check("validate flags a non-positive amount", _has_prefix(errs, "day 2: amount must be > 0"))
	_check("validate flags a non-contiguous day", _has_substr(errs, "out of sequence"))
	# duplicate day
	svc.block["calendar"] = [
		{"day": 1, "currency": "coins", "amount": 50},
		{"day": 1, "currency": "coins", "amount": 60}]
	_check("validate flags a duplicate day", svc._errors().has("duplicate day 1"))
	# empty calendar
	svc.block["calendar"] = []
	_check("validate flags an empty calendar", _has_prefix(svc._errors(), "calendar is empty"))

	# ── currency allow-set ───────────────────────────────────────────────────────
	_check("CURRENCIES is coins/souls/gems",
		Model.CURRENCIES.has("coins") and Model.CURRENCIES.has("souls")
		and Model.CURRENCIES.has("gems") and Model.CURRENCIES.size() == 3)

	# ── serialize round-trip stability ──────────────────────────────────────────
	svc.block = {"enabled": true, "version": 2, "cycle_length_days": 3, "reset_on_miss": true,
		"calendar": [
			{"day": 2, "currency": "coins", "amount": 75},
			{"day": 1, "currency": "coins", "amount": 50},
			{"day": 3, "currency": "gems", "amount": 20}]}
	var s1: String = svc.serialize()
	var rt := tmp.path_join("rt.json")
	_write(rt, s1)
	svc.reload_from(rt)
	_check("serialize round-trips byte-identical", svc.serialize() == s1)
	var parsed = JSON.parse_string(s1)
	_check("serialize sorts calendar by day",
		[int(parsed["calendar"][0]["day"]), int(parsed["calendar"][1]["day"]), int(parsed["calendar"][2]["day"])] == [1, 2, 3])
	_check("serialize derives cycle_length from calendar", int(parsed["cycle_length_days"]) == 3)
	_check("serialize preserves reset_on_miss", bool(parsed["reset_on_miss"]))

	# ── save_to: success + bump, then a forced write-failure rollback ───────────
	var out := tmp.path_join("dl_out.json")
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
	var rf: Dictionary = svc.save_to("/dl_nonexistent_dir_zzz/x.json", false)
	_check("save_to fails on an unwritable path", not rf.get("ok", true) and str(rf.get("stage", "")) == "write")
	_check("a failed save rolls back the bump", int(svc.block["version"]) == v1)

	# ── save_to refuses an invalid block ────────────────────────────────────────
	svc.block["calendar"][0]["currency"] = "bogus"
	var ri: Dictionary = svc.save_to(out, false)
	_check("save_to blocks on validation errors", not ri.get("ok", true) and str(ri.get("stage", "")) == "validate")

	# ── provisioning readout ─────────────────────────────────────────────────────
	svc.block = {"enabled": true, "version": 1, "cycle_length_days": 2, "reset_on_miss": false,
		"calendar": [
			{"day": 1, "currency": "coins", "amount": 50},
			{"day": 2, "currency": "gems", "amount": 20}]}
	var ro: String = svc.provisioning_readout()
	_check("readout names the login_calendar ladder", ro.contains("login_calendar"))
	_check("readout has a ladder line per day",
		ro.contains("level 1  min_xp 1  reward coins 50") and ro.contains("level 2  min_xp 2  reward gems 20"))
	_check("readout names the daily_login quest", ro.contains("daily_login") and ro.contains("open_app"))

	svc.queue_free()
	print("VERIFY daily_login_service: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _has_prefix(arr: Array, prefix: String) -> bool:
	for s in arr:
		if str(s).begins_with(prefix):
			return true
	return false


func _has_substr(arr: Array, sub: String) -> bool:
	for s in arr:
		if str(s).contains(sub):
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
