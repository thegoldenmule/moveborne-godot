@tool
class_name ArtgenService
extends Node

## UI-free ArtGen core: presets/config, request building, decode + immediate
## write, post-processing, the save pipeline (res://assets/generated/ +
## ai_manifest.json), ledger journaling, and thumbnails. The dock and the MCP
## bridge are both thin callers; signals keep the dock fresh when the bridge
## (Claude over MCP) drives generation.
##
## Preset "style_id" semantics: null → config.json default custom style;
## "none" → send no style at all (required for raster output: a vector-base
## custom style forces SVG even on raster models); "<uuid>" → explicit style.

const LedgerT := preload("res://addons/artgen/ledger.gd")
const SvgT := preload("res://addons/artgen/svg_tools.gd")
const ClientT := preload("res://addons/artgen/recraft_client.gd")

const GenTextureT := preload("res://assets/gen_texture.gd")

const MANIFEST_PATH := "res://assets/generated/ai_manifest.json"
# Baked, post-processed pixels live here, named by gen_id and referenced from a
# GenTexture .tres by uid — opaque, deduped, GC-able. The human-named .tres refs
# are what scenes bind to. See assets/gen_texture.gd.
const POOL_DIR := "res://assets/generated/_pool"
const SAVE_CATEGORIES := ["icons", "cards", "textures", "misc"]
const THUMB_SIZE := 256

# Model-family capabilities, keyed by model-id prefix. Per the Recraft docs
# (api-reference/endpoints, /appendix, /styles): every v4-family variant
# (recraftv4_1, *_pro, *_utility, *_vector) rejects style/style_id — custom
# styles are v2/v3-only — and negative_prompt, and v4-family vector models
# take aspect-ratio sizes ("1:1", …) where omitting size auto-selects.
# Unlisted families (recraftv3/recraftv2) keep full current behavior.
const MODEL_CAPS := {
	"recraftv4": {
		"supports_styles": false,
		"supports_negative_prompt": false,
		"vector_size_is_aspect_ratio": true,
	},
}

signal history_changed
signal generation_started(info: Dictionary)
signal generation_completed(records: Array)
signal generation_failed(error: String)
signal balance_changed(credits: int)

var config := {}
var presets := {}
var client: Node

var repo_root := ""
var gen_root := ""
var ledger_path := ""
var thumbs_dir := ""

var balance := -1
var generating := false

var _index := {"generations": {}, "order": [], "styles": []}
var _thumb_textures := {}


# _enter_tree (not _ready): the dock is added straight into the live editor UI,
# so its _ready can fire before this service's _ready would — _enter_tree runs
# synchronously inside the plugin's add_child, guaranteeing the client exists.
func _enter_tree() -> void:
	repo_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	gen_root = repo_root.path_join("art/generated")
	ledger_path = gen_root.path_join("ledger.jsonl")
	thumbs_dir = gen_root.path_join(".thumbs")
	DirAccess.make_dir_recursive_absolute(thumbs_dir)

	reload_config()

	client = ClientT.new()
	client.name = "RecraftClient"
	client.api_key = resolve_api_key()
	add_child(client)

	reload_history()
	_refresh_balance.call_deferred()


## Re-read config.json + presets.json (e.g. after an external edit) without
## restarting the editor.
func reload_config() -> void:
	config = {}
	_load_json_into("res://addons/artgen/config.json", config)
	var pres := {}
	_load_json_into("res://addons/artgen/presets.json", pres)
	presets = pres.get("presets", {})


# -- API key ------------------------------------------------------------------

## Editor project metadata (gitignored) → RECRAFT_API_KEY env → repo-root .env.
func resolve_api_key() -> String:
	if Engine.is_editor_hint():
		var meta: Variant = EditorInterface.get_editor_settings().get_project_metadata(
			"artgen", "api_key", "")
		if str(meta) != "":
			return str(meta)
	var env := OS.get_environment("RECRAFT_API_KEY")
	if not env.is_empty():
		return env
	var env_file := repo_root.path_join(".env")
	if FileAccess.file_exists(env_file):
		for line in FileAccess.get_file_as_string(env_file).split("\n"):
			if line.strip_edges().begins_with("RECRAFT_API_KEY="):
				return line.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


func set_api_key(key: String) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_project_metadata("artgen", "api_key", key)
	client.api_key = key


# -- Generation ---------------------------------------------------------------

## Pure request construction (no I/O): resolves preset/overrides into the
## /v1/images/generations body, applying MODEL_CAPS family rules. Returns the
## payload, or {"ok": false, "error": …} when the request is invalid for the
## resolved model (e.g. an explicit style_id on a v4.x model).
func build_payload(opts: Dictionary) -> Dictionary:
	var preset_name := str(opts.get("preset", ""))
	if not presets.has(preset_name):
		return {"ok": false, "error": "unknown preset '%s' (have: %s)" % [
			preset_name, ", ".join(presets.keys())]}
	var preset: Dictionary = presets[preset_name]

	var subject := str(opts.get("subject", ""))
	# {subject} substitutes in overridden prompts too, so a preset template
	# loaded into the dock's prompt field keeps its placeholder live
	var prompt := (str(opts.get("prompt", "")) if opts.get("prompt") else \
			str(preset.get("prompt", "{subject}"))).replace("{subject}", subject)
	var model_kind := str(opts.get("model", "")) if opts.get("model") else \
			str(preset.get("model", "vector"))
	var model: String = config.get("models", {}).get(model_kind, model_kind)
	var caps := _model_caps(model)
	var n := clampi(int(opts.get("n", 1)), 1, 6)
	var size := str(opts.get("size", "")) if opts.get("size") else \
			str(preset.get("size", "1024x1024"))

	var payload := {
		"prompt": prompt, "model": model, "n": n, "size": size,
		"response_format": "b64_json",
	}
	# v4-family vector models take aspect-ratio sizes, not WxH — omit a pixel
	# size so the API auto-selects instead of rejecting the request.
	if caps.get("vector_size_is_aspect_ratio", false) and model.ends_with("_vector") \
			and _is_pixel_size(size):
		payload.erase("size")

	var style_id: Variant = opts.get("style_id", preset.get("style_id"))
	if style_id == null:
		style_id = config.get("style_id")
	if style_id != null and str(style_id) != "none" and str(style_id) != "":
		if caps.get("supports_styles", true):
			payload["style_id"] = str(style_id)
		elif opts.get("style_id") != null:
			return {"ok": false, "error": ("custom styles are v2/v3-only; %s rejects " +
				"style_id (use a v3 model kind, or style_id 'none')") % model}
		# else: preset/config-inherited style — silently omitted for v4.x
	var controls: Variant = opts.get("controls", preset.get("controls"))
	if controls != null:
		payload["controls"] = controls
	if opts.get("negative_prompt") and caps.get("supports_negative_prompt", true):
		payload["negative_prompt"] = str(opts["negative_prompt"])
	return payload


## True when the resolved model for `model_kind` accepts custom styles —
## drives the dock's "custom styles ignored" note for v4.x kinds.
func model_supports_styles(model_kind: String) -> bool:
	var model: String = config.get("models", {}).get(model_kind, model_kind)
	return _model_caps(model).get("supports_styles", true)


# Longest matching prefix wins, so a future more-specific family entry
# (e.g. "recraftv4_1" beside "recraftv4") can't be shadowed by insertion order.
static func _model_caps(model: String) -> Dictionary:
	var best := ""
	for prefix in MODEL_CAPS:
		if model.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
	return MODEL_CAPS.get(best, {})


static func _is_pixel_size(size: String) -> bool:
	var parts := size.split("x")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()


## opts: {preset*, subject, n, prompt, model, size, style_id, negative_prompt,
## parent_id}. prompt/model/size/style_id override the preset when present.
## Returns {"ok": bool, "generations": [records]} or {"ok": false, "error": …}.
func generate(opts: Dictionary) -> Dictionary:
	var payload := build_payload(opts)
	if payload.get("ok") == false:
		return payload
	var preset_name := str(opts.get("preset", ""))
	var preset: Dictionary = presets[preset_name]
	var subject := str(opts.get("subject", ""))
	var n := int(payload["n"])

	generating = true
	generation_started.emit({"preset": preset_name, "subject": subject, "n": n})
	if balance < 0:
		await _refresh_balance()  # so per-image cost_units can be derived below
	var resp: Dictionary = await client.generate(payload)
	generating = false

	var ts := _now_iso()
	var base_event := {
		"type": "generation", "id": "", "batch_id": _new_id("b"), "ts": ts,
		"provider": "recraft",
		"model": payload["model"], "style_id": payload.get("style_id"), "style": null,
		"preset": preset_name, "subject": subject, "prompt": payload["prompt"],
		"negative_prompt": payload.get("negative_prompt"), "size": payload.get("size"),
		"n": n, "n_index": 0, "controls": payload.get("controls"),
		"random_seed": null, "parent_id": opts.get("parent_id"), "image_id": null,
		"file": null, "post": opts.get("post", preset.get("post", [])),
		"cost_units": 0, "status": "ok",
	}
	if not resp.get("ok", false):
		var msg := str(resp.get("error", "unknown error"))
		var failed := base_event.duplicate()
		failed["id"] = _new_gen_id()
		failed["status"] = "api_error"
		failed["error"] = msg.left(300)
		LedgerT.append(ledger_path, failed)
		reload_history()
		generation_failed.emit(msg)
		return {"ok": false, "error": msg, "code": resp.get("code", 0)}

	var old_balance := balance
	await _refresh_balance()
	var cost: int = (old_balance - balance) if (old_balance >= 0 and balance >= 0) else 0

	var month := _month_bucket()
	DirAccess.make_dir_recursive_absolute(gen_root.path_join(month))
	var records: Array = []
	var data: Array = resp["data"].get("data", [])
	for i in data.size():
		var raw := Marshalls.base64_to_raw(str(data[i].get("b64_json", "")))
		var is_svg := _looks_like_svg(raw)
		var ext := "svg" if is_svg else "png"
		var gid := _new_gen_id()
		var slug := _slugify(subject if not subject.is_empty() else preset_name)
		var rel := "art/generated/%s/%s-%s.%s" % [month, gid, slug, ext]
		var abs_path := repo_root.path_join(rel)
		if is_svg:
			var fa := FileAccess.open(abs_path, FileAccess.WRITE)
			if fa == null:
				generation_failed.emit("cannot write " + rel)
				return {"ok": false, "error": "cannot write %s (err %d)" % [rel, FileAccess.get_open_error()]}
			fa.store_buffer(raw)
			fa.close()
		else:
			# Recraft v4.x raster (recraftv4_1) returns WebP bytes; older models
			# returned PNG. Normalize every raster payload to a real PNG so the
			# .png name is honest — otherwise Finder/QuickLook/iOS/Godot trust the
			# extension, hit the format mismatch, and fail to thumbnail/import.
			var werr := _write_raster_as_png(raw, abs_path)
			if werr != OK:
				generation_failed.emit("cannot decode raster " + rel)
				return {"ok": false, "error": "cannot decode/write %s (err %d)" % [rel, werr]}
		var event := base_event.duplicate()
		event["id"] = gid
		event["n_index"] = i
		event["image_id"] = data[i].get("image_id")
		event["file"] = rel
		event["cost_units"] = int(float(cost) / data.size())
		LedgerT.append(ledger_path, event)
		records.append(event)

	reload_history()
	generation_completed.emit(records)
	return {"ok": true, "generations": records}


# -- Save pipeline ------------------------------------------------------------

## Bake a generation's post-processed pixels into the shared pool
## (res://assets/generated/_pool/<gen_id>.<ext>) and import them. Idempotent: a
## pooled file is reused as-is (never re-runs the paid removeBackground step).
## Returns {ok, pool_path, ext, sha, post, rec} or {ok:false, error}.
func _bake_to_pool(gen_id: String) -> Dictionary:
	var rec: Dictionary = _index["generations"].get(gen_id, {})
	if rec.is_empty() or rec.get("file") == null:
		return {"ok": false, "error": "unknown generation '%s'" % gen_id}

	var ext := str(rec["file"]).get_extension()
	var pool_path := "%s/%s.%s" % [POOL_DIR, gen_id, ext]
	if FileAccess.file_exists(pool_path):
		# Already baked — trust it; declared post steps stand in for "applied".
		return {"ok": true, "pool_path": pool_path, "ext": ext,
			"sha": FileAccess.get_sha256(pool_path), "post": rec.get("post", []), "rec": rec}

	var src_abs := repo_root.path_join(str(rec["file"]))
	var bytes := FileAccess.get_file_as_bytes(src_abs)
	if bytes.is_empty():
		return {"ok": false, "error": "generation file missing: " + str(rec["file"])}

	var applied: Array = []
	for step in rec.get("post", []):
		match str(step):
			"strip_bg_rect":
				if ext == "svg":
					var stripped: Dictionary = SvgT.strip_background(
						bytes.get_string_from_utf8(), _background_color(rec))
					if stripped["status"] == SvgT.STATUS_STRIPPED:
						bytes = str(stripped["text"]).to_utf8_buffer()
						applied.append("strip_bg_rect")
					elif stripped["status"] == SvgT.STATUS_FILL_MISMATCH:
						return {"ok": false, "error":
							"background fill doesn't match the requested background — " +
							"this composition uses it as ink; save raw or regenerate"}
			"removeBackground":
				if ext == "png":
					var rb: Dictionary = await client.remove_background(bytes)
					if not rb.get("ok", false):
						return {"ok": false, "error": "removeBackground failed: " + str(rb.get("error"))}
					var b64: Variant = rb.get("data", {}).get("image", {}).get("b64_json")
					if b64 == null:
						return {"ok": false, "error": "removeBackground returned an unexpected shape"}
					bytes = Marshalls.base64_to_raw(str(b64))
					applied.append("removeBackground")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POOL_DIR))
	if ext == "png":
		# Normalize to a genuine PNG (Recraft v4.x / removeBackground may hand
		# back WebP) so the imported asset is a real .png.
		var werr := _write_raster_as_png(bytes, ProjectSettings.globalize_path(pool_path))
		if werr != OK:
			return {"ok": false, "error": "cannot decode/write %s (err %d)" % [pool_path, werr]}
	else:
		var fa := FileAccess.open(pool_path, FileAccess.WRITE)
		if fa == null:
			return {"ok": false, "error": "cannot write %s (err %d)" % [pool_path, FileAccess.get_open_error()]}
		fa.store_buffer(bytes)
		fa.close()

	await _rescan_filesystem()
	return {"ok": true, "pool_path": pool_path, "ext": ext,
		"sha": FileAccess.get_sha256(pool_path), "post": applied, "rec": rec}


## Promote a generation into the game as a GenTexture ref: bakes its pixels into
## the pool, writes res://assets/generated/<category>/<name>.tres pointing at
## them, and records attribution in ai_manifest.json (keyed by the ref's uid) +
## a ledger save event. Scenes bind to the .tres; rename/move/swap stay intact.
func save_generation(gen_id: String, category: String, asset_name: String) -> Dictionary:
	if not SAVE_CATEGORIES.has(category):
		return {"ok": false, "error": "category must be one of %s" % str(SAVE_CATEGORIES)}
	if not asset_name.is_valid_filename() or asset_name.is_empty():
		return {"ok": false, "error": "invalid asset name '%s'" % asset_name}

	var dest := "res://assets/generated/%s/%s.tres" % [category, asset_name]
	if FileAccess.file_exists(dest):
		return {"ok": false, "error": "asset already exists: " + dest}

	var baked := await _bake_to_pool(gen_id)
	if not baked.get("ok", false):
		return baked

	var result := await _write_ref(dest, gen_id, baked)
	if not result.get("ok", false):
		return result
	LedgerT.append(ledger_path, {
		"type": "save", "gen_id": gen_id, "ts": _now_iso(),
		"dest": dest, "ref_uid": result["uid"], "pool": baked["pool_path"], "sha256": baked["sha"],
	})
	reload_history()
	return result


## Re-point an existing GenTexture ref at a different generation (typically a
## sibling permutation from the same batch). The .tres keeps its uid, so every
## consumer follows the swap untouched.
func swap_permutation(ref_path: String, gen_id: String) -> Dictionary:
	if not FileAccess.file_exists(ref_path):
		return {"ok": false, "error": "no ref at " + ref_path}
	var ref: Variant = ResourceLoader.load(ref_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (ref is GenTextureT):
		return {"ok": false, "error": "not a GenTexture ref: " + ref_path}

	var baked := await _bake_to_pool(gen_id)
	if not baked.get("ok", false):
		return baked

	var result := await _write_ref(ref_path, gen_id, baked)
	if not result.get("ok", false):
		return result
	LedgerT.append(ledger_path, {
		"type": "swap", "gen_id": gen_id, "ts": _now_iso(),
		"dest": ref_path, "ref_uid": result["uid"], "pool": baked["pool_path"], "sha256": baked["sha"],
	})
	reload_history()
	return result


## Sibling permutations of a generation (same batch, n_index order) — the
## candidates for swap_permutation. Returns the batch's records (or just the one
## record for pre-batch ledgers).
func permutations(gen_id: String) -> Array:
	var rec: Dictionary = _index["generations"].get(gen_id, {})
	if rec.is_empty():
		return []
	var batch := str(rec.get("batch_id", gen_id))
	var out: Array = []
	for gid in _index["order"]:
		var r: Dictionary = _index["generations"][gid]
		if str(r.get("batch_id", gid)) == batch:
			out.append(r)
	return out


## Shared writer for save_generation / swap_permutation: stamps a GenTexture
## .tres from a baked-pool result, imports it, and upserts the uid-keyed manifest
## entry. Returns {ok, dest, uid, gen_id, pool, sha256, post}.
func _write_ref(dest: String, gen_id: String, baked: Dictionary) -> Dictionary:
	var rec: Dictionary = baked["rec"]
	var ref := GenTextureT.new()
	ref.source = _load_texture(str(baked["pool_path"]))
	if ref.source == null:
		return {"ok": false, "error": "cannot load baked pixels: " + str(baked["pool_path"])}
	ref.gen_id = gen_id
	ref.batch_id = str(rec.get("batch_id", ""))
	ref.prompt = str(rec.get("prompt", ""))
	ref.generator = "recraft/" + str(rec.get("model", ""))
	ref.style_id = str(rec.get("style_id", "")) if rec.get("style_id") != null else ""
	ref.sha256 = str(baked["sha"])
	ref.saved_at = _now_iso()
	ref.post = PackedStringArray(baked["post"])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
	var serr := ResourceSaver.save(ref, dest)
	if serr != OK:
		return {"ok": false, "error": "cannot write ref %s (err %d)" % [dest, serr]}
	await _rescan_filesystem()

	var uid := _uid_for(dest)
	var manifest := _load_manifest()
	# Re-key by uid: drop any stale entry that named this ref by path.
	manifest["assets"].erase(dest)
	manifest["assets"][uid] = {
		"ref_path": dest,
		"pool": baked["pool_path"],
		"generator": ref.generator,
		"style_id": rec.get("style_id"),
		"prompt": ref.prompt,
		"gen_id": gen_id,
		"batch_id": ref.batch_id,
		"generated_at": rec.get("ts"),
		"saved_at": ref.saved_at,
		"sha256": ref.sha256,
		"post": baked["post"],
		"modified_after_save": false,
	}
	_store_manifest(manifest)
	return {"ok": true, "dest": dest, "uid": uid, "gen_id": gen_id,
		"pool": baked["pool_path"], "sha256": baked["sha"], "post": baked["post"]}


## The uid:// text id Godot assigned a freshly-imported resource (empty if none).
func _uid_for(res_path: String) -> String:
	var id := ResourceLoader.get_resource_uid(res_path)
	return ResourceUID.id_to_text(id) if id != ResourceUID.INVALID_ID else ""


## Load a pooled image as a Texture2D. In-editor the import pipeline has run, so
## ResourceLoader returns the imported texture — ResourceSaver then stores it in
## the .tres as a uid ext_resource (the stable pool link). Headless (verifier,
## no import) falls back to building an ImageTexture from raw pixels, which the
## .tres embeds — fine for tests; real saves run in-editor.
func _load_texture(path: String) -> Texture2D:
	if Engine.is_editor_hint():
		var t: Variant = ResourceLoader.load(path)
		if t is Texture2D:
			return t
	var img := Image.new()
	if path.get_extension() == "svg":
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 1.0) != OK:
			return null
	elif img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func discard_generation(gen_id: String) -> Dictionary:
	if not _index["generations"].has(gen_id):
		return {"ok": false, "error": "unknown generation '%s'" % gen_id}
	LedgerT.append(ledger_path, {"type": "discard", "gen_id": gen_id, "ts": _now_iso()})
	reload_history()
	return {"ok": true}


func create_style(base_style: String, ref_paths: Array) -> Dictionary:
	var resp: Dictionary = await client.create_style(base_style, ref_paths)
	if not resp.get("ok", false):
		return {"ok": false, "error": str(resp.get("error"))}
	var style_id := str(resp["data"]["id"])
	LedgerT.append(ledger_path, {
		"type": "style_created", "ts": _now_iso(), "style_id": style_id,
		"style": base_style,
		"refs": ref_paths.map(func(p: String) -> String: return p.replace(repo_root + "/", "")),
		"cost_units": 40,
	})
	reload_history()
	await _refresh_balance()
	return {"ok": true, "style_id": style_id}


# -- History / index ----------------------------------------------------------

func reload_history() -> void:
	_index = LedgerT.fold(ledger_path)
	history_changed.emit()


## Newest-first records. filters: {preset, state, search} (all optional).
func get_history(filters := {}) -> Array:
	var out: Array = []
	var order: Array = _index["order"]
	for i in range(order.size() - 1, -1, -1):
		var rec: Dictionary = _index["generations"][order[i]]
		if filters.get("preset") and str(rec.get("preset")) != str(filters["preset"]):
			continue
		if filters.get("state") and str(rec.get("state")) != str(filters["state"]):
			continue
		var search := str(filters.get("search", ""))
		if not search.is_empty():
			var hay := (str(rec.get("subject", "")) + " " + str(rec.get("prompt", ""))
				+ " " + str(rec.get("id", ""))).to_lower()
			if not hay.contains(search.to_lower()):
				continue
		out.append(rec)
	return out


## get_history() bucketed into variation groups: newest batch first, records
## inside a group in generation order (n_index ascending). Returns
## [{"batch_id": String, "records": [record, …]}, …]. Records without a
## batch_id (pre-migration ledgers) become singleton groups keyed by id.
func get_history_grouped(filters := {}) -> Array:
	var buckets := {}
	var order: Array = []
	for rec in get_history(filters):
		var key := str(rec.get("batch_id", rec.get("id")))
		if not buckets.has(key):
			buckets[key] = []
			order.append(key)
		buckets[key].append(rec)
	var out: Array = []
	for key in order:
		var records: Array = buckets[key]
		records.reverse()  # history is newest-first; restore n_index order
		out.append({"batch_id": key, "records": records})
	return out


## A record plus its parent chain (oldest ancestor last).
func get_generation(gen_id: String) -> Dictionary:
	var rec: Dictionary = _index["generations"].get(gen_id, {})
	if rec.is_empty():
		return {}
	var lineage: Array = []
	var cursor: Variant = rec.get("parent_id")
	while cursor != null and _index["generations"].has(cursor):
		var parent: Dictionary = _index["generations"][cursor]
		lineage.append(parent)
		cursor = parent.get("parent_id")
	var out := rec.duplicate()
	out["lineage"] = lineage
	return out


func get_styles() -> Array:
	return _index["styles"]


# -- Thumbnails ---------------------------------------------------------------

func thumbnail(gen_id: String) -> Texture2D:
	if _thumb_textures.has(gen_id):
		return _thumb_textures[gen_id]
	var rec: Dictionary = _index["generations"].get(gen_id, {})
	if rec.is_empty() or rec.get("file") == null:
		return null
	var cached := thumbs_dir.path_join(gen_id + ".png")
	var img := Image.new()
	if not (FileAccess.file_exists(cached) and img.load(cached) == OK):
		var abs_path := repo_root.path_join(str(rec["file"]))
		if str(rec["file"]).ends_with(".svg"):
			var scale := float(THUMB_SIZE) / 1024.0
			if img.load_svg_from_string(FileAccess.get_file_as_string(abs_path), scale) != OK:
				return null
		else:
			if img.load(abs_path) != OK:
				return null
			img.resize(THUMB_SIZE, THUMB_SIZE, Image.INTERPOLATE_LANCZOS)
		img.save_png(cached)
	var tex := ImageTexture.create_from_image(img)
	_thumb_textures[gen_id] = tex
	return tex


## Full-size preview with the generation's post steps applied in memory
## (so the detail view can show the actually-transparent result pre-save).
func preview_image(gen_id: String, apply_post := false) -> Image:
	var rec: Dictionary = _index["generations"].get(gen_id, {})
	if rec.is_empty() or rec.get("file") == null:
		return null
	var abs := repo_root.path_join(str(rec["file"]))
	var img := Image.new()
	if str(rec["file"]).ends_with(".svg"):
		var text := FileAccess.get_file_as_string(abs)
		if apply_post and rec.get("post", []).has("strip_bg_rect"):
			var stripped: Dictionary = SvgT.strip_background(text, _background_color(rec))
			if stripped["status"] == SvgT.STATUS_STRIPPED:
				text = stripped["text"]
		if img.load_svg_from_string(text, 0.5) != OK:
			return null
	elif img.load(abs) != OK:
		return null
	return img


# -- Manifest -----------------------------------------------------------------

## Audit promoted assets. For each manifest entry, verify the ref file + its
## baked pool pixels still exist and flag hand-edits (the pool sha drifting
## without modified_after_save). Reports on-disk files no entry accounts for.
## Tolerant of legacy path-keyed entries (key IS the file, no ref_path/pool).
## Returns {"issues": [String]}.
func check_manifest() -> Dictionary:
	var manifest := _load_manifest()
	var issues: Array = []
	var changed := false
	var known := {}  # res_path -> true, the files entries account for
	for key in manifest["assets"]:
		var entry: Dictionary = manifest["assets"][key]
		var ref_path := str(entry.get("ref_path", key))   # legacy: key is the file
		var pool := str(entry.get("pool", ""))             # legacy: no separate pool
		var hashed := pool if not pool.is_empty() else ref_path
		known[ref_path] = true
		if not pool.is_empty():
			known[pool] = true
		if not FileAccess.file_exists(ref_path):
			issues.append("missing ref for manifest entry: " + ref_path)
			continue
		if not FileAccess.file_exists(hashed):
			issues.append("missing baked pixels for ref: " + ref_path + " → " + hashed)
			continue
		if FileAccess.get_sha256(hashed) != str(entry.get("sha256")) \
				and not bool(entry.get("modified_after_save", false)):
			entry["modified_after_save"] = true
			changed = true
			issues.append("hand-edited after save: " + hashed)
	var root := DirAccess.open("res://assets/generated")
	if root != null:
		for sub in root.get_directories():
			var subdir := DirAccess.open("res://assets/generated/" + sub)
			for f in subdir.get_files():
				if f.ends_with(".import") or f.ends_with(".uid"):
					continue
				var res_path := "res://assets/generated/%s/%s" % [sub, f]
				if not known.has(res_path):
					issues.append("no manifest entry (invariant violation): " + res_path)
	if changed:
		_store_manifest(manifest)
	return {"issues": issues}


## Wrap an existing promoted file (legacy direct .svg/.png asset) into a
## GenTexture ref without re-generating: copies its current pixels into the pool
## under its recorded gen_id, writes <category>/<name>.tres beside it, and
## re-keys the manifest by uid. The old file is left in place — flip consumers to
## the .tres, then delete it. Returns the _write_ref result.
func migrate_asset(old_path: String, category: String, asset_name: String) -> Dictionary:
	if not FileAccess.file_exists(old_path):
		return {"ok": false, "error": "no file at " + old_path}
	if not SAVE_CATEGORIES.has(category):
		return {"ok": false, "error": "category must be one of %s" % str(SAVE_CATEGORIES)}
	if not asset_name.is_valid_filename() or asset_name.is_empty():
		return {"ok": false, "error": "invalid asset name '%s'" % asset_name}

	var manifest := _load_manifest()
	var entry: Dictionary = manifest["assets"].get(old_path, {})
	var gen_id := str(entry.get("gen_id", ""))
	var rec: Dictionary = _index["generations"].get(gen_id, {}) if not gen_id.is_empty() else {}
	var ext := old_path.get_extension()

	# The promoted file is already post-applied — copy its bytes straight into
	# the pool (named by gen_id, or by asset name for un-attributed legacy files).
	var pool_id := gen_id if not gen_id.is_empty() else "legacy_" + asset_name
	var pool_path := "%s/%s.%s" % [POOL_DIR, pool_id, ext]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POOL_DIR))
	if not FileAccess.file_exists(pool_path):
		var bytes := FileAccess.get_file_as_bytes(old_path)
		var fa := FileAccess.open(pool_path, FileAccess.WRITE)
		if fa == null:
			return {"ok": false, "error": "cannot write pool file " + pool_path}
		fa.store_buffer(bytes)
		fa.close()
		await _rescan_filesystem()

	var dest := "res://assets/generated/%s/%s.tres" % [category, asset_name]
	var baked := {
		"ok": true, "pool_path": pool_path, "ext": ext,
		"sha": FileAccess.get_sha256(pool_path),
		"post": entry.get("post", rec.get("post", [])),
		"rec": rec if not rec.is_empty() else {
			"prompt": entry.get("prompt", ""),
			"model": str(entry.get("generator", "")).trim_prefix("recraft/"),
			"style_id": entry.get("style_id"),
			"batch_id": entry.get("batch_id", ""),
			"ts": entry.get("generated_at", ""),
		},
	}
	var result := await _write_ref(dest, pool_id, baked)
	if result.get("ok", false):
		LedgerT.append(ledger_path, {
			"type": "migrate", "gen_id": pool_id, "ts": _now_iso(),
			"from": old_path, "dest": dest, "ref_uid": result["uid"], "sha256": baked["sha"],
		})
		reload_history()
	return result


func _load_manifest() -> Dictionary:
	var manifest := {"version": 1, "assets": {}}
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			manifest = parsed
			if not manifest.has("assets"):
				manifest["assets"] = {}
	return manifest


func _store_manifest(manifest: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(MANIFEST_PATH.get_base_dir()))
	var fa := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if fa == null:
		push_error("ArtGen: cannot write %s (err %d)" % [MANIFEST_PATH, FileAccess.get_open_error()])
		return
	fa.store_string(JSON.stringify(manifest, "\t") + "\n")
	fa.close()


# -- Helpers ------------------------------------------------------------------

func status() -> Dictionary:
	return {
		"ok": true,
		"editor": "godot-" + str(Engine.get_version_info()["string"]),
		"api_key_configured": client != null and not client.api_key.is_empty(),
		"balance": balance,
		"generating": generating,
		"config": config,
		"presets": presets.keys(),
		"categories": SAVE_CATEGORIES,
		"history_count": _index["order"].size(),
	}


func _refresh_balance() -> void:
	if client.api_key.is_empty():
		return
	var resp: Dictionary = await client.me()
	if resp.get("ok", false):
		balance = int(resp["data"].get("credits", -1))
		balance_changed.emit(balance)


func _rescan_filesystem() -> void:
	if not Engine.is_editor_hint():
		return
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	while fs.is_scanning():
		await get_tree().process_frame


func _background_color(rec: Dictionary) -> Color:
	var controls: Variant = rec.get("controls")
	if typeof(controls) == TYPE_DICTIONARY and controls.get("background_color") != null:
		var rgb: Array = controls["background_color"].get("rgb", [0, 0, 0])
		return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	return Color.BLACK


func _load_json_into(path: String, target: Dictionary) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		target.merge(parsed, true)
	else:
		push_error("ArtGen: cannot parse " + path)


func _new_gen_id() -> String:
	return _new_id("g")


## One batch_id is stamped per generate() call (all n variation records share
## it), which is what the gallery groups on.
func _new_id(prefix: String) -> String:
	return "%s_%d_%s" % [prefix,
		int(Time.get_unix_time_from_system()),
		Crypto.new().generate_random_bytes(2).hex_encode()]


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _month_bucket() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d" % [d["year"], d["month"]]


static func _looks_like_svg(raw: PackedByteArray) -> bool:
	var head := raw.slice(0, mini(200, raw.size())).get_string_from_utf8().strip_edges()
	return head.begins_with("<?xml") or head.begins_with("<svg")


# Decode a raster payload (PNG / WebP / JPEG, sniffed by magic bytes) and write
# it back out as a genuine PNG. Recraft v4.x returns WebP; if the bytes are
# already PNG this is a lossless re-encode. Returns OK or a decode/write error.
static func _write_raster_as_png(raw: PackedByteArray, abs_path: String) -> int:
	var img := Image.new()
	var err := FAILED
	if raw.size() >= 4 and raw[0] == 0x89 and raw[1] == 0x50 and raw[2] == 0x4E and raw[3] == 0x47:
		err = img.load_png_from_buffer(raw)          # \x89PNG
	elif raw.size() >= 12 and raw[0] == 0x52 and raw[1] == 0x49 and raw[2] == 0x46 and raw[3] == 0x46 \
			and raw[8] == 0x57 and raw[9] == 0x45 and raw[10] == 0x42 and raw[11] == 0x50:
		err = img.load_webp_from_buffer(raw)         # RIFF....WEBP
	elif raw.size() >= 2 and raw[0] == 0xFF and raw[1] == 0xD8:
		err = img.load_jpg_from_buffer(raw)          # JPEG
	else:
		err = img.load_png_from_buffer(raw)          # assume PNG, surface the error if not
	if err != OK:
		return err
	return img.save_png(abs_path)


static func _slugify(text: String) -> String:
	var slug := ""
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif not slug.ends_with("-"):
			slug += "-"
	return slug.trim_suffix("-").left(40)
