extends "res://ui/router/ui_state.gd"
## Pushes the existing match scene (scenes/main.tscn) as a full-screen takeover.
## The shell is suspended (cover + hidden) by the router before enter() runs, so
## enter() just mounts the match under black and reveals it.

const MATCH_SCENE := "res://scenes/main.tscn"
var _root: Node       # UiRouter.content_root
var _scene: Node


func _init(content_root: Node) -> void:
	_root = content_root


func enter(params: Dictionary) -> void:
	GameState.next_match = params
	_scene = load(MATCH_SCENE).instantiate()
	_root.add_child(_scene)
	if _scene.has_signal("match_exited"):
		_scene.match_exited.connect(_on_match_exited)
	await Engine.get_main_loop().process_frame  # let main._ready build the board
	await UiRouter.reveal()


func exit() -> void:
	# Fade to black, then free the match (drops the MbMatch ref + validator Node +
	# the match's CanvasLayers). resume() on the shell reveals from black.
	await UiRouter.cover()
	if is_instance_valid(_scene):
		_scene.queue_free()


func _on_match_exited(result: Dictionary) -> void:
	GameState.last_result = result
	UiRouter.pop()


func state_name() -> String:
	return "MatchState"
