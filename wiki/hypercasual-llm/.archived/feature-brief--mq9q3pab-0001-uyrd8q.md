# Feature: Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport

**Status:** shipped

## Summary
Refactor the validator (validator/, today Bun + Hono + Socket.IO) into a simple gRPC request/response service. All wire message types are defined as protobuf in a dedicated directory (validator/protos/), with ValidatorService exposing three RPCs: InitMatch, ValidateAction, CompleteMatch — replacing the HTTP-init + Socket.IO event protocol and eliminating the connection_id lifecycle entirely (requests are keyed by match_id + gateway-bound player identity). GDScript bindings are generated from the protos (godobuf) and the game client migrates from the hand-rolled Engine.IO/Socket.IO client to a Hermes-envelope WSS client: in production the game connects to wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws?token=$TOKEN and sends MESSAGE_TYPE_SNAP_API_PROXY ClientMessages whose snap_api_request carries {method: "/moveborne.validator.v1.ValidatorService/<Rpc>", payload: request proto bytes}, which Hermes forwards to the validator's gRPC service; locally the validator serves an equivalent Hermes-emulating WS endpoint so the same client codepath works offline. The snap is redeployed (byosnap-validator on app c4n1awfs) and verified end-to-end through the Hermes WSS endpoint. Side effect: token-in-query-param auth fixes the open web-export bug where browsers cannot send Token/User-Id headers on WS upgrade.

## Components affected
- Protobuf definitions — validator/protos/ (moveborne.validator.v1 service + messages, vendored Hermes envelope protos)
- Validator gRPC server (Bun + @grpc/grpc-js) with transport-agnostic service handlers refactored out of Hono/Socket.IO
- Local-dev Hermes emulation WS endpoint on the validator (same ClientMessage/ServerMessage envelope, token query param)
- GDScript protobuf bindings generated via godobuf into game/net/proto/
- Game Hermes WSS client (game/net/hermes_client.gd) replacing the Socket.IO client (game/net/validator_client.gd retired)
- BYOSnap deployment update (Dockerfile, snapser-byosnap-profile.json, snapctl publish + snapend update on c4n1awfs)
- E2E verification: local emulated-Hermes loop + deployed gateway Hermes WSS loop

## Design constraints
1. Determinism parity is non-negotiable: game/logic (GDScript) and validator/src/logic/dist (TS) must keep producing identical state hashes. The hash domain is canonical JSON, so SynchronizedGameState and GameAction travel as canonical-JSON string fields inside proto messages — the protos must NOT re-model game state. Parity verifiers (game/tools/verify_*.gd) must pass unchanged.
2. Auth model preserved: identity comes from the gateway-validated session (Hermes token query param → session → user id), bound to player_id server-side. No signature-based caller auth. Local dev has no gateway, so the emulated Hermes endpoint accepts a self-stamped identity the same way the current local flow self-stamps User-Id.
3. BYOSnap container contract unchanged where applicable: Docker build context MUST be validator/ (workspace:* link resolution), container listens on :8080 for HTTP, /health answered unprefixed for the platform probe, BYOSNAP_BASE_PATH respected for remaining HTTP routes (health, MCP, history tooling).
4. validator/src/logic (committed dist) and game/logic behavior must not change — this is a transport-layer refactor only; executeAction/computeStateHash call sites keep identical semantics, ordering, and RNG consumption (including the moveIndex +1/+2-on-card-draw rule and score accumulation in the validate handler).
5. Local dev loop must keep working fully offline: bun run dev on :5555, game presses V to connect — same MbHermesClient codepath against the validator's local Hermes-emulation WS endpoint. MCP debug interface (/mcp) and history replay tooling stay functional.
6. Wire protocol change is breaking by design (single-client game, no compat window): Socket.IO and the connection_id lifecycle are removed in the same change, not deprecated alongside.
7. Platform risk to verify FIRST: Snapser must support Hermes SNAP_API_PROXY routing to a BYOSnap gRPC service (hermes.mdx confirms the envelope + /package.Service/Method routing for snaps; BYOSnap-specific gRPC registration needs confirming, and the snapend's Gateway > Web Sockets toggle must be enabled on c4n1awfs). If unsupported, fallback is the same protobuf request/response messages POSTed over HTTP under /v1/byosnap-validator (still kills Socket.IO and still fixes the web header bug).

## Open questions
_None._

## Resolved questions
1. **SynchronizedGameState/GameAction are kept as canonical-JSON strings inside proto fields to protect hash parity (the hash is computed over canonical JSON). Is that acceptable long-term, or should a follow-up fully proto-model the game state with a parallel canonical-JSON codec for hashing?** — _Accepted as the shipped design — recorded as ADR-19 (Protobuf as the validator wire contract; game state rides as canonical-JSON strings). Carrying SynchronizedGameState/GameAction as canonical-JSON strings is what preserves hash parity by construction (the hash domain stays canonical JSON; all 9 parity verifiers pass unchanged), and it keeps the protos small/stable and godobuf-generatable. No follow-up is planned now; a future move to fully proto-model the state would require a parallel canonical-JSON codec dedicated to hashing — documented in ADR-19's consequences._
2. **If Snapser turns out not to route Hermes SNAP_API_PROXY to BYOSnap gRPC services, do you approve the documented fallback (same protos, HTTP POST transport under /v1/byosnap-validator, Hermes dropped) without re-planning?** — _Moot — Hermes SNAP_API_PROXY routing to the BYOSnap gRPC service was confirmed working live (deployed E2E through wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws, routing by the byosnap-id package segment), so the HTTP-POST fallback was never needed and was not implemented. Recorded in ADR-20._
3. **Live finding during deployed E2E (pre-existing path, code untouched by this refactor): the Inventory s2s currency grant resolves transport "internal" and CompleteMatch latches granted=true, but the wallet credit does not land — GET /v1/inventory/users/<uid>/currencies stays empty after settle (verified twice with fresh anon users). Needs container-log triage on the snapend (the validator logs the failed PUT but does not block). Treat as a separate bug?** — _Yes — treated as a separate, pre-existing bug (the award s2s path is unchanged by this refactor). Filed under Bugs as bug-report:mq9v48kl-006b-xxqhck ("Deployed currency grant latches granted=true but never credits the Inventory wallet"), with repro, the exact failing s2s call, leading hypotheses, and the container-log triage step. Not a blocker for this feature._

## References
_None._

## Child pages
- [Implementation plan — Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport](implementation-plan:mq9q3pab-0002-ibven5)
- [Testing plan — Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport](testing-plan:mq9q3pab-0003-oii8kq)
- [Spec — Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport](feature-spec:mq9q3pab-0004-r5ckc6)

## Commits
- `feffd1d` feat(validator): gRPC request/response service over Snapser Hermes — protobuf wire protocol end to end
- `3afd897` fix(validator): code-review hardening — reconnect, re-init guard, stale-index guard, local-only Hermes WS
- `124e3bd` build(validator): regeneration tooling for JS + GDScript SDKs and swagger from the protos
- `d67a153` build(validator): v0.2.4 — /api/status reads version from package.json; regenerate swagger
