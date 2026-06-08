import { RNG_NAMESPACES, TOTEM_TYPES } from "./constants";
import { createEmptyTile } from "./factories";
import { indexToRowCol } from "./gameLogic";
import type {
  GameEvent,
  SynchronizedGameState,
  SynchronizedTileState,
  Totem,
  TotemConfig,
  TotemType,
  TotemTypeDefinition,
} from "./types";
import { IRandomGenerator, RandomGenerator } from "./random";

/**
 * Process all active totem effects for a given game event
 * @param gameState - Current game state
 * @param gameEvent - Game event that triggered effect processing
 * @param randomGenerator - Random number generator instance
 * @returns Modified game state with totem effects applied
 */
export const processTotemEffects = (
  gameState: SynchronizedGameState,
  gameEvent: GameEvent,
  randomGenerator: IRandomGenerator,
): SynchronizedGameState => {
  const extendedState = gameState as SynchronizedGameState;
  const { totems } = extendedState;

  if (!totems || !totems.active || totems.active.length === 0) {
    return gameState;
  }

  // Deep clone the game state to prevent mutations affecting the original
  let modifiedState = {
    ...extendedState,
    totems: {
      ...extendedState.totems,
      active: extendedState.totems.active.map((totem) => ({
        ...totem,
        config: totem.config
          ? { ...totem.config }
          : {
              maxTallyMarks: 0,
              mergesRemaining: 0,
              movesRemaining: 0,
              swipesRemaining: 0,
              tallyMarks: 0,
              spawnValue: 0,
            },
      })),
    },
  };
  const extendedEvent = gameEvent as GameEvent;

  // Handle spawn booster prioritization for TILE_SPAWN events
  if (extendedEvent.type === "TILE_SPAWN") {
    const spawnBoosters = modifiedState.totems.active.filter((totem) =>
      isSpawnBooster(totem.type),
    );

    if (spawnBoosters.length > 0) {
      // Find the highest priority spawn booster (8x > 4x > 2x)
      // Only the highest priority booster will be consumed and applied
      const highestPriorityBooster = spawnBoosters.reduce(
        (highest, current) => {
          return getSpawnBoosterPriority(current.type) >
            getSpawnBoosterPriority(highest.type)
            ? current
            : highest;
        },
      );

      // Apply only the highest priority booster's effect
      modifiedState = processSpawnBooster(
        modifiedState,
        highestPriorityBooster,
        extendedEvent,
      );

      // Process all other non-spawn-booster totems normally
      for (const totem of modifiedState.totems.active) {
        if (!isSpawnBooster(totem.type)) {
          modifiedState = processTotemByType(
            modifiedState,
            totem,
            extendedEvent,
            randomGenerator,
          );
        }
      }
    } else {
      // No spawn boosters, process all totems normally
      for (const totem of modifiedState.totems.active) {
        modifiedState = processTotemByType(
          modifiedState,
          totem,
          extendedEvent,
          randomGenerator,
        );
      }
    }
  } else {
    // For non-TILE_SPAWN events, process all totems normally
    for (const totem of modifiedState.totems.active) {
      modifiedState = processTotemByType(
        modifiedState,
        totem,
        extendedEvent,
        randomGenerator,
      );
    }
  }

  // Check for despawn conditions after processing all effects
  modifiedState = checkTotemDespawnConditions(modifiedState, extendedEvent);

  return modifiedState as SynchronizedGameState;
};

/**
 * Helper function to process a totem by its type
 * @param gameState - Current game state
 * @param totem - Totem to process
 * @param gameEvent - Game event
 * @param randomGenerator - Random number generator instance
 * @returns Modified game state
 */
const processTotemByType = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
  randomGenerator: IRandomGenerator,
): SynchronizedGameState => {
  switch (totem.type) {
    case "combo_saver":
      return processComboSaver(gameState, totem, gameEvent);
    case "spawn_booster_2x":
    case "spawn_booster_4x":
    case "spawn_booster_8x":
      return processSpawnBooster(gameState, totem, gameEvent);
    case "momentum_idol":
      return processMomentumIdol(gameState, totem, gameEvent);
    case "magnet_core":
      return processMagnetCore(gameState, totem, gameEvent);
    case "void_gate":
      return processVoidGate(gameState, totem, gameEvent);
    case "ghost_merge":
      return processGhostMerge(gameState, totem, gameEvent, randomGenerator);
    case "scavenger":
      return processScavenger(gameState, totem, gameEvent);
    case "chrono_anchor":
      return processChronoAnchor(gameState);
    default:
      console.warn(`Unknown totem type: ${totem.type}`);
      return gameState;
  }
};

/**
 * Process Combo Saver totem effects
 * Prevents combo breaks and tracks tally marks
 */
const processComboSaver = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  if (gameEvent.type === "COMBO_BREAK_ATTEMPTED") {
    // Initialize config if not present
    if (!totem.config) {
      totem.config = {};
    }

    // Increment tally marks
    totem.config.tallyMarks = (totem.config.tallyMarks || 0) + 1;

    // Prevent combo break by restoring previous combo value
    if (gameEvent.previousCombo !== undefined) {
      gameState.comboMultiplier = gameEvent.previousCombo;
    }

    // Check if totem should despawn after reaching max tally marks
    const totemDef = Object.values(TOTEM_TYPES).find(
      (t: TotemTypeDefinition) => t.id === totem.type,
    ) as TotemTypeDefinition | undefined;

    if (totem.config.tallyMarks >= (totemDef?.maxTallyMarks || 3)) {
      gameState.totems.active = gameState.totems.active.filter(
        (t) => t.id !== totem.id,
      );
    }
  }

  return gameState;
};

/**
 * Process Spawn Booster totem effects
 * Overrides tile spawn values and decrements move counter
 */
const processSpawnBooster = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  if (gameEvent.type === "TILE_SPAWN") {
    // Get spawn value from totem configuration
    const totemDefinition = Object.values(TOTEM_TYPES).find(
      (t: TotemTypeDefinition) => t.id === totem.type,
    ) as TotemTypeDefinition | undefined;

    if (totemDefinition && totemDefinition.spawnValue) {
      // Override spawn value
      gameEvent.tileValue = totemDefinition.spawnValue;
    }

    // Initialize config if not present
    if (!totem.config) {
      totem.config = {};
    }

    // Decrement move counter
    if (totem.config.movesRemaining !== undefined) {
      totem.config.movesRemaining = Math.max(
        0,
        totem.config.movesRemaining - 1,
      );
    }
  }

  return gameState;
};

/**
 * Process Momentum Idol totem effects
 * Adds +1 to combo multiplier increments
 */
const processMomentumIdol = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  if (gameEvent.type === "COMBO_INCREMENT") {
    // Add +1 to combo increment
    gameEvent.incrementAmount = (gameEvent.incrementAmount || 0) + 1;
  } else if (
    gameEvent.type === "MOVE_COMPLETED" &&
    totem.config?.movesRemaining !== undefined
  ) {
    // Decrement move counter
    totem.config.movesRemaining = Math.max(0, totem.config.movesRemaining - 1);
  }

  return gameState;
};

/**
 * Process Magnet Core totem effects
 * Moves all tiles toward the center of the board (no merging)
 */
const processMagnetCore = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  if (gameEvent.type === "POST_SPAWN") {
    // Implement magnet effect logic
    const newTiles = [...gameState.board.tiles];
    const BOARD_SIZE = 4; // 4x4 board

    // The 4 center positions in a 4x4 board
    const centerPositions = [
      { row: 1, col: 1 },
      { row: 1, col: 2 },
      { row: 2, col: 1 },
      { row: 2, col: 2 },
    ];

    // Helper function to get tile at position
    const getTile = (
      tiles: SynchronizedTileState[],
      row: number,
      col: number,
    ): SynchronizedTileState => tiles[row * BOARD_SIZE + col];

    // Helper function to set tile at position
    const setTile = (
      tiles: SynchronizedTileState[],
      row: number,
      col: number,
      tile: SynchronizedTileState,
    ): void => {
      tiles[row * BOARD_SIZE + col] = tile;
    };

    // Helper function to get distance to nearest center position
    const getDistanceToCenter = (row: number, col: number): number => {
      let minDistance = Infinity;
      for (const center of centerPositions) {
        const distance =
          Math.abs(row - center.row) + Math.abs(col - center.col); // Manhattan distance
        minDistance = Math.min(minDistance, distance);
      }
      return minDistance;
    };

    // Helper function to get the nearest center position
    const getNearestCenter = (row: number, col: number) => {
      let nearestCenter = centerPositions[0];
      let minDistance = Infinity;

      for (const center of centerPositions) {
        const distance =
          Math.abs(row - center.row) + Math.abs(col - center.col);
        if (distance < minDistance) {
          minDistance = distance;
          nearestCenter = center;
        }
      }
      return nearestCenter;
    };

    // Keep moving tiles until no more movement is possible
    // Track which tiles moved so we can mark them as magnetized
    const movedTiles = new Set<number>();

    let moved = true;
    while (moved) {
      moved = false;

      // Get all tile positions and sort by distance from center (farthest first)
      const tilePositions: {
        row: number;
        col: number;
        tile: SynchronizedTileState;
        distance: number;
      }[] = [];
      for (let row = 0; row < BOARD_SIZE; row++) {
        for (let col = 0; col < BOARD_SIZE; col++) {
          const tile = getTile(newTiles, row, col);
          if (tile && !tile.isEmpty) {
            tilePositions.push({
              row,
              col,
              tile,
              distance: getDistanceToCenter(row, col),
            });
          }
        }
      }

      // Sort by distance (farthest first)
      tilePositions.sort((a, b) => b.distance - a.distance);

      // Try to move each tile one step closer to its nearest center
      for (const { row, col, tile } of tilePositions) {
        const nearestCenter = getNearestCenter(row, col);

        // Calculate direction toward nearest center
        let newRow = row;
        let newCol = col;

        // Move toward center, prioritizing the axis with larger difference
        const rowDiff = nearestCenter.row - row;
        const colDiff = nearestCenter.col - col;

        if (Math.abs(rowDiff) > Math.abs(colDiff)) {
          // Move vertically first
          if (rowDiff > 0) {
            newRow = row + 1;
          } else if (rowDiff < 0) {
            newRow = row - 1;
          }
        } else if (Math.abs(colDiff) > 0) {
          // Move horizontally
          if (colDiff > 0) {
            newCol = col + 1;
          } else if (colDiff < 0) {
            newCol = col - 1;
          }
        }

        // Check if the new position is valid and empty
        if (
          newRow >= 0 &&
          newRow < BOARD_SIZE &&
          newCol >= 0 &&
          newCol < BOARD_SIZE &&
          getTile(newTiles, newRow, newCol).isEmpty
        ) {
          // Move the tile
          setTile(newTiles, row, col, createEmptyTile(row, col));
          setTile(newTiles, newRow, newCol, tile);
          movedTiles.add(newRow * BOARD_SIZE + newCol);
          moved = true;
        }
      }
    }

    // Mark only tiles that moved as magnetized (preserve "new" and "merged" statuses)
    for (let i = 0; i < newTiles.length; i++) {
      if (newTiles[i] && !newTiles[i].isEmpty && movedTiles.has(i)) {
        // Only set magnetized if the tile doesn't have a more important status
        if (newTiles[i].status !== "new" && newTiles[i].status !== "merged") {
          newTiles[i] = {
            ...newTiles[i],
            status: "magnetized",
            meta: { ...newTiles[i].meta },
          };
        }
      }
    }

    // Update game state with magnetized board
    gameState = {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles,
      },
    };

    // Initialize config if not present
    if (!totem.config) {
      totem.config = {};
    }

    // Decrement move counter
    if (totem.config.movesRemaining !== undefined) {
      totem.config.movesRemaining = Math.max(
        0,
        totem.config.movesRemaining - 1,
      );
    }
  }

  return gameState;
};

/**
 * Process Void Gate totem effects
 * Removes lowest tile instead of spawning on failed swipes
 */
const processVoidGate = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  if (gameEvent.type === "POST_SWIPE") {
    // Only trigger if no merges occurred
    if (!gameEvent.mergeOccurred) {
      // Find the lowest value tile (excluding empty tiles)
      const tiles = gameState.board.tiles;
      let lowestIndex = -1;
      let lowestValue = Infinity;
      let nonEmptyCount = 0;

      for (let i = 0; i < tiles.length; i++) {
        if (tiles[i] && !tiles[i].isEmpty) {
          nonEmptyCount++;
          if (tiles[i].value < lowestValue) {
            lowestValue = tiles[i].value;
            lowestIndex = i;
          }
        }
      }

      // Only remove the lowest tile if there's more than 1 tile on the board
      if (lowestIndex !== -1 && nonEmptyCount > 1) {
        const row = Math.floor(lowestIndex / 4);
        const col = lowestIndex % 4;

        // Replace the lowest tile with an empty tile
        const newTiles = [...tiles];
        newTiles[lowestIndex] = createEmptyTile(row, col);

        gameState = {
          ...gameState,
          board: {
            ...gameState.board,
            tiles: newTiles,
          },
        };
      }
    }

    // Initialize config if not present
    if (!totem.config) {
      totem.config = {};
    }

    // Decrement move counter on every swipe
    if (totem.config.movesRemaining !== undefined) {
      totem.config.movesRemaining = Math.max(
        0,
        totem.config.movesRemaining - 1,
      );
    }
  }

  return gameState;
};

/**
 * Process Ghost Merge totem effects
 * Echoes first merge to random empty cell
 */
const processGhostMerge = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
  randomGenerator: IRandomGenerator,
): SynchronizedGameState => {
  // Handle the ghost merge effect during post-swipe
  if (
    gameEvent.type === "POST_SWIPE" &&
    gameEvent.mergeOccurred &&
    totem.config?.mergesRemaining !== undefined &&
    totem.config.mergesRemaining > 0
  ) {
    // Find all merged tiles (tiles with status "merged")
    const mergedTiles: {
      index: number;
      row: number;
      col: number;
      value: number;
    }[] = [];
    gameState.board.tiles.forEach((tile, index) => {
      if (tile && tile.status === "merged") {
        mergedTiles.push({
          index,
          row: Math.floor(index / 4),
          col: index % 4,
          value: tile.value,
        });
      }
    });

    // If we have merged tiles, process the first one (ghost merge effect)
    if (mergedTiles.length > 0) {
      const firstMerge = mergedTiles[0];

      // Find all empty cells on the board
      const emptyCells: { index: number; row: number; col: number }[] = [];
      gameState.board.tiles.forEach((tile, index) => {
        if (tile?.isEmpty) {
          emptyCells.push({
            index,
            row: Math.floor(index / 4),
            col: index % 4,
          });
        }
      });

      // If we have empty cells, place a ghost tile
      if (emptyCells.length > 0) {
        // Select a random empty cell
        const randomCell =
          emptyCells[
            Math.floor(
              randomGenerator.getRandom(RNG_NAMESPACES.TOTEM_SPAWN) *
                emptyCells.length,
            )
          ];

        // Create a new tile with the same value as the first merge
        const ghostTile: SynchronizedTileState = {
          isEmpty: false,
          value: firstMerge.value,
          status: "spawned", // Use spawned status to show it's a special tile
          meta: {
            isGhost: true, // Mark as ghost merge tile for potential future use
          },
          ...indexToRowCol(randomCell.index, gameState.board.size),
          effect: undefined,
        };

        // Place the ghost tile in the random empty cell
        gameState.board.tiles[randomCell.index] = ghostTile;

        console.log(
          `Ghost Merge: Created tile with value ${firstMerge.value} at position (${randomCell.row}, ${randomCell.col})`,
        );
      }

      // Decrement merge counter immediately when effect triggers
      totem.config.mergesRemaining = Math.max(
        0,
        totem.config.mergesRemaining - 1,
      );
    }
  }

  return gameState;
};

/**
 * Process Scavenger totem effects
 * Doubles shards earned from merges (4 uses)
 */
const processScavenger = (
  gameState: SynchronizedGameState,
  totem: Totem,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  // Handle shard doubling during post-swipe
  if (
    gameEvent.type === "POST_SWIPE" &&
    gameEvent.mergedTilesCount !== undefined &&
    gameEvent.mergedTilesCount > 0 &&
    totem.config?.mergesRemaining !== undefined &&
    totem.config.mergesRemaining > 0
  ) {
    // Double the shard multiplier
    gameEvent.shardsMultiplier = (gameEvent.shardsMultiplier || 1) * 2;

    // Decrement merge counter
    totem.config.mergesRemaining = Math.max(
      0,
      totem.config.mergesRemaining - 1,
    );
  }

  return gameState;
};

/**
 * Process Chrono Anchor totem effects
 * Manages time rewind snapshots
 */
const processChronoAnchor = (
  gameState: SynchronizedGameState,
): SynchronizedGameState => {
  return gameState;
};

/**
 * Check despawn conditions for all active totems
 * @param gameState - Current game state
 * @param gameEvent - Game event that might trigger despawn
 * @returns Game state with despawned totems removed
 */
const checkTotemDespawnConditions = (
  gameState: SynchronizedGameState,
  gameEvent: GameEvent,
): SynchronizedGameState => {
  const activeTotems = gameState.totems.active.filter((totem) => {
    // Check move-based despawn conditions (only on MOVE_COMPLETED to avoid double counting)
    if (
      gameEvent.type === "MOVE_COMPLETED" &&
      totem.config?.movesRemaining !== undefined
    ) {
      return totem.config.movesRemaining > 0;
    }

    // Check merge-based despawn conditions (for Ghost Merge)
    if (
      gameEvent.type === "POST_SWIPE" &&
      gameEvent.mergeOccurred &&
      totem.config?.mergesRemaining !== undefined
    ) {
      return totem.config.mergesRemaining > 0;
    }

    // Check tally-based despawn conditions
    if (totem.config?.maxTallyMarks !== undefined) {
      return (totem.config.tallyMarks || 0) < totem.config.maxTallyMarks;
    }

    return true; // Keep totem if no despawn condition met
  });

  // Update active totems list if any were filtered out
  if (activeTotems.length !== gameState.totems.active.length) {
    gameState.totems.active = activeTotems;
  }

  return gameState;
};

/**
 * Initialize a totem with default configuration based on its type
 * @param totemType - The type of totem to initialize
 * @param customConfig - Optional custom configuration
 * @returns Initialized totem configuration
 */
export const initializeTotemConfig = (
  totemType: TotemType,
  customConfig: Partial<TotemConfig> = {},
): TotemConfig => {
  const totemDefinition = Object.values(TOTEM_TYPES).find(
    (t: TotemTypeDefinition) => t.id === totemType,
  ) as TotemTypeDefinition | undefined;

  if (!totemDefinition) {
    throw new Error(`Unknown totem type: ${totemType}`);
  }

  const config: TotemConfig = { ...customConfig };

  // Set default values based on totem definition
  if (totemDefinition.defaultMoves !== undefined) {
    config.movesRemaining =
      config.movesRemaining || totemDefinition.defaultMoves;
  }

  if (totemDefinition.defaultSwipes !== undefined) {
    config.swipesRemaining =
      config.swipesRemaining || totemDefinition.defaultSwipes;
  }

  if (totemDefinition.defaultMerges !== undefined) {
    config.mergesRemaining =
      config.mergesRemaining || totemDefinition.defaultMerges;
  }

  if (totemDefinition.maxTallyMarks !== undefined) {
    config.tallyMarks = config.tallyMarks || 0;
    config.maxTallyMarks = totemDefinition.maxTallyMarks;
  }

  if (totemDefinition.spawnValue !== undefined) {
    config.spawnValue = totemDefinition.spawnValue;
  }

  return config;
};

/**
 * Get the priority value for a spawn booster totem type
 * Higher values indicate higher priority
 * @param totemType - The totem type (e.g., "spawn_booster_8x")
 * @returns Priority value (3 for 8x, 2 for 4x, 1 for 2x, 0 for others)
 */
const getSpawnBoosterPriority = (totemType: TotemType): number => {
  const priorities: Record<string, number> = {
    spawn_booster_8x: 3, // Highest priority (spawns 16s)
    spawn_booster_4x: 2, // Medium priority (spawns 8s)
    spawn_booster_2x: 1, // Lowest priority (spawns 4s)
  };
  return priorities[totemType] || 0;
};

/**
 * Check if a totem type is a spawn booster
 * @param totemType - The totem type to check
 * @returns True if the totem is a spawn booster
 */
const isSpawnBooster = (totemType: TotemType): boolean => {
  return ["spawn_booster_2x", "spawn_booster_4x", "spawn_booster_8x"].includes(
    totemType,
  );
};

/**
 * Test function to verify spawn booster prioritization
 * This function can be called from browser console for testing
 */
const testSpawnBoosterPrioritization = (): void => {
  console.log("=== Spawn Booster Prioritization Tests ===");

  // Create test game state with multiple spawn boosters
  const createTestGameState = (
    activeTotemTypes: TotemType[],
  ): SynchronizedGameState => {
    return {
      totems: {
        active: activeTotemTypes.map((type, index) => ({
          id: `test_totem_${index}`,
          type: type,
          name: "",
          description: "",
          active: true,
          config: {
            movesRemaining: 5,
          },
        })),
      },
    } as SynchronizedGameState;
  };

  // Create test spawn event
  const createSpawnEvent = (): GameEvent => ({
    type: "TILE_SPAWN",
    tileValue: 2, // Default spawn value
  });

  // Test 1: Multiple spawn boosters - 8x should win
  console.log("\n--- Test 1: 8x vs 4x vs 2x (8x should win) ---");
  const gameState1 = createTestGameState([
    "spawn_booster_2x",
    "spawn_booster_4x",
    "spawn_booster_8x",
  ]);
  const spawnEvent1 = createSpawnEvent();
  // Create a test IRandomGenerator for testing
  const testRng: IRandomGenerator = new RandomGenerator(
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
  const result1 = processTotemEffects(gameState1, spawnEvent1, testRng);

  console.log("Original spawn value:", 2);
  console.log("Final spawn value:", spawnEvent1.tileValue);
  console.log(
    "Expected:",
    16,
    "Actual:",
    spawnEvent1.tileValue,
    "✓",
    spawnEvent1.tileValue === 16,
  );

  // Verify only 8x totem had its moves decremented
  const extendedResult1 = result1 as SynchronizedGameState;
  const totem8x = extendedResult1.totems.active.find(
    (t) => t.type === "spawn_booster_8x",
  );
  const totem4x = extendedResult1.totems.active.find(
    (t) => t.type === "spawn_booster_4x",
  );
  const totem2x = extendedResult1.totems.active.find(
    (t) => t.type === "spawn_booster_2x",
  );

  console.log(
    "8x moves remaining:",
    totem8x?.config?.movesRemaining,
    "(should be 4)",
  );
  console.log(
    "4x moves remaining:",
    totem4x?.config?.movesRemaining,
    "(should be 5)",
  );
  console.log(
    "2x moves remaining:",
    totem2x?.config?.movesRemaining,
    "(should be 5)",
  );

  console.log("\n=== All Tests Complete ===");
};

// Export for use in browser console
if (typeof window !== "undefined") {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (window as any).testSpawnBoosterPrioritization =
    testSpawnBoosterPrioritization;
}
