@tool
class_name RemoteConfigService
extends "res://addons/editor_tool_kit/tool_service.gd"

## Headless-testable core for the Remote Config authoring tool (a ToolService).
## The SINGLE aggregation point for the Snapser app-config/v1 document: it reads
## the committed registry validator/content/app_config.manifest.json + every
## entry's content blob, builds the WHOLE document, copies the full publish
## payload, and runs Check Sync by shelling out to the ONE generic TS comparator
## (validator/src/validator/tools/appconfig.ts) — never reimplementing the compare
## in GDScript.
##
## No Control / EditorInterface references (it loads under godot --headless); the
## only editor-side seams are OS.execute (check_sync) and DisplayServer.clipboard_set
## (copy_publish_payload), both harmless headless. build_document() / versions() /
## validate() are pure reads the verifier asserts directly.

const ContentStore := preload("res://addons/editor_tool_kit/content_store.gd")

## Repo-relative path of the registry and the generic comparator.
const MANIFEST_REL := "validator/content/app_config.manifest.json"
const CONTENT_REL := "validator/content"
const APPCONFIG_TS_REL := "validator/src/validator/tools/appconfig.ts"

## Emitted after reload so the dock rebuilds its table + preview.
signal changed

var manifest: Dictionary = {}    # {app_config_version, entries:[{key,file,version_field,label}]}
var blobs: Dictionary = {}       # key -> parsed content Dictionary ({} when missing/unparseable)
var _content_dir := ""           # absolute dir the blobs were loaded from (for validate's re-stat)


# ── load ───────────────────────────────────────────────────────────────────────


## Load the committed manifest + every blob from the real repo paths. The dock
## drives the rebuild on `changed` (mirrors StoryMapService.reload).
func reload() -> void:
	reload_from(_repo_path(MANIFEST_REL), _repo_path(CONTENT_REL))


## Load core, parameterized by paths so the headless verifier drives a temp dir.
func reload_from(manifest_abs: String, content_dir_abs: String) -> void:
	_content_dir = content_dir_abs
	manifest = ContentStore.load_json(manifest_abs)
	blobs.clear()
	for e in _entries():
		blobs[str(e.get("key", ""))] = ContentStore.load_json(
			content_dir_abs.path_join(str(e.get("file", ""))))
	clear_dirty()
	changed.emit()


## The manifest's entries array ([] when absent/malformed).
func _entries() -> Array:
	var e = manifest.get("entries", [])
	return e if e is Array else []


func app_config_version() -> String:
	return str(manifest.get("app_config_version", ""))


# ── aggregation (pure) ──────────────────────────────────────────────────────────


## THE single aggregation point: the exact document that gets published —
## { <key>: <blob>, … } for every manifest entry whose blob is present, in
## manifest order. Pure (reads only manifest + blobs); the verifier asserts it.
func build_document() -> Dictionary:
	var doc := {}
	for e in _entries():
		var key := str(e.get("key", ""))
		var b: Dictionary = blobs.get(key, {})
		if key != "" and not b.is_empty():   # missing blobs are blocked by validate()
			doc[key] = b
	return doc


## Per-key rollup for the dock table: [{key, file, label, present, version}].
func versions() -> Array:
	var out: Array = []
	for e in _entries():
		var key := str(e.get("key", ""))
		var vfield := str(e.get("version_field", ""))
		var b: Dictionary = blobs.get(key, {})
		out.append({
			"key": key,
			"file": str(e.get("file", "")),
			"label": str(e.get("label", key)),
			"present": not b.is_empty(),
			"has_version": b.has(vfield),   # distinguish "absent field" from a real 0
			"version": int(b.get(vfield, 0)),
		})
	return out


## Structural problems ([] == publishable). Manifest missing/empty; per entry a
## missing file, an unparseable/empty blob, or a missing/non-int version field;
## and any duplicate key across the manifest.
func validate() -> Array:
	var problems: Array = []
	if _entries().is_empty():
		problems.append("manifest missing or has no entries (%s)" % MANIFEST_REL)
		return problems
	var seen := {}
	for e in _entries():
		var key := str(e.get("key", ""))
		var file := str(e.get("file", ""))
		var vfield := str(e.get("version_field", ""))
		if key == "" or file == "" or vfield == "":
			problems.append("manifest entry missing key/file/version_field: %s" % str(e))
			continue
		if seen.has(key):
			problems.append("%s: duplicate key in manifest" % key)
		seen[key] = true
		var path := _content_dir.path_join(file)
		if not FileAccess.file_exists(path):
			problems.append("%s: content file not found (%s/%s)" % [key, CONTENT_REL, file])
			continue
		var b: Dictionary = blobs.get(key, {})
		if b.is_empty():
			problems.append("%s: blob absent or not a JSON object (%s/%s)" % [key, CONTENT_REL, file])
			continue
		if not b.has(vfield) or not (typeof(b[vfield]) == TYPE_INT or typeof(b[vfield]) == TYPE_FLOAT):
			problems.append("%s: missing integer version field \"%s\"" % [key, vfield])
	return problems


# ── publish / verify (editor-side seams) ────────────────────────────────────────


## Copy the WHOLE app-config document to the clipboard for a manual console paste.
## Gated on validate() so a structurally-broken document never reaches the clipboard
## (and a single-key paste can never silently drop a sibling). Returns
## {ok:true, keys, count, bytes} or err(joined problems).
func copy_publish_payload() -> Dictionary:
	var problems := validate()
	if not problems.is_empty():
		return err("\n".join(problems))
	var doc := build_document()
	var text := JSON.stringify(doc, "  ")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)   # no-op under the headless verifier
	return ok({"keys": doc.keys(), "count": doc.size(), "bytes": text.length()})


## Check the live Remote Config against the committed blobs by shelling out to the
## ONE generic comparator (appconfig.ts verify --json) — no second comparator in
## GDScript. Returns {ok, code, results:[{key,status,committed_version,live_version}],
## text}. code -1 = bun missing (surfaced as a hint, like StoryMapService did).
func check_sync() -> Dictionary:
	var out: Array = []
	var args := [_repo_path(APPCONFIG_TS_REL), "verify", "--json"]
	var code := OS.execute("bun", args, out, true)
	var text := "\n".join(out).strip_edges() if out.size() > 0 else ""
	var results: Array = []
	var error := ""
	# appconfig.ts verify --json prints exactly one JSON object on stdout; scan for
	# the first parseable line carrying "results" (other lines are plain logs) and
	# stop there. On a login/HTTP failure it prints {ok:false,error,results:[]}.
	for line in text.split("\n"):
		var parsed = JSON.parse_string(line.strip_edges())
		if parsed is Dictionary and parsed.has("results"):
			results = parsed.get("results", [])
			error = str(parsed.get("error", ""))
			break
	return {"ok": code == 0, "code": code, "results": results, "error": error, "text": text}


# ── helpers ──────────────────────────────────────────────────────────────────--


static func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(rel)
