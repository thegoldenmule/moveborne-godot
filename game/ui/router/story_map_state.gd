extends "res://ui/router/ui_state.gd"
## The Story world-map route: pushed by the Home Story button, sits between
## ShellState and MatchState in the stack —
##   [ShellState, StoryMapState]              -> browsing the map
##   [ShellState, StoryMapState, MatchState]  -> playing a level
## Owns the story_map screen; pushes MatchState when the screen asks to play a
## level, and on resume (the match popped) shows the banked level result, then
## refreshes progress from the server.

const StoryMapScene := preload("res://ui/screens/story_map.tscn")
const MatchStateS := preload("res://ui/router/match_state.gd")

var _root: Node       # UiRouter.content_root
var _screen: Control


func _init(content_root: Node) -> void:
	_root = content_root


func enter(_params: Dictionary) -> void:
	_screen = StoryMapScene.instantiate()
	_screen.play_level.connect(_on_play_level)
	_screen.closed.connect(_on_closed)
	_root.add_child(_screen)
	await Engine.get_main_loop().process_frame
	await UiRouter.reveal()
	# Fetch catalog + progress after the reveal (the screen shows its own
	# loading state); detached so a slow network never wedges the router.
	_screen.refresh()


func exit() -> void:
	await UiRouter.cover()
	if is_instance_valid(_screen):
		_screen.queue_free()


func suspend() -> void:
	# A match is covering the map.
	await UiRouter.cover()
	if is_instance_valid(_screen):
		_screen.visible = false


func resume() -> void:
	# Back from a match: surface the level result first (reads the result the
	# match banked in GameState.last_result), then re-fetch server progress.
	if is_instance_valid(_screen):
		_screen.visible = true
		_screen.show_result(GameState.last_result)
	await UiRouter.reveal()
	if is_instance_valid(_screen):
		_screen.refresh()
	# Flush the banked result to the leaderboards now — the shell (which
	# normally does this on resume) stays suspended while the player keeps
	# playing levels, and a second launch would overwrite last_result.
	var tree := Engine.get_main_loop() as SceneTree
	var shell = tree.get_first_node_in_group("mcp_shell") if tree != null else null
	if shell != null and shell.has_method("flush_pending_result"):
		shell.flush_pending_result()


func _on_play_level(cfg: Dictionary) -> void:
	if UiRouter.is_busy():
		return
	UiRouter.push(MatchStateS.new(UiRouter.content_root), cfg)


func _on_closed() -> void:
	if UiRouter.is_busy():
		return
	UiRouter.pop()


func state_name() -> String:
	return "StoryMapState"
