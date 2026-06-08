import { DEFAULT_BOARD_SIZE, RNG_NAMESPACES } from "../src/constants";
import { createEmptyTile } from "../src/factories";
import type {
  GameFactoryConfig,
  SynchronizedBoardState,
  SynchronizedGameState,
} from "../src/types";

export const createBoard = (
  size: number = DEFAULT_BOARD_SIZE,
): SynchronizedBoardState => {
  const tiles = [];
  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      tiles.push(createEmptyTile(row, col));
    }
  }
  return {
    tiles,
    size,
  };
};

export const createGameState = (
  config: GameFactoryConfig = {},
): SynchronizedGameState => {
  const boardSize = config.boardSize ?? DEFAULT_BOARD_SIZE;
  const board = config.tiles
    ? { tiles: config.tiles, size: boardSize }
    : createBoard(boardSize);

  return {
    board,
    hand: { cards: config.startingCards ?? [] },
    deck: { remainingCards: config.deckSize ?? 12, nextCardIndex: 0 },
    score: config.score ?? 0,
    shards: 0,
    combo: 0,
    comboMultiplier: 1,
    totems: { active: [] },
    moveIndex: config.moveIndex ?? 0,
    randomSeeds: config.rngSeeds ?? {
      [RNG_NAMESPACES.TILE_GEN]: 12345,
      [RNG_NAMESPACES.SHUFFLE]: 12345,
      [RNG_NAMESPACES.EFFECT_SPAWN]: 12345,
      [RNG_NAMESPACES.TOTEM_SPAWN]: 12345,
      [RNG_NAMESPACES.CARD_DRAW]: 12345,
    },
    rngIndices: config.rngIndices ?? {
      [RNG_NAMESPACES.TILE_GEN]: 0,
      [RNG_NAMESPACES.SHUFFLE]: 0,
      [RNG_NAMESPACES.EFFECT_SPAWN]: 0,
      [RNG_NAMESPACES.TOTEM_SPAWN]: 0,
      [RNG_NAMESPACES.CARD_DRAW]: 0,
    },
    level: config.level,
    timeRemaining: config.timeRemaining,
    moves: undefined,
    highScore: undefined,
    moveCount: 0,
    scenarioConfig: config.scenarioConfig,
    eventTriggerStates: undefined,
    totalMerges: 0,
  };
};
