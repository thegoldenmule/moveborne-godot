@tool
extends "res://addons/editor_tool_kit/editor_tool_plugin.gd"

## Story Map editor plugin: a bottom-panel dock for placing the per-level dots
## that the Story Mode map renders. Pure editor-side authoring — it reads the
## committed story_catalog.json + story_maps.json and writes the catalog
## (baked + canonical) + story_maps.json. No runtime/game dependency and no
## bridge (placement needs no cloud service). The shared EditorToolPlugin base
## constructs the StoryMapService + dock and mounts/tears them down.

const ServiceT := preload("res://addons/story_map_editor/story_map_service.gd")
const DockT := preload("res://addons/story_map_editor/dock.gd")


func _config() -> Dictionary:
	return {
		"panel": "Story Map",
		"service": ServiceT,
		"dock": DockT,
		"service_name": "StoryMapService",
		"dock_name": "StoryMap",
	}
