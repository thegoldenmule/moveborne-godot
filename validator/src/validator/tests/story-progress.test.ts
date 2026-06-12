import { describe, expect, test } from "bun:test";
import { getCatalog, getLevel, getOrderedLevelIds, validateCatalog } from "../story/catalog";
import { gradeLevel } from "../story/goals";
import {
  applyGrade,
  computeNextLevel,
  emptyProgress,
  isLevelUnlocked,
} from "../story/progress";
import type { StoryGradeResult } from "../story/types";

const catalog = getCatalog();
const L1 = getLevel("w1_l1")!;

function stars(n: number): StoryGradeResult {
  return {
    stars: n,
    goals: L1.goals.map((goal, i) => ({ goal, met: i < n, value: 0 })),
  };
}

const NOW = "2026-06-12T00:00:00Z";

describe("committed catalog", () => {
  test("validates, with 45 levels in 3 worlds and w1_l1 first", () => {
    expect(() => validateCatalog()).not.toThrow();
    expect(catalog.worlds.length).toBe(3);
    const ids = getOrderedLevelIds();
    expect(ids.length).toBe(45);
    expect(ids[0]).toBe("w1_l1");
    expect(ids[15]).toBe("w2_l1");
  });
});

describe("applyGrade", () => {
  test("first 2-star completion grants complete + tiers 0..1 and watermarks", () => {
    const applied = applyGrade(emptyProgress(catalog), L1, stars(2), 700, catalog, NOW);
    // w1_l1: complete {coins:30}, per_star [{coins:12},{coins:24},{coins:36}]
    expect(applied.rewards).toEqual({ coins: String(30 + 12 + 24) });
    expect(applied.newStars).toBe(2);
    const entry = applied.progress.levels["w1_l1"]!;
    expect(entry).toMatchObject({ stars: 2, best_score: 700, rewarded_stars: 2, completed_at: NOW });
    expect(applied.nextLevelId).toBe("w1_l2");
    expect(applied.unlocked).toBe(true);
  });

  test("improving replay 2->3 grants only the new tier", () => {
    const first = applyGrade(emptyProgress(catalog), L1, stars(2), 700, catalog, NOW);
    const second = applyGrade(first.progress, L1, stars(3), 900, catalog, NOW);
    expect(second.rewards).toEqual({ coins: "36" });
    expect(second.newStars).toBe(1);
    expect(second.progress.levels["w1_l1"]).toMatchObject({
      stars: 3,
      best_score: 900,
      rewarded_stars: 3,
    });
    // Frontier was already past this level; an improvement does not re-unlock.
    expect(second.unlocked).toBe(false);
  });

  test("worse replay grants nothing and never lowers stars or best score", () => {
    const first = applyGrade(emptyProgress(catalog), L1, stars(3), 900, catalog, NOW);
    const replay = applyGrade(first.progress, L1, stars(1), 300, catalog, NOW);
    expect(replay.rewards).toEqual({});
    expect(replay.newStars).toBe(0);
    expect(replay.progress.levels["w1_l1"]).toMatchObject({
      stars: 3,
      best_score: 900,
      rewarded_stars: 3,
    });
  });

  test("a 0-star run records best_score but neither completes nor unlocks", () => {
    const applied = applyGrade(emptyProgress(catalog), L1, stars(0), 120, catalog, NOW);
    expect(applied.rewards).toEqual({});
    const entry = applied.progress.levels["w1_l1"]!;
    expect(entry.stars).toBe(0);
    expect(entry.best_score).toBe(120);
    expect(entry.completed_at).toBeUndefined();
    expect(applied.nextLevelId).toBe("w1_l1");
    expect(applied.unlocked).toBe(false);
  });
});

describe("unlock chain", () => {
  test("computeNextLevel walks catalog order; '' when everything is complete", () => {
    expect(computeNextLevel({})).toBe("w1_l1");
    expect(computeNextLevel({ w1_l1: { stars: 1, best_score: 1, rewarded_stars: 1 } })).toBe("w1_l2");
    const all: Record<string, { stars: number; best_score: number; rewarded_stars: number }> = {};
    for (const id of getOrderedLevelIds()) {
      all[id] = { stars: 1, best_score: 1, rewarded_stars: 1 };
    }
    expect(computeNextLevel(all)).toBe("");
  });

  test("isLevelUnlocked: frontier and everything before it; locked beyond", () => {
    expect(isLevelUnlocked({}, "w1_l1")).toBe(true);
    expect(isLevelUnlocked({}, "w1_l2")).toBe(false);
    const after1 = { w1_l1: { stars: 2, best_score: 1, rewarded_stars: 2 } };
    expect(isLevelUnlocked(after1, "w1_l1")).toBe(true); // replays allowed
    expect(isLevelUnlocked(after1, "w1_l2")).toBe(true);
    expect(isLevelUnlocked(after1, "w1_l3")).toBe(false);
    expect(isLevelUnlocked(after1, "not_a_level")).toBe(false);
  });
});
