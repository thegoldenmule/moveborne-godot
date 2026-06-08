/**
 * Game Logic Module for Tile Tacticians
 * Re-exports all game logic functions from separate modules
 */

// Board utilities
export { indexToRowCol } from "./board";

// Merge and swipe logic
export {
  addRandomValue as addRandomTile,
  addRandomTileWithEffects,
  calculateComboScore,
  performSwipe,
  updateComboMultiplier,
} from "./merge";

// Power card functions
export {
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
  performPowerCardVortex,
} from "./powerCards";

// Validation functions
export {
  hasValidBombTiles,
  hasValidClearColumns,
  hasValidCloneTiles,
  hasValidDestroyTiles,
  hasValidDoubleTiles,
  hasValidLightningTiles,
  hasValidMultiplyTiles,
  hasValidRadiateTiles,
  hasValidShuffleTiles,
  hasValidSplitTiles,
  hasValidSwapTiles,
  hasValidTeleportTiles,
  hasValidVortexTiles,
  isValidBombPosition,
  isValidClearColumn,
  isValidCloneSourcePosition,
  isValidCloneTargetPosition,
  isValidDestroyPosition,
  isValidDoublePosition,
  isValidLightningColumn,
  isValidMultiplyPosition,
  isValidRadiatePosition,
  isValidSplitPosition,
  isValidSwapPosition,
  isValidTeleportSourcePosition,
  isValidTeleportTargetPosition,
  isValidVortexPosition,
} from "./validation";

// Shard calculation
export { calculateShards } from "./shards";

// Card draw functions
export { canDrawCard, drawCardFromDeck, performDrawCard } from "./cardDraw";
