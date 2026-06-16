@tool
extends EditorPlugin

## Story Map editor plugin: a bottom-panel dock for placing the per-level dots
## that the Story Mode map renders. Pure editor-side authoring — it reads the
## committed story_catalog.json + story_maps.json and writes story_maps.json.
## No runtime/game dependency and no bridge (placement needs no cloud service).

const DockT := preload("res://addons/story_map_editor/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = DockT.new()
	_dock.name = "StoryMap"
	add_control_to_bottom_panel(_dock, "Story Map")


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.free()
		_dock = null
