# Implementation plan — Story Map — progressive level dots on a textured path

**Status:** ready

## Steps
- [x] Data layer: add res://story/story_maps.json ({ version, maps: { <world_id>: { texture, dots:[{level_id,x,y}] } } }) and game/story/story_map_layout.gd (class_name MbStoryMapLayout, RefCounted, static-only): load_baked(), map_for_world(layout, world_id), texture_for_world(layout, world_id), dots_for_world(layout, world_id), validate(layout, catalog) -> [] when valid. Mirror MbStoryCatalog (BAKED_PATH const, JSON.parse_string, {} fallback). Commit the .gd.uid.
- [x] Map art: copy the example render art/generated/2026-06/g_1781295015_4cfa-ice-planet.png into res://assets/generated/story_map_w1.png with ai_manifest.json attribution; seed story_maps.json with the w1 map (texture + dots placed for w1's 15 levels). Leave w2/w3 texture-less so they fall back to the flat list until a designer authors them via the artgen 'story-map' presets.
- [x] Editor authoring plugin: create game/addons/story_map_editor/ (plugin.cfg + plugin.gd @tool EditorPlugin adding a bottom-panel dock via add_control_to_bottom_panel; dock.gd @tool pure-code UI mirroring addons/artgen/dock.gd). Dock loads story_catalog.json + story_maps.json, has a world dropdown + texture FileDialog, renders the chosen texture in a TextureRect, click-to-place a dot for the next-unplaced level and drag-to-move existing dots (normalize via gui_input against the TextureRect rect, clamp 0..1), lists unplaced level_ids, runs MbStoryMapLayout.validate, and Saves JSON to res://story/story_maps.json. Register in game/project.godot [editor_plugins].
- [x] story_map.gd _build_ui(): replace the _scroll/_level_list block (lines ~180-191) with a map container — a TextureRect background (world texture from MbStoryMapLayout) sized into the same rect, plus a sibling dot-layer Control for absolutely-positioned dot buttons. Keep _title, world selector row, _status, _play_btn, and _build_gate untouched. Load the baked layout in _ready alongside _baked catalog (_layout var).
- [x] story_map.gd _rebuild(): when a texture exists for the current world, set the TextureRect texture and render dots — for each dot in MbStoryMapLayout.dots_for_world place a button via new _make_level_dot(level, progress, is_next, unlocked) (replacing _make_level_row), positioned at dot_layer_origin + Vector2(x,y)*dot_layer_size (centered). Compute unlocked/is_next with the EXACT existing frontier/passed_frontier math (lines ~303-318). Style next (glow) / completed (star count) / locked (dim + lock) reusing _style_level_row semantics. Reg.adopt(dot, 'level_%s' % id). If no texture for the world, render the existing flat list (fallback).
- [x] Level-detail modal: add _build_level_detail_modal() following settings_tab.gd avatar-picker (CanvasLayer layer=20, Reg.screen(_detail_modal,'story_level_detail'), dimmed ColorRect backdrop that dismisses on click, centered panel). Dot press calls _show_level_detail(level) which populates level name, lock status, _star_string(stars from GameState.story_progress), and a Play button (Reg.adopt 'play') that calls the existing _launch_level(level) then hides the modal. Locked levels show locked status with Play disabled.
- [x] Preserve flow + state: keep _launch_level -> play_level.emit(Catalog.match_cfg(level)) and StoryMapState (game/ui/router/story_map_state.gd) unchanged so on resume the existing show_result overlay + refresh() still run and the next-level dot re-highlights from the re-read GameState.story_progress. Ensure the new CanvasLayer modal and the existing free-floating result overlay do not z-fight (modal hidden before play; result overlay stays as-is).
- [x] Coverage: add tools/verify_story_map.gd headless verifier (and/or an McpTestSuite test) that loads the baked catalog + story_maps.json and asserts: validate() == [] on the committed file; validate() flags unknown level_id / duplicate dot / out-of-0..1 position; the frontier-world layout renders dots_for_world().size() dots with correct next/locked/star state; normalized->pixel mapping is resolution-independent; MbUi catalog includes 'story_map' level_<id> controls + the 'story_level_detail' screen when open; pressing a dot then modal Play emits play_level with the right level_id; and the missing-map fallback renders the flat list. Wire into the verifier list in CLAUDE.md / commands.

## Data models & interfaces
```json
// res://story/story_maps.json  (NEW committed file; client-only cosmetics — NOT Remote Config'd, NOT in story_progress)
{
  "version": 1,
  "maps": {
    "w1": {
      "texture": "res://assets/generated/story_map_w1.png",
      "dots": [
        { "level_id": "w1_l1", "x": 0.12, "y": 0.86 },
        { "level_id": "w1_l2", "x": 0.28, "y": 0.74 },
        { "level_id": "w1_l3", "x": 0.40, "y": 0.61 }
        // ... one dot per level_id in the world (normalized 0..1, origin top-left)
      ]
    },
    // worlds without a texture fall back to the flat list until authored
    "w2": { "texture": "", "dots": [] },
    "w3": { "texture": "", "dots": [] }
  }
}
```

```gdscript
# game/story/story_map_layout.gd  (NEW) — pure static utility, mirrors MbStoryCatalog
class_name MbStoryMapLayout
extends RefCounted

const BAKED_PATH := "res://story/story_maps.json"

static func load_baked() -> Dictionary:
	if not FileAccess.file_exists(BAKED_PATH):
		return {}
	var f := FileAccess.open(BAKED_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}

static func map_for_world(layout: Dictionary, world_id: String) -> Dictionary:
	var maps = layout.get("maps", {})
	var m = (maps as Dictionary).get(world_id, {}) if maps is Dictionary else {}
	return m if m is Dictionary else {}

static func texture_for_world(layout: Dictionary, world_id: String) -> String:
	return str(map_for_world(layout, world_id).get("texture", ""))

static func dots_for_world(layout: Dictionary, world_id: String) -> Array:
	var out: Array = []
	for d in map_for_world(layout, world_id).get("dots", []):
		if d is Dictionary and str(d.get("level_id", "")) != "":
			out.append(d)
	return out

# [] == valid. Every dot binds to a catalog level; positions in 0..1; no dup level_ids.
static func validate(layout: Dictionary, catalog: Dictionary) -> Array:
	var problems: Array = []
	var known := {}
	for l in MbStoryCatalog.ordered_levels(catalog):
		known[str(l.get("id", ""))] = true
	for world_id in (layout.get("maps", {}) as Dictionary).keys():
		var seen := {}
		for d in dots_for_world(layout, str(world_id)):
			var lid := str(d.get("level_id", ""))
			if not known.has(lid):
				problems.append("%s: unknown level_id" % lid)
			if seen.has(lid):
				problems.append("%s: duplicate dot" % lid)
			seen[lid] = true
			var x := float(d.get("x", -1.0)); var y := float(d.get("y", -1.0))
			if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
				problems.append("%s: position out of 0..1" % lid)
	return problems
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
