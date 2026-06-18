@tool
extends "res://addons/editor_tool_kit/editor_tool_plugin.gd"

## Remote Config editor plugin: a bottom-panel dock that aggregates every
## committed validator/content/<key>.json blob (per app_config.manifest.json) into
## the single Snapser app-config/v1 document, copies the full publish payload, and
## runs Check Sync. Pure editor-side authoring; no runtime/game dependency and no
## bridge (publishing is a manual console paste). The shared EditorToolPlugin base
## constructs the RemoteConfigService + dock and mounts/tears them down.

const ServiceT := preload("res://addons/remote_config_editor/remote_config_service.gd")
const DockT := preload("res://addons/remote_config_editor/dock.gd")


func _config() -> Dictionary:
	return {
		"panel": "Remote Config",
		"service": ServiceT,
		"dock": DockT,
		"service_name": "RemoteConfigService",
		"dock_name": "RemoteConfig",
	}
