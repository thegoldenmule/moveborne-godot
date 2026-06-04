extends Node

## Quality — VFX quality tier (render/quality-settings.ts). LOW / MEDIUM / HIGH
## gates particle density, the continuous run loops, and (future) glow. Persisted
## to user://settings.cfg. Defaults LOW on touch devices, HIGH otherwise.

signal changed

enum Level { LOW, MEDIUM, HIGH }

const _CFG := "user://settings.cfg"

var level: int = Level.HIGH


func _ready() -> void:
	_load()


## Multiplier on particle counts (cheaper on lower tiers).
func particle_scale() -> float:
	match level:
		Level.LOW: return 0.45
		Level.MEDIUM: return 0.75
		_: return 1.0


## Continuous tile-effect "run" loops only on MEDIUM+ (they're the steady cost).
func loops_enabled() -> bool:
	return level != Level.LOW


## For the future tile/HUD glow shader.
func glow_enabled() -> bool:
	return level != Level.LOW


func glow_quality() -> float:
	return 0.1 if level == Level.MEDIUM else 0.3


func level_name() -> String:
	return ["LOW", "MEDIUM", "HIGH"][level]


func cycle() -> void:
	set_level((level + 1) % 3)


func set_level(l: int) -> void:
	level = clampi(l, 0, 2)
	_save()
	changed.emit()


func _default_level() -> int:
	return Level.LOW if DisplayServer.is_touchscreen_available() else Level.HIGH


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_CFG) == OK:
		level = clampi(int(cfg.get_value("vfx", "quality", _default_level())), 0, 2)
	else:
		level = _default_level()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_CFG)  # preserve any other settings
	cfg.set_value("vfx", "quality", level)
	cfg.save(_CFG)
