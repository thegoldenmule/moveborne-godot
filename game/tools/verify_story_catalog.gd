extends SceneTree

## Headless story-catalog verifier:
##   godot --headless --path game --script res://tools/verify_story_catalog.gd
##
## Asserts the baked res://story/story_catalog.json is structurally valid,
## that every level references a real MbScenarios entry, and that it is
## BYTE-IDENTICAL to the validator's canonical copy
## (validator/content/story_catalog.json) — the grading and the map must read
## the same data. Prints VERIFY story_catalog: PASS/FAIL; exit 0/1.

const Catalog := preload("res://story/story_catalog.gd")
const MbScenariosS := preload("res://logic/scenarios.gd")

var _ok := true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)


func _initialize() -> void:
	var catalog := Catalog.load_baked()
	_check("baked catalog loads", not catalog.is_empty())

	var problems := Catalog.validate(catalog)
	for p in problems:
		print("  problem: %s" % p)
	_check("baked catalog structurally valid", problems.is_empty())

	var levels := Catalog.ordered_levels(catalog)
	# 3 worlds, and at least the original 45 levels — additions are fine (the
	# catalog is editable now), but a drop below the baseline is suspicious.
	_check("3 worlds, >= 45 levels", Catalog.ordered_worlds(catalog).size() == 3 and levels.size() >= 45)
	for level in levels:
		var sid := int(level.get("scenario_id", -1))
		_check("level %s -> scenario %d exists" % [level.get("id"), sid],
			MbScenariosS.get_scenario(sid) != null)

	# Byte-compare against the validator's canonical copy: one catalog, three
	# surfaces (validator grading / Remote Config upload / baked client copy).
	var baked_path := ProjectSettings.globalize_path("res://story/story_catalog.json")
	var canonical_path := baked_path.get_base_dir().path_join("../../validator/content/story_catalog.json")
	var baked := FileAccess.get_file_as_bytes(baked_path)
	var canonical := FileAccess.get_file_as_bytes(canonical_path)
	_check("validator canonical catalog readable (%s)" % canonical_path, canonical.size() > 0)
	_check("baked catalog is byte-identical to the validator canonical copy",
		baked.size() > 0 and baked == canonical)

	print("VERIFY story_catalog: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)
