import type { SynchronizedTileState } from "./types";

/**
 * Board utility functions for tile position management
 */

export function indexToRowCol(
  index: number,
  boardSize: number,
): {
  row: number;
  col: number;
} {
  return {
    row: Math.floor(index / boardSize),
    col: index % boardSize,
  };
}

export function rowColToIndex(row: number, col: number, boardSize: number) {
  return row * boardSize + col;
}

export function isValidPosition(row: number, col: number, boardSize: number) {
  return row >= 0 && row < boardSize && col >= 0 && col < boardSize;
}

export function getTile(
  tiles: SynchronizedTileState[],
  row: number,
  col: number,
  boardSize: number,
): SynchronizedTileState {
  if (!isValidPosition(row, col, boardSize)) {
    throw new Error("Invalid row or column");
  }

  return tiles[rowColToIndex(row, col, boardSize)];
}

export function setTile(
  tiles: SynchronizedTileState[],
  tile: SynchronizedTileState,
  boardSize: number,
) {
  tiles[rowColToIndex(tile.row, tile.col, boardSize)] = tile;
}
