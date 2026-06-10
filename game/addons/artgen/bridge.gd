@tool
class_name ArtgenBridge
extends Node

## Localhost-only HTTP bridge (TCPServer, default :4848, env ARTGEN_BRIDGE_PORT)
## exposing the ArtGen service to the stdio MCP shim (tools/artgen_mcp.ts).
## Routes map 1:1 to the MCP tools. Connections stay open through 10–60 s
## generations: each request dispatches a coroutine that writes its response
## whenever the awaited service work finishes. The Recraft API key never
## transits the bridge.

var service: Node
var port := 4848

var _server := TCPServer.new()
var _conns: Array = []


func _ready() -> void:
	var env_port := OS.get_environment("ARTGEN_BRIDGE_PORT")
	if not env_port.is_empty():
		port = env_port.to_int()
	elif service != null and service.config.has("bridge_port"):
		port = int(service.config["bridge_port"])
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_error("ArtGen bridge: cannot listen on 127.0.0.1:%d (err %d)" % [port, err])
	else:
		print("ArtGen bridge listening on 127.0.0.1:%d" % port)


func _exit_tree() -> void:
	_server.stop()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_conns.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "dispatched": false})
	for conn in _conns.duplicate():
		var peer: StreamPeerTCP = conn["peer"]
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_conns.erase(conn)
			continue
		if conn["dispatched"]:
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			if chunk[0] == OK:
				conn["buf"].append_array(chunk[1])
		if _request_complete(conn["buf"]):
			conn["dispatched"] = true
			_handle(conn)


func _request_complete(buf: PackedByteArray) -> bool:
	var text := buf.get_string_from_utf8()
	var header_end := text.find("\r\n\r\n")
	if header_end < 0:
		return false
	var content_length := 0
	for line in text.left(header_end).split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = line.get_slice(":", 1).strip_edges().to_int()
	return buf.size() >= header_end + 4 + content_length


func _handle(conn: Dictionary) -> void:
	var text: String = conn["buf"].get_string_from_utf8()
	var header_end := text.find("\r\n\r\n")
	var request_line := text.get_slice("\r\n", 0)
	var method := request_line.get_slice(" ", 0)
	var target := request_line.get_slice(" ", 1)
	var path := target.get_slice("?", 0)
	var query := _parse_query(target.get_slice("?", 1) if target.contains("?") else "")
	var body: Variant = JSON.parse_string(text.substr(header_end + 4))
	if typeof(body) != TYPE_DICTIONARY:
		body = {}

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
		["POST", "/style/create"]:
			result = await service.create_style(
				str(body.get("style", "vector_illustration")), body.get("refs", []))
			if not result.get("ok", false):
				code = 400
		_:
			code = 404
			result = {"ok": false, "error": "no route %s %s" % [method, path]}

	_respond(conn, code, result)


func _respond(conn: Dictionary, code: int, payload: Dictionary) -> void:
	var peer: StreamPeerTCP = conn["peer"]
	peer.poll()
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var body := JSON.stringify(payload).to_utf8_buffer()
		var head := ("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\n"
			+ "Content-Length: %d\r\nConnection: close\r\n\r\n") % [
				code, "OK" if code == 200 else "Error", body.size()]
		peer.put_data(head.to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()
	_conns.erase(conn)


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


func _parse_query(query_string: String) -> Dictionary:
	var out := {}
	for pair in query_string.split("&"):
		if pair.contains("="):
			out[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode()
	return out
