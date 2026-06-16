@tool
class_name StoryMapService
extends "res://addons/editor_tool_kit/tool_service.gd"

## Headless-testable core for the Story Map authoring tool (a ToolService). Owns
## the in-memory catalog + layout and the current world, all mutations (delegating
## to MbCatalogEdit + a normalized layout), validation, canonical serialization,
## the 3-file atomic save (baked + canonical catalog, byte-identical, + the
## client-only layout) via ContentStore with a catalog_version-bump rollback, and
## the Remote Config verify / publish-payload helpers. The dock is a thin view
## that calls these and re-renders on `changed`.
##
## catalog_edit.gd / story_catalog.gd / story_map_layout.gd stay the pure static
## utilities this service calls.
##
## The dirty flag (mark_dirty / is_dirty) means "the CATALOG changed since load"
## and gates the catalog_version bump on save — dot/layout edits change the
## (always-saved) layout but do NOT bump the catalog, so they don't mark dirty.

const Catalog := preload("res://story/story_catalog.gd")
const Layout := preload("res://story/story_map_layout.gd")
const CatalogEdit := preload("res://addons/story_map_editor/catalog_edit.gd")
const ContentStore := preload("res://addons/editor_tool_kit/content_store.gd")

## Repo-relative path of the canonical (validator/content) catalog copy.
const CANONICAL_REL := "validator/content/story_catalog.json"

## Emitted after a structural change (world/level add/remove, field/goal/reward
## edit, dot place/remove/clear) so the dock rebuilds world picker + tree +
## markers. NOT emitted for a dot DRAG (move_dot) or a texture set — those are
## view-coupled and the dock updates the affected node itself — nor for reload /
## select_world, where the dock drives the full view setup.
signal changed

var catalog: Dictionary = {}
var layout: Dictionary = {}
var world_id := ""   # the world the dock is currently showing (model state: dots
                     #  are per-world, and remove must re-point it consistently)


# ── load ──────────────────────────────────────────────────────────────────────


## Load the committed catalog + layout, normalize the layout shape, clear dirty,
## and point world_id at the first world. The dock drives the full view rebuild
## afterward (no `changed` here, so render never runs against a half-set view).
func reload() -> void:
	catalog = ContentStore.load_json(Catalog.BAKED_PATH)
	layout = ContentStore.load_json(Layout.BAKED_PATH)
	if layout.is_empty():
		layout = {"version": 1, "maps": {}}
	if not (layout.get("maps") is Dictionary):
		layout["maps"] = {}
	clear_dirty()
	var worlds := Catalog.ordered_worlds(catalog)
	world_id = str(worlds[0].get("id", "")) if not worlds.is_empty() else ""


## Switch the active world (creating its map entry, mirroring the pre-migration
## load path so empty entries are authored exactly as before). View-coupled: the
## dock updates the canvas + re-renders, so no `changed`.
func select_world(wid: String) -> void:
	world_id = wid
	if wid != "":
		world_map(wid)


# ── layout accessors ──────────────────────────────────────────────────────────


## The map entry for a world, creating it ({texture:"", dots:[]}) if absent.
func world_map(wid: String) -> Dictionary:
	var maps: Dictionary = layout["maps"]
	if not (maps.get(wid) is Dictionary):
		maps[wid] = {"texture": "", "dots": []}
	var m: Dictionary = maps[wid]
	if not (m.get("dots") is Array):
		m["dots"] = []
	return m


## The world's live dots array (creates the entry — used by render/placement,
## which only run for a valid current world).
func dots_for_world(wid: String) -> Array:
	return world_map(wid)["dots"]


## Non-creating dots read (for cascades/rename — never resurrects a map entry).
func _dots_ro(wid: String) -> Array:
	var maps = layout.get("maps", {})
	var m = maps.get(wid, {}) if maps is Dictionary else {}
	return m.get("dots", []) if (m is Dictionary and m.get("dots") is Array) else []


func texture_for(wid: String) -> String:
	return str(world_map(wid).get("texture", ""))


# ── catalog reads (the form binds to these; writes go through set_*) ───────────


func get_world(wid: String) -> Dictionary:
	return CatalogEdit.get_world(catalog, wid)


func get_level(wid: String, lid: String) -> Dictionary:
	return CatalogEdit.get_level(catalog, wid, lid)


func dot_by_id(wid: String, lid: String) -> Dictionary:
	for d in dots_for_world(wid):
		if str(d.get("level_id", "")) == lid:
			return d
	return {}


# ── placement / drag helpers ──────────────────────────────────────────────────


func world_level_ids(wid: String) -> Array:
	var out: Array = []
	for l in Catalog.ordered_levels(catalog):
		if str(l.get("world_id", "")) == wid:
			out.append(str(l.get("id", "")))
	return out


func placed_ids(wid: String) -> Dictionary:
	var seen := {}
	for d in dots_for_world(wid):
		seen[str(d.get("level_id", ""))] = true
	return seen


func next_unplaced(wid: String) -> String:
	var placed := placed_ids(wid)
	for lid in world_level_ids(wid):
		if not placed.has(lid):
			return lid
	return ""


func level_in_world(wid: String, lid: String) -> bool:
	return world_level_ids(wid).has(lid)


# ── layout mutations ──────────────────────────────────────────────────────────


## Texture is layout (no version bump) and view-coupled (the dock loads it into
## the canvas), so this is quiet — the dock re-renders.
func set_texture(wid: String, path: String) -> void:
	world_map(wid)["texture"] = path


func place_dot(wid: String, lid: String, x: float, y: float) -> void:
	dots_for_world(wid).append({
		"level_id": lid, "x": snappedf(x, 0.001), "y": snappedf(y, 0.001)})
	changed.emit()


## Drag: update a dot's position only. Quiet (no `changed`) so the dock can move
## the marker node in place without a rebuild mid-drag.
func move_dot(wid: String, lid: String, x: float, y: float) -> void:
	var d := dot_by_id(wid, lid)
	if d.is_empty():
		return
	d["x"] = snappedf(x, 0.001)
	d["y"] = snappedf(y, 0.001)


func remove_dot(wid: String, lid: String) -> void:
	var dots := dots_for_world(wid)
	for i in range(dots.size()):
		if str(dots[i].get("level_id", "")) == lid:
			dots.remove_at(i)
			break
	changed.emit()


func clear_world_dots(wid: String) -> void:
	world_map(wid)["dots"] = []
	changed.emit()


## Drop a dot for `lid` offset from the last existing dot (or a default for the
## first), so a newly added level appears on the map without a manual click.
## Internal helper (the public caller emits `changed`). No-op if already placed.
func _add_dot_near_last(wid: String, lid: String) -> void:
	var dots: Array = world_map(wid)["dots"]
	for d in dots:
		if str(d.get("level_id", "")) == lid:
			return
	var pos := Vector2(0.5, 0.12)
	if not dots.is_empty():
		var last: Dictionary = dots[dots.size() - 1]
		pos = Vector2(
			clampf(float(last.get("x", 0.5)) + 0.05, 0.0, 1.0),
			clampf(float(last.get("y", 0.12)) + 0.05, 0.0, 1.0))
	dots.append({"level_id": lid, "x": snappedf(pos.x, 0.001), "y": snappedf(pos.y, 0.001)})


# ── catalog mutations (all mark the catalog dirty + emit `changed`) ────────────


func add_world() -> Dictionary:
	var w: Dictionary = CatalogEdit.add_world(catalog)
	mark_dirty()
	changed.emit()
	return w


## Add a level to a world AND drop its map dot near the last (the pre-migration
## flow). Returns the new level, or {} for an unknown world.
func add_level(wid: String) -> Dictionary:
	var l: Dictionary = CatalogEdit.add_level(catalog, wid)
	if l.is_empty():
		return {}
	_add_dot_near_last(wid, str(l.get("id", "")))
	mark_dirty()
	changed.emit()
	return l


## Remove a level and cascade-delete its map dot (so the layout doesn't orphan).
func remove_level(wid: String, lid: String) -> void:
	CatalogEdit.remove_level(catalog, wid, lid)
	var dots := _dots_ro(wid)
	for i in range(dots.size()):
		if str(dots[i].get("level_id", "")) == lid:
			dots.remove_at(i)
			break
	mark_dirty()
	changed.emit()


## Remove a world (and its map entry + dots). Re-points world_id to a surviving
## world (or "") when the active world is the one removed, so a follow-up render
## can't resurrect the deleted entry. Returns the removed level ids.
func remove_world(wid: String) -> Array:
	var removed: Array = CatalogEdit.remove_world(catalog, wid)
	if layout.get("maps") is Dictionary:
		(layout["maps"] as Dictionary).erase(wid)
	if wid == world_id:
		var worlds := Catalog.ordered_worlds(catalog)
		world_id = str(worlds[0].get("id", "")) if not worlds.is_empty() else ""
	mark_dirty()
	changed.emit()
	return removed


func set_world_field(wid: String, key: String, value) -> void:
	CatalogEdit.set_world_field(catalog, wid, key, value)
	mark_dirty()
	changed.emit()


func set_level_field(wid: String, lid: String, key: String, value) -> void:
	CatalogEdit.set_level_field(catalog, wid, lid, key, value)
	mark_dirty()
	changed.emit()


func set_goal(wid: String, lid: String, idx: int, goal: Dictionary) -> void:
	CatalogEdit.set_goal(catalog, wid, lid, idx, goal)
	mark_dirty()
	changed.emit()


func set_reward(wid: String, lid: String, where: String, amounts: Dictionary) -> void:
	CatalogEdit.set_reward(catalog, wid, lid, where, amounts)
	mark_dirty()
	changed.emit()


## Rename a level id (globally unique), migrating its map dot's level_id so the
## layout doesn't orphan. Returns {ok:true, new_id} or {ok:false, error} on an
## empty / colliding id (the dock reverts the field + restores the form).
func rename_level(wid: String, old_id: String, raw: String) -> Dictionary:
	var new_id := raw.strip_edges()
	if new_id == old_id:
		return ok({"new_id": old_id})
	if new_id == "" or not CatalogEdit.is_level_id_unique(catalog, new_id, old_id):
		return err("Level id '%s' is empty or already used — keeping '%s'." % [new_id, old_id])
	CatalogEdit.set_level_field(catalog, wid, old_id, "id", new_id)
	for d in _dots_ro(wid):
		if str(d.get("level_id", "")) == old_id:
			d["level_id"] = new_id
	mark_dirty()
	changed.emit()
	return ok({"new_id": new_id})


# ── validation / serialization ─────────────────────────────────────────────────


## Structural problems with the catalog + layout ([] == valid).
func validate() -> Array:
	return Catalog.validate(catalog) + Layout.validate(layout, catalog)


func serialize_catalog() -> String:
	return CatalogEdit.serialize(catalog)


## A stable, normalized copy of the layout for serialization: integer `version`
## (JSON round-tripping otherwise promotes it to 1.0), a fixed key order
## (version, maps; per world texture, dots; per dot level_id, x, y), and dot
## coordinates snapped to 0.001 — so saves produce clean, churn-free diffs.
func _normalized_layout() -> Dictionary:
	var maps_in: Dictionary = layout.get("maps", {})
	var maps_out := {}
	for wid in maps_in:
		var m: Dictionary = maps_in[wid]
		var dots_out: Array = []
		for d in m.get("dots", []):
			dots_out.append({
				"level_id": str(d.get("level_id", "")),
				"x": snappedf(float(d.get("x", 0.0)), 0.001),
				"y": snappedf(float(d.get("y", 0.0)), 0.001),
			})
		maps_out[wid] = {"texture": str(m.get("texture", "")), "dots": dots_out}
	return {"version": int(layout.get("version", 1)), "maps": maps_out}


func serialize_layout() -> String:
	return JSON.stringify(_normalized_layout(), "  ", false) + "\n"


# ── save ───────────────────────────────────────────────────────────────────────


## One save persists everything: the catalog to both the baked (res://) and the
## canonical (validator/content) copies — byte-identical, same serializer — and
## the dot layout. Auto-bumps catalog_version when the catalog changed, rolling
## the bump back on any write failure. Validates catalog then layout first, with
## distinct results so the dock can show the exact pre-migration messages.
## Returns one of:
##   {ok:false, stage:"catalog"|"layout", problems:[...]}
##   {ok:false, stage:"write", error:String}
##   {ok:true, bumped:bool, version:int}
func save() -> Dictionary:
	return save_to(Catalog.BAKED_PATH, _repo_path(CANONICAL_REL), Layout.BAKED_PATH)


## The save core, parameterized by output paths so a headless verifier can drive
## it against a temp dir (and force a write failure) without touching the
## committed files. The public save() binds the real baked/canonical/layout paths.
func save_to(catalog_path: String, canonical_path: String, layout_path: String, scan := true) -> Dictionary:
	var cat_problems: Array = Catalog.validate(catalog)
	if not cat_problems.is_empty():
		return {"ok": false, "stage": "catalog", "problems": cat_problems}
	var layout_problems: Array = Layout.validate(layout, catalog)
	if not layout_problems.is_empty():
		return {"ok": false, "stage": "layout", "problems": layout_problems}

	var bumped := is_dirty()
	# bump_then bumps catalog_version BEFORE serializing (so the written bytes
	# carry the new version) and rolls it back if any of the 3 writes fail, so a
	# retry recomputes the same version. We already validated, so save_all's gate
	# is a defensive [] (it never re-blocks here).
	var result := ContentStore.bump_then(catalog, "catalog_version",
		func() -> Dictionary:
			var catalog_text := CatalogEdit.serialize(catalog)
			var layout_text := serialize_layout()
			return ContentStore.save_all([
				{"path": catalog_path, "text": catalog_text},
				{"path": canonical_path, "text": catalog_text},
				{"path": layout_path, "text": layout_text},
			], func() -> Array: return [], scan),
		bumped)
	if not result.get("ok", false):
		return {"ok": false, "stage": "write", "error": str(result.get("error", "write failed"))}
	clear_dirty()
	return {"ok": true, "bumped": bumped, "version": int(catalog.get("catalog_version", 1))}


# ── Catalog ⇄ Remote Config ──────────────────────────────────────────────────


## Reuse the canonical TS comparator instead of reimplementing it: shell out to
## `bun tools/story-appconfig.ts verify`, which anon-logs in, GETs the live
## app-config, and deep-compares it to the committed catalog. Blocking; the dock
## formats the result. Returns {ok, committed, code, text}; code -1 = bun missing.
func check_catalog_sync() -> Dictionary:
	var committed := int(Catalog.load_baked().get("catalog_version", 0))
	var script := _repo_path("validator/src/validator/tools/story-appconfig.ts")
	var out: Array = []
	var code := OS.execute("bun", [script, "verify"], out, true)
	var text := "\n".join(out).strip_edges() if out.size() > 0 else ""
	return {"ok": code == 0, "committed": committed, "code": code, "text": text}


## Put the exact {"story_catalog": <committed>} JSON on the clipboard for a manual
## paste into the Snapser console (Remote Config has no write API). Returns
## {ok:true, version} or {ok:false, error} when no committed catalog exists.
func copy_publish_payload() -> Dictionary:
	var cat := Catalog.load_baked()
	if cat.is_empty():
		return err("No committed catalog found.")
	DisplayServer.clipboard_set(JSON.stringify({"story_catalog": cat}, "  "))
	return ok({"version": int(cat.get("catalog_version", 0))})


# ── helpers ────────────────────────────────────────────────────────────────────


static func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(rel)
