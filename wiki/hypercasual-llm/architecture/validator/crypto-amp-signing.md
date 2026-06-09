# Crypto &amp; Signing

**Status:** current

## Kind
subsystem

## Summary
`utils/crypto.ts` — HMAC-SHA256 signing/verification over canonical serialization, plus connection-id/UUID generation. Two signature shapes: the inbound Nakama init signature `(match_id, starting_state, player_id)` and the outbound validator response `(match_id, index, action, state_hash)`.

## Purpose
Establish trust at both ends of the loop. `verifyNakamaSignature` gates `/init` (skipped in DEV_MODE) so only the server can start a match; `signValidatorResponse` signs every ACK/mismatch so the downstream server can accept validated actions without re-simulating. All HMACs are computed over `canonicalStringify(data)` from the logic package and compared with `timingSafeEqual`.

## Design notes
_None._

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- function `signValidatorResponse` in `validator/src/validator/utils/crypto.ts`
- interface `ValidatorConfig` in `validator/src/validator/config.ts`

## Data model
_None._

## Usage
`computeHmacSignature(data, secret)` / `verifyHmacSignature`; the typed wrappers `signNakamaPayload` / `verifyNakamaSignature` and `signValidatorResponse` / `verifyValidatorSignature`. Secret comes from `VALIDATOR_SHARED_SECRET` (config). Generate a production secret with `openssl rand -hex 32`.

## Invariants & constraints
- Signing canonicalization MUST match the client/engine's (canonicalStringify) byte-for-byte, or a correct state would fail verification. Comparison is constant-time (timingSafeEqual).

## Synced commit
ada25ef
