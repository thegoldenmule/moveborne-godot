extends Control
## The Leaderboard tab: daily / weekly / monthly global high-score boards from
## the Snapser Leaderboards snap. Shows the top 10 plus the player's own
## standing. The shell calls refresh() each time the tab becomes visible;
## sign-in is lazy (first fetch triggers the anonymous session).

## Preloaded (not the class_name global): fresh class_name registration needs a
## full editor scan, which scenes must not depend on.
const LbClientS := preload("res://net/leaderboards_client.gd")

const TOP_COUNT := 10
const PERIODS := [
	["Daily", LbClientS.BOARD_DAILY],
	["Weekly", LbClientS.BOARD_WEEKLY],
	["Monthly", LbClientS.BOARD_MONTHLY],
]
## The shell insets the content host between the top band and bottom nav, so the
## screen only needs its own breathing room from those edges.
const EDGE_PADDING := 16.0
const SIDE_MARGIN := 24.0

@onready var _vbox: VBoxContainer = $VBox
@onready var _title: Label = $VBox/Title
@onready var _periods_row: HBoxContainer = $VBox/Periods
@onready var _period_btns: Array = [
	$VBox/Periods/Daily, $VBox/Periods/Weekly, $VBox/Periods/Monthly,
]
@onready var _scroll: ScrollContainer = $VBox/Scroll
@onready var _rows: VBoxContainer = $VBox/Scroll/Rows
@onready var _own: Label = $VBox/OwnRank
@onready var _status: Label = $VBox/Status

var _auth: MbSnapserAuth
var _client: Node  # MbLeaderboardsClient
var _board: String = LbClientS.BOARD_DAILY
var _fetch_id := 0  # increments per refresh; stale responses are dropped


## Injected by the shell before the scene enters the tree.
func setup(auth: MbSnapserAuth, client: Node) -> void:
	_auth = auth
	_client = client


func _ready() -> void:
	# Root size comes from the shell (already inset clear of the top band and
	# bottom nav); the VBox fills it minus a little edge padding.
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.offset_left = SIDE_MARGIN
	_vbox.offset_right = -SIDE_MARGIN
	_vbox.offset_top = EDGE_PADDING
	_vbox.offset_bottom = -EDGE_PADDING
	_vbox.add_theme_constant_override("separation", 14)

	# Grammara is wide: 24px is the biggest "LEADERBOARD" that fits the narrow
	# logical viewport (the Home hero fits 34 only because its word is shorter).
	_title.text = "LEADERBOARD"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", MbStyle.PRIMARY)

	# Daily / Weekly / Monthly as a radio row; selecting refetches that board.
	_periods_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_periods_row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in _period_btns.size():
		var b: Button = _period_btns[i]
		b.text = PERIODS[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(88, 40)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_period_pressed.bind(i))
	(_period_btns[0] as Button).button_pressed = true

	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)

	_own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_own.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_own.add_theme_font_size_override("font_size", 16)
	_own.add_theme_color_override("font_color", MbStyle.TEXT)
	_own.text = ""

	# Long error strings (snap messages) wrap instead of running offscreen.
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", MbStyle.DIM)
	_status.text = ""


func _on_period_pressed(index: int) -> void:
	_board = PERIODS[index][1]
	refresh()


## Refetch the current board. Called by the shell when the tab is selected and
## by the period toggle. Coroutine internally; safe to fire-and-forget.
func refresh() -> void:
	if _client == null:
		_status.text = "Offline — leaderboards unavailable."
		return
	_fetch_id += 1
	var fid := _fetch_id
	_status.text = "Consulting the spirits…"
	_own.text = ""
	_clear_rows()

	var top: Dictionary = await _client.fetch_scores(_board, "top", TOP_COUNT)
	if fid != _fetch_id or not is_inside_tree():
		return  # a newer refresh superseded this one
	if not bool(top.get("ok", false)):
		_status.text = "The veil is silent — %s" % str(top.get("error", "error"))
		return
	var scores: Array = top.get("scores", [])
	if scores.is_empty():
		_status.text = "No scores yet this period. Be the first."
	else:
		_status.text = ""
		for row in scores:
			_rows.add_child(_make_row(row))

	# The player's own standing. range=around returns a WINDOW of neighbors, so
	# pick the caller's row out of it. A user with no score this period is a 404
	# from the snap — render it as "no rank yet", not an error.
	var mine: Dictionary = await _client.fetch_scores(_board, "around", 1, _auth.user_id)
	if fid != _fetch_id or not is_inside_tree():
		return
	var me := {}
	if bool(mine.get("ok", false)):
		for row in mine.get("scores", []):
			if str(row.get("user_id", "")) == _auth.user_id:
				me = row
				break
	if not me.is_empty():
		_own.text = "Your rank: #%d   ·   %d" % [int(me.get("rank", 0)), int(me.get("score", 0))]
	else:
		_own.text = "No rank yet this period."


func _clear_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()


## One standings row: rank (dim) · name (light, expands) · score (brand purple).
func _make_row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 12)

	var rank := Label.new()
	rank.text = "#%d" % int(row.get("rank", 0))
	rank.custom_minimum_size = Vector2(52, 0)
	rank.add_theme_font_size_override("font_size", 18)
	rank.add_theme_color_override("font_color", MbStyle.DIM)
	line.add_child(rank)

	var name_lb := Label.new()
	name_lb.text = _display_name(row)
	name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lb.clip_text = true
	name_lb.add_theme_font_size_override("font_size", 18)
	var is_me: bool = _auth != null and str(row.get("user_id", "")) == _auth.user_id
	name_lb.add_theme_color_override("font_color",
		MbStyle.HIGHLIGHT if is_me else MbStyle.TEXT)
	line.add_child(name_lb)

	var score := Label.new()
	score.text = str(int(row.get("score", 0)))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.add_theme_font_size_override("font_size", 18)
	score.add_theme_color_override("font_color", MbStyle.PRIMARY)
	line.add_child(score)
	return line


## Metadata display name when the submitter stashed one; truncated opaque id
## otherwise (anon accounts have no other handle).
static func _display_name(row: Dictionary) -> String:
	var n := str(row.get("name", ""))
	if n != "":
		return n
	var uid := str(row.get("user_id", ""))
	return uid.substr(0, 8) if uid.length() > 8 else uid
