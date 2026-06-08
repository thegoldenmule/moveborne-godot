import {
  MAX_HAND_SIZE,
  POWER_CARDS,
  RNG_NAMESPACES,
  SHARDS_PER_CARD,
} from "./constants";
import type { PowerCardInstance, SynchronizedGameState } from "./types";
import type { IRandomGenerator } from "./random";

/**
 * Result of a card draw operation
 */
interface DrawCardResult {
  success: boolean;
  shards: number;
  deckNextCardIndex: number;
  deckRemainingCards: number;
  error?: string;
}

/**
 * Perform a card draw operation
 * Shared logic used by both client (optimistic update) and server
 * Returns the state mutations needed - caller is responsible for adding the actual card
 *
 * @param gameState - Current game state
 * @returns Result object with state changes to apply
 */
export function performDrawCard(
  gameState: SynchronizedGameState,
): DrawCardResult {
  // Validate we have enough shards
  if (gameState.shards < SHARDS_PER_CARD) {
    return {
      success: false,
      shards: gameState.shards,
      deckNextCardIndex: gameState.deck.nextCardIndex,
      deckRemainingCards: gameState.deck.remainingCards,
      error: `Not enough shards (have ${gameState.shards}, need ${SHARDS_PER_CARD})`,
    };
  }

  // Validate hand has space
  if (gameState.hand.cards.length >= MAX_HAND_SIZE) {
    return {
      success: false,
      shards: gameState.shards,
      deckNextCardIndex: gameState.deck.nextCardIndex,
      deckRemainingCards: gameState.deck.remainingCards,
      error: "Hand is full",
    };
  }

  // Validate deck has cards
  if (gameState.deck.remainingCards <= 0) {
    return {
      success: false,
      shards: gameState.shards,
      deckNextCardIndex: gameState.deck.nextCardIndex,
      deckRemainingCards: gameState.deck.remainingCards,
      error: "No more cards in deck",
    };
  }

  // Success - return state mutations
  return {
    success: true,
    shards: 0, // Reset shards after drawing
    deckNextCardIndex: gameState.deck.nextCardIndex + 1,
    deckRemainingCards: gameState.deck.remainingCards - 1,
  };
}

/**
 * Check if player can draw a card
 * @param gameState - Current game state
 * @returns True if player has enough shards and hand has space
 */
export function canDrawCard(gameState: SynchronizedGameState): boolean {
  return (
    gameState.shards >= SHARDS_PER_CARD &&
    gameState.hand.cards.length < MAX_HAND_SIZE &&
    gameState.deck.remainingCards > 0
  );
}

/**
 * Draw a card from the deck using deterministic RNG
 * This ensures both client and server draw the same card
 *
 * @param rng - Random number generator
 * @param drawIndex - The index of this draw (used for card ID)
 * @returns The drawn card
 */
export function drawCardFromDeck(
  rng: IRandomGenerator,
  drawIndex: number,
): PowerCardInstance {
  // Get all available power cards as an array
  const availableCards = Object.values(POWER_CARDS);

  // Use RNG to select a random card from available power cards
  const randomValue = rng.getRandom(RNG_NAMESPACES.CARD_DRAW);
  const cardIndex = Math.floor(randomValue * availableCards.length);
  const selectedCard = availableCards[cardIndex];

  // Create card instance with deterministic ID
  return {
    ...selectedCard,
    id: `card_draw_${drawIndex}`,
  };
}
