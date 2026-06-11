# ADR-20: gRPC over Snapser Hermes as the validator transport, replacing HTTP-init + Socket.IO

**Status:** accepted

## Metadata
- **Date:** 2026-06-11
- **Scope:** Validator / Networking / Deployment / Client
- **Deciders:** Benjamin Jordan

## Context
ADR-16 adopted Snapser with the Validator as a BYOSnap reached over HTTP match-init + a hand-rolled Socket.IO transport, authenticated by a native WebSocket carrying custom handshake headers (assuming a mobile-only target). Two problems surfaced. (1) Web exports cannot set WebSocket upgrade headers, so the header-authenticated Socket.IO upgrade 400s at the gateway (the open web-build bug), and the gateway accepts no browser-reachable WS auth fallback on byosnap routes. (2) The Engine.IO/Socket.IO wire format was hand-rolled on both sides — a ~200-line GDScript Engine.IO/Socket.IO parser — and carried a connection_id lifecycle (HTTP init mints a token, WS handshake binds it). Snapser provides Hermes, a managed, horizontally-scaled WebSocket server that proxies MESSAGE_TYPE_SNAP_API_PROXY messages to a snap's gRPC service and authenticates via a token QUERY PARAM (browser-reachable).

## Decision
Replace HTTP-init + Socket.IO with a simple gRPC request/response service, moveborne.validator.v1.ValidatorService (InitMatch, ValidateAction, CompleteMatch). In production the game connects to the Snapser Hermes WSS endpoint (wss://gateway.snapser.com/<snapend>/v1/hermes/ws?token=<session>) and sends protobuf ClientMessages whose snap_api_request {api_method, payload} Hermes forwards to the BYOSnap's gRPC port — declared as the profile's internal "grpc" port; Hermes routes by the method string's package segment, which must be the byosnap id (/byosnap-validator.ValidatorService/<Rpc>).

Locally the validator serves the IDENTICAL ClientMessage/ServerMessage envelope at ws://localhost:5555/hermes/ws?token=<player-id>, so the game has exactly one client codepath — only the URL differs. That emulation route is mounted only when there is no gateway prefix (local dev), so the token→self-stamped-identity trust does not exist in deployed code.

The connection_id lifecycle is removed: requests are correlated by match_id and the caller is bound to the match owner by the gateway-validated identity (User-Id over HTTP / gRPC metadata; the ?token= param self-stamps identity only in local dev). The gateway-stamped-identity auth model (ADR-17) is unchanged — this decision only changes how that identity arrives.

## Consequences
POSITIVE: Token-in-query auth is browser-reachable, so the web-export WS bug is fixed architecturally with ONE transport for native and web. The hand-rolled Socket.IO/Engine.IO stack on both sides is deleted; the wire format is a small generated protobuf contract. The service is pure request/response with no connection state — simpler to reason about, test, and scale. Verified live end-to-end through the real gateway Hermes on c4n1awfs (anonymous login → InitMatch → ValidateAction → CompleteMatch) plus in-game Story mode.

NEGATIVE / COST: Hermes platform coupling, with undocumented behaviors learned empirically and now encoded: routing is by byosnap id (the canonical proto package answers "invalid service"), a client-initiated Message_Ping drops the live connection, and the envelope field numbers had to be reconstructed from Snapser's generated Go stubs. There is no client-initiated keepalive; idle keepalive on the deployed path is the managed Hermes service's responsibility (the local emulation relies on a long idle timeout). gRPC routing depends on declaring an internal grpc port in the BYOSnap profile, and that profile's EXTERNAL port must not change on a live snapend — changing it once failed the rollout (revert + redeploy fixed it).

RELATIONS: Partially supersedes ADR-16's transport specifics (Socket.IO, header auth, mobile-only assumption); ADR-16's core "adopt Snapser" decision and ADR-17's gateway-stamped-identity auth model both still stand. Resolves the open web-build WebSocket gateway-auth bug architecturally (verify with an actual web export before closing it).

## Relations
_None._
