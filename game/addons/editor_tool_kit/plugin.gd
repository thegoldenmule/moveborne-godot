@tool
extends EditorPlugin

## editor_tool_kit is a LIBRARY addon: it ships the shared base classes for
## in-editor authoring tools — EditorToolPlugin, ToolService, ContentStore,
## EditorToolUi, and BridgeServer (see each file + README.md). It mounts nothing
## of its own; enabling the plugin simply keeps the addon active so its
## class_name globals stay registered for the tools that subclass them.
##
## Concrete tools (addons/artgen, addons/story_map_editor) each ship their own
## EditorPlugin (an EditorToolPlugin subclass) — this plugin is not their host.
