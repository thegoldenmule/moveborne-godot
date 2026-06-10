@tool
extends EditorPlugin

## ArtGen editor plugin: owns the UI-free service, the localhost bridge for the
## MCP shim, and the bottom-panel dock. Everything lives in the editor process —
## the MCP shim (tools/artgen_mcp.ts) is a stateless proxy to the bridge.

const ServiceT := preload("res://addons/artgen/artgen_service.gd")
const BridgeT := preload("res://addons/artgen/bridge.gd")
const DockT := preload("res://addons/artgen/dock.gd")

var _service: Node
var _bridge: Node
var _dock: Control


func _enter_tree() -> void:
	_service = ServiceT.new()
	_service.name = "ArtgenService"
	add_child(_service)

	_bridge = BridgeT.new()
	_bridge.name = "ArtgenBridge"
	_bridge.service = _service
	add_child(_bridge)

	_dock = DockT.new()
	_dock.name = "ArtGen"
	_dock.service = _service
	add_control_to_bottom_panel(_dock, "ArtGen")


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.free()
		_dock = null
