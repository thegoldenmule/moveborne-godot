extends SceneTree

## Headless Story-mode E2E against the LOCAL validator:
##   godot --headless --path game --script res://tools/verify_story_e2e.gd
##
## Drives the REAL app (autoloads + shell + router + MbUi/MbDebug, no fakes):
## home → story map (sign-in + catalog/progress fetch) → locked levels inert →
## play w1_l1 → re-register the fresh match against ws://localhost:5555 (the
## Hermes-emulation endpoint) → validated swipes → exit → the validator grades
## the level and the story result lands in _gs.last_result + the map's
## result overlay. Prints VERIFY story_e2e: PASS/FAIL; exit 0/1.
##
## Prereqs: the local validator on :5555 (tools/run_validator.sh or
## `cd validator && bun run dev`) and network for the anonymous Snapser
## sign-in the map performs (story is online-only by design).
##
## DEPLOYED mode — MB_E2E_DEPLOYED=1 godot --headless ... — skips the local
## validator and plays against the live snapend through the gateway (the
## match's own _connect_snapser path). Expects the full production loop:
## stars graded, rewards GRANTED, and the progress blob persisted + read
## back on the map refresh.

var _deployed := false
var _ok := true
var _router: Node
var _ui: Node
var _dbg: Node
var _gs: Node


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)


func _initialize() -> void:
	_run.call_deferred()


func _finish(code: int) -> void:
	print("VERIFY story_e2e: %s" % ["PASS" if _ok and code == 0 else "FAIL"])
	quit(code if not _ok or code != 0 else 0)


## Await frames until cond() or timeout (seconds). Returns cond()'s final value.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var waited := 0.0
	while not bool(cond.call()) and waited < timeout:
		await process_frame
		waited += 0.016
	return bool(cond.call())


func _run() -> void:
	# Autoload singletons exist in the tree under --script runs, but their
	# named globals do not resolve at compile time — fetch them dynamically.
	_router = root.get_node_or_null("/root/UiRouter")
	_ui = root.get_node_or_null("/root/MbUi")
	_dbg = root.get_node_or_null("/root/MbDebug")
	_gs = root.get_node_or_null("/root/GameState")
	if _router == null or _ui == null or _dbg == null or _gs == null:
		_ok = false
		print("FAIL: autoloads missing under --script (router=%s ui=%s dbg=%s gs=%s)"
			% [_router, _ui, _dbg, _gs])
		_finish(1)
		return

	_deployed = OS.get_environment("MB_E2E_DEPLOYED") == "1"
	if _deployed:
		print("  mode: DEPLOYED (live snapend through the gateway)")

	# 0) Local mode needs the local validator up — fail fast with a clear message.
	if not _deployed:
		var probe := HTTPRequest.new()
		root.add_child(probe)
		if probe.request("http://localhost:5555/health") != OK:
			_ok = false
			print("FAIL: cannot start health probe")
			_finish(1)
			return
		var presp: Array = await probe.request_completed
		probe.queue_free()
		if int(presp[1]) != 200:
			_ok = false
			print("FAIL: local validator not running on :5555 — start it first (run-validator)")
			_finish(1)
			return

	# 1) Mount the shell (what ui/boot.gd does) and open the story map.
	# load() at runtime, NOT preload: a top-level preload compiles before the
	# autoload globals (UiRouter/GameState/MbStyle) register under --script,
	# failing the whole dependency chain with "Identifier not found".
	var shell_state = load("res://ui/router/shell_state.gd")
	_router.reset(shell_state.new())
	var st: Dictionary = await _ui.goto("story")
	_check("goto('story') lands on the story map", str(st.get("screen", "")) == "story_map")
	_check("route is [shell, story_map]", str(st.get("route", [])) == str(["shell", "story_map"]))

	# 2) Wait out the map's refresh (anonymous sign-in + catalog/progress GETs).
	var play_enabled := func() -> bool:
		for a in _ui.actions():
			if str(a.get("id", "")) == "story_map.play":
				return bool(a.get("enabled", false))
		return false
	_check("map online — play enabled after refresh", await _wait_until(play_enabled, 15.0))

	# 3) Locked levels are inert; the frontier is playable. The rows rebuild
	# after the progress fetch lands (play enables earlier, at sign-in), so
	# wait for the frontier row rather than sampling mid-refresh.
	var frontier_enabled := func() -> bool:
		for a in _ui.actions():
			if str(a.get("id", "")) == "story_map.level_w1_l1":
				return bool(a.get("enabled", false))
		return false
	_check("frontier level w1_l1 is enabled", await _wait_until(frontier_enabled, 15.0))
	var locked: Dictionary = _ui.press("story_map.level_w1_l5")
	_check("locked level press is rejected", not bool(locked.get("ok", true)))

	# 4) Play the next level; wait for the match to mount.
	_ui.press("story_map.play")
	var in_match := func() -> bool:
		var m = get_first_node_in_group("mb_match")
		return m != null and _dbg.is_ready()
	_check("match mounts after play", await _wait_until(in_match, 20.0))
	var m = get_first_node_in_group("mb_match")
	if m == null:
		_finish(1)
		return
	_check("match launched as story w1_l1", m._mode == "story" and m._level_id == "w1_l1")
	_check("goal HUD strip built from the catalog goals", m._goals.size() == 3)

	# 5) Bind the match to a validator. Deployed: the scene's own
	# _connect_snapser (gateway Hermes) is already in flight — wait for it.
	# Local: re-register the (still fresh) match against :5555, where the
	# ?token= IS the self-stamped player id (no gateway).
	if _deployed:
		_check("deployed validator accepted the fresh story init",
			await _wait_until(func() -> bool: return m._match.online, 20.0))
	else:
		m._match.online = false
		m._start_net("ws://localhost:5555/hermes/ws", "e2e_player", "e2e_player")
		_check("local validator accepted the fresh story init",
			await _wait_until(func() -> bool: return m._match.online, 10.0))

	# 6) Play validated moves; chase the first points goal (240) but cap the
	# move budget — the E2E gate is the grading round-trip, not the stars.
	var dirs := ["left", "up", "right", "up"]
	for i in range(60):
		_dbg.swipe(dirs[i % dirs.size()])
		await process_frame
		if int(m._match.state.get("score", 0)) >= 250:
			break
	var final_score := int(m._match.state.get("score", 0))
	print("  played to score=%d moveIndex=%d" % [final_score, int(m._match.state.get("moveIndex", 0))])
	# Let in-flight validations settle so completion grades the final state.
	await create_timer(1.5).timeout
	_check("still online after validated play", m._match.online)

	# 7) Exit: settles CompleteMatch with the validator, pops to the map,
	# surfaces the result overlay, refreshes progress.
	var st2: Dictionary = await _ui.goto("story")
	_check("back on the story map after exit", str(st2.get("screen", "")) == "story_map")

	var result: Dictionary = _gs.last_result
	_check("result tagged story/w1_l1", str(result.get("mode", "")) == "story"
		and str(result.get("level_id", "")) == "w1_l1")
	var story = result.get("story", {})
	_check("validator returned a story grade", story is Dictionary and not (story as Dictionary).is_empty())
	if story is Dictionary and not (story as Dictionary).is_empty():
		var stars := int(story.get("stars", -1))
		_check("stars graded in 0..3", stars >= 0 and stars <= 3)
		_check("3 goal results returned", (story.get("goals", []) as Array).size() == 3)
		_check("grade is for this level", str(story.get("level_id", "")) == "w1_l1")
		if _deployed:
			# Production loop: the progress write lands, so earned stars grant
			# catalog rewards and the blob round-trips into the refreshed map.
			if stars >= 1:
				_check("earned stars granted catalog rewards",
					not (story.get("rewards", {}) as Dictionary).is_empty())
				var blob_has_stars := func() -> bool:
					var levels = (_gs.story_progress as Dictionary).get("levels", {})
					if not (levels is Dictionary):
						return false
					return int(((levels as Dictionary).get("w1_l1", {}) as Dictionary).get("stars", 0)) >= 1
				_check("progress blob persisted and read back on map refresh",
					await _wait_until(blob_has_stars, 15.0))
		else:
			# Storage is disabled on the local validator, so the watermark cannot
			# land -> rewards must be withheld (the anti-refarm rule).
			_check("rewards withheld without a progress write", (story.get("rewards", {}) as Dictionary).is_empty())
		print("  graded: stars=%d new_stars=%d next=%s rewards=%s" % [stars, int(story.get("new_stars", -1)), str(story.get("next_level_id", "")), str(story.get("rewards", {}))])

	# 8) The result overlay is up (its continue button registers on the map).
	var has_continue := false
	for a in _ui.actions():
		if str(a.get("id", "")) == "story_map.continue":
			has_continue = true
	_check("level-result overlay shown (story_map.continue present)", has_continue)

	_finish(0)
