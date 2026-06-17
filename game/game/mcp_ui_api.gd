extends Node

## MbUi — semantic UI/navigation command layer for LLM/automation control.
##
## The UI analog of MbDebug (game/mcp_game_api.gd). MbDebug drives *gameplay*
## (swipe/cards/board); MbUi drives the *shell*: navigate to any screen by name,
## press any registered control by stable id, and run deterministic ordered
## sequences — all via the godot-ai MCP `game_eval` command, e.g.:
##
##     return MbUi.state()
##     return MbUi.actions()                       # every pressable id on this screen
##     return await MbUi.goto("settings")          # awaited — returns when it's live
##     return MbUi.press("settings.avatar")
##     return await MbUi.run(["goto:settings", "press:settings.avatar",
##                            "press:avatar.skull_avatar_03", {set="settings.music", to=0.3},
##                            "flow:start_story", "swipe:up"])
##
## WHY IT'S DETERMINISTIC: the navigation layer (UiRouter) is an async stack-FSM
## whose push/pop await their lifecycle hooks + the cover/reveal fades, and
## `game_eval` itself awaits the eval coroutine — so `await goto(...)` returns only
## once the destination screen is actually live.
##
## CONTROL IDS come from MbUiReg (ui/mcp_ui_reg.gd): screens build/adopt their
## actionable controls through it, which records each on the live tree. MbUi walks
## that live tree to build its catalog — self-cleaning, no central state.
##
## Full reference: the UI Control API (MbUi) wiki page
## (wiki/hypercasual-llm/architecture/client/ui-control-api-mbui.md).

const MbUiReg := preload("res://ui/mcp_ui_reg.gd")
const AvatarsS := preload("res://ui/avatars.gd")

const NOT_READY := {"ok": false, "reason": "not_ready",
	"message": "shell not live — open ui/boot.tscn (project_run) first"}

## Tab screen ids (selectable inside the shell — NOT router pushes).
const TAB_IDS := ["collection", "leaderboard", "home", "guilds", "settings"]
## Play modes (router pushes) and the match config each launches with.
## Story is NOT here: goto("story") opens the world map (StoryMapState) — the
## level is chosen on the map (press story_map.play / story_map.level_<id>).
const MODE_CFG := {
	"infinite": {"mode": "infinite"},
}

## The named-flow catalog: the single source of truth for flows() + help(). Each
## flow is an ordered run() script that `_expand_flow` builds (interpolating the
## listed params; a "?" suffix marks an optional param). Keep these names in
## lockstep with _expand_flow's match — verify_ui_driver asserts every entry here
## expands to non-null steps.
const FLOWS := [
	{"name": "start_story", "params": [], "summary": "Open the Story world map."},
	{"name": "story_play_next", "params": [], "summary": "Open the Story map and play the next unlocked level."},
	{"name": "start_infinite", "params": [], "summary": "Launch an Infinite match."},
	{"name": "open_settings", "params": [], "summary": "Switch to the Settings tab."},
	{"name": "open_leaderboard", "params": [], "summary": "Switch to the Leaderboard tab."},
	{"name": "open_daily_missions", "params": [], "summary": "Open the Daily Missions panel (Home sigil)."},
	{"name": "claim_daily", "params": [], "summary": "Open Daily Missions and Claim All claimable rewards."},
	{"name": "exit_match", "params": [], "summary": "Leave the current match, back to the shell."},
	{"name": "sign_out", "params": [], "summary": "Settings -> Sign out."},
	{"name": "set_avatar", "params": ["id"], "summary": "Open Settings and pick avatar <id> (e.g. skull_avatar_05)."},
	{"name": "rename", "params": ["name"], "summary": "Set the display name to <name> and save."},
	{"name": "set_volume", "params": ["music?", "sfx?"], "summary": "Set the music and/or sfx volume sliders."},
]


# ── scene/shell/autoload resolution ───────────────────────────────────────────
# Autoloads are resolved by node path (not the global identifier) so this script
# compiles + its pure surface (catalog/actions/press/…) runs even outside the full
# app — e.g. the headless verifier, which builds a fake tree and never mounts the
# router. In-game these resolve to the UiRouter / MbDebug singletons under /root.

func _router() -> Node:
	return get_node_or_null("/root/UiRouter")

func _dbg() -> Node:
	return get_node_or_null("/root/MbDebug")

## The live AppShell (navigation hub), or null when the shell isn't mounted.
func _shell():
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("mcp_shell")

## The live match scene (main.gd), or null when no match is active.
func _match_scene():
	var tree := get_tree()
	if tree == null:
		return null
	var m = tree.get_first_node_in_group("mb_match")
	return m if (m != null and m.has_method("mcp_exit")) else null

func _top_name() -> String:
	var r := _router()
	if r == null:
		return ""
	var t = r.top()
	return t.state_name() if t != null else ""

func _in_match() -> bool:
	return _top_name() == "MatchState"


# ── readiness / situational reads ─────────────────────────────────────────────

## True when the navigation shell is mounted (Godot's analog of "the menu is up").
func is_ready() -> bool:
	return _shell() != null

## The single situational read: where am I, what's on top, is a transition running.
func state() -> Dictionary:
	var sh = _shell()
	if sh == null:
		return NOT_READY
	var router := _router()
	var dbg := _dbg()
	var route: Array = []
	if router != null:
		for r in router.route_names():
			match r:
				"MatchState":
					route.append("match")
				"StoryMapState":
					route.append("story_map")
				_:
					route.append("shell")
	var active := _active_screen_ids()
	var in_match := _in_match()
	var on_map := _top_name() == "StoryMapState"
	var modal := ""
	if active.has("daily"):
		modal = "daily"
	elif active.has("avatar"):
		modal = "avatar"
	return {
		"ok": true,
		"busy": router != null and router.is_busy(),
		"route": route,
		"route_depth": router.stack_depth() if router != null else 0,
		"tab": sh.mcp_current_tab_id(),
		"screen": "match" if in_match else ("story_map" if on_map else sh.mcp_current_tab_id()),
		"modal": modal,
		"match_ready": dbg != null and dbg.is_ready(),
	}

## The static catalog of goto() targets.
func screens() -> Dictionary:
	return {
		"tabs": TAB_IDS,
		"modes": MODE_CFG.keys(),
		"surfaces": ["shell", "back", "match", "avatar", "daily", "story", "story_map"],
		"note": "goto(tab) selects a tab; goto(mode) starts a match; goto('story') opens the world map (play via story_map.play); goto('shell'/'back') exits a match/map.",
	}


# ── the live-tree registry walk ───────────────────────────────────────────────

## Every registered control, as {full_id: control}. A control belongs to its
## NEAREST screen-root ancestor, so a nested modal (avatar) forms its own screen.
func _catalog() -> Dictionary:
	var out := {}
	var tree := get_tree()
	if tree == null:
		return out
	for c in tree.get_nodes_in_group(MbUiReg.CONTROL_GROUP):
		if not (c is Control) or not c.has_meta(MbUiReg.META_ID):
			continue
		var screen := _nearest_screen_id(c)
		if screen == "":
			continue
		out["%s.%s" % [screen, str(c.get_meta(MbUiReg.META_ID))]] = c
	return out

func _nearest_screen_id(node: Node) -> String:
	var n: Node = node.get_parent()
	while n != null:
		if n.has_meta(MbUiReg.META_SCREEN):
			return str(n.get_meta(MbUiReg.META_SCREEN))
		n = n.get_parent()
	return ""

## Screen ids whose root is currently visible in the tree.
func _active_screen_ids() -> Array:
	var ids: Array = []
	var tree := get_tree()
	if tree == null:
		return ids
	for root in tree.get_nodes_in_group(MbUiReg.GROUP):
		if root.has_meta(MbUiReg.META_SCREEN) and _visible(root):
			ids.append(str(root.get_meta(MbUiReg.META_SCREEN)))
	return ids

## Visible accounting for BOTH Control and CanvasLayer ancestors (a Control under a
## hidden CanvasLayer — e.g. the avatar modal or the hidden nav — still reports
## is_visible_in_tree()==true, since a CanvasLayer breaks the CanvasItem chain).
func _visible(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var n: Node = node
	while n != null:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		if n is CanvasLayer and not (n as CanvasLayer).visible:
			return false
		n = n.get_parent()
	return true


# ── actions(): the discovery surface ──────────────────────────────────────────

## Every pressable thing on the live screen(s), by stable id. Filtered to
## visible+in-tree unless `all`. Each: {id, kind, enabled, + value/on/text}.
func actions(all: bool = false) -> Array:
	var out: Array = []
	var cat := _catalog()
	var ids := cat.keys()
	ids.sort()
	for id in ids:
		var c: Control = cat[id]
		if not all and not _visible(c):
			continue
		out.append(_describe(id, c))
	return out

func _describe(id: String, c: Control) -> Dictionary:
	var kind := _kind(c)
	var info := {"id": id, "kind": kind, "enabled": not _disabled(c), "visible": _visible(c)}
	match kind:
		"slider":
			info["value"] = (c as Range).value
		"toggle":
			info["on"] = (c as BaseButton).button_pressed
		"text":
			info["text"] = (c as LineEdit).text
		_:
			if _has_prop(c, "text"):
				info["text"] = str(c.get("text"))
	return info

func _kind(c: Control) -> String:
	if c is Range:
		return "slider"
	if c is CheckButton or c is CheckBox:
		return "toggle"
	if c is LineEdit:
		return "text"
	if c is TextureButton:
		return "texture_button"
	if c is BaseButton:
		return "button"
	return "control"

func _disabled(c: Control) -> bool:
	if c is BaseButton:
		return (c as BaseButton).disabled
	if c is Range:
		return not (c as Range).editable
	if c is LineEdit:
		return not (c as LineEdit).editable
	return false

func _has_prop(o: Object, prop: String) -> bool:
	for p in o.get_property_list():
		if p.get("name", "") == prop:
			return true
	return false


# ── navigation (awaited) ──────────────────────────────────────────────────────

## Navigate to any screen by name, fully awaited. Tabs ("home"/"settings"/…) and
## modes ("story"/"infinite") and surfaces ("shell"/"back"). Returns state().
func goto(target: String) -> Dictionary:
	var sh = _shell()
	if sh == null:
		return NOT_READY
	var t := target.to_lower()
	await _settle()

	# Leaving a match first if the target isn't the match itself.
	if _in_match() and t != "match":
		await _exit_match()

	# Story world map: a router surface between the shell and a match.
	if t == "story" or t == "story_map":
		if _top_name() != "StoryMapState":
			sh.mcp_select_tab("home")
			sh.mcp_start_match({"mode": "story"})  # the shell routes story to the map
			await _settle()
			# The map fetches catalog/progress detached after the reveal; wait
			# until it is interactable — play enabled, or the offline gate's
			# retry showing — so a following press:story_map.play is
			# deterministic instead of racing the network.
			var map_ready := func() -> bool:
				for a in actions():
					var id := str(a.get("id", ""))
					if id == "story_map.play" and bool(a.get("enabled", false)):
						return true
					if id == "story_map.retry" and bool(a.get("visible", false)):
						return true
				return false
			await _wait_until(map_ready, 10.0)
		return state()

	if t == "match":
		if not _in_match():
			return {"ok": false, "reason": "no_mode",
				"message": "goto('match') needs an active match; start one with goto('story'/'infinite')"}
		return state()

	# Validate BEFORE any side effect: an unknown target must leave the UI
	# untouched (popping the map below would tear down its result overlay).
	if t != "shell" and t != "back" and not TAB_IDS.has(t) and not MODE_CFG.has(t):
		return {"ok": false, "reason": "unknown_target",
			"message": "unknown screen '%s'; see screens()" % target}

	# The remaining targets want the shell visible — pop the map if it's on top.
	if _top_name() == "StoryMapState":
		_router().pop()
		await _settle()

	if t == "shell" or t == "back":
		return state()

	if TAB_IDS.has(t):
		sh.mcp_select_tab(t)
		await _settle()
		return state()

	sh.mcp_start_match(MODE_CFG[t].duplicate(true))
	await _settle()
	await _wait_until(func(): var d := _dbg(); return _in_match() and d != null and d.is_ready(), 5.0)
	return state()

## Press the in-match exit (validator completion + router pop), awaited to the shell.
func _exit_match() -> void:
	var scene = _match_scene()
	if scene == null:
		return
	await scene.mcp_exit()
	await _wait_until(func(): return not _in_match(), 6.0)
	await _settle()


# ── control invocation ────────────────────────────────────────────────────────

## Activate a button/toggle/texture-button by id. NOTE: this does not await router
## transitions (a launcher push, a match exit) — use goto()/run() for those.
func press(id: String, force: bool = false) -> Dictionary:
	var c = _resolve(id)
	if c == null:
		return _unknown(id)
	if _disabled(c) and not force:
		return {"ok": false, "reason": "disabled", "id": id}
	if c is BaseButton:
		if (c as BaseButton).toggle_mode:
			(c as BaseButton).button_pressed = true
		c.emit_signal("pressed")
		return {"ok": true, "status": "pressed", "id": id, "visible": _visible(c)}
	return {"ok": false, "reason": "not_pressable", "id": id,
		"message": "kind=%s — use set_value/set_text/toggle" % _kind(c)}

## Set a toggle (CheckButton/CheckBox) on/off by id.
func toggle(id: String, on: bool = true) -> Dictionary:
	var c = _resolve(id)
	if c == null:
		return _unknown(id)
	if not (c is BaseButton) or not (c as BaseButton).toggle_mode:
		return {"ok": false, "reason": "not_toggle", "id": id}
	(c as BaseButton).button_pressed = on
	return {"ok": true, "status": "toggled", "id": id, "on": on}

## Set a slider (Range) value by id.
func set_value(id: String, value: float) -> Dictionary:
	var c = _resolve(id)
	if c == null:
		return _unknown(id)
	if not (c is Range):
		return {"ok": false, "reason": "not_a_slider", "id": id}
	(c as Range).value = value
	return {"ok": true, "status": "set", "id": id, "value": (c as Range).value}

## Set a text field (LineEdit) by id; optionally submit (fires text_submitted).
func set_text(id: String, text: String, submit: bool = false) -> Dictionary:
	var c = _resolve(id)
	if c == null:
		return _unknown(id)
	if not (c is LineEdit):
		return {"ok": false, "reason": "not_a_text_field", "id": id}
	(c as LineEdit).text = text
	if submit:
		c.emit_signal("text_submitted", text)
	return {"ok": true, "status": "text_set", "id": id, "text": text, "submitted": submit}

func _resolve(id: String):
	return _catalog().get(id, null)

func _unknown(id: String) -> Dictionary:
	return {"ok": false, "reason": "unknown_id", "id": id,
		"message": "no control '%s'; see actions()" % id}


# ── sequences ─────────────────────────────────────────────────────────────────

## Run an ordered list of steps, awaiting each. A step is a string ("goto:settings",
## "press:home.story", "exit", "swipe:up", "wait:0.5", "flow:start_story") or a dict
## ({goto=}, {press=}, {set=,to=}, {text=,to=,submit=}, {toggle=,on=}, {swipe=},
## {wait=}, {flow=,params=}). Returns a per-step trace; stops on first error unless
## opts.continue_on_error.
func run(steps: Array, opts: Dictionary = {}) -> Array:
	var trace: Array = []
	var cont := bool(opts.get("continue_on_error", false))
	for step in steps:
		var r: Dictionary = await _do_step(step)
		var st := state()
		r["screen_after"] = str(st.get("screen", "")) if st.get("ok", false) else "?"
		trace.append(r)
		if not bool(r.get("ok", false)) and not cont:
			break
	return trace

func _do_step(step) -> Dictionary:
	if step is String:
		return await _do_string_step(step)
	if step is Dictionary:
		return await _do_dict_step(step)
	return {"ok": false, "step": step, "error": "bad_step_type"}

func _do_string_step(s: String) -> Dictionary:
	var verb := s
	var arg := ""
	var ci := s.find(":")
	if ci >= 0:
		verb = s.substr(0, ci)
		arg = s.substr(ci + 1)
	match verb:
		"goto", "tab", "start":
			var r := await goto(arg)
			return _wrap(s, r)
		"exit":
			var r := await goto("shell")
			return _wrap(s, r)
		"press":
			var r := press(arg)
			await _settle()  # covers a launcher push (goes busy synchronously)
			return _wrap(s, r)
		"toggle":
			return _wrap(s, toggle(arg, true))
		"swipe":
			return _wrap(s, _swipe(arg))
		"wait":
			await _wait_seconds(float(arg) if arg != "" else 0.0)
			return {"ok": true, "step": s}
		"flow":
			var sub := await flow(arg)
			return {"ok": _all_ok(sub), "step": s, "sub": sub}
		_:
			return {"ok": false, "step": s, "error": "unknown_verb: %s" % verb}

func _do_dict_step(d: Dictionary) -> Dictionary:
	if d.has("goto"):
		return _wrap(d, await goto(str(d["goto"])))
	if d.has("press"):
		var r := press(str(d["press"]), bool(d.get("force", false)))
		await _settle()
		return _wrap(d, r)
	if d.has("set"):
		return _wrap(d, set_value(str(d["set"]), float(d.get("to", 0.0))))
	if d.has("text"):
		return _wrap(d, set_text(str(d["text"]), str(d.get("to", "")), bool(d.get("submit", false))))
	if d.has("toggle"):
		return _wrap(d, toggle(str(d["toggle"]), bool(d.get("on", true))))
	if d.has("swipe"):
		return _wrap(d, _swipe(str(d["swipe"])))
	if d.has("wait"):
		await _wait_seconds(float(d["wait"]))
		return {"ok": true, "step": d}
	if d.has("flow"):
		var sub := await flow(str(d["flow"]), d.get("params", {}))
		return {"ok": _all_ok(sub), "step": d, "sub": sub}
	return {"ok": false, "step": d, "error": "unknown_dict_step"}

func _wrap(step, result: Dictionary) -> Dictionary:
	return {"ok": bool(result.get("ok", false)), "step": step, "result": result}

func _all_ok(trace: Array) -> bool:
	for r in trace:
		if not bool(r.get("ok", false)):
			return false
	return true


# ── named flows ───────────────────────────────────────────────────────────────

## The catalog of named flows — the discovery surface for flow(), as screens() is
## for goto() and actions() is for press(). Each entry: {name, params, summary,
## steps} where `steps` is the expansion with default/empty params (a shape
## preview); pass the listed params to flow(name, params).
func flows() -> Array:
	var out: Array = []
	for f in FLOWS:
		out.append({
			"name": f["name"],
			"params": f["params"],
			"summary": f["summary"],
			"steps": _expand_flow(str(f["name"]), {}),
		})
	return out

## Expand + run a named flow (see the FLOWS catalog / flows()). Returns the run() trace.
func flow(name: String, params: Dictionary = {}) -> Array:
	var steps = _expand_flow(name, params)
	if steps == null:
		return [{"ok": false, "error": "unknown_flow: %s" % name}]
	return await run(steps)

func _expand_flow(name: String, params: Dictionary):
	match name:
		"start_story":
			return ["goto:story"]
		"story_play_next":
			return ["goto:story", "press:story_map.play"]
		"start_infinite":
			return ["goto:infinite"]
		"open_settings":
			return ["goto:settings"]
		"open_leaderboard":
			return ["goto:leaderboard"]
		"open_daily_missions":
			return ["goto:home", "press:home.daily"]
		"claim_daily":
			return ["goto:home", "press:home.daily", "press:missions.claim_all"]
		"exit_match":
			return ["goto:shell"]
		"sign_out":
			return ["goto:settings", "press:settings.sign_out"]
		"set_avatar":
			var id := str(params.get("id", AvatarsS.default_id()))
			return ["goto:settings", "press:settings.avatar", "press:avatar.%s" % id]
		"rename":
			return ["goto:settings",
				{"text": "settings.name", "to": str(params.get("name", ""))},
				"press:settings.save_name"]
		"set_volume":
			var s: Array = ["goto:settings"]
			if params.has("music"):
				s.append({"set": "settings.music", "to": float(params["music"])})
			if params.has("sfx"):
				s.append({"set": "settings.sfx", "to": float(params["sfx"])})
			return s
	return null


# ── async helpers ─────────────────────────────────────────────────────────────

## Delegate a swipe to MbDebug (gameplay), guarded if it isn't present.
func _swipe(direction: String) -> Dictionary:
	var d := _dbg()
	if d == null:
		return {"ok": false, "reason": "no_mbdebug"}
	return d.swipe(direction)

## Yield frames while the router is mid-transition (it no-ops calls while busy).
func _settle() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	var router := _router()
	while router != null and router.is_busy():
		await tree.process_frame

## Await frames until cond() is true or `timeout` seconds elapse.
func _wait_until(cond: Callable, timeout: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var waited := 0.0
	while not bool(cond.call()) and waited < timeout:
		await tree.process_frame
		waited += tree.root.get_process_delta_time() if tree.root else 0.016

func _wait_seconds(secs: float) -> void:
	var tree := get_tree()
	if tree == null or secs <= 0.0:
		return
	await tree.create_timer(secs).timeout


# ── utility ───────────────────────────────────────────────────────────────────

func help() -> String:
	var flow_names: Array = []
	for f in FLOWS:
		flow_names.append(str(f["name"]))
	return """MbUi — semantic UI/navigation control (call via godot-ai game_eval). See the UI Control API (MbUi) wiki page.
  reads     : state() screens() actions(all=false) flows() is_ready()
  navigate  : await goto(target)   # tabs: %s ; modes: %s ; or 'shell'/'back'
  controls  : press(id) toggle(id,on) set_value(id,v) set_text(id,s,submit=false)
  sequence  : await run([steps], opts)  # steps: \"goto:settings\" \"press:home.story\" \"exit\" \"swipe:up\" \"wait:0.5\" \"flow:start_story\" / {set=\"settings.music\",to=0.3}
  flows     : await flow(name, params)  # catalog via flows(): %s
  gameplay  : in a match, drive the board/cards via MbDebug (see the Game Control API wiki page)""" % [str(TAB_IDS), str(MODE_CFG.keys()), " ".join(flow_names)]
