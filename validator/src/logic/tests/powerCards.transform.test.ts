import { describe, expect, it } from "vitest";
import type { SynchronizedTileState, TileEffect } from "../src/types";
import { createEmptyTile } from "../src/factories";
import { performPowerCardTransform } from "../src/powerCards";
import type { IRandomGenerator } from "../src/random";
import { RNG_NAMESPACES } from "../src/constants";

describe("performPowerCardTransform", () => {
  const createBoardWithSize = (size: number): SynchronizedTileState[] => {
    const board: SynchronizedTileState[] = [];
    for (let row = 0; row < size; row++) {
      for (let col = 0; col < size; col++) {
        board.push(createEmptyTile(row, col));
      }
    }
    return board;
  };

  const setTileWithEffect = (
    board: SynchronizedTileState[],
    row: number,
    col: number,
    value: number,
    effectType: string,
    boardSize: number,
  ): void => {
    const index = row * boardSize + col;
    board[index] = {
      isEmpty: false,
      value,
      status: "normal",
      row,
      col,
      effect: {
        type: effectType,
        active: true,
      } as TileEffect,
    };
  };

  const mockRng: IRandomGenerator = {
    getRandom: (namespace: string) => 0.5,
    getIndices: () => ({
      "tile-gen": 0,
      shuffle: 0,
      "effect-spawn": 0,
      "totem-spawn": 0,
      "card-draw": 0,
    }),
  };

  it("should remove exactly numEffects effects from the board", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);

    // Add 5 tiles with effects
    setTileWithEffect(board, 0, 0, 2, "freeze", boardSize);
    setTileWithEffect(board, 0, 1, 2, "lock", boardSize);
    setTileWithEffect(board, 0, 2, 2, "amplify", boardSize);
    setTileWithEffect(board, 1, 0, 2, "stone", boardSize);
    setTileWithEffect(board, 1, 1, 2, "decay", boardSize);

    const result = performPowerCardTransform(board, 3, mockRng, boardSize);

    expect(result.success).toBe(true);
    expect(result.score).toBe(0);

    const tilesWithEffects = result.tiles.filter(
      (t) => t.effect && t.effect.type !== "none",
    );
    expect(tilesWithEffects.length).toBe(2); // 5 - 3 = 2
  });

  it("should return success false when no effects are present", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);

    const result = performPowerCardTransform(board, 3, mockRng, boardSize);

    expect(result.success).toBe(false);
    expect(result.score).toBe(0);
  });

  it("should remove all effects when numEffects >= total effects", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);

    // Add 3 tiles with effects
    setTileWithEffect(board, 0, 0, 2, "freeze", boardSize);
    setTileWithEffect(board, 0, 1, 2, "lock", boardSize);
    setTileWithEffect(board, 0, 2, 2, "amplify", boardSize);

    const result = performPowerCardTransform(board, 10, mockRng, boardSize);

    expect(result.success).toBe(true);

    const tilesWithEffects = result.tiles.filter(
      (t) => t.effect && t.effect.type !== "none",
    );
    expect(tilesWithEffects.length).toBe(0);
  });

  it("should not modify tiles without effects", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);

    // Add 2 tiles with effects and 2 without
    setTileWithEffect(board, 0, 0, 8, "freeze", boardSize);
    setTileWithEffect(board, 0, 1, 16, "lock", boardSize);

    board[2] = { isEmpty: false, value: 32, status: "normal", row: 0, col: 2 };
    board[3] = { isEmpty: false, value: 64, status: "normal", row: 0, col: 3 };

    const result = performPowerCardTransform(board, 1, mockRng, boardSize);

    expect(result.success).toBe(true);

    // Check that tiles without effects still have their values
    const tile2 = result.tiles[2];
    const tile3 = result.tiles[3];
    expect(tile2.value).toBe(32);
    expect(tile3.value).toBe(64);
    expect(tile2.effect).toBeUndefined();
    expect(tile3.effect).toBeUndefined();
  });

  it("should work on 6x6 board", () => {
    const boardSize = 6;
    const board = createBoardWithSize(boardSize);

    // Add effects to various tiles
    setTileWithEffect(board, 0, 0, 2, "freeze", boardSize);
    setTileWithEffect(board, 1, 1, 4, "lock", boardSize);
    setTileWithEffect(board, 2, 2, 8, "amplify", boardSize);
    setTileWithEffect(board, 3, 3, 16, "stone", boardSize);
    setTileWithEffect(board, 4, 4, 32, "decay", boardSize);
    setTileWithEffect(board, 5, 5, 64, "amplify_static", boardSize);

    const result = performPowerCardTransform(board, 3, mockRng, boardSize);

    expect(result.success).toBe(true);

    const tilesWithEffects = result.tiles.filter(
      (t) => t.effect && t.effect.type !== "none",
    );
    expect(tilesWithEffects.length).toBe(3); // 6 - 3 = 3
  });

  it("should preserve tile values when removing effects", () => {
    const boardSize = 4;
    const board = createBoardWithSize(boardSize);

    setTileWithEffect(board, 0, 0, 128, "freeze", boardSize);
    setTileWithEffect(board, 0, 1, 256, "lock", boardSize);

    const result = performPowerCardTransform(board, 1, mockRng, boardSize);

    expect(result.success).toBe(true);

    // Check that values are preserved
    const tile0 = result.tiles[0];
    const tile1 = result.tiles[1];

    // One should still have value and effect, one should have value but no effect
    const totalValue = tile0.value + tile1.value;
    expect(totalValue).toBe(384); // 128 + 256
  });
});
