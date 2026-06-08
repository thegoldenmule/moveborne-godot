/**
 * Unit tests for Event Trigger State Management
 */

import { describe, it, expect } from "vitest";
import {
  initializeEventTriggerStates,
  updateTriggerStates,
  markTriggersActivated,
  resetTriggeredStates,
  getComboProgress,
  getScoreProgress,
  getMergeCountProgress,
  getMoveProgress,
  isTriggerConditionMet,
} from "../src/eventTriggerState";
import type {
  EventBasedSpawnRule,
  EventTriggerState,
  SynchronizedGameState,
} from "../src/types";
import { createGameState } from "./testHelpers";

describe("Event Trigger State Management", () => {
  // Helper to create a test game state
  function createTestGameState(
    overrides?: Partial<SynchronizedGameState>,
  ): SynchronizedGameState {
    const baseState = createGameState();
    return {
      ...baseState,
      ...overrides,
    };
  }

  describe("initializeEventTriggerStates", () => {
    it("should return undefined for empty rules array", () => {
      const gameState = createTestGameState();
      const result = initializeEventTriggerStates([], gameState);
      expect(result).toBeUndefined();
    });

    it("should create one trigger state for single rule", () => {
      const gameState = createTestGameState({ comboMultiplier: 0 });
      const rules: EventBasedSpawnRule[] = [
        {
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
        },
      ];

      const result = initializeEventTriggerStates(rules, gameState);

      expect(result).toHaveLength(1);
      expect(result![0]).toMatchObject({
        id: "trigger_0",
        trigger: { event: "COMBO_BREAK", minCombo: 3 },
        effect: "freeze",
        spawnCount: 2,
        status: "idle",
      });
      expect(result![0].progress).toEqual({ current: 0, required: 3 });
    });

    it("should create multiple trigger states with unique IDs", () => {
      const gameState = createTestGameState({ score: 100, comboMultiplier: 2 });
      const rules: EventBasedSpawnRule[] = [
        {
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
        },
        {
          trigger: { event: "SCORE_MILESTONE", threshold: 500 },
          effect: "amplify",
          spawnCount: 1,
          targetPositions: "highest_value",
        },
      ];

      const result = initializeEventTriggerStates(rules, gameState);

      expect(result).toHaveLength(2);
      expect(result![0].id).toBe("trigger_0");
      expect(result![1].id).toBe("trigger_1");
      expect(result![0].effect).toBe("freeze");
      expect(result![1].effect).toBe("amplify");
      expect(result![1].targetPositions).toBe("highest_value");
    });

    it("should calculate initial progress correctly", () => {
      const gameState = createTestGameState({
        comboMultiplier: 5,
        score: 750,
      });
      const rules: EventBasedSpawnRule[] = [
        {
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
        },
        {
          trigger: { event: "SCORE_MILESTONE", threshold: 1000 },
          effect: "amplify",
          spawnCount: 1,
        },
      ];

      const result = initializeEventTriggerStates(rules, gameState);

      expect(result![0].progress).toEqual({ current: 5, required: 3 });
      expect(result![1].progress).toEqual({ current: 750, required: 1000 });
    });

    it("should set initial status to idle", () => {
      const gameState = createTestGameState({ comboMultiplier: 10 });
      const rules: EventBasedSpawnRule[] = [
        {
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 1,
        },
      ];

      const result = initializeEventTriggerStates(rules, gameState);

      expect(result![0].status).toBe("idle");
    });
  });

  describe("updateTriggerStates", () => {
    it("should do nothing if no trigger states exist", () => {
      const gameState = createTestGameState();
      const result = updateTriggerStates(gameState);
      expect(result).toBe(gameState);
    });

    it("should transition COMBO_BREAK trigger to primed when combo >= minCombo", () => {
      const gameState = createTestGameState({ comboMultiplier: 3 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "idle",
          progress: { current: 0, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = updateTriggerStates(gameState);

      expect(result.eventTriggerStates![0].status).toBe("primed");
      expect(result.eventTriggerStates![0].progress).toEqual({
        current: 3,
        required: 3,
      });
    });

    it("should keep COMBO_BREAK trigger idle when combo < minCombo", () => {
      const gameState = createTestGameState({ comboMultiplier: 2 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "idle",
          progress: { current: 0, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = updateTriggerStates(gameState);

      expect(result.eventTriggerStates![0].status).toBe("idle");
      expect(result.eventTriggerStates![0].progress).toEqual({
        current: 2,
        required: 3,
      });
    });

    it("should update progress values correctly", () => {
      const gameState = createTestGameState({
        comboMultiplier: 5,
        score: 850,
      });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "idle",
          progress: { current: 0, required: 3 },
        },
        {
          id: "trigger_1",
          trigger: { event: "SCORE_MILESTONE", threshold: 1000 },
          effect: "amplify",
          spawnCount: 1,
          status: "idle",
          progress: { current: 0, required: 1000 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = updateTriggerStates(gameState);

      expect(result.eventTriggerStates![0].progress).toEqual({
        current: 5,
        required: 3,
      });
      expect(result.eventTriggerStates![1].progress).toEqual({
        current: 850,
        required: 1000,
      });
    });

    it("should handle multiple triggers independently", () => {
      const gameState = createTestGameState({
        comboMultiplier: 4,
        score: 500,
      });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "idle",
        },
        {
          id: "trigger_1",
          trigger: { event: "SCORE_MILESTONE", threshold: 1000 },
          effect: "amplify",
          spawnCount: 1,
          status: "idle",
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = updateTriggerStates(gameState);

      expect(result.eventTriggerStates![0].status).toBe("primed"); // combo 4 >= 3
      expect(result.eventTriggerStates![1].status).toBe("idle"); // score 500 < 1000
    });

    it("should skip triggers with triggered status", () => {
      const gameState = createTestGameState({ comboMultiplier: 5 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "triggered",
          progress: { current: 0, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = updateTriggerStates(gameState);

      // Should remain triggered (not updated to primed)
      expect(result.eventTriggerStates![0].status).toBe("triggered");
    });
  });

  describe("markTriggersActivated", () => {
    it("should do nothing if no trigger states exist", () => {
      const gameState = createTestGameState();
      const result = markTriggersActivated(gameState, [0]);
      expect(result).toBe(gameState);
    });

    it("should mark specified trigger as triggered", () => {
      const gameState = createTestGameState({ comboMultiplier: 0 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "primed",
          progress: { current: 3, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = markTriggersActivated(gameState, [0]);

      expect(result.eventTriggerStates![0].status).toBe("triggered");
    });

    it("should reset progress after activation", () => {
      const gameState = createTestGameState({ comboMultiplier: 0 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "primed",
          progress: { current: 3, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = markTriggersActivated(gameState, [0]);

      expect(result.eventTriggerStates![0].progress).toEqual({
        current: 0,
        required: 3,
      });
    });

    it("should only mark specified triggers", () => {
      const gameState = createTestGameState({ comboMultiplier: 0, score: 600 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "primed",
        },
        {
          id: "trigger_1",
          trigger: { event: "SCORE_MILESTONE", threshold: 500 },
          effect: "amplify",
          spawnCount: 1,
          status: "primed",
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = markTriggersActivated(gameState, [0]);

      expect(result.eventTriggerStates![0].status).toBe("triggered");
      expect(result.eventTriggerStates![1].status).toBe("primed"); // Unchanged
    });

    it("should handle multiple indices", () => {
      const gameState = createTestGameState({ comboMultiplier: 0 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "primed",
        },
        {
          id: "trigger_1",
          trigger: { event: "COMBO_BREAK", minCombo: 5 },
          effect: "freeze",
          spawnCount: 1,
          status: "primed",
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = markTriggersActivated(gameState, [0, 1]);

      expect(result.eventTriggerStates![0].status).toBe("triggered");
      expect(result.eventTriggerStates![1].status).toBe("triggered");
    });

    it("should ignore invalid indices", () => {
      const gameState = createTestGameState();
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "primed",
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = markTriggersActivated(gameState, [5, -1]);

      expect(result.eventTriggerStates![0].status).toBe("primed"); // Unchanged
    });
  });

  describe("resetTriggeredStates", () => {
    it("should do nothing if no trigger states exist", () => {
      const gameState = createTestGameState();
      const result = resetTriggeredStates(gameState);
      expect(result).toBe(gameState);
    });

    it("should reset triggered → idle when conditions no longer met", () => {
      const gameState = createTestGameState({ comboMultiplier: 2 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "triggered",
          progress: { current: 0, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = resetTriggeredStates(gameState);

      expect(result.eventTriggerStates![0].status).toBe("idle");
      expect(result.eventTriggerStates![0].progress).toEqual({
        current: 2,
        required: 3,
      });
    });

    it("should reset triggered → primed when conditions still met", () => {
      const gameState = createTestGameState({ comboMultiplier: 4 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "triggered",
          progress: { current: 0, required: 3 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = resetTriggeredStates(gameState);

      expect(result.eventTriggerStates![0].status).toBe("primed");
      expect(result.eventTriggerStates![0].progress).toEqual({
        current: 4,
        required: 3,
      });
    });

    it("should leave non-triggered states unchanged", () => {
      const gameState = createTestGameState({ comboMultiplier: 3 });
      const triggerStates: EventTriggerState[] = [
        {
          id: "trigger_0",
          trigger: { event: "COMBO_BREAK", minCombo: 3 },
          effect: "freeze",
          spawnCount: 2,
          status: "primed",
          progress: { current: 3, required: 3 },
        },
        {
          id: "trigger_1",
          trigger: { event: "COMBO_BREAK", minCombo: 5 },
          effect: "freeze",
          spawnCount: 1,
          status: "idle",
          progress: { current: 3, required: 5 },
        },
      ];
      gameState.eventTriggerStates = triggerStates;

      const result = resetTriggeredStates(gameState);

      expect(result.eventTriggerStates![0].status).toBe("primed"); // Unchanged
      expect(result.eventTriggerStates![1].status).toBe("idle"); // Unchanged
    });
  });

  describe("Progress Calculation Helpers", () => {
    describe("getComboProgress", () => {
      it("should return current combo and required combo", () => {
        const gameState = createTestGameState({ comboMultiplier: 5 });
        const result = getComboProgress(gameState, 3);
        expect(result).toEqual({ current: 5, required: 3 });
      });

      it("should handle combo of 0", () => {
        const gameState = createTestGameState({ comboMultiplier: 0 });
        const result = getComboProgress(gameState, 3);
        expect(result).toEqual({ current: 0, required: 3 });
      });
    });

    describe("getScoreProgress", () => {
      it("should return current score and required threshold", () => {
        const gameState = createTestGameState({ score: 750 });
        const result = getScoreProgress(gameState, 1000);
        expect(result).toEqual({ current: 750, required: 1000 });
      });

      it("should handle score of 0", () => {
        const gameState = createTestGameState({ score: 0 });
        const result = getScoreProgress(gameState, 500);
        expect(result).toEqual({ current: 0, required: 500 });
      });
    });

    describe("getMergeCountProgress", () => {
      it("should return 0 for current when totalMerges not in state", () => {
        const gameState = createTestGameState();
        const result = getMergeCountProgress(gameState, 10);
        expect(result).toEqual({ current: 0, required: 10 });
      });

      it("should return totalMerges when present in state", () => {
        const gameState = createTestGameState();
        gameState.totalMerges = 7;
        const result = getMergeCountProgress(gameState, 10);
        expect(result).toEqual({ current: 7, required: 10 });
      });
    });

    describe("getMoveProgress", () => {
      it("should return current moveIndex and required moves", () => {
        const gameState = createTestGameState({ moveIndex: 25 });
        const result = getMoveProgress(gameState, 50);
        expect(result).toEqual({ current: 25, required: 50 });
      });

      it("should handle moveIndex of 0", () => {
        const gameState = createTestGameState({ moveIndex: 0 });
        const result = getMoveProgress(gameState, 10);
        expect(result).toEqual({ current: 0, required: 10 });
      });
    });

    describe("isTriggerConditionMet", () => {
      it("should return true for COMBO_BREAK when combo >= minCombo", () => {
        const gameState = createTestGameState({ comboMultiplier: 5 });
        const result = isTriggerConditionMet(gameState, {
          event: "COMBO_BREAK",
          minCombo: 3,
        });
        expect(result).toBe(true);
      });

      it("should return false for COMBO_BREAK when combo < minCombo", () => {
        const gameState = createTestGameState({ comboMultiplier: 2 });
        const result = isTriggerConditionMet(gameState, {
          event: "COMBO_BREAK",
          minCombo: 3,
        });
        expect(result).toBe(false);
      });

      it("should return true for SCORE_MILESTONE when score >= threshold", () => {
        const gameState = createTestGameState({ score: 1000 });
        const result = isTriggerConditionMet(gameState, {
          event: "SCORE_MILESTONE",
          threshold: 1000,
        });
        expect(result).toBe(true);
      });

      it("should return false for SCORE_MILESTONE when score < threshold", () => {
        const gameState = createTestGameState({ score: 999 });
        const result = isTriggerConditionMet(gameState, {
          event: "SCORE_MILESTONE",
          threshold: 1000,
        });
        expect(result).toBe(false);
      });

      it("should return true for MERGE_COUNT when totalMerges >= count", () => {
        const gameState = createTestGameState();
        gameState.totalMerges = 15;
        const result = isTriggerConditionMet(gameState, {
          event: "MERGE_COUNT",
          count: 10,
        });
        expect(result).toBe(true);
      });

      it("should return false for MERGE_COUNT when totalMerges < count", () => {
        const gameState = createTestGameState();
        gameState.totalMerges = 5;
        const result = isTriggerConditionMet(gameState, {
          event: "MERGE_COUNT",
          count: 10,
        });
        expect(result).toBe(false);
      });

      it("should return true for MOVE_COUNT when moveIndex >= moves", () => {
        const gameState = createTestGameState({ moveIndex: 50 });
        const result = isTriggerConditionMet(gameState, {
          event: "MOVE_COUNT",
          moves: 50,
        });
        expect(result).toBe(true);
      });

      it("should return false for MOVE_COUNT when moveIndex < moves", () => {
        const gameState = createTestGameState({ moveIndex: 25 });
        const result = isTriggerConditionMet(gameState, {
          event: "MOVE_COUNT",
          moves: 50,
        });
        expect(result).toBe(false);
      });
    });
  });
});
