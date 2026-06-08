# ADR-11: Code beats spec; rules from src/logic, scenarios/UI from src/game

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Project / Source of truth
- **Deciders:** Benjamin Jordan

## Context
The moveborne repo contains **two** engine copies: `src/logic/src` (the shared rules package the validator imports — the rules authority) and `src/game/engine` (the client's copy plus rendering, controllers, and the scenario table). The markdown specs under `spec/game` are a guide and sometimes diverge from the running code (for example scenarios, decay value-reduction, totem durations, which events are routed). Parity requires matching the code that actually computes hashes, not the prose.

## Decision
Adopt code-beats-spec as a standing rule, with a clear two-copy split: port the rules from src/logic (the validator's authority), and take the scenario table and UI-facing config from src/game/engine (notably scenarios, which diverges from the spec markdown). Treat spec/game as a guide only. When code and spec disagree, the code wins and the divergence is noted (known cases: scenarios source, decay value-reduction not implemented, totem durations by moves/merges/tally rather than swipes, only combo-break and score-update events routed).

## Consequences
POSITIVE: The port tracks reality and stays hash-compatible, avoiding bugs from trusting stale prose. The authority for each concern is unambiguous (rules from the shared logic package, scenarios and UI from the client copy).

NEGATIVE / COST: Contributors must read two TS sources and cannot rely on the spec docs alone; known divergences have to be tracked by hand. The spec remains useful context but is not trustworthy as a literal contract.

## Relations
_None._
