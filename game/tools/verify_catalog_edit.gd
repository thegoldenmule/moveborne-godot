extends SceneTree

## Headless verifier for the in-editor catalog mutation + serialization helper:
##   godot --headless --path game --script res://tools/verify_catalog_edit.gd
##
## 1. Churn guard: MbCatalogEdit.serialize(load_baked()) reproduces the committed
##    story_catalog.json bytes exactly (so an editor save is a no-op diff and the
##    canonical + baked copies stay byte-identical).
## 2. Round-trip: mutate -> serialize -> reparse -> MbStoryCatalog.validate == [].
## 3. Ids: suggested ids are globally unique; existing ids are rejected.
## 4. Scenario integrity: every level's scenario_id resolves to a real scenario.
## Prints VERIFY catalog_edit: PASS/FAIL; exit 0/1.

const Catalog := preload("res://story/story_catalog.gd")
const Edit := preload("res://addons/story_map_editor/catalog_edit.gd")
const Scen := preload("res://logic/scenarios.gd")
const BAKED := "res://story/story_catalog.json"

var _ok := true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := Catalog.load_baked()
	_check("baked catalog loads", not catalog.is_empty())

	# 1. churn guard — serialize must reproduce the committed bytes exactly.
	var committed := FileAccess.get_file_as_string(BAKED)
	var serialized := Edit.serialize(catalog)
	var same := serialized == committed
	_check("serialize() reproduces committed bytes", same)
	if not same:
		print("  committed len=%d serialized len=%d" % [committed.length(), serialized.length()])
		var n: int = mini(committed.length(), serialized.length())
		for i in range(n):
			if committed[i] != serialized[i]:
				var a: int = maxi(0, i - 30)
				print("  first diff at %d:\n   committed: …%s…\n   serialized: …%s…" % [
					i, committed.substr(a, 60).c_escape(), serialized.substr(a, 60).c_escape()])
				break

	# 2. round-trip: mutate -> serialize -> reparse -> validate.
	var c2 := Catalog.load_baked()
	var w: Dictionary = Edit.add_world(c2)
	var l: Dictionary = Edit.add_level(c2, str(w.get("id", "")))
	Edit.set_level_field(c2, str(w.id), str(l.id), "name", "Probe Level")
	Edit.set_goal(c2, str(w.id), str(l.id), 0, {"type": "max_tile", "threshold": 128, "time_limit_s": 30})
	Edit.set_reward(c2, str(w.id), str(l.id), "per_star:2", {"gems": 2})
	var reparsed = JSON.parse_string(Edit.serialize(c2))
	_check("mutated catalog reparses", reparsed is Dictionary)
	_check("mutated catalog validates", Catalog.validate(reparsed) == [])
	_check("added world+level present", not Catalog.get_level(reparsed, str(l.id)).is_empty())

	# removal -> still valid, level gone.
	Edit.remove_level(c2, str(w.id), str(l.id))
	Edit.remove_world(c2, str(w.id))
	var after = JSON.parse_string(Edit.serialize(c2))
	_check("after removal validates", Catalog.validate(after) == [])
	_check("removed level is gone", Catalog.get_level(after, str(l.id)).is_empty())

	# 3. id uniqueness.
	var c3 := Catalog.load_baked()
	var lid: String = Edit.suggest_level_id(c3, "w1")
	_check("suggested level id is globally unique", Edit.is_level_id_unique(c3, lid))
	_check("existing level id rejected", not Edit.is_level_id_unique(c3, "w1_l1"))
	var wid: String = Edit.suggest_world_id(c3)
	_check("suggested world id is fresh", Catalog.ordered_worlds(c3).all(
		func(x): return str(x.get("id", "")) != wid))

	# 4. scenario integrity.
	var all_resolve := true
	for lvl in Catalog.ordered_levels(catalog):
		if Scen.get_scenario(int(lvl.get("scenario_id", 0))) == null:
			all_resolve = false
	_check("all level scenario_ids resolve", all_resolve)

	# 5. dock + service smoke — the dock is now a view over StoryMapService (the
	#    EditorToolPlugin injects the service). Inject it here, then _ready →
	#    _build_ui (tabs/tree/form) → _reload run without errors and the tree fills.
	var svc = preload("res://addons/story_map_editor/story_map_service.gd").new()
	var dock = preload("res://addons/story_map_editor/dock.gd").new()
	dock.service = svc
	root.add_child(svc)
	root.add_child(dock)
	await process_frame  # let _ready → _build_ui → _reload run
	var tree_root = dock._cat_tree.get_root() if dock._cat_tree != null else null
	_check("dock builds + catalog tree populated",
		tree_root != null and tree_root.get_child_count() == Catalog.ordered_worlds(catalog).size())

	# Adding a level via the dock auto-places a dot in that world (the dock calls
	# the service, which mutates + emits `changed`).
	dock._cat_sel = {"kind": "world", "world_id": "w1"}
	var dots_before: int = svc.dots_for_world("w1").size()
	dock._on_add_level()
	_check("add level auto-places a dot", svc.dots_for_world("w1").size() == dots_before + 1)

	dock.queue_free()
	svc.queue_free()

	print("VERIFY catalog_edit: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)
