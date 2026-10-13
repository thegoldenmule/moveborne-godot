# Realtime Gateway

**Status:** current

## Kind
subsystem

## Summary
The transport front door: a gRPC service (moveborne.validator.v1.ValidatorService — InitMatch, ValidateAction, CompleteMatch; protos in validator/protos/) that Snapser Hermes proxies MESSAGE_TYPE_SNAP_API_PROXY calls to, plus the validator's own Hermes-emulation WebSocket (/hermes/ws?token=...) speaking the identical protobuf ClientMessage/ServerMessage envelope for local dev, and a slim Hono HTTP surface (health probe, status, state-history tooling, MCP). Transport-agnostic handlers live in service.ts; grpc.ts and hermes-ws.ts are thin codecs over them. Replaced the original HTTP-init + Socket.IO design — there is no connection lifecycle anymore.

## Purpose
Expose the validation loop as pure request/response RPCs correlated by match_id. Every RPC binds the gateway-validated caller identity to the match owner before any game logic; ValidateAction fetches state, runs executeAction (score accumulation + the moveIndex +1/+2-on-card-draw rule preserved exactly), computes the hash, signs (match_id, index, action, state_hash), and returns matched=true or matched=false plus the authoritative state, then writes new state back to the store. CompleteMatch settles rewards idempotently. Game state and actions stay canonical-JSON strings inside proto fields — the determinism hash domain must not be re-modeled by the wire format.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
- **depends-on** → [Crypto & Signing](architecture:mq1c351c-0011-gtfyxx) — Verifies the Snapser gateway caller (User-Id binding) on init + the Socket.IO handshake, and signs each validation response.
- **depends-on** → [Match State Store](architecture:mq1c31rb-000x-6l2ehj) — Reads/writes match state keyed by match_id (the connection_id index is gone).

## Code references
- `validator/src/validator/index.ts`
- function `createMatchRoutes` in `validator/src/validator/routes/match.ts`
- class `ValidatorService` in `validator/src/validator/service.ts`
- function `startGrpcServer` in `validator/src/validator/grpc.ts`
- class `HermesDispatcher` in `validator/src/validator/hermes-ws.ts`
- `validator/protos/moveborne/validator/v1/validator.proto`
- `validator/protos/hermes/hermes_envelope.proto`

## Data model
Wire protocol source of truth: validator/protos/moveborne/validator/v1/validator_messages.proto (+ validator.proto for the service block — split because godobuf parses messages but not services) and validator/protos/hermes/hermes_envelope.proto (reconstructed from snapser-pb Go stubs; field numbers are load-bearing, live-verified against the deployed Hermes). GDScript bindings are godobuf-generated into game/net/proto/; the TS side loads the same protos at runtime (protobufjs / @grpc/proto-loader, keepCase). Cross-implementation byte parity is asserted by game/tools/verify_hermes_proto.gd against fixtures from src/validator/tools/generate-hermes-golden.ts.

## Usage
bun run dev (HTTP + Hermes-emulation WS on PORT 5555, gRPC on GRPC_PORT 8081; deployed: HTTP 8080 behind the gateway, gRPC 8081 as the profile's internal "grpc" port). The game connects with one codepath: ws://localhost:5555/hermes/ws?token=<player-id> locally (token = self-stamped player id), wss://gateway.snapser.com/<snapend>/v1/hermes/ws?token=<session> deployed — token-in-query auth also works from web exports where WS upgrade headers are blocked. snap_api_request carries {api_method: "/moveborne.validator.v1.ValidatorService/<Rpc>", payload: request proto bytes}; responses echo the mid. Do not send Message_Ping to the live Hermes endpoint — it drops the connection. Per CLAUDE.md, the dev server runs under bun run --watch — do not kill/restart it.

## Invariants & constraints
- Caller binding must pass before any game logic on every RPC and on the WS upgrade: user-context callers must have gateway-validated identity == match owner (player_id); api-key/internal callers pass unbound. Locally the Hermes-emulation ?token= param is the self-stamped identity. Failures map to gRPC codes (PERMISSION_DENIED / NOT_FOUND / INVALID_ARGUMENT) and to SnapApiError in the Hermes envelope. There is no bypass switch.
- The Hermes envelope must stay wire-compatible with the platform proto: field renames are allowed (names are not encoded — error_message, api_method, oneof msg exist only because godobuf cannot parse the originals), but field numbers and enum values must match snapser-pb exactly.

## Synced commit
7f55d94
