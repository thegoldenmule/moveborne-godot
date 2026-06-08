import { describe, expect, it } from "vitest";
import { DEFAULT_BOARD_SIZE } from "../src/constants";
import {
  createAmplifyEffect,
  createBlackHoleEffect,
  createFreezeEffect,
  createStoneEffect,
} from "../src/factories";
import { createGameState } from "./testHelpers";
import type { SynchronizedGameState, SynchronizedTileState } from "../src/types";
import {
  canValueMerge,
  canValueMove,
  canTilesMergeTogether,
  findBlackHoleInPath,
  getAdjacentTiles,
  getAmplifyMultiplier,
  isAmplifyTile,
  isBlackHoleTile,
  processAmplifyEffect,
  processBlackHoleDestruction,
  processFreezeRemovalFromAdjacentMerge,
  removeBlackHoleWithShards,
  tileHasEffect,
} from "../src/tileEffectLogic";

const createTestGameState = (
  tiles: SynchronizedTileState[],
  boardSize = DEFAULT_BOARD_SIZE,
): SynchronizedGameState => ({
  ...createGameState(),
  board: {
    tiles,
    size: boardSize,
  },
});

describe("Tile Effect Logic - FREEZE", () => {
  const createEmptyTile = (
    row: number,
    col: number,
  ): SynchronizedTileState => ({
    isEmpty: true,
    value: 0,
    status: "normal",
    row,
    col,
  });

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

  const createEmptyBoard = (): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < DEFAULT_BOARD_SIZE; row++) {
      for (let col = 0; col < DEFAULT_BOARD_SIZE; col++) {
        tiles.push(createEmptyTile(row, col));
      }
    }
    return tiles;
  };

  describe("tileHasEffect", () => {
    it("should return false for tile without effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      expect(tileHasEffect(tile, "freeze")).toBe(false);
    });

    it("should return true for tile with active freeze effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      expect(tileHasEffect(tile, "freeze")).toBe(true);
    });

    it("should return false for tile with inactive freeze effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      tile.effect.active = false;
      expect(tileHasEffect(tile, "freeze")).toBe(false);
    });

    it("should return false when checking for wrong effect type", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      expect(tileHasEffect(tile, "stone")).toBe(false);
    });
  });

  describe("canValueMerge", () => {
    it("should return true for tile without effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      expect(canValueMerge(tile)).toBe(true);
    });

    it("should return false for tile with freeze effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      expect(canValueMerge(tile)).toBe(false);
    });

    it("should return false for tile with stone effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createStoneEffect();
      expect(canValueMerge(tile)).toBe(false);
    });

    it("should return true for tile with inactive freeze effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      tile.effect.active = false;
      expect(canValueMerge(tile)).toBe(true);
    });
  });

  describe("canTilesMergeTogether", () => {
    it("should return true for two normal tiles with same value", () => {
      const tile1 = createTileWithValue(0, 0, 4);
      const tile2 = createTileWithValue(0, 1, 4);
      expect(canTilesMergeTogether(tile1, tile2)).toBe(true);
    });

    it("should return false for tiles with different values", () => {
      const tile1 = createTileWithValue(0, 0, 4);
      const tile2 = createTileWithValue(0, 1, 8);
      expect(canTilesMergeTogether(tile1, tile2)).toBe(false);
    });

    it("should return false when first tile is frozen", () => {
      const tile1 = createTileWithValue(0, 0, 4);
      tile1.effect = createFreezeEffect();
      const tile2 = createTileWithValue(0, 1, 4);
      expect(canTilesMergeTogether(tile1, tile2)).toBe(false);
    });

    it("should return false when second tile is frozen", () => {
      const tile1 = createTileWithValue(0, 0, 4);
      const tile2 = createTileWithValue(0, 1, 4);
      tile2.effect = createFreezeEffect();
      expect(canTilesMergeTogether(tile1, tile2)).toBe(false);
    });

    it("should return false when both tiles are frozen", () => {
      const tile1 = createTileWithValue(0, 0, 4);
      tile1.effect = createFreezeEffect();
      const tile2 = createTileWithValue(0, 1, 4);
      tile2.effect = createFreezeEffect();
      expect(canTilesMergeTogether(tile1, tile2)).toBe(false);
    });

    it("should return false when first tile is empty", () => {
      const tile1 = createEmptyTile(0, 0);
      const tile2 = createTileWithValue(0, 1, 4);
      expect(canTilesMergeTogether(tile1, tile2)).toBe(false);
    });

    it("should return false when second tile is empty", () => {
      const tile1 = createTileWithValue(0, 0, 4);
      const tile2 = createEmptyTile(0, 1);
      expect(canTilesMergeTogether(tile1, tile2)).toBe(false);
    });
  });

  describe("getAdjacentTiles", () => {
    it("should return 4 adjacent tiles for center position", () => {
      const tiles = createEmptyBoard();
      const gameState = createTestGameState(tiles);
      const adjacent = getAdjacentTiles(gameState, { row: 1, col: 1 });
      expect(adjacent.length).toBe(4);
    });

    it("should return 2 adjacent tiles for corner position", () => {
      const tiles = createEmptyBoard();
      const gameState = createTestGameState(tiles);
      const adjacent = getAdjacentTiles(gameState, { row: 0, col: 0 });
      expect(adjacent.length).toBe(2);
    });

    it("should return 3 adjacent tiles for edge position", () => {
      const tiles = createEmptyBoard();
      const gameState = createTestGameState(tiles);
      const adjacent = getAdjacentTiles(gameState, { row: 0, col: 1 });
      expect(adjacent.length).toBe(3);
    });

    it("should return correct tiles for center position", () => {
      const tiles = createEmptyBoard();
      tiles[5] = createTileWithValue(1, 1, 2); // Center
      tiles[1] = createTileWithValue(0, 1, 4); // Up
      tiles[9] = createTileWithValue(2, 1, 8); // Down
      tiles[4] = createTileWithValue(1, 0, 16); // Left
      tiles[6] = createTileWithValue(1, 2, 32); // Right

      const gameState = createTestGameState(tiles);
      const adjacent = getAdjacentTiles(gameState, { row: 1, col: 1 });

      expect(adjacent.length).toBe(4);
      expect(adjacent.some((t) => t.value === 4)).toBe(true); // Up
      expect(adjacent.some((t) => t.value === 8)).toBe(true); // Down
      expect(adjacent.some((t) => t.value === 16)).toBe(true); // Left
      expect(adjacent.some((t) => t.value === 32)).toBe(true); // Right
    });

    it("should work correctly on 5x5 board - center position", () => {
      const boardSize = 5;
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < boardSize; row++) {
        for (let col = 0; col < boardSize; col++) {
          tiles.push(createEmptyTile(row, col));
        }
      }

      tiles[12] = createTileWithValue(2, 2, 2); // Center (2,2)
      tiles[7] = createTileWithValue(1, 2, 4); // Up
      tiles[17] = createTileWithValue(3, 2, 8); // Down
      tiles[11] = createTileWithValue(2, 1, 16); // Left
      tiles[13] = createTileWithValue(2, 3, 32); // Right

      const gameState = createTestGameState(tiles, boardSize);
      const adjacent = getAdjacentTiles(gameState, { row: 2, col: 2 });

      expect(adjacent.length).toBe(4);
      expect(adjacent.some((t) => t.value === 4)).toBe(true);
      expect(adjacent.some((t) => t.value === 8)).toBe(true);
      expect(adjacent.some((t) => t.value === 16)).toBe(true);
      expect(adjacent.some((t) => t.value === 32)).toBe(true);
    });

    it("should work correctly on 8x8 board - center position", () => {
      const boardSize = 8;
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < boardSize; row++) {
        for (let col = 0; col < boardSize; col++) {
          tiles.push(createEmptyTile(row, col));
        }
      }

      tiles[36] = createTileWithValue(4, 4, 2); // Center (4,4)
      tiles[28] = createTileWithValue(3, 4, 4); // Up
      tiles[44] = createTileWithValue(5, 4, 8); // Down
      tiles[35] = createTileWithValue(4, 3, 16); // Left
      tiles[37] = createTileWithValue(4, 5, 32); // Right

      const gameState = createTestGameState(tiles, boardSize);
      const adjacent = getAdjacentTiles(gameState, { row: 4, col: 4 });

      expect(adjacent.length).toBe(4);
      expect(adjacent.some((t) => t.value === 4)).toBe(true);
      expect(adjacent.some((t) => t.value === 8)).toBe(true);
      expect(adjacent.some((t) => t.value === 16)).toBe(true);
      expect(adjacent.some((t) => t.value === 32)).toBe(true);
    });

    it("should work correctly on 8x8 board - corner position", () => {
      const boardSize = 8;
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < boardSize; row++) {
        for (let col = 0; col < boardSize; col++) {
          tiles.push(createEmptyTile(row, col));
        }
      }

      tiles[0] = createTileWithValue(0, 0, 2); // Top-left corner
      tiles[1] = createTileWithValue(0, 1, 4); // Right
      tiles[8] = createTileWithValue(1, 0, 8); // Down

      const gameState = createTestGameState(tiles, boardSize);
      const adjacent = getAdjacentTiles(gameState, { row: 0, col: 0 });

      expect(adjacent.length).toBe(2);
      expect(adjacent.some((t) => t.value === 4)).toBe(true);
      expect(adjacent.some((t) => t.value === 8)).toBe(true);
    });

    it("should work correctly on 6x6 board - edge position", () => {
      const boardSize = 6;
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < boardSize; row++) {
        for (let col = 0; col < boardSize; col++) {
          tiles.push(createEmptyTile(row, col));
        }
      }

      tiles[3] = createTileWithValue(0, 3, 2); // Top edge
      tiles[2] = createTileWithValue(0, 2, 4); // Left
      tiles[4] = createTileWithValue(0, 4, 8); // Right
      tiles[9] = createTileWithValue(1, 3, 16); // Down

      const gameState = createTestGameState(tiles, boardSize);
      const adjacent = getAdjacentTiles(gameState, { row: 0, col: 3 });

      expect(adjacent.length).toBe(3);
      expect(adjacent.some((t) => t.value === 4)).toBe(true);
      expect(adjacent.some((t) => t.value === 8)).toBe(true);
      expect(adjacent.some((t) => t.value === 16)).toBe(true);
    });
  });

  describe("processFreezeRemovalFromAdjacentMerge", () => {
    it("should remove freeze from all adjacent tiles", () => {
      const tiles = createEmptyBoard();
      tiles[5] = createTileWithValue(1, 1, 4); // Center (merge position)
      tiles[1] = createTileWithValue(0, 1, 2); // Up - frozen
      tiles[1].effect = createFreezeEffect();
      tiles[9] = createTileWithValue(2, 1, 2); // Down - frozen
      tiles[9].effect = createFreezeEffect();
      tiles[4] = createTileWithValue(1, 0, 2); // Left - frozen
      tiles[4].effect = createFreezeEffect();
      tiles[6] = createTileWithValue(1, 2, 2); // Right - frozen
      tiles[6].effect = createFreezeEffect();

      const gameState = createTestGameState(tiles);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 1,
        col: 1,
      });

      expect(removed.length).toBe(4);
      expect(tiles[1].effect?.active).toBe(false);
      expect(tiles[9].effect?.active).toBe(false);
      expect(tiles[4].effect?.active).toBe(false);
      expect(tiles[6].effect?.active).toBe(false);
    });

    it("should only remove freeze from frozen tiles, not normal tiles", () => {
      const tiles = createEmptyBoard();
      tiles[5] = createTileWithValue(1, 1, 4); // Center (merge position)
      tiles[1] = createTileWithValue(0, 1, 2); // Up - frozen
      tiles[1].effect = createFreezeEffect();
      tiles[9] = createTileWithValue(2, 1, 2); // Down - normal
      tiles[4] = createTileWithValue(1, 0, 2); // Left - normal
      tiles[6] = createTileWithValue(1, 2, 2); // Right - frozen
      tiles[6].effect = createFreezeEffect();

      const gameState = createTestGameState(tiles);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 1,
        col: 1,
      });

      expect(removed.length).toBe(2);
      expect(tiles[1].effect?.active).toBe(false);
      expect(tiles[6].effect?.active).toBe(false);
      expect(tiles[9].effect).toBeUndefined();
      expect(tiles[4].effect).toBeUndefined();
    });

    it("should remove stone effect from adjacent tiles", () => {
      const tiles = createEmptyBoard();
      tiles[5] = createTileWithValue(1, 1, 4); // Center (merge position)
      tiles[1] = createTileWithValue(0, 1, 2); // Up - stone
      tiles[1].effect = createStoneEffect();

      const gameState = createTestGameState(tiles);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 1,
        col: 1,
      });

      expect(removed.length).toBe(1);
      expect(tiles[1].effect?.active).toBe(false);
    });

    it("should return empty array when no adjacent tiles have freeze", () => {
      const tiles = createEmptyBoard();
      tiles[5] = createTileWithValue(1, 1, 4); // Center (merge position)
      tiles[1] = createTileWithValue(0, 1, 2); // Up - normal
      tiles[9] = createTileWithValue(2, 1, 2); // Down - normal

      const gameState = createTestGameState(tiles);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 1,
        col: 1,
      });

      expect(removed.length).toBe(0);
    });

    it("should handle corner position with frozen tiles", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 4); // Corner (merge position)
      tiles[1] = createTileWithValue(0, 1, 2); // Right - frozen
      tiles[1].effect = createFreezeEffect();
      tiles[4] = createTileWithValue(1, 0, 2); // Down - frozen
      tiles[4].effect = createFreezeEffect();

      const gameState = createTestGameState(tiles);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 0,
        col: 0,
      });

      expect(removed.length).toBe(2);
      expect(tiles[1].effect?.active).toBe(false);
      expect(tiles[4].effect?.active).toBe(false);
    });

    it("should remove freeze from tile below merge position (row 2, col 3 -> row 3, col 3)", () => {
      const tiles = createEmptyBoard();
      // Create merged tile at (2, 3) - index = 2 * 4 + 3 = 11
      tiles[11] = createTileWithValue(2, 3, 16);
      tiles[11].status = "merged";

      // Create frozen tile below at (3, 3) - index = 3 * 4 + 3 = 15
      tiles[15] = createTileWithValue(3, 3, 2);
      tiles[15].effect = createFreezeEffect();

      const gameState = createTestGameState(tiles);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 2,
        col: 3,
      });

      expect(removed.length).toBe(1);
      expect(removed[0]).toEqual({ row: 3, col: 3 });
      expect(tiles[15].effect?.active).toBe(false);
    });

    it("should work correctly on 8x8 board - remove effects from adjacent tiles", () => {
      const boardSize = 8;
      const tiles: SynchronizedTileState[] = [];
      for (let row = 0; row < boardSize; row++) {
        for (let col = 0; col < boardSize; col++) {
          tiles.push(createEmptyTile(row, col));
        }
      }

      // Merge at center (4, 4) - index = 4 * 8 + 4 = 36
      tiles[36] = createTileWithValue(4, 4, 16);
      // Freeze adjacent tiles
      tiles[28] = createTileWithValue(3, 4, 2); // Up
      tiles[28].effect = createFreezeEffect();
      tiles[44] = createTileWithValue(5, 4, 2); // Down
      tiles[44].effect = createFreezeEffect();
      tiles[35] = createTileWithValue(4, 3, 2); // Left
      tiles[35].effect = createFreezeEffect();
      tiles[37] = createTileWithValue(4, 5, 2); // Right
      tiles[37].effect = createFreezeEffect();

      const gameState = createTestGameState(tiles, boardSize);
      const removed = processFreezeRemovalFromAdjacentMerge(gameState, {
        row: 4,
        col: 4,
      });

      expect(removed.length).toBe(4);
      expect(tiles[28].effect?.active).toBe(false);
      expect(tiles[44].effect?.active).toBe(false);
      expect(tiles[35].effect?.active).toBe(false);
      expect(tiles[37].effect?.active).toBe(false);
    });
  });
});

describe("Tile Effect Logic - BLACK_HOLE", () => {
  const createEmptyTile = (
    row: number,
    col: number,
  ): SynchronizedTileState => ({
    isEmpty: true,
    value: 0,
    status: "normal",
    row,
    col,
  });

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

  const createEmptyBoard = (): SynchronizedTileState[] => {
    const tiles: SynchronizedTileState[] = [];
    for (let row = 0; row < DEFAULT_BOARD_SIZE; row++) {
      for (let col = 0; col < DEFAULT_BOARD_SIZE; col++) {
        tiles.push(createEmptyTile(row, col));
      }
    }
    return tiles;
  };

  describe("isBlackHoleTile", () => {
    it("should return false for tile without effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      expect(isBlackHoleTile(tile)).toBe(false);
    });

    it("should return true for tile with active black hole effect", () => {
      const tile = createEmptyTile(0, 0);
      tile.effect = createBlackHoleEffect();
      expect(isBlackHoleTile(tile)).toBe(true);
    });

    it("should return false for tile with inactive black hole effect", () => {
      const tile = createEmptyTile(0, 0);
      tile.effect = createBlackHoleEffect();
      tile.effect.active = false;
      expect(isBlackHoleTile(tile)).toBe(false);
    });

    it("should return false for tile with different effect", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      expect(isBlackHoleTile(tile)).toBe(false);
    });
  });

  describe("canValueMove", () => {
    it("should return true for normal tile", () => {
      const tile = createTileWithValue(0, 0, 2);
      expect(canValueMove(tile)).toBe(true);
    });

    it("should return false for empty tile", () => {
      const tile = createEmptyTile(0, 0);
      expect(canValueMove(tile)).toBe(false);
    });

    it("should return false for black hole tile", () => {
      const tile = createEmptyTile(0, 0);
      tile.effect = createBlackHoleEffect();
      expect(canValueMove(tile)).toBe(false);
    });

    it("should return false for stone tile", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createStoneEffect();
      expect(canValueMove(tile)).toBe(false);
    });

    it("should return true for frozen tile (freeze doesn't prevent movement)", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createFreezeEffect();
      expect(canValueMove(tile)).toBe(true);
    });
  });

  describe("findBlackHoleInPath", () => {
    it("should return null when no black hole in path", () => {
      const tiles = createEmptyBoard();
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 0 },
        { row: 0, col: 3 },
      );
      expect(result).toBeNull();
    });

    it("should find black hole in horizontal path (left to right)", () => {
      const tiles = createEmptyBoard();
      tiles[2].effect = createBlackHoleEffect(); // row 0, col 2
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 0 },
        { row: 0, col: 3 },
      );
      expect(result).toEqual({ row: 0, col: 2 });
    });

    it("should find black hole in horizontal path (right to left)", () => {
      const tiles = createEmptyBoard();
      tiles[1].effect = createBlackHoleEffect(); // row 0, col 1
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 3 },
        { row: 0, col: 0 },
      );
      expect(result).toEqual({ row: 0, col: 1 });
    });

    it("should find black hole in vertical path (top to bottom)", () => {
      const tiles = createEmptyBoard();
      tiles[5].effect = createBlackHoleEffect(); // row 1, col 1
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 1 },
        { row: 3, col: 1 },
      );
      expect(result).toEqual({ row: 1, col: 1 });
    });

    it("should find black hole in vertical path (bottom to top)", () => {
      const tiles = createEmptyBoard();
      tiles[9].effect = createBlackHoleEffect(); // row 2, col 1
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 3, col: 1 },
        { row: 0, col: 1 },
      );
      expect(result).toEqual({ row: 2, col: 1 });
    });

    it("should not check start position for black hole", () => {
      const tiles = createEmptyBoard();
      tiles[0].effect = createBlackHoleEffect(); // row 0, col 0 (start)
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 0 },
        { row: 0, col: 3 },
      );
      expect(result).toBeNull();
    });

    it("should not check end position for black hole", () => {
      const tiles = createEmptyBoard();
      tiles[3].effect = createBlackHoleEffect(); // row 0, col 3 (end)
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 0 },
        { row: 0, col: 3 },
      );
      expect(result).toBeNull();
    });

    it("should find first black hole in path with multiple black holes", () => {
      const tiles = createEmptyBoard();
      tiles[1].effect = createBlackHoleEffect(); // row 0, col 1
      tiles[2].effect = createBlackHoleEffect(); // row 0, col 2
      const result = findBlackHoleInPath(
        tiles,
        DEFAULT_BOARD_SIZE,
        { row: 0, col: 0 },
        { row: 0, col: 3 },
      );
      expect(result).toEqual({ row: 0, col: 1 }); // First one encountered
    });
  });

  describe("processBlackHoleDestruction", () => {
    it("should return score loss equal to tile value and increment counter", () => {
      const tile = createTileWithValue(0, 0, 32);
      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      const result = processBlackHoleDestruction(tile, blackHole);
      expect(result.scoreLoss).toBe(32);
      expect(blackHole.effect?.config?.tilesConsumed).toBe(1);
    });

    it("should make tile empty", () => {
      const tile = createTileWithValue(0, 0, 16);
      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      processBlackHoleDestruction(tile, blackHole);
      expect(tile.isEmpty).toBe(true);
      expect(tile.value).toBe(0);
    });

    it("should set tile status to normal", () => {
      const tile = createTileWithValue(0, 0, 8);
      tile.status = "merged";
      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      processBlackHoleDestruction(tile, blackHole);
      expect(tile.status).toBe("normal");
    });

    it("should handle tile with value 2", () => {
      const tile = createTileWithValue(0, 0, 2);
      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      const result = processBlackHoleDestruction(tile, blackHole);
      expect(result.scoreLoss).toBe(2);
      expect(tile.isEmpty).toBe(true);
      expect(tile.value).toBe(0);
    });

    it("should clear tile effects when destroyed", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createFreezeEffect();
      expect(tile.effect).toBeDefined();

      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      processBlackHoleDestruction(tile, blackHole);

      expect(tile.effect).toBeUndefined();
      expect(tile.isEmpty).toBe(true);
      expect(tile.value).toBe(0);
    });

    it("should clear freeze effect from destroyed tile", () => {
      const tile = createTileWithValue(0, 0, 8);
      tile.effect = createFreezeEffect();

      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      processBlackHoleDestruction(tile, blackHole);

      expect(tile.effect).toBeUndefined();
    });

    it("should work correctly even if tile has no effect", () => {
      const tile = createTileWithValue(0, 0, 16);
      expect(tile.effect).toBeUndefined();

      const blackHole = createTileWithValue(1, 1, 0);
      blackHole.isEmpty = true;
      blackHole.effect = createBlackHoleEffect();

      const result = processBlackHoleDestruction(tile, blackHole);

      expect(result.scoreLoss).toBe(16);
      expect(tile.effect).toBeUndefined();
      expect(tile.isEmpty).toBe(true);
    });
  });

  describe("removeBlackHoleWithShards", () => {
    it("should remove black hole when player has enough shards", () => {
      const tiles = createEmptyBoard();
      tiles[0].effect = createBlackHoleEffect();
      const gameState = createTestGameState(tiles);
      gameState.shards = 10;

      const result = removeBlackHoleWithShards(gameState, { row: 0, col: 0 });

      expect(result).not.toBeNull();
      expect(result!.shards).toBe(3); // 10 - 7
      expect(tiles[0].effect?.active).toBe(false);
    });

    it("should return null when player doesn't have enough shards", () => {
      const tiles = createEmptyBoard();
      tiles[0].effect = createBlackHoleEffect();
      const gameState = createTestGameState(tiles);
      gameState.shards = 5;

      const result = removeBlackHoleWithShards(gameState, { row: 0, col: 0 });

      expect(result).toBeNull();
      expect(tiles[0].effect?.active).toBe(true); // Still active
    });

    it("should return null when tile is not a black hole", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 4);
      const gameState = createTestGameState(tiles);
      gameState.shards = 10;

      const result = removeBlackHoleWithShards(gameState, { row: 0, col: 0 });

      expect(result).toBeNull();
    });

    it("should handle exact shard count", () => {
      const tiles = createEmptyBoard();
      tiles[0].effect = createBlackHoleEffect();
      const gameState = createTestGameState(tiles);
      gameState.shards = 7;

      const result = removeBlackHoleWithShards(gameState, { row: 0, col: 0 });

      expect(result).not.toBeNull();
      expect(result!.shards).toBe(0);
      expect(tiles[0].effect?.active).toBe(false);
    });

    it("should use removalCost from effect config if present", () => {
      const tiles = createEmptyBoard();
      const blackHole = createBlackHoleEffect();
      blackHole.config.removalCost = 5;
      tiles[0].effect = blackHole;
      const gameState = createTestGameState(tiles);
      gameState.shards = 6;

      const result = removeBlackHoleWithShards(gameState, { row: 0, col: 0 });

      expect(result).not.toBeNull();
      expect(result!.shards).toBe(1); // 6 - 5
      expect(tiles[0].effect?.active).toBe(false);
    });
  });

  describe("isAmplifyTile", () => {
    it("should return true for tile with active amplify effect", () => {
      const tile = createTileWithValue(0, 0, 8);
      tile.effect = createAmplifyEffect();
      expect(isAmplifyTile(tile)).toBe(true);
    });

    it("should return false for empty tile", () => {
      const tile = createEmptyTile(0, 0);
      expect(isAmplifyTile(tile)).toBe(false);
    });

    it("should return false for tile with no effect", () => {
      const tile = createTileWithValue(0, 0, 4);
      expect(isAmplifyTile(tile)).toBe(false);
    });

    it("should return false for tile with inactive amplify effect", () => {
      const tile = createTileWithValue(0, 0, 8);
      tile.effect = createAmplifyEffect();
      tile.effect.active = false;
      expect(isAmplifyTile(tile)).toBe(false);
    });

    it("should return false for tile with different effect type", () => {
      const tile = createTileWithValue(0, 0, 8);
      tile.effect = createFreezeEffect();
      expect(isAmplifyTile(tile)).toBe(false);
    });

    it("should return false for undefined tile", () => {
      expect(isAmplifyTile(undefined)).toBe(false);
    });
  });

  describe("getAmplifyMultiplier", () => {
    it("should return default multiplier of 2", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();
      expect(getAmplifyMultiplier(tile)).toBe(2);
    });

    it("should return custom multiplier from config", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();
      tile.effect.config.multiplier = 3;
      expect(getAmplifyMultiplier(tile)).toBe(3);
    });

    it("should return 1 for tile without amplify effect", () => {
      const tile = createTileWithValue(0, 0, 4);
      expect(getAmplifyMultiplier(tile)).toBe(1);
    });

    it("should return 1 for tile with inactive amplify effect", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();
      tile.effect.active = false;
      expect(getAmplifyMultiplier(tile)).toBe(1);
    });

    it("should return 1 for empty tile", () => {
      const tile = createEmptyTile(0, 0);
      expect(getAmplifyMultiplier(tile)).toBe(1);
    });
  });

  describe("processAmplifyEffect", () => {
    it("should multiply merge value by default multiplier", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();

      const result = processAmplifyEffect(tile, 8);

      expect(result.value).toBe(16); // 8 * 2
      expect(result.consumed).toBe(true);
      expect(result.multiplier).toBe(2);
    });

    it("should multiply merge value by custom multiplier", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();
      tile.effect.config.multiplier = 3;

      const result = processAmplifyEffect(tile, 8);

      expect(result.value).toBe(24); // 8 * 3
      expect(result.consumed).toBe(true);
      expect(result.multiplier).toBe(3);
    });

    it("should mark effect as inactive after processing", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();
      expect(tile.effect.active).toBe(true);

      processAmplifyEffect(tile, 8);

      expect(tile.effect.active).toBe(false);
    });

    it("should return original value if tile has no amplify effect", () => {
      const tile = createTileWithValue(0, 0, 4);

      const result = processAmplifyEffect(tile, 8);

      expect(result.value).toBe(8);
      expect(result.consumed).toBe(false);
      expect(result.multiplier).toBe(1);
    });

    it("should return original value if amplify effect is inactive", () => {
      const tile = createTileWithValue(0, 0, 4);
      tile.effect = createAmplifyEffect();
      tile.effect.active = false;

      const result = processAmplifyEffect(tile, 8);

      expect(result.value).toBe(8);
      expect(result.consumed).toBe(false);
      expect(result.multiplier).toBe(1);
    });

    it("should handle high merge values", () => {
      const tile = createTileWithValue(0, 0, 512);
      tile.effect = createAmplifyEffect();

      const result = processAmplifyEffect(tile, 1024);

      expect(result.value).toBe(2048); // 1024 * 2
      expect(result.consumed).toBe(true);
      expect(result.multiplier).toBe(2);
      expect(tile.effect.active).toBe(false);
    });

    it("should handle value 2 merge", () => {
      const tile = createTileWithValue(0, 0, 2);
      tile.effect = createAmplifyEffect();

      const result = processAmplifyEffect(tile, 4);

      expect(result.value).toBe(8); // 4 * 2
      expect(result.consumed).toBe(true);
      expect(result.multiplier).toBe(2);
      expect(tile.effect.active).toBe(false);
    });
  });
});
