extends SceneTree

## Headless verifier for the Story Map interactive-dots feature:
##   godot --headless --path game --script res://tools/verify_story_map.gd
##
## Covers the pure layout helper (load/validate) and the live screen rendering:
## dots from story_maps.json with the SAME frontier lock/star math as the flat
## list, the normalized->pixel mapping (resolution independent), the level-detail
## modal (name/lock/stars/Play -> play_level), UiReg registration, and the
## missing-map flat-list fallback. Prints VERIFY story_map: PASS/FAIL; exit 0/1.

const Catalog := preload("res://story/story_catalog.gd")
const Layout := preload("res://story/story_map_layout.gd")
const Reg := preload("res://addons/ui_kit/ui_reg.gd")
# story_map.tscn is load()ed at runtime (not preloaded): its script references the
# GameState autoload global, which only registers after engine init under --script.

var _ok := true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := Catalog.load_baked()
	var layout := Layout.load_baked()
	# The GameState autoload global isn't registered at the --script compile moment;
	# reach it as a node (it's instantiated by engine init before _run fires).
	var gs := root.get_node("/root/GameState")

	# ── pure helper: validate + lookups ──────────────────────────────────────
	_check("committed layout validates clean", Layout.validate(layout, catalog) == [])
	_check("w1 has a map", Layout.has_map(layout, "w1"))
	# A world without a map exercises the flat-list fallback (which worlds are
	# mapped is editable content now, so find one dynamically).
	var unmapped := ""
	for w in Catalog.ordered_worlds(catalog):
		if not Layout.has_map(layout, str(w.get("id", ""))):
			unmapped = str(w.get("id", ""))
			break
	_check("an unmapped world exists for the fallback test", unmapped != "")
	var w1_levels := Catalog.ordered_levels(catalog).filter(
		func(l): return str(l.get("world_id", "")) == "w1").size()
	var w1_dots := Layout.dots_for_world(layout, "w1").size()
	_check("every w1 level has a dot", w1_dots == w1_levels)

	var unknown := {"version": 1, "maps": {"w1": {"dots": [{"level_id": "nope", "x": 0.5, "y": 0.5}]}}}
	_check("validate flags unknown level_id",
		Layout.validate(unknown, catalog).has("nope: unknown level_id"))
	var dup := {"version": 1, "maps": {"w1": {"dots": [
		{"level_id": "w1_l1", "x": 0.5, "y": 0.5}, {"level_id": "w1_l1", "x": 0.6, "y": 0.6}]}}}
	_check("validate flags duplicate dot",
		Layout.validate(dup, catalog).has("w1_l1: duplicate dot"))
	var oob := {"version": 1, "maps": {"w1": {"dots": [{"level_id": "w1_l1", "x": 1.5, "y": 0.5}]}}}
	_check("validate flags out-of-range position",
		Layout.validate(oob, catalog).has("w1_l1: position out of 0..1"))

	# ── live screen: dot rendering with empty progress (frontier = w1_l1) ─────
	gs.set_story_catalog({})       # force the baked catalog
	gs.set_story_progress({})      # nothing played yet
	var screen = load("res://ui/screens/story_map.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame

	_check("map shown, flat list hidden", screen._dot_layer.visible and not screen._scroll.visible)
	_check("renders one dot per w1 dot", screen._dot_layer.get_child_count() == w1_dots)

	var dots := _dots_by_id(screen)
	_check("frontier dot is next + unlocked + 0 stars",
		dots.has("w1_l1") and dots["w1_l1"].get_meta("is_next")
		and dots["w1_l1"].get_meta("unlocked") and int(dots["w1_l1"].get_meta("stars")) == 0)
	_check("post-frontier dot is locked",
		dots.has("w1_l2") and not dots["w1_l2"].get_meta("unlocked")
		and not dots["w1_l2"].get_meta("is_next"))

	# normalized -> pixel mapping holds, and survives a resize.
	_check("dots placed at norm * rect", _positions_match(screen))
	screen._dot_layer.size = Vector2(200, 400)
	screen._reposition_dots()
	_check("mapping resolution-independent after resize", _positions_match(screen))

	# registration: dots + modal are on the live tree for UiDriver.
	_check("dot registered as level_w1_l1",
		dots["w1_l1"].is_in_group(Reg.CONTROL_GROUP)
		and str(dots["w1_l1"].get_meta(Reg.META_ID)) == "level_w1_l1")
	_check("modal is its own UiDriver screen",
		screen._detail_modal.is_in_group(Reg.GROUP)
		and str(screen._detail_modal.get_meta(Reg.META_SCREEN)) == "story_level_detail")

	# ── modal: unlocked level → name/stars/Play emits play_level ─────────────
	screen._online = true
	var lvl1 := Catalog.get_level(catalog, "w1_l1")
	screen._show_level_detail(lvl1)
	_check("modal visible with name + stars",
		screen._detail_modal.visible and screen._detail_name.text == str(lvl1.get("name", ""))
		and screen._detail_stars.text == screen._star_string(0))
	_check("unlocked modal Play enabled", not screen._detail_play.disabled)
	var got: Array = [{}]
	screen.play_level.connect(func(cfg): got[0] = cfg)
	screen._on_detail_play()
	_check("Play emits match_cfg for the level",
		str((got[0] as Dictionary).get("level_id", "")) == "w1_l1"
		and str((got[0] as Dictionary).get("mode", "")) == "story")
	_check("modal hidden after Play", not screen._detail_modal.visible)

	# locked level → locked status, Play disabled.
	screen._show_level_detail(Catalog.get_level(catalog, "w1_l2"))
	_check("locked modal shows lock + disabled Play",
		screen._detail_status.text.contains("Locked") and screen._detail_play.disabled)
	screen._hide_level_detail()

	# ── completed level shows its star count ─────────────────────────────────
	gs.set_story_progress({"levels": {"w1_l1": {"stars": 3}, "w1_l2": {"stars": 1}}})
	screen._world_index = 0
	screen._rebuild()
	await process_frame
	var dots2 := _dots_by_id(screen)
	_check("completed dot shows 3 stars + unlocked",
		int(dots2["w1_l1"].get_meta("stars")) == 3 and dots2["w1_l1"].get_meta("unlocked"))
	_check("new frontier dot advanced to w1_l3",
		dots2.has("w1_l3") and dots2["w1_l3"].get_meta("is_next"))

	# ── fallback: a world without a map renders the flat list ────────────────
	var all_worlds := Catalog.ordered_worlds(catalog)
	var unmapped_idx := 0
	var unmapped_levels := 0
	for i in range(all_worlds.size()):
		if str(all_worlds[i].get("id", "")) == unmapped:
			unmapped_idx = i
			unmapped_levels = Catalog.ordered_levels(catalog).filter(
				func(l): return str(l.get("world_id", "")) == unmapped).size()
	screen._world_index = unmapped_idx
	screen._rebuild()
	await process_frame
	_check("fallback shows flat list, hides map",
		screen._scroll.visible and not screen._dot_layer.visible
		and screen._level_list.get_child_count() == unmapped_levels)

	screen.queue_free()
	print("VERIFY story_map: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _dots_by_id(screen) -> Dictionary:
	var out := {}
	for c in screen._dot_layer.get_children():
		if c.has_meta(Reg.META_ID):
			out[str(c.get_meta(Reg.META_ID)).trim_prefix("level_")] = c
	return out


## Every dot button sits at norm * dot_layer.size - DOT_SIZE/2.
func _positions_match(screen) -> bool:
	var rect: Vector2 = screen._dot_layer.size
	var half: Vector2 = screen.DOT_SIZE * 0.5
	for d in screen._dots:
		var btn = d.get("btn")
		if not is_instance_valid(btn):
			return false
		var want: Vector2 = Vector2(float(d.get("x")), float(d.get("y"))) * rect - half
		if btn.position.distance_to(want) > 0.5:
			return false
	return true
