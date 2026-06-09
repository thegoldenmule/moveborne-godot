# ADR-17: Authenticate BYOSnap requests by trusting gateway-stamped User-Id, not signatures

**Status:** accepted

## Metadata
- **Date:** 2026-06-09
- **Scope:** Server / Validator / Auth
- **Deciders:** Benjamin Jordan

## Context
Adopting Snapser (ADR-16) forced a rethink of how the Validator authenticates inbound match-init. The original scheme was an HMAC-SHA256 "Nakama signature" over `(match_id, starting_state, player_id)` keyed by a shared secret, verified on `/init` and skipped under a `DEV_MODE` flag. Two facts make that the wrong fit for Snapser: (1) requests reach a BYOSnap **only** through the gateway, which already validates the caller's session token against the Auth snap and forwards plain identity headers — `User-Id` (the validated user), `Auth-Type` (user / api-key), `Gateway` (external / internal); and (2) Snapser exposes **no JWKS or signed claim** for a service to verify a token offline. So there is nothing to cryptographically check, but there is a gateway-asserted identity to trust — provided the gateway strips and re-stamps those reserved headers from external callers.

## Decision
Replace the signature check with a gateway-trust check (verifySnapserCaller). On match-init, match-init-from-history, and the Socket.IO handshake, require the gateway-validated User-Id header to equal the request's claimed player id. Callers the gateway marks as api-key or internal (snap-to-snap) carry no user context and pass without a user binding. The legacy signature field is now ignored. Outbound response signing (HMAC over the Validator's ACK or mismatch) is unchanged — this decision is only about inbound trust.

Trust the headers because of two operational invariants: (a) the BYOSnap has no ingress except the gateway (private snapend network), and (b) the gateway sanitizes and re-stamps client-supplied User-Id and Gateway headers. Invariant (b) was verified live against the deployed snapend: a request carrying a real session token but a forged User-Id header (and matching forged player id) was rejected 401, because the gateway overwrote the forged User-Id with the real validated user; a forged Gateway: internal header was likewise stripped. So a player cannot impersonate another user or escalate to an internal caller.

Remove the dev-mode bypass flag entirely. The auth check runs unconditionally, so there is no prod-only branch that local runs never exercise, and no flag that, set wrong, silently disables all inbound auth. Locally there is no gateway, so direct callers self-stamp a User-Id equal to their player id (the game's local path, the run-validator script, and the headless test all do this); there the check is a no-op consistency check, not real auth, which is acceptable because a dev machine has no adversary to bind against.

## Consequences
POSITIVE: No shared secret to distribute or rotate for inbound auth, and no signing code on the client. One code path is tested everywhere (local and deployed), removing the dev-only-untested-branch risk and the footgun where the old bypass flag, left on in prod, disabled all auth. The identity the Validator binds is the same one the rest of the snapend trusts, so a future move-relay or leaderboard write lines up with no extra mapping.

NEGATIVE / COST: Security now rests on two operational invariants rather than cryptography. If the container is ever given direct ingress that bypasses the gateway, or is fronted by anything that does not sanitize the reserved identity headers, any caller can claim any user. There is no offline or standalone verification: the Validator cannot be exercised against real auth without the gateway in front (covered locally by self-stamped headers, which assert nothing). The trust-the-gateway invariant must be re-checked whenever the deployment topology changes.

## Relations
_None._
