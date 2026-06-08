import type { SynchronizedGameState, GameAction, OperationType, PowerCardInstance, TotemType } from "./types";
import type { IRandomGenerator } from "./random";
import {
  performSwipe,
  updateComboMultiplier,
  addRandomTileWithEffects,
  calculateComboScore,
  calculateShards,
  processTotemEffects,
  resetTriggeredStates,
  updateTriggerStates,
  performPowerCardBomb,
  performPowerCardClear,
  performPowerCardClone,
  performPowerCardDestroy,
  performPowerCardDouble,
  performPowerCardLightning,
  performPowerCardMultiply,
  performPowerCardRadiate,
  performPowerCardShuffle,
  performPowerCardSplit,
  performPowerCardSwap,
  performPowerCardTeleport,
  performPowerCardTransform,
  performPowerCardVortex,
  canDrawCard,
  performDrawCard,
  drawCardFromDeck,
  initializeTotemConfig,
} from "./index";
import { processGlobalEffects } from "./globalEffects";

export interface SwipeActionResult {
  success: boolean;
  newState: SynchronizedGameState;
  scoreAdded: number;
  shardsAdded: number;
  moved: boolean;
  cardDrawn: boolean;
  drawnCard?: PowerCardInstance;
  error?: string;
}

export interface CardActionResult {
  success: boolean;
  newState: SynchronizedGameState;
  scoreAdded: number;
  error?: string;
}

export interface ActionExecutionResult {
  success: boolean;
  newState: SynchronizedGameState;
  scoreAdded?: number;
  shardsAdded?: number;
  cardDrawn?: boolean;
  error?: string;
}

export function executeSwipeAction(
  state: SynchronizedGameState,
  direction: string,
  rng: IRandomGenerator,
): SwipeActionResult {
  const workingState = resetTriggeredStates(state);

  const result = performSwipe(workingState, direction, rng);

  if (result.moved) {
    let newState = result.gameState;

    newState = updateComboMultiplier(
      newState,
      result.mergedTilesCount,
      rng,
    );

    const totalScore =
      result.score >= 0
        ? calculateComboScore(result.score, newState.comboMultiplier)
        : result.score;

    let shardsToAdd = result.mergedTilesCount;
    if (result.mergedTilesCount > 0) {
      const shardEvent = {
        type: "POST_SWIPE" as const,
        mergedTilesCount: result.mergedTilesCount,
        mergeOccurred: true,
        shardsMultiplier: 1,
        direction,
      };

      newState = processTotemEffects(newState, shardEvent, rng);

      const shardMultiplier = shardEvent.shardsMultiplier || 1;
      shardsToAdd = result.mergedTilesCount * shardMultiplier;
    }

    const addTileResult = addRandomTileWithEffects(newState, rng);
    newState = addTileResult.gameState;

    newState = updateTriggerStates(newState);

    // Apply shard delta before checking if we can draw a card
    newState = {
      ...newState,
      shards: calculateShards(newState.shards, shardsToAdd),
    };

    let cardDrawn = false;
    let drawnCard: PowerCardInstance | undefined;

    if (canDrawCard(newState)) {
      const drawResult = performDrawCard(newState);
      if (drawResult.success) {
        drawnCard = drawCardFromDeck(rng, newState.deck.nextCardIndex);
        newState = {
          ...newState,
          hand: {
            ...newState.hand,
            cards: [...newState.hand.cards, drawnCard],
          },
          shards: drawResult.shards,
          deck: {
            ...newState.deck,
            nextCardIndex: drawResult.deckNextCardIndex,
            remainingCards: drawResult.deckRemainingCards,
          },
        };
        cardDrawn = true;
      }
    }

    const moveCompletedEvent = {
      type: "MOVE_COMPLETED" as const,
    };
    newState = processGlobalEffects(newState, moveCompletedEvent, rng);

    return {
      success: true,
      newState,
      scoreAdded: totalScore,
      shardsAdded: shardsToAdd,
      moved: true,
      cardDrawn,
      drawnCard,
    };
  } else {
    let newState = result.gameState;

    newState = updateComboMultiplier(newState, 0, rng);

    const failedSwipeEvent = {
      type: "FAILED_SWIPE" as const,
      direction,
    };
    newState = processTotemEffects(newState, failedSwipeEvent, rng);

    const addTileResult = addRandomTileWithEffects(newState, rng);
    newState = addTileResult.gameState;

    const moveCompletedEvent = {
      type: "MOVE_COMPLETED" as const,
    };
    newState = processGlobalEffects(newState, moveCompletedEvent, rng);

    return {
      success: true,
      newState,
      scoreAdded: 0,
      shardsAdded: 0,
      moved: false,
      cardDrawn: false,
    };
  }
}

export function executePlayCardAction(
  state: SynchronizedGameState,
  action: string,
  actionData: Record<string, unknown>,
  cardIndex: number,
  rng: IRandomGenerator,
): CardActionResult {
  let newState = { ...state };
  let operationSuccess = false;
  let scoreAdded = 0;
  let error: string | undefined;

  switch (action) {
    case "split": {
      const result = performPowerCardSplit(
        newState.board.tiles,
        actionData.tile as Parameters<typeof performPowerCardSplit>[1],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_split";
      }
      break;
    }

    case "multiply": {
      const result = performPowerCardMultiply(
        newState.board.tiles,
        actionData.tile as Parameters<typeof performPowerCardMultiply>[1],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_multiply";
      }
      break;
    }

    case "shuffle": {
      const result = performPowerCardShuffle(
        newState.board.tiles,
        rng,
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_shuffle";
      }
      break;
    }

    case "lightning": {
      const result = performPowerCardLightning(
        newState.board.tiles,
        actionData.column as number | undefined,
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_lightning";
      }
      break;
    }

    case "radiate": {
      const result = performPowerCardRadiate(
        newState.board.tiles,
        actionData.tile as Parameters<typeof performPowerCardRadiate>[1],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_radiate";
      }
      break;
    }

    case "clone": {
      const result = performPowerCardClone(
        newState.board.tiles,
        actionData.sourceTile as Parameters<typeof performPowerCardClone>[1],
        actionData.targetTile as Parameters<typeof performPowerCardClone>[2],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_clone";
      }
      break;
    }

    case "swap": {
      const result = performPowerCardSwap(
        newState.board.tiles,
        actionData.tile1 as Parameters<typeof performPowerCardSwap>[1],
        actionData.tile2 as Parameters<typeof performPowerCardSwap>[2],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_swap";
      }
      break;
    }

    case "vortex": {
      const result = performPowerCardVortex(
        newState.board.tiles,
        {
          row: actionData.row as number | undefined,
          col: actionData.column as number | undefined,
        },
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_vortex";
      }
      break;
    }

    case "teleport": {
      const result = performPowerCardTeleport(
        newState.board.tiles,
        actionData.sourceTile as Parameters<typeof performPowerCardTeleport>[1],
        actionData.targetTile as Parameters<typeof performPowerCardTeleport>[2],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_teleport";
      }
      break;
    }

    case "bomb": {
      const result = performPowerCardBomb(
        newState.board.tiles,
        actionData.tile as Parameters<typeof performPowerCardBomb>[1],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_bomb";
      }
      break;
    }

    case "destroy": {
      const result = performPowerCardDestroy(
        newState.board.tiles,
        actionData.tile as Parameters<typeof performPowerCardDestroy>[1],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_destroy";
      }
      break;
    }

    case "clear": {
      const result = performPowerCardClear(
        newState.board.tiles,
        actionData.column as number | undefined,
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_clear";
      }
      break;
    }

    case "double": {
      const result = performPowerCardDouble(
        newState.board.tiles,
        actionData.tile as Parameters<typeof performPowerCardDouble>[1],
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_double";
      }
      break;
    }

    case "transform": {
      const card = newState.hand.cards.find((c) => c.type === "transform");
      const numEffects = card?.value || 1;

      const result = performPowerCardTransform(
        newState.board.tiles,
        numEffects,
        rng,
        newState.board.size,
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_transform";
      }
      break;
    }

    default:
      error = "unknown_card_action";
      break;
  }

  if (operationSuccess) {
    if (newState.hand.cards[cardIndex]) {
      newState.hand.cards.splice(cardIndex, 1);
    }
    newState = updateTriggerStates(newState);
  }

  return {
    success: operationSuccess,
    newState,
    scoreAdded,
    error,
  };
}

export function executeSpawnTotemAction(
  state: SynchronizedGameState,
  totemType: TotemType,
  cardIndex: number,
): ActionExecutionResult {
  const newState = { ...state };

  if (cardIndex < 0 || cardIndex >= newState.hand.cards.length) {
    return {
      success: false,
      newState: state,
      error: `Invalid card index: ${cardIndex}`,
    };
  }

  const totemId = `totem_${newState.moveIndex + 1}_${totemType}`;
  const newTotem = {
    id: totemId,
    type: totemType,
    config: initializeTotemConfig(totemType),
    name: totemType,
    description: totemType,
    active: true,
  };

  newState.totems = {
    ...newState.totems,
    active: [...newState.totems.active, newTotem],
  };

  newState.hand.cards.splice(cardIndex, 1);

  return {
    success: true,
    newState,
    scoreAdded: 0,
  };
}

export function executeAction(
  state: SynchronizedGameState,
  action: GameAction,
  rng: IRandomGenerator,
): ActionExecutionResult {
  switch (action.type) {
    case "SWIPE": {
      const payload = action.payload as { direction: string };
      return executeSwipeAction(state, payload.direction, rng);
    }

    case "PLAY_CARD": {
      const payload = action.payload as {
        action: string;
        cardIndex: number;
        [key: string]: unknown;
      };
      return executePlayCardAction(
        state,
        payload.action,
        payload,
        payload.cardIndex,
        rng,
      );
    }

    case "SPAWN_TOTEM": {
      const payload = action.payload as {
        totemType: TotemType;
        cardIndex: number;
      };
      return executeSpawnTotemAction(
        state,
        payload.totemType,
        payload.cardIndex,
      );
    }

    default:
      return {
        success: false,
        newState: state,
        error: `Unknown action type: ${action.type}`,
      };
  }
}
