extends SceneTree

## Headless, offline verifier for the GenTexture ref pipeline (no API, no editor):
##   godot --headless --path . --script res://tools/verify_artgen_refs.gd
## Proves a promoted generation round-trips through a GenTexture .tres + pooled
## pixels, that the ref is a usable Texture2D carrying its provenance, that
## swap_permutation re-points the same ref at a sibling, and that the manifest is
## keyed by uid. Saves under res://assets/generated/misc/<tmp>.tres and restores
## the manifest + cleans up every artifact it writes.

const ServiceT := preload("res://addons/artgen/artgen_service.gd")
const GenTextureT := preload("res://assets/gen_texture.gd")

const MANIFEST := "res://assets/generated/ai_manifest.json"
const NAME := "_verify_ref_tmp"
const DEST := "res://assets/generated/misc/" + NAME + ".tres"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true

	# Snapshot the real manifest so the test can restore it byte-for-byte.
	var had_manifest := FileAccess.file_exists(MANIFEST)
	var manifest_backup := FileAccess.get_file_as_bytes(MANIFEST) if had_manifest else PackedByteArray()

	# Two sibling generations (same batch), distinguishable by size.
	var tmp := OS.get_cache_dir().path_join("artgen_ref_verify")
	DirAccess.make_dir_recursive_absolute(tmp)
	_write_svg(tmp.path_join("g_v1.svg"), 64, "#a070ff")
	_write_svg(tmp.path_join("g_v2.svg"), 48, "#70a0ff")

	var ledger := tmp.path_join("ledger.jsonl")
	if FileAccess.file_exists(ledger):
		DirAccess.remove_absolute(ledger)
	for spec in [["g_v1", "g_v1.svg"], ["g_v2", "g_v2.svg"]]:
		_append(ledger, {"type": "generation", "id": spec[0], "batch_id": "b_ref",
			"ts": "t", "preset": "icon-flat", "subject": "orb", "prompt": "an orb",
			"status": "ok", "parent_id": null, "model": "recraftv4_1_vector",
			"style_id": null, "post": [], "file": spec[1]})

	var service: Node = ServiceT.new()
	root.add_child(service)
	service.client.api_key = ""          # no network (skip balance refresh)
	service.repo_root = tmp              # rec.file resolves against our temp sources
	service.ledger_path = ledger
	service.reload_history()

	# Clean any leftovers from a prior failed run.
	_cleanup()

	# -- save: generation → GenTexture ref + pooled pixels ---------------------
	var saved: Dictionary = await service.save_generation("g_v1", "misc", NAME)
	ok = _check(ok, saved.get("ok", false), "save_generation ok: " + str(saved.get("error", "")))
	ok = _check(ok, str(saved.get("dest", "")) == DEST, "ref written as .tres")
	ok = _check(ok, FileAccess.file_exists(str(saved.get("pool", ""))), "pixels baked into pool")
	ok = _check(ok, FileAccess.file_exists(DEST), "ref file on disk")

	# -- the ref is a usable Texture2D carrying its provenance -----------------
	var ref: Variant = ResourceLoader.load(DEST, "", ResourceLoader.CACHE_MODE_IGNORE)
	ok = _check(ok, ref is GenTextureT, "ref loads as a GenTexture")
	ok = _check(ok, ref is Texture2D, "GenTexture IS a Texture2D (drop-in)")
	ok = _check(ok, ref != null and ref.source != null, "ref resolves to baked pixels")
	ok = _check(ok, ref != null and ref.get_width() == 64, "proxy width follows source (64)")
	ok = _check(ok, ref != null and str(ref.gen_id) == "g_v1", "provenance: gen_id embedded")
	ok = _check(ok, ref != null and str(ref.batch_id) == "b_ref", "provenance: batch_id embedded")
	ok = _check(ok, ref != null and str(ref.prompt) == "an orb", "provenance: prompt embedded")

	# -- manifest keyed by uid, pointing back at the ref -----------------------
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var entry := _entry_for(manifest, DEST)
	ok = _check(ok, not entry.is_empty(), "manifest has an entry resolving to the ref")
	ok = _check(ok, str(entry.get("gen_id", "")) == "g_v1", "manifest entry carries gen_id")
	# Keyed by the ref's uid in-editor; headless (no scan → no uid) falls back to
	# the ref path. Either way there must be no collided empty-string key.
	ok = _check(ok, not manifest.get("assets", {}).has(""), "no empty-uid collision key")

	# -- siblings enumerate for swap -------------------------------------------
	var sibs: Array = service.permutations("g_v1")
	ok = _check(ok, sibs.size() == 2, "permutations() returns both batch siblings")

	# -- swap: same ref, new permutation, uid/path unchanged -------------------
	var swapped: Dictionary = await service.swap_permutation(DEST, "g_v2")
	ok = _check(ok, swapped.get("ok", false), "swap_permutation ok: " + str(swapped.get("error", "")))
	ok = _check(ok, str(swapped.get("dest", "")) == DEST, "swap keeps the same ref path")
	var ref2: Variant = ResourceLoader.load(DEST, "", ResourceLoader.CACHE_MODE_IGNORE)
	ok = _check(ok, ref2 != null and str(ref2.gen_id) == "g_v2", "swap re-pointed gen_id")
	ok = _check(ok, ref2 != null and ref2.get_width() == 48, "swap re-pointed pixels (48)")

	# -- duplicate name refused ------------------------------------------------
	var dup: Dictionary = await service.save_generation("g_v1", "misc", NAME)
	ok = _check(ok, not dup.get("ok", true) and str(dup.get("error", "")).contains("already exists"),
		"duplicate ref name refused")

	# -- restore --------------------------------------------------------------
	_cleanup()
	if had_manifest:
		var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
		f.store_buffer(manifest_backup)
		f.close()
	elif FileAccess.file_exists(MANIFEST):
		DirAccess.remove_absolute(MANIFEST)

	print("VERIFY artgen_refs: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _entry_for(manifest: Dictionary, dest: String) -> Dictionary:
	for key in manifest.get("assets", {}):
		var e: Dictionary = manifest["assets"][key]
		if str(e.get("ref_path", key)) == dest:
			return e
	return {}


func _cleanup() -> void:
	for p in [DEST, DEST + ".import", DEST + ".uid",
			"res://assets/generated/_pool/g_v1.svg", "res://assets/generated/_pool/g_v1.svg.import",
			"res://assets/generated/_pool/g_v2.svg", "res://assets/generated/_pool/g_v2.svg.import"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _write_svg(abs_path: String, size: int, fill: String) -> void:
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [size, size]
		+ '<rect width="%d" height="%d" fill="#101010"/>' % [size, size]
		+ '<circle cx="%d" cy="%d" r="%d" fill="%s"/></svg>' % [size / 2, size / 2, size / 3, fill])
	f.close()


func _append(path: String, event: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path)
		else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(event))
	f.close()


func _check(ok: bool, condition: bool, what: String) -> bool:
	if not condition:
		print("FAIL " + what)
	return ok and condition
