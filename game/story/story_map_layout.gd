class_name MbStoryMapLayout
extends RefCounted

## Pure helpers over the client-only story-MAP layout file
## (res://story/story_maps.json): per-world background texture + normalized
## dot positions bound to catalog level_ids. The Story Map screen renders dots
## from this; the in-editor authoring tool (addons/story_map_editor) writes it.
##
## This is COSMETIC, client-only data — deliberately NOT in story_catalog.json
## (which is Remote-Config'd and would force a validator schema bump) and NOT in
## story_progress (server-authoritative, read-only client-side per the hard-wall
## ADR). Static functions only, mirroring MbStoryCatalog.

const BAKED_PATH := "res://story/story_maps.json"

# Reference the catalog helper by path rather than the MbStoryCatalog global so
# validate() works even where class_name globals aren't registered (headless).
const Catalog := preload("res://story/story_catalog.gd")


## The committed layout ({} if missing/corrupt).
static func load_baked() -> Dictionary:
	if not FileAccess.file_exists(BAKED_PATH):
		return {}
	var f := FileAccess.open(BAKED_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## The map entry for a world ({} when absent).
static func map_for_world(layout: Dictionary, world_id: String) -> Dictionary:
	var maps = layout.get("maps", {})
	if not (maps is Dictionary):
		return {}
	var m = (maps as Dictionary).get(world_id, {})
	return m if m is Dictionary else {}


## res:// path of the world's background texture ("" when none — caller falls
## back to the flat list).
static func texture_for_world(layout: Dictionary, world_id: String) -> String:
	return str(map_for_world(layout, world_id).get("texture", ""))


## Whether a world has a usable map (a non-empty texture path that loads).
static func has_map(layout: Dictionary, world_id: String) -> bool:
	var tex := texture_for_world(layout, world_id)
	return tex != "" and ResourceLoader.exists(tex)


## The world's dots (each {level_id, x, y}); skips malformed entries.
static func dots_for_world(layout: Dictionary, world_id: String) -> Array:
	var out: Array = []
	for d in map_for_world(layout, world_id).get("dots", []):
		if d is Dictionary and str(d.get("level_id", "")) != "":
			out.append(d)
	return out


## The dot bound to a level_id within a world ({} when none).
static func dot_for_level(layout: Dictionary, world_id: String, level_id: String) -> Dictionary:
	for d in dots_for_world(layout, world_id):
		if str(d.get("level_id", "")) == level_id:
			return d
	return {}


## Structural problems with a layout ([] == valid): every dot binds to a real
## catalog level, positions are in 0..1, and no level_id is placed twice within
## a world. Mirrors the editor's save-time validation.
static func validate(layout: Dictionary, catalog: Dictionary) -> Array:
	var problems: Array = []
	if int(layout.get("version", 0)) < 1:
		problems.append("version must be a positive integer")
	var known := {}
	for l in Catalog.ordered_levels(catalog):
		known[str(l.get("id", ""))] = true
	var maps = layout.get("maps", {})
	if not (maps is Dictionary):
		problems.append("maps must be an object")
		return problems
	for world_id in (maps as Dictionary).keys():
		var seen := {}
		for d in dots_for_world(layout, str(world_id)):
			var lid := str(d.get("level_id", ""))
			if not known.has(lid):
				problems.append("%s: unknown level_id" % lid)
			if seen.has(lid):
				problems.append("%s: duplicate dot" % lid)
			seen[lid] = true
			var x := float(d.get("x", -1.0))
			var y := float(d.get("y", -1.0))
			if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
				problems.append("%s: position out of 0..1" % lid)
	return problems
