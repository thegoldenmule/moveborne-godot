extends Node

## MbDebug — game-semantic command layer for LLM/automation control.
##
## This is the Godot analog of the TypeScript game's `window.__moveborne` debug API.
## It is an autoload singleton (`MbDebug`) that an LLM drives via the godot-ai MCP
## addon's `game_eval` command, e.g.:
##
##     return MbDebug.get_state()
##     MbDebug.swipe("up")
##     MbDebug.play_card(2)            # -> {"status":"awaiting_selection","selection_mode":"tile"}
##     MbDebug.select_tile(1, 3)       # -> {"status":"complete"}
##
## It is a THIN facade. All mutation routes through the live match scene
## (`scenes/main.gd`'s `mcp_*` methods), which reuse the exact targeting state
## machine the player uses — so plays animate the board, hand, and VFX normally.
## All reads come off the live `MbMatch.state`. Nothing here touches `engine/`, so
## determinism parity is unaffected. See MCP_GAME_API.md for the full reference.

const NOT_READY := {"ok": false, "reason": "not_ready",
	"message": "no live match — open the main scene (project_run) first"}

# State-history store (mirrors __moveborne's stateHistory). Snapshots are deep
# copies keyed by moveIndex, captured on every MbMatch.changed.
var _bound_match = null      # the MbMatch instance we're currently listening to
var _snaps: Array = []       # ordered Array of deep-copied state snapshots
var _last_mi: int = -1       # moveIndex of the most recent snapshot


func _process(_delta: float) -> void:
	# Keep the history binding fresh: re-bind whenever the active match instance
	# changes (e.g. a scene reload creates a new MbMatch). Cheap identity check.
	var m = _match()
	if m != _bound_match:
		_rebind(m)


func _rebind(m) -> void:
	if _bound_match != null and is_instance_valid(_bound_match) \
			and _bound_match.changed.is_connected(_on_match_changed):
		_bound_match.changed.disconnect(_on_match_changed)
	_bound_match = m
	_snaps.clear()
	_last_mi = -1
	if m != null:
		m.changed.connect(_on_match_changed)
		_on_match_changed()  # capture the current (initial) state


func _on_match_changed() -> void:
	var m = _bound_match
	if m == null or not is_instance_valid(m) or m.state.is_empty():
		return
	var mi := int(m.state.get("moveIndex", 0))
	# A fresh game/scenario restarts at moveIndex 0 (or rewinds) on the SAME match
	# instance — reset history so each match has its own timeline, like __moveborne.
	if not _snaps.is_empty() and (mi == 0 or mi < _last_mi):
		_snaps.clear()
	_snaps.append(m.state.duplicate(true))
	_last_mi = mi


# ── scene/match resolution ────────────────────────────────────────────────────

## The active main scene, if it exposes the MCP control surface; else null.
func _scene():
	var tree := get_tree()
	if tree == null:
		return null
	var sc = tree.current_scene
	if sc != null and sc.has_method("mcp_match"):
		return sc
	return null

## The live MbMatch, or null when no match scene is active.
func _match():
	var sc = _scene()
	return sc.mcp_match() if sc != null else null


# ── readiness ─────────────────────────────────────────────────────────────────

## True when a match is live and has a board (Godot's analog of __moveborne.isReady).
func is_ready() -> bool:
	var m = _match()
	return m != null and not m.state.is_empty() and m.state.has("board")


# ── movement (mutating, through the UI) ───────────────────────────────────────

const _DIRECTIONS := ["up", "down", "left", "right"]

## Swipe a direction ("up"/"down"/"left"/"right"). Returns {ok, moved, move_index}.
func swipe(direction: String) -> Dictionary:
	var sc = _scene()
	if sc == null:
		return NOT_READY
	if not _DIRECTIONS.has(direction):
		return {"ok": false, "reason": "bad_direction",
			"message": "direction must be one of %s" % str(_DIRECTIONS)}
	return sc.mcp_swipe(direction)

func up() -> Dictionary: return swipe("up")
func down() -> Dictionary: return swipe("down")
func left() -> Dictionary: return swipe("left")
func right() -> Dictionary: return swipe("right")


# ── reads (non-mutating) ──────────────────────────────────────────────────────

## The full synchronized game state Dictionary (board, hand, score, shards, …).
func get_state():
	var m = _match()
	return m.state if m != null else NOT_READY

## The board sub-object: {tiles: [...row-major...], size: int}.
func get_board():
	var m = _match()
	return m.state["board"] if m != null else NOT_READY

## The hand cards, mapped to [{index, id, type, name}].
func get_cards():
	var m = _match()
	if m == null:
		return NOT_READY
	var out: Array = []
	var cards: Array = m.state["hand"]["cards"]
	for i in range(cards.size()):
		var c: Dictionary = cards[i]
		var t := str(c["type"])
		out.append({"index": i, "id": str(c.get("id", "")), "type": t,
			"name": str(c.get("name", t))})
	return out

## Cards playable right now: [{index, type, name, selection_mode}] (delegates to
## the scene's single-source TARGET map; selection_mode "totem" for totem cards).
func get_playable_cards():
	var sc = _scene()
	return sc.mcp_playable_cards() if sc != null else NOT_READY

## The tile at (row, col), or null if empty/out of range. Tiles are row-major.
func get_tile(row: int, col: int):
	var m = _match()
	if m == null:
		return NOT_READY
	var board: Dictionary = m.state["board"]
	var size := int(board["size"])
	if row < 0 or col < 0 or row >= size or col >= size:
		return null
	var idx := row * size + col
	var tiles: Array = board["tiles"]
	return tiles[idx] if idx < tiles.size() else null


# ── state history (mirrors __moveborne.getHistory/getSnapshot/getHistoryCount) ──

## All state snapshots for the current match, oldest first.
func get_history() -> Array:
	return _snaps

## The snapshot whose moveIndex == move_index (latest match if duplicated), or null.
func get_snapshot(move_index: int):
	for i in range(_snaps.size() - 1, -1, -1):
		if int(_snaps[i].get("moveIndex", -1)) == move_index:
			return _snaps[i]
	return null

## Number of snapshots captured for the current match.
func get_history_count() -> int:
	return _snaps.size()


# ── cards (mutating, two-step, through the UI) ────────────────────────────────

## Begin playing the hand card at `index`. Returns one of:
##   {status:"complete"}                                  — played immediately
##   {status:"awaiting_selection", selection_mode:"tile"  — needs target(s); then
##        |"column"|"quadrant"|"two"}                       call select_tile/column
##   {status:"error", message}                            — invalid/unsupported card
func play_card(card_index: int) -> Dictionary:
	var sc = _scene()
	return sc.mcp_play_card(card_index) if sc != null else NOT_READY

## Alias of play_card (mirrors __moveborne.selectCard).
func select_card(card_index: int) -> Dictionary:
	return play_card(card_index)

## Supply a tile target (also: quadrant top-left, or first/second tile of a
## two-tile card) to the card awaiting selection. Returns a status Dictionary.
func select_tile(row: int, col: int) -> Dictionary:
	var sc = _scene()
	return sc.mcp_select_target(row, col) if sc != null else NOT_READY

## Supply a column target to the card awaiting a column. Returns a status Dictionary.
func select_column(col: int) -> Dictionary:
	var sc = _scene()
	return sc.mcp_select_column(col) if sc != null else NOT_READY

## Cancel an in-progress card selection.
func cancel() -> Dictionary:
	var sc = _scene()
	if sc == null:
		return NOT_READY
	sc.mcp_cancel()
	return {"ok": true}


# ── lifecycle ─────────────────────────────────────────────────────────────────

## Start a fresh Endless game (optionally seeded for reproducibility).
func new_game(seed_value: int = -1) -> Dictionary:
	var sc = _scene()
	return sc.mcp_new_game(seed_value) if sc != null else NOT_READY

## Load a built-in scenario: 0–7, 17 ("Fracture" glitch), 101 (black-hole tile).
func load_scenario(scenario_id: int, seed_value: int = -1) -> Dictionary:
	var sc = _scene()
	return sc.mcp_load_scenario(scenario_id, seed_value) if sc != null else NOT_READY


# ── utility ───────────────────────────────────────────────────────────────────

## A compact summary of the current state (for quick inspection / logging).
func inspect() -> Dictionary:
	var m = _match()
	if m == null:
		return NOT_READY
	var st: Dictionary = m.state
	var board: Dictionary = st["board"]
	var non_empty := 0
	for t in board["tiles"]:
		if not bool((t as Dictionary).get("isEmpty", true)):
			non_empty += 1
	return {
		"scenario": str(m.scenario_name),
		"move_index": int(st.get("moveIndex", 0)),
		"score": int(st.get("score", 0)),
		"shards": int(st.get("shards", 0)),
		"combo_multiplier": int(st.get("comboMultiplier", 1)),
		"cards": (st["hand"]["cards"] as Array).size(),
		"board_size": int(board["size"]),
		"non_empty_tiles": non_empty,
		"history_count": _snaps.size(),
	}

## Human-readable list of the available commands.
func help() -> String:
	return """MbDebug — game-semantic control (call via godot-ai game_eval). See MCP_GAME_API.md.
  readiness : is_ready()
  movement  : up() down() left() right() swipe(dir)
  reads     : get_state() get_board() get_cards() get_playable_cards() get_tile(r,c)
  history   : get_history() get_snapshot(moveIndex) get_history_count()
  cards     : play_card(i) -> then select_tile(r,c) / select_column(c) ; select_card(i) ; cancel()
  lifecycle : new_game(seed=-1) load_scenario(id, seed=-1)   # ids 0-7, 17, 101
  utility   : inspect() help()"""
