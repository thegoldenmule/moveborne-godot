class_name MbLocalSettings
extends RefCounted

## Local device preferences (audio / SFX / haptics) — NOT profile attributes and
## never networked. Persisted to user://settings.cfg via ConfigFile, loaded on
## boot and applied to the AudioServer. Pure load/save/apply so the round-trip is
## unit-testable headless.

const PATH := "user://settings.cfg"
const DEFAULTS := {"master": 1.0, "sfx": 1.0, "haptics": true}


## Load saved prefs, falling back to DEFAULTS for any missing key / no file.
static func load_settings() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return out
	out["master"] = clampf(float(cfg.get_value("audio", "master", DEFAULTS["master"])), 0.0, 1.0)
	out["sfx"] = clampf(float(cfg.get_value("audio", "sfx", DEFAULTS["sfx"])), 0.0, 1.0)
	out["haptics"] = bool(cfg.get_value("haptics", "enabled", DEFAULTS["haptics"]))
	return out


## Persist prefs. Returns OK or a ConfigFile error code.
static func save_settings(s: Dictionary) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", clampf(float(s.get("master", 1.0)), 0.0, 1.0))
	cfg.set_value("audio", "sfx", clampf(float(s.get("sfx", 1.0)), 0.0, 1.0))
	cfg.set_value("haptics", "enabled", bool(s.get("haptics", true)))
	return cfg.save(PATH)


## Apply audio prefs to the live mix. The Master bus always exists; an SFX bus is
## optional (applied only if the project defines one).
static func apply_audio(s: Dictionary) -> void:
	_set_bus_linear("Master", float(s.get("master", 1.0)))
	_set_bus_linear("SFX", float(s.get("sfx", 1.0)))


static func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear) if linear > 0.0 else -80.0)
