@tool
class_name DailyMissionsService
extends "res://addons/editor_tool_kit/tool_service.gd"

## Headless-testable core for the Daily Missions authoring tool (a ToolService).
## Authors the SINGLE committed file validator/content/daily_missions.json — the
## Remote Config block the runtime reads live (no baked res:// copy: Daily Missions
## is NOT in the determinism/parity domain, so unlike the story catalog there is no
## byte-identical client copy to keep in sync). The Remote Config editor tool
## aggregates this blob into the published app-config document.
##
## Owns the in-memory block, mission CRUD (with rename cascade), the weekday
## rotation, validate(), a canonical serialize(), and a one-target save() with a
## version-bump rollback via ContentStore. No Control / EditorInterface refs.

const ContentStore := preload("res://addons/editor_tool_kit/content_store.gd")
## The shared headless model owns the one allowed-icon set (ICON_GLYPHS / icon_names).
const Model := preload("res://ui/screens/daily_missions_model.gd")

const CANONICAL_REL := "validator/content/daily_missions.json"
const FIELDS := ["title", "icon", "desc", "reward"]

## Emitted after any structural change so the dock rebuilds tree + anchor + grid.
## (The dock deliberately does NOT rebuild the edit form on this, so typing in a
## field is never interrupted — same discipline as the Story Map dock.)
signal changed

var block: Dictionary = {}


# ── load ───────────────────────────────────────────────────────────────────────


func reload() -> void:
	reload_from(_repo_path(CANONICAL_REL))


## Load core, parameterized by path so the headless verifier drives a temp dir.
func reload_from(path: String) -> void:
	block = ContentStore.load_json(path)
	if block.is_empty():
		block = {"enabled": false, "version": 1, "anchor": "", "by_weekday": {}, "catalog": {}}
	if not (block.get("by_weekday") is Dictionary):
		block["by_weekday"] = {}
	for d in range(7):
		var k := str(d)
		if not (block["by_weekday"].get(k) is Array):
			block["by_weekday"][k] = []
	if not (block.get("catalog") is Dictionary):
		block["catalog"] = {}
	clear_dirty()


# ── catalog reads ────────────────────────────────────────────────────────────--


## Sorted catalog ids (drives the tree, the anchor picker, the rotation chips, and
## the provisioning readout).
func mission_ids() -> Array:
	var keys: Array = (block.get("catalog", {}) as Dictionary).keys()
	keys.sort()
	return keys


## A mission's display fields with safe fallbacks (reuses the runtime model shape).
func get_mission(id: String) -> Dictionary:
	return Model.catalog_entry(block, id)


# ── catalog mutations (all mark dirty + emit `changed`) ──────────────────────────


## Add a fresh mission with a unique placeholder id. Returns {id}.
func add_mission() -> Dictionary:
	var catalog: Dictionary = block["catalog"]
	var id := "mission_new"
	var n := 1
	while catalog.has(id):
		n += 1
		id = "mission_new_%d" % n
	catalog[id] = {"title": "New Mission", "icon": "cards", "desc": "", "reward": "0 coins"}
	mark_dirty(); changed.emit()
	return {"id": id}


## Remove a mission and cascade it out of every weekday + the anchor.
func remove_mission(id: String) -> void:
	(block["catalog"] as Dictionary).erase(id)
	for d in range(7):
		(block["by_weekday"][str(d)] as Array).erase(id)
	if str(block.get("anchor", "")) == id:
		block["anchor"] = ""
	mark_dirty(); changed.emit()


## Rename a mission id (globally unique). Cascades the catalog key, every weekday
## array, and the anchor so no dangling id survives. Returns {ok:true,new_id} or
## err on an empty/colliding id (the dock reverts the field).
func rename_mission(old_id: String, raw: String) -> Dictionary:
	var new_id := raw.strip_edges()
	if new_id == old_id:
		return ok({"new_id": old_id})
	var catalog: Dictionary = block["catalog"]
	if new_id == "" or catalog.has(new_id):
		return err("Mission id '%s' is empty or already used — keeping '%s'." % [new_id, old_id])
	if not catalog.has(old_id):
		return err("Unknown mission '%s'." % old_id)
	catalog[new_id] = catalog[old_id]
	catalog.erase(old_id)
	for d in range(7):
		var arr: Array = block["by_weekday"][str(d)]
		for i in range(arr.size()):
			if str(arr[i]) == old_id:
				arr[i] = new_id
	if str(block.get("anchor", "")) == old_id:
		block["anchor"] = new_id
	mark_dirty(); changed.emit()
	return ok({"new_id": new_id})


## Set one display field (title/icon/desc/reward) of a mission.
func set_mission_field(id: String, key: String, value) -> void:
	if not FIELDS.has(key):
		return
	var catalog: Dictionary = block["catalog"]
	if not (catalog.get(id) is Dictionary):
		return
	catalog[id][key] = value
	mark_dirty(); changed.emit()


# ── rotation mutations ──────────────────────────────────────────────────────────


func set_anchor(id: String) -> void:
	block["anchor"] = id   # "" clears the anchor
	mark_dirty(); changed.emit()


func set_enabled(on: bool) -> void:
	block["enabled"] = on
	mark_dirty(); changed.emit()


## The live ids array for a weekday (0=Sun .. 6=Sat).
func weekday_ids(wd: int) -> Array:
	return block["by_weekday"][str(wd)]


func add_weekday(wd: int, id: String) -> void:
	var arr: Array = block["by_weekday"][str(wd)]
	if not arr.has(id):
		arr.append(id)
		mark_dirty(); changed.emit()


func remove_weekday(wd: int, id: String) -> void:
	(block["by_weekday"][str(wd)] as Array).erase(id)
	mark_dirty(); changed.emit()


# ── validation / serialization ──────────────────────────────────────────────────


## Problems with the block. Hard errors block save(); "warning:"-prefixed entries
## are advisory (empty weekday, unused mission) and do not block save.
func validate() -> Array:
	var problems: Array = []
	var catalog: Dictionary = block.get("catalog", {})
	var anchor := str(block.get("anchor", ""))
	var referenced := {}
	if anchor != "":
		referenced[anchor] = true
		if not catalog.has(anchor):
			problems.append("anchor: unknown mission \"%s\"" % anchor)
	for d in range(7):
		var arr: Array = block.get("by_weekday", {}).get(str(d), [])
		if arr.is_empty():
			problems.append("warning: weekday %d has no missions" % d)
		for id in arr:
			referenced[str(id)] = true
			if not catalog.has(str(id)):
				problems.append("weekday %d: unknown mission \"%s\"" % [d, str(id)])
	var allowed := Model.icon_names()
	for id in catalog:
		if not (catalog[id] is Dictionary):
			problems.append("%s: catalog entry is not a JSON object" % str(id))
			continue
		var m: Dictionary = catalog[id]
		if not allowed.has(str(m.get("icon", ""))):
			problems.append("%s: invalid icon \"%s\" (allowed: %s)" % [str(id), str(m.get("icon", "")), ", ".join(allowed)])
		if str(m.get("reward", "")).strip_edges() == "":
			problems.append("%s: empty reward" % str(id))
		if not referenced.has(str(id)):
			problems.append("warning: %s is used by neither the anchor nor any weekday" % str(id))
	return problems


## The hard errors only (warnings filtered out) — the save gate.
func _errors() -> Array:
	return validate().filter(func(p): return not str(p).begins_with("warning:"))


## Canonical JSON: a fixed key order (enabled, version, anchor, by_weekday with
## string keys "0".."6" in order, catalog with sorted ids each {title,icon,desc,
## reward}), version int-coerced, trailing newline — so repeated saves of unchanged
## content are byte-identical. (sort_keys=false: insertion order is authoritative.)
func serialize() -> String:
	var by_weekday := {}
	for d in range(7):
		var ids: Array = []
		for id in block.get("by_weekday", {}).get(str(d), []):
			ids.append(str(id))
		by_weekday[str(d)] = ids
	var catalog := {}
	for id in mission_ids():
		var raw = (block.get("catalog", {}) as Dictionary).get(id, {})
		var m: Dictionary = raw if raw is Dictionary else {}
		catalog[id] = {
			"title": str(m.get("title", "")),
			"icon": str(m.get("icon", "")),
			"desc": str(m.get("desc", "")),
			"reward": str(m.get("reward", "")),
		}
	var out := {
		"enabled": bool(block.get("enabled", false)),
		"version": int(block.get("version", 1)),
		"anchor": str(block.get("anchor", "")),
		"by_weekday": by_weekday,
		"catalog": catalog,
	}
	return JSON.stringify(out, "  ", false) + "\n"


# ── save ─────────────────────────────────────────────────────────────────────--


## Persist to the single canonical target. Auto-bumps version when the block
## changed (is_dirty), rolling the bump back on a write failure. Returns one of:
##   {ok:false, stage:"validate", problems:[...]}
##   {ok:false, stage:"write", error:String}
##   {ok:true, bumped:bool, version:int}
func save() -> Dictionary:
	return save_to(_repo_path(CANONICAL_REL))


func save_to(path: String, scan := true) -> Dictionary:
	var errs := _errors()
	if not errs.is_empty():
		return {"ok": false, "stage": "validate", "problems": errs}
	var bumped := is_dirty()
	var result := ContentStore.bump_then(block, "version",
		func() -> Dictionary:
			return ContentStore.save_all([{"path": path, "text": serialize()}],
				func() -> Array: return [], scan),
		bumped)
	if not result.get("ok", false):
		return {"ok": false, "stage": "write", "error": str(result.get("error", "write failed"))}
	clear_dirty()
	return {"ok": true, "bumped": bumped, "version": int(block.get("version", 1))}


## Newline-joined canonical mission ids — copied to the clipboard so the operator
## can provision matching Quests in the Snapser console (no Quest write API).
func canonical_id_readout() -> String:
	return "\n".join(mission_ids())


# ── helpers ──────────────────────────────────────────────────────────────────--


static func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(rel)
