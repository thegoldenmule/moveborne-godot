@tool
extends McpTestSuite

## Virtual currency plumbing: MbInventory response parsing (currencies_64
## int64-strings, missing names default 0) and the GameState balance cache +
## change signal the top bar renders from. No network — the live Inventory
## snap is covered by the gateway smoke pass.

const Inv := preload("res://net/inventory_client.gd")


func suite_name() -> String:
	return "currency"


func test_parse_balances_int64_strings() -> void:
	var b: Dictionary = Inv.parse_balances({
		"currencies_64": {"coins": "153", "souls": "3", "gems": "0"},
	})
	assert_eq(int(b["coins"]), 153, "coins int64-string parsed to int")
	assert_eq(int(b["souls"]), 3, "souls parsed")
	assert_eq(int(b["gems"]), 0, "gems parsed")


func test_parse_balances_missing_default_zero() -> void:
	var b: Dictionary = Inv.parse_balances({"currencies_64": {"coins": "7"}})
	assert_eq(int(b["coins"]), 7, "present currency kept")
	assert_eq(int(b["souls"]), 0, "missing currency defaults to 0")
	assert_eq(int(b["gems"]), 0, "missing currency defaults to 0")


func test_parse_balances_malformed_payload() -> void:
	var b: Dictionary = Inv.parse_balances({"currencies_64": "garbage"})
	assert_eq(int(b["coins"]), 0, "non-dict currencies_64 yields zeros, no crash")
	assert_eq(b.size(), 3, "all three currencies always present")


func test_game_state_set_and_merge_emit() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_true(gs != null, "GameState autoload present")
	var seen: Array = []
	var handler := func(balances: Dictionary) -> void:
		seen.append(balances.duplicate())
	gs.currencies_changed.connect(handler)
	gs.set_currencies({"coins": 100, "souls": 2, "gems": 1})
	assert_eq(int(gs.currencies["coins"]), 100, "set_currencies replaces the cache")
	gs.merge_currencies({"coins": "160"})
	assert_eq(int(gs.currencies["coins"]), 160, "merge updates only the given currency (int64-string ok)")
	assert_eq(int(gs.currencies["souls"]), 2, "merge leaves other balances alone")
	assert_eq(seen.size(), 2, "currencies_changed emitted per update")
	gs.currencies_changed.disconnect(handler)
	gs.set_currencies({})  # restore zeros for other suites
