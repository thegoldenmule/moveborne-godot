extends SceneTree

## Headless verifier for the app-config registry ⇄ client contract:
##   godot --headless --path . --script res://tools/verify_app_config_manifest.gd
## Enforces the cross-runtime invariant the design calls out: the committed
## validator/content/app_config.manifest.json app_config_version MUST equal the
## client's MbRemoteConfigClient.APP_CONFIG_VERSION, so the publisher and the
## client can never target different Remote Config document versions. Also checks
## that each entry's content file exists and carries its declared version field,
## and that the client's known keys are registered.

const RC := preload("res://net/remote_config_client.gd")

const MANIFEST_REL := "validator/content/app_config.manifest.json"
const CONTENT_REL := "validator/content"

var _ok := true


func _initialize() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(_repo_path(MANIFEST_REL)))
	_check("manifest parses to an object", manifest is Dictionary)
	if not (manifest is Dictionary):
		_finish()
		return

	_check("manifest.app_config_version == MbRemoteConfigClient.APP_CONFIG_VERSION",
		str(manifest.get("app_config_version", "")) == RC.APP_CONFIG_VERSION)

	var entries = manifest.get("entries", [])
	_check("manifest has entries", entries is Array and not (entries as Array).is_empty())

	var keys := {}
	for e in entries:
		var key := str((e as Dictionary).get("key", ""))
		var file := str((e as Dictionary).get("file", ""))
		var vfield := str((e as Dictionary).get("version_field", ""))
		keys[key] = true
		_check("entry %s has key/file/version_field" % key, key != "" and file != "" and vfield != "")
		var path := _repo_path(CONTENT_REL).path_join(file)
		_check("entry %s file exists (%s)" % [key, file], FileAccess.file_exists(path))
		var blob = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check("entry %s carries an int version field \"%s\"" % [key, vfield],
			blob is Dictionary and (blob as Dictionary).has(vfield)
			and (typeof(blob[vfield]) == TYPE_INT or typeof(blob[vfield]) == TYPE_FLOAT))

	# The client's known keys must be registered in the manifest.
	_check("story_catalog key registered", keys.has(RC.CATALOG_KEY))
	_check("daily_missions key registered", keys.has(RC.DAILY_MISSIONS_KEY))

	_finish()


func _finish() -> void:
	print("VERIFY app_config_manifest: %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)


static func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(rel)


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAIL: %s" % label)
