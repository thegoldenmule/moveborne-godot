# Spec — Editor Tool Framework — shared base for in-editor authoring tools (migrate ArtGen + Story Map)

**Status:** drafting

## Overview
Define a small **editor-only** framework that captures the skeleton ArtGen and Story Map both reinvent, then migrate both tools onto it with **zero behavior change**. The spec covers the five primitives (`EditorToolPlugin`, `ToolService`, `ContentStore`, `EditorToolUi`, optional `BridgeServer`), the editor/headless seam that makes tool logic verifiable, and the two-stage migration (ArtGen re-bases; Story Map's monolith splits into service + view). The target structure is documented in the *Editor Tool Framework* architecture node; this spec fixes the contracts and the migration boundaries. Out of scope: the SVG Trim helper, any new authoring tool, and giving Story Map a bridge.

## Design
## Authoring contract

A tool is three pieces. A Plugin subclasses EditorToolPlugin and overrides _config() to name its panel + service + dock (+ optional bridge). A Service subclasses ToolService (a Node), owns all state, returns {ok, error?} from every method, and carries no Control/EditorInterface dependency so it loads under godot --headless. A Dock is a Control that binds the service's change signals with method callables and calls its methods; it never owns the source-of-truth state and never throws. Persistence is always via ContentStore.

```gdscript
# A complete tool's plugin after migration (ArtGen shown).
@tool
class_name ArtgenPlugin extends EditorToolPlugin
func _config() -> Dictionary:
    return {
        "panel": "ArtGen",
        "service": preload("artgen_service.gd"),  # extends ToolService
        "dock": preload("dock.gd"),                # Control, binds service signals
        "bridge": preload("bridge.gd"),            # extends BridgeServer (optional)
    }
# Story Map's plugin is identical minus the "bridge" key.
```

## Persistence + editor/headless seam

ContentStore owns the load -> validate -> atomic N-target write -> rescan cycle. validate() runs first and any problem aborts before a single byte is written. Writes are all-or-nothing across all targets; a save-time version bump (e.g. catalog_version) is reverted in memory if any write fails. The post-write EditorInterface.get_resource_filesystem().scan() is the ONLY editor-only call in the persistence path and is gated by a scan flag so the headless verifier exercises the same write logic with scan=false. Canonical serialization (stable key order, integer coercion, sparse fields) stays per-tool because field order is domain-specific — catalog_edit.gd.serialize() is the reference.

## Migration boundaries

ArtGen is a re-base: plugin.gd -> EditorToolPlugin, artgen_service.gd -> ToolService (ad-hoc dicts -> ok()/err()), bridge.gd -> BridgeServer (match-table -> _route()), with ledger/recraft/multipart/svg/config/presets and the :4848 port + MCP surface untouched. Story Map is a split: all non-UI logic (in-memory catalog/layout, dirty + version bump, CatalogEdit mutations, validate, serialize, the baked+canonical+layout save, the Remote Config verify + clipboard helpers) moves into StoryMapService(ToolService); dock.gd becomes a view. The interactive map canvas + dot drag stay in the dock as pure view but mutate through service methods. Acceptance for both: byte-identical output files diffed before/after each migration commit.

## Decisions
Shared addon location: game/addons/editor_tool_kit/ as a library plugin (recommended), discoverable beside artgen/ and story_map_editor/. PENDING human confirmation — alternatives were a terser addons/edkit/ or a non-plugin game/editor/ lib dir. The plan uses editor_tool_kit/ throughout; a rename is a mechanical find/replace if the human picks otherwise. Name + location of the shared addon: game/addons/editor_tool_kit/ (recommended — discoverable next to artgen/ and story_map_editor/, enabled as a library plugin), vs a terser game/addons/edkit/, vs a non-plugin game/editor/ lib dir. Recommendation: editor_tool_kit/ as a library addon.

SVG Trim stays out of the framework: it is a pure static helper (ArtgenSvg.trim_to_content) with no dock/service/state, already covered by verify_artgen_svg.gd. It remains under the sibling Editor Tools architecture node. Should the existing SVG Trim tool (game/tools/trim_svg_editor.gd + ArtgenSvg.trim_to_content) be folded into the framework? Recommendation: NO — it is a pure static helper with no dock/service/state, already headless-verified, and gains nothing from the bases. Leave it as-is under the sibling Editor Tools node.

Story Map migrates dock-only in v1; BridgeServer stays opt-in with ArtGen as the sole consumer. Because Story Map's logic becomes a headless-testable StoryMapService, adding a bridge later is a small additive follow-up. Should Story Map gain a BridgeServer (MCP/CLI authoring like ArtGen) as part of this work? Recommendation: NO for v1 — migrate it dock-only; BridgeServer stays opt-in and ArtGen remains the sole consumer until a concrete need for headless Story Map authoring appears.

## References
_None._

## Child pages
_None._
