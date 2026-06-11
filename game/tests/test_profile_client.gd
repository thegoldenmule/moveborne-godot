@tool
extends McpTestSuite

## MbProfileClient pure helpers: URL/body construction against the Profiles
## swagger (snapser-docs/swagger/profiles.swagger3.json), response parsing,
## display-name sanitization/validation, plus the avatar catalog and the
## canonical-handle resolution. No network — the live snap is covered by the
## gateway smoke / e2e passes once it is provisioned on the snapend.

const Profile := preload("res://net/profile_client.gd")
const Avatars := preload("res://ui/avatars.gd")
const AuthS := preload("res://net/snapser_auth.gd")


func suite_name() -> String:
	return "profile_client"


func test_profile_url() -> void:
	assert_eq(Profile.profile_url("user-123"),
		AuthS.GATEWAY + "/v1/profiles/user/user-123",
		"Get/Upsert/Patch URL targets the caller's own user path")


func test_profile_body() -> void:
	var body = JSON.parse_string(Profile.profile_body(
		{"display_name": "Nyx", "avatar_id": "skull_avatar_03"}))
	assert_true(body is Dictionary and body.has("profile"),
		"attributes are wrapped under 'profile'")
	assert_eq(str(body["profile"].get("display_name", "")), "Nyx",
		"display_name carried through the body")


func test_parse_profile() -> void:
	assert_eq(Profile.parse_profile({"profile": {"display_name": "x", "avatar_id": "y"}}),
		{"display_name": "x", "avatar_id": "y"}, "profile dict extracted")
	assert_eq(Profile.parse_profile(null), {}, "non-dict payload -> empty")
	assert_eq(Profile.parse_profile({"profile": 7}), {}, "non-dict profile -> empty")
	assert_eq(Profile.parse_profile({}), {}, "missing profile key -> empty")


func test_display_name_sanitize() -> void:
	assert_eq(Profile.sanitize_display_name("  Nyx  "), "Nyx", "surrounding whitespace trimmed")
	assert_eq(Profile.sanitize_display_name("Ny\tx\n"), "Nyx", "control chars stripped")
	assert_eq(Profile.sanitize_display_name("x".repeat(40)).length(), Profile.DISPLAY_NAME_MAX,
		"clamped to the max length")


func test_display_name_validity() -> void:
	assert_true(Profile.is_valid_display_name("Nyx"), "ordinary name valid")
	assert_true(not Profile.is_valid_display_name(""), "empty invalid")
	assert_true(not Profile.is_valid_display_name("   "), "whitespace-only invalid")


func test_avatar_catalog() -> void:
	assert_eq(Avatars.IDS.size(), 12, "12 preset avatars")
	assert_eq(Avatars.resolve_id(""), Avatars.default_id(), "empty id -> default")
	assert_eq(Avatars.resolve_id("skull_avatar_09"), "skull_avatar_09", "known id preserved")


func test_canonical_handle_resolution() -> void:
	assert_eq(AuthS.resolve_display_name("Nyx", "godot-deadbeef"), "Nyx",
		"profile name is the canonical handle")
	assert_eq(AuthS.resolve_display_name("", "godot-deadbeef"), "godot-deadbeef",
		"falls back to anon username")
