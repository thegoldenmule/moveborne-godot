import { SHARDS_PER_CARD } from "./constants";

/**
 * Calculate new shard count after adding shards
 * Caps at SHARDS_PER_CARD to match server behavior when hand is full
 *
 * @param currentShards - Current shard count
 * @param shardsToAdd - Number of shards being added
 * @returns New shard count (capped at SHARDS_PER_CARD)
 */
export function calculateShards(
  currentShards: number,
  shardsToAdd: number,
): number {
  return Math.min(currentShards + shardsToAdd, SHARDS_PER_CARD);
}
