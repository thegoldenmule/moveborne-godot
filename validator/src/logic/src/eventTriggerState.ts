/**
 * Event Trigger State Management
 *
 * Manages synchronized state for event-based spawn triggers to enable visual indicators.
 * Tracks trigger status (idle/primed/triggered) and progress for UI display.
 */

import type {
  EventBasedSpawnRule,
  EventTrigger,
  EventTriggerState,
  SynchronizedGameState,
} from "./types";

/**
 * Initialize event trigger states from scenario event rules
 * @param eventRules Array of event-based spawn rules from scenario config
 * @param gameState Current game state (for initial progress calculation)
 * @returns Array of EventTriggerState objects, or undefined if no rules
 */
export function initializeEventTriggerStates(
  eventRules: EventBasedSpawnRule[],
  gameState: SynchronizedGameState,
): EventTriggerState[] | undefined {
  if (!eventRules || eventRules.length === 0) {
    return undefined;
  }

  return eventRules.map((rule, index) => {
    const triggerState: EventTriggerState = {
      id: `trigger_${index}`,
      trigger: rule.trigger,
      effect: rule.effect,
      spawnCount: rule.spawnCount,
      targetPositions: rule.targetPositions,
      status: "idle",
      icon: rule.icon, // Copy icon from rule for visual display
      progress: getProgressForTrigger(gameState, rule.trigger),
    };

    return triggerState;
  });
}

/**
 * Update all trigger states based on current game state
 * Sets status to 'primed' if conditions are met, 'idle' if not
 * @param gameState Current game state
 * @returns Updated game state (mutates in place)
 */
export function updateTriggerStates(
  gameState: SynchronizedGameState,
): SynchronizedGameState {
  if (!gameState.eventTriggerStates) {
    return gameState;
  }

  for (const triggerState of gameState.eventTriggerStates) {
    // Skip triggers that are currently in 'triggered' state
    if (triggerState.status === "triggered") {
      continue;
    }

    // Check if trigger conditions are met
    const conditionMet = isTriggerConditionMet(gameState, triggerState.trigger);

    // Update status
    triggerState.status = conditionMet ? "primed" : "idle";

    // Update progress
    triggerState.progress = getProgressForTrigger(
      gameState,
      triggerState.trigger,
    );
  }

  return gameState;
}

/**
 * Mark specific triggers as 'triggered' after they fire
 * @param gameState Current game state
 * @param matchingRuleIndices Array of rule indices that just fired
 * @returns Updated game state (mutates in place)
 */
export function markTriggersActivated(
  gameState: SynchronizedGameState,
  matchingRuleIndices: number[],
): SynchronizedGameState {
  if (!gameState.eventTriggerStates) {
    return gameState;
  }

  for (const index of matchingRuleIndices) {
    if (index >= 0 && index < gameState.eventTriggerStates.length) {
      const triggerState = gameState.eventTriggerStates[index];
      triggerState.status = "triggered";
      // Reset progress after activation
      triggerState.progress = getProgressForTrigger(
        gameState,
        triggerState.trigger,
      );
    }
  }

  return gameState;
}

/**
 * Reset 'triggered' states back to 'idle' or 'primed' based on current conditions
 * Should be called after visual feedback completes (typically next frame)
 * @param gameState Current game state
 * @returns Updated game state (mutates in place)
 */
export function resetTriggeredStates(
  gameState: SynchronizedGameState,
): SynchronizedGameState {
  if (!gameState.eventTriggerStates) {
    return gameState;
  }

  for (const triggerState of gameState.eventTriggerStates) {
    if (triggerState.status === "triggered") {
      // Recalculate if conditions are still met
      const conditionMet = isTriggerConditionMet(
        gameState,
        triggerState.trigger,
      );

      // Set to 'primed' if conditions met, 'idle' if not
      triggerState.status = conditionMet ? "primed" : "idle";

      // Update progress
      triggerState.progress = getProgressForTrigger(
        gameState,
        triggerState.trigger,
      );
    }
  }

  return gameState;
}

// ============================================================================
// Progress Calculation Helpers
// ============================================================================

/**
 * Get progress for a specific trigger based on game state
 * @param gameState Current game state
 * @param trigger Event trigger definition
 * @returns Progress object with current and required values
 */
function getProgressForTrigger(
  gameState: SynchronizedGameState,
  trigger: EventTrigger,
): { current: number; required: number } | undefined {
  switch (trigger.event) {
    case "COMBO_BREAK":
      return getComboProgress(gameState, trigger.minCombo);
    case "SCORE_MILESTONE":
      return getScoreProgress(gameState, trigger.threshold);
    case "MERGE_COUNT":
      return getMergeCountProgress(gameState, trigger.count);
    case "MOVE_COUNT":
      return getMoveProgress(gameState, trigger.moves);
    default:
      return undefined;
  }
}

/**
 * Get combo progress for COMBO_BREAK triggers
 * @param gameState Current game state
 * @param minCombo Minimum combo required
 * @returns Progress with current combo and required combo
 */
export function getComboProgress(
  gameState: SynchronizedGameState,
  minCombo: number,
): { current: number; required: number } {
  return {
    current: gameState.comboMultiplier,
    required: minCombo,
  };
}

/**
 * Get score progress for SCORE_MILESTONE triggers
 * @param gameState Current game state
 * @param threshold Score threshold required
 * @returns Progress with current score and required score
 */
export function getScoreProgress(
  gameState: SynchronizedGameState,
  threshold: number,
): { current: number; required: number } {
  return {
    current: gameState.score,
    required: threshold,
  };
}

/**
 * Get merge count progress for MERGE_COUNT triggers
 * Note: Requires totalMerges field in game state (future enhancement)
 * @param gameState Current game state
 * @param count Number of merges required
 * @returns Progress with current merge count and required count
 */
export function getMergeCountProgress(
  gameState: SynchronizedGameState,
  count: number,
): { current: number; required: number } {
  return {
    current: gameState.totalMerges ?? 0,
    required: count,
  };
}

/**
 * Get move progress for MOVE_COUNT triggers
 * @param gameState Current game state
 * @param moves Number of moves required
 * @returns Progress with current moves and required moves
 */
export function getMoveProgress(
  gameState: SynchronizedGameState,
  moves: number,
): { current: number; required: number } {
  return {
    current: gameState.moveIndex,
    required: moves,
  };
}

/**
 * Check if trigger condition is currently met
 * @param gameState Current game state
 * @param trigger Event trigger definition
 * @returns True if condition is met, false otherwise
 */
export function isTriggerConditionMet(
  gameState: SynchronizedGameState,
  trigger: EventTrigger,
): boolean {
  switch (trigger.event) {
    case "COMBO_BREAK":
      return gameState.comboMultiplier >= trigger.minCombo;
    case "SCORE_MILESTONE":
      return gameState.score >= trigger.threshold;
    case "MERGE_COUNT":
      return (gameState.totalMerges ?? 0) >= trigger.count;
    case "MOVE_COUNT":
      return gameState.moveIndex >= trigger.moves;
    default:
      return false;
  }
}
