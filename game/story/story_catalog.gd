class_name MbStoryCatalog
extends RefCounted

## Pure helpers over the story catalog + per-user progress blob — parsing,
## lookups, and the unlock-chain math the map screen renders from. Mirrors the
## validator's story/catalog.ts + story/progress.ts read-side semantics (the
## validator is authoritative; the client only displays).
##
## NOT part of game/logic/: story mode is account/meta data, outside the
## determinism hash domain (hard-wall ADR). Static functions only, per the
## repo's Mb* utility convention.

const BAKED_PATH := "res://story/story_catalog.json"


## The committed offline/dev fallback catalog ({} if missing/corrupt).
static func load_baked() -> Dictionary:
	if not FileAccess.file_exists(BAKED_PATH):
		return {}
	var f := FileAccess.open(BAKED_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## Structural problems with a catalog dict ([] = valid). Matches the
## validator's validateCatalog checks so a bad edit fails on both sides.
static func validate(catalog: Dictionary) -> Array:
	var problems: Array = []
	if int(catalog.get("catalog_version", 0)) < 1:
		problems.append("catalog_version must be a positive integer")
	var seen := {}
	for level in ordered_levels(catalog):
		var tag := str(level.get("id", "?"))
		if seen.has(tag):
			problems.append("%s: duplicate level id" % tag)
		seen[tag] = true
		if int(level.get("scenario_id", -1)) < 0:
			problems.append("%s: bad scenario_id" % tag)
		var goals = level.get("goals", [])
		if not (goals is Array) or goals.size() != 3:
			problems.append("%s: must have exactly 3 goals" % tag)
			continue
		for goal in goals:
			var gtype := str((goal as Dictionary).get("type", ""))
			if gtype != "points" and gtype != "max_tile":
				problems.append("%s: bad goal type '%s'" % [tag, gtype])
			if float((goal as Dictionary).get("threshold", 0)) <= 0:
				problems.append("%s: goal threshold must be > 0" % tag)
			var tl = (goal as Dictionary).get("time_limit_s", null)
			if tl != null and float(tl) <= 0:
				problems.append("%s: time_limit_s must be null or > 0" % tag)
		var per_star = (level.get("rewards", {}) as Dictionary).get("per_star", [])
		if not (per_star is Array) or per_star.size() != 3:
			problems.append("%s: rewards.per_star must have exactly 3 entries" % tag)
	return problems


## Worlds sorted by order (each with its levels sorted by order).
static func ordered_worlds(catalog: Dictionary) -> Array:
	var worlds: Array = []
	for w in catalog.get("worlds", []):
		if w is Dictionary:
			worlds.append(w)
	worlds.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return worlds


## Every level in canonical unlock order, each tagged with its world_id.
static func ordered_levels(catalog: Dictionary) -> Array:
	var out: Array = []
	for w in ordered_worlds(catalog):
		var levels: Array = []
		for l in w.get("levels", []):
			if l is Dictionary:
				levels.append(l)
		levels.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
		for l in levels:
			var tagged: Dictionary = (l as Dictionary).duplicate()
			tagged["world_id"] = str(w.get("id", ""))
			out.append(tagged)
	return out


static func get_level(catalog: Dictionary, level_id: String) -> Dictionary:
	for l in ordered_levels(catalog):
		if str(l.get("id", "")) == level_id:
			return l
	return {}


## Stars recorded for a level in the progress blob (0 when unplayed).
static func stars_for(progress: Dictionary, level_id: String) -> int:
	var levels = progress.get("levels", {})
	if not (levels is Dictionary):
		return 0
	var entry = (levels as Dictionary).get(level_id, {})
	return int((entry as Dictionary).get("stars", 0)) if entry is Dictionary else 0


## First level (catalog order) without a star — the unlock frontier. Recomputed
## client-side so a missing/stale blob next_level_id can never wedge the map.
## "" when every level is complete.
static func compute_next_level(catalog: Dictionary, progress: Dictionary) -> String:
	for l in ordered_levels(catalog):
		if stars_for(progress, str(l.get("id", ""))) < 1:
			return str(l.get("id", ""))
	return ""


## A level is playable when it sits at or before the unlock frontier.
static func is_level_unlocked(catalog: Dictionary, progress: Dictionary, level_id: String) -> bool:
	var frontier := compute_next_level(catalog, progress)
	if frontier == "":
		return get_level(catalog, level_id).size() > 0
	for l in ordered_levels(catalog):
		var id := str(l.get("id", ""))
		if id == level_id:
			return true
		if id == frontier:
			return false
	return false


## The GameState.next_match config a story level launches with.
static func match_cfg(level: Dictionary) -> Dictionary:
	return {
		"mode": "story",
		"level_id": str(level.get("id", "")),
		"scenario_id": int(level.get("scenario_id", 0)),
		"goals": level.get("goals", []),
	}
