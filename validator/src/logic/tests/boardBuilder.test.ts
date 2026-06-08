import { describe, expect, it } from "vitest";
import {
  buildInitialBoard,
  setTileAt,
  validateBoardConfig,
} from "../src/boardBuilder";
import { RandomGenerator } from "../src/random";
import type { InitialBoardConfig, SynchronizedTileState } from "../src/types";

describe("boardBuilder", () => {
  const mockRng = new RandomGenerator(
    {
      "tile-gen": 12345,
      shuffle: 12346,
      "effect-spawn": 12347,
      "totem-spawn": 12348,
      "card-draw": 12349,
    },
    {
      "tile-gen": 0,
      shuffle: 0,
      "effect-spawn": 0,
      "totem-spawn": 0,
      "card-draw": 0,
    },
  );

  describe("buildInitialBoard", () => {
    describe("explicit tile placement", () => {
      it("should create empty board with no config", () => {
        const config: InitialBoardConfig = {};
        const tiles = buildInitialBoard(config, 4, mockRng);

        expect(tiles).toHaveLength(16);
        expect(tiles.every((tile) => tile.isEmpty)).toBe(true);
      });

      it("should place single tile at specified position", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 1, col: 2 },
              config: { value: 8 },
            },
          ],
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        expect(tiles).toHaveLength(16);
        const tile = tiles[1 * 4 + 2];
        expect(tile.isEmpty).toBe(false);
        expect(tile.value).toBe(8);
        expect(tile.row).toBe(1);
        expect(tile.col).toBe(2);
      });

      it("should place multiple tiles at different positions", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 2 },
            },
            {
              position: { row: 0, col: 3 },
              config: { value: 4 },
            },
            {
              position: { row: 3, col: 0 },
              config: { value: 16 },
            },
            {
              position: { row: 3, col: 3 },
              config: { value: 32 },
            },
          ],
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        expect(tiles[0 * 4 + 0].value).toBe(2);
        expect(tiles[0 * 4 + 3].value).toBe(4);
        expect(tiles[3 * 4 + 0].value).toBe(16);
        expect(tiles[3 * 4 + 3].value).toBe(32);

        expect(tiles[0 * 4 + 0].isEmpty).toBe(false);
        expect(tiles[0 * 4 + 3].isEmpty).toBe(false);
        expect(tiles[3 * 4 + 0].isEmpty).toBe(false);
        expect(tiles[3 * 4 + 3].isEmpty).toBe(false);
      });

      it("should place tiles with effects", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 16, effect: { type: "freeze" } },
            },
            {
              position: { row: 1, col: 1 },
              config: { value: 32, effect: { type: "amplify" } },
            },
          ],
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        const tile1 = tiles[0 * 4 + 0];
        expect(tile1.value).toBe(16);
        expect(tile1.effect).toBeDefined();
        expect(tile1.effect?.type).toBe("freeze");
        expect(tile1.effect?.active).toBe(true);

        const tile2 = tiles[1 * 4 + 1];
        expect(tile2.value).toBe(32);
        expect(tile2.effect).toBeDefined();
        expect(tile2.effect?.type).toBe("amplify");
        expect(tile2.effect?.active).toBe(true);
      });

      it("should place tiles with effect config overrides", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: {
                value: 8,
                effect: {
                  type: "lock",
                  config: { remainingTriggers: 3 },
                },
              },
            },
          ],
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        const tile = tiles[0];
        expect(tile.effect?.config.remainingTriggers).toBe(3);
      });
    });

    describe("random tile generation", () => {
      it("should generate correct number of random tiles", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 5,
            values: [2, 4],
          },
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        const nonEmptyTiles = tiles.filter((tile) => !tile.isEmpty);
        expect(nonEmptyTiles).toHaveLength(5);
      });

      it("should use values from specified list", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 3,
            values: [8, 16],
          },
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        const nonEmptyTiles = tiles.filter((tile) => !tile.isEmpty);
        expect(nonEmptyTiles).toHaveLength(3);
        nonEmptyTiles.forEach((tile) => {
          expect([8, 16]).toContain(tile.value);
        });
      });

      it("should respect avoidPositions", () => {
        const avoidPos = { row: 0, col: 0 };
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 3,
            values: [2],
            avoidPositions: [avoidPos],
          },
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        const avoidTile = tiles[avoidPos.row * 4 + avoidPos.col];
        expect(avoidTile.isEmpty).toBe(true);
      });

      it("should not place random tiles on explicit tile positions", () => {
        const explicitPos = { row: 1, col: 1 };
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: explicitPos,
              config: { value: 64 },
            },
          ],
          randomTiles: {
            count: 2,
            values: [2],
          },
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        const explicitTile = tiles[explicitPos.row * 4 + explicitPos.col];
        expect(explicitTile.value).toBe(64);

        const nonEmptyTiles = tiles.filter((tile) => !tile.isEmpty);
        expect(nonEmptyTiles).toHaveLength(3);
      });
    });

    describe("mixed explicit and random", () => {
      it("should handle both explicit and random tiles", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 32, effect: { type: "amplify" } },
            },
            {
              position: { row: 0, col: 1 },
              config: { value: 16, effect: { type: "lock" } },
            },
          ],
          randomTiles: {
            count: 3,
            values: [2, 4],
            avoidPositions: [
              { row: 0, col: 0 },
              { row: 0, col: 1 },
            ],
          },
        };
        const tiles = buildInitialBoard(config, 4, mockRng);

        expect(tiles[0 * 4 + 0].value).toBe(32);
        expect(tiles[0 * 4 + 0].effect?.type).toBe("amplify");

        expect(tiles[0 * 4 + 1].value).toBe(16);
        expect(tiles[0 * 4 + 1].effect?.type).toBe("lock");

        const nonEmptyTiles = tiles.filter((tile) => !tile.isEmpty);
        expect(nonEmptyTiles).toHaveLength(5);
      });
    });

    describe("error handling", () => {
      it("should throw if not enough space for random tiles", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 17,
            values: [2],
          },
        };

        expect(() => buildInitialBoard(config, 4, mockRng)).toThrow(
          "Cannot place 17 random tiles",
        );
      });
    });
  });

  describe("setTileAt", () => {
    it("should set tile value and isEmpty flag", () => {
      const tiles: SynchronizedTileState[] = [];
      for (let r = 0; r < 4; r++) {
        for (let c = 0; c < 4; c++) {
          tiles.push({
            isEmpty: true,
            value: 0,
            row: r,
            col: c,
            status: "normal",
          });
        }
      }

      setTileAt(tiles, 4, { row: 2, col: 1 }, { value: 8 });

      const tile = tiles[2 * 4 + 1];
      expect(tile.isEmpty).toBe(false);
      expect(tile.value).toBe(8);
    });

    it("should apply effect when specified", () => {
      const tiles: SynchronizedTileState[] = [];
      for (let r = 0; r < 4; r++) {
        for (let c = 0; c < 4; c++) {
          tiles.push({
            isEmpty: true,
            value: 0,
            row: r,
            col: c,
            status: "normal",
          });
        }
      }

      setTileAt(
        tiles,
        4,
        { row: 1, col: 2 },
        { value: 16, effect: { type: "stone" } },
      );

      const tile = tiles[1 * 4 + 2];
      expect(tile.effect).toBeDefined();
      expect(tile.effect?.type).toBe("stone");
      expect(tile.effect?.active).toBe(true);
    });

    it("should throw error for out-of-bounds positions", () => {
      const tiles: SynchronizedTileState[] = [];
      for (let r = 0; r < 4; r++) {
        for (let c = 0; c < 4; c++) {
          tiles.push({
            isEmpty: true,
            value: 0,
            row: r,
            col: c,
            status: "normal",
          });
        }
      }

      expect(() =>
        setTileAt(tiles, 4, { row: -1, col: 0 }, { value: 2 }),
      ).toThrow("out of bounds");

      expect(() =>
        setTileAt(tiles, 4, { row: 0, col: 5 }, { value: 2 }),
      ).toThrow("out of bounds");

      expect(() =>
        setTileAt(tiles, 4, { row: 4, col: 0 }, { value: 2 }),
      ).toThrow("out of bounds");
    });
  });

  describe("validateBoardConfig", () => {
    describe("explicit tile validation", () => {
      it("should accept valid explicit tile configuration", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 2 },
            },
            {
              position: { row: 2, col: 3 },
              config: { value: 16 },
            },
          ],
        };

        expect(() => validateBoardConfig(config, 4)).not.toThrow();
      });

      it("should reject out-of-bounds positions", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 5, col: 0 },
              config: { value: 2 },
            },
          ],
        };

        expect(() => validateBoardConfig(config, 4)).toThrow(
          "out of bounds for board size",
        );
      });

      it("should reject negative positions", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: -1, col: 2 },
              config: { value: 2 },
            },
          ],
        };

        expect(() => validateBoardConfig(config, 4)).toThrow("out of bounds");
      });

      it("should reject duplicate positions", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 1, col: 1 },
              config: { value: 2 },
            },
            {
              position: { row: 1, col: 1 },
              config: { value: 4 },
            },
          ],
        };

        expect(() => validateBoardConfig(config, 4)).toThrow(
          "Duplicate tile placement",
        );
      });

      it("should reject non-power-of-2 values", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 3 },
            },
          ],
        };

        expect(() => validateBoardConfig(config, 4)).toThrow(
          "not a power of 2",
        );
      });

      it("should reject zero and negative values", () => {
        const config1: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 0 },
            },
          ],
        };

        expect(() => validateBoardConfig(config1, 4)).toThrow(
          "not a power of 2",
        );

        const config2: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: -4 },
            },
          ],
        };

        expect(() => validateBoardConfig(config2, 4)).toThrow(
          "not a power of 2",
        );
      });
    });

    describe("random tile validation", () => {
      it("should accept valid random tile configuration", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 3,
            values: [2, 4, 8],
          },
        };

        expect(() => validateBoardConfig(config, 4)).not.toThrow();
      });

      it("should reject negative count", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: -1,
            values: [2],
          },
        };

        expect(() => validateBoardConfig(config, 4)).toThrow(
          "must be non-negative",
        );
      });

      it("should reject empty values array", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 2,
            values: [],
          },
        };

        expect(() => validateBoardConfig(config, 4)).toThrow("cannot be empty");
      });

      it("should reject non-power-of-2 values in random tiles", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 2,
            values: [2, 5, 8],
          },
        };

        expect(() => validateBoardConfig(config, 4)).toThrow(
          "not a power of 2",
        );
      });

      it("should reject count exceeding available positions", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 2 },
            },
          ],
          randomTiles: {
            count: 16,
            values: [2],
          },
        };

        expect(() => validateBoardConfig(config, 4)).toThrow(
          "Cannot place 16 random tiles",
        );
      });
    });

    describe("edge cases", () => {
      it("should accept empty configuration", () => {
        const config: InitialBoardConfig = {};

        expect(() => validateBoardConfig(config, 4)).not.toThrow();
      });

      it("should accept configuration with only explicit tiles", () => {
        const config: InitialBoardConfig = {
          tiles: [
            {
              position: { row: 0, col: 0 },
              config: { value: 2 },
            },
          ],
        };

        expect(() => validateBoardConfig(config, 4)).not.toThrow();
      });

      it("should accept configuration with only random tiles", () => {
        const config: InitialBoardConfig = {
          randomTiles: {
            count: 2,
            values: [2, 4],
          },
        };

        expect(() => validateBoardConfig(config, 4)).not.toThrow();
      });

      it("should accept full board with explicit tiles", () => {
        const tiles = [];
        for (let r = 0; r < 4; r++) {
          for (let c = 0; c < 4; c++) {
            tiles.push({
              position: { row: r, col: c },
              config: { value: 2 },
            });
          }
        }
        const config: InitialBoardConfig = { tiles };

        expect(() => validateBoardConfig(config, 4)).not.toThrow();
      });
    });
  });
});
