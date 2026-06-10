# Implementation plan — Virtual Currency — Coins, Souls, Gems

**Status:** draft

## Steps
- [ ] PLATFORM PROVISIONING (HUMAN GATE — prepared, not applied): validator/snapend-currency-manifest.json is ready with currencies coins/souls/gems ({name, display_name} per the inventory.Currency proto) and the user-auth exemption ({environment:dev, snap_id:inventory, method:PUT, path:/v1/inventory/users/{user_id}/currencies/{currency_name}} per auth.UserAuthRestriction). Apply with: snapctl snapend apply --manifest-path-filename validator/snapend-currency-manifest.json . NO api-key needed: the s2s transport is the snapend-internal route (SNAPEND_INVENTORY_HTTP_URL + SNAPEND_INTERNAL_HEADER as the Gateway header), auto-injected by the platform.
- [x] VALIDATOR CONFIG: Extend validator/src/validator/config.ts + types.ts with SNAPSER_GATEWAY_URL (default https://gateway.snapser.com/c4n1awfs) and SNAPSER_API_KEY (optional; awards disabled when absent so local bun run dev keeps working). Update .env.example and snapser-byosnap-profile.json env contract.
- [x] INVENTORY S2S CLIENT: New validator/src/validator/snaps/inventory.ts — InventoryClient via Bun fetch(): incrementUserCurrency(user_id, currency_name, delta_64) → PUT {gateway}/v1/inventory/users/{user_id}/currencies/{currency_name} with {delta_64} body and Api-Key header, parsing {previous_balance_64, current_balance_64}; plus getUserCurrencies(user_id) parsing currencies_64. Non-2xx → logged failure, no retry queue in v1.
- [x] REWARD TABLE: New validator/src/validator/rewards.ts — pure computeMatchRewards(mode, final_state) → MatchRewards: story → coins (score-derived placeholder), pvp → souls (flat placeholder), infinite → none; gems reserved for manual/IAP grants in v1. Bun tests beside it.
- [x] SETTLEMENT HOOK (as built — corrected from the gameStatus plan): gameStatus does NOT exist in SynchronizedGameState (it's local-tier; the engine has no game-over — main.gd's Home button is the only match-end source). Settlement is therefore an explicit, idempotent `complete_match` Socket.IO event: the client chooses WHEN to settle (on quit), the validator computes rewards from ITS OWN validated current_state + the match's stored mode (rewards_granted latch on StoredMatch prevents double-grants), awards via s2s, and acks {match_id, rewards, balances, granted}. mode rides in /api/match/init (selects only the reward table). Currency stays outside the state hash — no parity impact.
- [x] VALIDATOR VERIFY: cd validator && bun run type-check && bun run test; with the dev validator on :5555, drive a match to gameover via the validator MCP and confirm the award path logs/skips cleanly with SNAPSER_API_KEY unset.
- [ ] DEPLOY + SMOKE: Rebuild/publish the byosnap-validator image (build context = validator/) and roll with publish + snapend update (NOT sync). Smoke through the gateway with the snapser-validator skill: play a match to terminal state, GET currencies as the user and confirm increments; confirm a user-auth PUT is rejected (lockdown verification).
- [x] GODOT READ CLIENT: New game/net/inventory_client.gd (class_name MbInventory, mirroring MbSnapserAuth's HTTPRequest style): fetch_balances → await ensure_session(), GET {GATEWAY}/v1/inventory/users/{user_id}/currencies with auth_headers(), parse currencies_64 (int64 strings → int), default missing names to 0.
- [x] GAMESTATE CACHE: Extend game/ui/game_state.gd (the autoload whose comment defers currencies 'until a real feature needs them') with var currencies: Dictionary + signal currencies_changed(balances) + set_currencies() helper, keeping the plain-Dictionary convention.
- [x] CURRENCY TOP BAR: New game/ui/shell/currency_bar.gd instantiated from app_shell.gd _ready(): top-pinned band on its own CanvasLayer (NavLayer layer-5 + explicit-size pattern — Controls under CanvasLayer don't resolve wide anchors), safe-top inset, three icon+balance pairs styled per MbStyle. Lives in the shell, not the match HUD; hidden while a match covers the shell. Subscribes to GameState.currencies_changed.
- [x] REFRESH WIRING: (a) shell boot: after MbSnapserAuth.ensure_session() resolves, MbInventory.fetch_balances → GameState.set_currencies; (b) game/net/validator_client.gd: handle the match_rewards Socket.IO event and surface a signal so balances update before the shell resumes; (c) match_state.gd pop path: trigger a GET refresh on shell resume as fallback for quit-without-terminal-state. Offline play simply never receives match_rewards.
- [ ] GODOT VERIFY: filesystem_manage reimport changed .gd paths; run editor McpTestSuite via godot-ai test_run; project_run + editor_screenshot to confirm the bar renders three balances and updates after an online Story match. Run one headless parity verifier as a sanity check (no logic/ files touched).
- [x] SPEC: Author the feature-spec wiki page (Spec — Virtual Currency) from the implemented behavior: currency definitions, trust model (user-read / s2s-write), award flow, client display, and the recorded auth-lockdown + s2s transport decisions.

## Data models & interfaces
```typescript
// validator/src/validator/types.ts additions

/** The three Moveborne currencies, as provisioned in the Snapser Inventory snap (app c4n1awfs). */
export type CurrencyName = "coins" | "souls" | "gems";

/** Per-match reward computed by rewards.ts from the terminal state. */
export interface MatchRewards {
  match_id: string;
  player_id: string;
  mode: "story" | "pvp" | "infinite";
  game_status: "gameover" | "victory";
  /** Only non-zero entries are sent to the Inventory snap. int64-as-string per Snapser *_64 convention. */
  deltas: Partial<Record<CurrencyName, string>>; // e.g. { coins: "150" }
}

/** Socket.IO `match_rewards` event payload emitted after a successful s2s award. */
export interface MatchRewardsEvent {
  match_id: string;
  rewards: Partial<Record<CurrencyName, string>>;   // deltas granted
  balances: Partial<Record<CurrencyName, string>>;  // current_balance_64 per granted currency
}

// StoredMatch gains an idempotency flag (set around the s2s call so reconnect or
// replayed terminal actions never double-award):
//   rewards_granted?: boolean;

// --- Snapser Inventory snap wire shapes (snapser-docs/swagger/inventory.swagger3.json) ---

/** PUT /v1/inventory/users/{user_id}/currencies/{currency_name} — body */
export interface IncrementUserCurrencyRequest {
  delta_64: string; // int64 as string; positive grants, negative consumes
}

/** PUT response (inventoryIncrementUserCurrencyResponse) */
export interface IncrementUserCurrencyResponse {
  previous_balance_64: string;
  current_balance_64: string;
}

/** GET /v1/inventory/users/{user_id}/currencies (inventoryGetUserCurrenciesResponse) */
export interface GetUserCurrenciesResponse {
  currencies_64: Record<string, string>; // currency_name -> int64 balance as string
}

// config.ts additions (ValidatorConfig):
//   snapserGatewayUrl: string;   // SNAPSER_GATEWAY_URL, default https://gateway.snapser.com/c4n1awfs
//   snapserApiKey?: string;      // SNAPSER_API_KEY — awards disabled (logged no-op) when absent
```

```gdscript
## game/ui/game_state.gd — extension (autoload `GameState`).
## Currency balances are account data from the Snapser Inventory snap —
## NOT part of SynchronizedGameState, never hashed (hard-wall / two-tier ADRs).

## Cached balances, plain Dictionary per repo convention. int64 strings from
## currencies_64 are int()-cast on parse; missing currencies default to 0.
##   { "coins": int, "souls": int, "gems": int }
var currencies: Dictionary = {"coins": 0, "souls": 0, "gems": 0}

signal currencies_changed(balances: Dictionary)

func set_currencies(balances: Dictionary) -> void:
    currencies = balances
    currencies_changed.emit(currencies)

## game/net/inventory_client.gd — read-only client (class_name MbInventory).
## GET {MbSnapserAuth.GATEWAY}/v1/inventory/users/{user_id}/currencies
## with auth.auth_headers() (["Token: ...", "User-Id: ..."]) after
## `await auth.ensure_session()`. Parses inventoryGetUserCurrenciesResponse:
##   { "currencies_64": { "coins": "150", "souls": "3", "gems": "0" } }
## The client has NO write path — IncrementUserCurrency is locked to
## api-key/internal callers (validator only) on the platform.
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
