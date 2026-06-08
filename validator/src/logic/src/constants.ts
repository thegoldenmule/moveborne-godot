import {
  PowerCardDefinition,
  PowerCardType,
  TotemType,
  TotemTypeDefinition,
  OperationType,
} from "./types";

export const MIN_BOARD_SIZE = 4;
export const MAX_BOARD_SIZE = 8;
export const DEFAULT_BOARD_SIZE = 4;

export const SHARDS_PER_CARD = 8;
export const MAX_HAND_SIZE = 3;
export const DECK_SIZE = 12;

export const DEFAULT_TILE_SIZE = 70;

export const RNG_NAMESPACES = {
  TILE_GEN: "tile-gen" as const,
  SHUFFLE: "shuffle" as const,
  EFFECT_SPAWN: "effect-spawn" as const,
  TOTEM_SPAWN: "totem-spawn" as const,
  CARD_DRAW: "card-draw" as const,
};

export const TOTEM_TYPES: Record<TotemType, TotemTypeDefinition> = {
  none: {
    id: "none",
    name: "None",
    description: "No totem",
    icon: { src: "/assets/totems/none.png" },
  },
  combo_saver: {
    id: "combo_saver",
    name: "Combo Saver",
    description: "Prevents combo from breaking",
    maxTallyMarks: 3,
    icon: { src: "/assets/totems/combo-saver.png" },
  },
  spawn_booster_2x: {
    id: "spawn_booster_2x",
    name: "2x Spawn Booster",
    description: "All spawned tiles are 4s",
    defaultMoves: 10,
    spawnValue: 4,
    icon: { src: "/assets/totems/spawn-booster-2x.png" },
  },
  spawn_booster_4x: {
    id: "spawn_booster_4x",
    name: "4x Spawn Booster",
    description: "All spawned tiles are 8s",
    defaultMoves: 10,
    spawnValue: 8,
    icon: { src: "/assets/totems/spawn-booster-4x.png" },
  },
  spawn_booster_8x: {
    id: "spawn_booster_8x",
    name: "8x Spawn Booster",
    description: "All spawned tiles are 16s",
    defaultMoves: 10,
    spawnValue: 16,
    icon: { src: "/assets/totems/spawn-booster-8x.png" },
  },
  chrono_anchor: {
    id: "chrono_anchor",
    name: "Chrono Anchor",
    description: "Can rewind to snapshot",
    defaultMoves: 5,
    icon: { src: "/assets/totems/chrono-anchor.png" },
  },
  magnet_core: {
    id: "magnet_core",
    name: "Magnet Core",
    description: "Tiles move towards center after spawn",
    defaultMoves: 10,
    icon: { src: "/assets/totems/magnet-core.png" },
  },
  momentum_idol: {
    id: "momentum_idol",
    name: "Momentum Idol",
    description: "Adds +1 to combo multiplier increments",
    defaultMoves: 10,
    icon: { src: "/assets/totems/momentum-idol.png" },
  },
  void_gate: {
    id: "void_gate",
    name: "Void Gate",
    description: "Removes lowest tile instead of spawning on failed swipes",
    defaultMoves: 10,
    icon: { src: "/assets/totems/void-gate.png" },
  },
  ghost_merge: {
    id: "ghost_merge",
    name: "Ghost Merge",
    description: "First merge in swipe echoes to random empty cell (5 uses)",
    defaultMerges: 5,
    icon: { src: "/assets/totems/ghost-merge.png" },
  },
  scavenger: {
    id: "scavenger",
    name: "Scavenger",
    description: "Doubles shards earned from merges (4 uses)",
    defaultMerges: 4,
    icon: { src: "/assets/totems/scavenger.png" },
  },
};

export const POWER_CARDS: Record<PowerCardType, PowerCardDefinition> = {
  bomb: {
    type: "bomb",
    name: "Void Blast",
    description: "Removes all effects and value from a tile",
    texture: "/assets/hand/images/bomb.png",
  },
  clear: {
    type: "clear",
    name: "Purge Column",
    description: "Clear all unaffected tiles in a column",
    texture: "/assets/hand/images/clear.png",
  },
  double: {
    type: "double",
    name: "Amplify",
    description: "Double the value of a tile",
    texture: "/assets/hand/images/double.png",
  },
  time: {
    type: "time",
    name: "Temporal Freeze",
    description: "Pause the timer for 10 seconds",
    texture: "/assets/hand/images/time.png",
  },
  magnet: {
    type: "magnet",
    name: "Gravity Well",
    description: "Tiles move towards center after spawn",
    texture: "/assets/hand/images/magnet.png",
  },
  destroy: {
    type: "destroy",
    name: "Destroy",
    description: "Destroys a tile's value",
    texture: "/assets/cards/destroy.png",
    colors: {
      border: 0xdc7c05,
      nameplate: 0xdc7c05,
    },
  },
  transform: {
    type: "transform",
    name: "Transmute",
    description: "Removes 3 random tile effects from the board",
    texture: "/assets/hand/images/transform.png",
    value: 3,
  },
  vortex: {
    type: "vortex",
    name: "Whirlwind",
    description: "Rotate a 2x2 quadrant clockwise",
    texture: "/assets/hand/images/vortex.png",
  },
  swap: {
    type: "swap",
    name: "Phase Shift",
    description: "Swap any two tiles",
    texture: "/assets/hand/images/swap.png",
  },
  clone: {
    type: "clone",
    name: "Echo",
    description: "Copy a tile into an empty neighbour",
    texture: "/assets/hand/images/clone.png",
  },
  radiate: {
    type: "radiate",
    name: "Pulse Wave",
    description: "Double all tiles adjacent to a tile",
    texture: "/assets/hand/images/radiate.png",
  },
  shuffle: {
    type: "shuffle",
    name: "Chaos Storm",
    description: "Shuffle the entire board",
    texture: "/assets/cards/chaos-storm.png",
    colors: {
      border: 0x7dcb57,
      nameplate: 0x7dcb57,
    },
  },
  lightning: {
    type: "lightning",
    name: "Thunder Strike",
    description: "Double all tiles in a column",
    texture: "/assets/hand/images/lightning.png",
  },
  split: {
    type: "split",
    name: "Fracture",
    description: "Halve a tile (e.g., 64 → 32)",
    texture: "/assets/hand/images/split.png",
  },
  multiply: {
    type: "multiply",
    name: "Surge",
    description: "Double a tile",
    texture: "/assets/hand/images/multiply.png",
  },
  teleport: {
    type: "teleport",
    name: "Warp Gate",
    description: "Move a tile to any empty space",
    texture: "/assets/hand/images/teleport.png",
  },
  combo_guardian: {
    type: "combo_guardian",
    name: "Combo Guardian",
    description: "Spawn Combo Saver totem",
    texture: "/assets/hand/images/combo_guardian.png",
    spawnsTotem: TOTEM_TYPES.combo_saver,
    isTotemCard: true,
  },
  energy_catalyst: {
    type: "energy_catalyst",
    name: "Energy Catalyst",
    description: "Spawn 2x Spawn Booster",
    texture: "/assets/cards/energy-catalyst.png",
    spawnsTotem: TOTEM_TYPES.spawn_booster_2x,
    isTotemCard: true,
    colors: {
      nameplate: 0xffb72c,
      border: 0xffb72c,
    },
  },
  power_surge: {
    type: "power_surge",
    name: "Power Amplifier",
    description: "Spawn 4x Spawn Booster",
    texture: "/assets/hand/images/power_surge.png",
    spawnsTotem: TOTEM_TYPES.spawn_booster_4x,
    isTotemCard: true,
  },
  mega_boost: {
    type: "mega_boost",
    name: "Chaos Engine",
    description: "Spawn 8x Spawn Booster",
    texture: "/assets/hand/images/mega_boost.png",
    spawnsTotem: TOTEM_TYPES.spawn_booster_8x,
    isTotemCard: true,
  },
  time_anchor: {
    type: "time_anchor",
    name: "Time Keeper",
    description: "Spawn Chrono Anchor",
    texture: "/assets/hand/images/time_anchor.png",
    spawnsTotem: TOTEM_TYPES.chrono_anchor,
    isTotemCard: true,
  },
  attraction_field: {
    type: "attraction_field",
    name: "Graviton Core",
    description: "Spawn Magnet Core",
    texture: "/assets/hand/images/attraction_field.png",
    spawnsTotem: TOTEM_TYPES.magnet_core,
    isTotemCard: true,
  },
  momentum_wave: {
    type: "momentum_wave",
    name: "Momentum Idol",
    description: "Spawn Momentum Idol",
    texture: "/assets/hand/images/momentum_wave.png",
    spawnsTotem: TOTEM_TYPES.momentum_idol,
    isTotemCard: true,
  },
  void_portal: {
    type: "void_portal",
    name: "Void Summoner",
    description: "Spawn Void Gate",
    texture: "/assets/hand/images/void_portal.png",
    spawnsTotem: TOTEM_TYPES.void_gate,
    isTotemCard: true,
  },
  echo_chamber: {
    type: "echo_chamber",
    name: "Ghost Merge",
    description: "Spawn Ghost Merge",
    texture: "/assets/hand/images/echo_chamber.png",
    spawnsTotem: TOTEM_TYPES.ghost_merge,
    isTotemCard: true,
  },
  scavenger_totem: {
    type: "scavenger_totem",
    name: "Scavenger",
    description: "Spawn Scavenger",
    texture: "/assets/hand/images/scavenger_totem.png",
    spawnsTotem: TOTEM_TYPES.scavenger,
    isTotemCard: true,
  },
};

export const MAX_ACTIVE_TOTEMS = 3;

export { OperationType };
