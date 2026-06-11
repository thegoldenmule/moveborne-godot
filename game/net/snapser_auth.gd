class_name MbSnapserAuth
extends Node

## Anonymous Snapser sign-in for the deployed validator BYOSnap. The gateway
## requires a user session on every route, so before talking to the validator we
## PUT /v1/auth/login/anon on the Auth snap, which returns
## {user: {id, session_token, token_validity_seconds}}; subsequent requests carry
## the session as `Token` / `User-Id` headers (auth_headers()).
##
## The anon username is generated once and persisted in user:// alongside the
## session, so the same Snapser user is reused across launches; the cached token
## is reused until near expiry, then a fresh login is performed transparently.

const GATEWAY := "https://gateway.snapser.com/c4n1awfs"
const SAVE_PATH := "user://snapser_session.json"
const EXPIRY_MARGIN_SEC := 60

var user_id := ""
var session_token := ""
var _expires_at := 0     # unix seconds
var _username := ""
var _profile_name := ""  # canonical handle from the Profiles snap (overrides username)
var _loaded := false


## Gateway auth headers for HTTP requests and the WebSocket handshake.
func auth_headers() -> PackedStringArray:
	return PackedStringArray(["Token: " + session_token, "User-Id: " + user_id])


## The persisted anon username — the bootstrap handle generated on first login
## (godot-XXXXXXXX). The display name seeds from this on first profile creation.
func username() -> String:
	return _username


## The canonical handle the player sees and shares: the Profiles-snap display
## name once known, falling back to the anon username (no profile / offline).
## Leaderboard submissions stash THIS in user_metadata.name.
func display_name() -> String:
	return resolve_display_name(_profile_name, _username)


## Cache the loaded/edited profile display name so display_name() (and thus
## leaderboard submissions) reflect it. "" clears back to the username fallback.
func set_profile_name(name: String) -> void:
	_profile_name = name


## Canonical-handle resolution (static: unit-testable). Profile name wins when
## non-empty, else the bootstrap fallback.
static func resolve_display_name(profile_name: String, fallback: String) -> String:
	return profile_name if profile_name != "" else fallback


## Ensure a live session (cached or fresh anonymous login). Coroutine — await it:
##   var ok: bool = await auth.ensure_session()
func ensure_session() -> bool:
	if not _loaded:
		_load()
	if _session_valid():
		return true
	return await _login()


func _session_valid() -> bool:
	return session_token != "" and user_id != "" \
		and int(Time.get_unix_time_from_system()) < _expires_at - EXPIRY_MARGIN_SEC


func _login() -> bool:
	if _username == "":
		_username = "godot-%08x" % (randi() & 0xffffffff)
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"username": _username, "create_user": true})
	var err := http.request(GATEWAY + "/v1/auth/login/anon",
		["Content-Type: application/json"], HTTPClient.METHOD_PUT, body)
	if err != OK:
		http.queue_free()
		push_warning("Snapser login: HTTPRequest failed to start: %d" % err)
		return false
	var resp: Array = await http.request_completed
	http.queue_free()
	var code: int = resp[1]
	var text: String = (resp[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text)
	var user = data.get("user") if data is Dictionary else null
	if code != 200 or not (user is Dictionary):
		push_warning("Snapser login failed (HTTP %d): %s" % [code, text])
		return false
	user_id = str(user.get("id", ""))
	session_token = str(user.get("session_token", ""))
	var ttl := int(user.get("token_validity_seconds", 0))
	_expires_at = int(Time.get_unix_time_from_system()) + (ttl if ttl > 0 else 3600)
	_save()
	return user_id != "" and session_token != ""


## Drop this device's anonymous identity: clear the session + cached handle and
## delete the persisted file, so the next ensure_session() mints a fresh anon
## user. (Anonymous accounts have no credential to re-attach, so "sign out" =
## start over.)
func sign_out() -> void:
	user_id = ""
	session_token = ""
	_expires_at = 0
	_username = ""
	_profile_name = ""
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _load() -> void:
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	_username = str(data.get("username", ""))
	user_id = str(data.get("user_id", ""))
	session_token = str(data.get("session_token", ""))
	_expires_at = int(data.get("expires_at", 0))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Snapser login: cannot write " + SAVE_PATH)
		return
	f.store_string(JSON.stringify({
		"username": _username, "user_id": user_id,
		"session_token": session_token, "expires_at": _expires_at,
	}, "  "))
