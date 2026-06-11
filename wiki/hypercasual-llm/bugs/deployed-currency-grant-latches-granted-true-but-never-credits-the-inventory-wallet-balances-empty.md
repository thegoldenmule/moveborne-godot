# Bug: Deployed currency grant latches granted=true but never credits the Inventory wallet (balances empty)

**Status:** open

## Report
- **Component:** Validator → Inventory snap (currency awards, snap-to-snap)
- **Platform:** Snapser deployed snapend c4n1awfs (byosnap-validator)
- **Version:** v0.2.4 (pre-existing: the award path is unchanged by the gRPC/Hermes refactor — same code since the virtual-currency feature, commit 644612c)

## Summary
On the deployed snapend, completing a match settles the reward correctly (CompleteMatch returns rewards={coins:"N"}, granted=true) but the coins never appear in the player's Inventory wallet, and the response's balances map is empty. The validator's s2s call to the Inventory snap (InventoryClient.incrementUserCurrency, PUT /v1/inventory/users/{userId}/currencies/{currency} with body {delta_64}, internal transport with the Gateway header) is returning null — i.e. a non-2xx or a thrown error — which the validator logs ([inventory] increment ... failed) but deliberately swallows so a failed award never breaks validation (idempotency latch is set BEFORE the grant). Net effect: granted=true is reported even though nothing was credited, and the wallet stays empty. Reward COMPUTATION is correct (coins = floor(score/10)); only the s2s WRITE fails. Reproduced twice with fresh anonymous users plus once during the deployed E2E. Only manifests deployed — locally awards resolve to "disabled" (no s2s creds), so local tests pass with granted=false and never exercise this path. NOTE: granted reflects "awards transport enabled", not "award actually applied" — a secondary issue making the failure invisible to the client.

## Repro steps
1. Anonymous login to the gateway (PUT https://gateway.snapser.com/c4n1awfs/v1/auth/login/anon) to get user_id + session_token.
2. Open the Hermes WSS (wss://gateway.snapser.com/c4n1awfs/v1/hermes/ws?token=<session>); send InitMatch with a starting state, then a ValidateAction or two so the validated score is > 0 (e.g. score 80).
3. Send CompleteMatch. Response: {match_id, rewards: {coins: "8"}, balances: {}, granted: true}. (rewards is computed from the validator's validated state; coins = floor(80/10) = 8.)
4. GET https://gateway.snapser.com/c4n1awfs/v1/inventory/users/<user_id>/currencies with the session Token/User-Id headers → {"currencies":{},"currencies_64":{}} (empty). The 8 coins were never credited.
5. Repeat with a brand-new anonymous user → identical result (empty wallet, granted=true). /api/status reports awards: "internal", confirming the s2s transport resolved (SNAPEND_INVENTORY_HTTP_URL + SNAPEND_INTERNAL_HEADER are injected).

## Expected result
After CompleteMatch with granted=true, the player's Inventory wallet reflects the granted currency: GET .../currencies shows currencies_64.coins incremented by the reward amount, and the CompleteMatchResponse.balances map carries current_balance_64 per granted currency (incrementUserCurrency returns the new balance, which completeMatch copies into balances).

## Observed result
The wallet stays empty and balances is {}. incrementUserCurrency is returning null, which means the internal PUT to the Inventory snap either returned non-2xx or threw. The actual cause is in the deployed container log line `[inventory] increment coins for <userId> failed: HTTP <status> <body>` (or the catch-branch error) — TRIAGE STEP: read that line from the byosnap-validator pod logs. Leading hypotheses to check against that log: (a) the "coins"/"souls"/"gems" currencies are not provisioned in the snapend's Inventory snap config, so the PUT 404s/400s; (b) the internal endpoint path or body shape is wrong for this Inventory snap version (expected PUT /v1/inventory/users/{id}/currencies/{currency} with {delta_64}); (c) the internal-auth `Gateway: <SNAPEND_INTERNAL_HEADER>` header is not what the Inventory snap accepts for an internal s2s write (it may require api-key, gRPC metadata, or a different header). Secondary fix regardless of root cause: make CompleteMatch's `granted` reflect whether the grant actually succeeded (incrementUserCurrency returned non-null), not merely that the transport is enabled, so the client/HUD can tell a real grant from a silent failure.

## Resolution
_None._

## References
_None._

## Child pages
_None._
