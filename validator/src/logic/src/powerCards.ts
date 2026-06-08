import { RNG_NAMESPACES } from "./constants";
import { createEmptyTile } from "./factories";
import type { SynchronizedTileState } from "./types";
import { IRandomGenerator } from "./random";
import { getTile, indexToRowCol, isValidPosition, setTile } from "./board";

/**
 * Power card functions for special tile operations
 */

/**
 * Clear all tile statuses before applying power card effects
 * This ensures client and server have matching state
 */
function clearTileStatuses(
  tiles: SynchronizedTileState[],
): SynchronizedTileState[] {
  const clearedTiles = [...tiles];
  clearedTiles.forEach((tile) => {
    if (tile && !tile.isEmpty) {
      tile.status = "normal";
    }
  });
  return clearedTiles;
}

/**
 * Perform a power card split operation on a tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tilePos - Tile position {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardSplit(
  tiles: SynchronizedTileState[],
  tilePos: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate input parameters
  if (!tilePos || tilePos.row === undefined || tilePos.col === undefined) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position not provided",
    };
  }

  // Validate position is within bounds
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position out of bounds",
    };
  }

  // Get the tile from the board
  const tileData = getTile(newTiles, tilePos.row, tilePos.col, boardSize);

  // Verify tile exists and has a value greater than 2 (so it can be split)
  if (tileData.isEmpty || tileData.value <= 2) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Calculate split value (half of original)
  const splitValue = tileData.value / 2;

  // Update the original tile to half value
  setTile(
    newTiles,
    {
      value: splitValue,
      status: "split",
      meta: {},
      row: tilePos.row,
      col: tilePos.col,
      isEmpty: false,
      effect: tileData.effect,
    },
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Split doesn't give score
  };
}

/**
 * Perform a power card multiply operation on a tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tilePos - Position object with row and col properties
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardMultiply(
  tiles: SynchronizedTileState[],
  tilePos: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate input parameters
  if (!tilePos || tilePos.row === undefined || tilePos.col === undefined) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position not provided",
    };
  }

  // Validate position is within bounds
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position out of bounds",
    };
  }

  // Get the tile from the board
  const tileData = getTile(newTiles, tilePos.row, tilePos.col, boardSize);

  // Verify tile exists and has a value
  if (tileData.isEmpty || !tileData.value) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Calculate multiplied value (double the original)
  const multipliedValue = tileData.value * 2;

  // Update the tile to double value
  setTile(
    newTiles,
    {
      value: multipliedValue,
      status: "multiplied",
      meta: {},
      row: tilePos.row,
      col: tilePos.col,
      isEmpty: false,
      effect: tileData.effect,
    },
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Multiply doesn't give score
  };
}

/**
 * Perform a power card shuffle operation on the entire board
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardShuffle(
  tiles: SynchronizedTileState[],
  randomGenerator: IRandomGenerator,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Extract all non-empty tiles from the board
  const existingTiles: SynchronizedTileState[] = [];
  for (let i = 0; i < newTiles.length; i++) {
    if (!newTiles[i].isEmpty) {
      existingTiles.push({
        ...newTiles[i],
        status: "shuffled", // Mark as shuffled for animation
      });
    }
  }

  // Validate that there are tiles to shuffle
  if (existingTiles.length === 0) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Clear the board with empty tiles
  for (let i = 0; i < newTiles.length; i++) {
    const { row, col } = indexToRowCol(i, boardSize);
    newTiles[i] = createEmptyTile(row, col);
  }

  // Shuffle the existing tiles using Fisher-Yates algorithm
  for (let i = existingTiles.length - 1; i > 0; i--) {
    const j = Math.floor(
      randomGenerator.getRandom(RNG_NAMESPACES.SHUFFLE) * (i + 1),
    );
    [existingTiles[i], existingTiles[j]] = [existingTiles[j], existingTiles[i]];
  }

  // Get all available positions (indices)
  const availablePositions = [];
  for (let i = 0; i < newTiles.length; i++) {
    availablePositions.push(i);
  }

  // Shuffle the available positions
  for (let i = availablePositions.length - 1; i > 0; i--) {
    const j = Math.floor(
      randomGenerator.getRandom(RNG_NAMESPACES.SHUFFLE) * (i + 1),
    );
    [availablePositions[i], availablePositions[j]] = [
      availablePositions[j],
      availablePositions[i],
    ];
  }

  // Place the shuffled tiles in the shuffled positions
  for (let i = 0; i < existingTiles.length; i++) {
    const targetIndex = availablePositions[i];
    const { row, col } = indexToRowCol(targetIndex, boardSize);
    newTiles[targetIndex] = {
      ...existingTiles[i],
      row,
      col,
    };
  }

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Shuffle doesn't give score
  };
}

/**
 * Perform a power card lightning operation on a column
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} column - Column index to double (0-3)
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardLightning(
  tiles: SynchronizedTileState[],
  column: number | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate column parameter
  if (column === undefined || column < 0 || column >= boardSize) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Invalid column",
    };
  }

  // Check if there are any tiles in the specified column
  let hasValidTiles = false;
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (tile && tile.value) {
      hasValidTiles = true;
      break;
    }
  }

  if (!hasValidTiles) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  let totalScore = 0;

  // Double all tiles in the specified column
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (!tile.isEmpty) {
      const newValue = tile.value * 2;
      setTile(
        newTiles,
        {
          isEmpty: false,
          row: row,
          col: column,
          value: newValue,
          status: "lightning", // Mark as lightning for animation
          meta: {},
          effect: tile.effect,
        },
        boardSize,
      );
      totalScore += newValue; // Add the new value to score
    }
  }

  return {
    tiles: newTiles,
    success: true,
    score: totalScore,
  };
}

/**
 * Perform a power card radiate operation on a tile
 * Doubles all tiles adjacent to the selected tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tilePos - Position object with row and col properties
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardRadiate(
  tiles: SynchronizedTileState[],
  tilePos: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate input parameters
  if (!tilePos || tilePos.row === undefined || tilePos.col === undefined) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position not provided",
    };
  }

  // Validate position is within bounds
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position out of bounds",
    };
  }

  // Get the center tile from the board
  const centerTile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);

  // Verify center tile exists and has a value
  if (!centerTile || !centerTile.value) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Get all adjacent positions (up, down, left, right, and diagonals)
  const adjacentPositions = [
    { row: tilePos.row - 1, col: tilePos.col - 1 }, // Top-left
    { row: tilePos.row - 1, col: tilePos.col }, // Top
    { row: tilePos.row - 1, col: tilePos.col + 1 }, // Top-right
    { row: tilePos.row, col: tilePos.col - 1 }, // Left
    { row: tilePos.row, col: tilePos.col + 1 }, // Right
    { row: tilePos.row + 1, col: tilePos.col - 1 }, // Bottom-left
    { row: tilePos.row + 1, col: tilePos.col }, // Bottom
    { row: tilePos.row + 1, col: tilePos.col + 1 }, // Bottom-right
  ];

  let totalScore = 0;
  let affectedTiles = 0;

  // Double all adjacent tiles that have values
  for (const pos of adjacentPositions) {
    // Check if position is valid before getting tile
    if (!isValidPosition(pos.row, pos.col, boardSize)) continue;

    const adjacentTile = getTile(newTiles, pos.row, pos.col, boardSize);
    if (!adjacentTile.isEmpty) {
      const newValue = adjacentTile.value * 2;
      setTile(
        newTiles,
        {
          value: newValue,
          status: "radiated", // Mark as radiated for animation
          meta: {},
          row: pos.row,
          col: pos.col,
          isEmpty: false,
          effect: adjacentTile.effect,
        },
        boardSize,
      );
      totalScore += newValue; // Add the new value to score
      affectedTiles++;
    }
  }

  // If no adjacent tiles were affected, the operation fails
  if (affectedTiles === 0) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  return {
    tiles: newTiles,
    success: true,
    score: totalScore,
  };
}

/**
 * Perform a power card clone operation on a tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} sourceTilePos - Position of the tile to clone {row, col}
 * @param {Object} targetTilePos - Position where to place the clone {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardClone(
  tiles: SynchronizedTileState[],
  sourceTilePos: SynchronizedTileState | undefined,
  targetTilePos: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate input parameters
  if (
    !sourceTilePos ||
    sourceTilePos.row === undefined ||
    sourceTilePos.col === undefined ||
    !targetTilePos ||
    targetTilePos.row === undefined ||
    targetTilePos.col === undefined
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position not provided",
    };
  }

  // Validate positions are within bounds
  if (
    !isValidPosition(sourceTilePos.row, sourceTilePos.col, boardSize) ||
    !isValidPosition(targetTilePos.row, targetTilePos.col, boardSize)
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position out of bounds",
    };
  }

  // Get the source tile from the board
  const sourceTile = getTile(
    newTiles,
    sourceTilePos.row,
    sourceTilePos.col,
    boardSize,
  );

  // Verify source tile exists and has a value
  if (sourceTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Verify target position is empty
  const targetTile = getTile(
    newTiles,
    targetTilePos.row,
    targetTilePos.col,
    boardSize,
  );
  if (!targetTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Verify target position is adjacent to source
  const isAdjacent =
    Math.abs(sourceTilePos.row - targetTilePos.row) +
      Math.abs(sourceTilePos.col - targetTilePos.col) ===
    1;

  if (!isAdjacent) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Clone the tile to the target position
  setTile(
    newTiles,
    {
      value: sourceTile.value,
      status: "cloned",
      meta: {},
      row: targetTilePos.row,
      col: targetTilePos.col,
      isEmpty: false,
      effect: sourceTile.effect,
    },
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Clone doesn't give score
  };
}

/**
 * Perform a power card swap operation on two tiles
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tile1 - First tile position {row, col}
 * @param {Object} tile2 - Second tile position {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardSwap(
  tiles: SynchronizedTileState[],
  tile1: SynchronizedTileState | undefined,
  tile2: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate input parameters
  if (
    !tile1 ||
    tile1.row === undefined ||
    tile1.col === undefined ||
    !tile2 ||
    tile2.row === undefined ||
    tile2.col === undefined
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile positions not provided",
    };
  }

  // Validate positions are within bounds
  if (
    !isValidPosition(tile1.row, tile1.col, boardSize) ||
    !isValidPosition(tile2.row, tile2.col, boardSize)
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile positions out of bounds",
    };
  }

  // Verify that the two positions are different
  if (tile1.row === tile2.row && tile1.col === tile2.col) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Get the tiles from the board
  const tileData1 = getTile(newTiles, tile1.row, tile1.col, boardSize);
  const tileData2 = getTile(newTiles, tile2.row, tile2.col, boardSize);

  // verify that the two tiles are not empty
  if (tileData1.isEmpty || tileData2.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Swap the tiles (can swap any two tiles, including empty spaces)
  setTile(
    newTiles,
    !tileData2.isEmpty
      ? {
          ...tileData2,
          row: tile1.row,
          col: tile1.col,
          status: "swapped",
          meta: {},
        }
      : createEmptyTile(tile1.row, tile1.col),
    boardSize,
  );

  setTile(
    newTiles,
    tileData1
      ? {
          ...tileData1,
          row: tile2.row,
          col: tile2.col,
          status: "swapped",
          meta: {},
        }
      : createEmptyTile(tile2.row, tile2.col),
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Swap doesn't give score
  };
}

/**
 * Perform a power card vortex operation on a 2x2 quadrant
 * Rotates the selected 2x2 quadrant clockwise
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} quadrantPos - Position object with row and col properties for top-left corner
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardVortex(
  tiles: SynchronizedTileState[],
  quadrantPos: { row?: number; col?: number },
  boardSize: number,
) {
  if (undefined === quadrantPos.row || undefined === quadrantPos.col) {
    return {
      tiles: tiles,
      success: false,
      score: 0,
      error: "Row or column not provided",
    };
  }

  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // If any position is out of bounds, return false
  if (
    !isValidPosition(quadrantPos.row, quadrantPos.col, boardSize) ||
    !isValidPosition(quadrantPos.row + 1, quadrantPos.col + 1, boardSize) ||
    !isValidPosition(quadrantPos.row + 1, quadrantPos.col, boardSize) ||
    !isValidPosition(quadrantPos.row, quadrantPos.col + 1, boardSize)
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Invalid quadrant position",
    };
  }

  // Get the four tiles in the 2x2 quadrant
  const topLeft = getTile(
    newTiles,
    quadrantPos.row,
    quadrantPos.col,
    boardSize,
  );
  const topRight = getTile(
    newTiles,
    quadrantPos.row,
    quadrantPos.col + 1,
    boardSize,
  );
  const bottomLeft = getTile(
    newTiles,
    quadrantPos.row + 1,
    quadrantPos.col,
    boardSize,
  );
  const bottomRight = getTile(
    newTiles,
    quadrantPos.row + 1,
    quadrantPos.col + 1,
    boardSize,
  );

  // Perform clockwise rotation:
  // topLeft -> topRight
  // topRight -> bottomRight
  // bottomRight -> bottomLeft
  // bottomLeft -> topLeft
  setTile(
    newTiles,
    {
      ...topLeft,
      row: quadrantPos.row,
      col: quadrantPos.col + 1,
    },
    boardSize,
  ); // topLeft -> topRight
  setTile(
    newTiles,
    {
      ...topRight,
      row: quadrantPos.row + 1,
      col: quadrantPos.col + 1,
    },
    boardSize,
  ); // topRight -> bottomRight
  setTile(
    newTiles,
    {
      ...bottomRight,
      row: quadrantPos.row + 1,
      col: quadrantPos.col,
    },
    boardSize,
  ); // bottomRight -> bottomLeft
  setTile(
    newTiles,
    {
      ...bottomLeft,
      row: quadrantPos.row,
      col: quadrantPos.col,
    },
    boardSize,
  ); // bottomLeft -> topLeft

  // Mark rotated tiles for animation
  if (getTile(newTiles, quadrantPos.row, quadrantPos.col, boardSize)) {
    getTile(newTiles, quadrantPos.row, quadrantPos.col, boardSize).status =
      "rotated";
  }
  if (getTile(newTiles, quadrantPos.row, quadrantPos.col + 1, boardSize)) {
    getTile(newTiles, quadrantPos.row, quadrantPos.col + 1, boardSize).status =
      "rotated";
  }
  if (getTile(newTiles, quadrantPos.row + 1, quadrantPos.col, boardSize)) {
    getTile(newTiles, quadrantPos.row + 1, quadrantPos.col, boardSize).status =
      "rotated";
  }
  if (getTile(newTiles, quadrantPos.row + 1, quadrantPos.col + 1, boardSize)) {
    getTile(
      newTiles,
      quadrantPos.row + 1,
      quadrantPos.col + 1,
      boardSize,
    ).status = "rotated";
  }

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Vortex is a utility card that doesn't generate score
  };
}

/**
 * Perform a power card teleport operation on a tile
 * Move a tile from source position to target empty position
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} sourceTilePos - Position of the tile to teleport {row, col}
 * @param {Object} targetTilePos - Position where to teleport the tile {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardTeleport(
  tiles: SynchronizedTileState[],
  sourceTilePos: SynchronizedTileState | undefined,
  targetTilePos: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear all tile statuses before applying power card
  const clearedTiles = clearTileStatuses(tiles);

  // Create a copy of tiles to work with
  const newTiles = [...clearedTiles];

  // Validate input parameters
  if (
    !sourceTilePos ||
    sourceTilePos.row === undefined ||
    sourceTilePos.col === undefined ||
    !targetTilePos ||
    targetTilePos.row === undefined ||
    targetTilePos.col === undefined
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position not provided",
    };
  }

  // Validate positions are within bounds
  if (
    !isValidPosition(sourceTilePos.row, sourceTilePos.col, boardSize) ||
    !isValidPosition(targetTilePos.row, targetTilePos.col, boardSize)
  ) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position out of bounds",
    };
  }

  // Verify target position is different from source
  if (
    sourceTilePos.row === targetTilePos.row &&
    sourceTilePos.col === targetTilePos.col
  ) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Get the source tile from the board
  const sourceTile = getTile(
    newTiles,
    sourceTilePos.row,
    sourceTilePos.col,
    boardSize,
  );

  // Verify source tile exists and has a value
  if (sourceTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Verify target position is empty
  const targetTile = getTile(
    newTiles,
    targetTilePos.row,
    targetTilePos.col,
    boardSize,
  );
  if (!targetTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Move the tile to the target position
  setTile(
    newTiles,
    {
      value: sourceTile.value,
      status: "teleported",
      meta: {},
      row: targetTilePos.row,
      col: targetTilePos.col,
      isEmpty: false,
      effect: sourceTile.effect,
    },
    boardSize,
  );

  // Remove the tile from the source position
  setTile(
    newTiles,
    createEmptyTile(sourceTilePos.row, sourceTilePos.col),
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: 0, // Teleport doesn't give score
  };
}

/**
 * Perform a bomb operation on a tile
 * Removes all effects from the tile and negates score by tile value
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} targetTile - Target tile to bomb
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardBomb(
  tiles: SynchronizedTileState[],
  targetTile: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear tile statuses first
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];

  // Validate target tile exists
  if (!targetTile) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  const tilePos = { row: targetTile.row, col: targetTile.col };

  // Validate position is on board
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Get the target tile from the board
  const tile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);

  // Verify tile exists and has a value or effect
  if (tile.isEmpty && !tile.effect) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Calculate negative score (negate the tile value)
  const negativeScore = tile.isEmpty ? 0 : -tile.value;

  // Remove all effects from the tile and set value to 0
  setTile(
    newTiles,
    {
      ...tile,
      isEmpty: true,
      value: 0,
      effect: undefined,
      status: "bombed",
    },
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: negativeScore, // Negative score to reduce player's score
  };
}

/**
 * Destroy power card - destroys a tile without effects and negates score
 * @param {SynchronizedTileState[]} tiles - Current board state
 * @param {SynchronizedTileState} targetTile - Tile to destroy
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardDestroy(
  tiles: SynchronizedTileState[],
  targetTile: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear tile statuses first
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];

  // Validate target tile exists
  if (!targetTile) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  const tilePos = { row: targetTile.row, col: targetTile.col };

  // Validate position is on board
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Get the target tile from the board
  const tile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);

  // Verify tile exists and has a value but NO effect
  if (tile.isEmpty || tile.effect) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Calculate negative score (negate the tile value)
  const negativeScore = -tile.value;

  // Destroy the tile (set to empty)
  setTile(
    newTiles,
    {
      ...tile,
      isEmpty: true,
      value: 0,
      status: "destroyed",
    },
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: negativeScore, // Negative score to reduce player's score
  };
}

/**
 * Clear (Purge Column) power card - clears tiles without effects in a column with no score change
 * @param {SynchronizedTileState[]} tiles - Current board state
 * @param {number} column - Column index (0-3) to clear
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardClear(
  tiles: SynchronizedTileState[],
  column: number | undefined,
  boardSize: number,
) {
  // Clear tile statuses first
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];

  // Validate column parameter
  if (column === undefined || column < 0 || column >= boardSize) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Check if there are any non-empty tiles without effects in this column
  let hasClearableTiles = false;
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (!tile.isEmpty && !tile.effect) {
      hasClearableTiles = true;
      break;
    }
  }

  if (!hasClearableTiles) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Clear only tiles without effects in the column
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    // Only clear tiles that have no effects
    if (!tile.isEmpty && !tile.effect) {
      setTile(
        newTiles,
        {
          ...tile,
          isEmpty: true,
          value: 0,
          status: "purged",
        },
        boardSize,
      );
    }
  }

  return {
    tiles: newTiles,
    success: true,
    score: 0, // No score change for purge
  };
}

/**
 * Double (Amplify) power card - doubles a tile's value if it has no effects
 * @param {SynchronizedTileState[]} tiles - Current board state
 * @param {SynchronizedTileState} targetTile - Tile to amplify
 * @returns {Object} Result object with { tiles, success, score }
 */
export function performPowerCardDouble(
  tiles: SynchronizedTileState[],
  targetTile: SynchronizedTileState | undefined,
  boardSize: number,
) {
  // Clear tile statuses first
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];

  // Validate target tile exists
  if (!targetTile) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  const tilePos = { row: targetTile.row, col: targetTile.col };

  // Validate position is on board
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Get the target tile from the board
  const tile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);

  // Verify tile has a value and NO effect
  if (tile.isEmpty || tile.effect) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  // Double the tile value
  const newValue = tile.value * 2;

  setTile(
    newTiles,
    {
      ...tile,
      value: newValue,
      status: "amplified",
    },
    boardSize,
  );

  return {
    tiles: newTiles,
    success: true,
    score: newValue, // Add the new value as score
  };
}

export function performPowerCardTransform(
  tiles: SynchronizedTileState[],
  numEffects: number,
  randomGenerator: IRandomGenerator,
  boardSize: number,
) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];

  const tilesWithEffects: number[] = [];
  for (let i = 0; i < newTiles.length; i++) {
    if (newTiles[i].effect && newTiles[i].effect?.type !== "none") {
      tilesWithEffects.push(i);
    }
  }

  if (tilesWithEffects.length === 0) {
    return { tiles: newTiles, success: false, score: 0 };
  }

  for (let i = tilesWithEffects.length - 1; i > 0; i--) {
    const j = Math.floor(
      randomGenerator.getRandom(RNG_NAMESPACES.SHUFFLE) * (i + 1),
    );
    [tilesWithEffects[i], tilesWithEffects[j]] = [
      tilesWithEffects[j],
      tilesWithEffects[i],
    ];
  }

  const tilesToTransform = tilesWithEffects.slice(
    0,
    Math.min(numEffects, tilesWithEffects.length),
  );

  for (const index of tilesToTransform) {
    const { row, col } = indexToRowCol(index, boardSize);
    const tile = getTile(newTiles, row, col, boardSize);
    setTile(
      newTiles,
      {
        ...tile,
        effect: undefined,
        status: "normal",
      },
      boardSize,
    );
  }

  return {
    tiles: newTiles,
    success: true,
    score: 0,
  };
}
