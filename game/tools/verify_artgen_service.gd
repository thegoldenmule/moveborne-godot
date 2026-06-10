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
	LedgerT.append(tmp_ledger, {"type": "generation", "id": "g_1", "ts": "t1",
		"preset": "icon-flat", "subject": "trophy", "prompt": "p1", "status": "ok",
		"parent_id": null, "file": "art/generated/x/g_1.svg", "post": []})
	LedgerT.append(tmp_ledger, {"type": "generation", "id": "g_2", "ts": "t2",
		"preset": "icon-flat", "subject": "gear", "prompt": "p2", "status": "ok",
		"parent_id": "g_1", "file": "art/generated/x/g_2.svg", "post": []})
	LedgerT.append(tmp_ledger, {"type": "save", "gen_id": "g_1", "ts": "t3",
		"dest": "res://assets/generated/icons/trophy.svg", "sha256": "abc"})
	LedgerT.append(tmp_ledger, {"type": "discard", "gen_id": "g_2", "ts": "t4"})
	LedgerT.append(tmp_ledger, {"type": "style_created", "ts": "t5",
		"style_id": "s-1", "style": "vector_illustration", "refs": [], "cost_units": 40})

	var idx: Dictionary = LedgerT.fold(tmp_ledger)
	ok = _check(ok, idx["order"] == ["g_1", "g_2"], "fold order")
	ok = _check(ok, idx["generations"]["g_1"]["state"] == "saved", "g_1 folds to saved")
	ok = _check(ok, idx["generations"]["g_1"]["dest"] == "res://assets/generated/icons/trophy.svg",
		"g_1 carries dest")
	ok = _check(ok, idx["generations"]["g_2"]["state"] == "discarded", "g_2 folds to discarded")
	ok = _check(ok, idx["styles"].size() == 1 and idx["styles"][0]["style_id"] == "s-1",
		"style event folds")

	# -- service history/lineage over the same ledger ---------------------------
	var service: Node = ServiceT.new()
	root.add_child(service)
	service.ledger_path = tmp_ledger
	service.reload_history()

	var all: Array = service.get_history()
	ok = _check(ok, all.size() == 2 and all[0]["id"] == "g_2", "history newest-first")
	ok = _check(ok, service.get_history({"state": "saved"}).size() == 1, "state filter")
	ok = _check(ok, service.get_history({"search": "gear"}).size() == 1, "search filter")
	ok = _check(ok, service.get_history({"preset": "icon-flat"}).size() == 2, "preset filter")

	var rec: Dictionary = service.get_generation("g_2")
	ok = _check(ok, rec["lineage"].size() == 1 and rec["lineage"][0]["id"] == "g_1",
		"lineage walks parent_id")

	ok = _check(ok, service.presets.has("icon-flat") and service.presets.has("card-glyph"),
		"presets.json loads")
	ok = _check(ok, str(service.config.get("models", {}).get("vector")) == "recraftv3_vector",
		"config.json pins V3 vector")

	var bad: Dictionary = await service.generate({"preset": "nope", "subject": "x"})
	ok = _check(ok, bad["ok"] == false and str(bad["error"]).contains("unknown preset"),
		"unknown preset refused without API call")

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
