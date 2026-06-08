# Validator Client

**Status:** current

## Kind
subsystem

## Summary
`net/validator_client.gd` (`MbValidatorClient`) — a hand-rolled Engine.IO/Socket.IO client over Godot's `WebSocketPeer`. Connects to the Validator service, sends `(index, action, state_hash)` per move, and surfaces ACK / authoritative-state-sync results to the Match Controller.

## Purpose
Let the Godot client talk to the unmodified validator without a Socket.IO SDK. It speaks the Engine.IO framing and Socket.IO event protocol directly over a raw WebSocket: handshake with `(connection_id, player_id)`, emit per-action validation requests, and parse the match/mismatch response union. On match it confirms the optimistic move; on mismatch it returns the validator's authoritative state for the controller to snap to.

## Design notes
_None._

## Components
_No components._

## Dependencies
- **calls** → [Validator](architecture:mq1c2ixi-000h-kd018q) — Connects to and validates moves against the Validator service over Socket.IO.

## Code references
- class `MbValidatorClient` in `llm-workflow/net/validator_client.gd`

## Data model
_None._

## Usage
Activated by the `V` key (or MCP). Requires the validator running (`tools/run_validator.sh`, DEV_MODE on `:5055`). The HUD reflects status as `validator: ✓ move N ok`. Verified headless against the live validator via a `tools/verify_*` client smoke.

## Invariants & constraints
- The predicted hash sent up is exactly the hash MbEngine produced for the optimistic move — same canonical serialization as the validator, or every move would falsely mismatch.

## Synced commit
85f64c0
