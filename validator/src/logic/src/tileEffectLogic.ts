import { RNG_NAMESPACES } from "./constants";
import type {
  BoardPosition,
  SpawnCurve,
  SynchronizedGameState,
  SynchronizedTileState,
  TileEffect,
  TileEffectSpawnConfig,
  TileEffectType,
} from "./types";
import { IRandomGenerator } from "./random";

/**
 * Disabled spawn configuration - used when effect is not configured to spawn
 */
const DISABLED_SPAWN_CONFIG: TileEffectSpawnConfig = {
  spawnCurve: {
    type: "constant",
    baseChance: 0,
  },
  canSpawnOn: [],
  canSpawnOnEmpty: false,
  maxActiveOnBoard: 0,
};

/**
 * Get effective spawn configuration for an effect type
 * @param effectType Type of effect
 * @param gameState Current game state
 * @returns Spawn configuration (returns disabled config if not defined in scenario)
 */
export function getSpawnConfig(
  effectType: Exclude<TileEffectType, "none">,
  gameState: SynchronizedGameState,
): TileEffectSpawnConfig {
  return (
    gameState.scenarioConfig?.spawnConfigs?.[effectType] ??
    DISABLED_SPAWN_CONFIG
  );
}

/**
 * Calculate spawn chance based on curve configuration and move index
 * @param curve Spawn curve configuration
 * @param moveIndex Current move index
 * @returns Calculated spawn chance (0-1)
 */
function calculateSpawnChance(curve: SpawnCurve, moveIndex: number): number {
  let chance: number;

  switch (curve.type) {
    case "constant":
      chance = curve.baseChance;
      break;

    case "linear": {
      const rate = curve.params?.linearRate ?? 0.001;
      chance = curve.baseChance + rate * moveIndex;
      break;
    }

    case "exponential": {
      const factor = curve.params?.exponentialFactor ?? 1.01;
      chance = curve.baseChance * Math.pow(factor, moveIndex);
      break;
    }

    case "stepped": {
      const steps = curve.params?.steps ?? [];
      chance = curve.baseChance;
      for (const step of steps) {
        if (moveIndex >= step.moveIndex) {
          chance = step.chance;
        }
      }
      break;
    }

    default:
      chance = curve.baseChance;
  }

  // Clamp to min/max bounds
  const minChance = curve.minChance ?? 0;
  const maxChance = curve.maxChance ?? 1;
  return Math.max(minChance, Math.min(maxChance, chance));
}

/**
 * Check if an effect should spawn based on configuration
 * @param effectType Type of effect to spawn
 * @param gameState Current game state
 * @param currentActiveCount Current count of this effect type on board
 * @param randomGenerator Random number generator
 * @returns Whether effect should spawn
 */
export function shouldSpawnEffect(
  effectType: Exclude<TileEffectType, "none">,
  gameState: SynchronizedGameState,
  currentActiveCount: number,
  randomGenerator: IRandomGenerator,
): boolean {
  const config = getSpawnConfig(effectType, gameState);

  // Check if we've hit the max active limit
  const maxActive =
    gameState.scenarioConfig?.maxActiveOverrides?.[effectType] ??
    config.maxActiveOnBoard;

  if (currentActiveCount >= maxActive) {
    return false;
  }

  // Calculate spawn chance based on curve and moveIndex
  const spawnChance = calculateSpawnChance(
    config.spawnCurve,
    gameState.moveIndex,
  );

  // Random roll
  return randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) < spawnChance;
}

/**
 * Check if a tile can have an effect applied to it
 * @param tile Tile to check
 * @param effectType Type of effect to apply
 * @param gameState Current game state
 * @returns Whether effect can be applied
 */
export function canApplyEffectToTile(
  tile: SynchronizedTileState,
  effectType: Exclude<TileEffectType, "none">,
  gameState: SynchronizedGameState,
): boolean {
  // Don't apply if tile already has an effect
  if (tile.effect && tile.effect.active && tile.effect.type !== "none") {
    return false;
  }

  // Get spawn configuration for this effect type
  const spawnConfig = getSpawnConfig(effectType, gameState);

  // Check if tile's empty/non-empty state matches effect's requirements
  if (tile.isEmpty) {
    // If tile is empty, effect must allow spawning on empty tiles
    return spawnConfig.canSpawnOnEmpty;
  }

  // If tile is not empty, check if tile status is valid for this effect
  return spawnConfig.canSpawnOn.includes(tile.status);
}

/**
 * Count active effects of a specific type on the board
 * @param gameState Current game state
 * @param effectType Type of effect to count
 * @returns Number of active effects of this type
 */
export function countActiveEffects(
  gameState: SynchronizedGameState,
  effectType: TileEffectType,
): number {
  let count = 0;
  for (const tile of gameState.board.tiles) {
    if (tile.effect && tile.effect.active && tile.effect.type === effectType) {
      count++;
    }
  }
  return count;
}

/**
 * Get tiles adjacent to a position (orthogonal only)
 * @param gameState Current game state
 * @param position Position to check around
 * @returns Array of adjacent tiles
 */
export function getAdjacentTiles(
  gameState: SynchronizedGameState,
  position: BoardPosition,
): SynchronizedTileState[] {
  const { row, col } = position;
  const boardSize = gameState.board.size;
  const adjacentPositions: BoardPosition[] = [];

  // Up
  if (row > 0) adjacentPositions.push({ row: row - 1, col });
  // Down
  if (row < boardSize - 1) adjacentPositions.push({ row: row + 1, col });
  // Left
  if (col > 0) adjacentPositions.push({ row, col: col - 1 });
  // Right
  if (col < boardSize - 1) adjacentPositions.push({ row, col: col + 1 });

  return adjacentPositions.map((pos) => {
    const index = pos.row * boardSize + pos.col;
    return gameState.board.tiles[index];
  });
}

/**
 * Check if a tile has a specific effect
 * @param tile Tile to check
 * @param effectType Type of effect to check for
 * @returns Whether tile has the effect
 */
export function tileHasEffect(
  tile: SynchronizedTileState,
  effectType: TileEffectType,
): boolean {
  return (
    tile.effect !== undefined &&
    tile.effect.active &&
    tile.effect.type === effectType
  );
}

/**
 * Remove effect from a tile
 * @param tile Tile to remove effect from
 */
function removeEffectFromTile(tile: SynchronizedTileState): void {
  if (tile.effect) {
    tile.effect.active = false;
  }
}

/**
 * Apply effect to a tile
 * @param tile Tile to apply effect to
 * @param effect Effect to apply
 */
export function applyEffectToTile(
  tile: SynchronizedTileState,
  effect: TileEffect,
): void {
  tile.effect = effect;
}

// ============================================================================
// FREEZE Effect Logic
// ============================================================================

/**
 * Check if a value can merge (based on effect config)
 * @param tile Tile to check
 * @returns Whether value can merge
 */
export function canValueMerge(tile: SynchronizedTileState): boolean {
  if (!tile.effect || !tile.effect.active) {
    return true;
  }

  // Check allowsValueMerge flag in effect config
  return tile.effect.config.allowsValueMerge;
}

/**
 * Process effect removal when a merge happens adjacent to tiles (based on effectRemovedByAdjacentMerge config)
 * @param gameState Current game state
 * @param mergedPosition Position where merge occurred
 * @returns Array of positions where effects were removed
 */
export function processFreezeRemovalFromAdjacentMerge(
  gameState: SynchronizedGameState,
  mergedPosition: BoardPosition,
): BoardPosition[] {
  const removedPositions: BoardPosition[] = [];
  const adjacentTiles = getAdjacentTiles(gameState, mergedPosition);

  adjacentTiles.forEach((tile) => {
    // Check if tile has an active effect that should be removed by adjacent merges
    if (
      tile.effect &&
      tile.effect.active &&
      tile.effect.config.effectRemovedByAdjacentMerge
    ) {
      removeEffectFromTile(tile);
      removedPositions.push({ row: tile.row, col: tile.col });
    }
  });

  return removedPositions;
}

/**
 * Check if two tiles can merge together (considering freeze/stone effects)
 * @param tile1 First tile
 * @param tile2 Second tile
 * @returns Whether tiles can merge
 */
export function canTilesMergeTogether(
  tile1: SynchronizedTileState,
  tile2: SynchronizedTileState,
): boolean {
  // Empty tiles can't merge
  if (tile1.isEmpty || tile2.isEmpty) {
    return false;
  }

  // Values must match
  if (tile1.value !== tile2.value) {
    return false;
  }

  // Both values must be able to merge (not frozen/stone)
  return canValueMerge(tile1) && canValueMerge(tile2);
}

// ============================================================================
// LOCK Effect Logic
// ============================================================================

/**
 * Process lock effect trigger decrement when a merge happens on a locked tile
 * @param tile Tile that was involved in the merge
 * @returns Position if lock was removed, null otherwise
 */
export function processLockTriggerOnMerge(
  tile: SynchronizedTileState,
): BoardPosition | null {
  if (!tileHasEffect(tile, "lock")) {
    return null;
  }

  if (!tile.effect || !tile.effect.config) {
    return null;
  }

  const remainingTriggers = tile.effect.config.remainingTriggers;

  if (remainingTriggers <= 1) {
    removeEffectFromTile(tile);
    return { row: tile.row, col: tile.col };
  }

  tile.effect.config.remainingTriggers = remainingTriggers - 1;
  return null;
}

// ============================================================================
// BLACK_HOLE Effect Logic
// ============================================================================

/**
 * Check if a tile is a black hole
 * @param tile Tile to check
 * @returns Whether tile is a black hole
 */
export function isBlackHoleTile(tile: SynchronizedTileState): boolean {
  return tileHasEffect(tile, "black_hole");
}

/**
 * Check if a value can move during swipes (based on effect config)
 * @param tile Tile to check
 * @returns Whether value can move
 */
export function canValueMove(tile: SynchronizedTileState): boolean {
  if (tile.isEmpty) return false;
  if (!tile.effect || !tile.effect.active) return true;

  // Check allowsValueMovement flag in effect config
  return tile.effect.config.allowsValueMovement;
}

/**
 * Check if there's a black hole in the path between two positions
 * @param tiles Array of tiles representing the board
 * @param boardSize Size of the board (e.g., 4 for 4x4)
 * @param from Starting position
 * @param to Ending position
 * @returns Position of black hole if found, null otherwise
 */
export function findBlackHoleInPath(
  tiles: SynchronizedTileState[],
  boardSize: number,
  from: BoardPosition,
  to: BoardPosition,
): BoardPosition | null {
  // Determine direction
  const rowDir = to.row === from.row ? 0 : to.row > from.row ? 1 : -1;
  const colDir = to.col === from.col ? 0 : to.col > from.col ? 1 : -1;

  let currentRow = from.row + rowDir;
  let currentCol = from.col + colDir;

  // Check each position in the path (excluding start and end)
  while (currentRow !== to.row || currentCol !== to.col) {
    const index = currentRow * boardSize + currentCol;
    const tile = tiles[index];

    if (isBlackHoleTile(tile)) {
      return { row: currentRow, col: currentCol };
    }

    currentRow += rowDir;
    currentCol += colDir;
  }

  return null;
}

/**
 * Process tile destruction by black hole
 * @param consumedTile Tile being consumed
 * @param blackHoleTile The black hole tile consuming it
 * @returns Object with scoreLoss and shouldImplode
 */
export function processBlackHoleDestruction(
  consumedTile: SynchronizedTileState,
  blackHoleTile: SynchronizedTileState,
): { scoreLoss: number; shouldImplode: boolean } {
  const scoreLoss = consumedTile.value;

  // Make consumed tile empty and clear any effects
  consumedTile.isEmpty = true;
  consumedTile.value = 0;
  consumedTile.status = "normal";
  delete consumedTile.effect;

  // Increment the black hole's consumption counter
  if (blackHoleTile.effect && blackHoleTile.effect.config) {
    blackHoleTile.effect.config.tilesConsumed =
      blackHoleTile.effect.config.tilesConsumed + 1;

    const maxTiles = blackHoleTile.effect.config.maxTilesToImplosion;
    const shouldImplode = blackHoleTile.effect.config.tilesConsumed >= maxTiles;

    return { scoreLoss, shouldImplode };
  }

  return { scoreLoss, shouldImplode: false };
}

/**
 * Attempt to remove black hole effect by spending shards
 * @param gameState Current game state
 * @param position Position of black hole to remove
 * @returns Updated game state, or null if removal failed
 */
export function removeBlackHoleWithShards(
  gameState: SynchronizedGameState,
  position: BoardPosition,
): SynchronizedGameState | null {
  const index = position.row * gameState.board.size + position.col;
  const tile = gameState.board.tiles[index];

  // Validate this is a black hole
  if (!isBlackHoleTile(tile)) return null;

  const removalCost = tile.effect!.config.removalCost;

  // Check if player has enough shards
  if (gameState.shards < removalCost) return null;

  // Remove effect and deduct shards
  removeEffectFromTile(tile);

  return {
    ...gameState,
    shards: gameState.shards - removalCost,
  };
}

/**
 * Check if tile has amplify effect
 * @param tile Tile to check
 * @returns True if tile has active amplify effect
 */
export function isAmplifyTile(
  tile: SynchronizedTileState | undefined,
): boolean {
  return (
    tile !== undefined &&
    !tile.isEmpty &&
    tile.effect?.type === "amplify" &&
    tile.effect.active === true
  );
}

/**
 * Get amplier multiplier value from effect config
 * @param tile Tile with amplify effect
 * @returns Multiplier value (default: 2)
 */
export function getAmplifyMultiplier(tile: SynchronizedTileState): number {
  if (!isAmplifyTile(tile)) return 1;
  return tile.effect!.config.multiplier;
}

/**
 * Process amplify effect - apply multiplier and remove effect
 * @param tile Tile with amplify effect
 * @param mergeValue The value to multiply
 * @returns Object with multiplied value, whether effect was consumed, and multiplier
 * @deprecated Use processTileEffectsOnMerge instead for generic effect handling
 */
export function processAmplifyEffect(
  tile: SynchronizedTileState,
  mergeValue: number,
): { value: number; consumed: boolean; multiplier: number } {
  if (!isAmplifyTile(tile)) {
    return { value: mergeValue, consumed: false, multiplier: 1 };
  }

  const multiplier = getAmplifyMultiplier(tile);
  const result = mergeValue * multiplier;

  // Mark effect as inactive (consumed)
  if (tile.effect) {
    tile.effect.active = false;
  }

  return { value: result, consumed: true, multiplier };
}

/**
 * Metadata about a consumed tile effect
 */
export interface TileEffectConsumption {
  type: TileEffectType;
  row: number;
  col: number;
  metadata: {
    multiplier?: number;
    emitter?: string;
  };
}

/**
 * Result of processing tile effects during a merge
 */
interface TileEffectMergeResult {
  finalValue: number;
  consumedEffects: TileEffectConsumption[];
}

/**
 * Generic function to process all tile effects during a merge
 * Reads effect configuration to determine merge behavior
 * @param tile Target tile where merge is happening
 * @param baseValue Base merge value before effect modifiers
 * @returns Final value after effects applied and list of consumed effects
 */
export function processTileEffectsOnMerge(
  tile: SynchronizedTileState,
  baseValue: number,
): TileEffectMergeResult {
  let finalValue = baseValue;
  const consumedEffects: TileEffectConsumption[] = [];

  // Process active effects
  if (tile.effect && tile.effect.active && tile.effect.type !== "none") {
    const mergeConfig = tile.effect.config.mergeConfig;

    // Apply multiplier
    finalValue *= mergeConfig.valueMultiplier;

    // Track consumption if configured
    if (mergeConfig.consumedOnMerge) {
      consumedEffects.push({
        type: tile.effect.type,
        row: tile.row,
        col: tile.col,
        metadata: {
          multiplier: mergeConfig.valueMultiplier,
          emitter: mergeConfig.consumptionEmitter,
        },
      });

      // Mark effect as inactive (consumed)
      tile.effect.active = false;
    }
  }

  return { finalValue, consumedEffects };
}

/**
 * Check if a tile's effect should be preserved at the source position during a merge
 * @param tile Source tile in merge operation
 * @returns The effect to preserve at source, or undefined if no preservation needed
 */
export function getEffectToPreserveAtSource(
  tile: SynchronizedTileState,
): TileEffect | undefined {
  if (!tile.effect || !tile.effect.active || tile.effect.type === "none") {
    return undefined;
  }

  const mergeConfig = tile.effect.config.mergeConfig;

  if (mergeConfig.effectStaysAtSource) {
    return tile.effect;
  }

  return undefined;
}
