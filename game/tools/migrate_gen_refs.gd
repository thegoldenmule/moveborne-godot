extends SceneTree

## One-shot migration of the legacy direct .svg/.png assets under
## res://assets/generated/icons/ into GenTexture refs. Run headless:
##   godot --headless --path . --script res://tools/migrate_gen_refs.gd -- migrate
##   godot --headless --path . --import            # import the pooled files
##   godot --headless --path . --script res://tools/migrate_gen_refs.gd -- migrate
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/migrate_gen_refs.gd -- finalize
## The first migrate copies pixels into the pool + writes refs (pool not yet
## imported → pixels embedded); --import imports the pool; the second migrate
## re-points each ref at the now-imported pool (uid ext_resource link, SVGs stay
## scalable). finalize drops the legacy path-keyed manifest entries and reports
## check_manifest. migrate_asset is idempotent, so the double pass is safe.

const ServiceT := preload("res://addons/artgen/artgen_service.gd")
const ICONS_DIR := "res://assets/generated/icons/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mode := "migrate"
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		mode = uargs[0]

	var service: Node = ServiceT.new()
	root.add_child(service)
	service.client.api_key = ""   # no network

	# Every promoted file in icons/ that isn't already a ref.
	var plan: Array = []
	var dir := DirAccess.open(ICONS_DIR)
	for f in dir.get_files():
		if f.ends_with(".import") or f.ends_with(".uid") or f.ends_with(".tres"):
			continue
		plan.append({"old": ICONS_DIR + f, "name": f.get_basename()})

	var ok := true
	if mode == "finalize":
		_rebuild_manifest()
		var issues: Array = service.check_manifest()["issues"]
		# A migrated-but-not-yet-deleted old file still shows as an unaccounted
		# on-disk file; that's expected until the deletion step runs.
		for i in issues:
			print("  manifest: ", i)
		print("MIGRATE finalize: rebuilt manifest, %d notes" % issues.size())
	else:
		for item in plan:
			var r: Dictionary = await service.migrate_asset(item["old"], "icons", item["name"])
			if r.get("ok", false):
				print("  ✓ %s → %s (uid %s)" % [item["name"], r.get("dest"), r.get("uid")])
			else:
				ok = false
				print("  ✗ %s — %s" % [item["name"], r.get("error")])
		print("MIGRATE %s: %d assets, %s" % [mode, plan.size(), "OK" if ok else "ERRORS"])

	quit(0 if ok else 1)


const MANIFEST := "res://assets/generated/ai_manifest.json"
const GENERATED := "res://assets/generated"


## Rebuild ai_manifest.json from scratch: one uid-keyed entry per GenTexture
## .tres (provenance read from the resource itself), plus a preserved entry for
## any un-migrated legacy file still on disk. Clears the collided "" key and any
## stale path entries whose files no longer exist.
func _rebuild_manifest() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(old) != TYPE_DICTIONARY:
		old = {"assets": {}}
	var assets := {}

	# Index legacy entries by their on-disk file, so a surviving un-migrated
	# asset keeps its record while migrated/stale ones are dropped.
	var legacy_by_path := {}
	for k in old.get("assets", {}):
		var e: Dictionary = old["assets"][k]
		if not e.has("ref_path"):              # legacy = path-keyed, key IS the file
			legacy_by_path[str(k)] = e

	var dir := DirAccess.open(GENERATED)
	for sub in dir.get_directories():
		if sub == "_pool":
			continue
		var subdir := DirAccess.open(GENERATED + "/" + sub)
		var ref_stems := {}
		for f in subdir.get_files():
			if not f.ends_with(".tres"):
				continue
			var path := "%s/%s/%s" % [GENERATED, sub, f]
			var ref: Variant = ResourceLoader.load(path)
			if ref == null:
				continue
			ref_stems[f.get_basename()] = true
			var id := ResourceLoader.get_resource_uid(path)
			var uid := ResourceUID.id_to_text(id) if id != ResourceUID.INVALID_ID else ""
			var key := uid if not uid.is_empty() else path
			assets[key] = {
				"ref_path": path,
				"pool": ref.source.resource_path if ref.source != null else "",
				"generator": str(ref.generator),
				"style_id": str(ref.style_id) if str(ref.style_id) != "" else null,
				"prompt": str(ref.prompt),
				"gen_id": str(ref.gen_id),
				"batch_id": str(ref.batch_id),
				"generated_at": "",
				"saved_at": str(ref.saved_at),
				"sha256": str(ref.sha256),
				"post": Array(ref.post),
				"modified_after_save": false,
			}
		# Preserve any un-migrated legacy file in this dir (no .tres of same stem).
		for f in subdir.get_files():
			if f.ends_with(".import") or f.ends_with(".uid") or f.ends_with(".tres"):
				continue
			var fp := "%s/%s/%s" % [GENERATED, sub, f]
			if not ref_stems.has(f.get_basename()) and legacy_by_path.has(fp):
				assets[fp] = legacy_by_path[fp]

	var out := {"version": 1, "assets": assets}
	var fa := FileAccess.open(MANIFEST, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, "\t") + "\n")
	fa.close()
