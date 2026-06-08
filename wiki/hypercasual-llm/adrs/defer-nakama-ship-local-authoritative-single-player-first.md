# ADR-4: Defer Nakama; ship local-authoritative single-player first

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Server / Networking
- **Deciders:** Benjamin Jordan

## Context
A 15-agent investigation of the moveborne backend surfaced two facts. First, `src/server` is a Nakama runtime module with reusable infra (device auth, Turnkey/Movement web3 wallet, matchmaking, glicko2, leaderboards, economy) — but its in-match handler is still named `"hangman"` with hangman opcodes and contains **no** tile-merge gameplay (a rename/fork in progress). Second, the reference web client doesn't play through Nakama match opcodes at all — it plays the gameplay loop through the **Validator** (Socket.IO), with Nakama only signing the start and accepting validated moves. Building a Moveborne Nakama match handler is real, open-ended work.

## Decision
Front-load a fully-playable local-authoritative single-player build with no backend dependency, then add online play via the Validator afterward. Defer Nakama (auth, matchmaking, economy, and a Moveborne match handler); the Server architecture node is a documented stub. The local build is identical in logic to the eventual networked build, so it is not throwaway work.

## Consequences
POSITIVE: A shippable, valuable single-player game exists immediately with no server to stand up. The validator path proves the determinism contract end-to-end against a real service. Nakama's reusable infra remains available to adopt later unchanged.

NEGATIVE / COST: No accounts, matchmaking, leaderboards, or economy in v1. The intended long-term online authority (Validator plus Nakama orchestration, versus a new Nakama match handler) is recorded as an open question, not yet resolved.

## Relations
_None._
