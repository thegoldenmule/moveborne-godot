extends SceneTree

## Headless checks for the Player Profile + Settings feature's pure helpers and
## that all its new scripts/scene compile + load.
##   godot --headless --path . --script res://tools/verify_profile_client.gd
##
## The live Profiles snap (gateway round-trip) is NOT covered here — it requires
## the snap provisioned on the snapend and is verified by a gateway smoke/e2e
## pass, like the leaderboards/inventory clients.

const Profile := preload("res://net/profile_client.gd")
const Avatars := preload("res://ui/avatars.gd")
const LocalSettings := preload("res://ui/local_settings.gd")
const Auth := preload("res://net/snapser_auth.gd")

var _ok := true
var _n := 0


func _check(cond: bool, msg: String) -> void:
	_n += 1
	if not cond:
		_ok = false
		print("FAIL: %s" % msg)


func _initialize() -> void:
	_test_urls_and_body()
	_test_parse_profile()
	_test_name_validation()
	_test_avatars()
	_test_local_settings_roundtrip()
	_test_display_name_resolution()
	_test_compiles()
	print("VERIFY profile_client: %s (%d checks)" % ["PASS" if _ok else "FAIL", _n])
	quit(0 if _ok else 1)


func _test_urls_and_body() -> void:
	_check(Profile.profile_url("u-1") == Auth.GATEWAY + "/v1/profiles/user/u-1",
		"profile_url targets /v1/profiles/user/{id}")
	var body = JSON.parse_string(Profile.profile_body({"display_name": "Nyx", "avatar_id": "skull_avatar_03"}))
	_check(body is Dictionary and body.has("profile"), "body wraps attrs under 'profile'")
	_check(str(body["profile"].get("display_name", "")) == "Nyx", "display_name carried in body")


func _test_parse_profile() -> void:
	_check(Profile.parse_profile({"profile": {"display_name": "x"}}) == {"display_name": "x"},
		"parse_profile extracts the profile dict")
	_check(Profile.parse_profile(null) == {}, "non-dict payload -> empty")
	_check(Profile.parse_profile({"profile": "nope"}) == {}, "non-dict profile -> empty")
	_check(Profile.parse_profile({}) == {}, "missing profile key -> empty")


func _test_name_validation() -> void:
	_check(Profile.sanitize_display_name("  Nyx  ") == "Nyx", "trims surrounding whitespace")
	_check(Profile.sanitize_display_name("Ny\nx") == "Nyx", "strips control chars")
	var long_name := "x".repeat(40)
	_check(Profile.sanitize_display_name(long_name).length() == Profile.DISPLAY_NAME_MAX,
		"clamps to DISPLAY_NAME_MAX")
	_check(Profile.is_valid_display_name("Nyx"), "ordinary name valid")
	_check(not Profile.is_valid_display_name("   "), "whitespace-only invalid")
	_check(not Profile.is_valid_display_name(""), "empty invalid")
	_check(Profile.is_valid_display_name(long_name), "over-length sanitizes to a valid clamped name")


func _test_avatars() -> void:
	_check(Avatars.IDS.size() == 12, "12 preset avatars")
	_check(Avatars.default_id() == "skull_avatar_01", "default is the first preset")
	_check(Avatars.resolve_id("nope") == Avatars.default_id(), "unknown id resolves to default")
	_check(Avatars.resolve_id("skull_avatar_07") == "skull_avatar_07", "known id preserved")
	_check(Avatars.texture("skull_avatar_01") != null, "preset avatar texture loads")


func _test_local_settings_roundtrip() -> void:
	var saved := {"master": 0.4, "sfx": 0.0, "haptics": false}
	_check(LocalSettings.save_settings(saved) == OK, "settings save ok")
	var got := LocalSettings.load_settings()
	_check(abs(float(got["master"]) - 0.4) < 0.001, "master volume round-trips")
	_check(abs(float(got["sfx"]) - 0.0) < 0.001, "sfx volume round-trips")
	_check(bool(got["haptics"]) == false, "haptics flag round-trips")
	# Restore defaults so a dev's real prefs aren't left clobbered.
	LocalSettings.save_settings(LocalSettings.DEFAULTS)


func _test_display_name_resolution() -> void:
	_check(Auth.resolve_display_name("Nyx", "godot-deadbeef") == "Nyx",
		"profile name wins as canonical handle")
	_check(Auth.resolve_display_name("", "godot-deadbeef") == "godot-deadbeef",
		"falls back to anon username when no profile name")


func _test_compiles() -> void:
	var packed = load("res://ui/screens/settings_tab.tscn")
	_check(packed != null, "settings scene loads (script compiles)")
	# Instantiate + run _ready (_build) and the no-session path with no setup() —
	# catches runtime errors the compile-check can't (null guards, bad API calls).
	var inst = packed.instantiate()
	get_root().add_child(inst)
	inst.refresh()
	_check(is_instance_valid(inst), "settings screen builds + refreshes offline without error")
	inst.queue_free()
