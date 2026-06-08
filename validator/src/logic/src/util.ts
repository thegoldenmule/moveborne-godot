import { computeStateHash } from "./hashing";
import type { SynchronizedGameState } from "./types";

export function hashGameState(state: SynchronizedGameState): string {
  return computeStateHash(state);
}
