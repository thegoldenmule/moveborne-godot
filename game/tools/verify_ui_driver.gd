extends SceneTree

## Headless smoke for the ui_kit control registry + UiDriver mechanism.
##   godot --headless --path . --script res://tools/verify_ui_driver.gd
##
## Exercises UiReg (build/adopt → live-tree registration) and the UiDriver's
## catalog / actions / press / set_value / toggle / set_text / visibility filter on
## a HAND-BUILT control tree, plus the host-sourced flow catalog against a fake
## UiNavHost — no real router/scenes, so it runs cleanly headless. The async
## navigation surface (goto/run against the live router) is covered by the in-editor
## driven session (see the UI Control API wiki page), not here.

const Reg := preload("res://addons/ui_kit/ui_reg.gd")
const Driver := preload("res://addons/ui_kit/ui_driver.gd")

var _ok := true


## A minimal UiNavHost: just enough for state()/flows() to resolve. The flow
## catalog lives here (the game owns it), mirroring how AppShell supplies it.
class FakeHost:
	extends Node
	const FLOWS := [
		{"name": "open_a", "params": [], "summary": "Go to A."},
		{"name": "set_b", "params": ["v"], "summary": "Set B to <v>."},
	]
	func mcp_current_tab_id() -> String:
		return "settings"
	func mcp_nav_tabs() -> Array:
		return ["settings", "home"]
	func mcp_nav_modes() -> Array:
		return ["infinite"]
	func mcp_flows() -> Array:
		return FLOWS
	func mcp_expand_flow(name: String, params: Dictionary):
		match name:
			"open_a":
				return ["wait:0"]
			"set_b":
				return ["wait:0", {"set": "settings.music", "to": float(params.get("v", 0.0))}]
		return null


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)


func _initialize() -> void:
	_run()

## Async so we can yield a frame after building: children added to `root` in
## _initialize() only fire ENTER_TREE (which populates the SceneTree's group map
## that get_nodes_in_group reads) on the first frame.
func _run() -> void:
	# A fake "settings" screen with one of each actionable kind, plus a nested
	# "avatar" modal screen (so we test nearest-screen-root namespacing).
	var screen := Control.new()
	screen.name = "FakeSettings"
	Reg.screen(screen, "settings")
	root.add_child(screen)

	var save := Reg.button("save_name", screen, "Save")
	var music := Reg.slider("music", screen)
	music.min_value = 0.0
	music.max_value = 1.0
	music.step = 0.05  # Range default step is 1.0, which would snap fractional values
	music.value = 0.2
	var haptics := Reg.check("haptics", screen, "Haptics")
	haptics.button_pressed = true
	var name_edit := Reg.line_edit("name", screen)

	var modal := Control.new()
	modal.name = "FakeAvatarModal"
	Reg.screen(modal, "avatar")
	screen.add_child(modal)
	var pick := Reg.texture_button("skull_avatar_01", modal)

	# A fake host so state()/flows() resolve (the game supplies these).
	var host := FakeHost.new()
	host.name = "FakeHost"
	host.add_to_group(Driver.HOST_GROUP)
	root.add_child(host)

	# --- UiReg: registration is recorded on the live tree ---
	_check("screen grouped + id",
		screen.is_in_group(Reg.GROUP) and str(screen.get_meta(Reg.META_SCREEN)) == "settings")
	_check("button registered + parented",
		save.is_in_group(Reg.CONTROL_GROUP) and str(save.get_meta(Reg.META_ID)) == "save_name"
		and save.get_parent() == screen)
	_check("slider/check/text/texture registered",
		music.is_in_group(Reg.CONTROL_GROUP) and haptics.is_in_group(Reg.CONTROL_GROUP)
		and name_edit.is_in_group(Reg.CONTROL_GROUP) and pick.is_in_group(Reg.CONTROL_GROUP))

	# --- UiDriver over the hand-built tree ---
	var d := Driver.new()
	d.name = "UiDriverProbe"
	root.add_child(d)

	# Let ENTER_TREE fire so the SceneTree group map (CONTROL_GROUP) is populated.
	await process_frame

	var cat: Dictionary = d._catalog()
	_check("catalog namespaces by nearest screen root",
		cat.has("settings.save_name") and cat.has("settings.music")
		and cat.has("avatar.skull_avatar_01") and not cat.has("settings.skull_avatar_01"))

	# actions(): all visible (screen is visible) — 4 settings + 1 avatar pick = 5.
	var acts: Array = d.actions()
	var by_id := {}
	for a in acts:
		by_id[a["id"]] = a
	_check("actions lists all visible (5)", acts.size() == 5)
	_check("slider kind+value", by_id.has("settings.music")
		and by_id["settings.music"]["kind"] == "slider" and by_id["settings.music"]["value"] == 0.2)
	_check("toggle kind+on", by_id.has("settings.haptics")
		and by_id["settings.haptics"]["kind"] == "toggle" and by_id["settings.haptics"]["on"] == true)
	_check("text kind", by_id.has("settings.name") and by_id["settings.name"]["kind"] == "text")
	_check("texture_button kind", by_id.has("avatar.skull_avatar_01")
		and by_id["avatar.skull_avatar_01"]["kind"] == "texture_button")

	# state(): host present -> ok, tab from the host.
	var st: Dictionary = d.state()
	_check("state ok + tab from host", bool(st.get("ok", false)) and str(st.get("tab", "")) == "settings")

	# press() emits the control's pressed signal.
	var pressed := [false]
	save.pressed.connect(func() -> void: pressed[0] = true)
	var pr: Dictionary = d.press("settings.save_name")
	_check("press ok + emits", bool(pr.get("ok", false)) and pressed[0])

	# set_value / toggle / set_text mutate the right control.
	d.set_value("settings.music", 0.7)
	_check("set_value", music.value == 0.7)
	d.toggle("settings.haptics", false)
	_check("toggle off", haptics.button_pressed == false)
	d.set_text("settings.name", "Spectre")
	_check("set_text", name_edit.text == "Spectre")

	# Errors are structured, not crashes.
	var unk: Dictionary = d.press("settings.nope")
	_check("unknown id → error", not bool(unk.get("ok", true)) and str(unk.get("reason", "")) == "unknown_id")

	# flows() is the host-sourced named-flow catalog; every entry must expand
	# (guards drift between the host catalog and its mcp_expand_flow), and an
	# unknown flow is null.
	var fl: Array = d.flows()
	var every_expands := fl.size() == FakeHost.FLOWS.size()
	for f in fl:
		if not (f.has("steps") and f["steps"] != null and f.has("params") and f.has("summary")):
			every_expands = false
	_check("flows() catalog complete + every entry expands", every_expands)
	_check("unknown flow → null", d._expand_flow("nope", {}) == null)

	# Visibility filter: hiding the screen drops its controls from actions() (the
	# self-cleaning live-tree walk) but resolve()/press() still find them by id.
	screen.visible = false
	_check("hidden screen → empty actions", d.actions().size() == 0)
	_check("resolve ignores visibility", d._resolve("settings.save_name") == save)
	screen.visible = true

	print("VERIFY ui_driver: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)
