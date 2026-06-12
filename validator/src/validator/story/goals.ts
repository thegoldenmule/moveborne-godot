/**
 * Pure post-match grader: final validated state + elapsed wall-clock -> stars.
 *
 * Every input is validator-held (the state was built move-by-move through
 * executeAction; elapsed_ms comes from StoredMatch.created_at), so the client
 * cannot inflate a grade — it only chooses when to settle. Timed goals use raw
 * server wall-clock (decision 2026-06-12: a timer-suspending pause mechanic is
 * post-v1).
 */

import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";
import type { GoalResult, StoryGradeResult, StoryLevel } from "./types";

/** Highest tile value on the final board (0 for an empty/missing board).
 *  Tolerates the engine's flat tiles array carrying empty tiles as value 0. */
export function maxTileValue(state: SynchronizedGameState): number {
  const tiles = (state as { board?: { tiles?: unknown[] } }).board?.tiles;
  if (!Array.isArray(tiles)) return 0;
  let max = 0;
  for (const t of tiles) {
    const v = (t as { value?: unknown })?.value;
    if (typeof v === "number" && v > max) max = v;
  }
  return max;
}

export function gradeLevel(
  level: StoryLevel,
  finalState: SynchronizedGameState,
  elapsedMs: number,
): StoryGradeResult {
  const score = typeof finalState.score === "number" ? finalState.score : 0;
  const maxTile = maxTileValue(finalState);

  const goals: GoalResult[] = level.goals.map((goal) => {
    const value = goal.type === "points" ? score : maxTile;
    const inTime = goal.time_limit_s === null || elapsedMs <= goal.time_limit_s * 1000;
    return { goal, met: value >= goal.threshold && inTime, value };
  });

  return { stars: goals.filter((g) => g.met).length, goals };
}
