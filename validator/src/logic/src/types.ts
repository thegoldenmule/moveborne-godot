import type { RNGNamespace } from "./random";

export type TileStatus =
  | "normal"
  | "new"
  | "merged"
  | "magnetized"
  | "spawned"
  | "shuffled"
  | "lightning"
  | "rotated"
  | "radiated"
  | "cloned"
  | "swapped"
  | "teleported"
  | "split"
  | "multiplied"
  | "bombed"
  | "destroyed"
  | "purged"
  | "amplified";

export type TileEffectType =
  | "none"
  | "freeze"
  | "black_hole"
  | "amplify"
  | "amplify_static"
  | "lock"
  | "decay"
  | "stone";

export interface TileEffectVisualConfig {
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

export interface TileEffectMergeConfig {
  valueMultiplier: number;
  consumedOnMerge: boolean;
  consumptionEmitter?: string;
  effectStaysAtSource: boolean;
}

export type SpawnCurveType = "constant" | "linear" | "exponential" | "stepped";

export interface SpawnCurve {
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

export interface TileEffectSpawnConfig {
  spawnCurve: SpawnCurve;
  canSpawnOn: TileStatus[];
  canSpawnOnEmpty: boolean;
  maxActiveOnBoard: number;
}

export interface TileEffectConfig {
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

export interface TileEffect {
  type: TileEffectType;
  active: boolean;
  config: TileEffectConfig;
}

export interface SynchronizedTileState {
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

export interface BoardPosition {
  row: number;
  col: number;
}

export interface PartialBoardPosition {
  row?: number;
  col?: number;
}

export interface DestroyedTile {
  position: BoardPosition;
  value: number;
  destroyedBy: {
    type: "black_hole";
    position: BoardPosition;
  };
}

export interface SynchronizedBoardState {
  tiles: SynchronizedTileState[];
  size: number;
}

export interface InitialTileConfig {
  value: number;
  effect?: {
    type: Exclude<TileEffectType, "none">;
    config?: Partial<TileEffectConfig>;
  };
}

export interface InitialBoardConfig {
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

export type SpawnPositionStrategy = "random" | "empty" | "highest_value";

export type EventTrigger =
  | { event: "COMBO_BREAK"; minCombo: number }
  | { event: "SCORE_MILESTONE"; threshold: number }
  | { event: "MERGE_COUNT"; count: number }
  | { event: "MOVE_COUNT"; moves: number };

export interface AuthoritativeSpawnConfig {
  effects: Array<{
    type: Exclude<TileEffectType, "none">;
    position: BoardPosition;
    config?: Partial<TileEffectConfig>;
  }>;
}

export interface EventBasedSpawnRule {
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

export interface EventTriggerState {
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

export type PowerCardType =
  | "bomb"
  | "swap"
  | "clear"
  | "double"
  | "time"
  | "magnet"
  | "shuffle"
  | "destroy"
  | "transform"
  | "lightning"
  | "radiate"
  | "clone"
  | "vortex"
  | "multiply"
  | "teleport"
  | "split"
  | "combo_guardian"
  | "energy_catalyst"
  | "power_surge"
  | "mega_boost"
  | "time_anchor"
  | "attraction_field"
  | "momentum_wave"
  | "void_portal"
  | "echo_chamber"
  | "scavenger_totem";

export interface PowerCardColors {
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

export interface TotemTypeDefinition {
  id: TotemType;
  name: string;
  description: string;
  icon: { src: string };
  maxTallyMarks?: number;
  defaultMoves?: number;
  defaultSwipes?: number;
  defaultMerges?: number;
  spawnValue?: number;
}

export interface PowerCardDefinition {
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

export type PowerCardInstance = {
  id: string;
} & PowerCardDefinition;

export interface SynchronizedHandState {
  cards: PowerCardInstance[];
}

export interface SynchronizedDeckState {
  remainingCards: number;
  nextCardIndex: number;
}

export type TotemType =
  | "none"
  | "combo_saver"
  | "spawn_booster_2x"
  | "spawn_booster_4x"
  | "spawn_booster_8x"
  | "momentum_idol"
  | "magnet_core"
  | "void_gate"
  | "ghost_merge"
  | "scavenger"
  | "chrono_anchor";

export interface TotemConfig {
  tallyMarks?: number;
  maxTallyMarks?: number;
  movesRemaining?: number;
  swipesRemaining?: number;
  mergesRemaining?: number;
  spawnValue?: number;
  [key: string]: unknown;
}

export interface Totem {
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

export interface SynchronizedTotemsState {
  active: Totem[];
}

export type GameStatus = "idle" | "playing" | "paused" | "gameover" | "victory";

export interface ScenarioConfig {
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

export type GlobalEffectState = {
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

export interface SynchronizedGameState {
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

export enum OperationType {
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
  REMOVE_BLACK_HOLE = "REMOVE_BLACK_HOLE",
}

export interface OperationData {
  type: OperationType;
  direction?: string;
  cardIndex?: number;
  position?: { row: number; col: number };
  [key: string]: unknown;
}

export interface OptimisticUpdate {
  opId: string;
  moveIndex: number;
  operation: OperationData;
  stateBeforeOp: SynchronizedGameState;
  stateAfterOp: SynchronizedGameState;
  timestamp: number;
}

export interface GameAction {
  type: OperationType;
  payload: unknown;
}

export interface HandFactoryConfig {
  size?: number;
}

export interface GameFactoryConfig {
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

export type GameEventType =
  | "PRE_SWIPE"
  | "SWIPE_COMPLETED"
  | "TILE_SPAWN"
  | "TILE_MERGE"
  | "TILE_MOVE"
  | "TILE_DESTROY"
  | "TILE_EFFECT_APPLIED"
  | "TILE_EFFECT_REMOVED"
  | "CARD_PLAYED"
  | "TOTEM_ACTIVATED"
  | "TOTEM_DESPAWNED"
  | "COMBO_BREAK"
  | "COMBO_BREAK_ATTEMPTED"
  | "COMBO_CONTINUE"
  | "COMBO_INCREMENT"
  | "GAME_START"
  | "GAME_END"
  | "TURN_END"
  | "SCORE_UPDATE"
  | "SELECTION_MADE"
  | "MOVE_COMPLETED"
  | "POST_SPAWN"
  | "FAILED_SWIPE"
  | "POST_SWIPE"
  | "CREATE_SNAPSHOT"
  | "TRIGGER_REWIND";

export interface GameEvent {
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
