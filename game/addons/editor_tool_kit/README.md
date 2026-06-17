# editor_tool_kit

Shared, **editor-only** base classes for in-editor authoring tools. A new tool is
a *service + a view* — persistence, layout, status, and optional MCP/CLI access
are inherited. This is a **library addon**: it mounts no UI of its own (its
`plugin.gd` is a no-op); enabling it just keeps the `class_name` globals
registered for the tools that subclass them.

Consumers today: `addons/artgen/` (full: plugin + service + bridge + dock) and
`addons/story_map_editor/` (plugin + service + dock, no bridge).

## The three-piece recipe

A tool is three small files that each subclass a base:

```
addons/<tool>/
  plugin.gd          extends EditorToolPlugin   → _config() declares the pieces
  <tool>_service.gd  extends ToolService        → state + signals, ok()/err(), headless-safe
  dock.gd            extends Control            → the view; binds the service, renders
  (bridge.gd         extends BridgeServer)      → OPTIONAL: localhost HTTP for an MCP/CLI shim
```

1. **`plugin.gd`** — override `_config()` only:

   ```gdscript
   @tool
   extends "res://addons/editor_tool_kit/editor_tool_plugin.gd"

   const ServiceT := preload("res://addons/<tool>/<tool>_service.gd")
   const DockT := preload("res://addons/<tool>/dock.gd")

   func _config() -> Dictionary:
       return {
           "panel": "My Tool",          # bottom-panel tab title
           "service": ServiceT,
           "dock": DockT,
           # "bridge": BridgeT,         # optional
           "service_name": "MyService", # optional cosmetic node names
           "dock_name": "MyTool",
       }
   ```

   `EditorToolPlugin` constructs `service` → (`bridge`) → `dock` (injecting the
   service into the bridge + dock), mounts the dock **beneath an enforced header**
   (tool title left; version + a self-reload button right) in the bottom panel,
   and reverses it all in `_exit_tree`. The version is read from the tool's own
   `plugin.cfg` and the reload button disable→enables the plugin, so a tool gets
   both for free — the dock builds none of it. Register the tool in
   `project.godot [editor_plugins]` and commit the `.gd.uid` files.

2. **`<tool>_service.gd`** — the headless-testable core (`ToolService`):

   - owns the tool's state, declares its own change signals;
   - returns `ok(data := {})` / `err(msg, code := 0)` for the `{ok, error?}`
     contract, and tracks `mark_dirty()` / `is_dirty()`;
   - **carries NO `Control` / `EditorInterface` references** so it loads and runs
     under `godot --headless` — which is what makes the tool's logic verifiable
     without the editor. Bind its signals from the dock with **method callables**
     (not lambdas) so a hot-reload / late async signal can't fire into a freed
     view.

3. **`dock.gd`** — a `Control` with a `service` property (the base injects it).
   Pure view: build with the `EditorToolUi` builders, hold control refs +
   interaction state, and re-render when the service emits its change signal.

## The other primitives

- **`ContentStore`** (static) — `load_json(path)`, atomic N-target write
  `save_all(targets, validate, scan := true)` (validate-then-write-all, editor
  rescan), and `bump_then(struct, key, do_save, when := true)` (version bump that
  rolls back if the save fails). The canonical serializer stays per-tool (field
  order is domain-specific; see `story_map_editor/catalog_edit.gd`).
- **`EditorToolUi`** (static) — `split_root`, `tool_header` (the enforced
  title/version/reload bar the plugin mounts), `label_wrap`, `form_row`,
  `button`, `button_bar`, `spin`, `status_label`, `restyle_selected`. Pure
  construction, no state; adopt incrementally with no visual change.
- **`BridgeServer`** — optional localhost HTTP base (TCPServer poll loop +
  Content-Length framing + async dispatch + headless skip). A subclass overrides
  `_resolve_port()` and `_route(method, path, query, body) -> {code, payload}`.
  Opt-in per tool (ArtGen is the only consumer).

## Verifying

Headless, no editor:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script res://tools/verify_editor_tool_kit.gd      # the bases
    --script res://tools/verify_story_map_service.gd     # a service migrated onto them
```
