@tool
extends McpTestSuite

## MbRemoteConfigClient pure helpers: app-config URL against the Remote Config
## swagger, response parsing with garbage tolerance, and the remote-vs-baked
## catalog selection rule (a stale or malformed remote payload can never
## downgrade a shipped client). No network.

const RcClient := preload("res://net/remote_config_client.gd")
const Catalog := preload("res://story/story_catalog.gd")
const AuthS := preload("res://net/snapser_auth.gd")


func suite_name() -> String:
	return "remote_config_client"


func _tiny_catalog(version: int) -> Dictionary:
	return {
		"catalog_version": version,
		"worlds": [{"id": "w1", "name": "W", "order": 0, "levels": [{
			"id": "w1_l1", "order": 0, "scenario_id": 0, "name": "L",
			"goals": [
				{"type": "points", "threshold": 100, "time_limit_s": null},
				{"type": "points", "threshold": 200, "time_limit_s": null},
				{"type": "max_tile", "threshold": 64, "time_limit_s": 60},
			],
			"rewards": {"complete": {"coins": 1}, "per_star": [{"coins": 1}, {"coins": 1}, {"coins": 1}]},
		}]}],
	}


func test_app_config_url() -> void:
	assert_eq(RcClient.app_config_url(),
		AuthS.GATEWAY + "/v1/remote-config/app-config/v1",
		"GET app-config URL matches the swagger path with the default version")
	assert_eq(RcClient.app_config_url("v2"),
		AuthS.GATEWAY + "/v1/remote-config/app-config/v2", "explicit version respected")


func test_parse_app_config() -> void:
	assert_eq(RcClient.parse_app_config({"config": {"story_catalog": {"catalog_version": 3}}}),
		{"story_catalog": {"catalog_version": 3}}, "config object extracted")
	assert_eq(RcClient.parse_app_config(null), {}, "non-dict payload -> empty")
	assert_eq(RcClient.parse_app_config({"config": "nope"}), {}, "non-dict config -> empty")


func test_extract_catalog() -> void:
	var config := {"story_catalog": _tiny_catalog(2), "other_feature": {"x": 1}}
	assert_eq(int(RcClient.extract_catalog(config).get("catalog_version", 0)), 2,
		"the story catalog rides under its own app-config key")
	assert_eq(RcClient.extract_catalog({}), {}, "absent key -> empty")


func test_extract_daily_missions() -> void:
	# daily_missions rides alongside story_catalog in the SAME app-config doc; one
	# never disturbs the other.
	var config := {"story_catalog": _tiny_catalog(2), "daily_missions": {"enabled": true, "anchor": "a"}}
	assert_eq(RcClient.extract_daily_missions(config), {"enabled": true, "anchor": "a"},
		"daily_missions extracted from the shared app-config doc")
	assert_eq(int(RcClient.extract_catalog(config).get("catalog_version", 0)), 2,
		"story catalog still extracts alongside daily_missions")
	assert_eq(RcClient.extract_daily_missions({}), {}, "absent key -> empty")
	assert_eq(RcClient.extract_daily_missions({"daily_missions": "nope"}), {}, "non-dict block -> empty")


func test_select_catalog_prefers_valid_newer_remote() -> void:
	var baked := _tiny_catalog(1)
	var remote := _tiny_catalog(2)
	assert_eq(RcClient.select_catalog(remote, baked), remote,
		"a valid remote catalog at least as new as the baked one wins")
	assert_eq(RcClient.select_catalog(_tiny_catalog(1), baked), _tiny_catalog(1),
		"equal versions: remote still wins (live tuning)")


func test_select_catalog_falls_back_to_baked() -> void:
	var baked := _tiny_catalog(3)
	assert_eq(RcClient.select_catalog({}, baked), baked, "empty remote -> baked")
	assert_eq(RcClient.select_catalog(_tiny_catalog(2), baked), baked,
		"older remote can never downgrade the shipped catalog")
	var malformed := _tiny_catalog(9)
	malformed["worlds"][0]["levels"][0]["goals"] = []  # structurally invalid
	assert_eq(RcClient.select_catalog(malformed, baked), baked,
		"a malformed remote payload -> baked")
