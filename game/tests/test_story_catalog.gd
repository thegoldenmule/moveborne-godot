@tool
extends McpTestSuite

## MbStoryCatalog pure helpers over the BAKED catalog: structural validity,
## scenario cross-checks against the live MbScenarios table, the canonical
## level ordering, and the unlock-chain math the map renders from. No network.

const Catalog := preload("res://story/story_catalog.gd")
const MbScenariosS := preload("res://logic/scenarios.gd")


func suite_name() -> String:
	return "story_catalog"


func _progress(levels: Dictionary) -> Dictionary:
	return {"catalog_version": 1, "levels": levels, "next_level_id": ""}


func test_baked_catalog_is_valid() -> void:
	var catalog := Catalog.load_baked()
	assert_true(not catalog.is_empty(), "baked res://story/story_catalog.json loads")
	assert_eq(Catalog.validate(catalog), [],
		"baked catalog has no structural problems (3 goals/level, valid types, positive thresholds)")
	assert_true(int(catalog.get("catalog_version", 0)) >= 1, "catalog_version present")


func test_every_level_references_a_real_scenario() -> void:
	var catalog := Catalog.load_baked()
	var missing: Array = []
	for level in Catalog.ordered_levels(catalog):
		var sid := int(level.get("scenario_id", -1))
		if MbScenariosS.get_scenario(sid) == null:
			missing.append("%s -> %d" % [level.get("id"), sid])
	assert_eq(missing, [], "every catalog level maps onto an existing MbScenarios entry")


func test_ordering_is_a_strict_unambiguous_chain() -> void:
	var catalog := Catalog.load_baked()
	var levels := Catalog.ordered_levels(catalog)
	assert_eq(levels.size(), 45, "3 worlds x 15 levels")
	assert_eq(str(levels[0].get("id", "")), "w1_l1", "the chain starts at w1_l1")
	assert_eq(str(levels[15].get("id", "")), "w2_l1", "world 2 follows world 1")
	var seen := {}
	for l in levels:
		seen[str(l.get("id", ""))] = true
	assert_eq(seen.size(), 45, "level ids are unique (the unlock chain is unambiguous)")


func test_world1_is_ice_only() -> void:
	# Decision 2026-06-12: world 1 uses only freeze-mechanic scenarios.
	var catalog := Catalog.load_baked()
	var ice_only := [0, 7, 13, 17]
	for level in Catalog.ordered_levels(catalog):
		if str(level.get("world_id", "")) == "w1":
			assert_true(ice_only.has(int(level.get("scenario_id", -1))),
				"w1 level %s uses an ice-only scenario" % level.get("id"))


func test_unlock_chain_math() -> void:
	var catalog := Catalog.load_baked()
	var fresh := _progress({})
	assert_eq(Catalog.compute_next_level(catalog, fresh), "w1_l1",
		"no progress -> the frontier is the first level")
	assert_true(Catalog.is_level_unlocked(catalog, fresh, "w1_l1"), "first level playable")
	assert_true(not Catalog.is_level_unlocked(catalog, fresh, "w1_l2"), "second level locked")

	var after1 := _progress({"w1_l1": {"stars": 2, "best_score": 700, "rewarded_stars": 2}})
	assert_eq(Catalog.compute_next_level(catalog, after1), "w1_l2", "1+ star advances the frontier")
	assert_true(Catalog.is_level_unlocked(catalog, after1, "w1_l1"), "completed levels stay replayable")
	assert_true(Catalog.is_level_unlocked(catalog, after1, "w1_l2"), "the frontier is playable")
	assert_true(not Catalog.is_level_unlocked(catalog, after1, "w1_l3"), "beyond the frontier stays locked")

	# JSON int/float ambiguity: stars arriving as 2.0 still counts.
	var floaty := _progress({"w1_l1": {"stars": 2.0}})
	assert_eq(Catalog.stars_for(floaty, "w1_l1"), 2, "float stars normalize to int")
	assert_eq(Catalog.stars_for(floaty, "w1_l9"), 0, "unplayed level -> 0 stars")


func test_all_complete_frontier_is_empty() -> void:
	var catalog := Catalog.load_baked()
	var levels := {}
	for l in Catalog.ordered_levels(catalog):
		levels[str(l.get("id", ""))] = {"stars": 1}
	var done := _progress(levels)
	assert_eq(Catalog.compute_next_level(catalog, done), "", "everything complete -> no frontier")
	assert_true(Catalog.is_level_unlocked(catalog, done, "w3_l15"), "all levels replayable when done")


func test_match_cfg_shape() -> void:
	var catalog := Catalog.load_baked()
	var level := Catalog.get_level(catalog, "w1_l3")
	var cfg := Catalog.match_cfg(level)
	assert_eq(str(cfg.get("mode", "")), "story", "story mode")
	assert_eq(str(cfg.get("level_id", "")), "w1_l3", "level id rides the cfg")
	assert_eq(int(cfg.get("scenario_id", -1)), int(level.get("scenario_id", -2)),
		"scenario comes from the catalog")
	assert_eq((cfg.get("goals", []) as Array).size(), 3, "goals copied for the in-match HUD")
