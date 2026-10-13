# Testing plan — Editor Tool Framework — shared base for in-editor authoring tools (migrate ArtGen + Story Map)

**Status:** ready

## Planned
_None._

## Passed
- Framework primitives (verify_editor_tool_kit.gd, headless): ToolService.ok()/err() return the documented {ok,error?,code?} shapes and is_dirty() tracks mark/clear; ContentStore.load_json returns {} for a missing path and parses a written temp file; assert these pass under godot --headless.
- ContentStore atomicity + rollback (headless): save_all writes N temp targets when validate returns []; when validate returns problems, NO target file is created/modified; a simulated open-failure on the 2nd of 3 targets leaves the version-bump reverted (in-memory catalog_version unchanged) and returns ok=false.
- EditorToolUi builders (headless): split_root returns an HSplitContainer with both min-size floors set; label_wrap/form_row return the expected VBox/HBox node shapes; restyle_selected swaps the StyleBoxFlat border color on the selected/unselected states.
- ArtGen behavior parity (editor open): after migration the bridge still listens on 127.0.0.1:4848 (and honors ARTGEN_BRIDGE_PORT); every former route responds (status/history/generate/save/discard/swap/migrate/style-create); a generate->save->swap round-trip writes a ledger.jsonl entry + ai_manifest.json entry whose shape matches a pre-migration capture (diff is empty modulo ids/timestamps).
- ArtGen MCP shim parity (editor open): tools/artgen_mcp.ts driving artgen_generate/_history/_get/_save/_discard/_status/_style_create succeeds against the migrated bridge with identical response envelopes; a generated asset file is byte-identical to one produced by the same prompt pre-migration (same model/style/seed path).
- Plugin lifecycle / hot-reload (editor): enabling, disabling, and reloading each migrated plugin via EditorToolPlugin leaves no orphaned bottom-panel control, no freed-node access errors, and no leaked TCP port; a signal arriving during reload does not call into a freed dock (method-callable binding holds).
- Story Map service logic (verify_story_map_service.gd, headless — NEW coverage): load catalog+layout via StoryMapService; add/remove world+level reflects in serialize(); place/move/remove dot clamps to 0..1; validate() flags unknown level_id, duplicate dot, and out-of-0..1 position; all without the editor running.
- Story Map save parity: a save through StoryMapService + ContentStore.save_all writes res://story/story_catalog.json, validator/content/story_catalog.json, and res://story/story_maps.json that are byte-identical to a pre-migration save of the same edits (baked == canonical bytes; catalog_version bumps once and only when dirty).
- Story Map Remote Config + dock parity (editor open): the Remote Config 'verify' action still shells out to bun story-appconfig.ts and reports in-sync/drift; clipboard export still copies {story_catalog:...}; the interactive map canvas places/drags dots and the catalog tree edit forms produce the same status-label messages as before.
- Isolation guarantee: grep confirms editor_tool_kit/ is referenced only by the two addons (not by game/scenes, game/ui, game/net, or game/logic/); the full determinism parity verifier suite (engine_swipe, playcard, ... combined) is untouched and still PASSes; no validator change is required.

## Failed
_None._

## References
_None._

## Child pages
_None._
