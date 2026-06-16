extends SceneTree

## Headless verifier for StoryMapService — the now-testable Story Map authoring
## logic, exercised WITHOUT the editor (the migration's primary payoff):
##   godot --headless --path . --script res://tools/verify_story_map_service.gd
## Covers load, catalog mutations (add/remove world+level via MbCatalogEdit),
## dot place/move/remove + snapping + near-last clamping, validate() catching
## bad layouts, byte-identical serialize round-trips (baked + canonical + layout),
## and the 3-target save with a forced-write-failure version-bump rollback.
## Writes only to a temp dir — never the committed content.

const ServiceT := preload("res://addons/story_map_editor/story_map_service.gd")
const Catalog := preload("res://story/story_catalog.gd")
const Layout := preload("res://story/story_map_layout.gd")

var _ok := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var svc: Node = ServiceT.new()
	root.add_child(svc)

	# ── load ──────────────────────────────────────────────────────────────────
	svc.reload()
	_check("catalog loaded", not svc.catalog.is_empty())
	_check("reload picks the first world (w1)", svc.world_id == "w1")
	_check("layout has maps", svc.layout.get("maps") is Dictionary)
	_check("committed content validates clean", svc.validate() == [])

	# ── catalog mutations ──────────────────────────────────────────────────────
	var w0 := Catalog.ordered_worlds(svc.catalog).size()
	svc.clear_dirty()
	var w: Dictionary = svc.add_world()
	var wid := str(w.get("id", ""))
	_check("add_world appends + suggests an id",
		Catalog.ordered_worlds(svc.catalog).size() == w0 + 1 and wid != "")
	_check("add_world marks the catalog dirty", svc.is_dirty())
	var l: Dictionary = svc.add_level(wid)
	var lid := str(l.get("id", ""))
	_check("add_level returns a level in the world", lid != "" and svc.get_level(wid, lid).size() > 0)
	var nd: Dictionary = svc.dot_by_id(wid, lid)
	_check("add_level drops a dot near last (default 0.5,0.12)",
		_near(nd.get("x"), 0.5) and _near(nd.get("y"), 0.12))
	svc.remove_level(wid, lid)
	_check("remove_level drops the level", svc.get_level(wid, lid).is_empty())
	_check("remove_level cascades the map dot", svc.dot_by_id(wid, lid).is_empty())
	var removed: Array = svc.remove_world(wid)
	_check("remove_world removes the world", Catalog.ordered_worlds(svc.catalog).size() == w0)
	_check("remove_world erases its map entry", not (svc.layout["maps"] as Dictionary).has(wid))
	_check("remove_world re-points away from the deleted world", svc.world_id != wid)

	# ── dot place / move / remove + snapping ───────────────────────────────────
	svc.reload()
	svc.move_dot("w1", "w1_l1", 0.12349, 0.98765)
	var d: Dictionary = svc.dot_by_id("w1", "w1_l1")
	_check("move_dot snaps to 0.001", _near(d.get("x"), 0.123) and _near(d.get("y"), 0.988))
	svc.remove_dot("w1", "w1_l1")
	_check("remove_dot removes the dot", svc.dot_by_id("w1", "w1_l1").is_empty())
	svc.place_dot("w1", "w1_l1", 0.5006, 0.4004)
	var d2: Dictionary = svc.dot_by_id("w1", "w1_l1")
	_check("place_dot snaps to 0.001", _near(d2.get("x"), 0.501) and _near(d2.get("y"), 0.4))

	# ── add_dot_near_last clamps the offset into 0..1 ──────────────────────────
	svc.reload()
	var nw: Dictionary = svc.add_world()
	var nwid := str(nw.get("id", ""))
	var nl: Dictionary = svc.add_level(nwid)               # first dot at (0.5, 0.12)
	svc.move_dot(nwid, str(nl.get("id", "")), 0.99, 0.99)  # push it to the edge
	var nl2: Dictionary = svc.add_level(nwid)              # near-last would be 1.04 → clamped 1.0
	var d3: Dictionary = svc.dot_by_id(nwid, str(nl2.get("id", "")))
	_check("add_dot_near_last clamps to <= 1.0", _near(d3.get("x"), 1.0) and _near(d3.get("y"), 1.0))

	# ── validate() catches bad layouts ─────────────────────────────────────────
	svc.reload()
	svc.layout = {"version": 1, "maps": {"w1": {"dots": [{"level_id": "nope", "x": 0.5, "y": 0.5}]}}}
	_check("validate flags unknown level_id", svc.validate().has("nope: unknown level_id"))
	svc.layout = {"version": 1, "maps": {"w1": {"dots": [
		{"level_id": "w1_l1", "x": 0.5, "y": 0.5}, {"level_id": "w1_l1", "x": 0.6, "y": 0.6}]}}}
	_check("validate flags duplicate dot", svc.validate().has("w1_l1: duplicate dot"))
	svc.layout = {"version": 1, "maps": {"w1": {"dots": [{"level_id": "w1_l1", "x": 1.5, "y": 0.5}]}}}
	_check("validate flags out-of-0..1 position", svc.validate().has("w1_l1: position out of 0..1"))

	# ── serialize round-trips to a byte-identical baked + canonical pair ────────
	svc.reload()
	var baked := FileAccess.get_file_as_string(Catalog.BAKED_PATH)
	var canonical := FileAccess.get_file_as_string(svc._repo_path(svc.CANONICAL_REL))
	var layout_baked := FileAccess.get_file_as_string(Layout.BAKED_PATH)
	_check("serialize_catalog == committed baked", svc.serialize_catalog() == baked)
	_check("serialize_catalog == committed canonical", svc.serialize_catalog() == canonical)
	_check("committed baked == canonical (byte-identical)", baked == canonical)
	_check("serialize_layout == committed story_maps.json", svc.serialize_layout() == layout_baked)

	# ── save_to writes all 3 targets + rolls back the bump on write failure ─────
	var tmp := OS.get_cache_dir().path_join("sms_verify")
	DirAccess.make_dir_recursive_absolute(tmp)
	var tc := tmp.path_join("catalog.json")
	var tcan := tmp.path_join("canonical.json")
	var tl := tmp.path_join("layout.json")
	for p in [tc, tcan, tl]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	svc.reload()
	svc.mark_dirty()   # simulate a catalog edit so the version bumps on save
	var v0 := int(svc.catalog.get("catalog_version", 1))
	var r: Dictionary = svc.save_to(tc, tcan, tl, false)
	_check("save_to succeeds", r.get("ok", false))
	_check("save_to bumped the dirty catalog's version",
		r.get("bumped", false) and int(svc.catalog["catalog_version"]) == v0 + 1)
	_check("save_to wrote all 3 targets",
		FileAccess.file_exists(tc) and FileAccess.file_exists(tcan) and FileAccess.file_exists(tl))
	_check("save_to baked + canonical are byte-identical",
		FileAccess.get_file_as_string(tc) == FileAccess.get_file_as_string(tcan))

	svc.reload()
	svc.mark_dirty()
	var v1 := int(svc.catalog.get("catalog_version", 1))
	var rf: Dictionary = svc.save_to("/sms_nonexistent_dir_zzz/catalog.json", tcan, tl, false)
	_check("save_to fails on an unwritable path",
		not rf.get("ok", true) and str(rf.get("stage", "")) == "write")
	_check("a failed save rolls back the version bump", int(svc.catalog["catalog_version"]) == v1)

	svc.queue_free()
	print("VERIFY story_map_service: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _near(a, b: float) -> bool:
	return a != null and absf(float(a) - b) < 1e-6


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
