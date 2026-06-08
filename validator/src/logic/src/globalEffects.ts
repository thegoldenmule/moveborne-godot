import type {
  EventBasedSpawnRule,
  GameEvent,
  GlobalEffectState,
  SynchronizedGameState,
} from "./types";
import type { IRandomGenerator } from "./random";
import { RNG_NAMESPACES } from "./constants";

export function processGlobalEffects(
  gameState: SynchronizedGameState,
  gameEvent: GameEvent,
  randomGenerator: IRandomGenerator,
): SynchronizedGameState {
  if (!gameState.globalEffects || gameState.globalEffects.length === 0) {
    return gameState;
  }

  let modifiedState = { ...gameState };

  if (gameEvent.type === "MOVE_COMPLETED") {
    modifiedState.globalEffects = (modifiedState.globalEffects || [])
      .map((effect) => {
        const newMovesRemaining = Math.max(0, effect.movesRemaining - 1);

        if (newMovesRemaining === 0) {
          return null;
        }

        const newSeed =
          randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 10000;
        const offsetVariation =
          15 + randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 10;

        return {
          ...effect,
          movesRemaining: newMovesRemaining,
          filterConfig: {
            ...effect.filterConfig,
            seed: newSeed,
            offset: offsetVariation,
          },
        };
      })
      .filter(Boolean) as GlobalEffectState[];
  }

  return modifiedState;
}

export function createGlobalEffect(
  rule: EventBasedSpawnRule,
  triggerId: string,
  randomGenerator: IRandomGenerator,
): GlobalEffectState | null {
  if (!rule.globalEffect) {
    return null;
  }

  const { type, duration, config } = rule.globalEffect;

  const effectIdSeed = Math.floor(
    randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 1000000,
  );

  const defaultConfig = {
    slices: 10,
    offset: 75,
    direction: 0,
    fillMode: 0,
    seed: randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 10000,
    average: false,
    minSize: 8,
    sampleSize: 512,
  };

  return {
    id: `${triggerId}_effect_${effectIdSeed}`,
    type,
    movesRemaining: duration,
    maxMoves: duration,
    triggerId,
    filterConfig: {
      ...defaultConfig,
      ...config,
    },
  };
}
