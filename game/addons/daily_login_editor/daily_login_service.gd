@tool
class_name DailyLoginService
extends "res://addons/editor_tool_kit/tool_service.gd"

## Headless-testable core for the Daily Login Bonus authoring tool (a ToolService).
## Authors the SINGLE committed file validator/content/daily_login.json — the
## Remote Config DISPLAY block the runtime reads live (no baked res:// copy: Daily
## Login is NOT in the determinism/parity domain, so unlike the story catalog there
## is no byte-identical client copy to keep in sync). The Remote Config editor tool
## aggregates this blob into the published app-config document.
##
## Owns the in-memory block, calendar-day CRUD, the enabled / cycle-length /
## reset-on-miss knobs, validate(), a canonical serialize(), and a one-target
## save() with a version-bump rollback via ContentStore. The calendar array is the
## source of truth: days are kept contiguous 1..N and cycle_length_days == N, so a
## row is never orphaned. No Control / EditorInterface refs.

const ContentStore := preload("res://addons/editor_tool_kit/content_store.gd")
## The shared headless model owns the one allowed-currency set (CURRENCIES).
const Model := preload("res://ui/screens/daily_login_model.gd")

const CANONICAL_REL := "validator/content/daily_login.json"
const FIELDS := ["currency", "amount"]

## Emitted after any structural change so the dock rebuilds the day list + readout.
## (The dock deliberately does NOT rebuild the edit form on this, so typing in a
## field is never interrupted — same discipline as the Daily Missions dock.)
signal changed

var block: Dictionary = {}


# ── load ───────────────────────────────────────────────────────────────────────


func reload() -> void:
	reload_from(_repo_path(CANONICAL_REL))


## Load core, parameterized by path so the headless verifier drives a temp dir.
func reload_from(path: String) -> void:
	block = ContentStore.load_json(path)
	if block.is_empty():
		block = {"enabled": false, "version": 1, "cycle_length_days": 0,
			"reset_on_miss": false, "calendar": []}
	if not (block.get("calendar") is Array):
		block["calendar"] = []
	_normalize()
	clear_dirty()


## Coerce each calendar entry to {day, currency, amount}, sort by day, renumber to
## a contiguous 1..N, and re-derive cycle_length_days = N. Tolerates a hand-edited
## or partial file. NOTE: does not mark dirty — it is load-time hygiene.
func _normalize() -> void:
	var entries: Array = []
	for e in block.get("calendar", []):
		if e is Dictionary:
			entries.append({
				"day": int(e.get("day", 0)),
				"currency": str(e.get("currency", "coins")),
				"amount": int(e.get("amount", 0)),
			})
	entries.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	for i in range(entries.size()):
		entries[i]["day"] = i + 1
	block["calendar"] = entries
	block["cycle_length_days"] = entries.size()


# ── calendar reads ──────────────────────────────────────────────────────────--


## Sorted calendar day numbers (drives the day list + the strip preview).
func days() -> Array:
	var out: Array = []
	for e in block.get("calendar", []):
		out.append(int(e.get("day", 0)))
	out.sort()
	return out


## A day's display fields with safe fallbacks (reuses the runtime model shape).
func get_day(day: int) -> Dictionary:
	return Model.calendar_entry(block, day)


# ── calendar mutations (all mark dirty + emit `changed`) ─────────────────────────


## Append the next calendar day (currency coins, amount 0). Returns {day}.
func add_day() -> Dictionary:
	var cal: Array = block["calendar"]
	var day := cal.size() + 1
	cal.append({"day": day, "currency": "coins", "amount": 0})
	block["cycle_length_days"] = cal.size()
	mark_dirty(); changed.emit()
	return {"day": day}


## Remove a day and renumber the rest so days stay contiguous 1..N.
func remove_day(day: int) -> void:
	var cal: Array = block["calendar"]
	for i in range(cal.size()):
		if int(cal[i].get("day", 0)) == day:
			cal.remove_at(i)
			break
	_renumber()
	mark_dirty(); changed.emit()


## Set one editable field (currency/amount) of a calendar day.
func set_day_field(day: int, key: String, value) -> void:
	if not FIELDS.has(key):
		return
	for e in block.get("calendar", []):
		if int(e.get("day", 0)) == day:
			e[key] = int(value) if key == "amount" else str(value)
			mark_dirty(); changed.emit()
			return


# ── knob mutations ──────────────────────────────────────────────────────────────


func set_enabled(on: bool) -> void:
	block["enabled"] = on
	mark_dirty(); changed.emit()


func set_reset_on_miss(on: bool) -> void:
	block["reset_on_miss"] = on
	mark_dirty(); changed.emit()


## Grow or shrink the calendar to exactly n days (>= 1), appending default days or
## dropping trailing ones, keeping cycle_length_days == calendar length.
func set_cycle_length(n: int) -> void:
	n = maxi(1, n)
	var cal: Array = block["calendar"]
	while cal.size() < n:
		cal.append({"day": cal.size() + 1, "currency": "coins", "amount": 0})
	while cal.size() > n:
		cal.remove_at(cal.size() - 1)
	block["cycle_length_days"] = cal.size()
	mark_dirty(); changed.emit()


func _renumber() -> void:
	var cal: Array = block["calendar"]
	for i in range(cal.size()):
		cal[i]["day"] = i + 1
	block["cycle_length_days"] = cal.size()


# ── validation / serialization ──────────────────────────────────────────────────


## Problems with the block. Hard errors block save(); "warning:"-prefixed entries
## are advisory and do not block save.
func validate() -> Array:
	var problems: Array = []
	var cal: Array = block.get("calendar", [])
	if cal.is_empty():
		problems.append("calendar is empty — add at least one day")
	var allowed := Model.CURRENCIES
	var seen := {}
	for i in range(cal.size()):
		var e = cal[i]
		if not (e is Dictionary):
			problems.append("calendar[%d]: entry is not a JSON object" % i)
			continue
		var day := int(e.get("day", 0))
		if day != i + 1:
			problems.append("calendar[%d]: day %d out of sequence (expected %d) — days must be contiguous 1..N" % [i, day, i + 1])
		if seen.has(day):
			problems.append("duplicate day %d" % day)
		seen[day] = true
		if not allowed.has(str(e.get("currency", ""))):
			problems.append("day %d: invalid currency \"%s\" (allowed: %s)" % [day, str(e.get("currency", "")), ", ".join(allowed)])
		if int(e.get("amount", 0)) <= 0:
			problems.append("day %d: amount must be > 0" % day)
	var cycle := int(block.get("cycle_length_days", 0))
	if cycle != cal.size():
		problems.append("warning: cycle_length_days (%d) != calendar length (%d)" % [cycle, cal.size()])
	return problems


## The hard errors only (warnings filtered out) — the save gate.
func _errors() -> Array:
	return validate().filter(func(p): return not str(p).begins_with("warning:"))


## Canonical JSON: a fixed key order (enabled, version, cycle_length_days,
## reset_on_miss, calendar with day-sorted {day,currency,amount}), ints coerced,
## trailing newline — so repeated saves of unchanged content are byte-identical.
func serialize() -> String:
	var cal: Array = []
	for e in block.get("calendar", []):
		cal.append({
			"day": int(e.get("day", 0)),
			"currency": str(e.get("currency", "coins")),
			"amount": int(e.get("amount", 0)),
		})
	cal.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	var out := {
		"enabled": bool(block.get("enabled", false)),
		"version": int(block.get("version", 1)),
		"cycle_length_days": cal.size(),
		"reset_on_miss": bool(block.get("reset_on_miss", false)),
		"calendar": cal,
	}
	return JSON.stringify(out, "  ", false) + "\n"


# ── save ────────────────────────────────────────────────────────────────────--


## Persist to the single canonical target. Auto-bumps version when the block
## changed (is_dirty), rolling the bump back on a write failure. Returns one of:
##   {ok:false, stage:"validate", problems:[...]}
##   {ok:false, stage:"write", error:String}
##   {ok:true, bumped:bool, version:int}
func save() -> Dictionary:
	return save_to(_repo_path(CANONICAL_REL))


func save_to(path: String, scan := true) -> Dictionary:
	var errs := _errors()
	if not errs.is_empty():
		return {"ok": false, "stage": "validate", "problems": errs}
	var bumped := is_dirty()
	var result := ContentStore.bump_then(block, "version",
		func() -> Dictionary:
			return ContentStore.save_all([{"path": path, "text": serialize()}],
				func() -> Array: return [], scan),
		bumped)
	if not result.get("ok", false):
		return {"ok": false, "stage": "write", "error": str(result.get("error", "write failed"))}
	clear_dirty()
	return {"ok": true, "bumped": bumped, "version": int(block.get("version", 1))}


## The provisioning readout — copied to the clipboard so the operator can stand up
## the live ladder + quest in the Snapser console (Trackables + Quests have no
## write API). One login_calendar ladder level per calendar day, then the single
## recurring daily_login quest whose reward is +1 ladder progress.
func provisioning_readout() -> String:
	var lines: Array = []
	lines.append("# Trackables ladder — login_calendar  (kind: xp, auto_assign_level, auto_reset: on_max)")
	for e in _sorted_calendar():
		lines.append("  level %d  min_xp %d  reward %s %d" % [
			int(e["day"]), int(e["day"]), str(e["currency"]), int(e["amount"])])
	lines.append("")
	lines.append("# Quest — daily_login  (recurring, daily cron 0 0 * * *, auto_assign, tags [daily_login])")
	lines.append("  task open_app  goal 1 (counter)")
	lines.append("  reward -> +1 XP on the login_calendar ladder (Quests reward_xp — the ladder grants the day's currency)")
	return "\n".join(lines)


func _sorted_calendar() -> Array:
	var cal: Array = []
	for e in block.get("calendar", []):
		if e is Dictionary:
			cal.append(e)
	cal.sort_custom(func(a, b): return int(a.get("day", 0)) < int(b.get("day", 0)))
	return cal


# ── helpers ──────────────────────────────────────────────────────────────────--


static func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(rel)
