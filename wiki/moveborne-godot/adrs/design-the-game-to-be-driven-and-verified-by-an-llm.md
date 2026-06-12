# ADR-12: Design the game to be driven and verified by an LLM

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Project / Client / Tooling
- **Deciders:** Benjamin Jordan

## Context
This project is a research bet: can a one-shot LLM game demo scale into a non-trivial, server-authoritative game that an LLM can keep building? The lesson from shipping prior titles is that great specs and prompting only get an LLM to roughly **80%**; closing the gap needs an automated way to tell whether a change is *in the ballpark*. For a game — where there is no perfect scoring function and fun is judged by playing — a unit test cannot be that signal on its own. The agent must be able to drive the **actual game**: perform real inputs, read real state, and confirm a feature from a player's perspective. The same capability is what lets the agent reproduce and fix bugs from a captured state.

## Decision
Treat LLM-driveability as a first-class design goal that shapes the architecture, not an afterthought. The game exposes a stable interface an agent can use to both play it and verify it: issue every input (swipe, card, totem, tap), read the current state and the board, list playable cards, and capture state history. In the Godot port this is the MbDebug autoload (the analog of the web build's debug window object), reachable over the godot-ai MCP through game-eval, and mirrored on the validator by its own MCP debug surface. The verification loop is concrete: the agent loads a scenario, performs inputs, and inspects the resulting state to confirm the feature actually works.

Bug repro rides the same rails. Because state is consolidated and the engine is deterministic, a bug reduces to a triple of starting state, input, and expected-versus-actual result. The agent or the human copies that triple, the engine replays the input from the captured state, and the divergence is inspected directly; a captured state can also be force-loaded to jump straight to the failure. This is the practical payoff of determinism and state consolidation, not a separate feature.

## Consequences
POSITIVE: An agent can make meaningful, verified progress on real gameplay features, not just on isolated pure functions. Features are validated from a player's perspective, and bugs are reproducible from a captured state rather than from a vague description. This is what lets Claude work productively on a non-trivial, server-authoritative game.

NEGATIVE / COST: The driveability surface (input injection, state and board readout, history capture) is real product surface that must be built and kept in sync as features grow. It overlaps with debug tooling and has to track the action and state shapes, or the agent silently drives a stale interface.

## Relations
_None._
