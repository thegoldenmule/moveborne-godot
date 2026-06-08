import { describe, expect, it } from "vitest";
import type { SynchronizedTileState } from "../src/types";
import { createEmptyTile } from "../src/factories";
import { performPowerCardVortex } from "../src/powerCards";

describe("performPowerCardVortex", () => {
  const createBoard = (): SynchronizedTileState[] => {
    const board: SynchronizedTileState[] = [];
    for (let row = 0; row < 4; row++) {
      for (let col = 0; col < 4; col++) {
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
  ): void => {
    const index = row * 4 + col;
    board[index] = {
      isEmpty: false,
      value,
      status: "normal",
      meta: {},
      row,
      col,
    };
  };

  it("should rotate a 2x2 quadrant clockwise", () => {
    const board = createBoard();
    const boardSize = 4;
    setTileValue(board, 0, 0, 2); // Top-left
    setTileValue(board, 0, 1, 4); // Top-right
    setTileValue(board, 1, 0, 8); // Bottom-left
    setTileValue(board, 1, 1, 16); // Bottom-right

    const result = performPowerCardVortex(board, { row: 0, col: 0 }, boardSize);

    expect(result.success).toBe(true);
    expect(result.score).toBe(0);

    // After clockwise rotation:
    // topLeft (2) -> topRight
    // topRight (4) -> bottomRight
    // bottomRight (16) -> bottomLeft
    // bottomLeft (8) -> topLeft
    expect(result.tiles[0 * 4 + 0].value).toBe(8); // Top-left
    expect(result.tiles[0 * 4 + 1].value).toBe(2); // Top-right
    expect(result.tiles[1 * 4 + 0].value).toBe(16); // Bottom-left
    expect(result.tiles[1 * 4 + 1].value).toBe(4); // Bottom-right
  });

  it("should handle empty tiles in the quadrant", () => {
    const board = createBoard();
    const boardSize = 4;
    setTileValue(board, 0, 0, 2); // Top-left
    // Top-right is empty
    setTileValue(board, 1, 0, 8); // Bottom-left
    // Bottom-right is empty

    const result = performPowerCardVortex(board, { row: 0, col: 0 }, boardSize);

    expect(result.success).toBe(true);

    // After rotation: 2 -> topRight, empty -> bottomRight, empty -> bottomLeft, 8 -> topLeft
    expect(result.tiles[0 * 4 + 0].value).toBe(8); // Top-left
    expect(result.tiles[0 * 4 + 1].value).toBe(2); // Top-right
    expect(result.tiles[1 * 4 + 0].isEmpty).toBe(true); // Bottom-left
    expect(result.tiles[1 * 4 + 1].isEmpty).toBe(true); // Bottom-right
  });

  it("should handle all empty tiles in the quadrant", () => {
    const board = createBoard();
    const boardSize = 4;

    const result = performPowerCardVortex(board, { row: 0, col: 0 }, boardSize);

    expect(result.success).toBe(true);

    // All tiles should remain empty
    expect(result.tiles[0 * 4 + 0].isEmpty).toBe(true);
    expect(result.tiles[0 * 4 + 1].isEmpty).toBe(true);
    expect(result.tiles[1 * 4 + 0].isEmpty).toBe(true);
    expect(result.tiles[1 * 4 + 1].isEmpty).toBe(true);
  });

  it("should mark rotated tiles with 'rotated' status", () => {
    const board = createBoard();
    const boardSize = 4;
    setTileValue(board, 1, 1, 2);
    setTileValue(board, 1, 2, 4);
    setTileValue(board, 2, 1, 8);
    setTileValue(board, 2, 2, 16);

    const result = performPowerCardVortex(board, { row: 1, col: 1 }, boardSize);

    expect(result.success).toBe(true);

    // All tiles in the quadrant should have 'rotated' status
    expect(result.tiles[1 * 4 + 1].status).toBe("rotated");
    expect(result.tiles[1 * 4 + 2].status).toBe("rotated");
    expect(result.tiles[2 * 4 + 1].status).toBe("rotated");
    expect(result.tiles[2 * 4 + 2].status).toBe("rotated");
  });

  it("should not rotate quadrants at invalid positions (out of bounds)", () => {
    const board = createBoard();
    const boardSize = 4;
    setTileValue(board, 3, 3, 2); // Bottom-right corner

    // Try to rotate at position (3, 3) - this would be out of bounds
    const result = performPowerCardVortex(board, { row: 3, col: 3 }, boardSize);

    expect(result.success).toBe(false);
    expect(result.score).toBe(0);

    // Board should remain unchanged
    expect(result.tiles[3 * 4 + 3].value).toBe(2);
  });

  it("should not rotate at negative positions", () => {
    const board = createBoard();
    const boardSize = 4;

    const result = performPowerCardVortex(
      board,
      {
        row: -1,
        col: 0,
      },
      boardSize,
    );

    expect(result.success).toBe(false);
    expect(result.score).toBe(0);
  });

  it("should work for bottom-right quadrant (row 2, col 2)", () => {
    const board = createBoard();
    const boardSize = 4;
    setTileValue(board, 2, 2, 2);
    setTileValue(board, 2, 3, 4);
    setTileValue(board, 3, 2, 8);
    setTileValue(board, 3, 3, 16);

    const result = performPowerCardVortex(board, { row: 2, col: 2 }, boardSize);

    expect(result.success).toBe(true);

    // After rotation
    expect(result.tiles[2 * 4 + 2].value).toBe(8); // Top-left
    expect(result.tiles[2 * 4 + 3].value).toBe(2); // Top-right
    expect(result.tiles[3 * 4 + 2].value).toBe(16); // Bottom-left
    expect(result.tiles[3 * 4 + 3].value).toBe(4); // Bottom-right
  });

  it("should work for bottom-left quadrant (row 2, col 0)", () => {
    const board = createBoard();
    const boardSize = 4;
    setTileValue(board, 2, 0, 2);
    setTileValue(board, 2, 1, 4);
    setTileValue(board, 3, 0, 8);
    setTileValue(board, 3, 1, 16);

    const result = performPowerCardVortex(board, { row: 2, col: 0 }, boardSize);

    expect(result.success).toBe(true);

    // After rotation
    expect(result.tiles[2 * 4 + 0].value).toBe(8); // Top-left
    expect(result.tiles[2 * 4 + 1].value).toBe(2); // Top-right
    expect(result.tiles[3 * 4 + 0].value).toBe(16); // Bottom-left
    expect(result.tiles[3 * 4 + 1].value).toBe(4); // Bottom-right
  });

  it("should not modify tiles outside the quadrant", () => {
    const board = createBoard();
    const boardSize = 4;
    // Set up a full board
    for (let row = 0; row < 4; row++) {
      for (let col = 0; col < 4; col++) {
        setTileValue(board, row, col, (row * 4 + col + 1) * 2);
      }
    }

    // Rotate middle quadrant
    const result = performPowerCardVortex(board, { row: 1, col: 1 }, boardSize);

    expect(result.success).toBe(true);

    // Check that tiles outside the quadrant are unchanged
    expect(result.tiles[0 * 4 + 0].value).toBe(2); // (0,0)
    expect(result.tiles[0 * 4 + 3].value).toBe(8); // (0,3)
    expect(result.tiles[3 * 4 + 0].value).toBe(26); // (3,0)
    expect(result.tiles[3 * 4 + 3].value).toBe(32); // (3,3)
  });

  it("should preserve tile metadata during rotation", () => {
    const board = createBoard();
    const boardSize = 4;
    board[0 * 4 + 0] = {
      isEmpty: false,
      value: 2,
      status: "normal",
      meta: { special: "test" },
      row: 0,
      col: 0,
    };

    const result = performPowerCardVortex(board, { row: 0, col: 0 }, boardSize);

    expect(result.success).toBe(true);

    // The tile at (0,0) should now be at (0,1) with metadata preserved
    const rotatedTile = result.tiles[0 * 4 + 1];
    expect(rotatedTile.value).toBe(2);
    expect(rotatedTile.meta).toEqual({ special: "test" });
  });
});

describe("performPowerCardVortex - variable board sizes", () => {
  const createBoardWithSize = (size: number): SynchronizedTileState[] => {
    const board: SynchronizedTileState[] = [];
    for (let row = 0; row < size; row++) {
      for (let col = 0; col < size; col++) {
        board.push(createEmptyTile(row, col));
      }
    }
    return board;
  };

  const setTileValueOnBoard = (
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

  it("should work on 6x6 board - top-left quadrant", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValueOnBoard(board, 0, 0, 2, boardSize);
    setTileValueOnBoard(board, 0, 1, 4, boardSize);
    setTileValueOnBoard(board, 1, 0, 8, boardSize);
    setTileValueOnBoard(board, 1, 1, 16, boardSize);

    const result = performPowerCardVortex(board, { row: 0, col: 0 }, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * boardSize + 0].value).toBe(8);
    expect(result.tiles[0 * boardSize + 1].value).toBe(2);
    expect(result.tiles[1 * boardSize + 0].value).toBe(16);
    expect(result.tiles[1 * boardSize + 1].value).toBe(4);
  });

  it("should work on 6x6 board - middle quadrant", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);
    setTileValueOnBoard(board, 2, 2, 2, boardSize);
    setTileValueOnBoard(board, 2, 3, 4, boardSize);
    setTileValueOnBoard(board, 3, 2, 8, boardSize);
    setTileValueOnBoard(board, 3, 3, 16, boardSize);

    const result = performPowerCardVortex(board, { row: 2, col: 2 }, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[2 * boardSize + 2].value).toBe(8);
    expect(result.tiles[2 * boardSize + 3].value).toBe(2);
    expect(result.tiles[3 * boardSize + 2].value).toBe(16);
    expect(result.tiles[3 * boardSize + 3].value).toBe(4);
  });

  it("should work on 8x8 board - top-left quadrant", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    setTileValueOnBoard(board, 0, 0, 2, boardSize);
    setTileValueOnBoard(board, 0, 1, 4, boardSize);
    setTileValueOnBoard(board, 1, 0, 8, boardSize);
    setTileValueOnBoard(board, 1, 1, 16, boardSize);

    const result = performPowerCardVortex(board, { row: 0, col: 0 }, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[0 * boardSize + 0].value).toBe(8);
    expect(result.tiles[0 * boardSize + 1].value).toBe(2);
    expect(result.tiles[1 * boardSize + 0].value).toBe(16);
    expect(result.tiles[1 * boardSize + 1].value).toBe(4);
  });

  it("should work on 8x8 board - bottom-right quadrant", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    setTileValueOnBoard(board, 6, 6, 2, boardSize);
    setTileValueOnBoard(board, 6, 7, 4, boardSize);
    setTileValueOnBoard(board, 7, 6, 8, boardSize);
    setTileValueOnBoard(board, 7, 7, 16, boardSize);

    const result = performPowerCardVortex(board, { row: 6, col: 6 }, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[6 * boardSize + 6].value).toBe(8);
    expect(result.tiles[6 * boardSize + 7].value).toBe(2);
    expect(result.tiles[7 * boardSize + 6].value).toBe(16);
    expect(result.tiles[7 * boardSize + 7].value).toBe(4);
  });

  it("should reject invalid quadrant on 8x8 board (out of bounds)", () => {
    const boardSize = 8;
    const board = createBoardWithSize(boardSize);
    setTileValueOnBoard(board, 7, 7, 2, boardSize);

    const result = performPowerCardVortex(board, { row: 7, col: 7 }, boardSize);

    expect(result.success).toBe(false);
    expect(result.tiles[7 * boardSize + 7].value).toBe(2);
  });

  it("should work on 5x5 board (odd size)", () => {
    const boardSize = 5;
    const board = createBoardWithSize(boardSize);
    setTileValueOnBoard(board, 1, 1, 2, boardSize);
    setTileValueOnBoard(board, 1, 2, 4, boardSize);
    setTileValueOnBoard(board, 2, 1, 8, boardSize);
    setTileValueOnBoard(board, 2, 2, 16, boardSize);

    const result = performPowerCardVortex(board, { row: 1, col: 1 }, boardSize);

    expect(result.success).toBe(true);
    expect(result.tiles[1 * boardSize + 1].value).toBe(8);
    expect(result.tiles[1 * boardSize + 2].value).toBe(2);
    expect(result.tiles[2 * boardSize + 1].value).toBe(16);
    expect(result.tiles[2 * boardSize + 2].value).toBe(4);
  });
});
