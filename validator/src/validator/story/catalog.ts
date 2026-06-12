/**
 * The story catalog: loaded from the committed validator/content/
 * story_catalog.json — the SAME file that is uploaded verbatim to the Remote
 * Config snap (app-config, key "story_catalog") and baked into the game client
 * at res://story/story_catalog.json. One source of truth; catalog_version
 * detects drift between the three surfaces.
 */

import rawCatalog from "../../../content/story_catalog.json" with { type: "json" };
import type { StoryCatalog, StoryLevel } from "./types";

const catalog = rawCatalog as StoryCatalog;

/** Worlds sorted by order, each with levels sorted by order — the canonical
 *  unlock chain. Computed once; the catalog is immutable at runtime. */
const orderedLevels: StoryLevel[] = [...catalog.worlds]
  .sort((a, b) => a.order - b.order)
  .flatMap((w) => [...w.levels].sort((a, b) => a.order - b.order));

const levelsById = new Map(orderedLevels.map((l) => [l.id, l]));

export function getCatalog(): StoryCatalog {
  return catalog;
}

export function getLevel(levelId: string): StoryLevel | undefined {
  return levelsById.get(levelId);
}

export function getOrderedLevelIds(): string[] {
  return orderedLevels.map((l) => l.id);
}

/** Sanity-check the catalog shape; throws with every problem found. Run from
 *  tests (and once at startup) so a malformed edit fails loudly, not as NaN
 *  grades in production. */
export function validateCatalog(c: StoryCatalog = catalog): void {
  const problems: string[] = [];
  if (!Number.isInteger(c.catalog_version) || c.catalog_version < 1) {
    problems.push("catalog_version must be a positive integer");
  }
  const ids = new Set<string>();
  for (const world of c.worlds ?? []) {
    for (const level of world.levels ?? []) {
      const tag = `${world.id}/${level.id}`;
      if (ids.has(level.id)) problems.push(`${tag}: duplicate level id`);
      ids.add(level.id);
      if (!Number.isInteger(level.scenario_id) || level.scenario_id < 0) {
        problems.push(`${tag}: bad scenario_id`);
      }
      if (!Array.isArray(level.goals) || level.goals.length !== 3) {
        problems.push(`${tag}: must have exactly 3 goals`);
        continue;
      }
      for (const goal of level.goals) {
        if (goal.type !== "points" && goal.type !== "max_tile") {
          problems.push(`${tag}: bad goal type '${goal.type}'`);
        }
        if (!(goal.threshold > 0)) problems.push(`${tag}: goal threshold must be > 0`);
        if (goal.time_limit_s !== null && !(goal.time_limit_s > 0)) {
          problems.push(`${tag}: time_limit_s must be null or > 0`);
        }
      }
      if (!Array.isArray(level.rewards?.per_star) || level.rewards.per_star.length !== 3) {
        problems.push(`${tag}: rewards.per_star must have exactly 3 entries`);
      }
    }
  }
  if (problems.length > 0) {
    throw new Error(`story catalog invalid:\n  ${problems.join("\n  ")}`);
  }
}
