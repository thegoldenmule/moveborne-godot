# Implementation plan — Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport

**Status:** ready

## Steps
- [x] Platform capability check: confirm from snapser-docs (infra/snaps/hermes.mdx, byosnap tutorials, snapend/protos.mdx) + Snapser MCP get_documentation how a BYOSnap registers a gRPC service that Hermes SNAP_API_PROXY can route to (method string /moveborne.validator.v1.ValidatorService/<Rpc>), whether the c4n1awfs snapend has the Gateway > Web Sockets toggle enabled, and what profile/publish changes (protos upload, gRPC port) are required. Record findings; if BYOSnap gRPC routing is unsupported, switch to the approved HTTP-POST-protobuf fallback before writing transport code.
- [x] Define protos in validator/protos/: moveborne/validator/v1/validator.proto (ValidatorService: InitMatch, ValidateAction, CompleteMatch + all request/response messages; state/action as canonical-JSON string fields) and hermes/hermes_envelope.proto (ClientMessage/ServerMessage/Message_SnapApiRequest/Message_SnapApiResponse/Message_Ping/Pong/Error reconstructed with exact field numbers from snapser-pb/hermes_types.pb.go: mid=1, message_type=2, timestamp=3, recipients=4, sender=5; oneof ping=10/pong=10, error=11, snap_api_request=50/api_response=50).
- [x] Refactor validator handlers to be transport-agnostic: extract init-match, validate-action (incl. moveIndex +1/+2 card-draw rule, score accumulation, state_history append, HMAC signature), and complete-match (idempotent rewards latch + Inventory s2s) out of index.ts/routes into a service module that takes (request, callerIdentity) and returns response objects — no Hono/Socket.IO imports.
- [x] Smoke-test gRPC-on-Bun feasibility (@grpc/grpc-js server over node:http2 h2c on Bun 1.3): tiny spike serving one unary echo RPC, called from grpc-js client. If Bun cannot serve grpc-js, decide fallback (document in plan): serve gRPC via minimal HTTP/2-free path — i.e. rely on Hermes emulation endpoint locally and HTTP-POST-protobuf transport behind the gateway.
- [x] Add proto codegen + gRPC server to the validator: bun-run codegen script (protoc or buf with ts plugin, or @grpc/proto-loader runtime loading to avoid codegen), wire ValidatorService RPCs to the transport-agnostic handlers, map gateway identity metadata to the caller-identity check (verifySnapserCaller equivalent for gRPC metadata). Serve on the platform-required port alongside the existing HTTP server.
- [x] Remove Socket.IO from the validator: delete socket.io/@socket.io/bun-engine deps and handlers, drop connection_id from init (keep generateConnectionId only if history tooling needs ids), keep /health (unprefixed + prefixed), /api/status, MCP /mcp, and history routes (init-from-history/save-history/load-history) on HTTP.
- [x] Add the local-dev Hermes emulation WS endpoint to the validator (ws://localhost:5555/hermes/ws?token=...): accept WS upgrade via Bun's websocket handler, decode protobuf ClientMessage frames, handle ping→pong and snap_api_request→dispatch by method string to the same gRPC handler table, reply with ServerMessage{mid, api_response{payload|is_error,error}}; token maps to self-stamped local identity (token value = player user id, mirroring today's self-stamped User-Id).
- [x] Vendor the godobuf addon (oniksan/godobuf, Godot 4) into game/addons/godobuf/ and generate GDScript bindings from validator/protos/ into game/net/proto/ (hermes envelope + validator messages); add a regeneration script/README note. Verify generated bindings parse in-editor (filesystem reimport + headless smoke).
- [x] Implement MbHermesClient (game/net/hermes_client.gd): WebSocketPeer binary frames; connect(url) with token query param; request/response correlation by mid; ping/pong keepalive; methods init_match(match_id, starting_state, player_id, mode), validate_action(index, action, state_hash), complete_match(); same signals as MbValidatorClient (connected, ready_received, action_validated, match_completed, validator_error) so main.gd wiring stays minimal.
- [x] Migrate the game: main.gd _start_net/_connect_snapser use MbHermesClient — local dev (V key) → ws://localhost:5555/hermes/ws?token=<player_id>; deployed Story/PvP → wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws?token=<session_token> after MbSnapserAuth.ensure_session(). Retire game/net/validator_client.gd and update game/tools/test_validator_client.gd to the new client.
- [x] Local E2E verification: run the validator (bun run dev :5555), headless Godot script drives InitMatch → several ValidateAction swipes (hash match) → a forced mismatch (tampered hash → authoritative state returned) → CompleteMatch through the emulated Hermes WS; run validator unit tests + type-check + all game parity verifiers (verify_engine_swipe etc. must be byte-identical).
- [x] Deploy: update validator/Dockerfile + snapser-byosnap-profile.json per step-1 findings (gRPC registration/protos upload), bump version, snapctl byosnap publish + snapend update on c4n1awfs (publish + update loop, NOT sync), confirm /health probe green.
- [x] Deployed E2E through the real gateway: anonymous login (snapser-validator skill flow) → open wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws?token=$TOKEN → drive InitMatch/ValidateAction/CompleteMatch from a test script; then run the actual game online (Story) and confirm HUD shows validator ✓ move N and rewards settle.
- [x] Documentation pass: validator/README.md + validator/src/validator/CLAUDE.md (new wire protocol, local Hermes emulation, gRPC), game/CLAUDE.md repo map (net/), root CLAUDE.md online-play section; update wiki architecture pages (Validator > Realtime Gateway, Client > Validator Client) via the wiki MCP.

## Data models & interfaces
```protobuf
// validator/protos/moveborne/validator/v1/validator.proto
syntax = "proto3";
package moveborne.validator.v1;

// Simple request/response service. Production transport: Snapser Hermes WSS
// (MESSAGE_TYPE_SNAP_API_PROXY -> this gRPC service). Local dev: identical
// envelope over the validator's own /hermes/ws emulation endpoint.
//
// SynchronizedGameState and GameAction stay canonical JSON inside string
// fields: the determinism hash is computed over canonical JSON, so the wire
// format must not re-model them (parity with game/logic GDScript port).
service ValidatorService {
  rpc InitMatch(InitMatchRequest) returns (InitMatchResponse);
  rpc ValidateAction(ValidateActionRequest) returns (ValidateActionResponse);
  rpc CompleteMatch(CompleteMatchRequest) returns (CompleteMatchResponse);
}

message InitMatchRequest {
  string match_id = 1;
  string starting_state_json = 2; // canonical SynchronizedGameState JSON
  string player_id = 3;           // must match gateway-bound identity
  string mode = 4;                // "story" | "pvp" | "infinite" (reward table only)
}
message InitMatchResponse {
  string match_id = 1;
  string current_state_json = 2;  // replaces the Socket.IO 'ready' event
  int64 expires_at = 3;           // match session expiry (ms epoch)
}

message ValidateActionRequest {
  string match_id = 1;            // replaces connection_id correlation
  uint32 index = 2;               // client moveIndex before the action
  string action_json = 3;         // canonical GameAction JSON
  string state_hash = 4;          // client's post-action hash claim
}
message ValidateActionResponse {
  uint32 index = 1;
  bool matched = 2;
  string state_json = 3;          // authoritative state, set only on mismatch
  string signature = 4;           // HMAC-SHA256 over {match_id,index,action,state_hash}
}

message CompleteMatchRequest {
  string match_id = 1;
}
message CompleteMatchResponse {
  string match_id = 1;
  map<string, string> rewards = 2;  // currency -> delta (int64-as-string)
  map<string, string> balances = 3; // currency -> current_balance_64
  bool granted = 4;
}

// gRPC errors use standard status codes: NOT_FOUND (match), PERMISSION_DENIED
// (player binding), INVALID_ARGUMENT (action failed), INTERNAL.
```

```protobuf
// validator/protos/hermes/hermes_envelope.proto — reconstructed from
// snapser-pb/hermes_types.pb.go (field numbers are load-bearing; verified
// against the generated Go structs).
syntax = "proto3";
package hermes;

enum MessageType {
  MESSAGE_TYPE_UNSPECIFIED = 0;
  MESSAGE_TYPE_SNAP_API_PROXY = 4;
  MESSAGE_TYPE_ERROR = 5;
  MESSAGE_TYPE_PINGPONG = 7;
  MESSAGE_TYPE_SNAP_EVENT = 8;
  MESSAGE_TYPE_PRESENCE = 9;
  MESSAGE_TYPE_USER_NOTIFICATION = 10;
  MESSAGE_TYPE_USER_PRESENCE_UPDATE = 11;
}

message Message_Ping {}
message Message_Pong {}
message Message_Error { ErrorCode code = 1; string message = 2; }
enum ErrorCode {
  ErrorCode_OK = 0; ErrorCode_INTERNAL = 1; ErrorCode_INVALID_ARGUMENT = 2;
  ErrorCode_NOT_FOUND = 3; ErrorCode_ALREADY_EXISTS = 4; ErrorCode_BUFFER_FULL = 5;
  ErrorCode_PERMISSION_DENIED = 6;
}

message Message_SnapApiRequest {
  string method = 1;   // "/moveborne.validator.v1.ValidatorService/ValidateAction"
  bytes payload = 2;   // request proto bytes
}
message SnapApiError { /* code/message/details — confirm exact fields from pb.go during impl */ }
message Message_SnapApiResponse {
  string caller_method = 1;
  int64 caller_time = 2;
  bytes payload = 3;   // response proto bytes
  bool is_error = 4;
  optional SnapApiError error = 5;
}

message ClientMessage {
  string mid = 1;                 // echoed back in ServerMessage
  MessageType message_type = 2;
  int64 timestamp = 3;
  repeated string recipients = 4;
  oneof message {
    Message_Ping ping = 10;
    Message_SnapApiRequest snap_api_request = 50;
  }
}
message ServerMessage {
  string mid = 1;
  MessageType message_type = 2;
  int64 timestamp = 3;
  repeated string recipients = 4;
  string sender = 5;
  oneof message {
    Message_Pong pong = 10;
    Message_Error error = 11;
    Message_SnapApiResponse api_response = 50;
  }
}

// GDScript client surface (game/net/hermes_client.gd, godobuf bindings in
// game/net/proto/):
//   signals: connected, ready_received(state), action_validated(index, matched,
//            corrected_state), match_completed(response), validator_error(msg)
//   funcs:   connect_hermes(url), init_match(match_id, starting_state, player_id, mode),
//            validate_action(index, action, state_hash), complete_match()
// Correlation: mid (uuid-ish counter) -> pending request map; binary WS frames.
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
