# Testing plan — Validator gRPC refactor: protobuf API, Godot bindings, Hermes transport

**Status:** ready

## Planned
_None._

## Passed
- Validator service-handler happy path (bun test): InitMatch with a real starting state → ValidateAction with the correct post-action hash returns matched=true + a verifiable HMAC signature → CompleteMatch returns rewards per mode table with granted latch behavior (second CompleteMatch returns granted=false, empty rewards).
- Hash-mismatch path: ValidateAction with a tampered state_hash returns matched=false plus the authoritative state_json whose computeStateHash equals the validator's computed hash; a follow-up ValidateAction from that adopted state succeeds.
- Auth binding: a user-context call whose bound identity != player_id/match owner is rejected (PERMISSION_DENIED), both on the gRPC metadata path and the Hermes-emulation token path; api-key/internal callers pass unbound.
- Envelope round-trip parity: protobuf ClientMessage/ServerMessage and all ValidatorService messages encode/decode byte-identically between the TS side and the godobuf-generated GDScript bindings (golden byte vectors generated from the TS encoder, asserted in a headless Godot verifier).
- Local E2E through emulated Hermes WS: headless Godot script connects MbHermesClient to ws://localhost:5555/hermes/ws?token=<player>, drives InitMatch → swipes with ValidateAction (hash match) → forced mismatch → CompleteMatch; signals fire correctly (ready_received, action_validated, match_completed).
- Determinism parity unchanged: all existing headless verifiers (engine_swipe, playcard, powercards, validation, tile_effects, totems, events, scenarios, combined) still PASS with unchanged golden hashes; validator bun test + tsc type-check pass.
- Container contract: /health answers unprefixed (platform probe) and the MCP debug tools (list_matches, get_match_state, simulate_action, get_state_history, clear_match) still work against matches created via gRPC/Hermes.
- Deployed E2E through the real gateway: anonymous Snapser login → wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws?token=$TOKEN → InitMatch/ValidateAction/CompleteMatch succeed end-to-end with NO custom WS headers (web-export-compatible); the live game (Story mode) shows validator ✓ move N and rewards settle.

## Failed
_None._

## References
_None._

## Child pages
_None._
