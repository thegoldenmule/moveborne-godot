# Feature: Story Map — progressive level dots on a textured path

**Status:** shipped

## Summary
Replace Story Mode's flat vertical level list with an interactive **map**: a per-world background texture overlaid with absolutely-positioned **dot buttons**, one per catalog level, instantiated from a NEW committed client-only data file `res://story/story_maps.json` (texture path + normalized 0..1 dot positions bound to catalog `level_id`s). Dots render lock/star state from the same `MbStoryCatalog` frontier math over the (server-authoritative, read-only) `GameState.story_progress`; clicking a dot opens a small **level-detail modal** (CanvasLayer, mirroring the settings_tab avatar-picker pattern) showing the level name, lock status, stars out of 3, and a **Play** button that calls the existing `_launch_level -> Catalog.match_cfg -> StoryMapState/MatchState` path unchanged. A NEW `@tool` EditorPlugin (`game/addons/story_map_editor/`, mirroring `addons/artgen/`) lets a designer pick a world + texture and click-place / drag dots, validating against the catalog and saving `story_maps.json`. The change is pure presentation + navigation: no impact on `game/logic/`, `net/`, the validator, or determinism parity. The existing flat list is kept ONLY as a graceful fallback when a world has no map data. Reference art with the desired path-with-dots look: `art/generated/2026-06/g_1781295015_4cfa-ice-planet.png`.

## Components affected
- MbStoryMapLayout (game/story/story_map_layout.gd) — NEW pure static helper over story_maps.json: load_baked / map_for_world / texture_for_world / dots_for_world / validate(layout, catalog). Mirrors the MbStoryCatalog convention.
- res://story/story_maps.json — NEW committed client-only layout file: { version, maps: { <world_id>: { texture, dots: [{level_id, x, y}] } } }. The editor tool's output and the game's baked fallback.
- story_map.gd (MODIFY) — replace the ScrollContainer/VBoxContainer flat list with a TextureRect map background + a dot-layer Control of absolutely-positioned dot buttons; keep title, world selector, status, Play, connect-gate, result overlay, and refresh()/frontier math intact.
- Level-detail modal (embedded in story_map.gd) — NEW CanvasLayer modal (Reg.screen 'story_level_detail') showing level name, lock status, stars (★/☆ out of 3), and a Play button (disabled when locked) that calls the existing _launch_level(level).
- game/addons/story_map_editor/ — NEW @tool EditorPlugin (plugin.gd + dock.gd, mirroring addons/artgen/): world dropdown + texture FileDialog, TextureRect canvas with click-to-place / drag-to-move dots bound to catalog level_ids, MbStoryMapLayout.validate, and Save to res://story/story_maps.json. Registered in project.godot [editor_plugins] + plugin.cfg.
- Headless verifier + McpTestSuite coverage — tools/verify_story_map.gd (+ a test) asserting validate() passes on the committed file, dot render/lock/star state, normalized->pixel mapping, MbUi catalog includes the dots + modal screen, and the dot->modal->Play launch path.

## Design constraints
1. Pure presentation + navigation: ZERO changes to game/logic/, game/net/, or validator/. No determinism parity tests are touched (story grading/progression live outside the hash domain). Match launch stays MbStoryCatalog.match_cfg(level) -> play_level(cfg) -> StoryMapState._on_play_level -> MatchState, unchanged.
2. Map data lives in a SEPARATE client-only file res://story/story_maps.json — NOT in story_catalog.json (delivered via Remote Config; adding spatial fields would force a validator catalog schema bump) and NOT in story_progress (server-authoritative, read-only client-side per the hard-wall ADR). Dot positions/texture are pure client cosmetics.
3. Lock/unlock + star state MUST remain derived from MbStoryCatalog.compute_next_level frontier in catalog order; dots only RENDER that state and must not perturb the frontier math. A dot is playable iff is_level_unlocked / at-or-before the frontier, identical to the current flat list.
4. Dot positions are normalized 0..1 (origin top-left), converted to pixels against the dot-layer rect at render time so the map scales with the viewport. The editor clamps to 0..1 and validate() rejects out-of-range positions, unknown level_ids, and duplicate dots.
5. Every dot button and modal control registers via Reg.adopt(dot, 'level_<id>') / Reg.screen + Reg.adopt, so MbUi flows (start_story, story_play_next) keep working and the modal forms its own 'story_level_detail' MbUi screen like the avatar picker (factory-over-manual-metadata).
6. Graceful degradation: if story_maps.json is missing/empty for the current world, fall back to the existing flat-list rendering. Never crash and never block play. Story stays online-only — the connect-to-play gate and _online disabling apply to dots exactly as to the old rows.
7. Design decisions resolved from the intent (recorded for reviewer): (1) the map REPLACES the flat list as the primary view (intent: 'rather than a list of levels'); the list survives only as fallback. (2) One background texture PER WORLD (matches the existing world selector + artgen 2:3 'story-map' presets), not one long 45-level scroll. (3) The modal stays MINIMAL — name, lock, stars/3, Play — per the intent. (4) The authoring tool is a full @tool EditorPlugin dock (mirrors artgen) rather than an EditorScript MVP.
8. Art: v1 ships using the existing example render art/generated/2026-06/g_1781295015_4cfa-ice-planet.png (copied into res://assets/generated/ with ai_manifest attribution) for at least the frontier world; remaining worlds without a committed texture fall back to the flat list. Designers author/replace per-world textures later via the artgen 'story-map'/'story-map-baked' presets — not a v1 blocker.

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
- [Implementation plan — Story Map — progressive level dots on a textured path](implementation-plan:mqgpny4v-001a-kseen9)
- [Testing plan — Story Map — progressive level dots on a textured path](testing-plan:mqgpny4v-001b-qtfgul)
- [Spec — Story Map — progressive level dots on a textured path](feature-spec:mqgpny4v-001c-lrshqf)

## Commits
- `568ec96` feat(story): interactive story map — level dots on a textured path + editor placement tool
- `f3f4453` fix(story-map-editor): selectable, draggable dots + 2× canvas (per-dot input, click-to-select with level info, fixed overlay/texture alignment)
