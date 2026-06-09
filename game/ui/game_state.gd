extends Node
## GameState (autoload). Tiny cross-screen state that survives the (non-)scene-swap.
## Deliberately minimal: NO currencies/profile/unlocks/Events-bus until a real
## feature needs them.

## Per-match launch config, read by scenes/main.gd._ready(). Plain Dictionary
## (consistent with the untyped SynchronizedGameState mirror). Shape:
##   { "mode": "story"|"infinite"|"pvp", "scenario_id": int, "seed": int,
##     "online": bool }
var next_match: Dictionary = {}

## Result banked by MatchState on match_exited (score, scenario, reason, ...).
var last_result: Dictionary = {}
