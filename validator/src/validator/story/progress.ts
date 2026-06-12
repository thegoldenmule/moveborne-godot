/**
 * Pure progress-merge logic for the per-user story_progress blob.
 *
 * Invariants (the anti-forgery/idempotency core):
 *   - stars are max-monotonic: a worse replay never lowers a level's stars
 *   - rewarded_stars never decreases: replays grant only NEWLY earned tiers
 *   - the completion reward is granted exactly once (first time stars >= 1)
 *   - next_level_id is recomputed from the catalog order (self-healing if the
 *     catalog gains/reorders levels between sessions)
 *
 * The Storage-snap transport lives in ../snaps/storage.ts; this module never
 * does I/O so the merge semantics are trivially unit-testable.
 */

import type { CurrencyDeltas, CurrencyName } from "../types";
import { getOrderedLevelIds } from "./catalog";
import type {
  LevelProgress,
  StoryCatalog,
  StoryGradeResult,
  StoryLevel,
  StoryProgress,
  StoryRewardAmounts,
} from "./types";

export function emptyProgress(catalog: StoryCatalog): StoryProgress {
  return {
    catalog_version: catalog.catalog_version,
    levels: {},
    next_level_id: getOrderedLevelIds()[0] ?? "",
  };
}

/** First level (catalog order) not yet completed with >=1 star; "" when done. */
export function computeNextLevel(levels: Record<string, LevelProgress>): string {
  for (const id of getOrderedLevelIds()) {
    if ((levels[id]?.stars ?? 0) < 1) return id;
  }
  return "";
}

/** A level is playable when it sits at or before the unlock frontier. */
export function isLevelUnlocked(levels: Record<string, LevelProgress>, levelId: string): boolean {
  const ordered = getOrderedLevelIds();
  const index = ordered.indexOf(levelId);
  if (index < 0) return false;
  const frontier = computeNextLevel(levels);
  if (frontier === "") return true; // everything completed
  return index <= ordered.indexOf(frontier);
}

export interface AppliedGrade {
  progress: StoryProgress;
  /** Stars newly earned above the previous watermark (drives the grant). */
  newStars: number;
  /** Summed currency deltas for the newly earned tiers (+ first completion). */
  rewards: CurrencyDeltas;
  /** True when this completion advanced the unlock frontier. */
  unlocked: boolean;
  nextLevelId: string;
}

function addAmounts(into: Record<string, number>, amounts: StoryRewardAmounts | undefined): void {
  for (const [currency, amount] of Object.entries(amounts ?? {})) {
    if (typeof amount === "number" && amount > 0) {
      into[currency] = (into[currency] ?? 0) + amount;
    }
  }
}

export function applyGrade(
  previous: StoryProgress,
  level: StoryLevel,
  grade: StoryGradeResult,
  finalScore: number,
  catalog: StoryCatalog,
  nowIso: string,
): AppliedGrade {
  const prev: LevelProgress = previous.levels[level.id] ?? {
    stars: 0,
    best_score: 0,
    rewarded_stars: 0,
  };

  const newStars = Math.max(0, grade.stars - prev.rewarded_stars);
  const totals: Record<string, number> = {};
  if (prev.stars < 1 && grade.stars >= 1) {
    addAmounts(totals, level.rewards.complete);
  }
  for (let tier = prev.rewarded_stars; tier < grade.stars; tier++) {
    addAmounts(totals, level.rewards.per_star[tier]);
  }

  const merged: LevelProgress = {
    stars: Math.max(prev.stars, grade.stars),
    best_score: Math.max(prev.best_score, finalScore),
    rewarded_stars: Math.max(prev.rewarded_stars, grade.stars),
  };
  if (merged.stars >= 1) {
    merged.completed_at = prev.completed_at ?? nowIso;
  }

  const levels = { ...previous.levels, [level.id]: merged };
  const prevNext = computeNextLevel(previous.levels);
  const nextLevelId = computeNextLevel(levels);

  const rewards: CurrencyDeltas = {};
  for (const [currency, total] of Object.entries(totals)) {
    rewards[currency as CurrencyName] = String(total);
  }

  return {
    progress: { catalog_version: catalog.catalog_version, levels, next_level_id: nextLevelId },
    newStars,
    rewards,
    // "" means everything is complete — the frontier moved, but there is no
    // next level to announce as unlocked.
    unlocked: nextLevelId !== prevNext && nextLevelId !== "",
    nextLevelId,
  };
}
