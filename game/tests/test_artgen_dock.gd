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
	var multi_total := 0
	var multi_blocks := 0
	for i in grouped.size():
		var n: int = grouped[i]["records"].size()
		var row: HFlowContainer = dock._gallery_list.get_child(i).get_child(1)
		assert_eq(row.get_child_count(), n, "block thumbnail count matches batch")
		if n > 1:
			multi_total += 1
			var head: Label = dock._gallery_list.get_child(i).get_child(0)
			if head.text.contains("×%d" % n):
				multi_blocks += 1
	assert_true(multi_total > 0, "real ledger has multi-variation batches")
	assert_eq(multi_blocks, multi_total, "multi-batch headers show the count")
