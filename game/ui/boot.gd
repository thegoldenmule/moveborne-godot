extends Node
## Boot scene (run/main_scene). Hands off immediately to the UiRouter, which mounts
## the shell as the root UI state. Keeps the engine's current_scene tiny + stable
## (the live match lives under UiRouter.content_root and is found via the
## 'mb_match' group, not current_scene).

const ShellStateS := preload("res://ui/router/shell_state.gd")


func _ready() -> void:
	UiRouter.reset(ShellStateS.new())
