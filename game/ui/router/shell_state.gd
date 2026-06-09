extends "res://ui/router/ui_state.gd"
## The persistent root state: owns app_shell.tscn (bottom nav + content host),
## instanced once into UiRouter.content_root. Tabs switch INSIDE the shell
## (a flat selector), so tab changes are NOT router pushes.

const SHELL_SCENE := "res://ui/shell/app_shell.tscn"
var _shell: Control


func _init() -> void:
	blocks_below = false  # nothing sits below the shell


func enter(_params: Dictionary) -> void:
	if not is_instance_valid(_shell):
		_shell = load(SHELL_SCENE).instantiate()
		UiRouter.content_root.add_child(_shell)
	_shell.set_active(true)
	await Engine.get_main_loop().process_frame


func suspend() -> void:
	# A match is covering us: fade to black, then hide the shell + its nav CanvasLayer.
	await UiRouter.cover()
	if is_instance_valid(_shell):
		_shell.set_active(false)


func resume() -> void:
	# The match popped (it left us on black): show the shell, then reveal it.
	if is_instance_valid(_shell):
		_shell.set_active(true)
	await UiRouter.reveal()


func state_name() -> String:
	return "ShellState"
