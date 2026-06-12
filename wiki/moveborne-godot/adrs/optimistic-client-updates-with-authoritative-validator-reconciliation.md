# ADR-2: Optimistic client updates with authoritative validator reconciliation

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Match Controller / Validator Client
- **Deciders:** Benjamin Jordan

## Context
A swipe-merge puzzle needs instant tactile feedback — tiles must slide and merge the frame the player swipes. But when online, the Validator is the authority on state. Waiting for a server round-trip before rendering each move would make the game feel laggy, especially on mobile networks. Because the local engine is built to compute the same result the validator will, a predict-then-confirm model is safe.

## Decision
Play optimistically: apply every action locally through the pure engine immediately and render the result, while, when online, sending the predicted state hash to the validator. On a hash match the validator ACKs and nothing changes (the fast path). On a hash mismatch the validator returns its authoritative state and the client snaps to it. The Match Controller owns this flow; the Validator Client transports it.

The v1 reconciliation is adopt-server-state-directly on mismatch, not a full rollback and replay of a pending-operation queue. That richer model (an op queue with backpressure cap, rollback, and replay ordered by moveIndex) is deferred; direct adoption is sufficient for single-player-versus-validator where divergence only happens on a genuine port bug.

## Consequences
POSITIVE: Zero perceived input latency; the game is fully playable offline with no validator and identical in logic online. Because ADR-0001 makes hashes match, mismatches are rare, so the cheap reconciliation almost never fires.

NEGATIVE / COST: A mismatch produces a visible snap rather than a smooth correction. Multi-client or PvP futures will need the deferred op-queue and rollback model; the current path is not safe for adversarial divergence at scale.

## Relations
_None._
