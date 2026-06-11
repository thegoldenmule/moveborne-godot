class_name MbLeaderboardsClient
extends Node

## Client for the Snapser Leaderboards snap (first-party, on the same snapend as
## the validator BYOSnap). Plain HTTP through the gateway; every call carries the
## session headers from MbSnapserAuth (Token / User-Id), same pattern as
## snapser_auth.gd. Pure request/response helpers are static so they can be
## tested without a network.
##
## Boards are recurring daily/weekly/monthly, Global, behavior=maximum (the
## server keeps the period's best score, so blind re-submits are safe) and
## scope=external — client-writable until the validator reports scores
## (snapser/README.md records the migration posture).

const BASE := MbSnapserAuth.GATEWAY + "/v1/leaderboards/leaderboards"

## Load-bearing: must byte-match the board names configured on the snapend
## (snapser/snapend-manifest.json).
const BOARD_DAILY := "moveborne-daily"
const BOARD_WEEKLY := "moveborne-weekly"
const BOARD_MONTHLY := "moveborne-monthly"
const BOARDS := [BOARD_DAILY, BOARD_WEEKLY, BOARD_MONTHLY]

## Modes whose results land on shared boards. Offline Infinite results stay off
## shared surfaces per the design authority model (design/general.md).
const SUBMIT_MODES := ["story", "pvp"]

var _auth: MbSnapserAuth


func _init(auth: MbSnapserAuth) -> void:
	_auth = auth


## --- pure helpers (static: unit-testable without a session or network) -------


## GetScores URL. range_kind: "top" | "bottom" | "around" (around needs user_id).
## offset > 0 looks K periods back on a recurring board.
static func scores_url(board: String, range_kind: String, count: int,
		user_id := "", offset := 0) -> String:
	var url := "%s/%s?range=%s&count=%d&with_metadata=true" \
		% [BASE, board.uri_encode(), range_kind, count]
	if user_id != "":
		url += "&user_id=" + user_id.uri_encode()
	if offset > 0:
		url += "&offset=%d" % offset
	return url


## SetScore URL — the path user MUST be the session user (the gateway binds
## user-auth writes to the stamped User-Id).
static func score_url(board: String, user_id: String) -> String:
	return "%s/%s/users/%s/score" % [BASE, board.uri_encode(), user_id.uri_encode()]


## SetScore body. The caller's canonical handle rides along as the display name
## (MbSnapserAuth.display_name() — profile name, else the anon username).
static func score_body(score: int, display_name: String) -> String:
	return JSON.stringify({"score": score, "user_metadata": {"name": display_name}})


## leaderboardsGetScoresResponse -> [{user_id, rank, score, name}] in server
## order (rank is 1-based). Tolerates the int/float ambiguity of parsed JSON.
static func parse_scores(data) -> Array:
	var rows: Array = []
	if not (data is Dictionary):
		return rows
	var entries = data.get("user_scores", [])
	if not (entries is Array):
		return rows
	for us in entries:
		if not (us is Dictionary):
			continue
		var meta = us.get("user_metadata")
		rows.append({
			"user_id": str(us.get("user_id", "")),
			"rank": int(us.get("rank", 0)),
			"score": int(us.get("score", 0)),
			"name": str(meta.get("name", "")) if meta is Dictionary else "",
		})
	return rows


## Post-match gate: only an unconsumed result from a submit-eligible mode with a
## positive score goes to the boards.
static func should_submit(result: Dictionary) -> bool:
	if result.is_empty() or bool(result.get("lb_submitted", false)):
		return false
	if not SUBMIT_MODES.has(str(result.get("mode", ""))):
		return false
	return int(result.get("score", 0)) > 0


## --- network calls (coroutines — await them) ---------------------------------


## Standings for one board. Returns {ok, scores: [{user_id, rank, score, name}], error}.
func fetch_scores(board: String, range_kind: String, count: int,
		user_id := "", offset := 0) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "scores": [], "error": "not signed in"}
	var resp := await _request(scores_url(board, range_kind, count, user_id, offset),
		HTTPClient.METHOD_GET)
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "scores": [], "error": _error_text(resp)}
	return {"ok": true, "scores": parse_scores(resp.get("data")), "error": ""}


## Submit the session user's score to one board. behavior=maximum means a lower
## score is a safe server-side no-op. Returns {ok, rank, score, error}.
func submit_score(board: String, score: int) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "error": "not signed in"}
	var resp := await _request(score_url(board, _auth.user_id),
		HTTPClient.METHOD_PUT, score_body(score, _auth.display_name()))
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "error": _error_text(resp)}
	var data = resp.get("data")
	return {
		"ok": true, "error": "",
		"rank": int(data.get("rank", 0)) if data is Dictionary else 0,
		"score": int(data.get("score", score)) if data is Dictionary else score,
	}


## Post-match entry point: PUT the banked result to all three boards exactly
## once. Marks the result consumed BEFORE the awaits so a re-entrant call (the
## shell resuming again) can never double-submit. Fire-and-forget from the
## shell — failures warn and are dropped (the next eligible run resubmits a
## fresh, equal-or-better score anyway).
func submit_pending(result: Dictionary) -> void:
	if not should_submit(result):
		return
	result["lb_submitted"] = true
	var score := int(result.get("score", 0))
	for board in BOARDS:
		var r: Dictionary = await submit_score(board, score)
		if not bool(r.get("ok", false)):
			push_warning("Leaderboards: submit to %s failed: %s" % [board, r.get("error", "")])


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
		push_warning("Leaderboards: HTTPRequest failed to start: %d" % err)
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
