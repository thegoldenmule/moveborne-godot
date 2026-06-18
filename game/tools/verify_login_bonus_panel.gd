extends SceneTree

## Headless structural smoke for the Daily Login bonus modal:
##   godot --headless --path . --script res://tools/verify_login_bonus_panel.gd
## Instantiates the panel, renders a 7-day calendar, and asserts it builds one cell
## per calendar day and surfaces the Claim button only when the bonus is claimable.
## (The full visual feel is verified by playing the game.)

const PanelS := preload("res://ui/screens/login_bonus_panel.gd")

var _ok := true

const BLOCK := {
	"enabled": true, "version": 1, "cycle_length_days": 7, "reset_on_miss": false,
	"calendar": [
		{"day": 1, "currency": "coins", "amount": 50},
		{"day": 2, "currency": "coins", "amount": 75},
		{"day": 3, "currency": "coins", "amount": 100},
		{"day": 4, "currency": "coins", "amount": 150},
		{"day": 5, "currency": "coins", "amount": 200},
		{"day": 6, "currency": "coins", "amount": 300},
		{"day": 7, "currency": "gems", "amount": 20}]}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var panel = PanelS.new()
	root.add_child(panel)   # parent is in the tree -> _ready/_build run synchronously

	# level 3 (days 1-3 claimed), bonus claimable
	panel.render(BLOCK, 3, true)
	_check("strip builds one cell per calendar day", panel._strip.get_child_count() == 7)
	_check("claim button visible when claimable", panel._claim_btn.visible)

	# not claimable -> claim hidden
	panel.render(BLOCK, 3, false)
	_check("claim button hidden when not claimable", not panel._claim_btn.visible)

	# a claim intent fires the signal
	var fired := [false]
	panel.claim_requested.connect(func(): fired[0] = true)
	panel.render(BLOCK, 3, true)
	panel._claim_btn.emit_signal("pressed")
	_check("claim button emits claim_requested", fired[0])

	panel.queue_free()
	print("VERIFY login_bonus_panel: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
