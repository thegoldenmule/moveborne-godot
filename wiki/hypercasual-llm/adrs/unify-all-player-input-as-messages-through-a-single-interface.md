# ADR-14: Unify all player input as messages through a single interface

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Match Controller / Networking
- **Deciders:** Benjamin Jordan

## Context
A casual game has several input modes — swiping, tapping a tile, playing a card, spawning a totem. If each is wired ad hoc into the UI, the game cannot be networked deterministically, cannot be replayed, and cannot be driven by an agent. The stated **first step** on this project was to make *every player input a message* piped into a single interface. That one abstraction is what later makes optimistic networking, deterministic replay, and LLM-injection all possible from the same seam.

## Decision
Model every player input as a message (an action) and funnel all of them through one interface, rather than handling each input mode separately. Each gesture or tap is reduced to a serializable action (for example a swipe carrying a direction, a play-card carrying a target, a spawn-totem carrying a type); no raw pointer coordinates enter the action. In the Godot port these actions are exactly what the Match Controller accepts, what the engine step functions consume, and what the debug and MCP interfaces emit.

Because inputs are uniform messages, the same stream feeds three consumers with no special cases: the local engine for optimistic play, the validator for confirmation, and the agent interface for injection and replay. Reducing a gesture to an action also keeps coordinates out of hashed state, which reinforces the logic-and-presentation wall and protects parity.

## Consequences
POSITIVE: One input path serves play, networking, replay, and agent-driving, so each new input type is added once and is immediately networkable, testable, and drivable. It is also simply good practice for any networked game.

NEGATIVE / COST: Every input must be expressible as a serializable action, which adds a small modeling step for each new interaction and forbids shortcuts that would smuggle presentation detail (raw coordinates, hover state) into the action stream.

## Relations
_None._
