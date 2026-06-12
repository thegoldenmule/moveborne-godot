extends Control
## The Story world map: a linear path of levels for the selected world with
## earned stars, locks, and the next playable level highlighted. Pushed as a
## router takeover (StoryMapState); play_level(cfg) asks the state to launch a
## match, closed() asks it to pop back to the shell.
##
## Server-authoritative: stars/unlocks render from the Storage-snap progress
## blob (validator-written); the catalog comes from Remote Config with the
## baked res://story/story_catalog.json as the offline/dev fallback. Story is
## online-only — without a Snapser session the map gates behind a
## connect-to-play panel (decision 2026-06-12).

signal play_level(cfg: Dictionary)
signal closed

const AuthS := preload("res://net/snapser_auth.gd")
const RemoteConfigS := preload("res://net/remote_config_client.gd")
const ProgressClientS := preload("res://net/story_progress_client.gd")
const Catalog := preload("res://story/story_catalog.gd")
const Reg := preload("res://ui/mcp_ui_reg.gd")

const SCREEN_MARGIN := 24.0
const STAR_FULL := "★"
const STAR_EMPTY := "☆"

var _auth: MbSnapserAuth
var _remote_config: Node    # MbRemoteConfigClient
var _progress_client: Node  # MbStoryProgressClient

var _catalog: Dictionary = {}
var _baked: Dictionary = {}  # parsed once; the fallback never changes at runtime
var _world_index := 0
var _online := false
var _refreshing := false

var _title: Label
var _world_label: Label
var _world_prev: Button
var _world_next: Button
var _scroll: ScrollContainer
var _level_list: VBoxContainer
var _play_btn: Button
var _status: Label
var _gate: Control          # connect-to-play panel (offline)
var _overlay: Control       # level-result overlay


func _ready() -> void:
	Reg.screen(self, "story_map")
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

	_auth = AuthS.new()
	add_child(_auth)
	_remote_config = RemoteConfigS.new(_auth)
	add_child(_remote_config)
	_progress_client = ProgressClientS.new(_auth)
	add_child(_progress_client)

	_build_ui()
	# Render immediately from the baked catalog + cached progress; refresh()
	# (called by StoryMapState after the reveal) swaps in live data.
	_baked = Catalog.load_baked()
	_catalog = _baked if GameState.story_catalog.is_empty() else GameState.story_catalog
	_world_index = _frontier_world_index()
	_rebuild()


## Re-fetch catalog + progress. Coroutine, but callers fire-and-forget — the
## screen renders a loading status and updates in place.
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	_status.text = "consulting the cards…"
	var ok: bool = await _auth.ensure_session()
	_online = ok
	if not ok:
		_refreshing = false
		_status.text = ""
		_show_gate(true)
		return
	_show_gate(false)
	# Sequential awaits: storing an un-awaited coroutine call to "parallelize"
	# the two fetches breaks the resume chain (verified: the coroutine dies
	# after the first await and the map never re-renders). Two round trips it is.
	var rc: Dictionary = await _remote_config.fetch_app_config()
	var pr: Dictionary = await _progress_client.fetch_progress()
	if bool(rc.get("ok", false)):
		var remote: Dictionary = RemoteConfigS.extract_catalog(rc.get("config", {}))
		_catalog = RemoteConfigS.select_catalog(remote, _baked)
		GameState.set_story_catalog(_catalog)
	if bool(pr.get("ok", false)):
		GameState.set_story_progress(pr.get("progress", {}))
	_status.text = "" if bool(pr.get("ok", false)) else "progress unavailable — %s" % pr.get("error", "")
	_world_index = _frontier_world_index()
	_refreshing = false
	_rebuild()


# ── build ─────────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var vp := size
	var bg := ColorRect.new()
	bg.color = MbStyle.BG
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg.size = vp
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var back := Button.new()
	back.text = "‹ Home"
	back.focus_mode = Control.FOCUS_NONE
	back.position = Vector2(SCREEN_MARGIN, 14.0)
	back.custom_minimum_size = Vector2(0, 34)
	back.add_theme_font_size_override("font_size", 15)
	_style_chrome_button(back)
	back.pressed.connect(func() -> void: closed.emit())
	Reg.adopt(back, "back")
	add_child(back)

	_title = Label.new()
	_title.text = "STORY"
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 16.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", MbStyle.PRIMARY)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	# World selector row: ‹ World N — Name ›
	var world_row := HBoxContainer.new()
	world_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	world_row.offset_left = SCREEN_MARGIN
	world_row.offset_right = -SCREEN_MARGIN
	world_row.offset_top = 58.0
	world_row.alignment = BoxContainer.ALIGNMENT_CENTER
	world_row.add_theme_constant_override("separation", 14)
	add_child(world_row)

	_world_prev = Button.new()
	_world_prev.text = "‹"
	_world_prev.focus_mode = Control.FOCUS_NONE
	_world_prev.custom_minimum_size = Vector2(40, 34)
	_style_chrome_button(_world_prev)
	_world_prev.pressed.connect(_shift_world.bind(-1))
	Reg.adopt(_world_prev, "world_prev")
	world_row.add_child(_world_prev)

	_world_label = Label.new()
	_world_label.custom_minimum_size = Vector2(260, 0)
	_world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_world_label.add_theme_font_size_override("font_size", 18)
	_world_label.add_theme_color_override("font_color", MbStyle.TEXT)
	world_row.add_child(_world_label)

	_world_next = Button.new()
	_world_next.text = "›"
	_world_next.focus_mode = Control.FOCUS_NONE
	_world_next.custom_minimum_size = Vector2(40, 34)
	_style_chrome_button(_world_next)
	_world_next.pressed.connect(_shift_world.bind(1))
	Reg.adopt(_world_next, "world_next")
	world_row.add_child(_world_next)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 96.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", MbStyle.DIM)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	# The level path: a scrollable vertical list, level 1 at the top.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_scroll.position = Vector2(SCREEN_MARGIN, 122.0)
	_scroll.size = Vector2(vp.x - 2.0 * SCREEN_MARGIN, vp.y - 122.0 - 96.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_level_list = VBoxContainer.new()
	_level_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_level_list)

	_play_btn = Button.new()
	_play_btn.text = "Play"
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_play_btn.offset_left = SCREEN_MARGIN
	_play_btn.offset_right = -SCREEN_MARGIN
	_play_btn.offset_top = -76.0
	_play_btn.offset_bottom = -20.0
	_play_btn.add_theme_font_size_override("font_size", 24)
	_style_chrome_button(_play_btn)
	_play_btn.pressed.connect(_play_next)
	Reg.adopt(_play_btn, "play")
	add_child(_play_btn)

	_build_gate()


## Connect-to-play gate (story is online-only). Covers the map until a session
## exists; Retry re-runs refresh().
func _build_gate() -> void:
	_gate = Control.new()
	_gate.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_gate.size = size
	_gate.visible = false
	add_child(_gate)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dim.size = size
	_gate.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	box.position = Vector2(size.x / 2.0 - 170.0, size.y / 2.0 - 70.0)
	box.custom_minimum_size = Vector2(340, 0)
	_gate.add_child(box)
	var msg := Label.new()
	msg.text = "Story needs a connection.\nConnect to play — your stars live on the server."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(340, 0)
	msg.add_theme_font_size_override("font_size", 18)
	msg.add_theme_color_override("font_color", MbStyle.TEXT)
	box.add_child(msg)
	var retry := Button.new()
	retry.text = "Connect"
	retry.focus_mode = Control.FOCUS_NONE
	retry.custom_minimum_size = Vector2(0, 44)
	retry.add_theme_font_size_override("font_size", 18)
	_style_chrome_button(retry)
	retry.pressed.connect(refresh)
	Reg.adopt(retry, "retry")
	box.add_child(retry)


func _show_gate(v: bool) -> void:
	_gate.visible = v
	_play_btn.disabled = v
	_play_btn.modulate = Color(1, 1, 1, 0.5) if v else Color.WHITE


# ── rendering ─────────────────────────────────────────────────────────────────


func _worlds() -> Array:
	return Catalog.ordered_worlds(_catalog)


## Index of the world containing the unlock frontier (the next level to play).
func _frontier_world_index() -> int:
	var frontier := Catalog.compute_next_level(_catalog, GameState.story_progress)
	if frontier == "":
		return maxi(0, _worlds().size() - 1)
	var level := Catalog.get_level(_catalog, frontier)
	var worlds := _worlds()
	for i in range(worlds.size()):
		if str(worlds[i].get("id", "")) == str(level.get("world_id", "")):
			return i
	return 0


func _shift_world(delta: int) -> void:
	_world_index = clampi(_world_index + delta, 0, maxi(0, _worlds().size() - 1))
	_rebuild()


func _rebuild() -> void:
	var worlds := _worlds()
	if worlds.is_empty():
		_world_label.text = "no catalog"
		return
	_world_index = clampi(_world_index, 0, worlds.size() - 1)
	var world: Dictionary = worlds[_world_index]
	var progress: Dictionary = GameState.story_progress
	var frontier := Catalog.compute_next_level(_catalog, progress)

	var earned := 0
	var levels := Catalog.ordered_levels(_catalog).filter(
		func(l): return str(l.get("world_id", "")) == str(world.get("id", "")))
	for l in levels:
		earned += Catalog.stars_for(progress, str(l.get("id", "")))
	_world_label.text = "World %d — %s   %d/%d %s" \
		% [_world_index + 1, str(world.get("name", "")), earned, levels.size() * 3, STAR_FULL]
	_world_prev.disabled = _world_index == 0
	_world_next.disabled = _world_index >= worlds.size() - 1

	for c in _level_list.get_children():
		c.queue_free()
	var focus_row: Control = null
	# Unlock state derives from the frontier in catalog order: everything up to
	# and including the frontier is playable, everything after is locked (O(1)
	# per row — no per-row catalog walk). Worlds before the current one are
	# fully unlocked iff the frontier sits in a later world.
	var frontier_world := str(Catalog.get_level(_catalog, frontier).get("world_id", "")) if frontier != "" else ""
	var world_ids: Array = worlds.map(func(w): return str(w.get("id", "")))
	var frontier_world_idx: int = world_ids.find(frontier_world)
	var passed_frontier := frontier != "" and frontier_world_idx >= 0 and _world_index > frontier_world_idx
	for l in levels:
		var id := str(l.get("id", ""))
		var unlocked := frontier == "" or not passed_frontier
		var row := _make_level_row(l, progress, id == frontier, unlocked)
		_level_list.add_child(row)
		if id == frontier:
			focus_row = row
			passed_frontier = true
	if focus_row != null:
		_scroll_to.call_deferred(focus_row)

	var next_level := Catalog.get_level(_catalog, frontier)
	if frontier == "":
		_play_btn.text = "All levels complete"
		_play_btn.disabled = true
	else:
		_play_btn.text = "Play  ·  %s" % str(next_level.get("name", frontier))
		_play_btn.disabled = not _online


func _scroll_to(row: Control) -> void:
	if is_instance_valid(row) and is_instance_valid(_scroll):
		_scroll.ensure_control_visible(row)


func _make_level_row(level: Dictionary, progress: Dictionary, is_next: bool, unlocked: bool) -> Control:
	var id := str(level.get("id", ""))
	var stars := Catalog.stars_for(progress, id)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 17)
	var num := int(level.get("order", 0)) + 1
	if unlocked:
		btn.text = "%d   %s   %s" % [num, _star_string(stars), str(level.get("name", id))]
	else:
		btn.text = "%d   🔒   %s" % [num, str(level.get("name", id))]
	_style_level_row(btn, unlocked, is_next, stars)
	btn.disabled = not unlocked or not _online
	if unlocked:
		btn.pressed.connect(_launch_level.bind(level))
	Reg.adopt(btn, "level_%s" % id)
	return btn


func _launch_level(level: Dictionary) -> void:
	play_level.emit(Catalog.match_cfg(level))


func _play_next() -> void:
	var frontier := Catalog.compute_next_level(_catalog, GameState.story_progress)
	if frontier == "":
		return
	var level := Catalog.get_level(_catalog, frontier)
	if not level.is_empty():
		_launch_level(level)


# ── level result overlay ──────────────────────────────────────────────────────


## Surface the level result banked by the match (called by StoryMapState on
## resume). No-ops for non-story results and results already shown.
func show_result(result: Dictionary) -> void:
	if result.is_empty() or str(result.get("mode", "")) != "story":
		return
	if str(result.get("level_id", "")) == "" or bool(result.get("story_shown", false)):
		return
	result["story_shown"] = true
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = _build_result_overlay(result)
	add_child(_overlay)


func _build_result_overlay(result: Dictionary) -> Control:
	var story = result.get("story", {})
	if not (story is Dictionary):
		story = {}
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.size = size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dim.size = size
	overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	box.position = Vector2(size.x / 2.0 - 180.0, size.y * 0.22)
	overlay.add_child(box)

	var level := Catalog.get_level(_catalog, str(result.get("level_id", "")))
	var stars := int(story.get("stars", 0))

	var title := Label.new()
	title.text = "LEVEL COMPLETE" if stars > 0 else "LEVEL FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", MbStyle.PRIMARY)
	box.add_child(title)

	var name_lbl := Label.new()
	name_lbl.text = str(level.get("name", result.get("level_id", "")))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", MbStyle.TEXT)
	box.add_child(name_lbl)

	var stars_lbl := Label.new()
	stars_lbl.text = _star_string(stars)
	stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars_lbl.add_theme_font_size_override("font_size", 44)
	stars_lbl.add_theme_color_override("font_color", Color("ffd54a") if stars > 0 else MbStyle.DIM)
	box.add_child(stars_lbl)

	if story.is_empty():
		var none := Label.new()
		none.text = "Connection lost — this run was not recorded."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(360, 0)
		none.add_theme_font_size_override("font_size", 15)
		none.add_theme_color_override("font_color", MbStyle.DIM)
		box.add_child(none)
	else:
		for g in story.get("goals", []):
			if not (g is Dictionary):
				continue
			var goal = (g as Dictionary).get("goal", {})
			var line := Label.new()
			line.text = "%s  %s" % ["✓" if bool((g as Dictionary).get("met", false)) else "✗", Catalog.goal_text(goal)]
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.add_theme_font_size_override("font_size", 15)
			line.add_theme_color_override("font_color",
				MbStyle.TEXT if bool((g as Dictionary).get("met", false)) else MbStyle.DIM)
			box.add_child(line)
		var rewards = story.get("rewards", {})
		if rewards is Dictionary and not (rewards as Dictionary).is_empty():
			var parts: Array = []
			for currency in rewards:
				parts.append("+%s %s" % [str(rewards[currency]), str(currency)])
			var rl := Label.new()
			rl.text = "  ".join(parts)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rl.add_theme_font_size_override("font_size", 17)
			rl.add_theme_color_override("font_color", Color("2e9e5b"))
			box.add_child(rl)
		if bool(story.get("unlocked", false)):
			var ul := Label.new()
			ul.text = "Next level unlocked!"
			ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ul.add_theme_font_size_override("font_size", 16)
			ul.add_theme_color_override("font_color", MbStyle.PRIMARY)
			box.add_child(ul)

	var cont := Button.new()
	cont.text = "Continue"
	cont.focus_mode = Control.FOCUS_NONE
	cont.custom_minimum_size = Vector2(0, 46)
	cont.add_theme_font_size_override("font_size", 18)
	_style_chrome_button(cont)
	cont.pressed.connect(func() -> void:
		if is_instance_valid(_overlay):
			_overlay.queue_free())
	Reg.adopt(cont, "continue")
	box.add_child(cont)
	return overlay


func _star_string(stars: int) -> String:
	return STAR_FULL.repeat(clampi(stars, 0, 3)) + STAR_EMPTY.repeat(3 - clampi(stars, 0, 3))


# ── styling ───────────────────────────────────────────────────────────────────


## Dark rounded body + purple border (the game's chrome look, cf. main.gd).
func _style_chrome_button(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.BOARD
	sb.set_corner_radius_all(8)
	sb.border_color = MbStyle.PRIMARY
	sb.set_border_width_all(2)
	sb.set_content_margin(SIDE_LEFT, 14)
	sb.set_content_margin(SIDE_RIGHT, 14)
	sb.set_content_margin(SIDE_TOP, 4)
	sb.set_content_margin(SIDE_BOTTOM, 4)
	var hover := sb.duplicate()
	hover.bg_color = Color(MbStyle.PRIMARY, 0.20)
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_color_override("font_color", MbStyle.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)


## Level rows: the next level glows (primary border + white text); completed
## rows are calm; locked rows are dim and inert.
func _style_level_row(b: Button, unlocked: bool, is_next: bool, stars: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.BOARD
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.set_content_margin(SIDE_LEFT, 16)
	sb.set_content_margin(SIDE_RIGHT, 16)
	if is_next:
		sb.border_color = MbStyle.PRIMARY
		sb.shadow_color = Color(MbStyle.PRIMARY, 0.45)
		sb.shadow_size = 6
	elif unlocked and stars > 0:
		sb.border_color = Color(MbStyle.PRIMARY, 0.55)
	else:
		sb.border_color = Color(MbStyle.DIM, 0.35)
	var hover := sb.duplicate()
	hover.bg_color = Color(MbStyle.PRIMARY, 0.18)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_color_override("font_color", Color.WHITE if is_next else MbStyle.TEXT)
	b.add_theme_color_override("font_disabled_color", Color(MbStyle.DIM, 0.7))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
