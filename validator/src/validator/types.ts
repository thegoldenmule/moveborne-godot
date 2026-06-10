import type { SynchronizedGameState, GameAction } from "@spyre-io/moveborne-logic";

export type { GameAction };

export interface ValidatorInitRequest {
  match_id: string;
  starting_state: SynchronizedGameState;
  player_id: string;
  /** Which play mode this match settles rewards for. Defaults to "story".
   *  Self-reported by the client, but it only selects the reward TABLE —
   *  reward amounts come from the validator's own validated state. */
  mode?: MatchMode;
  /** Legacy Nakama HMAC field — ignored; auth is the Snapser gateway's
   *  validated User-Id header (see utils/snapser-auth.ts). */
  signature?: string;
}

export interface ValidatorInitResponse {
  connection_id: string;
  expires_at: number;
}

export interface GameActionRequest {
  index: number;
  action: GameAction;
  state_hash: string;
}

export interface GameActionResponseMatch {
  index: number;
  signature: string;
}

export interface GameActionResponseMismatch {
  index: number;
  state: SynchronizedGameState;
  signature: string;
}

export type GameActionResponse = GameActionResponseMatch | GameActionResponseMismatch;

export interface StoredMatch {
  match_id: string;
  current_state: SynchronizedGameState;
  connection_id: string;
  player_id: string;
  mode: MatchMode;
  created_at: number;
  last_action_at: number;
  action_count: number;
  state_history: Map<number, SynchronizedGameState>;
  /** Idempotency latch for currency awards: set on the first complete_match so
   *  reconnects / repeated completions never double-grant. */
  rewards_granted: boolean;
}

export interface ConnectionToken {
  connection_id: string;
  match_id: string;
  player_id: string;
  issued_at: number;
  expires_at: number;
}

export interface ValidatorConfig {
  sharedSecret: string;
  connectionTokenTTL: number;
  matchSessionTTL: number;
  port: number;
  /** Public gateway base (https://gateway.snapser.com/<snapend>) — the api-key
   *  transport for Inventory s2s calls when running outside the snapend. */
  snapserGatewayUrl: string;
  /** Auth-snap api-key for s2s calls via the gateway. Optional — without it
   *  (and without the internal route) awards are a logged no-op. */
  snapserApiKey?: string;
  /** Platform-injected internal HTTP URL of the Inventory snap
   *  (SNAPEND_INVENTORY_HTTP_URL, e.g. http://service-inventory:8090/). */
  inventoryInternalUrl?: string;
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

/** Ack payload for the `complete_match` Socket.IO event. */
export interface MatchRewardsResponse {
  match_id: string;
  /** Deltas the reward table produced for this match (empty if none or if the
   *  match was already settled). */
  rewards: CurrencyDeltas;
  /** current_balance_64 per granted currency, when the Inventory snap call
   *  succeeded; empty when awards are disabled (no s2s credentials). */
  balances: CurrencyDeltas;
  /** False when this completion did not settle (already settled earlier, or
   *  s2s awards are disabled in this environment). */
  granted: boolean;
}

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

export type ValidatorErrorCode =
  | "UNAUTHORIZED"
  | "MATCH_NOT_FOUND"
  | "INVALID_TOKEN"
  | "TOKEN_EXPIRED"
  | "INVALID_ACTION"
  | "PLAYER_MISMATCH";

export interface ValidatorError {
  code: ValidatorErrorCode;
  message: string;
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
