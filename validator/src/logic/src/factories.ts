import type {
  SynchronizedTileState,
  TileEffect,
  TileEffectConfig,
  TileEffectType,
} from "./types";
import { DEFAULT_TILE_SIZE } from "./constants";

/**
 * Create an empty synchronized tile state object
 * @param row Row position (optional)
 * @param col Column position (optional)
 * @returns Empty synchronized tile state
 */
export const createEmptyTile = (row = 0, col = 0): SynchronizedTileState => {
  return {
    isEmpty: true,
    value: 0,
    row,
    col,
    status: "normal",
  };
};

/**
 * Create a tile effect instance
 * @param type Type of tile effect
 * @param config Optional configuration for the effect
 * @returns TileEffect instance
 */
export const createTileEffect = (
  type: TileEffectType,
  config?: Partial<TileEffectConfig>,
): TileEffect => {
  // Apply default configurations based on effect type
  let effectSpecificConfig: TileEffectConfig;

  switch (type) {
    case "black_hole":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 7,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 7,
        allowsValueMerge: true,
        allowsValueMovement: false,
        effectRemovedByAdjacentMerge: false,
        visual: {
          overlayTexture: "/assets/tile-effects/black-hole/overlay.png",
          overlayWidth: 100,
          overlayHeight: 100,
          spawnEmitter: "black-hole-spawn",
          activeEmitter: "black-hole-run",
          removalEmitter: "black-hole-removal",
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: true,
        },
        ...config,
      };
      break;

    case "lock":
      effectSpecificConfig = {
        remainingTriggers: 1,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: false,
        effectRemovedByAdjacentMerge: false,
        visual: {
          overlayTexture: "/assets/tile-effects/lock/overlay.png",
          overlayWidth: DEFAULT_TILE_SIZE,
          overlayHeight: DEFAULT_TILE_SIZE,
          spawnEmitter: "lock-spawn",
          removalEmitter: "lock-removal",
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: true,
        },
        ...config,
      };
      break;

    case "decay":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0.5,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 5,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        visual: {
          spawnEmitter: "decay-spawn",
          removalEmitter: "decay-removal",
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false,
        },
        ...config,
      };
      break;

    case "amplify":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 2,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        visual: {
          backgroundTexture: "/assets/tile-effects/amplify/background.png",
          backgroundWidth: DEFAULT_TILE_SIZE + 8,
          backgroundHeight: DEFAULT_TILE_SIZE + 8,
          spawnEmitter: "amplify-spawn",
          activeEmitter: "amplify-run",
          removalEmitter: "amplify-removal",
          showMultiplier: true,
        },
        mergeConfig: {
          valueMultiplier: 2,
          consumedOnMerge: true,
          consumptionEmitter: "amplify",
          effectStaysAtSource: true,
        },
        ...config,
      };
      break;

    case "amplify_static":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 2,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        visual: {
          backgroundTexture: "/assets/tile-effects/amplify/background.png",
          backgroundWidth: DEFAULT_TILE_SIZE + 8,
          backgroundHeight: DEFAULT_TILE_SIZE + 8,
          spawnEmitter: "amplify-spawn",
          activeEmitter: "amplify-run",
          removalEmitter: "amplify-removal",
          showMultiplier: true,
        },
        mergeConfig: {
          valueMultiplier: 2,
          consumedOnMerge: false,
          consumptionEmitter: "amplify",
          effectStaysAtSource: true,
        },
        ...config,
      };
      break;

    case "freeze":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: false,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: true,
        visual: {
          overlayTexture: "/assets/tile-effects/freeze/overlay.png",
          overlayWidth: 100,
          overlayHeight: 100,
          spawnEmitter: "freeze-spawn",
          activeEmitter: "freeze-run",
          removalEmitter: "freeze-removal",
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false,
        },
        ...config,
      };
      break;

    case "stone":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: false,
        allowsValueMovement: false,
        effectRemovedByAdjacentMerge: true,
        visual: {
          overlayTexture: "/assets/tile-effects/stone/overlay.png",
          overlayWidth: DEFAULT_TILE_SIZE + 8,
          overlayHeight: DEFAULT_TILE_SIZE + 8,
          spawnEmitter: "stone-spawn",
          removalEmitter: "stone-removal",
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: true,
        },
        ...config,
      };
      break;

    case "none":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false,
        },
        ...config,
      };
      break;

    default:
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false,
        },
        ...config,
      };
  }

  return {
    type,
    active: true,
    config: effectSpecificConfig,
  };
};

/**
 * Create a tile effect of type FREEZE
 * @returns TileEffect instance
 */
export const createFreezeEffect = (): TileEffect => createTileEffect("freeze");

/**
 * Create a tile effect of type BLACK_HOLE
 * @param removalCost Optional custom removal cost in shards (default: 7)
 * @returns TileEffect instance
 */
export const createBlackHoleEffect = (removalCost?: number): TileEffect =>
  createTileEffect(
    "black_hole",
    removalCost !== undefined ? { removalCost } : undefined,
  );

/**
 * Create a tile effect of type AMPLIFY
 * @returns TileEffect instance
 */
export const createAmplifyEffect = (): TileEffect =>
  createTileEffect("amplify");

/**
 * Create a tile effect of type STONE
 * @returns TileEffect instance
 */
export const createStoneEffect = (): TileEffect => createTileEffect("stone");
