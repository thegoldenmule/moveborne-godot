# Spec — Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport

**Status:** sealed

## Overview
Shipped: the Moveborne validator is a simple gRPC request/response service (moveborne.validator.v1.ValidatorService — InitMatch, ValidateAction, CompleteMatch) whose message types are protobuf in validator/protos/ (the single source of truth). The game reaches it through the Snapser Hermes WSS endpoint in production and an identical local Hermes-emulation endpoint in dev, over one client codepath (game/net/hermes_client.gd, godobuf bindings). The HTTP-init + Socket.IO protocol and the connection_id lifecycle are gone. Deployed as byosnap-validator v0.2.4 on c4n1awfs and verified end-to-end. Recorded as ADR-19 (wire contract), ADR-20 (transport), ADR-21 (codegen tooling).

## Design
## Wire protocol

All game⇄validator messages are protobuf (validator/protos/: moveborne/validator/v1/validator.proto for the service, validator_messages.proto for the messages — split because godobuf parses messages but not service blocks; hermes/hermes_envelope.proto for the Snapser ClientMessage/ServerMessage envelope, field numbers reconstructed from the platform's Go stubs). SynchronizedGameState and GameAction ride as canonical-JSON STRING fields inside the proto messages, never re-modeled as proto, so the determinism hash domain (canonical JSON) is untouched and all 9 parity verifiers pass unchanged. See ADR-19.

## Transport & service

Transport-agnostic handlers (service.ts) sit behind three codecs: a @grpc/grpc-js server (the production target; Snapser Hermes proxies MESSAGE_TYPE_SNAP_API_PROXY to the BYOSnap's internal gRPC port, routing by the byosnap-id package segment /byosnap-validator.ValidatorService/<Rpc>), a local Hermes-emulation WebSocket speaking the identical envelope (mounted only when there is no gateway prefix — local dev), and the surviving Hono HTTP surface (health probe, status, state-history tooling, MCP). Requests are correlated by match_id; there is no connection lifecycle. The game uses one client (MbHermesClient): ws://localhost:5555/hermes/ws?token=<player-id> locally, wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws?token=<session> deployed. See ADR-20.

## Auth & identity

Unchanged trust model (ADR-17): identity is the gateway-validated session, bound to the match owner (player_id) server-side — over User-Id on HTTP / gRPC metadata deployed, and the ?token= self-stamped player id only in local dev (where the emulation route lives). Token-in-query is browser-reachable, which is what fixes the web-export WS bug. Hardening from code review: InitMatch rejects a re-init by a different owner; ValidateAction rejects a stale/replayed action index; the self-stamp route is deployed-off.

## Deployment, tooling & verification

BYOSnap byosnap-validator v0.2.4 on c4n1awfs: HTTP :8080 (external, gateway + probe), gRPC :8081 (internal "grpc" port). tools/gen-protos.sh regenerates all three artifacts from the protos — the JS SDK (pbjs compiled descriptor loaded via Root.fromJSON), swagger.json (code-defined, version from package.json, uploaded on byosnap publish), and the godobuf GDScript bindings (ADR-21). Verified: bun type-check + 33 service/dispatch tests, all 9 parity verifiers unchanged, godobuf⇄protobufjs byte-parity golden, local + deployed E2E (anon login → gateway Hermes → Init/Validate/Complete) and in-game Story mode.

## Decisions
Game state and actions are carried as canonical-JSON strings inside proto fields rather than re-modeled as protobuf, to preserve hash parity by construction. Accepted as the shipped design (ADR-19); a future full proto-model would need a parallel canonical-JSON codec for hashing. SynchronizedGameState/GameAction are kept as canonical-JSON strings inside proto fields to protect hash parity (the hash is computed over canonical JSON). Is that acceptable long-term, or should a follow-up fully proto-model the game state with a parallel canonical-JSON codec for hashing?

gRPC over Snapser Hermes is the transport (no HTTP-POST fallback). The fallback question is moot: Hermes SNAP_API_PROXY routing to the BYOSnap gRPC service was confirmed working live, routing by the byosnap-id package segment (ADR-20). If Snapser turns out not to route Hermes SNAP_API_PROXY to BYOSnap gRPC services, do you approve the documented fallback (same protos, HTTP POST transport under /v1/byosnap-validator, Hermes dropped) without re-planning?

The deployed Inventory currency-grant gap (granted=true but wallet not credited) is a separate, pre-existing bug — the award s2s path is untouched by this refactor. Filed as bug-report:mq9v48kl-006b-xxqhck; not a blocker for shipping this transport refactor. Live finding during deployed E2E (pre-existing path, code untouched by this refactor): the Inventory s2s currency grant resolves transport "internal" and CompleteMatch latches granted=true, but the wallet credit does not land — GET /v1/inventory/users/<uid>/currencies stays empty after settle (verified twice with fresh anon users). Needs container-log triage on the snapend (the validator logs the failed PUT but does not block). Treat as a separate bug?

## References
_None._

## Child pages
_None._
