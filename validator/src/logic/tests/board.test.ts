import { describe, expect, it } from "vitest";
import type { SynchronizedTileState } from "../src/types";
import {
  getTile,
  indexToRowCol,
  isValidPosition,
  rowColToIndex,
  setTile,
} from "../src/board";

describe("Board Utilities", () => {
  describe("indexToRowCol", () => {
    it("should convert index 0 to row 0, col 0", () => {
      expect(indexToRowCol(0, 4)).toEqual({ row: 0, col: 0 });
    });

    it("should convert index 5 to row 1, col 1", () => {
      expect(indexToRowCol(5, 4)).toEqual({ row: 1, col: 1 });
    });

    it("should convert index 15 to row 3, col 3 (last position)", () => {
      expect(indexToRowCol(15, 4)).toEqual({ row: 3, col: 3 });
    });

    it("should convert index 3 to row 0, col 3", () => {
      expect(indexToRowCol(3, 4)).toEqual({ row: 0, col: 3 });
    });

    it("should convert index 12 to row 3, col 0", () => {
      expect(indexToRowCol(12, 4)).toEqual({ row: 3, col: 0 });
    });

    it("should convert index 7 to row 1, col 3", () => {
      expect(indexToRowCol(7, 4)).toEqual({ row: 1, col: 3 });
    });
  });

  describe("rowColToIndex", () => {
    it("should convert row 0, col 0 to index 0", () => {
      expect(rowColToIndex(0, 0, 4)).toBe(0);
    });

    it("should convert row 1, col 1 to index 5", () => {
      expect(rowColToIndex(1, 1, 4)).toBe(5);
    });

    it("should convert row 3, col 3 to index 15", () => {
      expect(rowColToIndex(3, 3, 4)).toBe(15);
    });

    it("should convert row 0, col 3 to index 3", () => {
      expect(rowColToIndex(0, 3, 4)).toBe(3);
    });

    it("should convert row 3, col 0 to index 12", () => {
      expect(rowColToIndex(3, 0, 4)).toBe(12);
    });

    it("should convert row 2, col 1 to index 9", () => {
      expect(rowColToIndex(2, 1, 4)).toBe(9);
    });
  });

  describe("isValidPosition", () => {
    it("should return true for valid position (0, 0)", () => {
      expect(isValidPosition(0, 0, 4)).toBe(true);
    });

    it("should return true for valid position (3, 3)", () => {
      expect(isValidPosition(3, 3, 4)).toBe(true);
    });

    it("should return true for valid position (1, 2)", () => {
      expect(isValidPosition(1, 2, 4)).toBe(true);
    });

    it("should return false for negative row", () => {
      expect(isValidPosition(-1, 0, 4)).toBe(false);
    });

    it("should return false for negative col", () => {
      expect(isValidPosition(0, -1, 4)).toBe(false);
    });

    it("should return false for row >= DEFAULT_BOARD_SIZE", () => {
      expect(isValidPosition(4, 0, 4)).toBe(false);
    });

    it("should return false for col >= DEFAULT_BOARD_SIZE", () => {
      expect(isValidPosition(0, 4, 4)).toBe(false);
    });

    it("should return false for both out of bounds", () => {
      expect(isValidPosition(5, 5, 4)).toBe(false);
    });
  });

  describe("getTile", () => {
    const createMockTile = (
      row: number,
      col: number,
      value: number,
    ): SynchronizedTileState => ({
      isEmpty: value === 0,
      value,
      status: "normal",
      row,
      col,
    });

    const createMockBoard = (): SynchronizedTileState[] => {
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < 4; row++) {
        for (let col = 0; col < 4; col++) {
          tiles.push(createMockTile(row, col, row * 4 + col));
        }
      }
      return tiles;
    };

    it("should return tile at valid position (0, 0)", () => {
      const tiles = createMockBoard();
      const tile = getTile(tiles, 0, 0, 4);

      expect(tile.row).toBe(0);
      expect(tile.col).toBe(0);
      expect(tile.value).toBe(0);
    });

    it("should return tile at valid position (1, 2)", () => {
      const tiles = createMockBoard();
      const tile = getTile(tiles, 1, 2, 4);

      expect(tile.row).toBe(1);
      expect(tile.col).toBe(2);
      expect(tile.value).toBe(6);
    });

    it("should return tile at valid position (3, 3)", () => {
      const tiles = createMockBoard();
      const tile = getTile(tiles, 3, 3, 4);

      expect(tile.row).toBe(3);
      expect(tile.col).toBe(3);
      expect(tile.value).toBe(15);
    });

    it("should throw error for invalid negative row", () => {
      const tiles = createMockBoard();
      expect(() => getTile(tiles, -1, 0, 4)).toThrow("Invalid row or column");
    });

    it("should throw error for invalid negative col", () => {
      const tiles = createMockBoard();
      expect(() => getTile(tiles, 0, -1, 4)).toThrow("Invalid row or column");
    });

    it("should throw error for row >= DEFAULT_BOARD_SIZE", () => {
      const tiles = createMockBoard();
      expect(() => getTile(tiles, 4, 0, 4)).toThrow("Invalid row or column");
    });

    it("should throw error for col >= DEFAULT_BOARD_SIZE", () => {
      const tiles = createMockBoard();
      expect(() => getTile(tiles, 0, 4, 4)).toThrow("Invalid row or column");
    });
  });

  describe("setTile", () => {
    const createMockTile = (
      row: number,
      col: number,
      value: number,
    ): SynchronizedTileState => ({
      isEmpty: value === 0,
      value,
      status: "normal",
      row,
      col,
    });

    const createEmptyBoard = (): SynchronizedTileState[] => {
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < 4; row++) {
        for (let col = 0; col < 4; col++) {
          tiles.push(createMockTile(row, col, 0));
        }
      }
      return tiles;
    };

    it("should set tile at position (0, 0)", () => {
      const tiles = createEmptyBoard();
      const newTile = createMockTile(0, 0, 64);

      setTile(tiles, newTile, 4);

      expect(tiles[0].value).toBe(64);
      expect(tiles[0].row).toBe(0);
      expect(tiles[0].col).toBe(0);
    });

    it("should set tile at position (1, 2)", () => {
      const tiles = createEmptyBoard();
      const newTile = createMockTile(1, 2, 128);

      setTile(tiles, newTile, 4);

      expect(tiles[6].value).toBe(128);
      expect(tiles[6].row).toBe(1);
      expect(tiles[6].col).toBe(2);
    });

    it("should set tile at position (3, 3)", () => {
      const tiles = createEmptyBoard();
      const newTile = createMockTile(3, 3, 256);

      setTile(tiles, newTile, 4);

      expect(tiles[15].value).toBe(256);
      expect(tiles[15].row).toBe(3);
      expect(tiles[15].col).toBe(3);
    });

    it("should overwrite existing tile", () => {
      const tiles = createEmptyBoard();
      tiles[5].value = 32;

      const newTile = createMockTile(1, 1, 64);
      setTile(tiles, newTile, 4);

      expect(tiles[5].value).toBe(64);
    });
  });
});
