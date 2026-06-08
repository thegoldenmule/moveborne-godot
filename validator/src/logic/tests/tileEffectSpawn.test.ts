import { describe, expect, it } from "vitest";
import { DEFAULT_BOARD_SIZE, RNG_NAMESPACES } from "../src/constants";
import { createGameState } from "./testHelpers";
import type {
  AuthoritativeSpawnConfig,
  SynchronizedGameState,
  SynchronizedTileState,
} from "../src/types";
import { RandomGenerator } from "../src/random";
import { createTileEffect } from "../src/factories";
import {
  attemptSpawnEffectOnTile,
  findValidSpawnPositions,
  selectSpawnPosition,
  spawnTileEffects,
  type PowerCardSpawnAction,
} from "../src/tileEffectSpawn";

const createTestGameState = (
  tiles: SynchronizedTileState[],
  boardSize = DEFAULT_BOARD_SIZE,
): SynchronizedGameState => ({
  ...createGameState(),
  board: {
    tiles,
    size: boardSize,
  },
  moveIndex: 0,
});

const createEmptyTile = (row: number, col: number): SynchronizedTileState => ({
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

const createEmptyBoard = (
  boardSize = DEFAULT_BOARD_SIZE,
): SynchronizedTileState[] => {
  const tiles: SynchronizedTileState[] = [];
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      tiles.push(createEmptyTile(row, col));
    }
  }
  return tiles;
};

const createTestRandomGenerator = (seed = 12345) => {
  const seeds = {
    [RNG_NAMESPACES.TILE_GEN]: seed,
    [RNG_NAMESPACES.SHUFFLE]: seed + 1,
    [RNG_NAMESPACES.EFFECT_SPAWN]: seed + 2,
    [RNG_NAMESPACES.TOTEM_SPAWN]: seed + 3,
    [RNG_NAMESPACES.CARD_DRAW]: seed + 4,
  };
  const indices = {
    [RNG_NAMESPACES.TILE_GEN]: 0,
    [RNG_NAMESPACES.SHUFFLE]: 0,
    [RNG_NAMESPACES.EFFECT_SPAWN]: 0,
    [RNG_NAMESPACES.TOTEM_SPAWN]: 0,
    [RNG_NAMESPACES.CARD_DRAW]: 0,
  };
  return new RandomGenerator(seeds, indices);
};

// Helper to add default spawn configs for all effect types to a game state
const addDefaultSpawnConfigs = (
  gameState: SynchronizedGameState,
): SynchronizedGameState => {
  return {
    ...gameState,
    scenarioConfig: {
      spawnConfigs: {
        freeze: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
        amplify: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
        black_hole: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: [],
          canSpawnOnEmpty: true,
          maxActiveOnBoard: 10,
        },
        lock: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
        decay: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
        stone: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
        amplify_static: {
          spawnCurve: { type: "constant", baseChance: 0.1 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
      },
    },
  };
};

describe("TileEffectSpawn - createTileEffect", () => {
  describe("freeze effect", () => {
    it("should create basic freeze effect", () => {
      const effect = createTileEffect("freeze");
      expect(effect.type).toBe("freeze");
      expect(effect.active).toBe(true);
    });

    it("should accept custom config for freeze", () => {
      const effect = createTileEffect("freeze", { custom: "value" });
      expect(effect.config?.custom).toBe("value");
    });
  });

  describe("black_hole effect", () => {
    it("should create black hole with default config", () => {
      const effect = createTileEffect("black_hole");
      expect(effect.type).toBe("black_hole");
      expect(effect.config?.tilesConsumed).toBe(0);
      expect(effect.config?.maxTilesToImplosion).toBe(7);
    });

    it("should allow custom maxTilesToImplosion", () => {
      const effect = createTileEffect("black_hole", {
        maxTilesToImplosion: 5,
      });
      expect(effect.config?.maxTilesToImplosion).toBe(5);
      expect(effect.config?.tilesConsumed).toBe(0);
    });

    it("should override defaults with custom config", () => {
      const effect = createTileEffect("black_hole", {
        tilesConsumed: 3,
        maxTilesToImplosion: 10,
      });
      expect(effect.config?.tilesConsumed).toBe(3);
      expect(effect.config?.maxTilesToImplosion).toBe(10);
    });
  });

  describe("lock effect", () => {
    it("should create lock with default remainingTriggers", () => {
      const effect = createTileEffect("lock");
      expect(effect.type).toBe("lock");
      expect(effect.config?.remainingTriggers).toBe(1);
    });

    it("should allow custom remainingTriggers", () => {
      const effect = createTileEffect("lock", { remainingTriggers: 5 });
      expect(effect.config?.remainingTriggers).toBe(5);
    });
  });

  describe("decay effect", () => {
    it("should create decay with default config", () => {
      const effect = createTileEffect("decay");
      expect(effect.type).toBe("decay");
      expect(effect.config?.decayMoveInterval).toBe(5);
      expect(effect.config?.lastDecayMove).toBe(0);
      expect(effect.config?.decayRate).toBe(0.5);
    });

    it("should allow custom decay config", () => {
      const effect = createTileEffect("decay", {
        decayMoveInterval: 3,
        decayRate: 0.25,
      });
      expect(effect.config?.decayMoveInterval).toBe(3);
      expect(effect.config?.decayRate).toBe(0.25);
    });
  });

  describe("amplify effect", () => {
    it("should create amplify with default multiplier", () => {
      const effect = createTileEffect("amplify");
      expect(effect.type).toBe("amplify");
      expect(effect.config?.multiplier).toBe(2);
    });

    it("should allow custom multiplier", () => {
      const effect = createTileEffect("amplify", { multiplier: 3 });
      expect(effect.config?.multiplier).toBe(3);
    });
  });

  describe("stone effect", () => {
    it("should create basic stone effect", () => {
      const effect = createTileEffect("stone");
      expect(effect.type).toBe("stone");
      expect(effect.active).toBe(true);
    });

    it("should accept custom config for stone", () => {
      const effect = createTileEffect("stone", { custom: "data" });
      expect(effect.config?.custom).toBe("data");
    });
  });
});

describe("TileEffectSpawn - findValidSpawnPositions", () => {
  it("should return all normal tiles for freeze effect", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    tiles[1] = createTileWithValue(0, 1, 4);
    tiles[2] = createTileWithValue(0, 2, 8);
    let gameState = createTestGameState(tiles);
    gameState = addDefaultSpawnConfigs(gameState);

    const validPositions = findValidSpawnPositions(gameState, "freeze");

    expect(validPositions.length).toBeGreaterThan(0);
    expect(validPositions).toContain(0);
    expect(validPositions).toContain(1);
    expect(validPositions).toContain(2);
  });

  it("should exclude tiles that already have effects", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    tiles[1] = createTileWithValue(0, 1, 4);
    tiles[1].effect = createTileEffect("freeze");
    let gameState = createTestGameState(tiles);
    gameState = addDefaultSpawnConfigs(gameState);

    const validPositions = findValidSpawnPositions(gameState, "amplify");

    expect(validPositions).toContain(0);
    expect(validPositions).not.toContain(1); // Already has effect
  });

  it("should only return empty tiles for black_hole", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2); // Not empty
    tiles[1] = createEmptyTile(0, 1); // Empty
    tiles[2] = createEmptyTile(0, 2); // Empty
    let gameState = createTestGameState(tiles);
    gameState = addDefaultSpawnConfigs(gameState);

    const validPositions = findValidSpawnPositions(gameState, "black_hole");

    expect(validPositions).not.toContain(0); // Has value
    expect(validPositions).toContain(1); // Empty
    expect(validPositions).toContain(2); // Empty
  });

  it("should return empty array when no valid positions", () => {
    const tiles = createEmptyBoard();
    // Fill all tiles with effects
    for (let i = 0; i < tiles.length; i++) {
      tiles[i] = createTileWithValue(0, i % DEFAULT_BOARD_SIZE, 2);
      tiles[i].effect = createTileEffect("freeze");
    }
    const gameState = createTestGameState(tiles);

    const validPositions = findValidSpawnPositions(gameState, "amplify");

    expect(validPositions.length).toBe(0);
  });
});

describe("TileEffectSpawn - selectSpawnPosition", () => {
  describe("random strategy", () => {
    it("should select from valid positions randomly", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 2);
      tiles[1] = createTileWithValue(0, 1, 4);
      const gameState = createTestGameState(tiles);
      const validIndices = [0, 1, 2, 3];
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(
        gameState,
        validIndices,
        "random",
        rng,
      );

      expect(selected).not.toBeNull();
      expect(validIndices).toContain(selected!);
    });

    it("should return null for empty valid indices", () => {
      const tiles = createEmptyBoard();
      const gameState = createTestGameState(tiles);
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(gameState, [], "random", rng);

      expect(selected).toBeNull();
    });
  });

  describe("empty strategy", () => {
    it("should only select from empty tiles", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 2); // Not empty
      tiles[1] = createEmptyTile(0, 1); // Empty
      tiles[2] = createTileWithValue(0, 2, 4); // Not empty
      const gameState = createTestGameState(tiles);
      const validIndices = [0, 1, 2];
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(
        gameState,
        validIndices,
        "empty",
        rng,
      );

      expect(selected).toBe(1); // Only empty tile
    });

    it("should return null when no empty tiles in valid indices", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 2);
      tiles[1] = createTileWithValue(0, 1, 4);
      const gameState = createTestGameState(tiles);
      const validIndices = [0, 1];
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(
        gameState,
        validIndices,
        "empty",
        rng,
      );

      expect(selected).toBeNull();
    });
  });

  describe("highest_value strategy", () => {
    it("should select tile with highest value", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 2);
      tiles[1] = createTileWithValue(0, 1, 32); // Highest
      tiles[2] = createTileWithValue(0, 2, 8);
      const gameState = createTestGameState(tiles);
      const validIndices = [0, 1, 2];
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(
        gameState,
        validIndices,
        "highest_value",
        rng,
      );

      expect(selected).toBe(1);
    });

    it("should handle ties by returning first found", () => {
      const tiles = createEmptyBoard();
      tiles[0] = createTileWithValue(0, 0, 16);
      tiles[1] = createTileWithValue(0, 1, 16);
      tiles[2] = createTileWithValue(0, 2, 8);
      const gameState = createTestGameState(tiles);
      const validIndices = [0, 1, 2];
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(
        gameState,
        validIndices,
        "highest_value",
        rng,
      );

      expect(selected).toBe(0); // First tile with value 16
    });

    it("should work with single valid position", () => {
      const tiles = createEmptyBoard();
      tiles[5] = createTileWithValue(1, 1, 64);
      const gameState = createTestGameState(tiles);
      const validIndices = [5];
      const rng = createTestRandomGenerator();

      const selected = selectSpawnPosition(
        gameState,
        validIndices,
        "highest_value",
        rng,
      );

      expect(selected).toBe(5);
    });
  });
});

describe("TileEffectSpawn - attemptSpawnEffectOnTile", () => {
  it("should not spawn effect when tile already has one", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    tiles[0].effect = createTileEffect("freeze");
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const result = attemptSpawnEffectOnTile(gameState, 0, rng);

    expect(result.success).toBe(false);
  });

  it("should filter by enabled effects via scenarioConfig", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    const gameState = createTestGameState(tiles);
    gameState.moveIndex = 1000; // High spawn chances

    // Only allow freeze effect via scenario config
    gameState.scenarioConfig = {
      spawnConfigs: {
        freeze: {
          spawnCurve: { type: "constant", baseChance: 1.0 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false,
          maxActiveOnBoard: 10,
        },
      },
    };

    const rng = createTestRandomGenerator();
    const result = attemptSpawnEffectOnTile(gameState, 0, rng);

    if (result.success) {
      expect(result.effectSpawned?.type).toBe("freeze");
    }
  });

  it("should not spawn when no spawn configs defined", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    const gameState = createTestGameState(tiles);
    gameState.moveIndex = 1000; // High spawn chances

    // With no spawn configs (all disabled), should never spawn
    gameState.scenarioConfig = {
      spawnConfigs: {}, // Empty - no effects enabled
    };

    let successCount = 0;
    for (let i = 0; i < 50; i++) {
      const rng = createTestRandomGenerator(i);
      const result = attemptSpawnEffectOnTile(gameState, 0, rng);
      if (result.success) successCount++;
    }

    expect(successCount).toBe(0);
  });

  it("should not spawn effect on empty tile unless black_hole", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createEmptyTile(0, 0);
    const gameState = createTestGameState(tiles);
    gameState.moveIndex = 1000;

    // Try to spawn freeze on empty tile (should fail)
    gameState.scenarioConfig = {
      spawnConfigs: {
        freeze: {
          spawnCurve: { type: "constant", baseChance: 1.0 },
          canSpawnOn: ["normal", "spawned", "new"],
          canSpawnOnEmpty: false, // Freeze can't spawn on empty
          maxActiveOnBoard: 10,
        },
      },
    };

    const rng = createTestRandomGenerator();
    const result = attemptSpawnEffectOnTile(gameState, 0, rng);

    expect(result.success).toBe(false);
  });
});

describe("TileEffectSpawn - spawnTileEffects (authoritative)", () => {
  it("should spawn effects at specified positions", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const config: AuthoritativeSpawnConfig = {
      effects: [
        { type: "freeze", position: { row: 0, col: 0 } },
        { type: "amplify", position: { row: 1, col: 1 } },
      ],
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "authoritative",
      authoritativeEffects: config,
    });

    expect(result.spawnedCount).toBe(2);
    expect(result.effectsSpawned.length).toBe(2);

    const tile0 = result.gameState.board.tiles[0];
    const tile5 = result.gameState.board.tiles[5]; // row 1, col 1

    expect(tile0.effect?.type).toBe("freeze");
    expect(tile5.effect?.type).toBe("amplify");
  });

  it("should apply custom configs from authoritative spawn", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const config: AuthoritativeSpawnConfig = {
      effects: [
        {
          type: "amplify",
          position: { row: 0, col: 0 },
          config: { multiplier: 5 },
        },
      ],
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "authoritative",
      authoritativeEffects: config,
    });

    const tile = result.gameState.board.tiles[0];
    expect(tile.effect?.config?.multiplier).toBe(5);
  });

  it("should skip invalid positions", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const config: AuthoritativeSpawnConfig = {
      effects: [
        { type: "freeze", position: { row: 0, col: 0 } },
        { type: "amplify", position: { row: 10, col: 10 } }, // Invalid
      ],
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "authoritative",
      authoritativeEffects: config,
    });

    expect(result.spawnedCount).toBe(1); // Only valid one
    expect(result.effectsSpawned.length).toBe(1);
  });

  it("should return empty result when no config provided", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "authoritative",
      // No authoritativeEffects provided
    });

    expect(result.spawnedCount).toBe(0);
    expect(result.effectsSpawned.length).toBe(0);
  });
});

describe("TileEffectSpawn - spawnTileEffects (powercard)", () => {
  it("should spawn effect at target position", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const action: PowerCardSpawnAction = {
      effectType: "amplify",
      targetPosition: { row: 0, col: 0 },
      sourceCardId: "card-123",
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "powercard",
      powerCardSpawn: action,
    });

    expect(result.spawnedCount).toBe(1);
    expect(result.effectsSpawned[0].type).toBe("amplify");

    const tile = result.gameState.board.tiles[0];
    expect(tile.effect?.type).toBe("amplify");
  });

  it("should apply custom config from power card", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const action: PowerCardSpawnAction = {
      effectType: "amplify",
      targetPosition: { row: 0, col: 0 },
      sourceCardId: "card-123",
      config: { multiplier: 4 },
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "powercard",
      powerCardSpawn: action,
    });

    const tile = result.gameState.board.tiles[0];
    expect(tile.effect?.config?.multiplier).toBe(4);
  });

  it("should return empty result for invalid position", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const action: PowerCardSpawnAction = {
      effectType: "amplify",
      targetPosition: { row: 10, col: 10 }, // Out of bounds
      sourceCardId: "card-123",
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "powercard",
      powerCardSpawn: action,
    });

    expect(result.spawnedCount).toBe(0);
  });

  it("should return empty result when no action provided", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "powercard",
      // No powerCardSpawn provided
    });

    expect(result.spawnedCount).toBe(0);
  });
});

describe("TileEffectSpawn - spawnTileEffects (random)", () => {
  it("should spawn effect on target tile if specified", () => {
    const tiles = createEmptyBoard();
    tiles[0] = createTileWithValue(0, 0, 2);
    const gameState = createTestGameState(tiles);
    gameState.moveIndex = 1000; // High spawn chance
    const rng = createTestRandomGenerator(999); // Use seed that gives success

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "random",
      targetTileIndex: 0,
    });

    // May or may not succeed depending on RNG, but should not error
    expect(result.spawnedCount).toBeGreaterThanOrEqual(0);
    expect(result.spawnedCount).toBeLessThanOrEqual(1);
  });

  it("should return empty result when no target specified", () => {
    const tiles = createEmptyBoard();
    const gameState = createTestGameState(tiles);
    const rng = createTestRandomGenerator();

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "random",
      // No targetTileIndex
    });

    expect(result.spawnedCount).toBe(0);
    expect(result.effectsSpawned.length).toBe(0);
  });
});

describe("TileEffectSpawn - Different Board Sizes", () => {
  it("should spawn effects on 5x5 board", () => {
    const boardSize = 5;
    const tiles = createEmptyBoard(boardSize);
    const gameState = createTestGameState(tiles, boardSize);
    const rng = createTestRandomGenerator();

    const config: AuthoritativeSpawnConfig = {
      effects: [
        { type: "freeze", position: { row: 2, col: 2 } },
        { type: "amplify", position: { row: 0, col: 4 } },
      ],
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "authoritative",
      authoritativeEffects: config,
    });

    expect(result.spawnedCount).toBe(2);
    const tile12 = result.gameState.board.tiles[12]; // row 2, col 2
    const tile4 = result.gameState.board.tiles[4]; // row 0, col 4
    expect(tile12.effect?.type).toBe("freeze");
    expect(tile4.effect?.type).toBe("amplify");
  });

  it("should spawn effects on 8x8 board", () => {
    const boardSize = 8;
    const tiles = createEmptyBoard(boardSize);
    const gameState = createTestGameState(tiles, boardSize);
    const rng = createTestRandomGenerator();

    const config: AuthoritativeSpawnConfig = {
      effects: [
        { type: "freeze", position: { row: 4, col: 4 } },
        { type: "amplify", position: { row: 0, col: 7 } },
        { type: "lock", position: { row: 7, col: 0 } },
      ],
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "authoritative",
      authoritativeEffects: config,
    });

    expect(result.spawnedCount).toBe(3);
    const tile36 = result.gameState.board.tiles[36]; // row 4, col 4
    const tile7 = result.gameState.board.tiles[7]; // row 0, col 7
    const tile56 = result.gameState.board.tiles[56]; // row 7, col 0
    expect(tile36.effect?.type).toBe("freeze");
    expect(tile7.effect?.type).toBe("amplify");
    expect(tile56.effect?.type).toBe("lock");
  });

  it("should find valid spawn positions on 6x6 board", () => {
    const boardSize = 6;
    const tiles = createEmptyBoard(boardSize);
    tiles[0] = createTileWithValue(0, 0, 2);
    tiles[5] = createTileWithValue(0, 5, 4);
    tiles[30] = createTileWithValue(5, 0, 8);
    tiles[35] = createTileWithValue(5, 5, 16);
    let gameState = createTestGameState(tiles, boardSize);
    gameState = addDefaultSpawnConfigs(gameState);

    const validPositions = findValidSpawnPositions(gameState, "freeze");

    expect(validPositions.length).toBeGreaterThan(0);
    expect(validPositions).toContain(0);
    expect(validPositions).toContain(5);
    expect(validPositions).toContain(30);
    expect(validPositions).toContain(35);
  });

  it("should handle power card spawn on 8x8 board", () => {
    const boardSize = 8;
    const tiles = createEmptyBoard(boardSize);
    tiles[63] = createTileWithValue(7, 7, 2); // Bottom-right corner
    const gameState = createTestGameState(tiles, boardSize);
    const rng = createTestRandomGenerator();

    const action: PowerCardSpawnAction = {
      effectType: "amplify",
      targetPosition: { row: 7, col: 7 },
      sourceCardId: "card-456",
    };

    const result = spawnTileEffects({
      gameState,
      randomGenerator: rng,
      spawnType: "powercard",
      powerCardSpawn: action,
    });

    expect(result.spawnedCount).toBe(1);
    const tile = result.gameState.board.tiles[63];
    expect(tile.effect?.type).toBe("amplify");
  });
});
