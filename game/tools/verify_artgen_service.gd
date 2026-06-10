extends SceneTree

## Headless, offline ArtGen service verifier (no API calls, no editor):
##   godot --headless --path . --script res://tools/verify_artgen_service.gd
## Covers the ledger fold (save/discard/lineage states), history filters,
## lineage walk, and the multipart builder.

const LedgerT := preload("res://addons/artgen/ledger.gd")
const ServiceT := preload("res://addons/artgen/artgen_service.gd")
const MultipartT := preload("res://addons/artgen/multipart.gd")


# Tree-dependent work (add_child → _enter_tree) must run after the tree is
# ready — see the headless-scripts gotcha in CLAUDE.md.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true
	var tmp_ledger := OS.get_cache_dir().path_join("artgen_verify_ledger.jsonl")
	if FileAccess.file_exists(tmp_ledger):
		DirAccess.remove_absolute(tmp_ledger)

	# -- fold ------------------------------------------------------------------
	LedgerT.append(tmp_ledger, {"type": "generation", "id": "g_1", "batch_id": "b_1",
		"ts": "t1", "preset": "icon-flat", "subject": "trophy", "prompt": "p1",
		"status": "ok", "parent_id": null, "file": "art/generated/x/g_1.svg", "post": []})
	LedgerT.append(tmp_ledger, {"type": "generation", "id": "g_2", "batch_id": "b_2",
		"ts": "t2", "preset": "icon-flat", "subject": "gear", "prompt": "p2",
		"status": "ok", "parent_id": "g_1", "file": "art/generated/x/g_2.svg", "post": []})
	LedgerT.append(tmp_ledger, {"type": "generation", "id": "g_3", "batch_id": "b_34",
		"ts": "t3", "preset": "icon-flat", "subject": "twins", "prompt": "p3",
		"status": "ok", "parent_id": null, "file": "art/generated/x/g_3.svg", "post": []})
	LedgerT.append(tmp_ledger, {"type": "generation", "id": "g_4", "batch_id": "b_34",
		"ts": "t3", "preset": "icon-flat", "subject": "twins", "prompt": "p3",
		"status": "ok", "parent_id": null, "file": "art/generated/x/g_4.svg", "post": []})
	LedgerT.append(tmp_ledger, {"type": "save", "gen_id": "g_1", "ts": "t5",
		"dest": "res://assets/generated/icons/trophy.svg", "sha256": "abc"})
	LedgerT.append(tmp_ledger, {"type": "discard", "gen_id": "g_2", "ts": "t6"})
	LedgerT.append(tmp_ledger, {"type": "style_created", "ts": "t5",
		"style_id": "s-1", "style": "vector_illustration", "refs": [], "cost_units": 40})

	var idx: Dictionary = LedgerT.fold(tmp_ledger)
	ok = _check(ok, idx["order"] == ["g_1", "g_2", "g_3", "g_4"], "fold order")
	ok = _check(ok, idx["generations"]["g_1"]["state"] == "saved", "g_1 folds to saved")
	ok = _check(ok, idx["generations"]["g_1"]["dest"] == "res://assets/generated/icons/trophy.svg",
		"g_1 carries dest")
	ok = _check(ok, idx["generations"]["g_2"]["state"] == "discarded", "g_2 folds to discarded")
	ok = _check(ok, idx["generations"]["g_1"]["batch_id"] == "b_1", "batch_id folds through")
	ok = _check(ok, idx["styles"].size() == 1 and idx["styles"][0]["style_id"] == "s-1",
		"style event folds")

	# -- service history/lineage over the same ledger ---------------------------
	var service: Node = ServiceT.new()
	root.add_child(service)
	service.ledger_path = tmp_ledger
	service.reload_history()

	var all: Array = service.get_history()
	ok = _check(ok, all.size() == 4 and all[0]["id"] == "g_4", "history newest-first")
	ok = _check(ok, service.get_history({"state": "saved"}).size() == 1, "state filter")
	ok = _check(ok, service.get_history({"search": "gear"}).size() == 1, "search filter")
	ok = _check(ok, service.get_history({"preset": "icon-flat"}).size() == 4, "preset filter")

	var grouped: Array = service.get_history_grouped()
	ok = _check(ok, grouped.size() == 3, "grouped: batches collapse")
	ok = _check(ok, grouped[0]["batch_id"] == "b_34"
		and grouped[0]["records"].map(func(r: Dictionary) -> String: return str(r["id"]))
			== ["g_3", "g_4"],
		"grouped: newest batch first, records in generation order")
	ok = _check(ok, grouped[1]["records"][0]["id"] == "g_2"
		and grouped[2]["records"][0]["id"] == "g_1", "grouped: singletons keep order")
	ok = _check(ok, service.get_history_grouped({"search": "twins"}).size() == 1,
		"grouped: filters apply before grouping")

	var rec: Dictionary = service.get_generation("g_2")
	ok = _check(ok, rec["lineage"].size() == 1 and rec["lineage"][0]["id"] == "g_1",
		"lineage walks parent_id")

	ok = _check(ok, service.presets.has("icon-flat") and service.presets.has("card-glyph"),
		"presets.json loads")
	ok = _check(ok, str(service.config.get("models", {}).get("vector")) == "recraftv3_vector",
		"config.json pins V3 vector")
	ok = _check(ok, str(service.config.get("models", {}).get("vector_v41")) == "recraftv4_1_vector",
		"config.json pins v4.1 vector kind")
	ok = _check(ok, str(service.config.get("models", {}).get("raster_v41")) == "recraftv4_1",
		"config.json pins v4.1 raster kind")

	var bad: Dictionary = await service.generate({"preset": "nope", "subject": "x"})
	ok = _check(ok, bad["ok"] == false and str(bad["error"]).contains("unknown preset"),
		"unknown preset refused without API call")

	# -- build_payload model-family rules (offline, pure) ------------------------
	# the v3 default path must stay byte-identical to the pre-v4.1 construction
	var p3: Dictionary = service.build_payload({"preset": "icon-flat", "subject": "trophy"})
	ok = _check(ok, p3 == {
		"prompt": str(service.presets["icon-flat"]["prompt"]).replace("{subject}", "trophy"),
		"model": "recraftv3_vector", "n": 1, "size": "1024x1024",
		"response_format": "b64_json",
		"style_id": "19f7542f-0727-4f6f-9d07-728c439fc583",
		"controls": service.presets["icon-flat"]["controls"],
	}, "v3 default payload unchanged")
	var p3n: Dictionary = service.build_payload(
		{"preset": "icon-flat", "subject": "trophy", "negative_prompt": "blurry"})
	ok = _check(ok, p3n.get("negative_prompt") == "blurry", "v3 keeps negative_prompt")

	# overrides: prompt substitutes {subject}; controls beats the preset's
	var po: Dictionary = service.build_payload(
		{"preset": "icon-flat", "subject": "orb", "prompt": "make a {subject} now"})
	ok = _check(ok, po["prompt"] == "make a orb now", "override prompt substitutes subject")
	var co: Dictionary = service.build_payload({"preset": "icon-flat", "subject": "orb",
		"controls": {"background_color": {"rgb": [10, 20, 30]}}})
	ok = _check(ok, co["controls"] == {"background_color": {"rgb": [10, 20, 30]}},
		"controls override beats preset controls")

	# v4.1: inherited style + negative_prompt stripped, controls kept, WxH dropped (vector)
	var p4: Dictionary = service.build_payload({"preset": "card-glyph",
		"subject": "the tower", "model": "vector_v41", "negative_prompt": "blurry"})
	ok = _check(ok, p4["model"] == "recraftv4_1_vector", "v4.1 vector kind resolves")
	ok = _check(ok, not p4.has("style_id"), "v4.1 strips preset-inherited style_id")
	ok = _check(ok, not p4.has("negative_prompt"), "v4.1 drops negative_prompt")
	ok = _check(ok, p4["controls"] == service.presets["card-glyph"]["controls"],
		"v4.1 keeps controls")
	ok = _check(ok, not p4.has("size"), "v4.1 vector omits WxH size")

	var p4e: Dictionary = service.build_payload({"preset": "icon-flat", "subject": "x",
		"model": "raster_v41", "style_id": "89aedef2-2411-42fc-aa8b-aec391b51bc7"})
	ok = _check(ok, p4e.get("ok") == false and str(p4e.get("error")).contains("v2/v3-only"),
		"explicit style on v4.1 refused pre-flight")

	var p4r: Dictionary = service.build_payload(
		{"preset": "icon-raster", "subject": "x", "model": "raster_v41"})
	ok = _check(ok, p4r["model"] == "recraftv4_1" and p4r.get("size") == "1024x1024",
		"v4.1 raster keeps WxH size")

	var p4u: Dictionary = service.build_payload(
		{"preset": "card-glyph", "subject": "x", "model": "recraftv4_1_utility"})
	ok = _check(ok, p4u["model"] == "recraftv4_1_utility" and not p4u.has("style_id"),
		"identity fallback gets v4-family caps")

	# -- multipart ---------------------------------------------------------------
	var mp: Dictionary = MultipartT.build(
		{"style": "vector_illustration"},
		[{"name": "file1", "filename": "a.png", "content_type": "image/png",
			"bytes": PackedByteArray([1, 2, 3])}])
	var body_text: String = (mp["body"] as PackedByteArray).get_string_from_utf8()
	var boundary: String = str(mp["content_type"]).get_slice("boundary=", 1)
	ok = _check(ok, body_text.contains("name=\"style\"") and body_text.contains("vector_illustration"),
		"multipart field encoded")
	ok = _check(ok, body_text.contains("filename=\"a.png\""), "multipart file encoded")
	ok = _check(ok, body_text.contains("--%s--" % boundary), "multipart terminator")

	print("VERIFY artgen_service: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _check(ok: bool, condition: bool, what: String) -> bool:
	if not condition:
		print("FAIL " + what)
	return ok and condition
