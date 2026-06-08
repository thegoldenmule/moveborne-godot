import { describe, expect, it } from "vitest";
import type { SynchronizedTileState } from "../src/types";
import { createEmptyTile } from "../src/factories";
import {
  performPowerCardLightning,
  performPowerCardClear,
  performPowerCardShuffle,
} from "../src/powerCards";
import type { IRandomGenerator } from "../src/random";
import { RNG_NAMESPACES } from "../src/constants";

describe("performPowerCardLightning - variable board sizes", () => {
  const createBoardWithSize = (size: number): SynchronizedTileState[] => {
    const board: SynchronizedTileState[] = [];
    for (let row = 0; row < size; row++) {
      for (let col = 0; col < size; col++) {
        board.push(createEmptyTile(row, col));
      }
    }
    return board;
  };

  const setTileValue = (
    board: SynchronizedTileState[],
    row: number,
    col: number,
    value: number,
    boardSize: number,
  ): void => {
    const index = row * boardSize + col;
    board[index] = {
      isEmpty: false,
      value,
      status: "normal",
      meta: {},
      row,
      col,
    };
  };

  it("should work on 4x4 board - column 0", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);
    setTileValue(board, 1, 0, 4, boardSize);
    setTileValue(board, 2, 0, 8, boardSize);
    setTileValue(board, 3, 0, 16, boardSize);

    const result = performPowerCardLightning(board, 0, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * 4 + 0].value).toBe(4);
    expect(result.tiles[1 * 4 + 0].value).toBe(8);
    expect(result.tiles[2 * 4 + 0].value).toBe(16);
    expect(result.tiles[3 * 4 + 0].value).toBe(32);
    expect(result.score).toBe(4 + 8 + 16 + 32);
  });

  it("should work on 6x6 board - column 3", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 3, 2, boardSize);
    setTileValue(board, 2, 3, 4, boardSize);
    setTileValue(board, 4, 3, 8, boardSize);

    const result = performPowerCardLightning(board, 3, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * 6 + 3].value).toBe(4);
    expect(result.tiles[1 * 6 + 3].isEmpty).toBe(true);
    expect(result.tiles[2 * 6 + 3].value).toBe(8);
    expect(result.tiles[3 * 6 + 3].isEmpty).toBe(true);
    expect(result.tiles[4 * 6 + 3].value).toBe(16);
    expect(result.tiles[5 * 6 + 3].isEmpty).toBe(true);
    expect(result.score).toBe(4 + 8 + 16);
  });

  it("should work on 8x8 board - column 7 (last column)", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    for (let row = 0; row < boardSize; row++) {
      setTileValue(board, row, 7, 2, boardSize);
    }

    const result = performPowerCardLightning(board, 7, boardSize);

    expect(result.success).toBe(true);
    for (let row = 0; row < boardSize; row++) {
      expect(result.tiles[row * boardSize + 7].value).toBe(4);
    }
    expect(result.score).toBe(4 * 8);
  });

  it("should reject invalid column on 8x8 board", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);

    const result = performPowerCardLightning(board, 8, boardSize);

    expect(result.success).toBe(false);
    expect(result.error).toBe("Invalid column");
  });

  it("should reject invalid column on 6x6 board", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);

    const result = performPowerCardLightning(board, 6, boardSize);

    expect(result.success).toBe(false);
    expect(result.error).toBe("Invalid column");
  });

  it("should work on 5x5 board (odd size)", () => {
    const boardSize = 5;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 2, 2, boardSize);
    setTileValue(board, 2, 2, 4, boardSize);
    setTileValue(board, 4, 2, 8, boardSize);

    const result = performPowerCardLightning(board, 2, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * 5 + 2].value).toBe(4);
    expect(result.tiles[2 * 5 + 2].value).toBe(8);
    expect(result.tiles[4 * 5 + 2].value).toBe(16);
  });
});

describe("performPowerCardClear - variable board sizes", () => {
  const createBoardWithSize = (size: number): SynchronizedTileState[] => {
    const board: SynchronizedTileState[] = [];
    for (let row = 0; row < size; row++) {
      for (let col = 0; col < size; col++) {
        board.push(createEmptyTile(row, col));
      }
    }
    return board;
  };

  const setTileValue = (
    board: SynchronizedTileState[],
    row: number,
    col: number,
    value: number,
    boardSize: number,
  ): void => {
    const index = row * boardSize + col;
    board[index] = {
      isEmpty: false,
      value,
      status: "normal",
      meta: {},
      row,
      col,
    };
  };

  it("should work on 4x4 board - column 1", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 1, 2, boardSize);
    setTileValue(board, 1, 1, 4, boardSize);
    setTileValue(board, 2, 1, 8, boardSize);

    const result = performPowerCardClear(board, 1, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * 4 + 1].isEmpty).toBe(true);
    expect(result.tiles[1 * 4 + 1].isEmpty).toBe(true);
    expect(result.tiles[2 * 4 + 1].isEmpty).toBe(true);
    expect(result.tiles[3 * 4 + 1].isEmpty).toBe(true);
  });

  it("should work on 6x6 board - column 4", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    for (let row = 0; row < boardSize; row++) {
      setTileValue(board, row, 4, 2, boardSize);
    }

    const result = performPowerCardClear(board, 4, boardSize);

    expect(result.success).toBe(true);
    for (let row = 0; row < boardSize; row++) {
      expect(result.tiles[row * boardSize + 4].isEmpty).toBe(true);
    }
  });

  it("should work on 8x8 board - column 7 (last column)", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    for (let row = 0; row < boardSize; row++) {
      setTileValue(board, row, 7, 2, boardSize);
    }

    const result = performPowerCardClear(board, 7, boardSize);

    expect(result.success).toBe(true);
    for (let row = 0; row < boardSize; row++) {
      expect(result.tiles[row * boardSize + 7].isEmpty).toBe(true);
    }
  });

  it("should reject invalid column on 8x8 board", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);

    const result = performPowerCardClear(board, 8, boardSize);

    expect(result.success).toBe(false);
  });

  it("should reject invalid column on 6x6 board", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);

    const result = performPowerCardClear(board, 6, boardSize);

    expect(result.success).toBe(false);
  });

  it("should work on 5x5 board (odd size)", () => {
    const boardSize = 5;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 3, 2, boardSize);
    setTileValue(board, 2, 3, 4, boardSize);
    setTileValue(board, 4, 3, 8, boardSize);

    const result = performPowerCardClear(board, 3, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * 5 + 3].isEmpty).toBe(true);
    expect(result.tiles[2 * 5 + 3].isEmpty).toBe(true);
    expect(result.tiles[4 * 5 + 3].isEmpty).toBe(true);
  });

  it("should not clear tiles with effects", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 2, 2, boardSize);
    board[0 * boardSize + 2].effect = {
      type: "freeze",
      active: true,
      config: {} as never,
    };
    setTileValue(board, 1, 2, 4, boardSize);
    setTileValue(board, 2, 2, 8, boardSize);

    const result = performPowerCardClear(board, 2, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * 6 + 2].isEmpty).toBe(false);
    expect(result.tiles[1 * 6 + 2].isEmpty).toBe(true);
    expect(result.tiles[2 * 6 + 2].isEmpty).toBe(true);
  });
});

describe("performPowerCardShuffle - variable board sizes", () => {
  const createBoardWithSize = (size: number): SynchronizedTileState[] => {
    const board: SynchronizedTileState[] = [];
    for (let row = 0; row < size; row++) {
      for (let col = 0; col < size; col++) {
        board.push(createEmptyTile(row, col));
      }
    }
    return board;
  };

  const setTileValue = (
    board: SynchronizedTileState[],
    row: number,
    col: number,
    value: number,
    boardSize: number,
  ): void => {
    const index = row * boardSize + col;
    board[index] = {
      isEmpty: false,
      value,
      status: "normal",
      meta: {},
      row,
      col,
    };
  };

  const createMockRandomGenerator = (): IRandomGenerator => {
    let callCount = 0;
    return {
      getRandom: (namespace: string) => {
        if (namespace === RNG_NAMESPACES.SHUFFLE) {
          callCount++;
          return (callCount * 0.123456) % 1;
        }
        return 0.5;
      },
      getIndices: () => ({}) as never,
      getSeeds: () => ({}) as never,
      getState: () => "" as never,
      getAllStates: () => ({}) as never,
      clone: () => createMockRandomGenerator(),
    };
  };

  it("should work on 4x4 board (16 tiles)", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);
    setTileValue(board, 1, 1, 4, boardSize);
    setTileValue(board, 2, 2, 8, boardSize);
    setTileValue(board, 3, 3, 16, boardSize);

    const mockRng = createMockRandomGenerator();
    const result = performPowerCardShuffle(board, mockRng, boardSize);

    expect(result.success).toBe(true);

    let nonEmptyCount = 0;
    for (const tile of result.tiles) {
      if (!tile.isEmpty) {
        nonEmptyCount++;
      }
    }
    expect(nonEmptyCount).toBe(4);
  });

  it("should work on 6x6 board (36 tiles)", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    for (let i = 0; i < 10; i++) {
      const row = Math.floor(i / boardSize);
      const col = i % boardSize;
      setTileValue(board, row, col, 2 * (i + 1), boardSize);
    }

    const mockRng = createMockRandomGenerator();
    const result = performPowerCardShuffle(board, mockRng, boardSize);

    expect(result.success).toBe(true);

    let nonEmptyCount = 0;
    for (const tile of result.tiles) {
      if (!tile.isEmpty) {
        nonEmptyCount++;
      }
    }
    expect(nonEmptyCount).toBe(10);
  });

  it("should work on 8x8 board (64 tiles)", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    for (let i = 0; i < 20; i++) {
      const row = Math.floor(i / boardSize);
      const col = i % boardSize;
      setTileValue(board, row, col, 2 * (i + 1), boardSize);
    }

    const mockRng = createMockRandomGenerator();
    const result = performPowerCardShuffle(board, mockRng, boardSize);

    expect(result.success).toBe(true);

    let nonEmptyCount = 0;
    for (const tile of result.tiles) {
      if (!tile.isEmpty) {
        nonEmptyCount++;
      }
    }
    expect(nonEmptyCount).toBe(20);
  });

  it("should work on 5x5 board (25 tiles, odd size)", () => {
    const boardSize = 5;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);
    setTileValue(board, 1, 1, 4, boardSize);
    setTileValue(board, 2, 2, 8, boardSize);
    setTileValue(board, 3, 3, 16, boardSize);
    setTileValue(board, 4, 4, 32, boardSize);

    const mockRng = createMockRandomGenerator();
    const result = performPowerCardShuffle(board, mockRng, boardSize);

    expect(result.success).toBe(true);

    let nonEmptyCount = 0;
    for (const tile of result.tiles) {
      if (!tile.isEmpty) {
        nonEmptyCount++;
      }
    }
    expect(nonEmptyCount).toBe(5);
  });

  it("should preserve tile effects during shuffle", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValue(board, 0, 0, 2, boardSize);
    board[0].effect = {
      type: "freeze",
      active: true,
      config: {} as never,
    };
    setTileValue(board, 1, 1, 4, boardSize);

    const mockRng = createMockRandomGenerator();
    const result = performPowerCardShuffle(board, mockRng, boardSize);

    expect(result.success).toBe(true);

    let foundFreezeEffect = false;
    for (const tile of result.tiles) {
      if (!tile.isEmpty && tile.effect?.type === "freeze") {
        foundFreezeEffect = true;
        break;
      }
    }
    expect(foundFreezeEffect).toBe(true);
  });
});
