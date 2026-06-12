/**
 * Transport-agnostic validator service — the single implementation behind
 * every transport (gRPC server, Hermes snap-api proxy, local /hermes/ws
 * emulation). Handlers take a decoded request + the caller's gateway-bound
 * identity and return plain response objects; transports own (de)serialization
 * and error mapping.
 *
 * The action-execution semantics here are determinism-parity critical and
 * must mirror the GDScript engine exactly: RNG construction from the stored
 * state, score accumulation on top of executeAction's result, and the
 * moveIndex advance of +1 (+2 when a card was auto-drawn).
 */
import {
  computeStateHash,
  executeAction,
  RandomGenerator,
  type GameAction,
  type SynchronizedGameState,
} from "@spyre-io/moveborne-logic";
import type { MatchStateStore } from "./store/match-state";
import type { CurrencyDeltas, CurrencyName, MatchMode, StoredMatch } from "./types";
import { getConfig } from "./config";
import { signValidatorResponse } from "./utils/crypto";
import { verifySnapserCaller } from "./utils/snapser-auth";
import { computeMatchRewards } from "./rewards";
import type { InventoryClient } from "./snaps/inventory";
import { StorageClient, STORY_PROGRESS_KEY } from "./snaps/storage";
import { getCatalog, getLevel } from "./story/catalog";
import { gradeLevel, maxTileValue } from "./story/goals";
import { applyGrade, emptyProgress } from "./story/progress";
import type { StoryProgress, StoryResult } from "./story/types";
import type { RpcName } from "./proto";

/** Gateway-stamped caller headers (lowercased keys), regardless of transport:
 *  HTTP headers, gRPC metadata, or the local WS emulation's token mapping. */
export type CallerHeaders = Record<string, string | string[] | undefined>;

/** gRPC status codes used by the service (subset). */
export const GrpcStatus = {
  INVALID_ARGUMENT: 3,
  NOT_FOUND: 5,
  PERMISSION_DENIED: 7,
  INTERNAL: 13,
} as const;

export class ServiceError extends Error {
  constructor(
    public readonly code: number,
    message: string,
  ) {
    super(message);
    this.name = "ServiceError";
  }
}

// Wire shapes (post-decode). Mirrors protos/moveborne/validator/v1/validator.proto.
export interface InitMatchRequest {
  match_id: string;
  starting_state_json: string;
  player_id: string;
  mode: string;
  /** Story-mode catalog level id (e.g. "w1_l3"); empty for other modes. */
  level_id?: string;
}
export interface InitMatchResponse {
  match_id: string;
  current_state_json: string;
  expires_at: number;
}
export interface ValidateActionRequest {
  match_id: string;
  index: number;
  action_json: string;
  state_hash: string;
}
export interface ValidateActionResponse {
  index: number;
  matched: boolean;
  state_json: string;
  signature: string;
}
export interface CompleteMatchRequest {
  match_id: string;
}
export interface CompleteMatchResponse {
  match_id: string;
  rewards: Record<string, string>;
  balances: Record<string, string>;
  granted: boolean;
  /** Story grading result (canonical JSON, see story/types.ts StoryResult);
   *  empty for non-story matches and for already-settled completions. */
  story_result_json: string;
}

export class ValidatorService {
  constructor(
    private readonly store: MatchStateStore,
    private readonly inventory: InventoryClient,
    private readonly storage: StorageClient = new StorageClient({ kind: "disabled" }),
  ) {}

  async initMatch(req: InitMatchRequest, caller: CallerHeaders): Promise<InitMatchResponse> {
    const { match_id, starting_state_json, player_id } = req;
    if (!match_id || !starting_state_json || !player_id) {
      throw new ServiceError(
        GrpcStatus.INVALID_ARGUMENT,
        "Missing required fields: match_id, starting_state_json, player_id",
      );
    }

    const auth = verifySnapserCaller(caller, player_id);
    if (!auth.ok) {
      throw new ServiceError(GrpcStatus.PERMISSION_DENIED, auth.reason);
    }

    // A match_id is owned by its first initializer. Reject a re-init by anyone
    // else: match ids are a small client-chosen space, so without this guard an
    // authenticated user could clobber a victim's in-progress match (resetting
    // its state, history, and the rewards latch). The old Socket.IO handshake
    // enforced this owner binding; the gRPC/Hermes init path must too. Same-owner
    // re-init stays allowed (the game always mints a fresh id, so this is benign).
    const existing = await this.store.get(match_id);
    if (existing && existing.player_id !== player_id) {
      throw new ServiceError(GrpcStatus.PERMISSION_DENIED, "match_id already owned by another player");
    }

    let starting_state: SynchronizedGameState;
    try {
      starting_state = JSON.parse(starting_state_json);
    } catch {
      throw new ServiceError(GrpcStatus.INVALID_ARGUMENT, "starting_state_json is not valid JSON");
    }
    if (typeof starting_state !== "object" || starting_state === null || !("board" in starting_state)) {
      throw new ServiceError(GrpcStatus.INVALID_ARGUMENT, "starting_state_json is not a game state");
    }

    const mode: MatchMode = req.mode === "pvp" || req.mode === "infinite" ? req.mode : "story";
    const config = getConfig();
    const now = Date.now();
    const expires_at = now + config.matchSessionTTL * 1000;

    const state_history = new Map<number, SynchronizedGameState>();
    state_history.set(starting_state.moveIndex, starting_state);

    // Bind the story level at registration so grading cannot be re-aimed at a
    // different level after the fact. Unknown ids are rejected up front — the
    // alternative (silently grading nothing) reads as a lost reward later.
    const level_id = mode === "story" && req.level_id ? req.level_id : undefined;
    if (level_id && !getLevel(level_id)) {
      throw new ServiceError(GrpcStatus.INVALID_ARGUMENT, `unknown story level_id '${level_id}'`);
    }
    // The starting state is CLIENT-supplied, so a story level must register a
    // fresh one — otherwise a caller inits a pre-scored / pre-merged board and
    // settles instantly for stars. score==0 + moveIndex==0 force points goals
    // through validated actions; the tile cap (64 — the largest fixed tile any
    // scenario places, High Stakes) does the same for max_tile goals. Exact
    // scenario-board reconstruction needs the scenario table server-side
    // (documented follow-up hardening).
    if (level_id) {
      const fresh =
        starting_state.score === 0 &&
        starting_state.moveIndex === 0 &&
        maxTileValue(starting_state) <= 64;
      if (!fresh) {
        throw new ServiceError(
          GrpcStatus.INVALID_ARGUMENT,
          "story matches must register a fresh scenario starting state",
        );
      }
    }

    const storedMatch: StoredMatch = {
      match_id,
      current_state: starting_state,
      player_id,
      mode,
      level_id,
      created_at: now,
      last_action_at: now,
      action_count: 0,
      state_history,
      rewards_granted: false,
    };
    await this.store.set(match_id, storedMatch, config.matchSessionTTL);

    console.log(
      `Match initialized: ${match_id} for player ${player_id} (mode=${mode}${level_id ? `, level=${level_id}` : ""})`,
    );

    return {
      match_id,
      current_state_json: JSON.stringify(starting_state),
      expires_at,
    };
  }

  async validateAction(req: ValidateActionRequest, caller: CallerHeaders): Promise<ValidateActionResponse> {
    const { match_id, index, action_json, state_hash } = req;
    const config = getConfig();

    const match = await this.store.get(match_id);
    if (!match) {
      throw new ServiceError(GrpcStatus.NOT_FOUND, "Match not found");
    }

    const auth = verifySnapserCaller(caller, match.player_id);
    if (!auth.ok) {
      throw new ServiceError(GrpcStatus.PERMISSION_DENIED, auth.reason);
    }

    // The action must apply to the move the server is actually on. In honest
    // sequential play the client's pre-action moveIndex always equals the
    // server's current moveIndex (a hash mismatch still leaves the indices
    // equal — the client adopts the authoritative state and resumes from its
    // moveIndex). Rejecting any other index closes a replay/dup-frame vector:
    // proto3 decodes an omitted index as 0, which would otherwise re-execute an
    // early action against late-game state and clobber state_history[0..].
    if (index !== match.current_state.moveIndex) {
      throw new ServiceError(
        GrpcStatus.INVALID_ARGUMENT,
        `stale action index ${index} (current moveIndex is ${match.current_state.moveIndex})`,
      );
    }

    let action: GameAction;
    try {
      action = JSON.parse(action_json);
    } catch {
      throw new ServiceError(GrpcStatus.INVALID_ARGUMENT, "action_json is not valid JSON");
    }

    const rng = new RandomGenerator(
      match.current_state.randomSeeds,
      match.current_state.rngIndices,
    );

    const executionResult = executeAction(match.current_state, action, rng);
    if (!executionResult.success) {
      throw new ServiceError(
        GrpcStatus.INVALID_ARGUMENT,
        executionResult.error || "Action execution failed",
      );
    }

    // executionResult.newState has shards and card draw already applied, but
    // score accumulates from the previous state; moveIndex advances +1, or +2
    // when a card was auto-drawn (mirrors the client engine exactly).
    const newState: SynchronizedGameState = {
      ...executionResult.newState,
      score: executionResult.newState.score + (executionResult.scoreAdded || 0),
      rngIndices: rng.getIndices(),
      moveIndex: index + (executionResult.cardDrawn ? 2 : 1),
    };

    match.state_history.set(newState.moveIndex, newState);

    const computedHash = computeStateHash(newState);
    const signature = signValidatorResponse(match_id, index, action, computedHash, config.sharedSecret);
    const matched = computedHash === state_hash;

    match.current_state = newState;
    match.action_count += 1;
    match.last_action_at = Date.now();
    await this.store.set(match_id, match, config.matchSessionTTL);

    console.log(`Action validated: match=${match_id}, index=${index}, hash_match=${matched}`);

    return {
      index,
      matched,
      state_json: matched ? "" : JSON.stringify(newState),
      signature,
    };
  }

  // Match settlement. The engine has no game-over — the client's quit IS the
  // match end — so completion is an explicit, idempotent call. The client only
  // chooses WHEN to settle; rewards come from the validator's own validated
  // state via the reward table, so the grant cannot be inflated.
  async completeMatch(req: CompleteMatchRequest, caller: CallerHeaders): Promise<CompleteMatchResponse> {
    const { match_id } = req;
    const config = getConfig();

    const match = await this.store.get(match_id);
    if (!match) {
      throw new ServiceError(GrpcStatus.NOT_FOUND, "Match not found");
    }

    const auth = verifySnapserCaller(caller, match.player_id);
    if (!auth.ok) {
      throw new ServiceError(GrpcStatus.PERMISSION_DENIED, auth.reason);
    }

    if (match.rewards_granted) {
      return { match_id, rewards: {}, balances: {}, granted: false, story_result_json: "" };
    }

    // Latch BEFORE the s2s calls so a racing duplicate completion can't
    // double-grant; a failed upstream call costs the player the award rather
    // than risking a dupe (acceptable for v1 — no retry queue).
    match.rewards_granted = true;
    await this.store.set(match_id, match, config.matchSessionTTL);

    // Story: grade the validator's own final state + wall-clock against the
    // catalog goals, then read-merge-write the progress blob BEFORE granting —
    // if the rewarded_stars watermark doesn't land, the grant is withheld
    // (a replay would otherwise re-mint the same star tiers). A story match
    // without a level grants nothing (catalog rewards fully replaced the old
    // score-derived table); other modes keep the flat reward table.
    let rewards: CurrencyDeltas = {};
    let storyResultJson = "";
    let progressPersisted = true;
    const level = match.mode === "story" && match.level_id ? getLevel(match.level_id) : undefined;
    if (level) {
      const catalog = getCatalog();
      const grade = gradeLevel(level, match.current_state, Date.now() - match.created_at);
      const previous =
        (await this.storage.getJsonBlob<StoryProgress>(match.player_id, STORY_PROGRESS_KEY)) ??
        emptyProgress(catalog);
      const applied = applyGrade(
        previous,
        level,
        grade,
        match.current_state.score ?? 0,
        catalog,
        new Date().toISOString(),
      );
      progressPersisted =
        this.storage.enabled &&
        (await this.storage.putJsonBlob(match.player_id, STORY_PROGRESS_KEY, applied.progress));
      if (progressPersisted) {
        rewards = applied.rewards;
      }
      const storyResult: StoryResult = {
        level_id: level.id,
        stars: grade.stars,
        goals: grade.goals,
        new_stars: applied.newStars,
        rewards: progressPersisted ? (applied.rewards as Record<string, string>) : {},
        next_level_id: applied.nextLevelId,
        unlocked: applied.unlocked,
      };
      storyResultJson = JSON.stringify(storyResult);
    } else if (match.mode !== "story") {
      rewards = computeMatchRewards(match.mode, match.current_state);
    }

    const balances: CurrencyDeltas = {};
    // granted must mean "every computed reward was actually credited" — not
    // merely "the awards transport is enabled". A swallowed s2s failure
    // (e.g. a currency missing from the snapend's Inventory config) would
    // otherwise report success while the wallet stays empty. For story, the
    // progress write is part of the grant.
    let granted = this.inventory.enabled && (level === undefined || progressPersisted);
    if (this.inventory.enabled) {
      for (const [currency, delta] of Object.entries(rewards)) {
        const result = await this.inventory.incrementUserCurrency(
          match.player_id,
          currency as CurrencyName,
          delta,
        );
        if (result) {
          balances[currency as CurrencyName] = result.current_balance_64;
        } else {
          granted = false;
        }
      }
    }

    console.log(
      `Match completed: ${match_id} (mode=${match.mode}${level ? `, level=${level.id}` : ""}, score=${match.current_state.score})`,
      { rewards, balances, granted },
    );

    return {
      match_id,
      rewards: rewards as Record<string, string>,
      balances: balances as Record<string, string>,
      granted,
      story_result_json: storyResultJson,
    };
  }
}

/** The RPC name → handler map every transport dispatches through, so the gRPC
 *  server and the Hermes emulation can never bind a different set of methods. */
export function rpcHandlers(
  service: ValidatorService,
): Record<RpcName, (req: any, caller: CallerHeaders) => Promise<unknown>> {
  return {
    InitMatch: (req, caller) => service.initMatch(req, caller),
    ValidateAction: (req, caller) => service.validateAction(req, caller),
    CompleteMatch: (req, caller) => service.completeMatch(req, caller),
  };
}
