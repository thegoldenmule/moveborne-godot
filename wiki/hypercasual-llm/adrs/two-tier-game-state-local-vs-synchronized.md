# ADR-13: Two-tier game state — local vs synchronized

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Match Controller / Presentation
- **Deciders:** Benjamin Jordan

## Context
When state is scattered across an application, neither an LLM nor a human can keep up, and a networked game cannot agree on what is authoritative. The approach here keeps essentially **two** state objects: a *synchronized* state (the part that defines the game, goes over the network, and enters the hash) and a *local* state (cosmetic things that do not matter to correctness — tween progress, particle and VFX detail, input affordances). Only the synchronized half is hashed and sent to the validator; the local half never leaves the client. The common objection — that one big state object is inefficient — is accepted knowingly in exchange for legibility.

## Decision
Consolidate all game state into exactly two buckets: synchronized state and local state. Synchronized state is the authoritative game definition and is the only thing hashed, sent to the validator, and reconciled. Local state holds presentation-only concerns that do not affect the outcome: tween progress, particle and VFX detail, targeting affordances. In the Godot port the synchronized half is the Dictionary mirror of SynchronizedGameState owned by the Match Controller; local presentation state lives in the scenes and VFX layer and is never hashed.

Enforce the split by naming and ownership rather than by a type system. The rule is simple: if a value would change the outcome of the game it belongs in synchronized state; if it only changes how the game looks or feels it belongs in local state and must never enter the hash.

## Consequences
POSITIVE: There is one obvious place that is authoritative and networkable, which keeps both the agent and the human oriented and keeps the hash stable. Cosmetic richness (VFX, tweens) can grow freely with no risk to determinism or the wire protocol.

NEGATIVE / COST: A single large synchronized object is not the most cache-efficient layout, and the discipline is manual. An engineer who stashes a cosmetic value in synchronized state, or a gameplay value in local state, breaks either performance assumptions or parity; the boundary is policed by convention, not by the compiler.

## Relations
_None._
