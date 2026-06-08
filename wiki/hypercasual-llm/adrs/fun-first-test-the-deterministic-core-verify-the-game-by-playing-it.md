# ADR-15: Fun-first — test the deterministic core, verify the game by playing it

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Project / Testing
- **Deciders:** Benjamin Jordan

## Context
Software is usually spec-first; games are fun-first. You build something and play it before you even know what the game is, and for the life of the game perception matters more than correctness — a shader that looks cool because it mangles precision, a physics sim with no relation to reality, a camera that slerps to points of interest. Driving an LLM with an airtight spec eventually collapses into writing code in English. And you cannot meaningfully unit-test fun: a triple-A action game might sit near **5%** coverage. So automated tests cannot be the universal evaluation metric for a game — but they are exactly right for the narrow, correctness-bearing core.

## Decision
Apply automated testing strategically, only where the value clearly outweighs the cost: the pure, deterministic reducer core (merge, scoring, RNG, hashing, card and totem logic). That core is consolidated as a library of pure functions, so it is cheap to test and high-value to get exactly right, and it is where golden-vector parity testing lives. Do not attempt to unit-test the game itself — feel, juice, VFX, and pacing are out of scope for automated tests.

Verify everything above the core by playing it. A feature is confirmed when the agent or the human loads a scenario, performs the inputs, and observes the actual behavior from a player's perspective. Prototyping is hands-first: build the thing, play it, then decide what it is, rather than specifying it to death up front.

## Consequences
POSITIVE: Test effort concentrates where it pays off (the parity-critical core), and the rest of the game stays free to be tuned by feel without fighting brittle tests. The agent still gets a tight feedback loop everywhere through play-and-observe, so coverage gaps do not block progress.

NEGATIVE / COST: Large parts of the game have little or no automated coverage, so presentation and game-feel regressions are caught by playing, not by CI. Deciding where the bang outweighs the buck is a judgment call, and verify-by-playing depends on the driveability surface staying healthy.

## Relations
_None._
