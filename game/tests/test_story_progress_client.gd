@tool
extends McpTestSuite

## MbStoryProgressClient pure helpers: the owner-scoped Storage blob URL, blob
## parsing with garbage tolerance, and the empty-progress default an unplayed
## account renders from. The client is strictly READ-ONLY — merge/watermark
## semantics live in the validator (story/progress.ts) and are covered by its
## bun tests; the client-side unlock math is covered in test_story_catalog.

const ProgressClient := preload("res://net/story_progress_client.gd")
const AuthS := preload("res://net/snapser_auth.gd")


func suite_name() -> String:
	return "story_progress_client"


func test_blob_url_is_owner_scoped() -> void:
	assert_eq(ProgressClient.blob_url("user-123"),
		AuthS.GATEWAY + "/v1/storage/owner/user-123/protected/json-blobs/story_progress",
		"GET targets the session user's protected story_progress blob")
	assert_true(ProgressClient.blob_url("a b").contains("/owner/a%20b/"),
		"owner id is uri-encoded")


func test_parse_blob() -> void:
	var blob := {
		"value": {
			"catalog_version": 1,
			"levels": {"w1_l1": {"stars": 2.0, "best_score": 700, "rewarded_stars": 2}},
			"next_level_id": "w1_l2",
		},
		"cas": "7",
	}
	var progress := ProgressClient.parse_blob(blob)
	assert_eq(str(progress.get("next_level_id", "")), "w1_l2", "value object extracted")
	assert_eq(int((progress.get("levels", {}) as Dictionary).get("w1_l1", {}).get("stars", 0)), 2,
		"levels map survives (JSON float stars tolerated downstream)")


func test_parse_blob_garbage() -> void:
	assert_eq(ProgressClient.parse_blob(null), {}, "non-dict payload -> empty")
	assert_eq(ProgressClient.parse_blob({"value": "nope"}), {}, "non-dict value -> empty")
	assert_eq(ProgressClient.parse_blob({}), {}, "missing value -> empty")


func test_empty_progress_shape() -> void:
	var empty := ProgressClient.empty_progress()
	assert_eq(empty.get("levels", null), {}, "no per-level entries")
	assert_eq(str(empty.get("next_level_id", "x")), "", "frontier resolves client-side from the catalog")
