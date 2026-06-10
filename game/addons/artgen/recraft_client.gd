@tool
class_name ArtgenRecraftClient
extends Node

## Recraft REST client. One in-tree HTTPRequest per call, strict serial queue
## (well under Recraft's 5 req/s), 120 s timeout to ride out 10–60 s generations.
## All methods are coroutines returning {"ok": bool, "code": int, "data": Variant}
## plus "error": String when not ok. Must be in the scene tree before calling.

const MultipartT := preload("res://addons/artgen/multipart.gd")

const BASE_URL := "https://external.api.recraft.ai"
const TIMEOUT_S := 120.0

var api_key := ""

var _busy := false

signal _released


func me() -> Dictionary:
	return await _call_json(HTTPClient.METHOD_GET, "/v1/users/me")


func list_styles() -> Dictionary:
	return await _call_json(HTTPClient.METHOD_GET, "/v1/styles")


## payload: the raw /v1/images/generations request body (prompt, model, style_id…).
func generate(payload: Dictionary) -> Dictionary:
	return await _call_json(HTTPClient.METHOD_POST, "/v1/images/generations", payload)


## base_style: any|realistic_image|digital_illustration|vector_illustration|icon.
## file_paths: ≤5 PNG/JPG/WEBP reference images, ≤5 MB total (Recraft limits).
func create_style(base_style: String, file_paths: Array) -> Dictionary:
	var files: Array = []
	for i in file_paths.size():
		var path: String = file_paths[i]
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return {"ok": false, "code": 0, "error": "unreadable style ref: " + path}
		files.append({
			"name": "file%d" % (i + 1), "filename": path.get_file(),
			"content_type": "image/png", "bytes": bytes,
		})
	var mp: Dictionary = MultipartT.build({"style": base_style}, files)
	return await _call_multipart(HTTPClient.METHOD_POST, "/v1/styles", mp)


func remove_background(image_bytes: PackedByteArray, filename := "image.png") -> Dictionary:
	var mp: Dictionary = MultipartT.build(
		{"response_format": "b64_json"},
		[{"name": "file", "filename": filename, "content_type": "image/png", "bytes": image_bytes}])
	return await _call_multipart(HTTPClient.METHOD_POST, "/v1/images/removeBackground", mp)


func _call_json(method: int, path: String, payload: Variant = null) -> Dictionary:
	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
	])
	var body := "" if payload == null else JSON.stringify(_canonical_numbers(payload))
	return await _execute(path, headers, method, body.to_utf8_buffer())


## JSON.parse_string yields floats for every number and JSON.stringify re-emits
## them as "x.0", which Recraft's Go unmarshaller rejects for int fields (e.g.
## controls colors). Integral floats become ints — always safe, since Go happily
## reads an int into a float field.
static func _canonical_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if value == floorf(value) else value
		TYPE_DICTIONARY:
			var dict := {}
			for key in value:
				dict[key] = _canonical_numbers(value[key])
			return dict
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(_canonical_numbers(item))
			return arr
		_:
			return value


func _call_multipart(method: int, path: String, mp: Dictionary) -> Dictionary:
	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: " + str(mp["content_type"]),
	])
	return await _execute(path, headers, method, mp["body"])


func _execute(
		path: String, headers: PackedStringArray, method: int,
		body: PackedByteArray) -> Dictionary:
	if api_key.is_empty():
		return {"ok": false, "code": 0,
			"error": "no Recraft API key configured (settings, or RECRAFT_API_KEY / repo .env)"}
	while _busy:
		await _released
	_busy = true

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.use_threads = true
	add_child(http)

	var out: Dictionary
	var err := http.request_raw(BASE_URL + path, headers, method, body)
	if err != OK:
		out = {"ok": false, "code": 0, "error": "request failed to start (err %d)" % err}
	else:
		var resp: Array = await http.request_completed
		var result: int = resp[0]
		var code: int = resp[1]
		var text := (resp[3] as PackedByteArray).get_string_from_utf8()
		# error bodies are sometimes plain text — don't let JSON.parse_string spam the log
		var trimmed := text.strip_edges()
		var data: Variant = JSON.parse_string(text) \
				if trimmed.begins_with("{") or trimmed.begins_with("[") else null
		if result != HTTPRequest.RESULT_SUCCESS:
			out = {"ok": false, "code": code, "error": "transport error %d (timeout/dns/tls)" % result}
		elif code < 200 or code >= 300:
			var msg := text.left(300) if data == null else str(data)
			out = {"ok": false, "code": code, "error": msg, "data": data}
		else:
			out = {"ok": true, "code": code, "data": data}

	http.queue_free()
	_busy = false
	_released.emit()
	return out
