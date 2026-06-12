# ADR-6: Mirror JS mutation semantics via GDScript references + shallow duplicate

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Rules Engine
- **Deciders:** Benjamin Jordan

## Context
The reference merge code (`merge.ts`) relies on JavaScript reference semantics: it spreads arrays/objects shallowly (`[...arr]`, `{...obj}`), mutates some tile objects in place, and creates fresh objects only for merged/spawned tiles. The resulting object identity and aliasing affect which tiles share state — and therefore the final serialized result. A naive port that deep-copies everything or models state as immutable would diverge subtly from the original, which the determinism-parity requirement forbids.

## Decision
Mirror the JS mutation model directly using GDScript reference semantics. GDScript Dictionary and Array are reference types like JS objects and arrays, so use shallow duplicate() to reproduce spread, mutate tile dictionaries in place exactly where the TS does, and create new dictionaries only for merged or spawned tiles. Do not deep-copy unless the TS does, because deep-copying changes identity and aliasing. Non-empty tiles produced by merge or spawn carry an empty meta dictionary; empty tiles do not.

## Consequences
POSITIVE: The port reproduces merge.ts behavior almost for free — reference semantics line up with JS, so aliasing-dependent results match without extra bookkeeping. Keeps the port a close transliteration of the source.

NEGATIVE / COST: Subtle and easy to get wrong — an accidental duplicate() or a missing one silently changes the hash. Aliasing is implicit, so the code demands care and golden coverage when edited; it is the least obvious of the determinism constraints.

## Relations
_None._
