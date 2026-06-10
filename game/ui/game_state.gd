extends Node
## GameState (autoload). Tiny cross-screen state that survives the (non-)scene-swap.
## Deliberately minimal: NO profile/unlocks/Events-bus until a real feature
## needs them. (Currencies earned that promotion — see below.)

## Per-match launch config, read by scenes/main.gd._ready(). Plain Dictionary
## (consistent with the untyped SynchronizedGameState mirror). Shape:
##   { "mode": "story"|"infinite"|"pvp", "scenario_id": int, "seed": int,
##     "online": bool }
var next_match: Dictionary = {}

## Result banked by MatchState on match_exited (score, scenario, reason, ...).
var last_result: Dictionary = {}

## Cached currency balances from the Snapser Inventory snap. Account data —
## NOT part of SynchronizedGameState, never hashed (hard-wall / two-tier ADRs).
## Plain Dictionary per repo convention: { "coins": int, "souls": int, "gems": int }.
var currencies: Dictionary = {"coins": 0, "souls": 0, "gems": 0}

signal currencies_changed(balances: Dictionary)


## Full replace (a fresh GET of all balances).
func set_currencies(balances: Dictionary) -> void:
	for name in ["coins", "souls", "gems"]:
		currencies[name] = int(balances.get(name, 0))
	currencies_changed.emit(currencies)


## Partial update (e.g. the validator's match_rewards ack carries only the
## currencies it just granted).
func merge_currencies(partial: Dictionary) -> void:
	for name in partial:
		if currencies.has(name):
			currencies[name] = int(partial[name])
	currencies_changed.emit(currencies)
