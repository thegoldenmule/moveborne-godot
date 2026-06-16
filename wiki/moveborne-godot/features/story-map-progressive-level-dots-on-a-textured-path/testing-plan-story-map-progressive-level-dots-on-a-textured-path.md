# Testing plan — Story Map — progressive level dots on a textured path

**Status:** draft

## Planned
- Round trip: launch the frontier level from a dot, return from the match; the show_result overlay appears, refresh() runs, and the next dot advances to the new frontier on re-render.
- Editor authoring tool: placing a dot writes a normalized {level_id,x,y}; Save produces JSON that re-loads and passes validate(); dragging an existing dot updates only its x/y (clamped to 0..1).

## Passed
- MbStoryMapLayout.validate(load_baked(), MbStoryCatalog.load_baked()) returns [] for the committed story_maps.json (every dot binds to a real catalog level, all positions in 0..1, no duplicate dots).
- validate() flags each failure class with a distinct problem string: a dot whose level_id is absent from the catalog, a duplicate dot for one level_id, and a position outside 0..1.
- Headless render: with the frontier world's layout present, _rebuild produces exactly dots_for_world().size() dot buttons; the frontier level's dot is the next/glowing one and enabled (when _online); a post-frontier level's dot is locked + disabled; a completed level's dot shows its star count.
- Normalized->pixel mapping is resolution-independent: a dot at x=0,y=0 lands at the dot-layer top-left and x=1,y=1 at the bottom-right, and the relationship holds after a viewport resize.
- Clicking a dot opens the level-detail modal showing the correct level name, lock status, and _star_string(stars) read from GameState.story_progress; the modal Play button emits play_level with MbStoryCatalog.match_cfg(level) carrying that level_id (driven via MbUi.press / a flow).
- Locked dot: opening its modal shows a locked status and a disabled Play; no play_level is emitted.
- MbUi catalog includes the 'story_map' screen with level_<id> dot controls and, while open, the 'story_level_detail' modal screen; the existing start_story / story_play_next flows still resolve.
- Fallback: with story_maps.json missing/empty (no texture) for the current world, the screen renders the existing flat list and remains playable — no crash, gate/online behavior preserved.
- Project sanity: the game opens and the existing headless verifiers/test suites still pass (no regression to game/logic/, net/, or the validator); story_map_editor plugin loads in-editor without errors.

## Failed
_None._

## References
_None._

## Child pages
_None._
