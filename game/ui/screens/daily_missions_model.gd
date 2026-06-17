class_name MbDailyMissions
extends RefCounted

## Pure presentation logic for Daily Missions, shared by the floating Home sigil
## and the modal panel. No Node / network / scene deps, so the whole surface is
## headless-testable (tools/verify_daily_missions.gd) — the same "static helpers"
## discipline as the *_client.gd parsers.
##
## Inputs are the Remote Config daily_missions block (see the implementation
## plan's JSON data model) and the normalized active-quest array from
## MbQuestsClient.parse_active_quests.

## A mission card is in exactly one of these (no "locked" — every active mission is
## available the moment it appears; locking is a story-map concept).
enum CardState { IN_PROGRESS, CLAIMABLE, CLAIMED }

## Sigil badge precedence: a count chip wins, else a soft dot for merely-active,
## else nothing for a fully-claimed (or empty) day.
enum Badge { NONE, DOT, COUNT }

## Inside this many seconds of the soonest reset the countdown goes amber and the
## sigil pulses (the only place the feature escalates its cue).
const WARN_SECONDS := 3600


## True when the feature is configured on and switched on.
static func is_enabled(block: Dictionary) -> bool:
	return block is Dictionary and bool(block.get("enabled", false))


## UTC weekday 0(Sun)..6(Sat) for a unix-seconds clock — matches the STRING keys of
## the daily_missions.by_weekday map. now_unix is injected so tests are deterministic.
static func utc_weekday(now_unix: int) -> int:
	return int(Time.get_datetime_dict_from_unix_time(now_unix).get("weekday", 0))


## The mission names to show today: the anchor first, then the weekday's pool subset.
## Empty when the feature is disabled or the block is malformed. Names absent from
## the catalog are kept (the caller decides how to render an unknown name).
static func todays_mission_names(block: Dictionary, weekday: int) -> Array:
	if not is_enabled(block):
		return []
	var out: Array = []
	var anchor := str(block.get("anchor", ""))
	if anchor != "":
		out.append(anchor)
	var by_weekday = block.get("by_weekday", {})
	if by_weekday is Dictionary:
		var todays = by_weekday.get(str(weekday), [])
		if todays is Array:
			for nm in todays:
				if str(nm) != "" and not out.has(str(nm)):
					out.append(str(nm))
	return out


## Display metadata for a mission name from the catalog, with safe fallbacks so the
## panel never renders a blank card.
static func catalog_entry(block: Dictionary, name: String) -> Dictionary:
	var catalog = block.get("catalog", {}) if block is Dictionary else {}
	var entry = catalog.get(name, {}) if catalog is Dictionary else {}
	if not (entry is Dictionary):
		entry = {}
	return {
		"title": str(entry.get("title", name)),
		"icon": str(entry.get("icon", "")),
		"desc": str(entry.get("desc", "")),
		"reward": str(entry.get("reward", "")),
	}


## A normalized quest (MbQuestsClient.parse_active_quests) -> CardState. Match
## "claimed" (not "claim") so a hypothetical "claimable" status isn't read as CLAIMED.
static func card_state(quest: Dictionary) -> int:
	if str(quest.get("status", "")).to_lower().contains("claimed"):
		return CardState.CLAIMED
	for t in quest.get("tasks", []):
		if bool((t as Dictionary).get("completed", false)):
			return CardState.CLAIMABLE
	return CardState.IN_PROGRESS


## Progress fraction [0,1] across a quest's tasks (averaged; goal 0 -> that task
## counts as complete). Drives the card's progress bar.
static func progress_fraction(quest: Dictionary) -> float:
	var tasks = quest.get("tasks", [])
	if not (tasks is Array) or tasks.is_empty():
		return 0.0
	var total := 0.0
	for t in tasks:
		var goal := int((t as Dictionary).get("goal", 0))
		var prog := int((t as Dictionary).get("progress", 0))
		if bool((t as Dictionary).get("completed", false)) or goal <= 0:
			total += 1.0
		else:
			total += clampf(float(prog) / float(goal), 0.0, 1.0)
	return total / float(tasks.size())


## How many active quests have a reward waiting to be claimed.
static func claimable_count(quests: Array) -> int:
	var n := 0
	for q in quests:
		if card_state(q) == CardState.CLAIMABLE:
			n += 1
	return n


## The sigil badge for the current set (see Badge precedence above).
static func badge_state(quests: Array) -> int:
	if claimable_count(quests) >= 1:
		return Badge.COUNT
	for q in quests:
		if card_state(q) == CardState.IN_PROGRESS:
			return Badge.DOT
	return Badge.NONE


## Absolute unix-seconds of the soonest quest reset, or 0 when none is set (no set
## assigned / offline). The live countdown stores this and ticks against the wall clock.
static func soonest_reset(quests: Array) -> int:
	var soonest := 0
	for q in quests:
		var r := int((q as Dictionary).get("resets_at", 0))
		if r > 0 and (soonest == 0 or r < soonest):
			soonest = r
	return soonest


## Seconds until the soonest quest reset, clamped at 0. 0 when nothing has a reset yet.
static func seconds_to_reset(quests: Array, now_unix: int) -> int:
	var soonest := soonest_reset(quests)
	if soonest == 0:
		return 0
	return maxi(0, soonest - now_unix)


## HH:MM:SS for the countdown label.
static func format_countdown(secs: int) -> String:
	secs = maxi(0, secs)
	return "%02d:%02d:%02d" % [secs / 3600, (secs % 3600) / 60, secs % 60]


## True inside the final hour before reset (and a reset actually exists) — the amber
## warning + pulse window.
static func is_warning(seconds_left: int) -> bool:
	return seconds_left > 0 and seconds_left <= WARN_SECONDS


## The one-time FTUE coachmark shows the first time the sigil is actually visible and
## only until the seen-flag is persisted — so exactly once, ever.
static func should_show_coachmark(coachmark_seen: bool, sigil_visible: bool) -> bool:
	return sigil_visible and not coachmark_seen
