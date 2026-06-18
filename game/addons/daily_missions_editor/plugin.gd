@tool
extends "res://addons/editor_tool_kit/editor_tool_plugin.gd"

## Daily Missions editor plugin: a bottom-panel dock for authoring the daily
## mission catalog + the 7-day rotation that ride in Remote Config. Pure
## editor-side authoring — it reads/writes the single committed
## validator/content/daily_missions.json (no baked copy, no bridge). The shared
## EditorToolPlugin base constructs the DailyMissionsService + dock and
## mounts/tears them down. Publishing to Remote Config is the Remote Config tool's
## job; this tool only writes the blob.

const ServiceT := preload("res://addons/daily_missions_editor/daily_missions_service.gd")
const DockT := preload("res://addons/daily_missions_editor/dock.gd")


func _config() -> Dictionary:
	return {
		"panel": "Daily Missions",
		"service": ServiceT,
		"dock": DockT,
		"service_name": "DailyMissionsService",
		"dock_name": "DailyMissions",
	}
