class_name MbValidatorClient
extends Node

## Minimal Engine.IO v4 / Socket.IO v5 client over WebSocketPeer, just enough to
## talk to the Moveborne validator: HTTP POST /api/match/init, then a Socket.IO
## connection (auth = {connection_id, player_id}), the 'ready' event, and
## 'validate_action' emits with ack callbacks.
##
## Works against the local dev validator (base_url http://localhost:5555) and the
## Snapser-deployed BYOSnap (base_url = gateway + snap prefix, e.g.
## https://gateway.snapser.com/c4n1awfs/v1/byosnap-validator) — the validator
## mounts both its HTTP routes and the Socket.IO engine under BYOSNAP_BASE_PATH,
## so every path is just base_url + suffix. The optional `headers` are sent on
## the init POST and the WebSocket upgrade (the gateway requires Token/User-Id).
##
## Engine.IO packet = first char of each WS text frame: 0 open, 1 close, 2 ping,
## 3 pong, 4 message, 6 noop. Socket.IO packet (inside a '4' message) = next char:
## 0 CONNECT, 1 DISCONNECT, 2 EVENT, 3 ACK, 4 CONNECT_ERROR.

signal ready_received(current_state: Dictionary)
signal action_validated(index: int, matched: bool, corrected_state)   # matched=true => keep optimistic; else corrected_state is the authoritative state
signal validator_error(message: String)
signal connected()

var _base_url: String
var _match_id: String
var _player_id: String
var _headers := PackedStringArray()   # extra headers (gateway auth), HTTP + WS handshake
var _ws := WebSocketPeer.new()
var _polling := false
var _sio_connected := false
var _ack_id := 0
var _pending: Dictionary = {}   # ack_id -> {index:int}


func init_and_connect(base_url: String, match_id: String, starting_state: Dictionary, player_id: String, headers: PackedStringArray = PackedStringArray()) -> void:
	_base_url = base_url
	_match_id = match_id
	_player_id = player_id
	_headers = headers
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_init_done.bind(http))
	# Auth is the gateway-validated User-Id header (== player_id); no signature.
	var body := JSON.stringify({
		"match_id": match_id, "starting_state": starting_state,
		"player_id": player_id,
	})
	var req_headers := PackedStringArray(["Content-Type: application/json"])
	req_headers.append_array(headers)
	var err := http.request(base_url + "/api/match/init", req_headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		validator_error.emit("HTTPRequest failed to start: %d" % err)


func _on_init_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var text := body.get_string_from_utf8()
	var resp = JSON.parse_string(text)
	if code != 200 or typeof(resp) != TYPE_DICTIONARY or not resp.has("connection_id"):
		validator_error.emit("init failed (HTTP %d): %s" % [code, text])
		return
	_connect_socket(str(resp["connection_id"]))


func _connect_socket(connection_id: String) -> void:
	var ws_url := _base_url.replace("https://", "wss://").replace("http://", "ws://") + "/socket.io/?EIO=4&transport=websocket"
	_ws.handshake_headers = _headers
	var err := _ws.connect_to_url(ws_url)
	if err != OK:
		validator_error.emit("WS connect failed: %d" % err)
		return
	_auth = {"connection_id": connection_id, "player_id": _player_id}
	_polling = true
	set_process(true)


var _auth: Dictionary = {}


func _process(_delta: float) -> void:
	if not _polling:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				_handle_eio(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_polling = false
			set_process(false)
			validator_error.emit("WS closed: %d %s" % [_ws.get_close_code(), _ws.get_close_reason()])


## Emit a 'validate_action' with an ack; on response fires action_validated(index, matched, state).
func validate_action(index: int, action: Dictionary, state_hash: String) -> void:
	var aid := _ack_id
	_ack_id += 1
	_pending[aid] = {"index": index}
	_send("42%d%s" % [aid, JSON.stringify([
		"validate_action", {"index": index, "action": action, "state_hash": state_hash},
	])])


func _handle_eio(pkt: String) -> void:
	if pkt.is_empty():
		return
	match pkt[0]:
		"0":  # open -> send Socket.IO CONNECT with auth
			_send("40" + JSON.stringify(_auth))
		"2":  # ping -> pong
			_send("3")
		"4":  # message (Socket.IO packet follows)
			_handle_sio(pkt.substr(1))


func _handle_sio(s: String) -> void:
	if s.is_empty():
		return
	match s[0]:
		"0":  # CONNECT ack
			_sio_connected = true
			connected.emit()
		"2":  # EVENT
			_handle_event(s.substr(1))
		"3":  # ACK
			_handle_ack(s.substr(1))
		"4":  # CONNECT_ERROR
			validator_error.emit("CONNECT_ERROR: " + s.substr(1))


func _split_ack_id(s: String) -> Array:
	var i := 0
	while i < s.length() and s[i] >= "0" and s[i] <= "9":
		i += 1
	var aid := -1 if i == 0 else int(s.substr(0, i))
	return [aid, s.substr(i)]


func _handle_event(s: String) -> void:
	var parts := _split_ack_id(s)
	var arr = JSON.parse_string(parts[1])
	if not (arr is Array) or arr.is_empty():
		return
	var ev := str(arr[0])
	var data = arr[1] if arr.size() > 1 else null
	if ev == "ready" and data is Dictionary:
		ready_received.emit(data.get("current_state", {}))
	elif ev == "error":
		validator_error.emit("server error: " + JSON.stringify(data))


func _handle_ack(s: String) -> void:
	var parts := _split_ack_id(s)
	var aid: int = parts[0]
	var arr = JSON.parse_string(parts[1])
	var resp = arr[0] if (arr is Array and not arr.is_empty()) else null
	if not _pending.has(aid):
		return
	var index: int = int(_pending[aid]["index"])
	_pending.erase(aid)
	if typeof(resp) != TYPE_DICTIONARY:
		validator_error.emit("bad ack")
		return
	if resp.has("error"):
		validator_error.emit("validate_action %s: %s" % [str(resp["error"]), str(resp.get("message", ""))])
	elif resp.has("state"):
		action_validated.emit(index, false, resp["state"])   # mismatch -> corrected state
	else:
		action_validated.emit(index, true, null)              # hash matched


func _send(s: String) -> void:
	_ws.send_text(s)
