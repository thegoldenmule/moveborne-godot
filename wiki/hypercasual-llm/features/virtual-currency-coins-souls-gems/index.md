# Feature: Virtual Currency — Coins, Souls, Gems

**Status:** review

## Summary
Add three virtual currencies to Moveborne — coins (soft), souls (PvP), gems (hard) — backed by the Snapser Inventory snap on app c4n1awfs, which already exposes the needed REST surface (verified in snapser-docs/swagger/inventory.swagger3.json): GET /v1/inventory/users/{user_id}/currencies returns a currencies_64 map (currency_name → int64 string) and PUT /v1/inventory/users/{user_id}/currencies/{currency_name} increments via {delta_64}, both with x-snapser-auth-types [user, api-key, internal]. The Godot client reads balances with its existing anonymous-session headers (MbSnapserAuth.auth_headers() → Token + User-Id, gateway-validated 'user' auth) and displays them in a new persistent top bar in the app shell (game/ui/shell/app_shell.gd, mirroring the bottom NavLayer CanvasLayer-5 pattern), cached in the GameState autoload — whose own comment reserves currencies as the intended extension point. Awards are server-authoritative: the validator BYOSnap detects terminal gameStatus (gameover/victory) in its validate_action pipeline, computes mode-based rewards, and makes an s2s HTTP PUT to the Inventory snap as a trusted non-user caller (api-key or internal — the same trust classes its own verifySnapserCaller() accepts without player binding), then emits a match_rewards Socket.IO event so the client updates the bar immediately. The increment endpoint is locked down on the Snapser platform side so 'user' callers cannot self-award; clients keep read access via the normal inventory GET endpoints.

## Components affected
- Snapser platform config (app c4n1awfs): Inventory snap in the snapend; currencies coins/souls/gems provisioned; IncrementUserCurrency 'user' auth disabled; api-key minted for the validator
- validator/src/validator/snaps/inventory.ts — new InventoryClient (Bun fetch, api-key/internal headers, increment + get-balances)
- validator/src/validator/rewards.ts — pure reward table: (mode, terminal state) → MatchRewards
- validator/src/validator/index.ts — terminal-gameStatus detection in the validate_action Socket.IO handler + match_rewards emit
- validator/src/validator/types.ts + config.ts + .env.example + snapser-byosnap-profile.json — MatchRewards/wire types, rewards_granted flag, SNAPSER_GATEWAY_URL / SNAPSER_API_KEY
- game/net/inventory_client.gd (MbInventory) — gateway GET of currencies_64 using MbSnapserAuth session headers
- game/ui/game_state.gd — currencies Dictionary cache + currencies_changed signal (the explicitly reserved extension point)
- game/ui/shell/currency_bar.gd + app_shell.gd integration — persistent top bar on its own CanvasLayer (NavLayer pattern), safe-top inset, three icon+balance widgets in MbStyle
- game/net/validator_client.gd + game/ui/router/match_state.gd — match_rewards event handling and balance refresh on shell resume
- Currency icons (coins/souls/gems) via the artgen MCP, occult-arcade style

## Design constraints
1. Currencies must be pre-provisioned in the Snapser Inventory snap config — the swagger has no currency-creation endpoint; the validator can only increment names that already exist on c4n1awfs
2. Award lockdown is platform config, not code: the swagger marks PUT IncrementUserCurrency as user|api-key|internal, so 'user' auth must be disabled on that endpoint in the snap configuration or any client with a session token could self-award
3. Currency balances must stay OUT of SynchronizedGameState and game/logic/ — they are unhashed account data (hard-wall and two-tier-state ADRs); no parity/golden vectors may change
4. Validator is TypeScript/Hono on Bun — s2s via HTTP fetch with *_64 string fields (int64 precision), not the metagame's Go gRPC stubs; use non-deprecated 64-bit fields (delta_64/currencies_64), never the int32 variants
5. Awards must be idempotent per match (rewards_granted flag on StoredMatch) — Socket.IO reconnects and replayed terminal actions must not double-grant
6. Local dev (V-key, :5555) and Infinite mode run without the gateway/api-key — the award path must degrade to a logged no-op, never crash validation; don't kill the bun --watch process
7. Client reads use gateway 'user' auth only (Token + User-Id from MbSnapserAuth); fetches must await ensure_session() (auth race + token-TTL refresh already handled there)
8. Shell layout gotcha: Controls under a CanvasLayer don't resolve wide anchors to the viewport — the top bar needs explicit sizing + safe-top inset like NavBar (app_shell.gd) and main.gd's _top_safe_inset()
9. BYOSnap deploy contract: build context = validator/, container :8080, BYOSNAP_BASE_PATH prefix preserved; roll out with publish + snapend update, NOT sync (known snapctl bug)
10. The currency bar lives in the app shell, not scenes/main.gd's match HUD — the in-match top band is fully occupied (Home, MOVES/SCORE/SHARDS, net label) and the shell is covered during matches anyway
11. Repo conventions: commit directly to main; after editing .gd files, filesystem_manage reimport; editor suites via godot-ai test_run; parity sanity check with a headless verifier even though logic/ is untouched

## Open questions
1. **Reward economy numbers: coins per Story result (flat or score-scaled?), souls per PvP win (and loss?), and whether gems are validator-awardable at all in v1 or reserved for IAP/manual grants. Pure game design — implementation proceeds with placeholder values (score-derived coins for Story, flat souls for PvP win, no gem awards) that are trivial to retune in rewards.ts.**

## Resolved questions
1. **S2S transport: HTTPS to the public gateway with an api-key, or internal snap-to-snap inside the snapend? To be verified against the live platform during platform provisioning; plan defaults to gateway+api-key as lowest friction.** — _Internal snap-to-snap, confirmed in the platform docs (Intra Snapend Networking): every snapend injects SNAPEND_INVENTORY_HTTP_URL (http://service-inventory:8090/) and SNAPEND_INTERNAL_HEADER into BYOSnap containers; internal calls hit the same REST paths with the header value sent as `Gateway`. The InventoryClient auto-selects: internal → gateway+api-key (SNAPSER_API_KEY) → disabled (logged no-op, local dev). No api-key needs to be minted; no env changes to the BYOSnap profile._
2. **Can the Inventory snap's IncrementUserCurrency endpoint have 'user' auth disabled per-endpoint in Snapser configuration? If not, the lockdown requirement cannot be met as specified and the trust model needs rethinking. To be verified during platform provisioning.** — _Yes — the Auth snap's 'User Auth Exemptions' tool exists exactly for this (its own docs use inventory granting as the motivating example). In the snapend manifest it is auth settings user_auth_restrictions: {environment, snap_id: inventory, method: PUT, path: /v1/inventory/users/{user_id}/currencies/{currency_name}} (shape confirmed against the auth.UserAuthRestriction proto). Prepared in validator/snapend-currency-manifest.json; verify with the deployed lockdown negative test after apply._
3. **Quit-in-progress awards: match_exited fires on player quit before gameStatus reaches a terminal value — plan default is to award nothing on quit; partial rewards would need a new completion route. Flag if you want quit rewards in v1.** — _Superseded by an engineering fact: the engine has no game-over at all — the quit (Home) button is the ONLY match-end source (main.gd). So settlement happens ON quit via an explicit idempotent complete_match event, and rewards are score-derived from the validator's own validated state — quitting early just settles a smaller validated score; nothing is client-claimable. If a real terminal state lands later, the same settlement path applies unchanged._
4. **Offline earnings: Infinite is always offline and local-validator play has no credentials — plan default is zero earnings offline (client-side queued grants would be a trust hole). Flag if offline earnings are wanted.** — _Zero earnings offline, as planned: Infinite never connects, local V-key play resolves the disabled transport (no credentials) and completion is a logged no-op. No client-side grant queue (trust hole)._
5. **Should balances also appear inside the match HUD (its top band is already tight with MOVES/SCORE/SHARDS), or shell-only as planned?** — _Shell-only, as built: the bar is a CanvasLayer band in the app shell, hidden while a match covers it (the match HUD top band stays untouched). Balances update optimistically from the complete_match ack and authoritatively on every shell resume._

## References
_None._

## Child pages
- [Implementation plan — Virtual Currency — Coins, Souls, Gems](implementation-plan:mq8j3xyq-001a-4m4rl4)
- [Testing plan — Virtual Currency — Coins, Souls, Gems](testing-plan:mq8j3xyq-001b-d7flut)
- [Spec — Virtual Currency — Coins, Souls, Gems](feature-spec:mq8j3xyq-001c-qwt9z2)

## Commits
- `644612c` feat(currency): coins/souls/gems — validator-awarded via Inventory snap s2s, client top bar
- `3006840` virtual currency and lb spec updates
