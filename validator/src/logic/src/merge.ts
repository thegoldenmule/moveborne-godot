import { RNG_NAMESPACES } from "./constants";
import type {
  BoardPosition,
  DestroyedTile,
  EventBasedSpawnRule,
  GameEvent,
  SynchronizedGameState,
  SynchronizedTileState,
  TileEffectType,
} from "./types";
import { IRandomGenerator } from "./random";
import { getTile, indexToRowCol, rowColToIndex, setTile } from "./board";
import { processEventSpawnRules } from "./eventSpawnProcessor";
import { updateTriggerStates } from "./eventTriggerState";
import { createEmptyTile } from "./factories";
import {
  canValueMove,
  canTilesMergeTogether,
  findBlackHoleInPath,
  getEffectToPreserveAtSource,
  isBlackHoleTile,
  processBlackHoleDestruction,
  processFreezeRemovalFromAdjacentMerge,
  processLockTriggerOnMerge,
  processTileEffectsOnMerge,
  type TileEffectConsumption,
} from "./tileEffectLogic";
import { attemptSpawnEffectOnTile } from "./tileEffectSpawn";
import { processTotemEffects } from "./totemLogic";

/**
 * Core merge and swipe logic for the game
 */
interface SwipeResult {
  moved: boolean;
  score: number;
  scoreLoss: number;
  mergedTilesCount: number;
  mergedTiles: Set<number>;
  destroyedTiles: DestroyedTile[];
  effectConsumptions: TileEffectConsumption[];
  removedLockPositions: BoardPosition[];
}

interface PerformSwipeResult {
  gameState: SynchronizedGameState;
  moved: boolean;
  score: number;
  mergedTilesCount: number;
  removedEffectPositions: BoardPosition[];
  destroyedTiles: DestroyedTile[];
  effectConsumptions: TileEffectConsumption[];
}

function swipeLeft(
  newTiles: SynchronizedTileState[],
  mergedTiles: Set<number>,
  boardSize: number,
): SwipeResult {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles: DestroyedTile[] = [];
  const effectConsumptions: TileEffectConsumption[] = [];
  const removedLockPositions: BoardPosition[] = [];

  for (let row = 0; row < boardSize; row++) {
    for (let col = 1; col < boardSize; col++) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;

      // Skip values that cannot move (immovable effects)
      if (!canValueMove(tile)) continue;

      let targetCol = col;

      // Find leftmost position
      for (let checkCol = col - 1; checkCol >= 0; checkCol--) {
        const checkTile = getTile(newTiles, row, checkCol, boardSize);

        // Black holes don't block movement - tiles pass through and get destroyed
        if (isBlackHoleTile(checkTile)) {
          targetCol = checkCol;
          continue; // Keep searching past the black hole
        }

        if (checkTile.isEmpty) {
          targetCol = checkCol;
        } else if (
          checkTile.value === tile.value &&
          !mergedTiles.has(rowColToIndex(row, checkCol, boardSize)) &&
          canTilesMergeTogether(tile, checkTile)
        ) {
          // Can merge (and neither tile is frozen/stone)
          targetCol = checkCol;
          break;
        } else {
          break;
        }
      }

      if (targetCol !== col) {
        const targetTile = getTile(newTiles, row, targetCol, boardSize);

        // Check if target itself is a destructive barrier, or if there's one in the path
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier
          ? findBlackHoleInPath(
              newTiles,
              boardSize,
              { row, col },
              { row, col: targetCol },
            )
          : null;

        if (targetIsBarrier || blackHolePos) {
          // Determine which black hole destroyed this tile
          const blackHolePosition = targetIsBarrier
            ? { row, col: targetCol }
            : blackHolePos!;

          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize,
          );

          // Tile is destroyed during swipe
          const { scoreLoss: loss, shouldImplode } =
            processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;

          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition,
            },
          });

          // If black hole should implode, mark it for removal
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }

          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (
            !targetTile.isEmpty &&
            targetTile.value === tile.value &&
            canTilesMergeTogether(tile, targetTile)
          ) {
            // Merge tiles
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue,
            );
            effectConsumptions.push(...mergeResult.consumedEffects);

            // Process lock effect on target tile before replacing it
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }

            // Create merged tile, preserving any effect that wasn't consumed
            const mergedTile: SynchronizedTileState = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row,
              col: targetCol,
            };

            // Transfer effect if it still exists after processing (not consumed)
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }

            setTile(newTiles, mergedTile, boardSize);

            // Preserve source tile effect at source position if configured
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);

            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(row, targetCol, boardSize));
            mergedTilesCount++;
          } else {
            // Just move
            // If tile has effect that should be preserved, keep it at the source position
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);

            // Check if target position has an effect to transfer
            const targetEffectToTransfer =
              getEffectToPreserveAtSource(targetTile);

            tile.col = targetCol;
            tile.row = row;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            // Transfer target effect to incoming tile
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);

            // Create empty tile at source, preserving source effect if configured
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }

  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions,
  };
}

function swipeRight(
  newTiles: SynchronizedTileState[],
  mergedTiles: Set<number>,
  boardSize: number,
): SwipeResult {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles: DestroyedTile[] = [];
  const effectConsumptions: TileEffectConsumption[] = [];
  const removedLockPositions: BoardPosition[] = [];

  for (let row = 0; row < boardSize; row++) {
    for (let col = boardSize - 2; col >= 0; col--) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;

      // Skip values that cannot move (immovable effects)
      if (!canValueMove(tile)) continue;

      let targetCol = col;
      // Find rightmost position
      for (let checkCol = col + 1; checkCol < boardSize; checkCol++) {
        const checkTile = getTile(newTiles, row, checkCol, boardSize);

        // Black holes don't block movement - tiles pass through and get destroyed
        if (isBlackHoleTile(checkTile)) {
          targetCol = checkCol;
          continue; // Keep searching past the black hole
        }

        if (checkTile.isEmpty) {
          targetCol = checkCol;
        } else if (
          checkTile.value === tile.value &&
          !mergedTiles.has(rowColToIndex(row, checkCol, boardSize)) &&
          canTilesMergeTogether(tile, checkTile)
        ) {
          // Can merge (and neither tile is frozen/stone)
          targetCol = checkCol;
          break;
        } else {
          break;
        }
      }

      if (targetCol !== col) {
        const targetTile = getTile(newTiles, row, targetCol, boardSize);

        // Check if target itself is a destructive barrier, or if there's one in the path
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier
          ? findBlackHoleInPath(
              newTiles,
              boardSize,
              { row, col },
              { row, col: targetCol },
            )
          : null;

        if (targetIsBarrier || blackHolePos) {
          // Determine which black hole destroyed this tile
          const blackHolePosition = targetIsBarrier
            ? { row, col: targetCol }
            : blackHolePos!;

          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize,
          );

          // Tile is destroyed during swipe
          const { scoreLoss: loss, shouldImplode } =
            processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;

          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition,
            },
          });

          // If black hole should implode, mark it for removal
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }

          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (
            !targetTile.isEmpty &&
            targetTile.value === tile.value &&
            canTilesMergeTogether(tile, targetTile)
          ) {
            // Merge tiles
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue,
            );
            effectConsumptions.push(...mergeResult.consumedEffects);

            // Process lock effect on target tile before replacing it
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }

            // Create merged tile, preserving any effect that wasn't consumed
            const mergedTile: SynchronizedTileState = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row,
              col: targetCol,
            };

            // Transfer effect if it still exists after processing (not consumed)
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }

            setTile(newTiles, mergedTile, boardSize);

            // Preserve source tile effect at source position if configured
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);

            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(row, targetCol, boardSize));
            mergedTilesCount++;
          } else {
            // Just move
            // If tile has effect that should be preserved, keep it at the source position
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);

            // Check if target position has an effect to transfer
            const targetEffectToTransfer =
              getEffectToPreserveAtSource(targetTile);

            tile.col = targetCol;
            tile.row = row;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            // Transfer target effect to incoming tile
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);

            // Create empty tile at source, preserving source effect if configured
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }

  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions,
  };
}

function swipeUp(
  newTiles: SynchronizedTileState[],
  mergedTiles: Set<number>,
  boardSize: number,
): SwipeResult {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles: DestroyedTile[] = [];
  const effectConsumptions: TileEffectConsumption[] = [];
  const removedLockPositions: BoardPosition[] = [];

  for (let col = 0; col < boardSize; col++) {
    for (let row = 1; row < boardSize; row++) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;

      // Skip values that cannot move (immovable effects)
      if (!canValueMove(tile)) continue;

      let targetRow = row;
      // Find topmost position
      for (let checkRow = row - 1; checkRow >= 0; checkRow--) {
        const checkTile = getTile(newTiles, checkRow, col, boardSize);

        // Black holes don't block movement - tiles pass through and get destroyed
        if (isBlackHoleTile(checkTile)) {
          targetRow = checkRow;
          continue; // Keep searching past the black hole
        }

        if (checkTile.isEmpty) {
          targetRow = checkRow;
        } else if (
          checkTile.value === tile.value &&
          !mergedTiles.has(rowColToIndex(checkRow, col, boardSize)) &&
          canTilesMergeTogether(tile, checkTile)
        ) {
          // Can merge (and neither tile is frozen/stone)
          targetRow = checkRow;
          break;
        } else {
          break;
        }
      }

      if (targetRow !== row) {
        const targetTile = getTile(newTiles, targetRow, col, boardSize);

        // Check if target itself is a destructive barrier, or if there's one in the path
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier
          ? findBlackHoleInPath(
              newTiles,
              boardSize,
              { row, col },
              { row: targetRow, col },
            )
          : null;

        if (targetIsBarrier || blackHolePos) {
          // Determine which black hole destroyed this tile
          const blackHolePosition = targetIsBarrier
            ? { row: targetRow, col }
            : blackHolePos!;

          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize,
          );

          // Tile is destroyed during swipe
          const { scoreLoss: loss, shouldImplode } =
            processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;

          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition,
            },
          });

          // If black hole should implode, mark it for removal
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }

          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (
            !targetTile.isEmpty &&
            targetTile.value === tile.value &&
            canTilesMergeTogether(tile, targetTile)
          ) {
            // Merge tiles
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue,
            );
            effectConsumptions.push(...mergeResult.consumedEffects);

            // Process lock effect on target tile before replacing it
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }

            // Create merged tile, preserving any effect that wasn't consumed
            const mergedTile: SynchronizedTileState = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row: targetRow,
              col: col,
            };

            // Transfer effect if it still exists after processing (not consumed)
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }

            setTile(newTiles, mergedTile, boardSize);

            // Preserve source tile effect at source position if configured
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);

            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(targetRow, col, boardSize));
            mergedTilesCount++;
          } else {
            // Just move
            // If tile has effect that should be preserved, keep it at the source position
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);

            // Check if target position has an effect to transfer
            const targetEffectToTransfer =
              getEffectToPreserveAtSource(targetTile);

            tile.row = targetRow;
            tile.col = col;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            // Transfer target effect to incoming tile
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);

            // Create empty tile at source, preserving source effect if configured
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }

  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions,
  };
}

function swipeDown(
  newTiles: SynchronizedTileState[],
  mergedTiles: Set<number>,
  boardSize: number,
): SwipeResult {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles: DestroyedTile[] = [];
  const effectConsumptions: TileEffectConsumption[] = [];
  const removedLockPositions: BoardPosition[] = [];

  for (let col = 0; col < boardSize; col++) {
    for (let row = boardSize - 2; row >= 0; row--) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;

      // Skip values that cannot move (immovable effects)
      if (!canValueMove(tile)) continue;

      let targetRow = row;
      // Find bottommost position
      for (let checkRow = row + 1; checkRow < boardSize; checkRow++) {
        const checkTile = getTile(newTiles, checkRow, col, boardSize);

        // Black holes don't block movement - tiles pass through and get destroyed
        if (isBlackHoleTile(checkTile)) {
          targetRow = checkRow;
          continue; // Keep searching past the black hole
        }

        if (checkTile.isEmpty) {
          targetRow = checkRow;
        } else if (
          checkTile.value === tile.value &&
          !mergedTiles.has(rowColToIndex(checkRow, col, boardSize)) &&
          canTilesMergeTogether(tile, checkTile)
        ) {
          // Can merge (and neither tile is frozen/stone)
          targetRow = checkRow;
          break;
        } else {
          break;
        }
      }

      if (targetRow !== row) {
        const targetTile = getTile(newTiles, targetRow, col, boardSize);

        // Check if target itself is a destructive barrier, or if there's one in the path
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier
          ? findBlackHoleInPath(
              newTiles,
              boardSize,
              { row, col },
              { row: targetRow, col },
            )
          : null;

        if (targetIsBarrier || blackHolePos) {
          // Determine which black hole destroyed this tile
          const blackHolePosition = targetIsBarrier
            ? { row: targetRow, col }
            : blackHolePos!;

          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize,
          );

          // Tile is destroyed during swipe
          const { scoreLoss: loss, shouldImplode } =
            processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;

          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition,
            },
          });

          // If black hole should implode, mark it for removal
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }

          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (
            !targetTile.isEmpty &&
            targetTile.value === tile.value &&
            canTilesMergeTogether(tile, targetTile)
          ) {
            // Merge tiles
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue,
            );
            effectConsumptions.push(...mergeResult.consumedEffects);

            // Process lock effect on target tile before replacing it
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }

            // Create merged tile, preserving any effect that wasn't consumed
            const mergedTile: SynchronizedTileState = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row: targetRow,
              col,
            };

            // Transfer effect if it still exists after processing (not consumed)
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }

            setTile(newTiles, mergedTile, boardSize);

            // Preserve source tile effect at source position if configured
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);

            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(targetRow, col, boardSize));
            mergedTilesCount++;
          } else {
            // Just move
            // If tile has effect that should be preserved, keep it at the source position
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);

            // Check if target position has an effect to transfer
            const targetEffectToTransfer =
              getEffectToPreserveAtSource(targetTile);

            tile.row = targetRow;
            tile.col = col;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            // Transfer target effect to incoming tile
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);

            // Create empty tile at source, preserving source effect if configured
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }

  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions,
  };
}

/**
 * Perform a swipe in the given direction
 * @param {Object} gameState - Full game state object with tiles, totems, etc.
 * @param {string} direction - Direction to swipe: "left", "right", "up", "down"
 * @returns {Object} Result object with { gameState, moved, score, mergedTilesCount }
 */
export function performSwipe(
  gameState: SynchronizedGameState,
  direction: string,
  randomGenerator: IRandomGenerator,
): PerformSwipeResult {
  let result = { ...gameState };

  // Pre-swipe totem effects
  result = processTotemEffects(
    result,
    {
      type: "PRE_SWIPE",
      direction,
    },
    randomGenerator,
  );

  const tilesSpawned = 0;

  // Create a copy of tiles to work with
  const newTiles = [...result.board.tiles];

  // Clear all statuses
  newTiles.forEach((tile) => {
    if (tile) {
      tile.status = "normal";
    }
  });

  const mergedTiles = new Set<number>();
  let swipeResult: SwipeResult;

  switch (direction) {
    case "left":
      swipeResult = swipeLeft(newTiles, mergedTiles, gameState.board.size);
      break;
    case "right":
      swipeResult = swipeRight(newTiles, mergedTiles, gameState.board.size);
      break;
    case "up":
      swipeResult = swipeUp(newTiles, mergedTiles, gameState.board.size);
      break;
    case "down":
      swipeResult = swipeDown(newTiles, mergedTiles, gameState.board.size);
      break;
    default:
      swipeResult = {
        moved: false,
        score: 0,
        scoreLoss: 0,
        mergedTilesCount: 0,
        mergedTiles,
        destroyedTiles: [],
        effectConsumptions: [],
        removedLockPositions: [],
      };
  }

  const {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions,
  } = swipeResult;
  const netScore = score - scoreLoss;

  // Update game state with new board
  result = {
    ...result,
    board: {
      ...result.board,
      tiles: newTiles,
    },
  };

  // Track positions where effects were removed by merges
  // Freeze/stone are removed by adjacent merges (via processFreezeRemovalFromAdjacentMerge)
  // Lock effects are decremented/removed on the merged tile itself (via processLockTriggerOnMerge in swipe functions)
  // This list is passed to event-based spawning to prevent re-applying effects to the same positions
  const removedEffectPositions: BoardPosition[] = [...removedLockPositions];
  if (mergedTilesCount > 0) {
    newTiles.forEach((tile, index) => {
      if (tile.status === "merged") {
        const { row, col } = indexToRowCol(index, gameState.board.size);

        // Process freeze/stone removal from adjacent tiles
        const freezeRemoved = processFreezeRemovalFromAdjacentMerge(result, {
          row,
          col,
        });
        removedEffectPositions.push(...freezeRemoved);
      }
    });
  }

  // Post-swipe totem effects
  result = processTotemEffects(
    result,
    {
      type: "POST_SWIPE",
      mergeOccurred: mergedTilesCount > 0,
      tilesSpawned,
      direction,
    },
    randomGenerator,
  );

  // Move completion totem effects
  result = processTotemEffects(
    result,
    { type: "MOVE_COMPLETED" },
    randomGenerator,
  );

  // Swipe completion totem effects (for swipe-based despawn logic)
  result = processTotemEffects(
    result,
    { type: "SWIPE_COMPLETED", direction },
    randomGenerator,
  );

  // Process event-based spawning for score updates
  if (netScore > 0) {
    const scoreUpdateEvent: GameEvent = {
      type: "SCORE_UPDATE",
      value: netScore,
    };

    const eventRules = gameState.scenarioConfig?.eventRules;
    if (eventRules && eventRules.length > 0) {
      result = processEventSpawnRules(
        result,
        scoreUpdateEvent,
        eventRules as EventBasedSpawnRule[],
        randomGenerator,
        removedEffectPositions, // Exclude positions where effects were just removed by merges
      );
    }
  }

  return {
    gameState: result,
    moved,
    score: netScore,
    mergedTilesCount,
    removedEffectPositions,
    destroyedTiles,
    effectConsumptions,
  };
}

interface AddRandomTileResult {
  gameState: SynchronizedGameState;
  effectSpawned?: {
    type: TileEffectType;
    position: BoardPosition;
  };
}

/**
 * Add a random tile to the board with totem effects
 * @param {Object} gameState - Full game state object with tiles, totems, etc.
 * @param {RandomGenerator} randomGenerator - Random number generator instance
 * @returns {Object} Modified game state with new tile added (if possible) and spawn info
 */
export function addRandomTileWithEffects(
  gameState: SynchronizedGameState,
  randomGenerator: IRandomGenerator,
): AddRandomTileResult {
  // Only spawn on empty tiles without effects
  const emptyIndices = gameState.board.tiles
    .map((tile, index) => {
      const hasEffect =
        tile.effect && tile.effect.active && tile.effect.type !== "none";
      return tile.isEmpty && !hasEffect ? index : -1;
    })
    .filter((index) => index !== -1);

  if (emptyIndices.length === 0) {
    return { gameState }; // Board is full or no valid spawn positions
  }

  const randomIndex =
    emptyIndices[
      Math.floor(
        randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) *
          emptyIndices.length,
      )
    ];

  // Default tile value (90% chance of 2, 10% chance of 4)
  const value =
    randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) < 0.9 ? 2 : 4;

  // Create a TILE_SPAWN event and process totem effects
  const position: BoardPosition = {
    row: Math.floor(randomIndex / gameState.board.size),
    col: randomIndex % gameState.board.size,
  };
  const spawnEvent: GameEvent = {
    type: "TILE_SPAWN",
    tileValue: value,
    position,
  };

  // Process totem effects that might modify the spawn value
  let modifiedState = processTotemEffects(
    gameState,
    spawnEvent,
    randomGenerator,
  );

  // Use the potentially modified tile value from the event
  const finalValue = spawnEvent.tileValue ?? 0;

  // Create a copy of the tiles array
  const newTiles = [...modifiedState.board.tiles];

  // Add the new tile with the final value (potentially modified by totems)
  newTiles[randomIndex] = {
    isEmpty: false,
    value: finalValue,
    status: "new",
    meta: {},
    ...indexToRowCol(randomIndex, gameState.board.size),
  };

  // Update the game state with the new tile
  modifiedState = {
    ...modifiedState,
    board: {
      ...modifiedState.board,
      tiles: newTiles,
    },
  };

  // Trigger POST_SPAWN event for totems that react after tile placement
  modifiedState = processTotemEffects(
    modifiedState,
    {
      type: "POST_SPAWN",
      spawnedPosition: randomIndex,
      spawnedValue: finalValue,
    },
    randomGenerator,
  );

  // Attempt to spawn a tile effect on the newly spawned tile
  const spawnResult = attemptSpawnEffectOnTile(
    modifiedState,
    randomIndex,
    randomGenerator,
  );

  // If an effect was spawned, emit TILE_EFFECT_APPLIED event
  if (spawnResult.success && spawnResult.effectSpawned) {
    modifiedState = processTotemEffects(
      spawnResult.gameState,
      {
        type: "TILE_EFFECT_APPLIED",
        effectApplied: {
          type: spawnResult.effectSpawned.type,
          position: spawnResult.effectSpawned.position,
          config: spawnResult.effectSpawned.config,
        },
      },
      randomGenerator,
    );

    return {
      gameState: modifiedState,
      effectSpawned: {
        type: spawnResult.effectSpawned.type,
        position: spawnResult.effectSpawned.position,
      },
    };
  } else {
    // No effect spawned, use the original state
    modifiedState = spawnResult.gameState;
    return { gameState: modifiedState };
  }
}

/**
 * Add a random value to the board
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {RandomGenerator} randomGenerator - Random number generator instance
 * @param {number} _boardSize - Size of the board (for API consistency, currently unused)
 * @returns {boolean} True if a tile was added, false if the board is full
 */
export function addRandomValue(
  tiles: SynchronizedTileState[],
  randomGenerator: IRandomGenerator,
  _boardSize: number,
): boolean {
  // Only spawn on empty tiles without effects
  const emptyIndices = tiles
    .map((tile, index) => {
      const hasEffect =
        tile.effect && tile.effect.active && tile.effect.type !== "none";
      return tile.isEmpty && !hasEffect ? index : -1;
    })
    .filter((index) => index !== -1);

  if (emptyIndices.length === 0) {
    return false;
  }

  const randomIndex =
    emptyIndices[
      Math.floor(
        randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) *
          emptyIndices.length,
      )
    ];

  // 90% chance of 2, 10% chance of 4
  const value =
    randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) < 0.9 ? 2 : 4;

  tiles[randomIndex] = {
    ...tiles[randomIndex],
    isEmpty: false,
    status: "new",
    meta: {},
    value,
  };

  return true;
}

/**
 * Update combo multiplier based on merge activity with totem integration
 * @param {Object} gameState - Full game state object
 * @param {number} mergedTilesCount - Number of tiles merged in this move
 * @returns {Object} Updated game state with new combo multiplier
 */
export function updateComboMultiplier(
  gameState: SynchronizedGameState,
  mergedTilesCount: number,
  randomGenerator: IRandomGenerator,
): SynchronizedGameState {
  if (mergedTilesCount === 0) {
    const previousCombo = gameState.comboMultiplier;

    // First, create a state with combo reset to 0
    const resetState = { ...gameState, comboMultiplier: 0 };

    // Then check if combo saver prevents the break
    let modifiedState = processTotemEffects(
      resetState,
      {
        type: "COMBO_BREAK_ATTEMPTED",
        previousCombo: gameState.comboMultiplier, // Pass the original combo value
      },
      randomGenerator,
    );

    // Update trigger states based on new combo value (triggers become idle after combo break)
    modifiedState = updateTriggerStates(modifiedState);

    // If combo actually broke (wasn't saved by totem), process event-based spawning
    if (modifiedState.comboMultiplier === 0 && previousCombo > 0) {
      // Create COMBO_BREAK event
      const comboBreakEvent: GameEvent = {
        type: "COMBO_BREAK",
        previousCombo,
      };

      // Process event-based spawn rules if they exist
      const eventRules = gameState.scenarioConfig?.eventRules;
      if (eventRules && eventRules.length > 0) {
        modifiedState = processEventSpawnRules(
          modifiedState,
          comboBreakEvent,
          eventRules as EventBasedSpawnRule[],
          randomGenerator,
        );

        // Note: resetTriggeredStates() is NOT called here
        // It will be called at the start of the next move to allow visual feedback
      }
    }

    // Return the modified state (either reset to 0 or restored by combo saver)
    return modifiedState;
  }

  // Process combo increment with totem effects
  const increment = mergedTilesCount;
  const incrementEvent: GameEvent = {
    type: "COMBO_INCREMENT",
    incrementAmount: increment,
  };
  let modifiedState = processTotemEffects(
    gameState,
    incrementEvent,
    randomGenerator,
  );

  // Use the potentially modified incrementAmount from the event (momentum idol adds +1)
  const finalIncrement = incrementEvent.incrementAmount || increment;

  modifiedState = {
    ...modifiedState,
    comboMultiplier: gameState.comboMultiplier + finalIncrement,
  };

  // Update trigger states based on new combo value (may become primed)
  modifiedState = updateTriggerStates(modifiedState);

  return modifiedState;
}

/**
 * Calculate total score with combo multiplier applied
 * @param {number} baseScore - Base score from the move
 * @param {number} comboMultiplier - Current combo multiplier
 * @returns {number} Total score with combo applied
 */
export function calculateComboScore(
  baseScore: number,
  comboMultiplier: number,
): number {
  if (comboMultiplier <= 0) {
    return baseScore; // No combo, return base score
  }

  // Multiply base score by combo multiplier
  return baseScore * comboMultiplier;
}
