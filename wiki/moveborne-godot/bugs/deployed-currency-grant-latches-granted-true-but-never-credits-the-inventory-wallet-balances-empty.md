# Bug: Deployed currency grant latches granted=true but never credits the Inventory wallet (balances empty)

**Status:** closed

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
The wallet stays empty and balances is {}. incrementUserCurrency is returning null (non-2xx from the Inventory snap), which the validator logs and deliberately swallows. ROOT CAUSE CONFIRMED (2026-06-11): the snapend's Inventory snap has NO currencies provisioned — the live manifest (snapctl snapend download --category snapend-manifest --snapend-id c4n1awfs) shows applied_configuration → settings[inventory].data.currencies = [] — so every PUT /v1/inventory/users/{id}/currencies/coins fails. Hypotheses (b) and (c) are ruled out: the endpoint path, {delta_64} body, and internal auth type were verified against the vendored inventory swagger (IncrementUserCurrency, x-snapser-auth-types includes "internal"; the docs' intra-snapend example passes SNAPEND_INTERNAL_HEADER as the gateway header, exactly what InventoryClient sends). FIX 1 (config, pending): provision coins/souls/gems in the Inventory snap config (manifest settings[inventory].data.currencies = [{name, display_name}…] + snapctl snapend apply). FIX 2 (code, committed 94f3a0f, v0.2.5): CompleteMatch granted now reflects whether every reward actually credited (any incrementUserCurrency null flips granted=false) instead of merely "transport enabled". SIDE FINDING for hardening: IncrementUserCurrency also accepts plain user auth (x-snapser-auth-types: user/api-key/internal), so any logged-in client can self-grant currency through the gateway — should be restricted via the Auth snap's user_auth_restrictions for a server-authoritative economy.

## Resolution
- `94f3a0fcc99fd0049b3f36bca6672c046ff839fd` fix(validator): CompleteMatch granted=true only when the Inventory credit actually lands (v0.2.5). Root cause was config, not code: snapend c4n1awfs had currencies:[] in the Inventory snap — provisioned coins/souls/gems via snapctl snapend apply. Deployed E2E verified 2026-06-11: CompleteMatch → rewards {coins:25}, granted=true, balances {coins:25}, wallet REST read-back 25 (regression test game/tools/test_snapser_grant.gd, commit b500fdb).

## References
_None._

## Child pages
_None._
