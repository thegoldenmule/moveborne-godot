# ADR-1: Byte-for-byte determinism parity with the canonical TS engine

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Rules Engine / Determinism Primitives
- **Deciders:** Benjamin Jordan

## Context
Moveborne's online play model has the client run the game logic locally and the Validator (which reuses the canonical TS `@spyre-io/moveborne-logic`) re-derive state and a **state hash** to confirm or correct each move. For a Godot/GDScript client to participate in that model — and ideally to play against the **unchanged** validator — the GDScript engine must compute the *same* hash as the TS engine for the same inputs.

Three things drive the hash and are easy to get subtly wrong across languages: the PRNG (`seedrandom@3.0.5` ARC4), the state hash (a custom 8-lane rolling hash, *not* real SHA-256 despite the name), and canonical JSON (`json-stable-stringify`). Number-to-string formatting and RNG draw order/count are the highest-risk landmines.

## Decision
Port the rules engine to be byte-for-byte deterministically identical to the TS engine. Reproduce exactly: (1) the seedrandom 3.0.5 default ARC4 returning a 53-bit double (resolved empirically versus the 32-bit variant), with state restored by reseed plus replay of N draws rather than an opaque blob; (2) the custom 8-lane rolling hash, lanes h0 through h7 seeded from the SHA-256 IVs, each UTF-8 byte folding via h becomes (h shifted left by k, minus h, plus byte) wrapped to signed 32-bit across shifts 5,7,11,13,17,19,23,29, each lane emitted as zero-padded 8-hex; and (3) a hand-written canonical serializer with keys sorted by UTF-16 code unit at every depth, two-space pretty-print, arrays preserved in order, missing optionals omitted, and numbers via JS String(n) where ints carry no trailing point-zero and floats take shortest round-trip form.

Hashes match across GDScript, the TS engine, and the validator for every action. RNG draw order and count per namespace, the moveIndex increments (plus 2 on auto-draw, else plus 1), and caller-applied score accumulation are mirrored exactly. Integral state stays an int; the only non-integer hashed floats (globalEffects filterConfig) use shortest-round-trip formatting via the MbHasher float helper.

## Consequences
POSITIVE: The Godot client plays against the real validator service with no server changes, and the optimistic fast-path hits every move (mismatches only on a genuine port bug). The same golden vectors exercise both engines.

NEGATIVE / COST: The engine is frozen against casual refactoring; any behavior change must be re-proven with golden vectors before commit. The team carries GDScript-specific hazards (float str() precision, no percent-g formatting, signed-32-bit emulation) as permanent constraints. Determinism is a UX and polish axis rather than a correctness gate — an imperfect port still snaps to authoritative state — but the project treats it as load-bearing.

## Relations
_None._
