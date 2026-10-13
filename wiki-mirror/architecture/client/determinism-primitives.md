# Determinism Primitives

**Status:** current

## Kind
subsystem

## Summary
The bit-exact foundation everything else stands on: a seedrandom@3.0.5 ARC4 PRNG, a 5-namespace RNG manager, and a custom rolling state hash over canonical (json-stable-stringify) JSON. These three reproduce the TS number/RNG/serialization behavior exactly so hashes match.

## Purpose
Guarantee that identical inputs produce identical bytes across GDScript and TypeScript. `rng.gd` reimplements seedrandom's ARC4 to 53-bit-double precision; `random_generator.gd` manages the 5 named draw streams (`tile-gen`, `shuffle`, `effect-spawn`, `totem-spawn`, `card-draw`) seeded by integer→string and restored by reseed+replay; `hasher.gd` canonicalizes state (sorted keys, 2-space, JS number format) and rolls the same hash the validator computes.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- `game/logic/rng.gd`
- `game/logic/random_generator.gd`
- class `MbHasher` in `game/logic/hasher.gd`

## Data model
_None._

## Usage
Consumed only by the Rules Engine — never by scenes. The engine draws from `MbRandomGenerator` in the exact order/count the TS does per namespace, then calls `MbHasher.hash(state)` on the result.

**GDScript gotchas:** `str(float)` caps at ~14 sig-digits; use `MbHasher._num_float` (shortest round-trip, JS-compatible) for any hashed float and keep integral values as `int`. `%g`/`%.17g` are invalid in GDScript formatting.

## Invariants & constraints
- RNG draw order and count per namespace must match the TS exactly; restoring state means reseed + replay to the stored index, not snapshotting internal ARC4 state.
- Floats that enter the hash must use the shortest round-trip (JS-compatible) formatting via MbHasher._num_float; integral state values stay int.

## Synced commit
85f64c0
