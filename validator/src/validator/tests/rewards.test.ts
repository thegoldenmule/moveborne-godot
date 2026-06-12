import { describe, expect, test } from "bun:test";
import { computeMatchRewards } from "../rewards";
import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";

function stateWithScore(score: number): SynchronizedGameState {
  // The reward table only reads `score`; the rest is irrelevant scaffolding.
  return { score } as unknown as SynchronizedGameState;
}

describe("computeMatchRewards", () => {
  test("story: nothing from the flat table — catalog star rewards own story", () => {
    // Decision 2026-06-12: catalog per-star rewards fully replaced the old
    // floor(score/10) placeholder; story grants flow through story/progress.ts.
    expect(computeMatchRewards("story", stateWithScore(1530))).toEqual({});
    expect(computeMatchRewards("story", stateWithScore(0))).toEqual({});
  });

  test("pvp: flat souls per completed match", () => {
    expect(computeMatchRewards("pvp", stateWithScore(9999))).toEqual({ souls: "1" });
    expect(computeMatchRewards("pvp", stateWithScore(0))).toEqual({ souls: "1" });
  });

  test("infinite: no rewards", () => {
    expect(computeMatchRewards("infinite", stateWithScore(100000))).toEqual({});
  });

  test("gems are never validator-awarded", () => {
    for (const mode of ["story", "pvp", "infinite"] as const) {
      expect(computeMatchRewards(mode, stateWithScore(123456)).gems).toBeUndefined();
    }
  });
});
