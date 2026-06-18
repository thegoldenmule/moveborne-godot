extends CanvasLayer

## The Daily Login Bonus controller — owns the data orchestration for the
## once-per-day login reward and the modal calendar panel. Its own CanvasLayer,
## owned by AppShell, active only on the Home surface with a live Snapser session
## and the feature flag on. On app open it ensures today's daily_login quest is
## incremented (the bounded client mint), reads the login_calendar ladder level,
## and surfaces the panel once per daily period when a bonus is claimable; Claim
## claims the quest (the ladder grants the day's currency server-side) and runs the
## shared reward-reveal ceremony.
##
## Pure presentation logic lives in MbDailyLogin (daily_login_model.gd); the
## network in MbQuestsClient / MbTrackablesClient / MbRemoteConfigClient; the claim
## ceremony in MbRewardCeremony (shared with the Daily Missions sigil).
##
## Until the Trackables snap is provisioned the level read returns 0 (today = day
## 1) and the live grant is inert — the feature degrades gracefully, never errors.

const Model := preload("res://ui/screens/daily_login_model.gd")
const PanelS := preload("res://ui/screens/login_bonus_panel.gd")
const RemoteConfigS := preload("res://net/remote_config_client.gd")
const TrackablesS := preload("res://net/trackables_client.gd")
const Ceremony := preload("res://ui/shell/reward_ceremony.gd")

const FLAG_PATH := "user://daily_login.cfg"
const QUEST := "daily_login"
const TASK_OPEN_APP := "open_app"
const TAG := "daily_login"

var _auth: Node          # MbSnapserAuth (shared shell session)
var _quests: Node        # MbQuestsClient
var _currency_bar: Node  # for the reward fly + slot pulse (optional)
var _remote_config: Node # MbRemoteConfigClient
var _trackables: Node    # MbTrackablesClient

var _block: Dictionary = {}
var _level := 0          # login_calendar XP == days claimed this cycle
var _quest: Dictionary = {}
var _reset_unix := 0
var _refreshing := false
var _busy := false       # a claim round-trip is in flight
var _surface_on := false # shell active AND on the Home tab

var _panel: CanvasLayer  # LoginBonusModal


## Pass the shell's shared session + clients. quests/currency_bar may be null in a
## headless build (the controller then stays inert).
func _init(auth: Node = null, quests: Node = null, currency_bar: Node = null) -> void:
	_auth = auth
	_quests = quests
	_currency_bar = currency_bar


func _ready() -> void:
	layer = 6
	name = "LoginBonusLayer"
	if _auth != null:
		_remote_config = RemoteConfigS.new(_auth)
		_remote_config.name = "LoginBonusRemoteConfig"
		add_child(_remote_config)
		_trackables = TrackablesS.new(_auth)
		_trackables.name = "LoginBonusTrackables"
		add_child(_trackables)
	# The modal lives on its own layer (20); owned here so the shell can hide it.
	_panel = PanelS.new()
	add_child(_panel)
	_panel.claim_requested.connect(_on_claim_requested)


func _has_session() -> bool:
	return _auth != null and _quests != null


# --- shell hooks -------------------------------------------------------------


## The shell calls this on suspend/resume (set_active) and tab change; the bonus
## only surfaces on the Home surface with a session + flag on.
func set_surface(active: bool, tab_id: String) -> void:
	_surface_on = active and tab_id == "home"
	if _surface_on:
		refresh()
	elif _panel != null:
		_panel.close()


# --- data orchestration ------------------------------------------------------


## Fetch the daily_login block + the daily_login quest, advance the open_app gate,
## read the ladder level, then surface the panel once per period when claimable.
## Coroutine; fire-and-forget.
func refresh() -> void:
	if _refreshing or not _has_session():
		return
	_refreshing = true
	await _load_block()
	if Model.is_enabled(_block):
		await _ensure_today()
		await _load_level()
		_maybe_open()
	_refreshing = false


func _load_block() -> void:
	if _remote_config == null:
		return
	var r: Dictionary = await _remote_config.fetch_app_config()
	if bool(r.get("ok", false)):
		_block = RemoteConfigS.extract_daily_login(r.get("config", {}))


## Read the login_calendar ladder level (== days claimed). ok:false (e.g.
## Trackables not provisioned) degrades to level 0 → today is day 1.
func _load_level() -> void:
	if _trackables == null:
		return
	var r: Dictionary = await _trackables.fetch_login_calendar()
	_level = int(r.get("xp", 0)) if bool(r.get("ok", false)) else 0


## Locate today's daily_login quest (auto-assigned by tag) and, if its open_app
## task isn't complete yet, increment it once — the bounded client mint that makes
## today's bonus claimable.
func _ensure_today() -> void:
	await _reload_quest()
	if _quest.is_empty():
		await _quests.assign_quest(QUEST)   # auto_assign usually covers this
		await _reload_quest()
	if _quest.is_empty():
		return
	if not _quest_task_done():
		await _quests.increment_task(QUEST, TASK_OPEN_APP, 1)
		await _reload_quest()


func _reload_quest() -> void:
	var r: Dictionary = await _quests.fetch_active_quests(TAG)
	_quest = {}
	if bool(r.get("ok", false)):
		for q in r.get("quests", []):
			if str((q as Dictionary).get("name", "")) == QUEST:
				_quest = q
				break
	_reset_unix = int(_quest.get("resets_at", 0))


func _quest_task_done() -> bool:
	for t in _quest.get("tasks", []):
		if bool((t as Dictionary).get("completed", false)):
			return true
	return false


## True when today's daily_login quest has a reward waiting to be claimed.
func _claimable() -> bool:
	return not _quest.is_empty() and _quests != null and _quests.is_claimable(_quest)


# --- open / claim ------------------------------------------------------------


## Surface the panel once per daily period when a bonus is claimable.
func _maybe_open() -> void:
	if not _claimable():
		return
	if _reset_unix > 0 and _reset_unix == int(_flag("last_open_period", 0)):
		return
	if _reset_unix > 0:
		_set_flag("last_open_period", _reset_unix)
	_open_panel()


func _open_panel() -> void:
	if _panel != null:
		_panel.open(_block, _level, _claimable())


func _on_claim_requested() -> void:
	if _busy or _quests == null:
		return
	_busy = true
	var cycle := Model.cycle_length(_block)
	var today := Model.today_day(_level, cycle)
	var entry := Model.calendar_entry(_block, today)   # the day's reward, for the reveal
	var r: Dictionary = await _quests.claim_quest_rewards(QUEST)
	if bool(r.get("ok", false)):
		# The quest grants +1 ladder XP; the login_calendar ladder grants the day's
		# currency server-side. Celebrate the calendar's reward (the ceremony also
		# optimistically credits the wallet; an Inventory refetch reconciles). Prefer
		# the server-reported grant if the quest itself carried currency.
		var granted: Dictionary = r.get("granted", {})
		if granted.is_empty() and int(entry.get("amount", 0)) > 0:
			granted = {str(entry.get("currency", "coins")): int(entry.get("amount", 0))}
		if not granted.is_empty():
			await Ceremony.run(self, _currency_bar, granted)
	# Reflect the new server state, then re-render or close. _busy stays held across
	# the claim + ceremony + reloads so a second tap can't start a concurrent claim.
	await _reload_quest()
	await _load_level()
	_busy = false
	if _panel != null and _panel.visible:
		if _claimable():
			_panel.render(_block, _level, true)
		else:
			_panel.close()


# --- local flags -------------------------------------------------------------


func _flag(key: String, default):
	var cfg := ConfigFile.new()
	if cfg.load(FLAG_PATH) != OK:
		return default
	return cfg.get_value("daily_login", key, default)


func _set_flag(key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(FLAG_PATH)
	cfg.set_value("daily_login", key, value)
	cfg.save(FLAG_PATH)
