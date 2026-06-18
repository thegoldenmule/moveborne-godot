extends SceneTree

## Headless verifier for the Daily Login Remote Config seam:
##   godot --headless --path . --script res://tools/verify_daily_login_rc.gd
## Asserts MbRemoteConfigClient.extract_daily_login reads the daily_login block
## from an app-config document, returns {} when the key is absent or non-object,
## and leaves the sibling extract_daily_missions / extract_catalog reads undisturbed.

const RC := preload("res://net/remote_config_client.gd")

var _ok := true


func _initialize() -> void:
	var config := {
		"story_catalog": {"catalog_version": 3},
		"daily_missions": {"version": 2, "enabled": true},
		"daily_login": {"version": 1, "enabled": true, "cycle_length_days": 7, "calendar": []},
	}
	var dl := RC.extract_daily_login(config)
	_check("extract_daily_login returns the block",
		int(dl.get("version", 0)) == 1 and bool(dl.get("enabled", false)))
	_check("extract_daily_login {} when the key is absent",
		RC.extract_daily_login({"story_catalog": {}}).is_empty())
	_check("extract_daily_login {} on a non-object value",
		RC.extract_daily_login({"daily_login": 5}).is_empty())
	# siblings on the same document are undisturbed
	_check("extract_daily_missions still reads its sibling key",
		int(RC.extract_daily_missions(config).get("version", 0)) == 2)
	_check("extract_catalog still reads its sibling key",
		int(RC.extract_catalog(config).get("catalog_version", 0)) == 3)

	print("VERIFY daily_login_rc: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
