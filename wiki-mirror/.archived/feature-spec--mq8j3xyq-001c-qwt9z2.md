# Spec — Virtual Currency — Coins, Souls, Gems

**Status:** sealed

## Overview
Three virtual currencies — coins (soft), souls (PvP), gems (hard) — backed by the Snapser Inventory snap on c4n1awfs. Clients READ balances with their normal anonymous-session user auth and render them in a persistent top bar in the app shell. WRITES are server-authoritative: the increment endpoint is locked away from user auth (User Auth Exemptions), and only the validator BYOSnap awards currency, over the snapend-internal s2s route, with amounts computed from its own validated match state.

## Design
## Trust model

Read path: game client to gateway (Token + User-Id headers) to an Inventory GET. Write path: validator to the platform-injected internal Inventory URL with the internal header sent as the Gateway header; gateway api-key is the configured fallback and local dev degrades to a logged no-op. The lockdown lives in platform config, not code — without it any session token could self-award, which is why the deployed lockdown negative test (a user-auth PUT must come back 401/403) is part of the testing plan.

## Settlement flow

```text
The engine has no game-over; quitting (Home) is the only match end.

quit pressed (game/scenes/main.gd)
  -> emit complete_match over the existing Socket.IO session (idempotent)
  -> validator (validator/src/validator/index.ts):
       match = store.get(match_id)            // mode captured at /api/match/init
       if match.rewards_granted: ack empty    // latch: reconnects never double-grant
       match.rewards_granted = true           // latched BEFORE the s2s calls
       rewards = computeMatchRewards(match.mode, match.current_state)
         story    -> coins = floor(score / 10)   // from the VALIDATOR'S validated state
         pvp      -> souls = 1
         infinite -> nothing; gems never validator-awarded (IAP/manual only)
       for each non-zero delta: PUT .../currencies/{name} {delta_64}
       ack {match_id, rewards, balances, granted}
  -> client merges acked balances into GameState immediately
  -> shell re-reads all balances on resume (reconciliation fallback)

Currency is account data OUTSIDE SynchronizedGameState: hashes and parity
vectors are untouched (hard-wall / two-tier-state ADRs).
```

## Client display

The currency bar is a CanvasLayer band pinned below the top safe inset (explicit sizing — Controls under a CanvasLayer do not resolve wide anchors), with three glyph-plus-amount slots: coins gold, souls violet, gems cyan — glyph placeholders pending generated occult-arcade icons. Hidden with the shell during matches; renders from the GameState currency cache via its change signal.

## Decisions
S2S transport: snapend-internal HTTP (platform-injected Inventory URL + internal header sent as the Gateway header), with gateway api-key as the configured fallback and a logged no-op when neither credential exists. Zero manual key management. S2S transport: HTTPS to the public gateway with an api-key, or internal snap-to-snap inside the snapend? To be verified against the live platform during platform provisioning; plan defaults to gateway+api-key as lowest friction.

Lockdown via the Auth snap User Auth Exemptions: a restriction entry for the increment-currency PUT, prepared in the snapend currency manifest in the validator directory and applied as platform config. Can the Inventory snap's IncrementUserCurrency endpoint have 'user' auth disabled per-endpoint in Snapser configuration? If not, the lockdown requirement cannot be met as specified and the trust model needs rethinking. To be verified during platform provisioning.

Settlement on quit via an explicit idempotent complete-match event — the quit IS the match end (no engine game-over), and score-derived rewards from validator-validated state make early-quit self-limiting rather than exploitable. Quit-in-progress awards: match_exited fires on player quit before gameStatus reaches a terminal value — plan default is to award nothing on quit; partial rewards would need a new completion route. Flag if you want quit rewards in v1.

Offline play earns nothing: Infinite never connects and the local validator runs with the disabled transport. No client-side pending-grant queue. Offline earnings: Infinite is always offline and local-validator play has no credentials — plan default is zero earnings offline (client-side queued grants would be a trust hole). Flag if offline earnings are wanted.

Balances display shell-only (typical F2P top bar); the in-match HUD keeps its existing MOVES/SCORE/SHARDS band untouched. Should balances also appear inside the match HUD (its top band is already tight with MOVES/SCORE/SHARDS), or shell-only as planned?

v1 reward economy ships with the placeholder values: Story awards floor(score/10) coins computed from the validator's own validated state, PvP awards 1 soul on a win (nothing on loss), and gems are never validator-awarded (reserved for IAP/manual grants). Real economy numbers remain a game-design tuning task; retuning is a pure-table change in the validator rewards module plus a BYOSnap redeploy. Reward economy numbers: coins per Story result (flat or score-scaled?), souls per PvP win (and loss?), and whether gems are validator-awardable at all in v1 or reserved for IAP/manual grants. Pure game design — implementation proceeds with placeholder values (score-derived coins for Story, flat souls for PvP win, no gem awards) that are trivial to retune in rewards.ts.

## References
_None._

## Child pages
_None._
