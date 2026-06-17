class_name MbRemoteConfigClient
extends Node

## Client for the Snapser Remote Config snap: reads the app-config document
## that carries live content (the story catalog rides under the
## "story_catalog" key so later features can add their own keys). Read-only —
## config is published via the Snapser console, never from the client.
##
## Same shape as leaderboards_client.gd: pure request/response helpers are
## static (unit-testable without a network); the coroutine carries the session
## headers from MbSnapserAuth.

const APP_CONFIG_VERSION := "v1"
const CATALOG_KEY := "story_catalog"
## Daily Missions rides under its own key in the SAME app-config document as the
## story catalog (display catalog + weekday rotation map). See the Daily Missions
## feature spec.
const DAILY_MISSIONS_KEY := "daily_missions"
## Preloaded (not the class_name global) so this compiles before an editor
## scan registers the new Mb* classes — same reason app_shell preloads Reg.
const Catalog := preload("res://story/story_catalog.gd")

var _auth: MbSnapserAuth


func _init(auth: MbSnapserAuth) -> void:
	_auth = auth


## --- pure helpers (static) ----------------------------------------------------


static func app_config_url(version: String = APP_CONFIG_VERSION) -> String:
	return MbSnapserAuth.GATEWAY + "/v1/remote-config/app-config/" + version.uri_encode()


## remoteConfigGetAppConfigResponse -> the config object ({} on any other shape).
static func parse_app_config(data) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var config = data.get("config", {})
	return config if config is Dictionary else {}


## The story catalog inside an app-config document ({} when absent).
static func extract_catalog(config: Dictionary) -> Dictionary:
	var catalog = config.get(CATALOG_KEY, {})
	return catalog if catalog is Dictionary else {}


## The daily_missions block inside an app-config document ({} when absent). Reads
## a sibling key, so it never disturbs extract_catalog / story-catalog selection.
static func extract_daily_missions(config: Dictionary) -> Dictionary:
	var block = config.get(DAILY_MISSIONS_KEY, {})
	return block if block is Dictionary else {}


## Remote-vs-baked selection: the remote catalog wins only when it is present,
## structurally valid, and at least as new as the baked copy — a stale or
## malformed remote payload can never downgrade a shipped client.
static func select_catalog(remote: Dictionary, baked: Dictionary) -> Dictionary:
	if remote.is_empty() or not Catalog.validate(remote).is_empty():
		return baked
	if int(remote.get("catalog_version", 0)) < int(baked.get("catalog_version", 0)):
		return baked
	return remote


## --- network (coroutine — await it) -------------------------------------------


## Fetch the app config. Returns {ok, config, error}.
func fetch_app_config() -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "config": {}, "error": "not signed in"}
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(_auth.auth_headers())
	var err := http.request(app_config_url(), headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "config": {}, "error": "HTTPRequest failed to start: %d" % err}
	var resp: Array = await http.request_completed
	http.queue_free()
	var code := int(resp[1])
	var data = JSON.parse_string((resp[3] as PackedByteArray).get_string_from_utf8())
	if code != 200:
		return {"ok": false, "config": {}, "error": "HTTP %d" % code}
	return {"ok": true, "config": parse_app_config(data), "error": ""}
