import { describe, expect, test } from "bun:test";
import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";
import { gradeLevel, maxTileValue } from "../story/goals";
import type { StoryGoal, StoryLevel } from "../story/types";

function state(score: number, tileValues: number[] = []): SynchronizedGameState {
  return {
    score,
    board: { size: 4, tiles: tileValues.map((value, i) => ({ value, position: { row: 0, col: i } })) },
  } as unknown as SynchronizedGameState;
}

function level(goals: StoryGoal[]): StoryLevel {
  return {
    id: "test_l1",
    order: 0,
    scenario_id: 0,
    name: "Test",
    goals,
    rewards: { complete: {}, per_star: [{}, {}, {}] },
  };
}

const POINTS_100: StoryGoal = { type: "points", threshold: 100, time_limit_s: null };
const TILE_64: StoryGoal = { type: "max_tile", threshold: 64, time_limit_s: null };
const TIMED_100_60S: StoryGoal = { type: "points", threshold: 100, time_limit_s: 60 };

describe("maxTileValue", () => {
  test("highest tile value, tolerating empty tiles (value 0)", () => {
    expect(maxTileValue(state(0, [0, 2, 64, 4, 0]))).toBe(64);
  });

  test("empty or missing board -> 0", () => {
    expect(maxTileValue(state(0, []))).toBe(0);
    expect(maxTileValue({ score: 0 } as unknown as SynchronizedGameState)).toBe(0);
  });
});

describe("gradeLevel", () => {
  test("points goal met exactly at the threshold boundary", () => {
    const l = level([POINTS_100, POINTS_100, POINTS_100]);
    expect(gradeLevel(l, state(100), 0).stars).toBe(3);
    expect(gradeLevel(l, state(99), 0).stars).toBe(0);
  });

  test("max_tile goal derives from the final board", () => {
    const l = level([TILE_64, POINTS_100, POINTS_100]);
    const grade = gradeLevel(l, state(0, [2, 64]), 0);
    expect(grade.goals[0]!.met).toBe(true);
    expect(grade.goals[0]!.value).toBe(64);
    expect(grade.stars).toBe(1);
  });

  test("timed goal passes at the limit and fails above it", () => {
    const l = level([TIMED_100_60S, POINTS_100, TILE_64]);
    expect(gradeLevel(l, state(150), 60_000).goals[0]!.met).toBe(true);
    expect(gradeLevel(l, state(150), 60_001).goals[0]!.met).toBe(false);
    // The untimed points goal still counts — time only gates its own goal.
    expect(gradeLevel(l, state(150), 60_001).stars).toBe(1);
  });

  test("stars == count of goals met, for every 0..3 combination", () => {
    const l = level([POINTS_100, { type: "points", threshold: 500, time_limit_s: null }, TILE_64]);
    expect(gradeLevel(l, state(50), 0).stars).toBe(0);
    expect(gradeLevel(l, state(100), 0).stars).toBe(1);
    expect(gradeLevel(l, state(500), 0).stars).toBe(2);
    expect(gradeLevel(l, state(500, [64]), 0).stars).toBe(3);
  });
});
