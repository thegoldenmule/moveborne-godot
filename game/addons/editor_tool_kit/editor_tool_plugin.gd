@tool
class_name EditorToolPlugin
extends EditorPlugin

## Shared bootstrap for in-editor authoring tools. A concrete tool subclasses
## this and overrides _config() to declare its pieces; the base constructs them
## in the right order, injects the service into the (optional) bridge + dock,
## mounts the dock in the bottom panel, and tears everything down in reverse on
## _exit_tree. This collapses the ~25–37 line per-tool plugin.gd boilerplate.
##
## _config() -> {
##   "panel":   String,          # bottom-panel tab title
##   "service": Script,          # a ToolService subclass (constructed first)
##   "dock":    Script,          # a Control exposing a `service` property
##   "bridge":  Script = null,   # optional BridgeServer subclass
##   # optional cosmetic node names (preserve parity with the pre-migration tool):
##   "service_name": String = "",
##   "dock_name":    String = "",
##   "bridge_name":  String = "",
## }
##
## Construction order mirrors the hand-written plugins exactly: service →
## (bridge) → dock, with `service` injected before each child is added so an
## early _ready/_enter_tree always sees it.

var _service: Node
var _bridge: Node
var _dock: Control


## Override in a subclass to declare the tool. The base returns {} and mounts
## nothing (so editor_tool_kit's own library plugin stays a no-op).
func _config() -> Dictionary:
	return {}


func _enter_tree() -> void:
	var c := _config()
	if c.is_empty():
		return

	_service = (c["service"] as Script).new()
	if str(c.get("service_name", "")) != "":
		_service.name = str(c["service_name"])
	add_child(_service)

	if c.get("bridge") != null:
		_bridge = (c["bridge"] as Script).new()
		if str(c.get("bridge_name", "")) != "":
			_bridge.name = str(c["bridge_name"])
		_bridge.service = _service
		add_child(_bridge)

	_dock = (c["dock"] as Script).new()
	if str(c.get("dock_name", "")) != "":
		_dock.name = str(c["dock_name"])
	_dock.service = _service
	add_control_to_bottom_panel(_dock, str(c["panel"]))


func _exit_tree() -> void:
	# The dock lives in the bottom panel (not a child of this plugin), so it must
	# be removed + freed explicitly. The service + bridge are children (add_child
	# above); freeing them here is equivalent to letting the plugin's own teardown
	# reap them, but explicit + ordered is clearer and lets each run its own
	# _exit_tree (e.g. the bridge stops its TCP server) deterministically.
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.free()
		_dock = null
	if _bridge != null:
		_bridge.free()
		_bridge = null
	if _service != null:
		_service.free()
		_service = null
