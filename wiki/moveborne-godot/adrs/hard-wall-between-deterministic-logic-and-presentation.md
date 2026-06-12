# ADR-3: Hard wall between deterministic logic and presentation

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client (all subsystems)
- **Deciders:** Benjamin Jordan

## Context
Byte-for-byte determinism is fragile: if presentation code can read or mutate game state, or if input coordinates leak into hashed state, parity breaks in ways that are hard to trace. The original PixiJS client interleaves rendering, controllers, and logic; porting that structure would entangle scene-tree concerns with the hash-critical engine.

## Decision
Enforce a hard wall with one-way data flow: input becomes an action, the pure engine produces new state plus a hash, scenes render that state, and net confirms it. The engine has zero Node or scene references (pure GDScript, Mb-prefixed classes with static functions). Presentation reads only the state the Match Controller publishes and never mutates state or RNG. Input is reduced to a direction enum (one gesture yields one SWIPE, debounced while animating) so no pointer coordinates ever enter hashed state.

## Consequences
POSITIVE: The engine is unit-testable headless with no scene; VFX and rendering can be rebuilt or changed freely without risking parity, which enables ADR-0009. State ownership is unambiguous — the Match Controller is the only mutator.

NEGATIVE / COST: Some ceremony — presentation cannot reach into logic for convenience; everything crosses the published-state boundary. Effects that want sub-state detail (for example per-tile animation cues) must derive it from published state plus moveIndex, not from engine internals.

## Relations
_None._
