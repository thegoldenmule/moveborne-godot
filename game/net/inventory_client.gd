class_name MbInventory
extends Node

## Read-only client for the Snapser Inventory snap's currency balances.
##
## GET {gateway}/v1/inventory/users/{user_id}/currencies with the anonymous
## session headers from MbSnapserAuth ('user' auth). The client has NO write
## path by design: IncrementUserCurrency is locked to api-key/internal callers
## on the platform (User Auth Exemptions), so only the validator can award.
##
## Balances are account data — NOT part of SynchronizedGameState, never hashed
## (hard-wall / two-tier-state ADRs).

const MbSnapserAuthS := preload("res://net/snapser_auth.gd")

## The provisioned currency names; missing entries parse as 0.
const CURRENCIES := ["coins", "souls", "gems"]


## Fetch all balances for the signed-in user. Coroutine — await it. Returns
## {"coins": int, "souls": int, "gems": int} on success, {} on any failure
## (callers should skip the update rather than zero out a stale-but-real bar).
func fetch_balances(auth) -> Dictionary:
	var ok: bool = await auth.ensure_session()
	if not ok:
		return {}
	var http := HTTPRequest.new()
	add_child(http)
	var url: String = MbSnapserAuthS.GATEWAY + "/v1/inventory/users/" + auth.user_id + "/currencies"
	var err := http.request(url, auth.auth_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		push_warning("Inventory: HTTPRequest failed to start: %d" % err)
		return {}
	var resp: Array = await http.request_completed
	http.queue_free()
	var code: int = resp[1]
	var text: String = (resp[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text)
	if code != 200 or not (data is Dictionary):
		push_warning("Inventory: balances fetch failed (HTTP %d): %s" % [code, text])
		return {}
	return parse_balances(data)


## Parse inventoryGetUserCurrenciesResponse: currencies_64 maps currency_name
## to an int64 balance AS A STRING (Snapser *_64 convention); missing names
## default to 0. Static so tests cover it without network.
static func parse_balances(data: Dictionary) -> Dictionary:
	var raw = data.get("currencies_64", {})
	if not (raw is Dictionary):
		raw = {}
	var balances := {}
	for name in CURRENCIES:
		balances[name] = int(str(raw.get(name, "0")))
	return balances
