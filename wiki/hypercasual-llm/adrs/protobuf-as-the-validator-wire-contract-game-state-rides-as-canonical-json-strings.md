# ADR-19: Protobuf as the validator wire contract; game state rides as canonical-JSON strings

**Status:** accepted

## Metadata
- **Date:** 2026-06-11
- **Scope:** Validator / Networking / Determinism
- **Deciders:** Benjamin Jordan

## Context
Refactoring the validator to a gRPC/Hermes transport (see the companion ADR) requires a concrete wire format for every game⇄validator message. The load-bearing constraint is determinism parity (ADR-1): game/logic (GDScript) and validator/src/logic/dist (TS) must compute identical state hashes, and that hash is computed over the CANONICAL JSON of SynchronizedGameState. If protobuf re-modeled the game state as proto messages, the proto encoding's normalization (proto3 omitting zero-value fields, integer widths, map key ordering, float representation) would diverge from the canonical-JSON the hash is taken over — silently breaking parity between the two engines. Separately, the GDScript binding generator (godobuf) cannot faithfully model the deeply-nested, dynamically-shaped game state, and that state shape evolves with the game while the transport envelope does not.

## Decision
Define ALL game⇄validator message types as protobuf in validator/protos/ — the single source of truth for the wire format — BUT carry SynchronizedGameState and GameAction as canonical-JSON STRING fields inside the proto messages (starting_state_json, current_state_json, action_json, state_json), not as re-modeled proto messages. The proto layer frames only the transport envelope: match_id, index, state_hash, signature, and the reward/balance maps.

The validator and the client JSON.stringify / JSON.parse the state and action at the proto boundary and compute the determinism hash over the canonical JSON exactly as before. The protos therefore never need to change when the game-state shape evolves, and the hash domain is provably untouched by the transport choice.

## Consequences
POSITIVE: Hash parity is preserved by construction — the hash domain stays canonical JSON, byte-identical between the TS dist and the GDScript port; all nine parity verifiers pass unchanged through the refactor. The protos stay small and stable (they do not track the evolving, deeply-nested state graph), so godobuf can generate the GDScript bindings (it handles the flat envelope messages but would choke on the full state). Adding a game-state field requires no proto change and no binding regeneration.

NEGATIVE / COST: The wire is not fully typed end-to-end — game state is an opaque string to the proto layer, so proto tooling cannot validate its shape (the engine does). The double representation (JSON inside protobuf) costs a stringify/parse per message and some extra bytes versus a native proto encoding. A future decision to fully proto-model the state would require a parallel canonical-JSON codec dedicated to hashing (recorded as an open question on the feature brief).

## Relations
_None._
