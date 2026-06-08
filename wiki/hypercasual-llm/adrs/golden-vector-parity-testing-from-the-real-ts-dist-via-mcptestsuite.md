# ADR-8: Golden-vector parity testing from the real TS dist via McpTestSuite

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Testing
- **Deciders:** Benjamin Jordan

## Context
Determinism parity is only credible if it is continuously verified against the *real* TS implementation, not against hand-authored expectations that could encode the same mistake as the port. The project needed a way to assert byte-equality of RNG outputs and state hashes against authoritative values, and a test runner that works through the godot-ai MCP.

## Decision
Generate golden vectors by running the real moveborne-logic dist in Node (the golden generators import a copy of the logic dist with seedrandom and json-stable-stringify installed), dumping first-N RNG outputs per namespace and seed plus computeStateHash of known states, and asserting byte-equality in GDScript. Never hand-write expected hashes. Use the built-in McpTestSuite runner (the test-prefixed scripts under res://tests) rather than GUT, with headless verifier scripts under tools per engine module. Every test must make at least one assertion or it auto-fails.

## Consequences
POSITIVE: Parity regressions are caught immediately and unambiguously against ground truth, and the same fixtures (including the repo history fixtures) can validate every move. New logic cannot ship without an oracle, which keeps the determinism contract honest.

NEGATIVE / COST: Adding engine logic requires a Node toolchain to regenerate goldens from the dist, which is extra setup and a moving dependency on the TS package. Two runners (McpTestSuite plus the headless verifiers) must be kept in sync.

## Relations
_None._
