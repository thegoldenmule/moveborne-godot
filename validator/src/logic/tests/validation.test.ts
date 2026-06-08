import { describe, expect, it } from "vitest";
import type { SynchronizedTileState } from "../src/types";
import {
  hasValidClearColumns,
  hasValidSplitTiles,
  hasValidVortexTiles,
  isValidClearColumn,
  isValidLightningColumn,
  isValidVortexPosition,
} from "../src/validation";

describe("hasValidSplitTiles", () => {
  const createEmptyBoard = (boardSize: number): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < boardSize; row++) {
      for (let col = 0; col < boardSize; col++) {
        tiles.push({
          isEmpty: true,
          value: 0,
          status: "normal",
          row,
          col,
        });
      }
    }
    return tiles;
  };

  const createTileWithValue = (
    row: number,
    col: number,
    value: number,
  ): SynchronizedTileState => ({
    isEmpty: false,
    value,
    status: "normal",
    row,
    col,
  });

  it("should return false when 4x4 board is completely empty", () => {
    const tiles = createEmptyBoard(4);
    expect(hasValidSplitTiles(tiles)).toBe(false);
  });

  it("should return false when 4x4 board has only tiles with value 2", () => {
    const tiles = createEmptyBoard(4);
    tiles[0] = createTileWithValue(0, 0, 2);
    tiles[5] = createTileWithValue(1, 1, 2);
    tiles[10] = createTileWithValue(2, 2, 2);
    expect(hasValidSplitTiles(tiles)).toBe(false);
  });

  it("should return true when 4x4 board has a tile with value 4", () => {
    const tiles = createEmptyBoard(4);
    tiles[0] = createTileWithValue(0, 0, 4);
    expect(hasValidSplitTiles(tiles)).toBe(true);
  });

  it("should return true when 4x4 board has multiple splittable tiles", () => {
    const tiles = createEmptyBoard(4);
    tiles[0] = createTileWithValue(0, 0, 4);
    tiles[5] = createTileWithValue(1, 1, 8);
    tiles[10] = createTileWithValue(2, 2, 16);
    expect(hasValidSplitTiles(tiles)).toBe(true);
  });

  it("should return true when 4x4 board has mix of splittable and non-splittable tiles", () => {
    const tiles = createEmptyBoard(4);
    tiles[0] = createTileWithValue(0, 0, 2);
    tiles[1] = createTileWithValue(0, 1, 2);
    tiles[3] = createTileWithValue(0, 3, 4);
    expect(hasValidSplitTiles(tiles)).toBe(true);
  });

  it("should return false when 4x4 tiles have values but all are 2 or less", () => {
    const tiles = createEmptyBoard(4);
    const boardSize = 4;
    for (let i = 0; i < tiles.length; i++) {
      tiles[i] = createTileWithValue(
        Math.floor(i / boardSize),
        i % boardSize,
        2,
      );
    }
    expect(hasValidSplitTiles(tiles)).toBe(false);
  });

  it("should work correctly on 6x6 board", () => {
    const tiles = createEmptyBoard(6);
    tiles[0] = createTileWithValue(0, 0, 4);
    expect(hasValidSplitTiles(tiles)).toBe(true);

    const emptyTiles = createEmptyBoard(6);
    expect(hasValidSplitTiles(emptyTiles)).toBe(false);
  });

  it("should work correctly on 8x8 board", () => {
    const tiles = createEmptyBoard(8);
    tiles[0] = createTileWithValue(0, 0, 8);
    expect(hasValidSplitTiles(tiles)).toBe(true);

    const emptyTiles = createEmptyBoard(8);
    expect(hasValidSplitTiles(emptyTiles)).toBe(false);
  });
});

describe("hasValidVortexTiles - variable board sizes", () => {
  const createEmptyBoard = (boardSize: number): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < boardSize; row++) {
      for (let col = 0; col < boardSize; col++) {
        tiles.push({
          isEmpty: true,
          value: 0,
          status: "normal",
          row,
          col,
        });
      }
    }
    return tiles;
  };

  it("should return false when 4x4 board is empty", () => {
    const tiles = createEmptyBoard(4);
    expect(hasValidVortexTiles(tiles)).toBe(false);
  });

  it("should return true when 4x4 board has a tile in valid quadrant", () => {
    const tiles = createEmptyBoard(4);
    tiles[0] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 0 };
    expect(hasValidVortexTiles(tiles)).toBe(true);
  });

  it("should return true when 8x8 board has more valid vortex positions", () => {
    const tiles = createEmptyBoard(8);
    tiles[0] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 0 };
    expect(hasValidVortexTiles(tiles)).toBe(true);
  });

  it("should work on 6x6 board", () => {
    const tiles = createEmptyBoard(6);
    tiles[7] = { isEmpty: false, value: 4, status: "normal", row: 1, col: 1 };
    expect(hasValidVortexTiles(tiles)).toBe(true);
  });
});

describe("isValidVortexPosition - variable board sizes", () => {
  const createEmptyBoard = (boardSize: number): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < boardSize; row++) {
      for (let col = 0; col < boardSize; col++) {
        tiles.push({
          isEmpty: true,
          value: 0,
          status: "normal",
          row,
          col,
        });
      }
    }
    return tiles;
  };

  it("should reject positions at bottom-right edge on 4x4 board", () => {
    const tiles = createEmptyBoard(4);
    expect(isValidVortexPosition(tiles, 3, 3)).toBe(false);
  });

  it("should allow more positions on 8x8 board than 4x4", () => {
    const tiles8x8 = createEmptyBoard(8);
    tiles8x8[0] = {
      isEmpty: false,
      value: 2,
      status: "normal",
      row: 0,
      col: 0,
    };

    expect(isValidVortexPosition(tiles8x8, 6, 6)).toBe(false);
    expect(isValidVortexPosition(tiles8x8, 7, 7)).toBe(false);

    const tiles4x4 = createEmptyBoard(4);
    tiles4x4[0] = {
      isEmpty: false,
      value: 2,
      status: "normal",
      row: 0,
      col: 0,
    };
    expect(isValidVortexPosition(tiles4x4, 0, 0)).toBe(true);
    expect(isValidVortexPosition(tiles8x8, 0, 0)).toBe(true);
  });
});

describe("isValidLightningColumn - variable board sizes", () => {
  const createEmptyBoard = (boardSize: number): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < boardSize; row++) {
      for (let col = 0; col < boardSize; col++) {
        tiles.push({
          isEmpty: true,
          value: 0,
          status: "normal",
          row,
          col,
        });
      }
    }
    return tiles;
  };

  it("should work correctly on 6x6 board", () => {
    const tiles = createEmptyBoard(6);
    tiles[5] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 5 };
    expect(isValidLightningColumn(tiles, 0, 5)).toBe(true);
    expect(isValidLightningColumn(tiles, 0, 0)).toBe(false);
  });

  it("should work correctly on 8x8 board", () => {
    const tiles = createEmptyBoard(8);
    tiles[7] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 7 };
    expect(isValidLightningColumn(tiles, 0, 7)).toBe(true);
    expect(isValidLightningColumn(tiles, 0, 0)).toBe(false);
  });
});

describe("hasValidClearColumns - variable board sizes", () => {
  const createEmptyBoard = (boardSize: number): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < boardSize; row++) {
      for (let col = 0; col < boardSize; col++) {
        tiles.push({
          isEmpty: true,
          value: 0,
          status: "normal",
          row,
          col,
        });
      }
    }
    return tiles;
  };

  it("should return false when 6x6 board is empty", () => {
    const tiles = createEmptyBoard(6);
    expect(hasValidClearColumns(tiles)).toBe(false);
  });

  it("should return true when 8x8 board has clearable tiles", () => {
    const tiles = createEmptyBoard(8);
    tiles[0] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 0 };
    expect(hasValidClearColumns(tiles)).toBe(true);
  });
});

describe("isValidClearColumn - variable board sizes", () => {
  const createEmptyBoard = (boardSize: number): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < boardSize; row++) {
      for (let col = 0; col < boardSize; col++) {
        tiles.push({
          isEmpty: true,
          value: 0,
          status: "normal",
          row,
          col,
        });
      }
    }
    return tiles;
  };

  it("should work correctly on 6x6 board", () => {
    const tiles = createEmptyBoard(6);
    tiles[5] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 5 };
    expect(isValidClearColumn(tiles, 5)).toBe(true);
    expect(isValidClearColumn(tiles, 0)).toBe(false);
  });

  it("should work correctly on 8x8 board", () => {
    const tiles = createEmptyBoard(8);
    tiles[7] = { isEmpty: false, value: 2, status: "normal", row: 0, col: 7 };
    expect(isValidClearColumn(tiles, 7)).toBe(true);
    expect(isValidClearColumn(tiles, 0)).toBe(false);
  });
});
