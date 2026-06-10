# Testing plan — Virtual Currency — Coins, Souls, Gems

**Status:** draft

## Planned
- Gateway smoke (snapser-validator skill, deployed): anon login → GET /v1/inventory/users/{uid}/currencies returns currencies_64 containing coins/souls/gems; play an online Story match to terminal state → balance incremented by the expected delta
- Lockdown negative test (deployed): PUT /v1/inventory/users/{uid}/currencies/coins with user Token/User-Id headers is rejected (401/403) — proving only api-key/internal callers can award
- Godot client (McpTestSuite via godot-ai test_run): MbInventory parses currencies_64 int64 strings to ints and defaults missing currencies to 0; GameState.set_currencies emits currencies_changed and the bar labels update
- Godot shell visual (project_run + editor_screenshot): currency bar renders three balances at top with safe-top inset, hidden while a match covers the shell, refreshed on shell resume after match pop and on match_rewards from validator_client.gd
- Auth-race / expiry: fetch before login completes waits on ensure_session(); expired cached session in user://snapser_session.json refreshes then succeeds (no 401 surfaced to UI)

## Passed
- rewards.ts unit (bun test): story victory yields coins delta derived from final state, pvp victory yields souls, infinite yields no deltas; gameover vs victory cases; zero-delta currencies omitted from the s2s calls
- InventoryClient unit (bun test, mocked fetch): PUT body is {delta_64: string} with Api-Key header to {gateway}/v1/inventory/users/{uid}/currencies/{name}; parses previous/current_balance_64; non-2xx → error result without throwing into the validation pipeline
- Award idempotency (local :5555, as built): init a match (mode=story, score in starting state), connect Socket.IO, emit complete_match twice — first ack grants {coins: floor(score/10)} computed from the VALIDATOR'S state, second ack returns empty rewards (rewards_granted latch); get_match_state/list_matches shows rewards_granted=true
- Local no-credentials degrade: with SNAPSER_API_KEY unset, terminal state logs an award skip and validate_action responses are unchanged (hash flow unaffected)
- Parity sanity: run a headless verifier (e.g. verify_engine_swipe.gd → PASS) confirming no logic/ or hash behavior changed

## Failed
_None._

## References
_None._

## Child pages
_None._
