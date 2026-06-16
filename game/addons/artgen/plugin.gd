@tool
extends "res://addons/editor_tool_kit/editor_tool_plugin.gd"

## ArtGen editor plugin. Declares its pieces via _config(); the shared
## EditorToolPlugin base constructs the UI-free service, the localhost bridge for
## the MCP shim, and the bottom-panel dock (injecting the service into both) and
## tears them down in reverse. The MCP shim (tools/artgen_mcp.ts) is a stateless
## proxy to the bridge.

const ServiceT := preload("res://addons/artgen/artgen_service.gd")
const BridgeT := preload("res://addons/artgen/bridge.gd")
const DockT := preload("res://addons/artgen/dock.gd")


func _config() -> Dictionary:
	return {
		"panel": "ArtGen",
		"service": ServiceT,
		"bridge": BridgeT,
		"dock": DockT,
		"service_name": "ArtgenService",
		"bridge_name": "ArtgenBridge",
		"dock_name": "ArtGen",
	}
