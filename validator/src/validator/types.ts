import type { SynchronizedGameState, GameAction } from "@spyre-io/moveborne-logic";

export type { GameAction };

export interface ValidatorInitRequest {
  match_id: string;
  starting_state: SynchronizedGameState;
  player_id: string;
  signature: string;
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
  created_at: number;
  last_action_at: number;
  action_count: number;
  state_history: Map<number, SynchronizedGameState>;
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
  devMode: boolean;
}

export type ValidatorErrorCode =
  | "INVALID_SIGNATURE"
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
