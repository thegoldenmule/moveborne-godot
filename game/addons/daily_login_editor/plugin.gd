@tool
extends "res://addons/editor_tool_kit/editor_tool_plugin.gd"

## Daily Login Bonus editor plugin: a bottom-panel dock for authoring the login
## calendar (per-day currency + amount) that rides in Remote Config. Pure
## editor-side authoring — it reads/writes the single committed
## validator/content/daily_login.json (no baked copy, no bridge). The shared
## EditorToolPlugin base constructs the DailyLoginService + dock and mounts/tears
## them down. Publishing to Remote Config is the Remote Config tool's job; this
## tool only writes the blob (and emits the ladder + quest provisioning readout).

const ServiceT := preload("res://addons/daily_login_editor/daily_login_service.gd")
const DockT := preload("res://addons/daily_login_editor/dock.gd")


func _config() -> Dictionary:
	return {
		"panel": "Daily Login",
		"service": ServiceT,
		"dock": DockT,
		"service_name": "DailyLoginService",
		"dock_name": "DailyLogin",
	}
