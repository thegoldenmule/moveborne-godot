class_name MbTrackablesClient
extends Node

## Client for the Snapser Trackables snap (first-party, on the same snapend as the
## validator BYOSnap). Plain HTTP through the gateway; every call carries the
## session headers from MbSnapserAuth (Token / User-Id), same pattern as
## quests_client.gd / leaderboards_client.gd. Pure request/response helpers are
## static so they can be tested without a network.
##
## Drives Daily Login Bonus: reads the login_calendar XP ladder — one level per
## calendar day — so the runtime can position the calendar strip on the player's
## current day. The Snapser console enforces non-overlapping level ranges, so each
## level spans 2 XP (e.g. Day1 [0,1], Day2 [2,3], …) and the daily quest grants
## +2 XP/claim; the runtime positions by the LEVEL INDEX (parse_xp "level"), not
## raw XP. The grant itself is server-side (the ladder's level-completion reward);
## this client only READS.
##
## IMPORTANT: the Trackables snap is NOT provisioned on c4n1awfs yet (confirmed
## 2026-06-18). Until it is, fetch_login_calendar returns {ok:false} gracefully and
## the runtime treats the player as day 0 — the feature stays inert, never errors.

const BASE := MbSnapserAuth.GATEWAY + "/v1/trackables"

## The XP ladder name configured on the snapend for the login calendar (must
## byte-match the provisioned ladder — see the editor's provisioning readout).
const LADDER_LOGIN := "login_calendar"

var _auth: MbSnapserAuth


func _init(auth: MbSnapserAuth) -> void:
	_auth = auth


## --- pure helpers (static: unit-testable without a session or network) -------


## GetUserXp URL — read one XP ladder's current level + total xp for the user.
static func xp_url(user_id: String, xp_name: String) -> String:
	return "%s/users/%s/xp/%s" % [BASE, user_id.uri_encode(), xp_name.uri_encode()]


## trackablesGetUserXpResponse -> { xp:int, level:int, level_name:String }.
## `xp` is the total ladder XP (== days claimed, since each level is 1 XP wide);
## `level` is current_level.index. Tolerates the int64-as-string convention and
## the int/float JSON ambiguity, like quests_client.parse_active_quests.
static func parse_xp(data) -> Dictionary:
	var out := {"xp": 0, "level": 0, "level_name": ""}
	if not (data is Dictionary):
		return out
	out["xp"] = _as_int(data.get("xp"))
	var cur = data.get("current_level")
	if cur is Dictionary:
		out["level"] = _as_int(cur.get("index"))
		out["level_name"] = str(cur.get("name", ""))
	return out


static func _as_int(v) -> int:
	if v == null:
		return 0
	if v is String:
		return int(v)
	return int(v)


## --- network calls (coroutines — await them) ---------------------------------


## Read the player's login_calendar ladder. Returns {ok, xp, level, error}. On any
## non-200 (incl. the snap being absent) returns ok:false with xp/level 0 so the
## runtime degrades to "day 0" rather than surfacing an error.
func fetch_login_calendar() -> Dictionary:
	return await fetch_xp(LADDER_LOGIN)


func fetch_xp(xp_name: String) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "xp": 0, "level": 0, "error": "not signed in"}
	var resp := await _request(xp_url(_auth.user_id, xp_name), HTTPClient.METHOD_GET)
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "xp": 0, "level": 0, "error": _error_text(resp)}
	var parsed := parse_xp(resp.get("data"))
	return {"ok": true, "xp": int(parsed["xp"]), "level": int(parsed["level"]), "error": ""}


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
		push_warning("Trackables: HTTPRequest failed to start: %d" % err)
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
