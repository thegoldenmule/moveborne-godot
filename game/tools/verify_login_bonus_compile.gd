extends SceneTree

## Compile guard: preload every script the Daily Login Bonus feature adds or
## touches, so a syntax / cross-reference break surfaces headlessly rather than
## only when the editor scans or the game runs.
##   godot --headless --path . --script res://tools/verify_login_bonus_compile.gd

func _initialize() -> void:
	var paths := [
		"res://ui/screens/daily_login_model.gd",
		"res://net/trackables_client.gd",
		"res://net/remote_config_client.gd",
		"res://ui/shell/reward_ceremony.gd",
		"res://ui/screens/login_bonus_panel.gd",
		"res://ui/shell/login_bonus.gd",
		"res://ui/shell/daily_sigil.gd",
		"res://ui/shell/app_shell.gd",
		"res://addons/daily_login_editor/daily_login_service.gd",
		"res://addons/daily_login_editor/dock.gd",
		"res://addons/daily_login_editor/plugin.gd",
	]
	var ok := true
	for p in paths:
		var s = load(p)
		if s == null:
			ok = false
			print("FAIL: could not load %s" % p)
	print("VERIFY login_bonus_compile: %s" % ["PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
