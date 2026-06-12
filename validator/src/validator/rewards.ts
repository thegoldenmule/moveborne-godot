/**
 * Reward table: (mode, final validated state) -> currency deltas.
 *
 * Pure and trivially retunable. Amounts derive from the validator's OWN
 * current_state — every point in it was earned through validated actions, so
 * the client choosing *when* to complete cannot inflate the grant.
 *
 *   story    -> handled by the story module (catalog-driven per-star rewards,
 *               see story/progress.ts); a story match WITHOUT a level_id
 *               grants nothing (decision 2026-06-12: catalog rewards fully
 *               replaced the old floor(score/10) placeholder)
 *   pvp      -> souls: 1 per completed match
 *   infinite -> nothing (always offline; never reaches the validator anyway)
 *   gems     -> never table-awarded (catalog star tiers / IAP / manual grants)
 */

import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";
import type { CurrencyDeltas, MatchMode } from "./types";

const PVP_SOULS_PER_MATCH = 1;

export function computeMatchRewards(
  mode: MatchMode,
  _finalState: SynchronizedGameState,
): CurrencyDeltas {
  const deltas: CurrencyDeltas = {};

  switch (mode) {
    case "story":
      // Catalog-driven (story module); nothing from the flat table.
      break;
    case "pvp": {
      deltas.souls = String(PVP_SOULS_PER_MATCH);
      break;
    }
    case "infinite":
      break;
  }

  return deltas;
}
