import type { SynchronizedGameState, GameAction } from "@spyre-io/moveborne-logic";

export type { GameAction };

// The game ⇄ validator wire types live in protos/moveborne/validator/v1/
// validator.proto (single source of truth) — see service.ts for the decoded
// request/response shapes. This module keeps server-internal types only.

export interface StoredMatch {
  match_id: string;
  current_state: SynchronizedGameState;
  player_id: string;
  mode: MatchMode;
  /** Story-mode catalog level this match plays (InitMatchRequest.level_id);
   *  absent for infinite/pvp and for story launches without a level. */
  level_id?: string;
  created_at: number;
  last_action_at: number;
  action_count: number;
  state_history: Map<number, SynchronizedGameState>;
  /** Idempotency latch for currency awards: set on the first CompleteMatch so
   *  reconnects / repeated completions never double-grant. */
  rewards_granted: boolean;
}

export interface ValidatorConfig {
  sharedSecret: string;
  matchSessionTTL: number;
  port: number;
  /** Port the gRPC ValidatorService listens on (Hermes proxies to it inside
   *  the snapend; declared as the BYOSnap profile's internal "grpc" port). */
  grpcPort: number;
  /** Public gateway base (https://gateway.snapser.com/<snapend>) — the api-key
   *  transport for Inventory s2s calls when running outside the snapend. */
  snapserGatewayUrl: string;
  /** Auth-snap api-key for s2s calls via the gateway. Optional — without it
   *  (and without the internal route) awards are a logged no-op. */
  snapserApiKey?: string;
  /** Platform-injected internal HTTP URL of the Inventory snap
   *  (SNAPEND_INVENTORY_HTTP_URL, e.g. http://service-inventory:8090/). */
  inventoryInternalUrl?: string;
  /** Platform-injected internal HTTP URL of the Storage snap
   *  (SNAPEND_STORAGE_HTTP_URL) — the story_progress blob's s2s write path. */
  storageInternalUrl?: string;
  /** Platform-injected internal-auth value (SNAPEND_INTERNAL_HEADER), sent as
   *  the `Gateway` header on internal snap-to-snap calls. */
  internalHeader?: string;
}

// ---------------------------------------------------------------------------
// Virtual currency (Snapser Inventory snap)
// ---------------------------------------------------------------------------

export type MatchMode = "story" | "pvp" | "infinite";

/** The three Moveborne currencies, as provisioned in the Inventory snap. */
export type CurrencyName = "coins" | "souls" | "gems";

/** Currency deltas granted for a completed match. int64-as-string per the
 *  Snapser *_64 convention; only non-zero entries are present. */
export type CurrencyDeltas = Partial<Record<CurrencyName, string>>;

/** PUT /v1/inventory/users/{user_id}/currencies/{currency_name} — body. */
export interface IncrementUserCurrencyRequest {
  delta_64: string;
}

/** PUT response (inventoryIncrementUserCurrencyResponse). */
export interface IncrementUserCurrencyResponse {
  previous_balance_64: string;
  current_balance_64: string;
}

/** GET /v1/inventory/users/{user_id}/currencies (inventoryGetUserCurrenciesResponse). */
export interface GetUserCurrenciesResponse {
  currencies_64: Record<string, string>;
}

export interface StateHistorySnapshot {
  moveIndex: number;
  timestamp: number;
  state: SynchronizedGameState;
}

export interface StateHistoryFile {
  id: string;
  description: string;
  created_at: string;
  match_id: string;
  player_id: string;
  states: StateHistorySnapshot[];
}

export interface ValidatorInitFromHistoryRequest {
  history_file_id?: string;
  history_data?: StateHistorySnapshot[];
  start_from_index?: number;
  player_id: string;
}
