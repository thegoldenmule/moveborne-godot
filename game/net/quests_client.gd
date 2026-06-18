class_name MbQuestsClient
extends Node

## Client for the Snapser Quests snap (first-party, on the same snapend as the
## validator BYOSnap). Plain HTTP through the gateway; every call carries the
## session headers from MbSnapserAuth (Token / User-Id), same pattern as
## leaderboards_client.gd / profile_client.gd. Pure request/response helpers are
## static so they can be tested without a network.
##
## Drives Daily Missions (and, later, Daily Login Bonus — both built-in Quests):
## list the active daily quests by tag, assign today's rotating subset, increment
## counter goals from gameplay, and claim a completed mission's reward. The reward
## is currency granted server-side by the Quests snap; the client reflects it via
## GameState.merge_currencies (Inventory is read-only here, like inventory_client.gd).
##
## Endpoints + verbs match snapser-docs/swagger/quests.swagger3.json. Quest
## state/rewards are ACCOUNT data — NOT part of SynchronizedGameState, never hashed.

const BASE := MbSnapserAuth.GATEWAY + "/v1/quests"

## The tag every Daily Mission quest carries on the snapend (anchor + pool).
const TAG_DAILY := "daily_mission"
## The currency wallets the daily loop can reward (mirrors inventory_client.gd).
const CURRENCIES := ["coins", "souls", "gems"]

var _auth: MbSnapserAuth


func _init(auth: MbSnapserAuth) -> void:
	_auth = auth


## --- pure helpers (static: unit-testable without a session or network) -------


## GetActiveQuests URL. include_reward_contents=true so the reward preview rides
## along; an optional tag filters to one family (daily_mission).
static func active_quests_url(user_id: String, tags := "") -> String:
	var url := "%s/users/%s/active_quests?include_reward_contents=true" \
		% [BASE, user_id.uri_encode()]
	if tags != "":
		url += "&tags=" + tags.uri_encode()
	return url


## AssignQuest URL — assign a (auto-assign-off) pool quest to the session user.
static func assign_url(user_id: String, quest: String) -> String:
	return "%s/users/%s/quests/%s/assign" % [BASE, user_id.uri_encode(), quest.uri_encode()]


## IncrementTaskProgress URL (PUT) — advance a counter goal by a delta.
static func increment_url(user_id: String, quest: String, task: String) -> String:
	return "%s/users/%s/quests/%s/tasks/%s" \
		% [BASE, user_id.uri_encode(), quest.uri_encode(), task.uri_encode()]


## ClaimQuestRewards URL — claim a completed mission's reward (before the reset).
static func claim_url(user_id: String, quest: String) -> String:
	return "%s/users/%s/quests/%s/claim_rewards" % [BASE, user_id.uri_encode(), quest.uri_encode()]


## IncrementTaskProgress body: both delta (int32) and delta64 (int64) per the
## swagger request schema.
static func increment_body(delta: int) -> String:
	return JSON.stringify({"delta": delta, "delta64": delta})


## questsUserQuests -> Array of normalized quest dicts, one per quest, in the map's
## iteration order. Each:
##   { name, status, resets_at (unix s), tags:[String],
##     tasks:[{ name, completed, progress, goal }],
##     reward:{coins, souls, gems} }
## Tolerates the *_64 (int64-as-string) Snapser convention and the int/float JSON
## ambiguity, like parse_balances / parse_scores.
static func parse_active_quests(data) -> Array:
	var out: Array = []
	if not (data is Dictionary):
		return out
	var quests = data.get("quests", {})
	if not (quests is Dictionary):
		return out
	for qname in quests:
		var q = quests[qname]
		if q is Dictionary:
			out.append(_parse_quest(str(qname), q))
	return out


static func _parse_quest(name: String, q: Dictionary) -> Dictionary:
	var tasks: Array = []
	var raw_tasks = q.get("tasks", {})
	if raw_tasks is Dictionary:
		for tname in raw_tasks:
			var t = raw_tasks[tname]
			if t is Dictionary:
				tasks.append({
					"name": str(tname),
					"completed": bool(t.get("completed", false)),
					"progress": _i64(t, "current_progress_64", "current_progress"),
					"goal": _i64(t, "goal_64", "goal"),
				})
	var tags: Array = []
	var raw_tags = q.get("tags", [])
	if raw_tags is Array:
		for tg in raw_tags:
			tags.append(str(tg))
	return {
		"name": name,
		"status": str(q.get("status", "")),
		"resets_at": _as_int(q.get("resets_at")),
		"tags": tags,
		"tasks": tasks,
		"reward": _sum_currencies(q.get("reward_currencies", [])),
	}


## questsClaimQuestRewardsResponse -> a partial {coins/souls/gems} grant for
## GameState.merge_currencies. Prefers currencies_granted_64 (int64-as-string map)
## over the deprecated currencies_granted int map; keeps only known wallets.
static func parse_claim(data) -> Dictionary:
	var out := {}
	if not (data is Dictionary):
		return out
	var raw = data.get("currencies_granted_64")
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		raw = data.get("currencies_granted")
	if not (raw is Dictionary):
		return out
	for nm in CURRENCIES:
		if raw.has(nm):
			out[nm] = _as_int(raw[nm])
	return out


## A quest is claimable when a task is complete and the reward isn't claimed yet.
## Snapser status (verified live): "completed" == reward already claimed;
## "unclaimed" == tasks done, reward waiting. Match these EXACTLY — a substring
## test on "claimed" wrongly matches "unclaimed" (which IS the claimable state).
static func is_claimable(quest: Dictionary) -> bool:
	var status := str(quest.get("status", "")).to_lower()
	if status == "completed":
		return false
	if status == "unclaimed":
		return true
	for t in quest.get("tasks", []):
		if bool((t as Dictionary).get("completed", false)):
			return true
	return false


## Prefer the int64 field (Snapser may serialize it as a string), fall back to the
## int32 one; null/garbage -> 0.
static func _i64(d: Dictionary, k64: String, k: String) -> int:
	var v = d.get(k64)
	if v == null:
		v = d.get(k)
	return _as_int(v)


static func _as_int(v) -> int:
	if v == null:
		return 0
	if v is String:
		return int(v)
	return int(v)


static func _sum_currencies(arr) -> Dictionary:
	var out := {"coins": 0, "souls": 0, "gems": 0}
	if not (arr is Array):
		return out
	for c in arr:
		if not (c is Dictionary):
			continue
		var nm := str(c.get("name", ""))
		if out.has(nm):
			out[nm] += _i64(c, "count_64", "count")
	return out


## --- network calls (coroutines — await them) ---------------------------------


## The session user's active quests, optionally filtered to one tag. Returns
## {ok, quests:[..], error}.
func fetch_active_quests(tags := TAG_DAILY) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "quests": [], "error": "not signed in"}
	var resp := await _request(active_quests_url(_auth.user_id, tags), HTTPClient.METHOD_GET)
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "quests": [], "error": _error_text(resp)}
	return {"ok": true, "quests": parse_active_quests(resp.get("data")), "error": ""}


## Assign one (auto-assign-off) pool quest to the session user. Returns {ok, error}.
## Assigning an already-active quest is treated as a soft success by the caller.
func assign_quest(quest: String) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "error": "not signed in"}
	var resp := await _request(assign_url(_auth.user_id, quest), HTTPClient.METHOD_POST)
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "error": _error_text(resp)}
	return {"ok": true, "error": ""}


## Advance a counter goal by `delta`. Returns {ok, error}.
func increment_task(quest: String, task: String, delta := 1) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "error": "not signed in"}
	var resp := await _request(increment_url(_auth.user_id, quest, task),
		HTTPClient.METHOD_PUT, increment_body(delta))
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "error": _error_text(resp)}
	return {"ok": true, "error": ""}


## Claim a completed mission's reward. Returns {ok, granted:{coins/souls/gems}, error}.
## The grant is server-side; the caller merges `granted` into GameState.
func claim_quest_rewards(quest: String) -> Dictionary:
	if not await _auth.ensure_session():
		return {"ok": false, "granted": {}, "error": "not signed in"}
	var resp := await _request(claim_url(_auth.user_id, quest), HTTPClient.METHOD_POST)
	if int(resp.get("code", 0)) != 200:
		return {"ok": false, "granted": {}, "error": _error_text(resp)}
	return {"ok": true, "granted": parse_claim(resp.get("data")), "error": ""}


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
		push_warning("Quests: HTTPRequest failed to start: %d" % err)
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
