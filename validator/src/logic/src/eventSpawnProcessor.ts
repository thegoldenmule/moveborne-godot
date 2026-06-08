import type {
  AuthoritativeSpawnConfig,
  BoardPosition,
  EventBasedSpawnRule,
  EventTrigger,
  GameEvent,
  SpawnPositionStrategy,
  SynchronizedGameState,
  TileEffectType,
} from "./types";
import type { IRandomGenerator } from "./random";
import {
  findValidSpawnPositions,
  selectSpawnPosition,
  spawnTileEffects,
} from "./tileEffectSpawn";
import { markTriggersActivated } from "./eventTriggerState";
import { createGlobalEffect } from "./globalEffects";

/**
 * Check if a game event matches a trigger condition
 * @param event The game event to check
 * @param trigger The trigger condition to match against
 * @returns True if event matches trigger, false otherwise
 */
function matchesEventTrigger(event: GameEvent, trigger: EventTrigger): boolean {
  switch (trigger.event) {
    case "COMBO_BREAK":
      // Match if event is COMBO_BREAK and combo was >= minCombo
      if (
        event.type === "COMBO_BREAK" ||
        event.type === "COMBO_BREAK_ATTEMPTED"
      ) {
        const previousCombo = event.previousCombo ?? 0;
        return previousCombo >= trigger.minCombo;
      }
      return false;

    case "SCORE_MILESTONE":
      // Match if event is SCORE_UPDATE and score crosses threshold
      // Note: This requires tracking previous score to detect crossing
      // For now, we'll trigger on any SCORE_UPDATE where current score >= threshold
      if (event.type === "SCORE_UPDATE") {
        // This will need to be enhanced to prevent duplicate triggers
        // by tracking last milestone reached in game state
        return true; // Caller should handle milestone tracking
      }
      return false;

    case "MERGE_COUNT":
      // Match if cumulative merge count reaches threshold
      // Requires tracking total merges in game state
      if (event.type === "TILE_MERGE") {
        // This will need game state context to track total merges
        return true; // Caller should handle merge count tracking
      }
      return false;

    case "MOVE_COUNT":
      // Match if move count has reached threshold
      // Requires move count tracking in game state
      if (event.type === "TURN_END" || event.type === "MOVE_COMPLETED") {
        // This will need game state context to check move count
        return true; // Caller should handle move count tracking
      }
      return false;

    default:
      return false;
  }
}

/**
 * Process event-based spawn rules and spawn effects if triggers match
 * @param gameState Current game state
 * @param event Game event that occurred
 * @param rules Array of event-based spawn rules to check
 * @param randomGenerator Random number generator
 * @param excludedPositions Positions to exclude from spawning (e.g., where effects were just removed)
 * @returns Updated game state with any spawned effects
 */
export function processEventSpawnRules(
  gameState: SynchronizedGameState,
  event: GameEvent,
  rules: EventBasedSpawnRule[],
  randomGenerator: IRandomGenerator,
  excludedPositions: BoardPosition[] = [],
): SynchronizedGameState {
  // Track which rule indices matched and fired
  const matchingRuleIndices: number[] = [];

  // Collect all effects to spawn across all matching rules
  const effectsToSpawn: Array<{
    type: Exclude<TileEffectType, "none">;
    position: BoardPosition;
  }> = [];

  // Check each rule and collect effects to spawn
  for (let ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
    const rule = rules[ruleIndex];

    const matched = matchesEventTrigger(event, rule.trigger);

    if (!matched) {
      continue; // Skip non-matching rules
    }

    const { effect: effectType, spawnCount, targetPositions = "random" } = rule;

    // Find valid positions for this effect type
    let validPositions = findValidSpawnPositions(gameState, effectType);

    // Filter out positions that had effects removed in the same turn
    // This prevents re-applying effects to positions where effects were just broken by merges
    validPositions = validPositions.filter((tileIndex) => {
      const tile = gameState.board.tiles[tileIndex];
      return !excludedPositions.some(
        (excludedPos) =>
          excludedPos.row === tile.row && excludedPos.col === tile.col,
      );
    });

    if (validPositions.length === 0) {
      continue; // No valid positions, skip this rule
    }

    // Track that this rule matched (will mark as triggered later)
    matchingRuleIndices.push(ruleIndex);

    // Select positions for the specified number of effects
    for (let i = 0; i < spawnCount; i++) {
      // Select a position based on strategy
      const tileIndex = selectSpawnPosition(
        gameState,
        validPositions,
        targetPositions as SpawnPositionStrategy,
        randomGenerator,
      );

      if (tileIndex === null) {
        break; // No more valid positions
      }

      // Add to spawn list
      const tile = gameState.board.tiles[tileIndex];
      effectsToSpawn.push({
        type: effectType,
        position: { row: tile.row, col: tile.col },
      });

      // Remove this index from valid positions to avoid duplicate spawns
      const indexPos = validPositions.indexOf(tileIndex);
      if (indexPos > -1) {
        validPositions.splice(indexPos, 1);
      }
    }
  }

  // Spawn all collected effects using authoritative spawn
  let modifiedState = gameState;
  if (effectsToSpawn.length > 0) {
    const authConfig: AuthoritativeSpawnConfig = {
      effects: effectsToSpawn,
    };

    const result = spawnTileEffects({
      gameState: modifiedState,
      randomGenerator,
      spawnType: "authoritative",
      authoritativeEffects: authConfig,
    });

    modifiedState = result.gameState;
  }

  // Mark triggers as activated for visual feedback
  if (matchingRuleIndices.length > 0) {
    modifiedState = markTriggersActivated(modifiedState, matchingRuleIndices);
  }

  // Create global effects for matching rules
  for (const ruleIndex of matchingRuleIndices) {
    const rule = rules[ruleIndex];
    if (rule.globalEffect && modifiedState.eventTriggerStates) {
      const triggerState = modifiedState.eventTriggerStates[ruleIndex];
      if (triggerState) {
        const globalEffect = createGlobalEffect(
          rule,
          triggerState.id,
          randomGenerator,
        );

        if (globalEffect) {
          if (!modifiedState.globalEffects) {
            modifiedState.globalEffects = [];
          }
          modifiedState.globalEffects = [
            ...modifiedState.globalEffects,
            globalEffect,
          ];
        }
      }
    }
  }

  return modifiedState;
}
