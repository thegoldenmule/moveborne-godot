class_name MbProfileClient
extends Node

## Client for the Snapser Profiles snap (first-party, on the same snapend as the
## validator BYOSnap). Plain HTTP through the gateway; every call carries the
## session headers from MbSnapserAuth (Token / User-Id), same pattern as
## leaderboards_client.gd / inventory_client.gd. Pure request/response + name
## helpers are static so they can be tested without a network.
##
## The snap stores a developer-defined JSON object per user; the attributes are
## configured on the snapend (admin tool), NOT hardcoded here. This client speaks
## the three we provision: display_name (text, searchable, public), avatar_id
## (text, public) and an optional title (text, public). user-auth writes are
## gateway-bound to the caller's own user_id.
##
## Profile data is ACCOUNT data — NOT part of SynchronizedGameState, never hashed
## (hard-wall / two-tier-state ADRs).

const BASE := MbSnapserAuth.GATEWAY + "/v1/profiles"

## Provisioned attribute keys (must byte-match the snapend's Profiles config).
const ATTR_DISPLAY_NAME := "display_name"
const ATTR_AVATAR := "avatar_id"
const ATTR_TITLE := "title"

## Display-name bounds (client-side UX validation only — the gateway/snap is the
## real boundary; a user-auth caller can write its own profile directly).
const DISPLAY_NAME_MAX := 24

var _auth: MbSnapserAuth


func _init(auth: MbSnapserAuth) -> void:
	_auth = auth


## --- pure helpers (static: unit-testable without a session or network) -------


## GetProfile / UpsertProfile / PatchProfile share this path. The user MUST be
## the session user for user-auth writes (the gateway binds them to User-Id).
static func profile_url(user_id: String) -> String:
	return "%s/user/%s" % [BASE, user_id.uri_encode()]


## Request body for PUT (upsert) / PATCH — the snap wraps attributes under
## "profile". Pass only the keys you mean to change for a PATCH.
static func profile_body(attrs: Dictionary) -> String:
	return JSON.stringify({"profile": attrs})


## profilesGetProfileResponse -> the attribute dict (or {} on any odd payload).
## Tolerates a missing/!dict "profile" the way the leaderboard parser tolerates
## the int/float JSON ambiguity.
static func parse_profile(data) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var p = data.get("profile")
	return p if p is Dictionary else {}


## Collapse whitespace, strip control characters, and clamp to DISPLAY_NAME_MAX.
## Pure + deterministic so the edit field and tests agree on the normalized form.
static func sanitize_display_name(name: String) -> String:
	var out := ""
	for ch in name.strip_edges():
		# Drop ASCII control chars (incl. newlines/tabs) — single-line handle only.
		if ch.unicode_at(0) >= 32:
			out += ch
	out = out.strip_edges()
	if out.length() > DISPLAY_NAME_MAX:
		out = out.substr(0, DISPLAY_NAME_MAX).strip_edges()
	return out


## A display name is acceptable iff sanitizing leaves a non-empty string within
## bounds. (Duplicates ARE allowed for v1 — uniqueness is not enforced.)
static func is_valid_display_name(name: String) -> bool:
	var s := sanitize_display_name(name)
	return s.length() >= 1 and s.length() <= DISPLAY_NAME_MAX


## --- network calls (coroutines — await them) ---------------------------------


## Fetch the signed-in user's profile. Returns {ok, profile: {..}, error}. A user
## with no profile yet is a 404 from the snap — surfaced as ok=true, empty
## profile (the caller seeds one), NOT an error.
func fetch_profile() -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "profile": {}, "error": "not signed in"}
	var resp := await _request(profile_url(_auth.user_id), HTTPClient.METHOD_GET)
	var code := int(resp.get("code", 0))
	if code == 404:
		return {"ok": true, "profile": {}, "error": ""}
	if code != 200:
		return {"ok": false, "profile": {}, "error": _error_text(resp)}
	return {"ok": true, "profile": parse_profile(resp.get("data")), "error": ""}


## Write the signed-in user's profile. PATCH (partial) by default so a save only
## touches the keys passed; pass upsert=true to PUT a full replace (first
## creation). Returns {ok, profile, error}; PATCH echoes the post-write profile.
func save_profile(attrs: Dictionary, upsert := false) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "profile": {}, "error": "not signed in"}
	var method := HTTPClient.METHOD_PUT if upsert else HTTPClient.METHOD_PATCH
	var resp := await _request(profile_url(_auth.user_id), method, profile_body(attrs))
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "profile": {}, "error": _error_text(resp)}
	return {"ok": true, "profile": parse_profile(resp.get("data")), "error": ""}


## One-shot HTTP round-trip -> {code, data}. The HTTPRequest must be in the tree
## before request() (ERR_UNCONFIGURED otherwise), hence child-of-self.
func _request(url: String, method: int, body := "") -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(_auth.auth_headers())
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		push_warning("Profiles: HTTPRequest failed to start: %d" % err)
		return {"code": 0, "data": null}
	var resp: Array = await http.request_completed
	http.queue_free()
	var text: String = (resp[3] as PackedByteArray).get_string_from_utf8()
	return {"code": int(resp[1]), "data": JSON.parse_string(text)}


static func _error_text(resp: Dictionary) -> String:
	var data = resp.get("data")
	if data is Dictionary and data.has("message"):
		return "%s (HTTP %d)" % [data.get("message"), int(resp.get("code", 0))]
	return "HTTP %d" % int(resp.get("code", 0))
