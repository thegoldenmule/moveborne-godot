/**
 * Story-mode types: the level catalog, post-match grading, and per-user
 * progress. All of this lives OUTSIDE the determinism hash domain — grading
 * reads the final validated SynchronizedGameState but never changes engine
 * state, scenario configs, or anything hashed.
 */

import type { CurrencyName } from "../types";

export type StoryGoalType = "points" | "max_tile";

export interface StoryGoal {
  type: StoryGoalType;
  /** points: final score >= threshold; max_tile: highest tile value >= threshold. */
  threshold: number;
  /** When set, the goal only counts if the match settled within this many seconds. */
  time_limit_s: number | null;
}

/** Catalog reward amounts are plain numbers (the *_64 string convention is a
 *  wire/Inventory concern; summed deltas are stringified at the grant edge). */
export type StoryRewardAmounts = Partial<Record<CurrencyName, number>>;

export interface StoryLevel {
  id: string;
  order: number;
  /** Existing MbScenarios id — the engine config is untouched by story mode. */
  scenario_id: number;
  name: string;
  goals: StoryGoal[];
  rewards: {
    complete: StoryRewardAmounts;
    per_star: StoryRewardAmounts[];
  };
}

export interface StoryWorld {
  id: string;
  name: string;
  order: number;
  levels: StoryLevel[];
}

export interface StoryCatalog {
  catalog_version: number;
  worlds: StoryWorld[];
}

export interface GoalResult {
  goal: StoryGoal;
  met: boolean;
  /** The graded value (final score for points goals, max tile for max_tile goals). */
  value: number;
}

export interface StoryGradeResult {
  /** Count of goals met: 1 goal = 1 star, all 3 = 3 stars. */
  stars: number;
  goals: GoalResult[];
}

/** One level's entry in the per-user progress blob. Stars are max-monotonic;
 *  rewarded_stars is the idempotency watermark (replays grant only star tiers
 *  ABOVE it, so a worse or repeated run can never re-mint rewards). */
export interface LevelProgress {
  stars: number;
  best_score: number;
  rewarded_stars: number;
  completed_at?: string;
}

/** The Storage-snap json-blob (`story_progress`), written ONLY by the
 *  validator via s2s; the client reads it to render the map. */
export interface StoryProgress {
  catalog_version: number;
  levels: Record<string, LevelProgress>;
  /** First level (in catalog order) not yet completed with >=1 star. */
  next_level_id: string;
}

/** The story_result_json payload returned in CompleteMatchResponse. */
export interface StoryResult {
  level_id: string;
  stars: number;
  goals: GoalResult[];
  /** Stars newly earned ABOVE the previous watermark (0 on a non-improving replay). */
  new_stars: number;
  /** Currency deltas granted for this completion (int64-as-string). */
  rewards: Record<string, string>;
  next_level_id: string;
  /** True when this completion advanced the unlock frontier. */
  unlocked: boolean;
}
