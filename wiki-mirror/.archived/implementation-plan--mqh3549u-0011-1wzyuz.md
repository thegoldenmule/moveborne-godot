# Implementation plan — Editor Tool Framework — shared base for in-editor authoring tools (migrate ArtGen + Story Map)

**Status:** ready

## Steps
- [x] Scaffold the framework addon. Create game/addons/editor_tool_kit/ with plugin.cfg (a no-op library plugin) and editor_tool_plugin.gd: @tool class_name EditorToolPlugin extends EditorPlugin with a virtual _config() -> {panel:String, service:Script, dock:Script, bridge:Script(optional)}. _enter_tree() instantiates service.new() (named), add_child; if bridge present, bridge.new() with .service set, add_child; dock.new() with .service set, add_control_to_bottom_panel(dock, panel). _exit_tree() reverses in order (remove_control_from_bottom_panel + free dock, free bridge, free service), nulling refs. Mirror artgen/plugin.gd's construction order exactly. Commit .gd.uid.
- [x] ToolService base. Add editor_tool_kit/tool_service.gd: class_name ToolService extends Node with ok(data:={})/err(msg,code:=0) helpers returning the {ok,error?,code?} contract, a _dirty bool with mark_dirty()/clear_dirty()/is_dirty(), and a documented rule: NO Control/EditorInterface references (so it loads under godot --headless). No signals are mandated by the base (each service declares its own, e.g. ArtGen's history_changed/balance_changed), but document the convention that the dock binds them with method callables. Commit .gd.uid.
- [x] ContentStore helper. Add editor_tool_kit/content_store.gd: class_name ContentStore (static-only). Provide load_json(path) -> Dictionary ({} on missing/corrupt, mirrors MbStoryCatalog.load_baked); save_all(targets:Array[{path,text}], validate:Callable, on_ok:Callable) -> {ok,error?} that runs validate (Array of problems; non-empty aborts before any write), writes every target all-or-nothing, calls EditorInterface.get_resource_filesystem().scan(), then on_ok; and a version-bump helper with rollback (bump_then(struct, key, do_save) reverts the in-memory bump if do_save returns ok=false). Keep the canonical-serialize contract documented here but leave the actual serializer in each tool (catalog_edit.gd is the reference) since field order is domain-specific. Guard the editor-only scan() so a headless caller can pass scan:=false.
- [x] EditorToolUi helper. Add editor_tool_kit/editor_tool_ui.gd: static builders for the idioms both docks share — split_root(min_left, min_right) -> HSplitContainer with custom_minimum_size floors; label_wrap(text, control) -> VBox(label+expanding control); form_row(label_text, control, label_w:=78) -> HBox; status_label() -> Label; restyle_selected(panel, selected) using StyleBoxFlat (violet/green border like story_map_editor _dot_style). Pure construction helpers, no state. This is additive — docks adopt builders incrementally with no visual change.
- [x] BridgeServer mixin. Add editor_tool_kit/bridge_server.gd by generalizing artgen/bridge.gd: class_name BridgeServer extends Node with var service, var port, a _ready() that skips when DisplayServer.get_name()=="headless" and otherwise TCPServer.listen(port,"127.0.0.1"), the _process poll loop, _request_complete (Content-Length framing), _handle (method/path/query/body parse), _respond (JSON + Connection: close), and a virtual _route(method, path, query, body) -> {code, payload} that subclasses override with their match [method, path] table (await-capable). Port resolution order (env override -> service.config -> default) stays a subclass concern.
- [x] Framework verifier. Add game/tools/verify_editor_tool_kit.gd (headless) asserting: ToolService.ok/err shapes and dirty flag; ContentStore.load_json returns {} for a missing path and parses a temp file; save_all writes N temp targets atomically, aborts all writes when validate returns problems, and rolls back a version bump on a simulated write failure; EditorToolUi builders return the expected node types. Add to the verifier list in CLAUDE.md commands + game/CLAUDE.md. This proves the bases before any tool depends on them.
- [x] Migrate ArtGen — plugin + service + bridge. Re-base artgen/plugin.gd to extend EditorToolPlugin and implement _config() returning its ServiceT/DockT/BridgeT (delete the hand-written _enter_tree/_exit_tree). Re-base artgen_service.gd to extend ToolService, swapping ad-hoc return dicts for ok()/err() (behavior identical). Re-base artgen/bridge.gd to extend BridgeServer, moving its match [method,path] block into _route() and its port resolution into an override; keep every route (status/history/generate/save/discard/swap/migrate/style-create) and the :4848 default + ARTGEN_BRIDGE_PORT override. Leave ledger.gd, recraft_client.gd, multipart.gd, svg_tools.gd, config.json, presets.json untouched.
- [x] ArtGen dock + parity check. Route artgen/dock.gd's compose/gallery/detail layout through EditorToolUi builders only where it is a clean substitution (split_root, label_wrap, status_label) — do not redesign the UI. Then verify parity end-to-end with the Godot editor open: bridge listens on 4848; the artgen MCP shim (tools/artgen_mcp.ts) still drives artgen_generate/_history/_get/_save/_discard/_status/_style_create; a generate->save->swap round-trip writes the same ledger.jsonl + ai_manifest.json shape as before. Diff a generated asset + ledger entry against a pre-migration run.
- [x] Extract StoryMapService. Add game/addons/story_map_editor/story_map_service.gd: class_name StoryMapService extends ToolService. Move OUT of dock.gd everything non-UI: in-memory _catalog/_layout, _reload() (Catalog.load_baked + Layout.load_baked via ContentStore.load_json), dirty tracking + catalog_version bump, all mutations (delegating to CatalogEdit add/remove/set_* + normalized layout), validate (Catalog.validate + Layout.validate), serialize (CatalogEdit.serialize + normalized layout JSON), the baked+canonical+layout save (now ContentStore.save_all with 3 targets + validate + version-bump rollback), and the Remote Config verify (OS.execute bun ...) + clipboard-export actions. Methods return {ok,error?}. catalog_edit.gd / story_catalog.gd / story_map_layout.gd stay as the pure static utilities the service calls.
- [x] Rewire Story Map dock as a view. Reduce story_map_editor/dock.gd to UI only: build via EditorToolUi (split_root, tabs, form_row), hold control refs + selection/drag state, bind StoryMapService signals (a 'changed' signal -> refresh tree/markers/status) with method callables, and call service methods for every mutation/save/validate/sync. plugin.gd switches to EditorToolPlugin._config() (no bridge). The interactive map canvas/overlay + dot _gui_input drag/placement stay in the dock (they are pure view), but they mutate through service.set_dot/place_dot rather than editing _layout directly. Net: same three output files, byte-identical; same status messages.
- [x] Story Map service verifier. Add game/tools/verify_story_map_service.gd (headless) exercising the now-testable logic without the editor: load catalog+layout via the service; add/remove a world + level and assert CatalogEdit results; place/move/remove a dot and assert normalized clamping + validate() catches unknown level_id / duplicate / out-of-0..1; serialize() round-trips to a byte-identical baked+canonical pair; a save writes all 3 targets and a forced write failure rolls back the catalog_version bump. This headless coverage is the migration's primary payoff — it did not exist before. Wire into the verifier list.
- [x] Docs + close-out. Update the Editor Tool Framework architecture node (recordSync with the final commit) and the editor-tools sections of game/CLAUDE.md + game/GODOT_PORT_PLAN.md to point new tools at editor_tool_kit/. Add the editor_tool_kit/README describing the three-piece authoring recipe (plugin _config + ToolService + dock). Confirm both tools' before/after output diffs are empty and record the migration commits on the brief.

## Data models & interfaces
```gdscript
# editor_tool_kit/editor_tool_plugin.gd — the bootstrap both tools collapse onto.
@tool
class_name EditorToolPlugin
extends EditorPlugin

var _service: Node
var _bridge: Node
var _dock: Control

# Subclasses override this; everything else is inherited.
func _config() -> Dictionary:
    return {}   # { panel:String, service:Script, dock:Script, bridge:Script? }

func _enter_tree() -> void:
    var c := _config()
    _service = (c["service"] as Script).new()
    add_child(_service)
    if c.has("bridge") and c["bridge"] != null:
        _bridge = (c["bridge"] as Script).new()
        _bridge.service = _service
        add_child(_bridge)
    _dock = (c["dock"] as Script).new()
    _dock.service = _service
    add_control_to_bottom_panel(_dock, c["panel"])

func _exit_tree() -> void:
    if _dock: remove_control_from_bottom_panel(_dock); _dock.free(); _dock = null
    if _bridge: _bridge.free(); _bridge = null
    if _service: _service.free(); _service = null
```

```gdscript
# editor_tool_kit/tool_service.gd — mandatory headless-testable core.
class_name ToolService
extends Node

var _dirty := false

func ok(data: Dictionary = {}) -> Dictionary:
    var out := {"ok": true}
    out.merge(data)
    return out

func err(msg: String, code := 0) -> Dictionary:
    return {"ok": false, "error": msg, "code": code}

func mark_dirty() -> void: _dirty = true
func clear_dirty() -> void: _dirty = false
func is_dirty() -> bool: return _dirty
# RULE: no Control / EditorInterface references in a ToolService subclass.
# Each subclass declares its own change signals; the dock binds them with
# method callables (not lambdas) so a hot-reload can't fire into a freed view.
```

```gdscript
# editor_tool_kit/content_store.gd — load / validate / atomic N-target write / rescan.
class_name ContentStore

static func load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return {}
    var d = JSON.parse_string(f.get_as_text())
    return d if d is Dictionary else {}

# targets: Array of { "path": String, "text": String }
# validate: Callable() -> Array (problem strings; non-empty aborts before any write)
static func save_all(targets: Array, validate: Callable, scan := true) -> Dictionary:
    var problems: Array = validate.call()
    if not problems.is_empty():
        return {"ok": false, "error": "\n".join(problems)}
    for t in targets:
        var f := FileAccess.open(t["path"], FileAccess.WRITE)
        if f == null:
            return {"ok": false, "error": "cannot write %s" % t["path"]}
        f.store_string(t["text"]); f.close()
    if scan:                                    # editor-only; headless passes scan=false
        EditorInterface.get_resource_filesystem().scan()
    return {"ok": true}

# Story Map's save: bump catalog_version, build the baked+canonical+layout
# target list, call save_all; if it returns ok=false, revert the version bump.
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
