# ADR-5: Game state as an untyped Dictionary mirror of SynchronizedGameState

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Rules Engine
- **Deciders:** Benjamin Jordan

## Context
The hashed state is the TS `SynchronizedGameState`. The idiomatic Godot approach would be typed classes or `Resource`s with named fields. But the canonical serializer sorts keys and emits exactly the fields present, with exact key names; any drift in field names, presence of optional fields, or numeric typing breaks the hash. Tiles in the reference engine are a flat row-major array of plain objects.

## Decision
Represent game state as an untyped Dictionary that mirrors SynchronizedGameState, with field names matching the TS exactly and tiles stored as a flat row-major Array of tile Dictionaries. Do not introduce typed wrappers around hashed state. The engine int-casts numeric reads for robustness against JSON int/float ambiguity, and keeps integral values as int so they serialize without a trailing point-zero.

## Consequences
POSITIVE: Serialization parity is structural, not bolted on — the shape that hashes is the shape that exists, so there is no mapping layer to drift. Mirrors the JS object model directly, which makes porting rules a near-transliteration.

NEGATIVE / COST: No compile-time type safety on state access; typos in field names fail at runtime, not in the editor. Readers must defend against JSON numeric ambiguity. This trades GDScript's static typing for byte-level fidelity.

## Relations
_None._
