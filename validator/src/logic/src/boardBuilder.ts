import type {
  BoardPosition,
  InitialBoardConfig,
  InitialTileConfig,
  SynchronizedTileState,
} from "./types";
import type { IRandomGenerator } from "./random";
import { createEmptyTile, createTileEffect } from "./factories";

/**
 * Build initial board state from configuration
 * Handles explicit tile placements and random tile generation
 */
export function buildInitialBoard(
  config: InitialBoardConfig,
  boardSize: number,
  randomGen: IRandomGenerator,
): SynchronizedTileState[] {
  validateBoardConfig(config, boardSize);

  const tiles: SynchronizedTileState[] = [];
  for (let r = 0; r < boardSize; r++) {
    for (let c = 0; c < boardSize; c++) {
      tiles.push(createEmptyTile(r, c));
    }
  }

  if (config.tiles) {
    for (const placement of config.tiles) {
      setTileAt(tiles, boardSize, placement.position, placement.config);
    }
  }

  if (config.randomTiles) {
    const { count, values, avoidPositions = [] } = config.randomTiles;
    const emptyPositions = getEmptyPositions(tiles, avoidPositions);

    if (emptyPositions.length < count) {
      throw new Error(
        `Not enough empty positions for random tiles. Requested ${count}, available ${emptyPositions.length}`,
      );
    }

    for (let i = 0; i < count; i++) {
      const randomIndex = Math.floor(
        randomGen.getRandom("tile-gen") * emptyPositions.length,
      );
      const position = emptyPositions.splice(randomIndex, 1)[0];
      const randomValueIndex = Math.floor(
        randomGen.getRandom("tile-gen") * values.length,
      );
      const value = values[randomValueIndex];

      setTileAt(tiles, boardSize, position, { value });
    }
  }

  return tiles;
}

/**
 * Set a tile at a specific position with given configuration
 */
export function setTileAt(
  tiles: SynchronizedTileState[],
  boardSize: number,
  position: BoardPosition,
  config: InitialTileConfig,
): void {
  const { row, col } = position;

  if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) {
    throw new Error(
      `Position (${row}, ${col}) is out of bounds for board size ${boardSize}`,
    );
  }

  const index = row * boardSize + col;
  const tile = tiles[index];

  tile.isEmpty = false;
  tile.value = config.value;

  if (config.effect) {
    tile.effect = createTileEffect(config.effect.type, config.effect.config);
  }
}

/**
 * Get list of empty positions that are not in the avoid list
 */
function getEmptyPositions(
  tiles: SynchronizedTileState[],
  avoidPositions: BoardPosition[],
): BoardPosition[] {
  const emptyPositions: BoardPosition[] = [];

  for (const tile of tiles) {
    if (!tile.isEmpty) continue;

    const isAvoided = avoidPositions.some(
      (pos) => pos.row === tile.row && pos.col === tile.col,
    );

    if (!isAvoided) {
      emptyPositions.push({ row: tile.row, col: tile.col });
    }
  }

  return emptyPositions;
}

/**
 * Validate board configuration for correctness
 */
export function validateBoardConfig(
  config: InitialBoardConfig,
  boardSize: number,
): void {
  if (config.tiles) {
    const positions = new Set<string>();

    for (const placement of config.tiles) {
      const { row, col } = placement.position;

      if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) {
        throw new Error(
          `Tile position (${row}, ${col}) is out of bounds for board size ${boardSize}`,
        );
      }

      const posKey = `${row},${col}`;
      if (positions.has(posKey)) {
        throw new Error(
          `Duplicate tile placement at position (${row}, ${col})`,
        );
      }
      positions.add(posKey);

      const { value } = placement.config;
      if (value <= 0 || (value & (value - 1)) !== 0) {
        throw new Error(
          `Tile value ${value} at position (${row}, ${col}) is not a power of 2`,
        );
      }
    }
  }

  if (config.randomTiles) {
    const { count, values } = config.randomTiles;

    if (count < 0) {
      throw new Error(`Random tile count must be non-negative, got ${count}`);
    }

    if (values.length === 0) {
      throw new Error("Random tile values array cannot be empty");
    }

    for (const value of values) {
      if (value <= 0 || (value & (value - 1)) !== 0) {
        throw new Error(`Random tile value ${value} is not a power of 2`);
      }
    }

    const totalPositions = boardSize * boardSize;
    const explicitTileCount = config.tiles?.length ?? 0;
    const availablePositions = totalPositions - explicitTileCount;

    if (count > availablePositions) {
      throw new Error(
        `Cannot place ${count} random tiles on board with ${availablePositions} available positions`,
      );
    }
  }
}
