@tool
class_name MbCatalogEdit
extends RefCounted

## Write-side helper for the story catalog — the mutation + serialization side
## the in-editor catalog authoring uses. Pure static functions (no FileAccess /
## scene deps) so it is headless-testable; MbStoryCatalog stays the read-only
## utility (validate / ordered lookups).
##
## serialize() is load-bearing: it must produce stable, canonical bytes so saves
## are churn-free and the canonical (validator/content) + baked (game/story)
## copies stay byte-identical. Godot's JSON.stringify defaults sort_keys=TRUE and
## round-trips ints to floats, so we build fresh ordered dicts and int()-coerce.

const Catalog := preload("res://story/story_catalog.gd")

const CURRENCIES := ["coins", "souls", "gems"]
const GOAL_TYPES := ["points", "max_tile"]


# ── templates / defaults ──────────────────────────────────────────────────────


static func default_goals() -> Array:
	return [
		{"type": "points", "threshold": 100, "time_limit_s": null},
		{"type": "points", "threshold": 200, "time_limit_s": null},
		{"type": "max_tile", "threshold": 64, "time_limit_s": null},
	]


static func default_rewards() -> Dictionary:
	return {"complete": {"coins": 0}, "per_star": [{"coins": 0}, {"coins": 0}, {"coins": 0}]}


static func new_world(catalog: Dictionary) -> Dictionary:
	return {
		"id": suggest_world_id(catalog),
		"name": "New World",
		"order": _next_world_order(catalog),
		"levels": [],
	}


static func new_level(catalog: Dictionary, world_id: String) -> Dictionary:
	return {
		"id": suggest_level_id(catalog, world_id),
		"order": _next_level_order(catalog, world_id),
		"scenario_id": 0,
		"name": "New Level",
		"goals": default_goals(),
		"rewards": default_rewards(),
	}


# ── lookups (mutable — return live references into the catalog) ────────────────


static func _worlds(catalog: Dictionary) -> Array:
	var out: Array = []
	for w in catalog.get("worlds", []):
		if w is Dictionary:
			out.append(w)
	return out


static func get_world(catalog: Dictionary, world_id: String) -> Dictionary:
	for w in _worlds(catalog):
		if str(w.get("id", "")) == world_id:
			return w
	return {}


static func get_level(catalog: Dictionary, world_id: String, level_id: String) -> Dictionary:
	var w := get_world(catalog, world_id)
	for l in w.get("levels", []):
		if l is Dictionary and str(l.get("id", "")) == level_id:
			return l
	return {}


# ── structural mutations (in place) ───────────────────────────────────────────


static func add_world(catalog: Dictionary) -> Dictionary:
	if not (catalog.get("worlds") is Array):
		catalog["worlds"] = []
	var w := new_world(catalog)
	catalog["worlds"].append(w)
	return w


## Returns the removed world's level ids (for the dot-layout cascade).
static func remove_world(catalog: Dictionary, world_id: String) -> Array:
	var ids: Array = []
	var worlds: Array = catalog.get("worlds", [])
	for i in range(worlds.size()):
		if str((worlds[i] as Dictionary).get("id", "")) == world_id:
			for l in (worlds[i] as Dictionary).get("levels", []):
				ids.append(str((l as Dictionary).get("id", "")))
			worlds.remove_at(i)
			break
	return ids


static func add_level(catalog: Dictionary, world_id: String) -> Dictionary:
	var w := get_world(catalog, world_id)
	if w.is_empty():
		return {}
	if not (w.get("levels") is Array):
		w["levels"] = []
	var l := new_level(catalog, world_id)
	w["levels"].append(l)
	return l


static func remove_level(catalog: Dictionary, world_id: String, level_id: String) -> bool:
	var w := get_world(catalog, world_id)
	var levels: Array = w.get("levels", [])
	for i in range(levels.size()):
		if str((levels[i] as Dictionary).get("id", "")) == level_id:
			levels.remove_at(i)
			return true
	return false


static func set_world_field(catalog: Dictionary, world_id: String, key: String, value) -> void:
	var w := get_world(catalog, world_id)
	if w.is_empty():
		return
	w[key] = int(value) if key == "order" else value


static func set_level_field(catalog: Dictionary, world_id: String, level_id: String, key: String, value) -> void:
	var l := get_level(catalog, world_id, level_id)
	if l.is_empty():
		return
	l[key] = int(value) if (key == "order" or key == "scenario_id") else value


static func set_goal(catalog: Dictionary, world_id: String, level_id: String, idx: int, goal: Dictionary) -> void:
	var l := get_level(catalog, world_id, level_id)
	if l.is_empty():
		return
	var goals: Array = l.get("goals", [])
	if idx >= 0 and idx < goals.size():
		goals[idx] = goal


## where = "complete" | "per_star:<0..2>". amounts is a sparse {coins?,souls?,gems?}.
static func set_reward(catalog: Dictionary, world_id: String, level_id: String, where: String, amounts: Dictionary) -> void:
	var l := get_level(catalog, world_id, level_id)
	if l.is_empty():
		return
	if not (l.get("rewards") is Dictionary):
		l["rewards"] = default_rewards()
	var rewards: Dictionary = l["rewards"]
	if where == "complete":
		rewards["complete"] = amounts
	elif where.begins_with("per_star:"):
		var i := int(where.substr("per_star:".length()))
		if not (rewards.get("per_star") is Array):
			rewards["per_star"] = [{}, {}, {}]
		if i >= 0 and i < (rewards["per_star"] as Array).size():
			rewards["per_star"][i] = amounts


## Swap a level's order with its neighbor (delta -1 up / +1 down) in catalog order.
static func move_level(catalog: Dictionary, world_id: String, level_id: String, delta: int) -> void:
	var w := get_world(catalog, world_id)
	var levels: Array = []
	for l in w.get("levels", []):
		if l is Dictionary:
			levels.append(l)
	levels.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for i in range(levels.size()):
		if str(levels[i].get("id", "")) == level_id:
			var j := i + delta
			if j >= 0 and j < levels.size():
				var oi = levels[i].get("order", 0)
				levels[i]["order"] = levels[j].get("order", 0)
				levels[j]["order"] = oi
			return


# ── ids ───────────────────────────────────────────────────────────────────────


static func suggest_world_id(catalog: Dictionary) -> String:
	var n := 1
	for w in _worlds(catalog):
		var id := str(w.get("id", ""))
		if id.begins_with("w") and id.substr(1).is_valid_int():
			n = maxi(n, int(id.substr(1)) + 1)
	while not _world_id_unique(catalog, "w%d" % n):
		n += 1
	return "w%d" % n


static func suggest_level_id(catalog: Dictionary, world_id: String) -> String:
	var prefix := "%s_l" % world_id
	var m := 1
	for l in get_world(catalog, world_id).get("levels", []):
		var id := str((l as Dictionary).get("id", ""))
		if id.begins_with(prefix) and id.substr(prefix.length()).is_valid_int():
			m = maxi(m, int(id.substr(prefix.length())) + 1)
	while not is_level_id_unique(catalog, "%s%d" % [prefix, m]):
		m += 1
	return "%s%d" % [prefix, m]


static func _world_id_unique(catalog: Dictionary, world_id: String) -> bool:
	var seen := 0
	for w in _worlds(catalog):
		if str(w.get("id", "")) == world_id:
			seen += 1
	return seen == 0


## Level ids must be GLOBALLY unique (validate() + the validator check the whole
## catalog). `except` lets the form keep a level's own id while typing.
static func is_level_id_unique(catalog: Dictionary, level_id: String, except: String = "") -> bool:
	for l in Catalog.ordered_levels(catalog):
		var id := str(l.get("id", ""))
		if id == level_id and id != except:
			return false
	return true


static func _next_world_order(catalog: Dictionary) -> int:
	var n := -1
	for w in _worlds(catalog):
		n = maxi(n, int(w.get("order", 0)))
	return n + 1


static func _next_level_order(catalog: Dictionary, world_id: String) -> int:
	var n := -1
	for l in get_world(catalog, world_id).get("levels", []):
		n = maxi(n, int((l as Dictionary).get("order", 0)))
	return n + 1


# ── serialization (canonical, churn-free) ─────────────────────────────────────


## Stable canonical JSON for both the baked (res://) and canonical
## (validator/content) copies: fixed key order, integer coercion, sparse
## rewards, sort_keys=false. Worlds + levels emitted in `order`.
static func serialize(catalog: Dictionary) -> String:
	var worlds_out: Array = []
	for w in Catalog.ordered_worlds(catalog):
		worlds_out.append(_ordered_world(w))
	var out := {"catalog_version": int(catalog.get("catalog_version", 1)), "worlds": worlds_out}
	return JSON.stringify(out, "  ", false) + "\n"


static func _ordered_world(w: Dictionary) -> Dictionary:
	var levels: Array = []
	for l in w.get("levels", []):
		if l is Dictionary:
			levels.append(l)
	levels.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	var levels_out: Array = []
	for l in levels:
		levels_out.append(_ordered_level(l))
	return {
		"id": str(w.get("id", "")),
		"name": str(w.get("name", "")),
		"order": int(w.get("order", 0)),
		"levels": levels_out,
	}


static func _ordered_level(l: Dictionary) -> Dictionary:
	var goals_out: Array = []
	for g in l.get("goals", []):
		if g is Dictionary:
			goals_out.append(_ordered_goal(g))
	return {
		"id": str(l.get("id", "")),
		"order": int(l.get("order", 0)),
		"scenario_id": int(l.get("scenario_id", 0)),
		"name": str(l.get("name", "")),
		"goals": goals_out,
		"rewards": _ordered_rewards(l.get("rewards", {})),
	}


static func _ordered_goal(g: Dictionary) -> Dictionary:
	var out := {"type": str(g.get("type", "points")), "threshold": int(g.get("threshold", 0))}
	var tl = g.get("time_limit_s", null)
	out["time_limit_s"] = null if tl == null else int(tl)
	return out


static func _ordered_rewards(r) -> Dictionary:
	var complete = r.get("complete", {}) if r is Dictionary else {}
	var per_star = r.get("per_star", []) if r is Dictionary else []
	var ps: Array = []
	for i in range(3):
		ps.append(_sparse(per_star[i] if i < per_star.size() else {}))
	return {"complete": _sparse(complete), "per_star": ps}


## Emit coins/souls/gems in that fixed order, only when present and > 0 (matches
## the existing content's sparse rewards; keeps bytes stable).
static func _sparse(amounts) -> Dictionary:
	var out := {}
	if amounts is Dictionary:
		for k in CURRENCIES:
			if amounts.has(k) and int(amounts[k]) > 0:
				out[k] = int(amounts[k])
	return out
