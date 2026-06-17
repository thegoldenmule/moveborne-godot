# Editor Tool Framework

**Status:** current

## Kind
layer

## Summary
The common structure for Moveborne's in-editor authoring tools — the `@tool` addons that run inside the Godot editor (not the game) to produce committed content. **Built and live** as `game/addons/editor_tool_kit/` (commit ab96f10): five shared primitives — **`EditorToolPlugin`** (plugin bootstrap + bottom-panel mount/teardown), **`ToolService`** (a `Node` state base with `ok()`/`err()` + dirty tracking and no `Control`/`EditorInterface` deps, so it runs headless), **`ContentStore`** (load → validate → atomic N-target write → rescan, with version-bump rollback), **`EditorToolUi`** (the shared `HSplitContainer`/`label_wrap`/`form_row`/`status_label`/selection-restyle builders), and an optional **`BridgeServer`** (localhost HTTP base for an MCP/CLI shim). Both editor tools build on it: **ArtGen** (`addons/artgen/`) re-bases its plugin + `ArtgenService(ToolService)` + `ArtgenBridge(BridgeServer)` (`:4848`, all routes preserved); **Story Map** (`addons/story_map_editor/`) split its ~1,000-line monolithic dock into a headless-testable `StoryMapService(ToolService)` + a thin view, with the baked+canonical+layout save moving behind `ContentStore`. A new authoring tool is now a service + a view. **Distribution (commit e022279):** the kit is vendored/committed but *sourced* from the standalone repo `github.com/thegoldenmule/godot-editor-tk`, and its own `plugin.gd` — formerly a no-op library plugin — now mounts one thing of its own: an **Editor Tool Kit** bottom-panel tab that checks that repo and self-updates the addon in place (its `UpdateService` is a `ToolService` and its `UpdatePanel` the dock, so the kit dogfoods its own bases), mirroring how the godot-ai plugin distributes itself. Headless coverage: `tools/verify_editor_tool_kit.gd` (the bases + the self-update version/extract-mapping helpers) and `tools/verify_story_map_service.gd`. See `game/addons/editor_tool_kit/README.md` for the recipe.

## Purpose
Two real costs motivate the framework. **Duplication:** each tool hand-rolls the same plugin bootstrap, bottom-panel mount/teardown, pure-code `HSplitContainer` layout with min-size floors, JSON read / `JSON.stringify` write, post-write `EditorInterface.get_resource_filesystem().scan()`, and `{ok, error}` status plumbing. **Untestability:** because Story Map fuses its logic into a `Control` that only exists inside a running editor, none of its mutation / serialize / atomic-write logic can run under the headless verifier loop the rest of the project leans on (`godot --headless --script res://tools/verify_*.gd`). ArtGen avoided this by putting all state and logic in a `Service` *node* the dock merely observes — which is exactly why a framework should make the service layer mandatory and the editor-only view optional. The payoff is leverage: the next authoring tool (a totem editor, a scenario tuner, a level balancer) should be ~a service + a view, inheriting persistence, layout, status feedback, and optional MCP/CLI access for free.

## Design notes
Current state vs. target. ArtGen already conforms to ~80% of the target: its artgen_service.gd is a ToolService in all but name (state + signals + {ok,error} methods), bridge.gd is the BridgeServer, and plugin.gd is the EditorToolPlugin bootstrap — the framework would mostly lift these into shared base classes and delete the per-tool copies. Story Map is the inverse: its dock.gd is a monolith whose data layer (catalog_edit.gd serialize + the 3-file atomic save) is the canonical reference for ContentStore but currently cannot run outside the editor. The framework lands first as new shared code; the two tools then migrate onto it one commit at a time, with behavior held byte-identical (same files, same bridge port, same MCP surface).

```gdscript
# Aspirational base classes (game/addons/editor_tool_kit/).
# Plugin shrinks to a declaration:
@tool
class_name ArtgenPlugin extends EditorToolPlugin
func _config() -> Dictionary:
    return {
        "panel": "ArtGen",
        "service": preload("artgen_service.gd"),
        "dock": preload("dock.gd"),
        "bridge": preload("bridge.gd"),   # optional; omit for Story Map
    }

# ToolService: the mandatory headless-testable core.
class_name ToolService extends Node
signal changed                              # view re-reads on this
var _dirty := false
func ok(data := {}) -> Dictionary: return {"ok": true}.merged(data)
func err(msg: String, code := 0) -> Dictionary:
    return {"ok": false, "error": msg, "code": code}
```

```gdscript
# ContentStore: load -> validate -> atomic N-target write -> rescan.
# Generalizes Story Map's hand-written baked+canonical+layout save.
static func save_all(targets: Array, validate: Callable, on_ok: Callable) -> Dictionary:
    var problems: Array = validate.call()
    if not problems.is_empty():
        return {"ok": false, "error": "\n".join(problems)}
    # serialize once per target, then write all-or-nothing
    for t in targets:                       # t = {path, text}
        var f := FileAccess.open(t["path"], FileAccess.WRITE)
        if f == null:
            return {"ok": false, "error": "cannot write %s" % t["path"]}
        f.store_string(t["text"]); f.close()
    EditorInterface.get_resource_filesystem().scan()
    on_ok.call()
    return {"ok": true}
```

Self-update / distribution (commit e022279; source repo seeded b85ec5f, hardened 501411d). The kit is vendored into a consuming project (a fresh clone works offline) but its source of truth is the standalone repo github.com/thegoldenmule/godot-editor-tk (layout: addons/editor_tool_kit/ at repo root + a repo README). The "Editor Tool Kit" bottom-panel tab is three pieces built on the kit's own framework: (1) update_service.gd, a ToolService that owns the version check — it reads the repo's plugin.cfg RAW from the default branch (raw.githubusercontent.com) and downloads the branch-archive zip — with static parse_remote_version / is_newer helpers the headless verifier exercises; (2) update_panel.gd, the dock (status line, Check / Update-now, and a Settings group: an auto-check-on-open EditorSetting + the source repo + Open repository); (3) update_reload_runner.gd, a Node parented OUTSIDE the plugin (so it survives set_plugin_enabled(false)) that disables the plugin, extracts ONLY the archive's addons/editor_tool_kit/ subtree (atomic .tmp+rename per file with rollback; anchored-prefix mapping that accepts addons/editor_tool_kit/ directly or under one branch-archive wrapper segment but rejects deeper-nested copies; duplicate-target abort; and a FAILED_MIXED guard that leaves the plugin DISABLED rather than load a half-installed tree), waits for a filesystem scan, then re-enables the plugin — adapted from godot-ai's runner. Version IS the ship signal: bump `version` in the repo's plugin.cfg and push to the default branch; no GitHub-release ceremony. Limits: the extract overwrites + adds but never prunes (a file removed upstream lingers); an update clobbers local edits to the vendored copy (land changes in the repo); in-editor reload needs Godot 4.4+ (the project ships 4.6). The pipeline's data-loss class (find()-based mapping collapsing two entries onto one target) was caught by an adversarial review and fixed before ship.

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- file `ArtGen plugin bootstrap (EditorToolPlugin exemplar)` in `game/addons/artgen/plugin.gd`
- file `Stateful service + signals + {ok,error} (ToolService exemplar)` in `game/addons/artgen/artgen_service.gd`
- file `TCPServer HTTP bridge on :4848 (BridgeServer exemplar)` in `game/addons/artgen/bridge.gd`
- file `Signal-bound view dock (EditorToolUi exemplar)` in `game/addons/artgen/dock.gd`
- file `Monolithic dock to split into service + view` in `game/addons/story_map_editor/dock.gd`
- file `Canonical serialize + mutations (ContentStore reference)` in `game/addons/story_map_editor/catalog_edit.gd`
- class `EditorToolPlugin (plugin bootstrap base)` in `game/addons/editor_tool_kit/editor_tool_plugin.gd`
- class `ToolService (headless-safe state base)` in `game/addons/editor_tool_kit/tool_service.gd`
- class `ContentStore (load/validate/atomic-write/rollback)` in `game/addons/editor_tool_kit/content_store.gd`
- class `EditorToolUi (shared layout builders)` in `game/addons/editor_tool_kit/editor_tool_ui.gd`
- class `BridgeServer (optional localhost HTTP base)` in `game/addons/editor_tool_kit/bridge_server.gd`
- class `StoryMapService (Story Map logic, extracted onto ToolService)` in `game/addons/story_map_editor/story_map_service.gd`
- class `Editor Tool Kit plugin — mounts the self-update panel + hosts install_downloaded_update (was a no-op library plugin)` in `game/addons/editor_tool_kit/plugin.gd`
- class `UpdateService — self-update version check + archive download (a ToolService; static parse_remote_version/is_newer)` in `game/addons/editor_tool_kit/update_service.gd`
- class `UpdatePanel — self-update dock (Check / Update now + Settings)` in `game/addons/editor_tool_kit/update_panel.gd`
- class `Update reload runner — detached extract (anchored prefix + rollback + FAILED_MIXED) → fs scan → plugin reload` in `game/addons/editor_tool_kit/update_reload_runner.gd`

## Data model
The framework is five primitives, each a thin extraction of what ArtGen already proves in production:

- **`EditorToolPlugin`** (`EditorPlugin` base) — constructs the service (+ optional bridge) and dock, injects the service into both, mounts the dock via `add_control_to_bottom_panel`, and reverses it all in `_exit_tree`. Replaces the near-identical ~25–37 line `plugin.gd` in each tool.
- **`ToolService`** (`Node` base) — state owner + signal emitter. Contract: every public method returns a `Dictionary` shaped `{ "ok": bool, "error"?: String, ... }`; mutations flip a dirty flag; change signals drive the view. Editor-free, hence headless-testable.
- **`ContentStore`** (helper) — the load → validate → atomic-write → rescan cycle: default-`{}` on missing, dirty tracking, save-time version bump with rollback on any write failure, canonical JSON serialization (stable key order + integer coercion + sparse fields — Story Map's `serialize()` is the reference impl), and **N-target byte-identical write** (Story Map writes 3 synced copies today — baked + canonical + layout — by hand).
- **`EditorToolUi`** (helper) — the layout idioms both tools reinvent: `HSplitContainer` root with min-size floors, `label_wrap` / row builders (label + expanding control), rebuild-form-on-selection, `StyleBoxFlat` selection restyle, and a one-line status `Label` driven from `{ok, error}`.
- **`BridgeServer`** (`Node` mixin, optional) — `TCPServer` + `_process` poll loop, `Content-Length` request framing, an async `match [method, path]` route table that can `await` service coroutines, and a headless skip. ArtGen's `bridge.gd` generalized so any tool can expose itself to the MCP shim or a CLI.

## Usage
A new editor tool is authored as three small pieces on top of the framework:

1. **Plugin** — a ~3-line `class_name FooPlugin extends EditorToolPlugin` that declares its dock class + panel name; the base handles `_enter_tree` / `_exit_tree`, mount, and teardown.
2. **Service** — `class_name FooService extends ToolService` (a `Node`): owns the in-memory model + config, exposes domain methods returning `{ok, error, ...}`, and emits change signals. No `Control` / `EditorInterface` deps, so it runs headless and is covered by a `verify_foo.gd` script.
3. **Dock** — a `Control` built with `EditorToolUi` helpers that binds the service's signals (method callables, for hot-reload safety) and calls its methods. Persistence flows through `ContentStore` (load → mutate → validate → atomic multi-target write → `fs.scan()`, with dirty tracking + version-bump rollback). Tools that want MCP/CLI access add a `BridgeServer` (ArtGen's `:4848` pattern) — opt-in, and a no-op under headless.

The existing **SVG Trim** tool (see the sibling *Editor Tools* node) is the trivial end of the spectrum — a pure static helper with no dock — and is left as-is; the framework targets the stateful, dock-bearing tools.

## Invariants & constraints
- A tool's logic lives in a ToolService Node with no Control / EditorInterface dependencies, so it runs under the headless verifier; the dock is a thin observer that binds the service's signals and calls its methods.
- All content writes go through ContentStore: validate-before-write, atomic all-or-nothing across N targets, any save-time version bump rolled back on a write failure, followed by an EditorInterface filesystem rescan.
- Every service method returns a {ok, error?} Dictionary; the dock never throws or asserts — it surfaces failures in a single status Label.
- Bridge / HTTP access is opt-in per tool and a no-op under headless (DisplayServer.get_name() == "headless"), so verifiers and CLI runs never bind a port.
- Dock-to-service signal bindings use method callables (not lambdas), so a plugin hot-reload cannot fire a late signal into a freed Control.
- The kit is vendored/committed but sourced from github.com/thegoldenmule/godot-editor-tk; the in-editor self-update writes ONLY the archive's addons/editor_tool_kit/ subtree (anchored prefix, never prunes other files) and, on a failed install, rolls back — refusing to re-enable the plugin if rollback leaves a mixed old+new tree. Shipping an update = bump plugin.cfg version + push to the default branch (version is the ship signal).

## Synced commit
e022279c55178660c39dc590dc0ae8dcfcdd1dcc
