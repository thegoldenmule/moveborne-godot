type RNGNamespace = "tile-gen" | "shuffle" | "effect-spawn" | "totem-spawn" | "card-draw";
interface IRandomGenerator {
    getRandom(namespace: RNGNamespace): number;
    getIndices(): Record<RNGNamespace, number>;
    getSeeds(): Record<RNGNamespace, number>;
    getState(namespace: RNGNamespace): string;
    getAllStates(): Record<RNGNamespace, string>;
    clone(): IRandomGenerator;
}
declare const PassThroughRandomGenerator: IRandomGenerator;
declare class RandomGenerator implements IRandomGenerator {
    private rngInstances;
    private rngIndices;
    private seeds;
    constructor(seeds: Record<RNGNamespace, number>, indices: Record<RNGNamespace, number>);
    getRandom(namespace: RNGNamespace): number;
    getIndices(): Record<RNGNamespace, number>;
    getSeeds(): Record<RNGNamespace, number>;
    getState(namespace: RNGNamespace): string;
    getAllStates(): Record<RNGNamespace, string>;
    clone(): IRandomGenerator;
}
declare function initRandomSeeds(seeds: Record<RNGNamespace, number>, indices: Record<RNGNamespace, number>): void;
declare function getRNGIndices(): Record<RNGNamespace, number>;

type TileStatus = "normal" | "new" | "merged" | "magnetized" | "spawned" | "shuffled" | "lightning" | "rotated" | "radiated" | "cloned" | "swapped" | "teleported" | "split" | "multiplied" | "bombed" | "destroyed" | "purged" | "amplified";
type TileEffectType = "none" | "freeze" | "black_hole" | "amplify" | "amplify_static" | "lock" | "decay" | "stone";
interface TileEffectVisualConfig {
    backgroundTexture?: string;
    backgroundWidth?: number;
    backgroundHeight?: number;
    overlayTexture?: string;
    overlayWidth?: number;
    overlayHeight?: number;
    spawnEmitter?: string;
    activeEmitter?: string;
    removalEmitter?: string;
    showMultiplier?: boolean;
}
interface TileEffectMergeConfig {
    valueMultiplier: number;
    consumedOnMerge: boolean;
    consumptionEmitter?: string;
    effectStaysAtSource: boolean;
}
type SpawnCurveType = "constant" | "linear" | "exponential" | "stepped";
interface SpawnCurve {
    type: SpawnCurveType;
    baseChance: number;
    maxChance?: number;
    minChance?: number;
    params?: {
        linearRate?: number;
        exponentialFactor?: number;
        steps?: Array<{
            moveIndex: number;
            chance: number;
        }>;
    };
}
interface TileEffectSpawnConfig {
    spawnCurve: SpawnCurve;
    canSpawnOn: TileStatus[];
    canSpawnOnEmpty: boolean;
    maxActiveOnBoard: number;
}
interface TileEffectConfig {
    remainingTriggers: number;
    decayRate: number;
    tilesConsumed: number;
    maxTilesToImplosion: number;
    decayMoveInterval: number;
    lastDecayMove: number;
    multiplier: number;
    removalCost: number;
    allowsValueMerge: boolean;
    allowsValueMovement: boolean;
    effectRemovedByAdjacentMerge: boolean;
    visual?: TileEffectVisualConfig;
    mergeConfig: TileEffectMergeConfig;
    [key: string]: unknown;
}
interface TileEffect {
    type: TileEffectType;
    active: boolean;
    config: TileEffectConfig;
}
interface SynchronizedTileState {
    isEmpty: boolean;
    value: number;
    status: TileStatus;
    row: number;
    col: number;
    effect?: TileEffect;
    meta?: {
        [key: string]: unknown;
    };
}
interface BoardPosition {
    row: number;
    col: number;
}
interface PartialBoardPosition {
    row?: number;
    col?: number;
}
interface DestroyedTile {
    position: BoardPosition;
    value: number;
    destroyedBy: {
        type: "black_hole";
        position: BoardPosition;
    };
}
interface SynchronizedBoardState {
    tiles: SynchronizedTileState[];
    size: number;
}
interface InitialTileConfig {
    value: number;
    effect?: {
        type: Exclude<TileEffectType, "none">;
        config?: Partial<TileEffectConfig>;
    };
}
interface InitialBoardConfig {
    tiles?: Array<{
        position: BoardPosition;
        config: InitialTileConfig;
    }>;
    randomTiles?: {
        count: number;
        values: number[];
        avoidPositions?: BoardPosition[];
    };
}
type SpawnPositionStrategy = "random" | "empty" | "highest_value";
type EventTrigger = {
    event: "COMBO_BREAK";
    minCombo: number;
} | {
    event: "SCORE_MILESTONE";
    threshold: number;
} | {
    event: "MERGE_COUNT";
    count: number;
} | {
    event: "MOVE_COUNT";
    moves: number;
};
interface AuthoritativeSpawnConfig {
    effects: Array<{
        type: Exclude<TileEffectType, "none">;
        position: BoardPosition;
        config?: Partial<TileEffectConfig>;
    }>;
}
interface EventBasedSpawnRule {
    trigger: EventTrigger;
    effect: Exclude<TileEffectType, "none">;
    spawnCount: number;
    targetPositions?: SpawnPositionStrategy;
    icon?: string;
    globalEffect?: {
        type: "glitch";
        duration: number;
        config?: {
            slices?: number;
            offset?: number;
            direction?: number;
            fillMode?: number;
            seed?: number;
            average?: boolean;
            minSize?: number;
            sampleSize?: number;
        };
    };
}
interface EventTriggerState {
    id: string;
    trigger: EventTrigger;
    effect: Exclude<TileEffectType, "none">;
    spawnCount: number;
    targetPositions?: SpawnPositionStrategy;
    status: "idle" | "primed" | "triggered";
    icon?: string;
    progress?: {
        current: number;
        required: number;
    };
}
type PowerCardType = "bomb" | "swap" | "clear" | "double" | "time" | "magnet" | "shuffle" | "destroy" | "transform" | "lightning" | "radiate" | "clone" | "vortex" | "multiply" | "teleport" | "split" | "combo_guardian" | "energy_catalyst" | "power_surge" | "mega_boost" | "time_anchor" | "attraction_field" | "momentum_wave" | "void_portal" | "echo_chamber" | "scavenger_totem";
interface PowerCardColors {
    border?: number;
    background?: number;
    nameplate?: number;
    titleText?: number;
    titleTextDisabled?: number;
    descriptionText?: number;
    valueText?: number;
    valueTextDisabled?: number;
    backBorder?: number;
}
interface TotemTypeDefinition {
    id: TotemType;
    name: string;
    description: string;
    icon: {
        src: string;
    };
    maxTallyMarks?: number;
    defaultMoves?: number;
    defaultSwipes?: number;
    defaultMerges?: number;
    spawnValue?: number;
}
interface PowerCardDefinition {
    type: PowerCardType;
    value?: number;
    name: string;
    description: string;
    texture: string;
    colors?: PowerCardColors;
    cost?: number;
    rarity?: "common" | "rare" | "epic" | "legendary";
    spawnsTotem?: TotemTypeDefinition;
    isTotemCard?: boolean;
}
type PowerCardInstance = {
    id: string;
} & PowerCardDefinition;
interface SynchronizedHandState {
    cards: PowerCardInstance[];
}
interface SynchronizedDeckState {
    remainingCards: number;
    nextCardIndex: number;
}
type TotemType = "none" | "combo_saver" | "spawn_booster_2x" | "spawn_booster_4x" | "spawn_booster_8x" | "momentum_idol" | "magnet_core" | "void_gate" | "ghost_merge" | "scavenger" | "chrono_anchor";
interface TotemConfig {
    tallyMarks?: number;
    maxTallyMarks?: number;
    movesRemaining?: number;
    swipesRemaining?: number;
    mergesRemaining?: number;
    spawnValue?: number;
    [key: string]: unknown;
}
interface Totem {
    id: string;
    type: TotemType;
    config: TotemConfig;
    name: string;
    description: string;
    charges?: number;
    maxCharges?: number;
    position?: BoardPosition;
    active: boolean;
}
interface SynchronizedTotemsState {
    active: Totem[];
}
type GameStatus = "idle" | "playing" | "paused" | "gameover" | "victory";
interface ScenarioConfig {
    id: number;
    name: string;
    description: string;
    boardSize: number;
    startingCards: PowerCardType[];
    spawnConfigs?: Partial<Record<TileEffectType, TileEffectSpawnConfig>>;
    maxActiveOverrides?: Partial<Record<TileEffectType, number>>;
    eventRules?: EventBasedSpawnRule[];
    initialBoard?: InitialBoardConfig;
    initialScore?: number;
    initialShards?: number;
}
type GlobalEffectState = {
    id: string;
    type: "glitch";
    movesRemaining: number;
    maxMoves: number;
    triggerId: string;
    filterConfig: {
        slices: number;
        offset: number;
        direction: number;
        fillMode: number;
        seed: number;
        average: boolean;
        minSize: number;
        sampleSize: number;
    };
};
interface SynchronizedGameState {
    board: SynchronizedBoardState;
    hand: SynchronizedHandState;
    deck: SynchronizedDeckState;
    score: number;
    shards: number;
    combo: number;
    comboMultiplier: number;
    totems: SynchronizedTotemsState;
    moveIndex: number;
    randomSeeds: Record<RNGNamespace, number>;
    rngIndices: Record<RNGNamespace, number>;
    level?: number;
    timeRemaining?: number;
    moves?: number;
    highScore?: number;
    moveCount?: number;
    scenarioConfig?: Partial<ScenarioConfig>;
    eventTriggerStates?: EventTriggerState[];
    globalEffects?: GlobalEffectState[];
    totalMerges?: number;
}
declare enum OperationType {
    READY = "READY",
    SWIPE = "SWIPE",
    PLAY_CARD = "PLAY_CARD",
    DRAW_CARD = "DRAW_CARD",
    SELECT_CARD = "SELECT_CARD",
    SELECT_TILE = "SELECT_TILE",
    SPAWN_TOTEM = "SPAWN_TOTEM",
    TRIGGER_TOTEM = "TRIGGER_TOTEM",
    REPLACE_TOTEM = "REPLACE_TOTEM",
    RESTORE_STATE = "RESTORE_STATE",
    REMOVE_BLACK_HOLE = "REMOVE_BLACK_HOLE"
}
interface OperationData {
    type: OperationType;
    direction?: string;
    cardIndex?: number;
    position?: {
        row: number;
        col: number;
    };
    [key: string]: unknown;
}
interface OptimisticUpdate {
    opId: string;
    moveIndex: number;
    operation: OperationData;
    stateBeforeOp: SynchronizedGameState;
    stateAfterOp: SynchronizedGameState;
    timestamp: number;
}
interface GameAction {
    type: OperationType;
    payload: unknown;
}
interface HandFactoryConfig {
    size?: number;
}
interface GameFactoryConfig {
    moveIndex?: number;
    boardSize?: number;
    handSize?: number;
    level?: number;
    score?: number;
    timeRemaining?: number;
    deckSize?: number;
    rngSeeds?: Record<RNGNamespace, number>;
    rngIndices?: Record<RNGNamespace, number>;
    startingCards?: PowerCardInstance[];
    tiles?: SynchronizedTileState[];
    scenarioConfig?: Partial<ScenarioConfig>;
}
type GameEventType = "PRE_SWIPE" | "SWIPE_COMPLETED" | "TILE_SPAWN" | "TILE_MERGE" | "TILE_MOVE" | "TILE_DESTROY" | "TILE_EFFECT_APPLIED" | "TILE_EFFECT_REMOVED" | "CARD_PLAYED" | "TOTEM_ACTIVATED" | "TOTEM_DESPAWNED" | "COMBO_BREAK" | "COMBO_BREAK_ATTEMPTED" | "COMBO_CONTINUE" | "COMBO_INCREMENT" | "GAME_START" | "GAME_END" | "TURN_END" | "SCORE_UPDATE" | "SELECTION_MADE" | "MOVE_COMPLETED" | "POST_SPAWN" | "FAILED_SWIPE" | "POST_SWIPE" | "CREATE_SNAPSHOT" | "TRIGGER_REWIND";
interface GameEvent {
    type: GameEventType;
    timestamp?: number;
    position?: BoardPosition;
    spawnedPosition?: number;
    value?: number;
    spawnedValue?: number;
    previousCombo?: number;
    incrementAmount?: number;
    tileValue?: number;
    mergeOccurred?: boolean;
    tilesSpawned?: number;
    direction?: string;
    shardsMultiplier?: number;
    mergedTilesCount?: number;
    effectApplied?: {
        type: TileEffectType;
        position: BoardPosition;
        config?: TileEffectConfig;
    };
    effectRemoved?: {
        type: TileEffectType;
        position: BoardPosition;
    };
}

declare const MIN_BOARD_SIZE = 4;
declare const MAX_BOARD_SIZE = 8;
declare const DEFAULT_BOARD_SIZE = 4;
declare const SHARDS_PER_CARD = 8;
declare const MAX_HAND_SIZE = 3;
declare const DECK_SIZE = 12;
declare const DEFAULT_TILE_SIZE = 70;
declare const RNG_NAMESPACES: {
    TILE_GEN: "tile-gen";
    SHUFFLE: "shuffle";
    EFFECT_SPAWN: "effect-spawn";
    TOTEM_SPAWN: "totem-spawn";
    CARD_DRAW: "card-draw";
};
declare const TOTEM_TYPES: Record<TotemType, TotemTypeDefinition>;
declare const POWER_CARDS: Record<PowerCardType, PowerCardDefinition>;
declare const MAX_ACTIVE_TOTEMS = 3;

declare function canonicalStringify(obj: unknown): string;
declare function computeStateHash(state: SynchronizedGameState): string;
declare function computeActionHash(action: GameAction): string;
declare function computeStateHashAsync(state: SynchronizedGameState): Promise<string>;
declare function computeActionHashAsync(action: GameAction): Promise<string>;

/**
 * Board utility functions for tile position management
 */
declare function indexToRowCol(index: number, boardSize: number): {
    row: number;
    col: number;
};
declare function rowColToIndex(row: number, col: number, boardSize: number): number;
declare function isValidPosition(row: number, col: number, boardSize: number): boolean;
declare function getTile(tiles: SynchronizedTileState[], row: number, col: number, boardSize: number): SynchronizedTileState;
declare function setTile(tiles: SynchronizedTileState[], tile: SynchronizedTileState, boardSize: number): void;

/**
 * Build initial board state from configuration
 * Handles explicit tile placements and random tile generation
 */
declare function buildInitialBoard(config: InitialBoardConfig, boardSize: number, randomGen: IRandomGenerator): SynchronizedTileState[];
/**
 * Set a tile at a specific position with given configuration
 */
declare function setTileAt(tiles: SynchronizedTileState[], boardSize: number, position: BoardPosition, config: InitialTileConfig): void;
/**
 * Validate board configuration for correctness
 */
declare function validateBoardConfig(config: InitialBoardConfig, boardSize: number): void;

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
declare function performDrawCard(gameState: SynchronizedGameState): DrawCardResult;
/**
 * Check if player can draw a card
 * @param gameState - Current game state
 * @returns True if player has enough shards and hand has space
 */
declare function canDrawCard(gameState: SynchronizedGameState): boolean;
/**
 * Draw a card from the deck using deterministic RNG
 * This ensures both client and server draw the same card
 *
 * @param rng - Random number generator
 * @param drawIndex - The index of this draw (used for card ID)
 * @returns The drawn card
 */
declare function drawCardFromDeck(rng: IRandomGenerator, drawIndex: number): PowerCardInstance;

/**
 * Process event-based spawn rules and spawn effects if triggers match
 * @param gameState Current game state
 * @param event Game event that occurred
 * @param rules Array of event-based spawn rules to check
 * @param randomGenerator Random number generator
 * @param excludedPositions Positions to exclude from spawning (e.g., where effects were just removed)
 * @returns Updated game state with any spawned effects
 */
declare function processEventSpawnRules(gameState: SynchronizedGameState, event: GameEvent, rules: EventBasedSpawnRule[], randomGenerator: IRandomGenerator, excludedPositions?: BoardPosition[]): SynchronizedGameState;

/**
 * Event Trigger State Management
 *
 * Manages synchronized state for event-based spawn triggers to enable visual indicators.
 * Tracks trigger status (idle/primed/triggered) and progress for UI display.
 */

/**
 * Initialize event trigger states from scenario event rules
 * @param eventRules Array of event-based spawn rules from scenario config
 * @param gameState Current game state (for initial progress calculation)
 * @returns Array of EventTriggerState objects, or undefined if no rules
 */
declare function initializeEventTriggerStates(eventRules: EventBasedSpawnRule[], gameState: SynchronizedGameState): EventTriggerState[] | undefined;
/**
 * Update all trigger states based on current game state
 * Sets status to 'primed' if conditions are met, 'idle' if not
 * @param gameState Current game state
 * @returns Updated game state (mutates in place)
 */
declare function updateTriggerStates(gameState: SynchronizedGameState): SynchronizedGameState;
/**
 * Mark specific triggers as 'triggered' after they fire
 * @param gameState Current game state
 * @param matchingRuleIndices Array of rule indices that just fired
 * @returns Updated game state (mutates in place)
 */
declare function markTriggersActivated(gameState: SynchronizedGameState, matchingRuleIndices: number[]): SynchronizedGameState;
/**
 * Reset 'triggered' states back to 'idle' or 'primed' based on current conditions
 * Should be called after visual feedback completes (typically next frame)
 * @param gameState Current game state
 * @returns Updated game state (mutates in place)
 */
declare function resetTriggeredStates(gameState: SynchronizedGameState): SynchronizedGameState;
/**
 * Get combo progress for COMBO_BREAK triggers
 * @param gameState Current game state
 * @param minCombo Minimum combo required
 * @returns Progress with current combo and required combo
 */
declare function getComboProgress(gameState: SynchronizedGameState, minCombo: number): {
    current: number;
    required: number;
};
/**
 * Get score progress for SCORE_MILESTONE triggers
 * @param gameState Current game state
 * @param threshold Score threshold required
 * @returns Progress with current score and required score
 */
declare function getScoreProgress(gameState: SynchronizedGameState, threshold: number): {
    current: number;
    required: number;
};
/**
 * Get merge count progress for MERGE_COUNT triggers
 * Note: Requires totalMerges field in game state (future enhancement)
 * @param gameState Current game state
 * @param count Number of merges required
 * @returns Progress with current merge count and required count
 */
declare function getMergeCountProgress(gameState: SynchronizedGameState, count: number): {
    current: number;
    required: number;
};
/**
 * Get move progress for MOVE_COUNT triggers
 * @param gameState Current game state
 * @param moves Number of moves required
 * @returns Progress with current moves and required moves
 */
declare function getMoveProgress(gameState: SynchronizedGameState, moves: number): {
    current: number;
    required: number;
};
/**
 * Check if trigger condition is currently met
 * @param gameState Current game state
 * @param trigger Event trigger definition
 * @returns True if condition is met, false otherwise
 */
declare function isTriggerConditionMet(gameState: SynchronizedGameState, trigger: EventTrigger): boolean;

/**
 * Create an empty synchronized tile state object
 * @param row Row position (optional)
 * @param col Column position (optional)
 * @returns Empty synchronized tile state
 */
declare const createEmptyTile: (row?: number, col?: number) => SynchronizedTileState;
/**
 * Create a tile effect instance
 * @param type Type of tile effect
 * @param config Optional configuration for the effect
 * @returns TileEffect instance
 */
declare const createTileEffect: (type: TileEffectType, config?: Partial<TileEffectConfig>) => TileEffect;
/**
 * Create a tile effect of type FREEZE
 * @returns TileEffect instance
 */
declare const createFreezeEffect: () => TileEffect;
/**
 * Create a tile effect of type BLACK_HOLE
 * @param removalCost Optional custom removal cost in shards (default: 7)
 * @returns TileEffect instance
 */
declare const createBlackHoleEffect: (removalCost?: number) => TileEffect;
/**
 * Create a tile effect of type AMPLIFY
 * @returns TileEffect instance
 */
declare const createAmplifyEffect: () => TileEffect;
/**
 * Create a tile effect of type STONE
 * @returns TileEffect instance
 */
declare const createStoneEffect: () => TileEffect;

/**
 * Get effective spawn configuration for an effect type
 * @param effectType Type of effect
 * @param gameState Current game state
 * @returns Spawn configuration (returns disabled config if not defined in scenario)
 */
declare function getSpawnConfig(effectType: Exclude<TileEffectType, "none">, gameState: SynchronizedGameState): TileEffectSpawnConfig;
/**
 * Check if an effect should spawn based on configuration
 * @param effectType Type of effect to spawn
 * @param gameState Current game state
 * @param currentActiveCount Current count of this effect type on board
 * @param randomGenerator Random number generator
 * @returns Whether effect should spawn
 */
declare function shouldSpawnEffect(effectType: Exclude<TileEffectType, "none">, gameState: SynchronizedGameState, currentActiveCount: number, randomGenerator: IRandomGenerator): boolean;
/**
 * Check if a tile can have an effect applied to it
 * @param tile Tile to check
 * @param effectType Type of effect to apply
 * @param gameState Current game state
 * @returns Whether effect can be applied
 */
declare function canApplyEffectToTile(tile: SynchronizedTileState, effectType: Exclude<TileEffectType, "none">, gameState: SynchronizedGameState): boolean;
/**
 * Count active effects of a specific type on the board
 * @param gameState Current game state
 * @param effectType Type of effect to count
 * @returns Number of active effects of this type
 */
declare function countActiveEffects(gameState: SynchronizedGameState, effectType: TileEffectType): number;
/**
 * Get tiles adjacent to a position (orthogonal only)
 * @param gameState Current game state
 * @param position Position to check around
 * @returns Array of adjacent tiles
 */
declare function getAdjacentTiles(gameState: SynchronizedGameState, position: BoardPosition): SynchronizedTileState[];
/**
 * Check if a tile has a specific effect
 * @param tile Tile to check
 * @param effectType Type of effect to check for
 * @returns Whether tile has the effect
 */
declare function tileHasEffect(tile: SynchronizedTileState, effectType: TileEffectType): boolean;
/**
 * Apply effect to a tile
 * @param tile Tile to apply effect to
 * @param effect Effect to apply
 */
declare function applyEffectToTile(tile: SynchronizedTileState, effect: TileEffect): void;
/**
 * Check if a value can merge (based on effect config)
 * @param tile Tile to check
 * @returns Whether value can merge
 */
declare function canValueMerge(tile: SynchronizedTileState): boolean;
/**
 * Process effect removal when a merge happens adjacent to tiles (based on effectRemovedByAdjacentMerge config)
 * @param gameState Current game state
 * @param mergedPosition Position where merge occurred
 * @returns Array of positions where effects were removed
 */
declare function processFreezeRemovalFromAdjacentMerge(gameState: SynchronizedGameState, mergedPosition: BoardPosition): BoardPosition[];
/**
 * Check if two tiles can merge together (considering freeze/stone effects)
 * @param tile1 First tile
 * @param tile2 Second tile
 * @returns Whether tiles can merge
 */
declare function canTilesMergeTogether(tile1: SynchronizedTileState, tile2: SynchronizedTileState): boolean;
/**
 * Process lock effect trigger decrement when a merge happens on a locked tile
 * @param tile Tile that was involved in the merge
 * @returns Position if lock was removed, null otherwise
 */
declare function processLockTriggerOnMerge(tile: SynchronizedTileState): BoardPosition | null;
/**
 * Check if a tile is a black hole
 * @param tile Tile to check
 * @returns Whether tile is a black hole
 */
declare function isBlackHoleTile(tile: SynchronizedTileState): boolean;
/**
 * Check if a value can move during swipes (based on effect config)
 * @param tile Tile to check
 * @returns Whether value can move
 */
declare function canValueMove(tile: SynchronizedTileState): boolean;
/**
 * Check if there's a black hole in the path between two positions
 * @param tiles Array of tiles representing the board
 * @param boardSize Size of the board (e.g., 4 for 4x4)
 * @param from Starting position
 * @param to Ending position
 * @returns Position of black hole if found, null otherwise
 */
declare function findBlackHoleInPath(tiles: SynchronizedTileState[], boardSize: number, from: BoardPosition, to: BoardPosition): BoardPosition | null;
/**
 * Process tile destruction by black hole
 * @param consumedTile Tile being consumed
 * @param blackHoleTile The black hole tile consuming it
 * @returns Object with scoreLoss and shouldImplode
 */
declare function processBlackHoleDestruction(consumedTile: SynchronizedTileState, blackHoleTile: SynchronizedTileState): {
    scoreLoss: number;
    shouldImplode: boolean;
};
/**
 * Attempt to remove black hole effect by spending shards
 * @param gameState Current game state
 * @param position Position of black hole to remove
 * @returns Updated game state, or null if removal failed
 */
declare function removeBlackHoleWithShards(gameState: SynchronizedGameState, position: BoardPosition): SynchronizedGameState | null;
/**
 * Check if tile has amplify effect
 * @param tile Tile to check
 * @returns True if tile has active amplify effect
 */
declare function isAmplifyTile(tile: SynchronizedTileState | undefined): boolean;
/**
 * Get amplier multiplier value from effect config
 * @param tile Tile with amplify effect
 * @returns Multiplier value (default: 2)
 */
declare function getAmplifyMultiplier(tile: SynchronizedTileState): number;
/**
 * Process amplify effect - apply multiplier and remove effect
 * @param tile Tile with amplify effect
 * @param mergeValue The value to multiply
 * @returns Object with multiplied value, whether effect was consumed, and multiplier
 * @deprecated Use processTileEffectsOnMerge instead for generic effect handling
 */
declare function processAmplifyEffect(tile: SynchronizedTileState, mergeValue: number): {
    value: number;
    consumed: boolean;
    multiplier: number;
};
/**
 * Metadata about a consumed tile effect
 */
interface TileEffectConsumption {
    type: TileEffectType;
    row: number;
    col: number;
    metadata: {
        multiplier?: number;
        emitter?: string;
    };
}
/**
 * Result of processing tile effects during a merge
 */
interface TileEffectMergeResult {
    finalValue: number;
    consumedEffects: TileEffectConsumption[];
}
/**
 * Generic function to process all tile effects during a merge
 * Reads effect configuration to determine merge behavior
 * @param tile Target tile where merge is happening
 * @param baseValue Base merge value before effect modifiers
 * @returns Final value after effects applied and list of consumed effects
 */
declare function processTileEffectsOnMerge(tile: SynchronizedTileState, baseValue: number): TileEffectMergeResult;
/**
 * Check if a tile's effect should be preserved at the source position during a merge
 * @param tile Source tile in merge operation
 * @returns The effect to preserve at source, or undefined if no preservation needed
 */
declare function getEffectToPreserveAtSource(tile: SynchronizedTileState): TileEffect | undefined;

interface PerformSwipeResult {
    gameState: SynchronizedGameState;
    moved: boolean;
    score: number;
    mergedTilesCount: number;
    removedEffectPositions: BoardPosition[];
    destroyedTiles: DestroyedTile[];
    effectConsumptions: TileEffectConsumption[];
}
/**
 * Perform a swipe in the given direction
 * @param {Object} gameState - Full game state object with tiles, totems, etc.
 * @param {string} direction - Direction to swipe: "left", "right", "up", "down"
 * @returns {Object} Result object with { gameState, moved, score, mergedTilesCount }
 */
declare function performSwipe(gameState: SynchronizedGameState, direction: string, randomGenerator: IRandomGenerator): PerformSwipeResult;
interface AddRandomTileResult {
    gameState: SynchronizedGameState;
    effectSpawned?: {
        type: TileEffectType;
        position: BoardPosition;
    };
}
/**
 * Add a random tile to the board with totem effects
 * @param {Object} gameState - Full game state object with tiles, totems, etc.
 * @param {RandomGenerator} randomGenerator - Random number generator instance
 * @returns {Object} Modified game state with new tile added (if possible) and spawn info
 */
declare function addRandomTileWithEffects(gameState: SynchronizedGameState, randomGenerator: IRandomGenerator): AddRandomTileResult;
/**
 * Add a random value to the board
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {RandomGenerator} randomGenerator - Random number generator instance
 * @param {number} _boardSize - Size of the board (for API consistency, currently unused)
 * @returns {boolean} True if a tile was added, false if the board is full
 */
declare function addRandomValue(tiles: SynchronizedTileState[], randomGenerator: IRandomGenerator, _boardSize: number): boolean;
/**
 * Update combo multiplier based on merge activity with totem integration
 * @param {Object} gameState - Full game state object
 * @param {number} mergedTilesCount - Number of tiles merged in this move
 * @returns {Object} Updated game state with new combo multiplier
 */
declare function updateComboMultiplier(gameState: SynchronizedGameState, mergedTilesCount: number, randomGenerator: IRandomGenerator): SynchronizedGameState;
/**
 * Calculate total score with combo multiplier applied
 * @param {number} baseScore - Base score from the move
 * @param {number} comboMultiplier - Current combo multiplier
 * @returns {number} Total score with combo applied
 */
declare function calculateComboScore(baseScore: number, comboMultiplier: number): number;

/**
 * Perform a power card split operation on a tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tilePos - Tile position {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardSplit(tiles: SynchronizedTileState[], tilePos: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card multiply operation on a tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tilePos - Position object with row and col properties
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardMultiply(tiles: SynchronizedTileState[], tilePos: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card shuffle operation on the entire board
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardShuffle(tiles: SynchronizedTileState[], randomGenerator: IRandomGenerator, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
};
/**
 * Perform a power card lightning operation on a column
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} column - Column index to double (0-3)
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardLightning(tiles: SynchronizedTileState[], column: number | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card radiate operation on a tile
 * Doubles all tiles adjacent to the selected tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tilePos - Position object with row and col properties
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardRadiate(tiles: SynchronizedTileState[], tilePos: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card clone operation on a tile
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} sourceTilePos - Position of the tile to clone {row, col}
 * @param {Object} targetTilePos - Position where to place the clone {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardClone(tiles: SynchronizedTileState[], sourceTilePos: SynchronizedTileState | undefined, targetTilePos: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card swap operation on two tiles
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} tile1 - First tile position {row, col}
 * @param {Object} tile2 - Second tile position {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardSwap(tiles: SynchronizedTileState[], tile1: SynchronizedTileState | undefined, tile2: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card vortex operation on a 2x2 quadrant
 * Rotates the selected 2x2 quadrant clockwise
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} quadrantPos - Position object with row and col properties for top-left corner
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardVortex(tiles: SynchronizedTileState[], quadrantPos: {
    row?: number;
    col?: number;
}, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a power card teleport operation on a tile
 * Move a tile from source position to target empty position
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} sourceTilePos - Position of the tile to teleport {row, col}
 * @param {Object} targetTilePos - Position where to teleport the tile {row, col}
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardTeleport(tiles: SynchronizedTileState[], sourceTilePos: SynchronizedTileState | undefined, targetTilePos: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error: string;
} | {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
    error?: undefined;
};
/**
 * Perform a bomb operation on a tile
 * Removes all effects from the tile and negates score by tile value
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {Object} targetTile - Target tile to bomb
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardBomb(tiles: SynchronizedTileState[], targetTile: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
};
/**
 * Destroy power card - destroys a tile without effects and negates score
 * @param {SynchronizedTileState[]} tiles - Current board state
 * @param {SynchronizedTileState} targetTile - Tile to destroy
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardDestroy(tiles: SynchronizedTileState[], targetTile: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
};
/**
 * Clear (Purge Column) power card - clears tiles without effects in a column with no score change
 * @param {SynchronizedTileState[]} tiles - Current board state
 * @param {number} column - Column index (0-3) to clear
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardClear(tiles: SynchronizedTileState[], column: number | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
};
/**
 * Double (Amplify) power card - doubles a tile's value if it has no effects
 * @param {SynchronizedTileState[]} tiles - Current board state
 * @param {SynchronizedTileState} targetTile - Tile to amplify
 * @returns {Object} Result object with { tiles, success, score }
 */
declare function performPowerCardDouble(tiles: SynchronizedTileState[], targetTile: SynchronizedTileState | undefined, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
};
declare function performPowerCardTransform(tiles: SynchronizedTileState[], numEffects: number, randomGenerator: IRandomGenerator, boardSize: number): {
    tiles: SynchronizedTileState[];
    success: boolean;
    score: number;
};

/**
 * Validation functions for power cards and game rules
 */
/**
 * Check if there are any tiles that can be split
 * Used to determine if the split power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be split
 */
declare function hasValidSplitTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are any tiles that can be multiplied
 * Used to determine if the multiply power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be multiplied
 */
declare function hasValidMultiplyTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are any tiles on the board
 * Used to determine if the shuffle power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be shuffled
 */
declare function hasValidShuffleTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are any tiles that can be affected by lightning
 * Used to determine if the lightning power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be doubled
 */
declare function hasValidLightningTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are any tiles that can be radiated
 * Used to determine if the radiate power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can radiate adjacent tiles
 */
declare function hasValidRadiateTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are any tiles that can be cloned
 * Used to determine if the clone power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles that can be cloned
 */
declare function hasValidCloneTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are any tiles that can be swapped
 * Used to determine if the swap power card should be enabled
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are at least two positions that can be swapped
 */
declare function hasValidSwapTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are valid tiles for vortex operation
 * Vortex requires at least one non-empty tile in any 2x2 quadrant
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if vortex can be used, false otherwise
 */
declare function hasValidVortexTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if there are tiles that can be teleported
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are tiles to teleport and empty spaces to teleport to
 */
declare function hasValidTeleportTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Validation function for swap power card - only highlight populated tiles
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for swap
 */
declare function isValidSwapPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Validation function for vortex power card - only highlight valid top-left corners of 2x2 quadrants
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for vortex
 */
declare function isValidVortexPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Validation function for split power card - only highlight tiles that can be split
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for split
 */
declare function isValidSplitPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Validation function for multiply power card - only highlight tiles that have values
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for multiply
 */
declare function isValidMultiplyPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Validation function for radiate power card - only highlight tiles that have values
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for radiate
 */
declare function isValidRadiatePosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Validation function for clone power card - only highlight tiles that have values (for source selection)
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @returns {boolean} True if this position should be highlighted for clone source
 */
declare function isValidCloneSourcePosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Validation function for clone power card target selection - only highlight empty adjacent positions
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate
 * @param {number} col - Column to validate
 * @param {Object} sourcePos - Source position {row, col} for adjacency check
 * @returns {boolean} True if this position should be highlighted for clone target
 */
declare function isValidCloneTargetPosition(tiles: SynchronizedTileState[], row: number, col: number, sourcePos: SynchronizedTileState): boolean;
/**
 * Validation function for lightning power card - only highlight columns that have tiles
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row to validate (ignored for column selection)
 * @param {number} col - Column to validate
 * @returns {boolean} True if this column should be highlighted for lightning
 */
declare function isValidLightningColumn(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Check if a position is valid for teleport source selection
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position contains a tile with value
 */
declare function isValidTeleportSourcePosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Check if a position is valid for teleport target selection
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position is empty
 */
declare function isValidTeleportTargetPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Check if there are any valid tiles for bomb operation
 * A tile is valid if it has a value or an effect
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid tiles for bombing
 */
declare function hasValidBombTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if a position is valid for bomb operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position has a tile with value or effect
 */
declare function isValidBombPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Check if there are any valid tiles for destroy operation
 * A tile is valid if it has a value but NO active effect
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid tiles for destroying
 */
declare function hasValidDestroyTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if a position is valid for destroy operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position has a tile with value but no active effect
 */
declare function isValidDestroyPosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
/**
 * Check if there are any valid columns for clear operation
 * A column is valid if it has at least one non-empty tile WITHOUT active effects
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid columns for clearing
 */
declare function hasValidClearColumns(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if a column is valid for clear operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} col - Column index
 * @returns {boolean} True if column has at least one non-empty tile without active effects
 */
declare function isValidClearColumn(tiles: SynchronizedTileState[], col: number): boolean;
/**
 * Check if there are any valid tiles for double (amplify) operation
 * A tile is valid if it has a value but NO active effect
 * @param {Array} tiles - Array of tile objects representing the board
 * @returns {boolean} True if there are valid tiles for doubling
 */
declare function hasValidDoubleTiles(tiles: SynchronizedTileState[]): boolean;
/**
 * Check if a position is valid for double (amplify) operation
 * @param {Array} tiles - Array of tile objects representing the board
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @returns {boolean} True if position has a tile with value but no active effect
 */
declare function isValidDoublePosition(tiles: SynchronizedTileState[], row: number, col: number): boolean;
declare function hasValidTransformTiles(tiles: SynchronizedTileState[]): boolean;

/**
 * Calculate new shard count after adding shards
 * Caps at SHARDS_PER_CARD to match server behavior when hand is full
 *
 * @param currentShards - Current shard count
 * @param shardsToAdd - Number of shards being added
 * @returns New shard count (capped at SHARDS_PER_CARD)
 */
declare function calculateShards(currentShards: number, shardsToAdd: number): number;

declare function processGlobalEffects(gameState: SynchronizedGameState, gameEvent: GameEvent, randomGenerator: IRandomGenerator): SynchronizedGameState;
declare function createGlobalEffect(rule: EventBasedSpawnRule, triggerId: string, randomGenerator: IRandomGenerator): GlobalEffectState | null;

/**
 * Type of spawn mechanism to use
 */
type SpawnType = "random" | "authoritative" | "event" | "powercard";
/**
 * Action for power card spawning
 */
interface PowerCardSpawnAction {
    effectType: Exclude<TileEffectType, "none">;
    targetPosition: BoardPosition;
    sourceCardId: string;
    config?: Partial<TileEffectConfig>;
}
/**
 * Options for spawning tile effects
 */
interface SpawnEffectOptions {
    gameState: SynchronizedGameState;
    randomGenerator: IRandomGenerator;
    spawnType?: SpawnType;
    authoritativeEffects?: AuthoritativeSpawnConfig;
    eventRules?: EventBasedSpawnRule[];
    triggeredEvent?: {
        type: string;
        [key: string]: unknown;
    };
    powerCardSpawn?: PowerCardSpawnAction;
    targetTileIndex?: number;
}
/**
 * Information about a spawned effect
 */
interface SpawnedEffectInfo {
    type: Exclude<TileEffectType, "none">;
    position: BoardPosition;
    config: TileEffectConfig;
}
/**
 * Result of spawning effects
 */
interface SpawnEffectResult {
    gameState: SynchronizedGameState;
    effectsSpawned: SpawnedEffectInfo[];
    spawnedCount: number;
}
/**
 * Result of attempting to spawn an effect on a single tile
 */
interface AttemptSpawnResult {
    success: boolean;
    gameState: SynchronizedGameState;
    effectSpawned?: SpawnedEffectInfo;
}
/**
 * Find all valid positions on the board where effects can spawn
 * @param gameState Current game state
 * @param effectType Type of effect to spawn
 * @returns Array of valid tile indices
 */
declare function findValidSpawnPositions(gameState: SynchronizedGameState, effectType: Exclude<TileEffectType, "none">): number[];
/**
 * Select a spawn position based on strategy
 * @param gameState Current game state
 * @param validIndices Array of valid tile indices
 * @param strategy Selection strategy
 * @param randomGenerator Random number generator
 * @returns Selected tile index, or null if no valid position
 */
declare function selectSpawnPosition(gameState: SynchronizedGameState, validIndices: number[], strategy: SpawnPositionStrategy, randomGenerator: IRandomGenerator): number | null;
/**
 * Attempt to spawn an effect on a specific tile
 * @param gameState Current game state
 * @param tileIndex Index of tile to spawn effect on
 * @param randomGenerator Random number generator
 * @returns Result with success status and updated game state
 */
declare function attemptSpawnEffectOnTile(gameState: SynchronizedGameState, tileIndex: number, randomGenerator: IRandomGenerator): AttemptSpawnResult;
/**
 * Main orchestrator function for spawning tile effects
 * @param options Spawn options
 * @returns Result with updated game state and spawned effects
 */
declare function spawnTileEffects(options: SpawnEffectOptions): SpawnEffectResult;

/**
 * Process all active totem effects for a given game event
 * @param gameState - Current game state
 * @param gameEvent - Game event that triggered effect processing
 * @param randomGenerator - Random number generator instance
 * @returns Modified game state with totem effects applied
 */
declare const processTotemEffects: (gameState: SynchronizedGameState, gameEvent: GameEvent, randomGenerator: IRandomGenerator) => SynchronizedGameState;
/**
 * Initialize a totem with default configuration based on its type
 * @param totemType - The type of totem to initialize
 * @param customConfig - Optional custom configuration
 * @returns Initialized totem configuration
 */
declare const initializeTotemConfig: (totemType: TotemType, customConfig?: Partial<TotemConfig>) => TotemConfig;

declare function hashGameState(state: SynchronizedGameState): string;

interface SwipeActionResult {
    success: boolean;
    newState: SynchronizedGameState;
    scoreAdded: number;
    shardsAdded: number;
    moved: boolean;
    cardDrawn: boolean;
    drawnCard?: PowerCardInstance;
    error?: string;
}
interface CardActionResult {
    success: boolean;
    newState: SynchronizedGameState;
    scoreAdded: number;
    error?: string;
}
interface ActionExecutionResult {
    success: boolean;
    newState: SynchronizedGameState;
    scoreAdded?: number;
    shardsAdded?: number;
    cardDrawn?: boolean;
    error?: string;
}
declare function executeSwipeAction(state: SynchronizedGameState, direction: string, rng: IRandomGenerator): SwipeActionResult;
declare function executePlayCardAction(state: SynchronizedGameState, action: string, actionData: Record<string, unknown>, cardIndex: number, rng: IRandomGenerator): CardActionResult;
declare function executeSpawnTotemAction(state: SynchronizedGameState, totemType: TotemType, cardIndex: number): ActionExecutionResult;
declare function executeAction(state: SynchronizedGameState, action: GameAction, rng: IRandomGenerator): ActionExecutionResult;

export { type ActionExecutionResult, type AuthoritativeSpawnConfig, type BoardPosition, type CardActionResult, DECK_SIZE, DEFAULT_BOARD_SIZE, DEFAULT_TILE_SIZE, type DestroyedTile, type EventBasedSpawnRule, type EventTrigger, type EventTriggerState, type GameAction, type GameEvent, type GameEventType, type GameFactoryConfig, type GameStatus, type GlobalEffectState, type HandFactoryConfig, type IRandomGenerator, type InitialBoardConfig, type InitialTileConfig, MAX_ACTIVE_TOTEMS, MAX_BOARD_SIZE, MAX_HAND_SIZE, MIN_BOARD_SIZE, type OperationData, OperationType, type OptimisticUpdate, POWER_CARDS, type PartialBoardPosition, PassThroughRandomGenerator, type PowerCardColors, type PowerCardDefinition, type PowerCardInstance, type PowerCardSpawnAction, type PowerCardType, type RNGNamespace, RNG_NAMESPACES, RandomGenerator, SHARDS_PER_CARD, type ScenarioConfig, type SpawnCurve, type SpawnCurveType, type SpawnPositionStrategy, type SwipeActionResult, type SynchronizedBoardState, type SynchronizedDeckState, type SynchronizedGameState, type SynchronizedHandState, type SynchronizedTileState, type SynchronizedTotemsState, TOTEM_TYPES, type TileEffect, type TileEffectConfig, type TileEffectConsumption, type TileEffectMergeConfig, type TileEffectSpawnConfig, type TileEffectType, type TileEffectVisualConfig, type TileStatus, type Totem, type TotemConfig, type TotemType, type TotemTypeDefinition, addRandomValue as addRandomTile, addRandomTileWithEffects, addRandomValue, applyEffectToTile, attemptSpawnEffectOnTile, buildInitialBoard, calculateComboScore, calculateShards, canApplyEffectToTile, canDrawCard, canTilesMergeTogether, canValueMerge, canValueMove, canonicalStringify, computeActionHash, computeActionHashAsync, computeStateHash, computeStateHashAsync, countActiveEffects, createAmplifyEffect, createBlackHoleEffect, createEmptyTile, createFreezeEffect, createGlobalEffect, createStoneEffect, createTileEffect, drawCardFromDeck, executeAction, executePlayCardAction, executeSpawnTotemAction, executeSwipeAction, findBlackHoleInPath, findValidSpawnPositions, getAdjacentTiles, getAmplifyMultiplier, getComboProgress, getEffectToPreserveAtSource, getMergeCountProgress, getMoveProgress, getRNGIndices, getScoreProgress, getSpawnConfig, getTile, hasValidBombTiles, hasValidClearColumns, hasValidCloneTiles, hasValidDestroyTiles, hasValidDoubleTiles, hasValidLightningTiles, hasValidMultiplyTiles, hasValidRadiateTiles, hasValidShuffleTiles, hasValidSplitTiles, hasValidSwapTiles, hasValidTeleportTiles, hasValidTransformTiles, hasValidVortexTiles, hashGameState, indexToRowCol, initRandomSeeds, initializeEventTriggerStates, initializeTotemConfig, isAmplifyTile, isBlackHoleTile, isTriggerConditionMet, isValidBombPosition, isValidClearColumn, isValidCloneSourcePosition, isValidCloneTargetPosition, isValidDestroyPosition, isValidDoublePosition, isValidLightningColumn, isValidMultiplyPosition, isValidPosition, isValidRadiatePosition, isValidSplitPosition, isValidSwapPosition, isValidTeleportSourcePosition, isValidTeleportTargetPosition, isValidVortexPosition, markTriggersActivated, performDrawCard, performPowerCardBomb, performPowerCardClear, performPowerCardClone, performPowerCardDestroy, performPowerCardDouble, performPowerCardLightning, performPowerCardMultiply, performPowerCardRadiate, performPowerCardShuffle, performPowerCardSplit, performPowerCardSwap, performPowerCardTeleport, performPowerCardTransform, performPowerCardVortex, performSwipe, processAmplifyEffect, processBlackHoleDestruction, processEventSpawnRules, processFreezeRemovalFromAdjacentMerge, processGlobalEffects, processLockTriggerOnMerge, processTileEffectsOnMerge, processTotemEffects, removeBlackHoleWithShards, resetTriggeredStates, rowColToIndex, selectSpawnPosition, setTile, setTileAt, shouldSpawnEffect, spawnTileEffects, tileHasEffect, updateComboMultiplier, updateTriggerStates, validateBoardConfig };
