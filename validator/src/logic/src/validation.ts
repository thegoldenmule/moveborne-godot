import type { SynchronizedTileState } from "./types";
import { getTile, isValidPosition } from "./board";

/**
 * Validation functions for power cards and game rules
 */

/**
 * Check if there are any tiles that can be split
 * Used to determine if the split power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be split
 */
export function hasValidSplitTiles(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);

      // Only check tiles that have values greater than 2 and can be split
      if (!tile.isEmpty && tile.value > 2) {
        return true; // Found a splittable tile
      }
    }
  }

  return false;
}

/**
 * Check if there are any tiles that can be multiplied
 * Used to determine if the multiply power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be multiplied
 */
export function hasValidMultiplyTiles(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);

      // Only check tiles that have values (any tile with a value can be multiplied)
      if (!tile.isEmpty) {
        return true; // Found a tile that can be multiplied
      }
    }
  }

  return false;
}

/**
 * Check if there are any tiles on the board
 * Used to determine if the shuffle power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be shuffled
 */
export function hasValidShuffleTiles(tiles: SynchronizedTileState[]) {
  // Count tiles with values
  let tileCount = 0;
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty) {
      tileCount++;
    }
  }

  // Need at least 2 tiles to make shuffling meaningful
  return tileCount >= 2;
}

/**
 * Check if there are any tiles that can be affected by lightning
 * Used to determine if the lightning power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be doubled
 */
export function hasValidLightningTiles(tiles: SynchronizedTileState[]) {
  // Check if there are any tiles with values on the board
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty) {
      return true; // Found at least one tile that can be doubled
    }
  }

  return false;
}

/**
 * Check if there are any tiles that can be radiated
 * Used to determine if the radiate power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can radiate adjacent tiles
 */
export function hasValidRadiateTiles(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const centerTile = getTile(tiles, row, col, boardSize);

      // Only check tiles that have values
      if (centerTile.isEmpty) continue;

      // Check if this tile has any adjacent tiles with values
      const adjacentPositions = [
        { row: row - 1, col: col - 1 }, // Top-left
        { row: row - 1, col: col }, // Top
        { row: row - 1, col: col + 1 }, // Top-right
        { row: row, col: col - 1 }, // Left
        { row: row, col: col + 1 }, // Right
        { row: row + 1, col: col - 1 }, // Bottom-left
        { row: row + 1, col: col }, // Bottom
        { row: row + 1, col: col + 1 }, // Bottom-right
      ];

      for (const pos of adjacentPositions) {
        if (!isValidPosition(pos.row, pos.col, boardSize)) continue;

        const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
        if (!adjacentTile.isEmpty) {
          return true; // Found a tile that can radiate
        }
      }
    }
  }

  return false;
}

/**
 * Check if there are any tiles that can be cloned
 * Used to determine if the clone power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be cloned
 */
export function hasValidCloneTiles(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);

      // Only check tiles that have values
      if (tile.isEmpty) continue;

      // Check adjacent positions for empty spaces
      const adjacentPositions = [
        { row: row - 1, col: col }, // Up
        { row: row + 1, col: col }, // Down
        { row: row, col: col - 1 }, // Left
        { row: row, col: col + 1 }, // Right
      ];

      for (const pos of adjacentPositions) {
        if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
        const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);

        // If we find an empty adjacent space, clone is possible
        if (adjacentTile.isEmpty) {
          return true;
        }
      }
    }
  }

  return false;
}

/**
 * Check if there are any tiles that can be swapped
 * Used to determine if the swap power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are at least two positions that can be swapped
 */
export function hasValidSwapTiles(tiles: SynchronizedTileState[]) {
  // check that there are 2 tiles with values
  let tileCount = 0;
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty) {
      tileCount++;
    }
  }

  // Need at least 2 tiles to make swapping meaningful
  return tileCount >= 2;
}

/**
 * Check if there are valid tiles for vortex operation
 * Vortex requires at least one non-empty tile in any 2x2 quadrant
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if vortex can be used, false otherwise
 */
export function hasValidVortexTiles(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  // Check each possible 2x2 quadrant position
  for (let row = 0; row < boardSize - 1; row++) {
    for (let col = 0; col < boardSize - 1; col++) {
      if (!isValidPosition(row, col, boardSize)) continue;
      if (!isValidPosition(row, col + 1, boardSize)) continue;
      if (!isValidPosition(row + 1, col, boardSize)) continue;
      if (!isValidPosition(row + 1, col + 1, boardSize)) continue;

      // Check if this 2x2 quadrant has at least one tile with a value
      const topLeft = getTile(tiles, row, col, boardSize);
      const topRight = getTile(tiles, row, col + 1, boardSize);
      const bottomLeft = getTile(tiles, row + 1, col, boardSize);
      const bottomRight = getTile(tiles, row + 1, col + 1, boardSize);

      if (
        !topLeft.isEmpty ||
        !topRight.isEmpty ||
        !bottomLeft.isEmpty ||
        !bottomRight.isEmpty
      ) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Check if there are tiles that can be teleported
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles to teleport and empty spaces to teleport to
 */
export function hasValidTeleportTiles(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  let hasSourceTiles = false;
  let hasEmptySpaces = false;

  // Check for both tiles and empty spaces
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);
      if (!tile.isEmpty) {
        hasSourceTiles = true;
      } else if (tile.isEmpty) {
        hasEmptySpaces = true;
      }
    }
  }

  // Need both source tiles and empty spaces for teleport to be valid
  return hasSourceTiles && hasEmptySpaces;
}

/**
 * Validation function for swap power card - only highlight populated tiles
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for swap
 */
export function isValidSwapPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  if (!isValidPosition(row, col, boardSize)) return false;
  const tile = getTile(tiles, row, col, boardSize);
  // For swap, we want to highlight tiles that have values (populated tiles)
  // since swapping empty spaces is less meaningful
  return !tile.isEmpty;
}

/**
 * Validation function for vortex power card - only highlight valid top-left corners of 2x2 quadrants
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for vortex
 */
export function isValidVortexPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  // Must be a valid top-left corner of a 2x2 quadrant
  if (row >= boardSize - 1 || col >= boardSize - 1) {
    return false;
  }

  // Check if this 2x2 quadrant has at least one tile
  const topLeft = getTile(tiles, row, col, boardSize);
  const topRight = getTile(tiles, row, col + 1, boardSize);
  const bottomLeft = getTile(tiles, row + 1, col, boardSize);
  const bottomRight = getTile(tiles, row + 1, col + 1, boardSize);

  return (
    !topLeft.isEmpty ||
    !topRight.isEmpty ||
    !bottomLeft.isEmpty ||
    !bottomRight.isEmpty
  );
}

/**
 * Validation function for split power card - only highlight tiles that can be split
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for split
 */
export function isValidSplitPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can only split tiles with values greater than 2
  return !tile.isEmpty && tile.value > 2;
}

/**
 * Validation function for multiply power card - only highlight tiles that have values
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for multiply
 */
export function isValidMultiplyPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can multiply any tile that has a value
  return !tile.isEmpty;
}

/**
 * Validation function for radiate power card - only highlight tiles that have values
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for radiate
 */
export function isValidRadiatePosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can only radiate from tiles that have values
  if (tile.isEmpty) return false;

  // Check if there's at least one adjacent tile with a value
  const adjacentPositions = [
    { row: row - 1, col: col - 1 }, // Top-left
    { row: row - 1, col: col }, // Top
    { row: row - 1, col: col + 1 }, // Top-right
    { row: row, col: col - 1 }, // Left
    { row: row, col: col + 1 }, // Right
    { row: row + 1, col: col - 1 }, // Bottom-left
    { row: row + 1, col: col }, // Bottom
    { row: row + 1, col: col + 1 }, // Bottom-right
  ];

  for (const pos of adjacentPositions) {
    if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
    const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
    if (!adjacentTile.isEmpty) {
      return true; // Found at least one adjacent tile with a value
    }
  }

  return false; // No adjacent tiles with values
}

/**
 * Validation function for clone power card - only highlight tiles that have values (for source selection)
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for clone source
 */
export function isValidCloneSourcePosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can only clone from tiles that have values
  if (tile.isEmpty) return false;

  // Check if there's at least one adjacent empty space
  const adjacentPositions = [
    { row: row - 1, col: col }, // Up
    { row: row + 1, col: col }, // Down
    { row: row, col: col - 1 }, // Left
    { row: row, col: col + 1 }, // Right
  ];

  for (const pos of adjacentPositions) {
    if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
    const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
    if (adjacentTile.isEmpty) {
      return true; // Found at least one adjacent empty space
    }
  }

  return false; // No adjacent empty spaces
}

/**
 * Validation function for clone power card target selection - only highlight empty adjacent positions
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @param {Object} sourcePos - Source position {row, col} for adjacency check
 * @returns {boolean} True if this position should be highlighted for clone target
 */
export function isValidCloneTargetPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
  sourcePos: SynchronizedTileState,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Must be empty
  if (!tile.isEmpty) {
    return false;
  }

  // Must be adjacent to source
  if (sourcePos) {
    const isAdjacent =
      Math.abs(sourcePos.row - row) + Math.abs(sourcePos.col - col) === 1;
    return isAdjacent;
  }

  return true; // If no source specified, highlight all empty spaces
}

/**
 * Validation function for lightning power card - only highlight columns that have tiles
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate (ignored for column selection)
 * @param {number} col - Column to validate
 * @returns {boolean} True if this column should be highlighted for lightning
 */
export function isValidLightningColumn(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  // Check if this column has any tiles
  for (let r = 0; r < boardSize; r++) {
    const tile = getTile(tiles, r, col, boardSize);
    if (!tile.isEmpty) {
      return true;
    }
  }
  return false;
}

/**
 * Check if a position is valid for teleport source selection
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position contains a tile with value
 */
export function isValidTeleportSourcePosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty;
}

/**
 * Check if a position is valid for teleport target selection
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position is empty
 */
export function isValidTeleportTargetPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return tile.isEmpty;
}

/**
 * Check if there are any valid tiles for bomb operation
 * A tile is valid if it has a value or an effect
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid tiles for bombing
 */
export function hasValidBombTiles(tiles: SynchronizedTileState[]) {
  // Check if there are any tiles with values or effects
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty || tiles[i].effect) {
      return true; // Found at least one tile that can be bombed
    }
  }
  return false;
}

/**
 * Check if a position is valid for bomb operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position has a tile with value or effect
 */
export function isValidBombPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can bomb tiles with values or effects
  return !tile.isEmpty || !!tile.effect;
}

/**
 * Check if there are any valid tiles for destroy operation
 * A tile is valid if it has a value but NO active effect
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid tiles for destroying
 */
export function hasValidDestroyTiles(tiles: SynchronizedTileState[]) {
  // Check if there are any tiles with values but no active effects
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty && !tiles[i].effect?.active) {
      return true; // Found at least one tile that can be destroyed
    }
  }
  return false;
}

/**
 * Check if a position is valid for destroy operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position has a tile with value but no active effect
 */
export function isValidDestroyPosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can destroy tiles with values but NO active effects
  return !tile.isEmpty && !tile.effect?.active;
}

/**
 * Check if there are any valid columns for clear operation
 * A column is valid if it has at least one non-empty tile WITHOUT active effects
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid columns for clearing
 */
export function hasValidClearColumns(tiles: SynchronizedTileState[]) {
  const boardSize = Math.sqrt(tiles.length);
  // Check each column
  for (let col = 0; col < boardSize; col++) {
    for (let row = 0; row < boardSize; row++) {
      const tile = getTile(tiles, row, col, boardSize);
      // Only non-empty tiles without active effects can be cleared
      if (!tile.isEmpty && !tile.effect?.active) {
        return true; // Found at least one clearable tile in a column
      }
    }
  }
  return false;
}

/**
 * Check if a column is valid for clear operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} col - Column index
 * @returns {boolean} True if column has at least one non-empty tile without active effects
 */
export function isValidClearColumn(
  tiles: SynchronizedTileState[],
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  // Check if column has any non-empty tiles without active effects
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(tiles, row, col, boardSize);
    // Only non-empty tiles without active effects can be cleared
    if (!tile.isEmpty && !tile.effect?.active) {
      return true;
    }
  }
  return false;
}

/**
 * Check if there are any valid tiles for double (amplify) operation
 * A tile is valid if it has a value but NO active effect
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid tiles for doubling
 */
export function hasValidDoubleTiles(tiles: SynchronizedTileState[]) {
  // Check if there are any tiles with values but no active effects
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty && !tiles[i].effect?.active) {
      return true; // Found at least one tile that can be doubled
    }
  }
  return false;
}

/**
 * Check if a position is valid for double (amplify) operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position has a tile with value but no active effect
 */
export function isValidDoublePosition(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
): boolean {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  // Can double tiles with values but NO active effects
  return !tile.isEmpty && !tile.effect?.active;
}

export function hasValidTransformTiles(tiles: SynchronizedTileState[]) {
  for (let i = 0; i < tiles.length; i++) {
    if (tiles[i].effect && tiles[i].effect?.type !== "none") {
      return true;
    }
  }
  return false;
}
