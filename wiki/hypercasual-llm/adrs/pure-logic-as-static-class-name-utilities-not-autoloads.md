# ADR-7: Pure logic as static class_name utilities, not autoloads

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Determinism Primitives / Rules Engine
- **Deciders:** Benjamin Jordan

## Context
The original port plan called for the RNG and Hasher to be Godot autoloads (singletons) alongside the stateful GameEngine and NetClient. In practice the RNG and hash are pure functions of their inputs, and the determinism layer needed to be testable directly editor-side before any scene or autoload existed. Autoloads also do not register `class_name` globals on reimport alone, complicating early testing.

## Decision
Implement the pure rules layer as static global-class utilities (Mb-prefixed: MbRng, MbHasher, MbRandom, MbEngine, MbPowerCards, and so on) with static functions and no instance state, instead of autoload singletons. Scenes and tests reference them via preload of the script path, which works before a full editor scan registers the global names. Stateful pieces that genuinely need lifecycle (the Match Controller, the Validator Client) remain ordinary objects or nodes, not part of this pure layer.

## Consequences
POSITIVE: Pure functions are trivially unit-testable headless with no autoload setup, and there is no hidden singleton state to reset between tests. The determinism layer stays obviously side-effect free, reinforcing the hard wall (ADR-0003).

NEGATIVE / COST: The global names do not register from reimport alone, so tests and scenes must preload script paths until a full editor scan runs. Callers pass state explicitly rather than reaching a global singleton, which is more verbose.

## Relations
_None._
