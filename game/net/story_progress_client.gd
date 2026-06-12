class_name MbStoryProgressClient
extends Node

## READ-ONLY client for the per-user story_progress json-blob in the Snapser
## Storage snap. The validator is the sole writer (s2s on CompleteMatch) —
## stars, watermarks, and unlocks are server-authoritative; this client only
## fetches the blob so the map can render. The snapend's Auth user-auth
## restrictions block client writes to the storage routes.
##
## Same shape as leaderboards_client.gd: static pure helpers + a session-
## carrying coroutine.

const BLOB_KEY := "story_progress"
const ACCESS_TYPE := "protected"

var _auth: MbSnapserAuth


func _init(auth: MbSnapserAuth) -> void:
	_auth = auth


## --- pure helpers (static) ----------------------------------------------------


## Owner-scoped blob URL — the owner MUST be the session user (the gateway
## binds user-auth reads to the stamped User-Id).
static func blob_url(user_id: String) -> String:
	return "%s/v1/storage/owner/%s/%s/json-blobs/%s" \
		% [MbSnapserAuth.GATEWAY, user_id.uri_encode(), ACCESS_TYPE, BLOB_KEY]


## storageGetJsonBlobResponse -> the progress dict ({} on any other shape).
static func parse_blob(data) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var value = data.get("value", {})
	return value if value is Dictionary else {}


## The shape an unplayed account renders from (no blob yet).
static func empty_progress() -> Dictionary:
	return {"catalog_version": 0, "levels": {}, "next_level_id": ""}


## --- network (coroutine — await it) -------------------------------------------


## Fetch the session user's progress blob. A missing blob (404 — never played)
## is ok=true with empty progress; only transport/auth failures are errors.
## Returns {ok, progress, error}.
func fetch_progress() -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "progress": empty_progress(), "error": "not signed in"}
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(_auth.auth_headers())
	var err := http.request(blob_url(_auth.user_id), headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "progress": empty_progress(), "error": "HTTPRequest failed to start: %d" % err}
	var resp: Array = await http.request_completed
	http.queue_free()
	var code := int(resp[1])
	var data = JSON.parse_string((resp[3] as PackedByteArray).get_string_from_utf8())
	if code == 404:
		return {"ok": true, "progress": empty_progress(), "error": ""}
	if code != 200:
		return {"ok": false, "progress": empty_progress(), "error": "HTTP %d" % code}
	return {"ok": true, "progress": parse_blob(data), "error": ""}
