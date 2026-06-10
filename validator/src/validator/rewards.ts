/**
 * Reward table: (mode, final validated state) -> currency deltas.
 *
 * Pure and trivially retunable. Amounts derive from the validator's OWN
 * current_state — every point in it was earned through validated actions, so
 * the client choosing *when* to complete cannot inflate the grant.
 *
 * v1 placeholder economy (pending game-design tuning — see the feature brief):
 *   story    -> coins: floor(score / 10)
 *   pvp      -> souls: 1 per completed match
 *   infinite -> nothing (always offline; never reaches the validator anyway)
 *   gems     -> never validator-awarded (reserved for IAP / manual grants)
 */

import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";
import type { CurrencyDeltas, MatchMode } from "./types";

const STORY_COINS_SCORE_DIVISOR = 10;
const PVP_SOULS_PER_MATCH = 1;

export function computeMatchRewards(
  mode: MatchMode,
  finalState: SynchronizedGameState,
): CurrencyDeltas {
  const deltas: CurrencyDeltas = {};

  switch (mode) {
    case "story": {
      const coins = Math.floor(Math.max(0, finalState.score) / STORY_COINS_SCORE_DIVISOR);
      if (coins > 0) {
        deltas.coins = String(coins);
      }
      break;
    }
    case "pvp": {
      deltas.souls = String(PVP_SOULS_PER_MATCH);
      break;
    }
    case "infinite":
      break;
  }

  return deltas;
}
