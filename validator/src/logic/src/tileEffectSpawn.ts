import { RNG_NAMESPACES } from "./constants";
import type {
  AuthoritativeSpawnConfig,
  BoardPosition,
  EventBasedSpawnRule,
  SpawnPositionStrategy,
  SynchronizedGameState,
  TileEffectConfig,
  TileEffectType,
} from "./types";
import type { IRandomGenerator } from "./random";
import { createTileEffect } from "./factories";
import {
  applyEffectToTile,
  canApplyEffectToTile,
  countActiveEffects,
  shouldSpawnEffect,
} from "./tileEffectLogic";

/**
 * Type of spawn mechanism to use
 */
type SpawnType = "random" | "authoritative" | "event" | "powercard";

/**
 * Action for power card spawning
 */
export interface PowerCardSpawnAction {
  effectType: Exclude<TileEffectType, "none">;
  targetPosition: BoardPosition;
  sourceCardId: string;
  config?: Partial<TileEffectConfig>;
}

/**
 * Options for spawning tile effects
 */
interface SpawnEffectOptions {
  // Required
  gameState: SynchronizedGameState;
  randomGenerator: IRandomGenerator;

  // Spawn type
  spawnType?: SpawnType;

  // For authoritative spawn
  authoritativeEffects?: AuthoritativeSpawnConfig;

  // For event-based spawn
  eventRules?: EventBasedSpawnRule[];
  triggeredEvent?: { type: string; [key: string]: unknown };

  // For power card spawn
  powerCardSpawn?: PowerCardSpawnAction;

  // For random spawn on specific tile
  targetTileIndex?: number;
}

/**
 * Information about a spawned effect
 */
interface SpawnedEffectInfo {
  type: Exclude<TileEffectType, "none">;
  position: BoardPosition;
  config: TileEffectConfig;
}

/**
 * Result of spawning effects
 */
interface SpawnEffectResult {
  gameState: SynchronizedGameState;
  effectsSpawned: SpawnedEffectInfo[];
  spawnedCount: number;
}

/**
 * Result of attempting to spawn an effect on a single tile
 */
interface AttemptSpawnResult {
  success: boolean;
  gameState: SynchronizedGameState;
  effectSpawned?: SpawnedEffectInfo;
}

/**
 * Find all valid positions on the board where effects can spawn
 * @param gameState Current game state
 * @param effectType Type of effect to spawn
 * @returns Array of valid tile indices
 */
export function findValidSpawnPositions(
  gameState: SynchronizedGameState,
  effectType: Exclude<TileEffectType, "none">,
): number[] {
  const validIndices: number[] = [];

  for (let i = 0; i < gameState.board.tiles.length; i++) {
    const tile = gameState.board.tiles[i];
    if (canApplyEffectToTile(tile, effectType, gameState)) {
      validIndices.push(i);
    }
  }

  return validIndices;
}

/**
 * Select a spawn position based on strategy
 * @param gameState Current game state
 * @param validIndices Array of valid tile indices
 * @param strategy Selection strategy
 * @param randomGenerator Random number generator
 * @returns Selected tile index, or null if no valid position
 */
export function selectSpawnPosition(
  gameState: SynchronizedGameState,
  validIndices: number[],
  strategy: SpawnPositionStrategy,
  randomGenerator: IRandomGenerator,
): number | null {
  if (validIndices.length === 0) return null;

  switch (strategy) {
    case "random":
      // Pick any valid position randomly
      return validIndices[
        Math.floor(
          randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) *
            validIndices.length,
        )
      ];

    case "empty":
      // Only pick from empty tiles
      const emptyIndices = validIndices.filter(
        (i) => gameState.board.tiles[i].isEmpty,
      );
      if (emptyIndices.length === 0) return null;
      return emptyIndices[
        Math.floor(
          randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) *
            emptyIndices.length,
        )
      ];

    case "highest_value":
      // Pick tile with highest value
      let maxValue = -1;
      let maxIndex = validIndices[0];
      for (const i of validIndices) {
        const tile = gameState.board.tiles[i];
        if (!tile.isEmpty && tile.value > maxValue) {
          maxValue = tile.value;
          maxIndex = i;
        }
      }
      return maxIndex;

    default:
      return null;
  }
}

/**
 * Attempt to spawn an effect on a specific tile
 * @param gameState Current game state
 * @param tileIndex Index of tile to spawn effect on
 * @param randomGenerator Random number generator
 * @returns Result with success status and updated game state
 */
export function attemptSpawnEffectOnTile(
  gameState: SynchronizedGameState,
  tileIndex: number,
  randomGenerator: IRandomGenerator,
): AttemptSpawnResult {
  const tile = gameState.board.tiles[tileIndex];

  // Get list of all effect types to try
  const allEffectTypes: Array<Exclude<TileEffectType, "none">> = [
    "freeze",
    "black_hole",
    "amplify",
    "amplify_static",
    "lock",
    "decay",
    "stone",
  ];

  // Try each effect type
  for (const effectType of allEffectTypes) {
    // Check if tile can have this effect
    if (!canApplyEffectToTile(tile, effectType, gameState)) {
      continue;
    }

    // Check if effect should spawn (includes max active limit check)
    const activeCount = countActiveEffects(gameState, effectType);
    if (
      !shouldSpawnEffect(effectType, gameState, activeCount, randomGenerator)
    ) {
      continue;
    }

    // Spawn the effect!
    const effect = createTileEffect(effectType);
    const newTiles = [...gameState.board.tiles];
    const newTile = { ...newTiles[tileIndex] };
    applyEffectToTile(newTile, effect);
    newTiles[tileIndex] = newTile;

    const newGameState = {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles,
      },
    };

    return {
      success: true,
      gameState: newGameState,
      effectSpawned: {
        type: effectType,
        position: { row: tile.row, col: tile.col },
        config: effect.config || {},
      },
    };
  }

  // No effect spawned
  return {
    success: false,
    gameState,
  };
}

/**
 * Spawn effects based on authoritative configuration
 * @param gameState Current game state
 * @param config Authoritative spawn configuration
 * @returns Result with spawned effects
 */
function spawnAuthoritativeEffects(
  gameState: SynchronizedGameState,
  config: AuthoritativeSpawnConfig,
): SpawnEffectResult {
  const effectsSpawned: SpawnedEffectInfo[] = [];
  const newTiles = [...gameState.board.tiles];
  const boardSize = gameState.board.size;

  for (const effectDef of config.effects) {
    const { type, position, config: effectConfig } = effectDef;

    // Calculate tile index
    const index = position.row * boardSize + position.col;
    if (index < 0 || index >= newTiles.length) {
      continue; // Invalid position
    }

    // Create and apply effect
    const effect = createTileEffect(type, effectConfig);
    const newTile = { ...newTiles[index] };
    applyEffectToTile(newTile, effect);
    newTiles[index] = newTile;

    effectsSpawned.push({
      type,
      position,
      config: effect.config || {},
    });
  }

  return {
    gameState: {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles,
      },
    },
    effectsSpawned,
    spawnedCount: effectsSpawned.length,
  };
}

/**
 * Spawn effect from power card action
 * @param gameState Current game state
 * @param action Power card spawn action
 * @returns Result with spawned effect
 */
function spawnFromPowerCard(
  gameState: SynchronizedGameState,
  action: PowerCardSpawnAction,
): SpawnEffectResult {
  const { effectType, targetPosition, config: effectConfig } = action;
  const boardSize = gameState.board.size;
  const index = targetPosition.row * boardSize + targetPosition.col;

  const newTiles = [...gameState.board.tiles];
  const tile = newTiles[index];

  // Validate position
  if (index < 0 || index >= newTiles.length) {
    return {
      gameState,
      effectsSpawned: [],
      spawnedCount: 0,
    };
  }

  // Create and apply effect
  const effect = createTileEffect(effectType, effectConfig);
  const newTile = { ...tile };
  applyEffectToTile(newTile, effect);
  newTiles[index] = newTile;

  return {
    gameState: {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles,
      },
    },
    effectsSpawned: [
      {
        type: effectType,
        position: targetPosition,
        config: effect.config || {},
      },
    ],
    spawnedCount: 1,
  };
}

/**
 * Main orchestrator function for spawning tile effects
 * @param options Spawn options
 * @returns Result with updated game state and spawned effects
 */
export function spawnTileEffects(
  options: SpawnEffectOptions,
): SpawnEffectResult {
  const {
    gameState,
    randomGenerator,
    spawnType = "random",
    authoritativeEffects,
    powerCardSpawn,
    targetTileIndex,
  } = options;

  // Route to appropriate spawn handler
  switch (spawnType) {
    case "authoritative":
      if (!authoritativeEffects) {
        return { gameState, effectsSpawned: [], spawnedCount: 0 };
      }
      return spawnAuthoritativeEffects(gameState, authoritativeEffects);

    case "powercard":
      if (!powerCardSpawn) {
        return { gameState, effectsSpawned: [], spawnedCount: 0 };
      }
      return spawnFromPowerCard(gameState, powerCardSpawn);

    case "random":
      // Random spawn on specific tile or any valid tile
      if (targetTileIndex !== undefined) {
        const result = attemptSpawnEffectOnTile(
          gameState,
          targetTileIndex,
          randomGenerator,
        );
        return {
          gameState: result.gameState,
          effectsSpawned: result.effectSpawned ? [result.effectSpawned] : [],
          spawnedCount: result.success ? 1 : 0,
        };
      }
      // If no target specified, return empty result (caller should specify target)
      return { gameState, effectsSpawned: [], spawnedCount: 0 };

    case "event":
      // Event-based spawning handled by eventSpawnProcessor.ts
      // This is a placeholder for now
      return { gameState, effectsSpawned: [], spawnedCount: 0 };

    default:
      return { gameState, effectsSpawned: [], spawnedCount: 0 };
  }
}
