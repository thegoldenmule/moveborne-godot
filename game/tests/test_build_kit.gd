@tool
extends McpTestSuite

## Build Kit dock + service against the LIVE editor plugin: enables the plugin
## (idempotent), then asserts the dock/service wiring and that the preflight
## checklist populates with the expected rows. Machine-dependent statuses are
## not asserted beyond "Xcode present" (this repo's builds are host-local by
## design — there is no CI).


func suite_name() -> String:
	return "build_kit"


func _find_dock() -> Control:
	for hit in EditorInterface.get_base_control().find_children("BuildKitDock", "Control", true, false):
		if "service" in hit:
			return hit
	return null


func test_dock_service_and_preflight() -> void:
	EditorInterface.set_plugin_enabled("build_kit", false)
	EditorInterface.set_plugin_enabled("build_kit", true)
	var dock := _find_dock()
	assert_true(dock != null, "Build Kit dock present after enable")
	if dock == null:
		return
	var service: Node = dock.service
	assert_true(service != null, "service injected into dock")
	if service == null:
		return

	service.refresh_preflight()
	var ids: Array = []
	var by_id := {}
	for row in service.preflight_rows:
		ids.append(row["id"])
		by_id[row["id"]] = row
	for want in ["xcode", "templates", "preset", "account", "asc_key", "app_record", "devices"]:
		assert_true(ids.has(want), "preflight row present: " + want)
	assert_true(by_id.get("xcode", {}).get("status", "") == "ok", "Xcode detected on this host")

	var preset: Dictionary = service.load_ios_preset()
	assert_true(not preset.is_empty(), "iOS preset parsed")
	assert_true(preset.get("bundle_id", "") == "com.thegoldenmule.moveborne", "bundle id read from preset")
	assert_true(not service.is_busy(), "pipeline idle")
