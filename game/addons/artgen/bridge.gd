@tool
class_name ArtgenBridge
extends "res://addons/editor_tool_kit/bridge_server.gd"

## ArtGen's localhost HTTP bridge (default :4848, env ARTGEN_BRIDGE_PORT, then
## config.bridge_port). Routes map 1:1 to the artgen MCP shim's tools
## (tools/artgen_mcp.ts). The TCPServer poll loop, Content-Length framing, async
## dispatch, responses, and headless skip live in the BridgeServer base; this
## subclass supplies only the port resolution + the [method, path] route table.
## The Recraft API key never transits the bridge.


## Port order: env override → service config → :4848 default.
func _resolve_port() -> int:
	var env_port := OS.get_environment("ARTGEN_BRIDGE_PORT")
	if not env_port.is_empty():
		return env_port.to_int()
	if service != null and service.config.has("bridge_port"):
		return int(service.config["bridge_port"])
	return 4848


func _route(method: String, path: String, query: Dictionary, body: Dictionary) -> Dictionary:
	var code := 200
	var result: Dictionary
	match [method, path]:
		["GET", "/status"]:
			result = service.status()
		["GET", "/history"]:
			var records: Array = service.get_history(query)
			var limit := clampi(int(str(query.get("limit", "50"))), 1, 1000)
			result = {"ok": true, "generations": _abs_files(records.slice(0, limit))}
		["GET", "/get"]:
			var rec: Dictionary = service.get_generation(str(query.get("id", "")))
			if rec.is_empty():
				code = 404
				result = {"ok": false, "error": "unknown generation '%s'" % query.get("id", "")}
			else:
				result = {"ok": true, "generation": _abs_files([rec])[0]}
		["POST", "/generate"]:
			result = await service.generate(body)
			if result.get("ok", false):
				result["generations"] = _abs_files(result["generations"])
			else:
				code = 400
		["POST", "/save"]:
			result = await service.save_generation(
				str(body.get("id", "")), str(body.get("category", "")), str(body.get("name", "")))
			if not result.get("ok", false):
				code = 400
		["POST", "/discard"]:
			result = service.discard_generation(str(body.get("id", "")))
			if not result.get("ok", false):
				code = 404
		["POST", "/swap"]:
			result = await service.swap_permutation(
				str(body.get("ref", "")), str(body.get("id", "")), bool(body.get("raw", false)))
			if not result.get("ok", false):
				code = 400
		["POST", "/migrate"]:
			result = await service.migrate_asset(
				str(body.get("from", "")), str(body.get("category", "")), str(body.get("name", "")))
			if not result.get("ok", false):
				code = 400
		["POST", "/style/create"]:
			result = await service.create_style(
				str(body.get("style", "vector_illustration")), body.get("refs", []))
			if not result.get("ok", false):
				code = 400
		_:
			code = 404
			result = {"ok": false, "error": "no route %s %s" % [method, path]}
	return {"code": code, "payload": result}


## The MCP caller (Claude) reads generated files straight off disk —
## translate the ledger's repo-relative paths to absolute ones.
func _abs_files(records: Array) -> Array:
	var out: Array = []
	for rec in records:
		var dup: Dictionary = rec.duplicate()
		if dup.get("file") != null:
			dup["abs_path"] = service.repo_root.path_join(str(dup["file"]))
		out.append(dup)
	return out
