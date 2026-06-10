@tool
extends McpTestSuite

## ArtGen dock + service v4.1 wiring, against the LIVE editor plugin:
## toggles the plugin off/on so the dock, service, and config.json are
## rebuilt from current disk state, then asserts the config-driven model
## dropdown, the v4.x "custom styles ignored" note, and the service's
## model-family payload rules.


func suite_name() -> String:
	return "artgen_dock"


func _find_dock() -> Control:
	for hit in EditorInterface.get_base_control().find_children("ArtGen", "Control", true, false):
		if "service" in hit:
			return hit
	return null


func test_v41_dock_and_service() -> void:
	EditorInterface.set_plugin_enabled("artgen", false)
	EditorInterface.set_plugin_enabled("artgen", true)
	var dock := _find_dock()
	assert_true(dock != null, "ArtGen dock present after plugin reload")
	if dock == null:
		return
	var service: Node = dock.service

	# config-driven model dropdown: "preset" first, then config.json map order
	var items: Array = []
	for i in dock._model_option.item_count:
		items.append(dock._model_option.get_item_text(i))
	assert_eq(items, ["preset", "vector", "raster", "vector_v41", "raster_v41"],
		"model dropdown mirrors config.json kinds")

	# v4.x kinds surface the style-loss note; v3 kinds don't
	dock._model_option.selected = items.find("vector_v41")
	dock._update_model_note()
	assert_true(dock._model_note.visible, "v4.1 kind shows note")
	assert_contains(dock._model_note.text, "custom styles ignored")
	dock._model_option.selected = items.find("vector")
	dock._update_model_note()
	assert_false(dock._model_note.visible, "v3 kind hides note")
	dock._model_option.selected = 0
	dock._update_model_note()

	# the fresh service picked the new kinds up from config.json
	assert_eq(str(service.config["models"]["vector_v41"]), "recraftv4_1_vector")
	assert_eq(str(service.config["models"]["raster_v41"]), "recraftv4_1")

	# family rules hold on the live service instance
	var p4: Dictionary = service.build_payload(
		{"preset": "card-glyph", "subject": "tower", "model": "vector_v41"})
	assert_eq(str(p4.get("model")), "recraftv4_1_vector")
	assert_false(p4.has("style_id"), "inherited style stripped on v4.1")
	assert_false(p4.has("size"), "WxH size omitted for v4.1 vector")
	var p3: Dictionary = service.build_payload({"preset": "icon-flat", "subject": "tower"})
	assert_eq(str(p3.get("model")), "recraftv3_vector")
	assert_eq(str(p3.get("style_id")), "19f7542f-0727-4f6f-9d07-728c439fc583")

	# gallery renders one block per variation group (real ledger: groups are
	# stable history — batches can be appended but never removed)
	var grouped: Array = service.get_history_grouped({})
	assert_eq(dock._gallery_list.get_child_count(), grouped.size(),
		"one gallery block per batch")
	# Load fills every compose field from the preset; preview tracks subject
	var icon_flat: Dictionary = service.presets["icon-flat"]
	dock._preset_option.selected = 0  # icon-flat (presets.json order)
	dock._on_load_preset()
	assert_eq(dock._prompt_override.text, str(icon_flat["prompt"]), "load fills prompt template")
	assert_eq(dock._model_option.get_item_text(dock._model_option.selected), "vector",
		"load selects the preset's model kind")
	assert_eq(dock._style_id_edit.text, "19f7542f-0727-4f6f-9d07-728c439fc583",
		"load resolves the config default style")
	assert_eq(dock._size_edit.text, "1024x1024", "load fills size")
	assert_eq(JSON.parse_string(dock._controls_edit.text), icon_flat["controls"],
		"load fills controls JSON")
	assert_eq(dock._post_edit.text, "strip_bg_rect", "load fills post steps")
	dock._subject_edit.text = "crystal ball"
	dock._update_prompt_preview()
	assert_eq(dock._prompt_preview.text,
		str(icon_flat["prompt"]).replace("{subject}", "crystal ball"),
		"live preview substitutes the subject")
	dock._prompt_override.text = "custom {subject} prompt"
	dock._update_prompt_preview()
	assert_eq(dock._prompt_preview.text, "custom crystal ball prompt",
		"preview follows an edited prompt template")
	dock._prompt_override.text = ""
	dock._subject_edit.text = ""
	dock._update_prompt_preview()

	var bad_headers := 0
	for i in grouped.size():
		var first: Dictionary = grouped[i]["records"][0]
		var row: HFlowContainer = dock._gallery_list.get_child(i).get_child(1)
		assert_eq(row.get_child_count(), grouped[i]["records"].size(),
			"block thumbnail count matches batch")
		var head: Label = dock._gallery_list.get_child(i).get_child(0)
		if head.text != "[%s] \"%s\"" % [first.get("preset"), str(first.get("subject", ""))]:
			bad_headers += 1
	assert_eq(bad_headers, 0, "headers are [preset] \"title\"")
