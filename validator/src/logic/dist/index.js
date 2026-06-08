import seedrandom from 'seedrandom';
import stableStringify from 'json-stable-stringify';

// src/types.ts
var OperationType = /* @__PURE__ */ ((OperationType2) => {
  OperationType2["READY"] = "READY";
  OperationType2["SWIPE"] = "SWIPE";
  OperationType2["PLAY_CARD"] = "PLAY_CARD";
  OperationType2["DRAW_CARD"] = "DRAW_CARD";
  OperationType2["SELECT_CARD"] = "SELECT_CARD";
  OperationType2["SELECT_TILE"] = "SELECT_TILE";
  OperationType2["SPAWN_TOTEM"] = "SPAWN_TOTEM";
  OperationType2["TRIGGER_TOTEM"] = "TRIGGER_TOTEM";
  OperationType2["REPLACE_TOTEM"] = "REPLACE_TOTEM";
  OperationType2["RESTORE_STATE"] = "RESTORE_STATE";
  OperationType2["REMOVE_BLACK_HOLE"] = "REMOVE_BLACK_HOLE";
  return OperationType2;
})(OperationType || {});
var PassThroughRandomGenerator = {
  getRandom: () => 0,
  getIndices: () => ({
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0
  }),
  getSeeds: () => ({
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0
  }),
  getState: () => "",
  getAllStates: () => ({
    "tile-gen": "",
    shuffle: "",
    "effect-spawn": "",
    "totem-spawn": "",
    "card-draw": ""
  }),
  clone: () => new RandomGenerator(
    {
      "tile-gen": 0,
      shuffle: 0,
      "effect-spawn": 0,
      "totem-spawn": 0,
      "card-draw": 0
    },
    {
      "tile-gen": 0,
      shuffle: 0,
      "effect-spawn": 0,
      "totem-spawn": 0,
      "card-draw": 0
    }
  )
};
var RandomGenerator = class _RandomGenerator {
  constructor(seeds, indices) {
    this.seeds = { ...seeds };
    this.rngIndices = { ...indices };
    this.rngInstances = /* @__PURE__ */ new Map();
    for (const namespace of Object.keys(seeds)) {
      this.rngInstances.set(namespace, seedrandom(seeds[namespace].toString()));
    }
    for (const [namespace, targetIndex] of Object.entries(indices)) {
      const rng = this.rngInstances.get(namespace);
      if (!rng) continue;
      for (let i = 0; i < targetIndex; i++) {
        rng();
      }
    }
  }
  getRandom(namespace) {
    const rng = this.rngInstances.get(namespace);
    if (!rng) {
      throw new Error(
        `RNG namespace '${namespace}' not initialized. Check RandomGenerator constructor.`
      );
    }
    const value = rng();
    this.rngIndices[namespace]++;
    return value;
  }
  getIndices() {
    return { ...this.rngIndices };
  }
  getSeeds() {
    return { ...this.seeds };
  }
  getState(namespace) {
    const index = this.rngIndices[namespace];
    const isInitialized = this.rngInstances.has(namespace);
    return `${namespace}: ${isInitialized ? "initialized" : "not initialized"}, index=${index}`;
  }
  getAllStates() {
    const namespaces = [
      "tile-gen",
      "shuffle",
      "effect-spawn",
      "totem-spawn",
      "card-draw"
    ];
    const states = {};
    for (const namespace of namespaces) {
      states[namespace] = this.getState(namespace);
    }
    return states;
  }
  clone() {
    return new _RandomGenerator(this.seeds, this.rngIndices);
  }
};
function initRandomSeeds(seeds, indices) {
  const rngInstances = /* @__PURE__ */ new Map();
  const rngIndices = {
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0
  };
  for (const namespace of Object.keys(seeds)) {
    rngInstances.set(namespace, seedrandom(seeds[namespace].toString()));
    rngIndices[namespace] = indices[namespace];
  }
  for (const [namespace, targetIndex] of Object.entries(rngIndices)) {
    const rng = rngInstances.get(namespace);
    if (!rng) continue;
    for (let i = 0; i < targetIndex; i++) {
      rng();
    }
  }
}
function getRNGIndices() {
  return {
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0
  };
}

// src/constants.ts
var MIN_BOARD_SIZE = 4;
var MAX_BOARD_SIZE = 8;
var DEFAULT_BOARD_SIZE = 4;
var SHARDS_PER_CARD = 8;
var MAX_HAND_SIZE = 3;
var DECK_SIZE = 12;
var DEFAULT_TILE_SIZE = 70;
var RNG_NAMESPACES = {
  TILE_GEN: "tile-gen",
  SHUFFLE: "shuffle",
  EFFECT_SPAWN: "effect-spawn",
  TOTEM_SPAWN: "totem-spawn",
  CARD_DRAW: "card-draw"
};
var TOTEM_TYPES = {
  none: {
    id: "none",
    name: "None",
    description: "No totem",
    icon: { src: "/assets/totems/none.png" }
  },
  combo_saver: {
    id: "combo_saver",
    name: "Combo Saver",
    description: "Prevents combo from breaking",
    maxTallyMarks: 3,
    icon: { src: "/assets/totems/combo-saver.png" }
  },
  spawn_booster_2x: {
    id: "spawn_booster_2x",
    name: "2x Spawn Booster",
    description: "All spawned tiles are 4s",
    defaultMoves: 10,
    spawnValue: 4,
    icon: { src: "/assets/totems/spawn-booster-2x.png" }
  },
  spawn_booster_4x: {
    id: "spawn_booster_4x",
    name: "4x Spawn Booster",
    description: "All spawned tiles are 8s",
    defaultMoves: 10,
    spawnValue: 8,
    icon: { src: "/assets/totems/spawn-booster-4x.png" }
  },
  spawn_booster_8x: {
    id: "spawn_booster_8x",
    name: "8x Spawn Booster",
    description: "All spawned tiles are 16s",
    defaultMoves: 10,
    spawnValue: 16,
    icon: { src: "/assets/totems/spawn-booster-8x.png" }
  },
  chrono_anchor: {
    id: "chrono_anchor",
    name: "Chrono Anchor",
    description: "Can rewind to snapshot",
    defaultMoves: 5,
    icon: { src: "/assets/totems/chrono-anchor.png" }
  },
  magnet_core: {
    id: "magnet_core",
    name: "Magnet Core",
    description: "Tiles move towards center after spawn",
    defaultMoves: 10,
    icon: { src: "/assets/totems/magnet-core.png" }
  },
  momentum_idol: {
    id: "momentum_idol",
    name: "Momentum Idol",
    description: "Adds +1 to combo multiplier increments",
    defaultMoves: 10,
    icon: { src: "/assets/totems/momentum-idol.png" }
  },
  void_gate: {
    id: "void_gate",
    name: "Void Gate",
    description: "Removes lowest tile instead of spawning on failed swipes",
    defaultMoves: 10,
    icon: { src: "/assets/totems/void-gate.png" }
  },
  ghost_merge: {
    id: "ghost_merge",
    name: "Ghost Merge",
    description: "First merge in swipe echoes to random empty cell (5 uses)",
    defaultMerges: 5,
    icon: { src: "/assets/totems/ghost-merge.png" }
  },
  scavenger: {
    id: "scavenger",
    name: "Scavenger",
    description: "Doubles shards earned from merges (4 uses)",
    defaultMerges: 4,
    icon: { src: "/assets/totems/scavenger.png" }
  }
};
var POWER_CARDS = {
  bomb: {
    type: "bomb",
    name: "Void Blast",
    description: "Removes all effects and value from a tile",
    texture: "/assets/hand/images/bomb.png"
  },
  clear: {
    type: "clear",
    name: "Purge Column",
    description: "Clear all unaffected tiles in a column",
    texture: "/assets/hand/images/clear.png"
  },
  double: {
    type: "double",
    name: "Amplify",
    description: "Double the value of a tile",
    texture: "/assets/hand/images/double.png"
  },
  time: {
    type: "time",
    name: "Temporal Freeze",
    description: "Pause the timer for 10 seconds",
    texture: "/assets/hand/images/time.png"
  },
  magnet: {
    type: "magnet",
    name: "Gravity Well",
    description: "Tiles move towards center after spawn",
    texture: "/assets/hand/images/magnet.png"
  },
  destroy: {
    type: "destroy",
    name: "Destroy",
    description: "Destroys a tile's value",
    texture: "/assets/cards/destroy.png",
    colors: {
      border: 14449669,
      nameplate: 14449669
    }
  },
  transform: {
    type: "transform",
    name: "Transmute",
    description: "Removes 3 random tile effects from the board",
    texture: "/assets/hand/images/transform.png",
    value: 3
  },
  vortex: {
    type: "vortex",
    name: "Whirlwind",
    description: "Rotate a 2x2 quadrant clockwise",
    texture: "/assets/hand/images/vortex.png"
  },
  swap: {
    type: "swap",
    name: "Phase Shift",
    description: "Swap any two tiles",
    texture: "/assets/hand/images/swap.png"
  },
  clone: {
    type: "clone",
    name: "Echo",
    description: "Copy a tile into an empty neighbour",
    texture: "/assets/hand/images/clone.png"
  },
  radiate: {
    type: "radiate",
    name: "Pulse Wave",
    description: "Double all tiles adjacent to a tile",
    texture: "/assets/hand/images/radiate.png"
  },
  shuffle: {
    type: "shuffle",
    name: "Chaos Storm",
    description: "Shuffle the entire board",
    texture: "/assets/cards/chaos-storm.png",
    colors: {
      border: 8244055,
      nameplate: 8244055
    }
  },
  lightning: {
    type: "lightning",
    name: "Thunder Strike",
    description: "Double all tiles in a column",
    texture: "/assets/hand/images/lightning.png"
  },
  split: {
    type: "split",
    name: "Fracture",
    description: "Halve a tile (e.g., 64 \u2192 32)",
    texture: "/assets/hand/images/split.png"
  },
  multiply: {
    type: "multiply",
    name: "Surge",
    description: "Double a tile",
    texture: "/assets/hand/images/multiply.png"
  },
  teleport: {
    type: "teleport",
    name: "Warp Gate",
    description: "Move a tile to any empty space",
    texture: "/assets/hand/images/teleport.png"
  },
  combo_guardian: {
    type: "combo_guardian",
    name: "Combo Guardian",
    description: "Spawn Combo Saver totem",
    texture: "/assets/hand/images/combo_guardian.png",
    spawnsTotem: TOTEM_TYPES.combo_saver,
    isTotemCard: true
  },
  energy_catalyst: {
    type: "energy_catalyst",
    name: "Energy Catalyst",
    description: "Spawn 2x Spawn Booster",
    texture: "/assets/cards/energy-catalyst.png",
    spawnsTotem: TOTEM_TYPES.spawn_booster_2x,
    isTotemCard: true,
    colors: {
      nameplate: 16758572,
      border: 16758572
    }
  },
  power_surge: {
    type: "power_surge",
    name: "Power Amplifier",
    description: "Spawn 4x Spawn Booster",
    texture: "/assets/hand/images/power_surge.png",
    spawnsTotem: TOTEM_TYPES.spawn_booster_4x,
    isTotemCard: true
  },
  mega_boost: {
    type: "mega_boost",
    name: "Chaos Engine",
    description: "Spawn 8x Spawn Booster",
    texture: "/assets/hand/images/mega_boost.png",
    spawnsTotem: TOTEM_TYPES.spawn_booster_8x,
    isTotemCard: true
  },
  time_anchor: {
    type: "time_anchor",
    name: "Time Keeper",
    description: "Spawn Chrono Anchor",
    texture: "/assets/hand/images/time_anchor.png",
    spawnsTotem: TOTEM_TYPES.chrono_anchor,
    isTotemCard: true
  },
  attraction_field: {
    type: "attraction_field",
    name: "Graviton Core",
    description: "Spawn Magnet Core",
    texture: "/assets/hand/images/attraction_field.png",
    spawnsTotem: TOTEM_TYPES.magnet_core,
    isTotemCard: true
  },
  momentum_wave: {
    type: "momentum_wave",
    name: "Momentum Idol",
    description: "Spawn Momentum Idol",
    texture: "/assets/hand/images/momentum_wave.png",
    spawnsTotem: TOTEM_TYPES.momentum_idol,
    isTotemCard: true
  },
  void_portal: {
    type: "void_portal",
    name: "Void Summoner",
    description: "Spawn Void Gate",
    texture: "/assets/hand/images/void_portal.png",
    spawnsTotem: TOTEM_TYPES.void_gate,
    isTotemCard: true
  },
  echo_chamber: {
    type: "echo_chamber",
    name: "Ghost Merge",
    description: "Spawn Ghost Merge",
    texture: "/assets/hand/images/echo_chamber.png",
    spawnsTotem: TOTEM_TYPES.ghost_merge,
    isTotemCard: true
  },
  scavenger_totem: {
    type: "scavenger_totem",
    name: "Scavenger",
    description: "Spawn Scavenger",
    texture: "/assets/hand/images/scavenger_totem.png",
    spawnsTotem: TOTEM_TYPES.scavenger,
    isTotemCard: true
  }
};
var MAX_ACTIVE_TOTEMS = 3;
function canonicalStringify(obj) {
  return stableStringify(obj, { space: 2 }) || "{}";
}
function computeStateHash(state) {
  const jsonStr = canonicalStringify(state);
  return sha256(jsonStr);
}
function computeActionHash(action) {
  const jsonStr = canonicalStringify(action);
  return sha256(jsonStr);
}
function sha256(input) {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  let h0 = 1779033703;
  let h1 = 3144134277;
  let h2 = 1013904242;
  let h3 = 2773480762;
  let h4 = 1359893119;
  let h5 = 2600822924;
  let h6 = 528734635;
  let h7 = 1541459225;
  for (let i = 0; i < data.length; i++) {
    const byte = data[i];
    h0 = (h0 << 5) - h0 + byte | 0;
    h1 = (h1 << 7) - h1 + byte | 0;
    h2 = (h2 << 11) - h2 + byte | 0;
    h3 = (h3 << 13) - h3 + byte | 0;
    h4 = (h4 << 17) - h4 + byte | 0;
    h5 = (h5 << 19) - h5 + byte | 0;
    h6 = (h6 << 23) - h6 + byte | 0;
    h7 = (h7 << 29) - h7 + byte | 0;
  }
  return (h0 >>> 0).toString(16).padStart(8, "0") + (h1 >>> 0).toString(16).padStart(8, "0") + (h2 >>> 0).toString(16).padStart(8, "0") + (h3 >>> 0).toString(16).padStart(8, "0") + (h4 >>> 0).toString(16).padStart(8, "0") + (h5 >>> 0).toString(16).padStart(8, "0") + (h6 >>> 0).toString(16).padStart(8, "0") + (h7 >>> 0).toString(16).padStart(8, "0");
}
async function computeStateHashAsync(state) {
  const jsonStr = canonicalStringify(state);
  return await sha256Async(jsonStr);
}
async function computeActionHashAsync(action) {
  const jsonStr = canonicalStringify(action);
  return await sha256Async(jsonStr);
}
async function sha256Async(input) {
  if (typeof crypto === "undefined" || !crypto.subtle) {
    return sha256(input);
  }
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
  return hashHex;
}

// src/board.ts
function indexToRowCol(index, boardSize) {
  return {
    row: Math.floor(index / boardSize),
    col: index % boardSize
  };
}
function rowColToIndex(row, col, boardSize) {
  return row * boardSize + col;
}
function isValidPosition(row, col, boardSize) {
  return row >= 0 && row < boardSize && col >= 0 && col < boardSize;
}
function getTile(tiles, row, col, boardSize) {
  if (!isValidPosition(row, col, boardSize)) {
    throw new Error("Invalid row or column");
  }
  return tiles[rowColToIndex(row, col, boardSize)];
}
function setTile(tiles, tile, boardSize) {
  tiles[rowColToIndex(tile.row, tile.col, boardSize)] = tile;
}

// src/factories.ts
var createEmptyTile = (row = 0, col = 0) => {
  return {
    isEmpty: true,
    value: 0,
    row,
    col,
    status: "normal"
  };
};
var createTileEffect = (type, config) => {
  let effectSpecificConfig;
  switch (type) {
    case "black_hole":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 7,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 7,
        allowsValueMerge: true,
        allowsValueMovement: false,
        effectRemovedByAdjacentMerge: false,
        visual: {
          overlayTexture: "/assets/tile-effects/black-hole/overlay.png",
          overlayWidth: 100,
          overlayHeight: 100,
          spawnEmitter: "black-hole-spawn",
          activeEmitter: "black-hole-run",
          removalEmitter: "black-hole-removal"
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: true
        },
        ...config
      };
      break;
    case "lock":
      effectSpecificConfig = {
        remainingTriggers: 1,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: false,
        effectRemovedByAdjacentMerge: false,
        visual: {
          overlayTexture: "/assets/tile-effects/lock/overlay.png",
          overlayWidth: DEFAULT_TILE_SIZE,
          overlayHeight: DEFAULT_TILE_SIZE,
          spawnEmitter: "lock-spawn",
          removalEmitter: "lock-removal"
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: true
        },
        ...config
      };
      break;
    case "decay":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0.5,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 5,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        visual: {
          spawnEmitter: "decay-spawn",
          removalEmitter: "decay-removal"
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false
        },
        ...config
      };
      break;
    case "amplify":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 2,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        visual: {
          backgroundTexture: "/assets/tile-effects/amplify/background.png",
          backgroundWidth: DEFAULT_TILE_SIZE + 8,
          backgroundHeight: DEFAULT_TILE_SIZE + 8,
          spawnEmitter: "amplify-spawn",
          activeEmitter: "amplify-run",
          removalEmitter: "amplify-removal",
          showMultiplier: true
        },
        mergeConfig: {
          valueMultiplier: 2,
          consumedOnMerge: true,
          consumptionEmitter: "amplify",
          effectStaysAtSource: true
        },
        ...config
      };
      break;
    case "amplify_static":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 2,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        visual: {
          backgroundTexture: "/assets/tile-effects/amplify/background.png",
          backgroundWidth: DEFAULT_TILE_SIZE + 8,
          backgroundHeight: DEFAULT_TILE_SIZE + 8,
          spawnEmitter: "amplify-spawn",
          activeEmitter: "amplify-run",
          removalEmitter: "amplify-removal",
          showMultiplier: true
        },
        mergeConfig: {
          valueMultiplier: 2,
          consumedOnMerge: false,
          consumptionEmitter: "amplify",
          effectStaysAtSource: true
        },
        ...config
      };
      break;
    case "freeze":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: false,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: true,
        visual: {
          overlayTexture: "/assets/tile-effects/freeze/overlay.png",
          overlayWidth: 100,
          overlayHeight: 100,
          spawnEmitter: "freeze-spawn",
          activeEmitter: "freeze-run",
          removalEmitter: "freeze-removal"
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false
        },
        ...config
      };
      break;
    case "stone":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: false,
        allowsValueMovement: false,
        effectRemovedByAdjacentMerge: true,
        visual: {
          overlayTexture: "/assets/tile-effects/stone/overlay.png",
          overlayWidth: DEFAULT_TILE_SIZE + 8,
          overlayHeight: DEFAULT_TILE_SIZE + 8,
          spawnEmitter: "stone-spawn",
          removalEmitter: "stone-removal"
        },
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: true
        },
        ...config
      };
      break;
    case "none":
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false
        },
        ...config
      };
      break;
    default:
      effectSpecificConfig = {
        remainingTriggers: 0,
        decayRate: 0,
        tilesConsumed: 0,
        maxTilesToImplosion: 0,
        decayMoveInterval: 0,
        lastDecayMove: 0,
        multiplier: 1,
        removalCost: 0,
        allowsValueMerge: true,
        allowsValueMovement: true,
        effectRemovedByAdjacentMerge: false,
        mergeConfig: {
          valueMultiplier: 1,
          consumedOnMerge: false,
          effectStaysAtSource: false
        },
        ...config
      };
  }
  return {
    type,
    active: true,
    config: effectSpecificConfig
  };
};
var createFreezeEffect = () => createTileEffect("freeze");
var createBlackHoleEffect = (removalCost) => createTileEffect(
  "black_hole",
  removalCost !== void 0 ? { removalCost } : void 0
);
var createAmplifyEffect = () => createTileEffect("amplify");
var createStoneEffect = () => createTileEffect("stone");

// src/boardBuilder.ts
function buildInitialBoard(config, boardSize, randomGen) {
  validateBoardConfig(config, boardSize);
  const tiles = [];
  for (let r = 0; r < boardSize; r++) {
    for (let c = 0; c < boardSize; c++) {
      tiles.push(createEmptyTile(r, c));
    }
  }
  if (config.tiles) {
    for (const placement of config.tiles) {
      setTileAt(tiles, boardSize, placement.position, placement.config);
    }
  }
  if (config.randomTiles) {
    const { count, values, avoidPositions = [] } = config.randomTiles;
    const emptyPositions = getEmptyPositions(tiles, avoidPositions);
    if (emptyPositions.length < count) {
      throw new Error(
        `Not enough empty positions for random tiles. Requested ${count}, available ${emptyPositions.length}`
      );
    }
    for (let i = 0; i < count; i++) {
      const randomIndex = Math.floor(
        randomGen.getRandom("tile-gen") * emptyPositions.length
      );
      const position = emptyPositions.splice(randomIndex, 1)[0];
      const randomValueIndex = Math.floor(
        randomGen.getRandom("tile-gen") * values.length
      );
      const value = values[randomValueIndex];
      setTileAt(tiles, boardSize, position, { value });
    }
  }
  return tiles;
}
function setTileAt(tiles, boardSize, position, config) {
  const { row, col } = position;
  if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) {
    throw new Error(
      `Position (${row}, ${col}) is out of bounds for board size ${boardSize}`
    );
  }
  const index = row * boardSize + col;
  const tile = tiles[index];
  tile.isEmpty = false;
  tile.value = config.value;
  if (config.effect) {
    tile.effect = createTileEffect(config.effect.type, config.effect.config);
  }
}
function getEmptyPositions(tiles, avoidPositions) {
  const emptyPositions = [];
  for (const tile of tiles) {
    if (!tile.isEmpty) continue;
    const isAvoided = avoidPositions.some(
      (pos) => pos.row === tile.row && pos.col === tile.col
    );
    if (!isAvoided) {
      emptyPositions.push({ row: tile.row, col: tile.col });
    }
  }
  return emptyPositions;
}
function validateBoardConfig(config, boardSize) {
  if (config.tiles) {
    const positions = /* @__PURE__ */ new Set();
    for (const placement of config.tiles) {
      const { row, col } = placement.position;
      if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) {
        throw new Error(
          `Tile position (${row}, ${col}) is out of bounds for board size ${boardSize}`
        );
      }
      const posKey = `${row},${col}`;
      if (positions.has(posKey)) {
        throw new Error(
          `Duplicate tile placement at position (${row}, ${col})`
        );
      }
      positions.add(posKey);
      const { value } = placement.config;
      if (value <= 0 || (value & value - 1) !== 0) {
        throw new Error(
          `Tile value ${value} at position (${row}, ${col}) is not a power of 2`
        );
      }
    }
  }
  if (config.randomTiles) {
    const { count, values } = config.randomTiles;
    if (count < 0) {
      throw new Error(`Random tile count must be non-negative, got ${count}`);
    }
    if (values.length === 0) {
      throw new Error("Random tile values array cannot be empty");
    }
    for (const value of values) {
      if (value <= 0 || (value & value - 1) !== 0) {
        throw new Error(`Random tile value ${value} is not a power of 2`);
      }
    }
    const totalPositions = boardSize * boardSize;
    const explicitTileCount = config.tiles?.length ?? 0;
    const availablePositions = totalPositions - explicitTileCount;
    if (count > availablePositions) {
      throw new Error(
        `Cannot place ${count} random tiles on board with ${availablePositions} available positions`
      );
    }
  }
}

// src/cardDraw.ts
function performDrawCard(gameState) {
  if (gameState.shards < SHARDS_PER_CARD) {
    return {
      success: false,
      shards: gameState.shards,
      deckNextCardIndex: gameState.deck.nextCardIndex,
      deckRemainingCards: gameState.deck.remainingCards,
      error: `Not enough shards (have ${gameState.shards}, need ${SHARDS_PER_CARD})`
    };
  }
  if (gameState.hand.cards.length >= MAX_HAND_SIZE) {
    return {
      success: false,
      shards: gameState.shards,
      deckNextCardIndex: gameState.deck.nextCardIndex,
      deckRemainingCards: gameState.deck.remainingCards,
      error: "Hand is full"
    };
  }
  if (gameState.deck.remainingCards <= 0) {
    return {
      success: false,
      shards: gameState.shards,
      deckNextCardIndex: gameState.deck.nextCardIndex,
      deckRemainingCards: gameState.deck.remainingCards,
      error: "No more cards in deck"
    };
  }
  return {
    success: true,
    shards: 0,
    // Reset shards after drawing
    deckNextCardIndex: gameState.deck.nextCardIndex + 1,
    deckRemainingCards: gameState.deck.remainingCards - 1
  };
}
function canDrawCard(gameState) {
  return gameState.shards >= SHARDS_PER_CARD && gameState.hand.cards.length < MAX_HAND_SIZE && gameState.deck.remainingCards > 0;
}
function drawCardFromDeck(rng, drawIndex) {
  const availableCards = Object.values(POWER_CARDS);
  const randomValue = rng.getRandom(RNG_NAMESPACES.CARD_DRAW);
  const cardIndex = Math.floor(randomValue * availableCards.length);
  const selectedCard = availableCards[cardIndex];
  return {
    ...selectedCard,
    id: `card_draw_${drawIndex}`
  };
}

// src/tileEffectLogic.ts
var DISABLED_SPAWN_CONFIG = {
  spawnCurve: {
    type: "constant",
    baseChance: 0
  },
  canSpawnOn: [],
  canSpawnOnEmpty: false,
  maxActiveOnBoard: 0
};
function getSpawnConfig(effectType, gameState) {
  return gameState.scenarioConfig?.spawnConfigs?.[effectType] ?? DISABLED_SPAWN_CONFIG;
}
function calculateSpawnChance(curve, moveIndex) {
  let chance;
  switch (curve.type) {
    case "constant":
      chance = curve.baseChance;
      break;
    case "linear": {
      const rate = curve.params?.linearRate ?? 1e-3;
      chance = curve.baseChance + rate * moveIndex;
      break;
    }
    case "exponential": {
      const factor = curve.params?.exponentialFactor ?? 1.01;
      chance = curve.baseChance * Math.pow(factor, moveIndex);
      break;
    }
    case "stepped": {
      const steps = curve.params?.steps ?? [];
      chance = curve.baseChance;
      for (const step of steps) {
        if (moveIndex >= step.moveIndex) {
          chance = step.chance;
        }
      }
      break;
    }
    default:
      chance = curve.baseChance;
  }
  const minChance = curve.minChance ?? 0;
  const maxChance = curve.maxChance ?? 1;
  return Math.max(minChance, Math.min(maxChance, chance));
}
function shouldSpawnEffect(effectType, gameState, currentActiveCount, randomGenerator) {
  const config = getSpawnConfig(effectType, gameState);
  const maxActive = gameState.scenarioConfig?.maxActiveOverrides?.[effectType] ?? config.maxActiveOnBoard;
  if (currentActiveCount >= maxActive) {
    return false;
  }
  const spawnChance = calculateSpawnChance(
    config.spawnCurve,
    gameState.moveIndex
  );
  return randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) < spawnChance;
}
function canApplyEffectToTile(tile, effectType, gameState) {
  if (tile.effect && tile.effect.active && tile.effect.type !== "none") {
    return false;
  }
  const spawnConfig = getSpawnConfig(effectType, gameState);
  if (tile.isEmpty) {
    return spawnConfig.canSpawnOnEmpty;
  }
  return spawnConfig.canSpawnOn.includes(tile.status);
}
function countActiveEffects(gameState, effectType) {
  let count = 0;
  for (const tile of gameState.board.tiles) {
    if (tile.effect && tile.effect.active && tile.effect.type === effectType) {
      count++;
    }
  }
  return count;
}
function getAdjacentTiles(gameState, position) {
  const { row, col } = position;
  const boardSize = gameState.board.size;
  const adjacentPositions = [];
  if (row > 0) adjacentPositions.push({ row: row - 1, col });
  if (row < boardSize - 1) adjacentPositions.push({ row: row + 1, col });
  if (col > 0) adjacentPositions.push({ row, col: col - 1 });
  if (col < boardSize - 1) adjacentPositions.push({ row, col: col + 1 });
  return adjacentPositions.map((pos) => {
    const index = pos.row * boardSize + pos.col;
    return gameState.board.tiles[index];
  });
}
function tileHasEffect(tile, effectType) {
  return tile.effect !== void 0 && tile.effect.active && tile.effect.type === effectType;
}
function removeEffectFromTile(tile) {
  if (tile.effect) {
    tile.effect.active = false;
  }
}
function applyEffectToTile(tile, effect) {
  tile.effect = effect;
}
function canValueMerge(tile) {
  if (!tile.effect || !tile.effect.active) {
    return true;
  }
  return tile.effect.config.allowsValueMerge;
}
function processFreezeRemovalFromAdjacentMerge(gameState, mergedPosition) {
  const removedPositions = [];
  const adjacentTiles = getAdjacentTiles(gameState, mergedPosition);
  adjacentTiles.forEach((tile) => {
    if (tile.effect && tile.effect.active && tile.effect.config.effectRemovedByAdjacentMerge) {
      removeEffectFromTile(tile);
      removedPositions.push({ row: tile.row, col: tile.col });
    }
  });
  return removedPositions;
}
function canTilesMergeTogether(tile1, tile2) {
  if (tile1.isEmpty || tile2.isEmpty) {
    return false;
  }
  if (tile1.value !== tile2.value) {
    return false;
  }
  return canValueMerge(tile1) && canValueMerge(tile2);
}
function processLockTriggerOnMerge(tile) {
  if (!tileHasEffect(tile, "lock")) {
    return null;
  }
  if (!tile.effect || !tile.effect.config) {
    return null;
  }
  const remainingTriggers = tile.effect.config.remainingTriggers;
  if (remainingTriggers <= 1) {
    removeEffectFromTile(tile);
    return { row: tile.row, col: tile.col };
  }
  tile.effect.config.remainingTriggers = remainingTriggers - 1;
  return null;
}
function isBlackHoleTile(tile) {
  return tileHasEffect(tile, "black_hole");
}
function canValueMove(tile) {
  if (tile.isEmpty) return false;
  if (!tile.effect || !tile.effect.active) return true;
  return tile.effect.config.allowsValueMovement;
}
function findBlackHoleInPath(tiles, boardSize, from, to) {
  const rowDir = to.row === from.row ? 0 : to.row > from.row ? 1 : -1;
  const colDir = to.col === from.col ? 0 : to.col > from.col ? 1 : -1;
  let currentRow = from.row + rowDir;
  let currentCol = from.col + colDir;
  while (currentRow !== to.row || currentCol !== to.col) {
    const index = currentRow * boardSize + currentCol;
    const tile = tiles[index];
    if (isBlackHoleTile(tile)) {
      return { row: currentRow, col: currentCol };
    }
    currentRow += rowDir;
    currentCol += colDir;
  }
  return null;
}
function processBlackHoleDestruction(consumedTile, blackHoleTile) {
  const scoreLoss = consumedTile.value;
  consumedTile.isEmpty = true;
  consumedTile.value = 0;
  consumedTile.status = "normal";
  delete consumedTile.effect;
  if (blackHoleTile.effect && blackHoleTile.effect.config) {
    blackHoleTile.effect.config.tilesConsumed = blackHoleTile.effect.config.tilesConsumed + 1;
    const maxTiles = blackHoleTile.effect.config.maxTilesToImplosion;
    const shouldImplode = blackHoleTile.effect.config.tilesConsumed >= maxTiles;
    return { scoreLoss, shouldImplode };
  }
  return { scoreLoss, shouldImplode: false };
}
function removeBlackHoleWithShards(gameState, position) {
  const index = position.row * gameState.board.size + position.col;
  const tile = gameState.board.tiles[index];
  if (!isBlackHoleTile(tile)) return null;
  const removalCost = tile.effect.config.removalCost;
  if (gameState.shards < removalCost) return null;
  removeEffectFromTile(tile);
  return {
    ...gameState,
    shards: gameState.shards - removalCost
  };
}
function isAmplifyTile(tile) {
  return tile !== void 0 && !tile.isEmpty && tile.effect?.type === "amplify" && tile.effect.active === true;
}
function getAmplifyMultiplier(tile) {
  if (!isAmplifyTile(tile)) return 1;
  return tile.effect.config.multiplier;
}
function processAmplifyEffect(tile, mergeValue) {
  if (!isAmplifyTile(tile)) {
    return { value: mergeValue, consumed: false, multiplier: 1 };
  }
  const multiplier = getAmplifyMultiplier(tile);
  const result = mergeValue * multiplier;
  if (tile.effect) {
    tile.effect.active = false;
  }
  return { value: result, consumed: true, multiplier };
}
function processTileEffectsOnMerge(tile, baseValue) {
  let finalValue = baseValue;
  const consumedEffects = [];
  if (tile.effect && tile.effect.active && tile.effect.type !== "none") {
    const mergeConfig = tile.effect.config.mergeConfig;
    finalValue *= mergeConfig.valueMultiplier;
    if (mergeConfig.consumedOnMerge) {
      consumedEffects.push({
        type: tile.effect.type,
        row: tile.row,
        col: tile.col,
        metadata: {
          multiplier: mergeConfig.valueMultiplier,
          emitter: mergeConfig.consumptionEmitter
        }
      });
      tile.effect.active = false;
    }
  }
  return { finalValue, consumedEffects };
}
function getEffectToPreserveAtSource(tile) {
  if (!tile.effect || !tile.effect.active || tile.effect.type === "none") {
    return void 0;
  }
  const mergeConfig = tile.effect.config.mergeConfig;
  if (mergeConfig.effectStaysAtSource) {
    return tile.effect;
  }
  return void 0;
}

// src/tileEffectSpawn.ts
function findValidSpawnPositions(gameState, effectType) {
  const validIndices = [];
  for (let i = 0; i < gameState.board.tiles.length; i++) {
    const tile = gameState.board.tiles[i];
    if (canApplyEffectToTile(tile, effectType, gameState)) {
      validIndices.push(i);
    }
  }
  return validIndices;
}
function selectSpawnPosition(gameState, validIndices, strategy, randomGenerator) {
  if (validIndices.length === 0) return null;
  switch (strategy) {
    case "random":
      return validIndices[Math.floor(
        randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * validIndices.length
      )];
    case "empty":
      const emptyIndices = validIndices.filter(
        (i) => gameState.board.tiles[i].isEmpty
      );
      if (emptyIndices.length === 0) return null;
      return emptyIndices[Math.floor(
        randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * emptyIndices.length
      )];
    case "highest_value":
      let maxValue = -1;
      let maxIndex = validIndices[0];
      for (const i of validIndices) {
        const tile = gameState.board.tiles[i];
        if (!tile.isEmpty && tile.value > maxValue) {
          maxValue = tile.value;
          maxIndex = i;
        }
      }
      return maxIndex;
    default:
      return null;
  }
}
function attemptSpawnEffectOnTile(gameState, tileIndex, randomGenerator) {
  const tile = gameState.board.tiles[tileIndex];
  const allEffectTypes = [
    "freeze",
    "black_hole",
    "amplify",
    "amplify_static",
    "lock",
    "decay",
    "stone"
  ];
  for (const effectType of allEffectTypes) {
    if (!canApplyEffectToTile(tile, effectType, gameState)) {
      continue;
    }
    const activeCount = countActiveEffects(gameState, effectType);
    if (!shouldSpawnEffect(effectType, gameState, activeCount, randomGenerator)) {
      continue;
    }
    const effect = createTileEffect(effectType);
    const newTiles = [...gameState.board.tiles];
    const newTile = { ...newTiles[tileIndex] };
    applyEffectToTile(newTile, effect);
    newTiles[tileIndex] = newTile;
    const newGameState = {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles
      }
    };
    return {
      success: true,
      gameState: newGameState,
      effectSpawned: {
        type: effectType,
        position: { row: tile.row, col: tile.col },
        config: effect.config || {}
      }
    };
  }
  return {
    success: false,
    gameState
  };
}
function spawnAuthoritativeEffects(gameState, config) {
  const effectsSpawned = [];
  const newTiles = [...gameState.board.tiles];
  const boardSize = gameState.board.size;
  for (const effectDef of config.effects) {
    const { type, position, config: effectConfig } = effectDef;
    const index = position.row * boardSize + position.col;
    if (index < 0 || index >= newTiles.length) {
      continue;
    }
    const effect = createTileEffect(type, effectConfig);
    const newTile = { ...newTiles[index] };
    applyEffectToTile(newTile, effect);
    newTiles[index] = newTile;
    effectsSpawned.push({
      type,
      position,
      config: effect.config || {}
    });
  }
  return {
    gameState: {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles
      }
    },
    effectsSpawned,
    spawnedCount: effectsSpawned.length
  };
}
function spawnFromPowerCard(gameState, action) {
  const { effectType, targetPosition, config: effectConfig } = action;
  const boardSize = gameState.board.size;
  const index = targetPosition.row * boardSize + targetPosition.col;
  const newTiles = [...gameState.board.tiles];
  const tile = newTiles[index];
  if (index < 0 || index >= newTiles.length) {
    return {
      gameState,
      effectsSpawned: [],
      spawnedCount: 0
    };
  }
  const effect = createTileEffect(effectType, effectConfig);
  const newTile = { ...tile };
  applyEffectToTile(newTile, effect);
  newTiles[index] = newTile;
  return {
    gameState: {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles
      }
    },
    effectsSpawned: [
      {
        type: effectType,
        position: targetPosition,
        config: effect.config || {}
      }
    ],
    spawnedCount: 1
  };
}
function spawnTileEffects(options) {
  const {
    gameState,
    randomGenerator,
    spawnType = "random",
    authoritativeEffects,
    powerCardSpawn,
    targetTileIndex
  } = options;
  switch (spawnType) {
    case "authoritative":
      if (!authoritativeEffects) {
        return { gameState, effectsSpawned: [], spawnedCount: 0 };
      }
      return spawnAuthoritativeEffects(gameState, authoritativeEffects);
    case "powercard":
      if (!powerCardSpawn) {
        return { gameState, effectsSpawned: [], spawnedCount: 0 };
      }
      return spawnFromPowerCard(gameState, powerCardSpawn);
    case "random":
      if (targetTileIndex !== void 0) {
        const result = attemptSpawnEffectOnTile(
          gameState,
          targetTileIndex,
          randomGenerator
        );
        return {
          gameState: result.gameState,
          effectsSpawned: result.effectSpawned ? [result.effectSpawned] : [],
          spawnedCount: result.success ? 1 : 0
        };
      }
      return { gameState, effectsSpawned: [], spawnedCount: 0 };
    case "event":
      return { gameState, effectsSpawned: [], spawnedCount: 0 };
    default:
      return { gameState, effectsSpawned: [], spawnedCount: 0 };
  }
}

// src/eventTriggerState.ts
function initializeEventTriggerStates(eventRules, gameState) {
  if (!eventRules || eventRules.length === 0) {
    return void 0;
  }
  return eventRules.map((rule, index) => {
    const triggerState = {
      id: `trigger_${index}`,
      trigger: rule.trigger,
      effect: rule.effect,
      spawnCount: rule.spawnCount,
      targetPositions: rule.targetPositions,
      status: "idle",
      icon: rule.icon,
      // Copy icon from rule for visual display
      progress: getProgressForTrigger(gameState, rule.trigger)
    };
    return triggerState;
  });
}
function updateTriggerStates(gameState) {
  if (!gameState.eventTriggerStates) {
    return gameState;
  }
  for (const triggerState of gameState.eventTriggerStates) {
    if (triggerState.status === "triggered") {
      continue;
    }
    const conditionMet = isTriggerConditionMet(gameState, triggerState.trigger);
    triggerState.status = conditionMet ? "primed" : "idle";
    triggerState.progress = getProgressForTrigger(
      gameState,
      triggerState.trigger
    );
  }
  return gameState;
}
function markTriggersActivated(gameState, matchingRuleIndices) {
  if (!gameState.eventTriggerStates) {
    return gameState;
  }
  for (const index of matchingRuleIndices) {
    if (index >= 0 && index < gameState.eventTriggerStates.length) {
      const triggerState = gameState.eventTriggerStates[index];
      triggerState.status = "triggered";
      triggerState.progress = getProgressForTrigger(
        gameState,
        triggerState.trigger
      );
    }
  }
  return gameState;
}
function resetTriggeredStates(gameState) {
  if (!gameState.eventTriggerStates) {
    return gameState;
  }
  for (const triggerState of gameState.eventTriggerStates) {
    if (triggerState.status === "triggered") {
      const conditionMet = isTriggerConditionMet(
        gameState,
        triggerState.trigger
      );
      triggerState.status = conditionMet ? "primed" : "idle";
      triggerState.progress = getProgressForTrigger(
        gameState,
        triggerState.trigger
      );
    }
  }
  return gameState;
}
function getProgressForTrigger(gameState, trigger) {
  switch (trigger.event) {
    case "COMBO_BREAK":
      return getComboProgress(gameState, trigger.minCombo);
    case "SCORE_MILESTONE":
      return getScoreProgress(gameState, trigger.threshold);
    case "MERGE_COUNT":
      return getMergeCountProgress(gameState, trigger.count);
    case "MOVE_COUNT":
      return getMoveProgress(gameState, trigger.moves);
    default:
      return void 0;
  }
}
function getComboProgress(gameState, minCombo) {
  return {
    current: gameState.comboMultiplier,
    required: minCombo
  };
}
function getScoreProgress(gameState, threshold) {
  return {
    current: gameState.score,
    required: threshold
  };
}
function getMergeCountProgress(gameState, count) {
  return {
    current: gameState.totalMerges ?? 0,
    required: count
  };
}
function getMoveProgress(gameState, moves) {
  return {
    current: gameState.moveIndex,
    required: moves
  };
}
function isTriggerConditionMet(gameState, trigger) {
  switch (trigger.event) {
    case "COMBO_BREAK":
      return gameState.comboMultiplier >= trigger.minCombo;
    case "SCORE_MILESTONE":
      return gameState.score >= trigger.threshold;
    case "MERGE_COUNT":
      return (gameState.totalMerges ?? 0) >= trigger.count;
    case "MOVE_COUNT":
      return gameState.moveIndex >= trigger.moves;
    default:
      return false;
  }
}

// src/globalEffects.ts
function processGlobalEffects(gameState, gameEvent, randomGenerator) {
  if (!gameState.globalEffects || gameState.globalEffects.length === 0) {
    return gameState;
  }
  let modifiedState = { ...gameState };
  if (gameEvent.type === "MOVE_COMPLETED") {
    modifiedState.globalEffects = (modifiedState.globalEffects || []).map((effect) => {
      const newMovesRemaining = Math.max(0, effect.movesRemaining - 1);
      if (newMovesRemaining === 0) {
        return null;
      }
      const newSeed = randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 1e4;
      const offsetVariation = 15 + randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 10;
      return {
        ...effect,
        movesRemaining: newMovesRemaining,
        filterConfig: {
          ...effect.filterConfig,
          seed: newSeed,
          offset: offsetVariation
        }
      };
    }).filter(Boolean);
  }
  return modifiedState;
}
function createGlobalEffect(rule, triggerId, randomGenerator) {
  if (!rule.globalEffect) {
    return null;
  }
  const { type, duration, config } = rule.globalEffect;
  const effectIdSeed = Math.floor(
    randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 1e6
  );
  const defaultConfig = {
    slices: 10,
    offset: 75,
    direction: 0,
    fillMode: 0,
    seed: randomGenerator.getRandom(RNG_NAMESPACES.EFFECT_SPAWN) * 1e4,
    average: false,
    minSize: 8,
    sampleSize: 512
  };
  return {
    id: `${triggerId}_effect_${effectIdSeed}`,
    type,
    movesRemaining: duration,
    maxMoves: duration,
    triggerId,
    filterConfig: {
      ...defaultConfig,
      ...config
    }
  };
}

// src/eventSpawnProcessor.ts
function matchesEventTrigger(event, trigger) {
  switch (trigger.event) {
    case "COMBO_BREAK":
      if (event.type === "COMBO_BREAK" || event.type === "COMBO_BREAK_ATTEMPTED") {
        const previousCombo = event.previousCombo ?? 0;
        return previousCombo >= trigger.minCombo;
      }
      return false;
    case "SCORE_MILESTONE":
      if (event.type === "SCORE_UPDATE") {
        return true;
      }
      return false;
    case "MERGE_COUNT":
      if (event.type === "TILE_MERGE") {
        return true;
      }
      return false;
    case "MOVE_COUNT":
      if (event.type === "TURN_END" || event.type === "MOVE_COMPLETED") {
        return true;
      }
      return false;
    default:
      return false;
  }
}
function processEventSpawnRules(gameState, event, rules, randomGenerator, excludedPositions = []) {
  const matchingRuleIndices = [];
  const effectsToSpawn = [];
  for (let ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
    const rule = rules[ruleIndex];
    const matched = matchesEventTrigger(event, rule.trigger);
    if (!matched) {
      continue;
    }
    const { effect: effectType, spawnCount, targetPositions = "random" } = rule;
    let validPositions = findValidSpawnPositions(gameState, effectType);
    validPositions = validPositions.filter((tileIndex) => {
      const tile = gameState.board.tiles[tileIndex];
      return !excludedPositions.some(
        (excludedPos) => excludedPos.row === tile.row && excludedPos.col === tile.col
      );
    });
    if (validPositions.length === 0) {
      continue;
    }
    matchingRuleIndices.push(ruleIndex);
    for (let i = 0; i < spawnCount; i++) {
      const tileIndex = selectSpawnPosition(
        gameState,
        validPositions,
        targetPositions,
        randomGenerator
      );
      if (tileIndex === null) {
        break;
      }
      const tile = gameState.board.tiles[tileIndex];
      effectsToSpawn.push({
        type: effectType,
        position: { row: tile.row, col: tile.col }
      });
      const indexPos = validPositions.indexOf(tileIndex);
      if (indexPos > -1) {
        validPositions.splice(indexPos, 1);
      }
    }
  }
  let modifiedState = gameState;
  if (effectsToSpawn.length > 0) {
    const authConfig = {
      effects: effectsToSpawn
    };
    const result = spawnTileEffects({
      gameState: modifiedState,
      randomGenerator,
      spawnType: "authoritative",
      authoritativeEffects: authConfig
    });
    modifiedState = result.gameState;
  }
  if (matchingRuleIndices.length > 0) {
    modifiedState = markTriggersActivated(modifiedState, matchingRuleIndices);
  }
  for (const ruleIndex of matchingRuleIndices) {
    const rule = rules[ruleIndex];
    if (rule.globalEffect && modifiedState.eventTriggerStates) {
      const triggerState = modifiedState.eventTriggerStates[ruleIndex];
      if (triggerState) {
        const globalEffect = createGlobalEffect(
          rule,
          triggerState.id,
          randomGenerator
        );
        if (globalEffect) {
          if (!modifiedState.globalEffects) {
            modifiedState.globalEffects = [];
          }
          modifiedState.globalEffects = [
            ...modifiedState.globalEffects,
            globalEffect
          ];
        }
      }
    }
  }
  return modifiedState;
}

// src/totemLogic.ts
var processTotemEffects = (gameState, gameEvent, randomGenerator) => {
  const extendedState = gameState;
  const { totems } = extendedState;
  if (!totems || !totems.active || totems.active.length === 0) {
    return gameState;
  }
  let modifiedState = {
    ...extendedState,
    totems: {
      ...extendedState.totems,
      active: extendedState.totems.active.map((totem) => ({
        ...totem,
        config: totem.config ? { ...totem.config } : {
          maxTallyMarks: 0,
          mergesRemaining: 0,
          movesRemaining: 0,
          swipesRemaining: 0,
          tallyMarks: 0,
          spawnValue: 0
        }
      }))
    }
  };
  const extendedEvent = gameEvent;
  if (extendedEvent.type === "TILE_SPAWN") {
    const spawnBoosters = modifiedState.totems.active.filter(
      (totem) => isSpawnBooster(totem.type)
    );
    if (spawnBoosters.length > 0) {
      const highestPriorityBooster = spawnBoosters.reduce(
        (highest, current) => {
          return getSpawnBoosterPriority(current.type) > getSpawnBoosterPriority(highest.type) ? current : highest;
        }
      );
      modifiedState = processSpawnBooster(
        modifiedState,
        highestPriorityBooster,
        extendedEvent
      );
      for (const totem of modifiedState.totems.active) {
        if (!isSpawnBooster(totem.type)) {
          modifiedState = processTotemByType(
            modifiedState,
            totem,
            extendedEvent,
            randomGenerator
          );
        }
      }
    } else {
      for (const totem of modifiedState.totems.active) {
        modifiedState = processTotemByType(
          modifiedState,
          totem,
          extendedEvent,
          randomGenerator
        );
      }
    }
  } else {
    for (const totem of modifiedState.totems.active) {
      modifiedState = processTotemByType(
        modifiedState,
        totem,
        extendedEvent,
        randomGenerator
      );
    }
  }
  modifiedState = checkTotemDespawnConditions(modifiedState, extendedEvent);
  return modifiedState;
};
var processTotemByType = (gameState, totem, gameEvent, randomGenerator) => {
  switch (totem.type) {
    case "combo_saver":
      return processComboSaver(gameState, totem, gameEvent);
    case "spawn_booster_2x":
    case "spawn_booster_4x":
    case "spawn_booster_8x":
      return processSpawnBooster(gameState, totem, gameEvent);
    case "momentum_idol":
      return processMomentumIdol(gameState, totem, gameEvent);
    case "magnet_core":
      return processMagnetCore(gameState, totem, gameEvent);
    case "void_gate":
      return processVoidGate(gameState, totem, gameEvent);
    case "ghost_merge":
      return processGhostMerge(gameState, totem, gameEvent, randomGenerator);
    case "scavenger":
      return processScavenger(gameState, totem, gameEvent);
    case "chrono_anchor":
      return processChronoAnchor(gameState);
    default:
      console.warn(`Unknown totem type: ${totem.type}`);
      return gameState;
  }
};
var processComboSaver = (gameState, totem, gameEvent) => {
  if (gameEvent.type === "COMBO_BREAK_ATTEMPTED") {
    if (!totem.config) {
      totem.config = {};
    }
    totem.config.tallyMarks = (totem.config.tallyMarks || 0) + 1;
    if (gameEvent.previousCombo !== void 0) {
      gameState.comboMultiplier = gameEvent.previousCombo;
    }
    const totemDef = Object.values(TOTEM_TYPES).find(
      (t) => t.id === totem.type
    );
    if (totem.config.tallyMarks >= (totemDef?.maxTallyMarks || 3)) {
      gameState.totems.active = gameState.totems.active.filter(
        (t) => t.id !== totem.id
      );
    }
  }
  return gameState;
};
var processSpawnBooster = (gameState, totem, gameEvent) => {
  if (gameEvent.type === "TILE_SPAWN") {
    const totemDefinition = Object.values(TOTEM_TYPES).find(
      (t) => t.id === totem.type
    );
    if (totemDefinition && totemDefinition.spawnValue) {
      gameEvent.tileValue = totemDefinition.spawnValue;
    }
    if (!totem.config) {
      totem.config = {};
    }
    if (totem.config.movesRemaining !== void 0) {
      totem.config.movesRemaining = Math.max(
        0,
        totem.config.movesRemaining - 1
      );
    }
  }
  return gameState;
};
var processMomentumIdol = (gameState, totem, gameEvent) => {
  if (gameEvent.type === "COMBO_INCREMENT") {
    gameEvent.incrementAmount = (gameEvent.incrementAmount || 0) + 1;
  } else if (gameEvent.type === "MOVE_COMPLETED" && totem.config?.movesRemaining !== void 0) {
    totem.config.movesRemaining = Math.max(0, totem.config.movesRemaining - 1);
  }
  return gameState;
};
var processMagnetCore = (gameState, totem, gameEvent) => {
  if (gameEvent.type === "POST_SPAWN") {
    const newTiles = [...gameState.board.tiles];
    const BOARD_SIZE = 4;
    const centerPositions = [
      { row: 1, col: 1 },
      { row: 1, col: 2 },
      { row: 2, col: 1 },
      { row: 2, col: 2 }
    ];
    const getTile2 = (tiles, row, col) => tiles[row * BOARD_SIZE + col];
    const setTile2 = (tiles, row, col, tile) => {
      tiles[row * BOARD_SIZE + col] = tile;
    };
    const getDistanceToCenter = (row, col) => {
      let minDistance = Infinity;
      for (const center of centerPositions) {
        const distance = Math.abs(row - center.row) + Math.abs(col - center.col);
        minDistance = Math.min(minDistance, distance);
      }
      return minDistance;
    };
    const getNearestCenter = (row, col) => {
      let nearestCenter = centerPositions[0];
      let minDistance = Infinity;
      for (const center of centerPositions) {
        const distance = Math.abs(row - center.row) + Math.abs(col - center.col);
        if (distance < minDistance) {
          minDistance = distance;
          nearestCenter = center;
        }
      }
      return nearestCenter;
    };
    const movedTiles = /* @__PURE__ */ new Set();
    let moved = true;
    while (moved) {
      moved = false;
      const tilePositions = [];
      for (let row = 0; row < BOARD_SIZE; row++) {
        for (let col = 0; col < BOARD_SIZE; col++) {
          const tile = getTile2(newTiles, row, col);
          if (tile && !tile.isEmpty) {
            tilePositions.push({
              row,
              col,
              tile,
              distance: getDistanceToCenter(row, col)
            });
          }
        }
      }
      tilePositions.sort((a, b) => b.distance - a.distance);
      for (const { row, col, tile } of tilePositions) {
        const nearestCenter = getNearestCenter(row, col);
        let newRow = row;
        let newCol = col;
        const rowDiff = nearestCenter.row - row;
        const colDiff = nearestCenter.col - col;
        if (Math.abs(rowDiff) > Math.abs(colDiff)) {
          if (rowDiff > 0) {
            newRow = row + 1;
          } else if (rowDiff < 0) {
            newRow = row - 1;
          }
        } else if (Math.abs(colDiff) > 0) {
          if (colDiff > 0) {
            newCol = col + 1;
          } else if (colDiff < 0) {
            newCol = col - 1;
          }
        }
        if (newRow >= 0 && newRow < BOARD_SIZE && newCol >= 0 && newCol < BOARD_SIZE && getTile2(newTiles, newRow, newCol).isEmpty) {
          setTile2(newTiles, row, col, createEmptyTile(row, col));
          setTile2(newTiles, newRow, newCol, tile);
          movedTiles.add(newRow * BOARD_SIZE + newCol);
          moved = true;
        }
      }
    }
    for (let i = 0; i < newTiles.length; i++) {
      if (newTiles[i] && !newTiles[i].isEmpty && movedTiles.has(i)) {
        if (newTiles[i].status !== "new" && newTiles[i].status !== "merged") {
          newTiles[i] = {
            ...newTiles[i],
            status: "magnetized",
            meta: { ...newTiles[i].meta }
          };
        }
      }
    }
    gameState = {
      ...gameState,
      board: {
        ...gameState.board,
        tiles: newTiles
      }
    };
    if (!totem.config) {
      totem.config = {};
    }
    if (totem.config.movesRemaining !== void 0) {
      totem.config.movesRemaining = Math.max(
        0,
        totem.config.movesRemaining - 1
      );
    }
  }
  return gameState;
};
var processVoidGate = (gameState, totem, gameEvent) => {
  if (gameEvent.type === "POST_SWIPE") {
    if (!gameEvent.mergeOccurred) {
      const tiles = gameState.board.tiles;
      let lowestIndex = -1;
      let lowestValue = Infinity;
      let nonEmptyCount = 0;
      for (let i = 0; i < tiles.length; i++) {
        if (tiles[i] && !tiles[i].isEmpty) {
          nonEmptyCount++;
          if (tiles[i].value < lowestValue) {
            lowestValue = tiles[i].value;
            lowestIndex = i;
          }
        }
      }
      if (lowestIndex !== -1 && nonEmptyCount > 1) {
        const row = Math.floor(lowestIndex / 4);
        const col = lowestIndex % 4;
        const newTiles = [...tiles];
        newTiles[lowestIndex] = createEmptyTile(row, col);
        gameState = {
          ...gameState,
          board: {
            ...gameState.board,
            tiles: newTiles
          }
        };
      }
    }
    if (!totem.config) {
      totem.config = {};
    }
    if (totem.config.movesRemaining !== void 0) {
      totem.config.movesRemaining = Math.max(
        0,
        totem.config.movesRemaining - 1
      );
    }
  }
  return gameState;
};
var processGhostMerge = (gameState, totem, gameEvent, randomGenerator) => {
  if (gameEvent.type === "POST_SWIPE" && gameEvent.mergeOccurred && totem.config?.mergesRemaining !== void 0 && totem.config.mergesRemaining > 0) {
    const mergedTiles = [];
    gameState.board.tiles.forEach((tile, index) => {
      if (tile && tile.status === "merged") {
        mergedTiles.push({
          index,
          row: Math.floor(index / 4),
          col: index % 4,
          value: tile.value
        });
      }
    });
    if (mergedTiles.length > 0) {
      const firstMerge = mergedTiles[0];
      const emptyCells = [];
      gameState.board.tiles.forEach((tile, index) => {
        if (tile?.isEmpty) {
          emptyCells.push({
            index,
            row: Math.floor(index / 4),
            col: index % 4
          });
        }
      });
      if (emptyCells.length > 0) {
        const randomCell = emptyCells[Math.floor(
          randomGenerator.getRandom(RNG_NAMESPACES.TOTEM_SPAWN) * emptyCells.length
        )];
        const ghostTile = {
          isEmpty: false,
          value: firstMerge.value,
          status: "spawned",
          // Use spawned status to show it's a special tile
          meta: {
            isGhost: true
            // Mark as ghost merge tile for potential future use
          },
          ...indexToRowCol(randomCell.index, gameState.board.size),
          effect: void 0
        };
        gameState.board.tiles[randomCell.index] = ghostTile;
        console.log(
          `Ghost Merge: Created tile with value ${firstMerge.value} at position (${randomCell.row}, ${randomCell.col})`
        );
      }
      totem.config.mergesRemaining = Math.max(
        0,
        totem.config.mergesRemaining - 1
      );
    }
  }
  return gameState;
};
var processScavenger = (gameState, totem, gameEvent) => {
  if (gameEvent.type === "POST_SWIPE" && gameEvent.mergedTilesCount !== void 0 && gameEvent.mergedTilesCount > 0 && totem.config?.mergesRemaining !== void 0 && totem.config.mergesRemaining > 0) {
    gameEvent.shardsMultiplier = (gameEvent.shardsMultiplier || 1) * 2;
    totem.config.mergesRemaining = Math.max(
      0,
      totem.config.mergesRemaining - 1
    );
  }
  return gameState;
};
var processChronoAnchor = (gameState) => {
  return gameState;
};
var checkTotemDespawnConditions = (gameState, gameEvent) => {
  const activeTotems = gameState.totems.active.filter((totem) => {
    if (gameEvent.type === "MOVE_COMPLETED" && totem.config?.movesRemaining !== void 0) {
      return totem.config.movesRemaining > 0;
    }
    if (gameEvent.type === "POST_SWIPE" && gameEvent.mergeOccurred && totem.config?.mergesRemaining !== void 0) {
      return totem.config.mergesRemaining > 0;
    }
    if (totem.config?.maxTallyMarks !== void 0) {
      return (totem.config.tallyMarks || 0) < totem.config.maxTallyMarks;
    }
    return true;
  });
  if (activeTotems.length !== gameState.totems.active.length) {
    gameState.totems.active = activeTotems;
  }
  return gameState;
};
var initializeTotemConfig = (totemType, customConfig = {}) => {
  const totemDefinition = Object.values(TOTEM_TYPES).find(
    (t) => t.id === totemType
  );
  if (!totemDefinition) {
    throw new Error(`Unknown totem type: ${totemType}`);
  }
  const config = { ...customConfig };
  if (totemDefinition.defaultMoves !== void 0) {
    config.movesRemaining = config.movesRemaining || totemDefinition.defaultMoves;
  }
  if (totemDefinition.defaultSwipes !== void 0) {
    config.swipesRemaining = config.swipesRemaining || totemDefinition.defaultSwipes;
  }
  if (totemDefinition.defaultMerges !== void 0) {
    config.mergesRemaining = config.mergesRemaining || totemDefinition.defaultMerges;
  }
  if (totemDefinition.maxTallyMarks !== void 0) {
    config.tallyMarks = config.tallyMarks || 0;
    config.maxTallyMarks = totemDefinition.maxTallyMarks;
  }
  if (totemDefinition.spawnValue !== void 0) {
    config.spawnValue = totemDefinition.spawnValue;
  }
  return config;
};
var getSpawnBoosterPriority = (totemType) => {
  const priorities = {
    spawn_booster_8x: 3,
    // Highest priority (spawns 16s)
    spawn_booster_4x: 2,
    // Medium priority (spawns 8s)
    spawn_booster_2x: 1
    // Lowest priority (spawns 4s)
  };
  return priorities[totemType] || 0;
};
var isSpawnBooster = (totemType) => {
  return ["spawn_booster_2x", "spawn_booster_4x", "spawn_booster_8x"].includes(
    totemType
  );
};
var testSpawnBoosterPrioritization = () => {
  console.log("=== Spawn Booster Prioritization Tests ===");
  const createTestGameState = (activeTotemTypes) => {
    return {
      totems: {
        active: activeTotemTypes.map((type, index) => ({
          id: `test_totem_${index}`,
          type,
          name: "",
          description: "",
          active: true,
          config: {
            movesRemaining: 5
          }
        }))
      }
    };
  };
  const createSpawnEvent = () => ({
    type: "TILE_SPAWN",
    tileValue: 2
    // Default spawn value
  });
  console.log("\n--- Test 1: 8x vs 4x vs 2x (8x should win) ---");
  const gameState1 = createTestGameState([
    "spawn_booster_2x",
    "spawn_booster_4x",
    "spawn_booster_8x"
  ]);
  const spawnEvent1 = createSpawnEvent();
  const testRng = new RandomGenerator(
    {
      "tile-gen": 12345,
      shuffle: 12346,
      "effect-spawn": 12347,
      "totem-spawn": 12348,
      "card-draw": 12349
    },
    {
      "tile-gen": 0,
      shuffle: 0,
      "effect-spawn": 0,
      "totem-spawn": 0,
      "card-draw": 0
    }
  );
  const result1 = processTotemEffects(gameState1, spawnEvent1, testRng);
  console.log("Original spawn value:", 2);
  console.log("Final spawn value:", spawnEvent1.tileValue);
  console.log(
    "Expected:",
    16,
    "Actual:",
    spawnEvent1.tileValue,
    "\u2713",
    spawnEvent1.tileValue === 16
  );
  const extendedResult1 = result1;
  const totem8x = extendedResult1.totems.active.find(
    (t) => t.type === "spawn_booster_8x"
  );
  const totem4x = extendedResult1.totems.active.find(
    (t) => t.type === "spawn_booster_4x"
  );
  const totem2x = extendedResult1.totems.active.find(
    (t) => t.type === "spawn_booster_2x"
  );
  console.log(
    "8x moves remaining:",
    totem8x?.config?.movesRemaining,
    "(should be 4)"
  );
  console.log(
    "4x moves remaining:",
    totem4x?.config?.movesRemaining,
    "(should be 5)"
  );
  console.log(
    "2x moves remaining:",
    totem2x?.config?.movesRemaining,
    "(should be 5)"
  );
  console.log("\n=== All Tests Complete ===");
};
if (typeof window !== "undefined") {
  window.testSpawnBoosterPrioritization = testSpawnBoosterPrioritization;
}

// src/merge.ts
function swipeLeft(newTiles, mergedTiles, boardSize) {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles = [];
  const effectConsumptions = [];
  const removedLockPositions = [];
  for (let row = 0; row < boardSize; row++) {
    for (let col = 1; col < boardSize; col++) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;
      if (!canValueMove(tile)) continue;
      let targetCol = col;
      for (let checkCol = col - 1; checkCol >= 0; checkCol--) {
        const checkTile = getTile(newTiles, row, checkCol, boardSize);
        if (isBlackHoleTile(checkTile)) {
          targetCol = checkCol;
          continue;
        }
        if (checkTile.isEmpty) {
          targetCol = checkCol;
        } else if (checkTile.value === tile.value && !mergedTiles.has(rowColToIndex(row, checkCol, boardSize)) && canTilesMergeTogether(tile, checkTile)) {
          targetCol = checkCol;
          break;
        } else {
          break;
        }
      }
      if (targetCol !== col) {
        const targetTile = getTile(newTiles, row, targetCol, boardSize);
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier ? findBlackHoleInPath(
          newTiles,
          boardSize,
          { row, col },
          { row, col: targetCol }
        ) : null;
        if (targetIsBarrier || blackHolePos) {
          const blackHolePosition = targetIsBarrier ? { row, col: targetCol } : blackHolePos;
          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize
          );
          const { scoreLoss: loss, shouldImplode } = processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;
          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition
            }
          });
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }
          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (!targetTile.isEmpty && targetTile.value === tile.value && canTilesMergeTogether(tile, targetTile)) {
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue
            );
            effectConsumptions.push(...mergeResult.consumedEffects);
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }
            const mergedTile = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row,
              col: targetCol
            };
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }
            setTile(newTiles, mergedTile, boardSize);
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(row, targetCol, boardSize));
            mergedTilesCount++;
          } else {
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const targetEffectToTransfer = getEffectToPreserveAtSource(targetTile);
            tile.col = targetCol;
            tile.row = row;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }
  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions
  };
}
function swipeRight(newTiles, mergedTiles, boardSize) {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles = [];
  const effectConsumptions = [];
  const removedLockPositions = [];
  for (let row = 0; row < boardSize; row++) {
    for (let col = boardSize - 2; col >= 0; col--) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;
      if (!canValueMove(tile)) continue;
      let targetCol = col;
      for (let checkCol = col + 1; checkCol < boardSize; checkCol++) {
        const checkTile = getTile(newTiles, row, checkCol, boardSize);
        if (isBlackHoleTile(checkTile)) {
          targetCol = checkCol;
          continue;
        }
        if (checkTile.isEmpty) {
          targetCol = checkCol;
        } else if (checkTile.value === tile.value && !mergedTiles.has(rowColToIndex(row, checkCol, boardSize)) && canTilesMergeTogether(tile, checkTile)) {
          targetCol = checkCol;
          break;
        } else {
          break;
        }
      }
      if (targetCol !== col) {
        const targetTile = getTile(newTiles, row, targetCol, boardSize);
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier ? findBlackHoleInPath(
          newTiles,
          boardSize,
          { row, col },
          { row, col: targetCol }
        ) : null;
        if (targetIsBarrier || blackHolePos) {
          const blackHolePosition = targetIsBarrier ? { row, col: targetCol } : blackHolePos;
          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize
          );
          const { scoreLoss: loss, shouldImplode } = processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;
          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition
            }
          });
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }
          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (!targetTile.isEmpty && targetTile.value === tile.value && canTilesMergeTogether(tile, targetTile)) {
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue
            );
            effectConsumptions.push(...mergeResult.consumedEffects);
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }
            const mergedTile = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row,
              col: targetCol
            };
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }
            setTile(newTiles, mergedTile, boardSize);
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(row, targetCol, boardSize));
            mergedTilesCount++;
          } else {
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const targetEffectToTransfer = getEffectToPreserveAtSource(targetTile);
            tile.col = targetCol;
            tile.row = row;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }
  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions
  };
}
function swipeUp(newTiles, mergedTiles, boardSize) {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles = [];
  const effectConsumptions = [];
  const removedLockPositions = [];
  for (let col = 0; col < boardSize; col++) {
    for (let row = 1; row < boardSize; row++) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;
      if (!canValueMove(tile)) continue;
      let targetRow = row;
      for (let checkRow = row - 1; checkRow >= 0; checkRow--) {
        const checkTile = getTile(newTiles, checkRow, col, boardSize);
        if (isBlackHoleTile(checkTile)) {
          targetRow = checkRow;
          continue;
        }
        if (checkTile.isEmpty) {
          targetRow = checkRow;
        } else if (checkTile.value === tile.value && !mergedTiles.has(rowColToIndex(checkRow, col, boardSize)) && canTilesMergeTogether(tile, checkTile)) {
          targetRow = checkRow;
          break;
        } else {
          break;
        }
      }
      if (targetRow !== row) {
        const targetTile = getTile(newTiles, targetRow, col, boardSize);
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier ? findBlackHoleInPath(
          newTiles,
          boardSize,
          { row, col },
          { row: targetRow, col }
        ) : null;
        if (targetIsBarrier || blackHolePos) {
          const blackHolePosition = targetIsBarrier ? { row: targetRow, col } : blackHolePos;
          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize
          );
          const { scoreLoss: loss, shouldImplode } = processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;
          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition
            }
          });
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }
          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (!targetTile.isEmpty && targetTile.value === tile.value && canTilesMergeTogether(tile, targetTile)) {
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue
            );
            effectConsumptions.push(...mergeResult.consumedEffects);
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }
            const mergedTile = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row: targetRow,
              col
            };
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }
            setTile(newTiles, mergedTile, boardSize);
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(targetRow, col, boardSize));
            mergedTilesCount++;
          } else {
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const targetEffectToTransfer = getEffectToPreserveAtSource(targetTile);
            tile.row = targetRow;
            tile.col = col;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }
  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions
  };
}
function swipeDown(newTiles, mergedTiles, boardSize) {
  let moved = false;
  let score = 0;
  let scoreLoss = 0;
  let mergedTilesCount = 0;
  const destroyedTiles = [];
  const effectConsumptions = [];
  const removedLockPositions = [];
  for (let col = 0; col < boardSize; col++) {
    for (let row = boardSize - 2; row >= 0; row--) {
      const tile = getTile(newTiles, row, col, boardSize);
      if (!tile || tile.isEmpty) continue;
      if (!canValueMove(tile)) continue;
      let targetRow = row;
      for (let checkRow = row + 1; checkRow < boardSize; checkRow++) {
        const checkTile = getTile(newTiles, checkRow, col, boardSize);
        if (isBlackHoleTile(checkTile)) {
          targetRow = checkRow;
          continue;
        }
        if (checkTile.isEmpty) {
          targetRow = checkRow;
        } else if (checkTile.value === tile.value && !mergedTiles.has(rowColToIndex(checkRow, col, boardSize)) && canTilesMergeTogether(tile, checkTile)) {
          targetRow = checkRow;
          break;
        } else {
          break;
        }
      }
      if (targetRow !== row) {
        const targetTile = getTile(newTiles, targetRow, col, boardSize);
        const targetIsBarrier = isBlackHoleTile(targetTile);
        const blackHolePos = !targetIsBarrier ? findBlackHoleInPath(
          newTiles,
          boardSize,
          { row, col },
          { row: targetRow, col }
        ) : null;
        if (targetIsBarrier || blackHolePos) {
          const blackHolePosition = targetIsBarrier ? { row: targetRow, col } : blackHolePos;
          const blackHoleTile = getTile(
            newTiles,
            blackHolePosition.row,
            blackHolePosition.col,
            boardSize
          );
          const { scoreLoss: loss, shouldImplode } = processBlackHoleDestruction(tile, blackHoleTile);
          scoreLoss += loss;
          destroyedTiles.push({
            position: { row, col },
            value: loss,
            destroyedBy: {
              type: "black_hole",
              position: blackHolePosition
            }
          });
          if (shouldImplode && blackHoleTile.effect) {
            blackHoleTile.effect.active = false;
          }
          setTile(newTiles, createEmptyTile(row, col), boardSize);
          moved = true;
        } else {
          moved = true;
          if (!targetTile.isEmpty && targetTile.value === tile.value && canTilesMergeTogether(tile, targetTile)) {
            const baseValue = tile.value * 2;
            const mergeResult = processTileEffectsOnMerge(
              targetTile,
              baseValue
            );
            effectConsumptions.push(...mergeResult.consumedEffects);
            const lockRemoved = processLockTriggerOnMerge(targetTile);
            if (lockRemoved) {
              removedLockPositions.push(lockRemoved);
            }
            const mergedTile = {
              isEmpty: false,
              value: mergeResult.finalValue,
              status: "merged",
              meta: {},
              row: targetRow,
              col
            };
            if (targetTile.effect && targetTile.effect.active) {
              mergedTile.effect = targetTile.effect;
            }
            setTile(newTiles, mergedTile, boardSize);
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
            score += mergeResult.finalValue;
            mergedTiles.add(rowColToIndex(targetRow, col, boardSize));
            mergedTilesCount++;
          } else {
            const sourceEffectToPreserve = getEffectToPreserveAtSource(tile);
            const targetEffectToTransfer = getEffectToPreserveAtSource(targetTile);
            tile.row = targetRow;
            tile.col = col;
            if (sourceEffectToPreserve) {
              delete tile.effect;
            }
            if (targetEffectToTransfer) {
              tile.effect = targetEffectToTransfer;
            }
            setTile(newTiles, tile, boardSize);
            const emptyTile = createEmptyTile(row, col);
            if (sourceEffectToPreserve) {
              emptyTile.effect = sourceEffectToPreserve;
            }
            setTile(newTiles, emptyTile, boardSize);
          }
        }
      }
    }
  }
  return {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    mergedTiles,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions
  };
}
function performSwipe(gameState, direction, randomGenerator) {
  let result = { ...gameState };
  result = processTotemEffects(
    result,
    {
      type: "PRE_SWIPE"},
    randomGenerator
  );
  const newTiles = [...result.board.tiles];
  newTiles.forEach((tile) => {
    if (tile) {
      tile.status = "normal";
    }
  });
  const mergedTiles = /* @__PURE__ */ new Set();
  let swipeResult;
  switch (direction) {
    case "left":
      swipeResult = swipeLeft(newTiles, mergedTiles, gameState.board.size);
      break;
    case "right":
      swipeResult = swipeRight(newTiles, mergedTiles, gameState.board.size);
      break;
    case "up":
      swipeResult = swipeUp(newTiles, mergedTiles, gameState.board.size);
      break;
    case "down":
      swipeResult = swipeDown(newTiles, mergedTiles, gameState.board.size);
      break;
    default:
      swipeResult = {
        moved: false,
        score: 0,
        scoreLoss: 0,
        mergedTilesCount: 0,
        mergedTiles,
        destroyedTiles: [],
        effectConsumptions: [],
        removedLockPositions: []
      };
  }
  const {
    moved,
    score,
    scoreLoss,
    mergedTilesCount,
    destroyedTiles,
    effectConsumptions,
    removedLockPositions
  } = swipeResult;
  const netScore = score - scoreLoss;
  result = {
    ...result,
    board: {
      ...result.board,
      tiles: newTiles
    }
  };
  const removedEffectPositions = [...removedLockPositions];
  if (mergedTilesCount > 0) {
    newTiles.forEach((tile, index) => {
      if (tile.status === "merged") {
        const { row, col } = indexToRowCol(index, gameState.board.size);
        const freezeRemoved = processFreezeRemovalFromAdjacentMerge(result, {
          row,
          col
        });
        removedEffectPositions.push(...freezeRemoved);
      }
    });
  }
  result = processTotemEffects(
    result,
    {
      type: "POST_SWIPE",
      mergeOccurred: mergedTilesCount > 0},
    randomGenerator
  );
  result = processTotemEffects(
    result,
    { type: "MOVE_COMPLETED" },
    randomGenerator
  );
  result = processTotemEffects(
    result,
    { type: "SWIPE_COMPLETED"},
    randomGenerator
  );
  if (netScore > 0) {
    const scoreUpdateEvent = {
      type: "SCORE_UPDATE"};
    const eventRules = gameState.scenarioConfig?.eventRules;
    if (eventRules && eventRules.length > 0) {
      result = processEventSpawnRules(
        result,
        scoreUpdateEvent,
        eventRules,
        randomGenerator,
        removedEffectPositions
        // Exclude positions where effects were just removed by merges
      );
    }
  }
  return {
    gameState: result,
    moved,
    score: netScore,
    mergedTilesCount,
    removedEffectPositions,
    destroyedTiles,
    effectConsumptions
  };
}
function addRandomTileWithEffects(gameState, randomGenerator) {
  const emptyIndices = gameState.board.tiles.map((tile, index) => {
    const hasEffect = tile.effect && tile.effect.active && tile.effect.type !== "none";
    return tile.isEmpty && !hasEffect ? index : -1;
  }).filter((index) => index !== -1);
  if (emptyIndices.length === 0) {
    return { gameState };
  }
  const randomIndex = emptyIndices[Math.floor(
    randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) * emptyIndices.length
  )];
  const value = randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) < 0.9 ? 2 : 4;
  ({
    row: Math.floor(randomIndex / gameState.board.size),
    col: randomIndex % gameState.board.size
  });
  const spawnEvent = {
    type: "TILE_SPAWN",
    tileValue: value};
  let modifiedState = processTotemEffects(
    gameState,
    spawnEvent,
    randomGenerator
  );
  const finalValue = spawnEvent.tileValue ?? 0;
  const newTiles = [...modifiedState.board.tiles];
  newTiles[randomIndex] = {
    isEmpty: false,
    value: finalValue,
    status: "new",
    meta: {},
    ...indexToRowCol(randomIndex, gameState.board.size)
  };
  modifiedState = {
    ...modifiedState,
    board: {
      ...modifiedState.board,
      tiles: newTiles
    }
  };
  modifiedState = processTotemEffects(
    modifiedState,
    {
      type: "POST_SPAWN"},
    randomGenerator
  );
  const spawnResult = attemptSpawnEffectOnTile(
    modifiedState,
    randomIndex,
    randomGenerator
  );
  if (spawnResult.success && spawnResult.effectSpawned) {
    modifiedState = processTotemEffects(
      spawnResult.gameState,
      {
        type: "TILE_EFFECT_APPLIED",
        effectApplied: {
          type: spawnResult.effectSpawned.type,
          position: spawnResult.effectSpawned.position,
          config: spawnResult.effectSpawned.config
        }
      },
      randomGenerator
    );
    return {
      gameState: modifiedState,
      effectSpawned: {
        type: spawnResult.effectSpawned.type,
        position: spawnResult.effectSpawned.position
      }
    };
  } else {
    modifiedState = spawnResult.gameState;
    return { gameState: modifiedState };
  }
}
function addRandomValue(tiles, randomGenerator, _boardSize) {
  const emptyIndices = tiles.map((tile, index) => {
    const hasEffect = tile.effect && tile.effect.active && tile.effect.type !== "none";
    return tile.isEmpty && !hasEffect ? index : -1;
  }).filter((index) => index !== -1);
  if (emptyIndices.length === 0) {
    return false;
  }
  const randomIndex = emptyIndices[Math.floor(
    randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) * emptyIndices.length
  )];
  const value = randomGenerator.getRandom(RNG_NAMESPACES.TILE_GEN) < 0.9 ? 2 : 4;
  tiles[randomIndex] = {
    ...tiles[randomIndex],
    isEmpty: false,
    status: "new",
    meta: {},
    value
  };
  return true;
}
function updateComboMultiplier(gameState, mergedTilesCount, randomGenerator) {
  if (mergedTilesCount === 0) {
    const previousCombo = gameState.comboMultiplier;
    const resetState = { ...gameState, comboMultiplier: 0 };
    let modifiedState2 = processTotemEffects(
      resetState,
      {
        type: "COMBO_BREAK_ATTEMPTED",
        previousCombo: gameState.comboMultiplier
        // Pass the original combo value
      },
      randomGenerator
    );
    modifiedState2 = updateTriggerStates(modifiedState2);
    if (modifiedState2.comboMultiplier === 0 && previousCombo > 0) {
      const comboBreakEvent = {
        type: "COMBO_BREAK",
        previousCombo
      };
      const eventRules = gameState.scenarioConfig?.eventRules;
      if (eventRules && eventRules.length > 0) {
        modifiedState2 = processEventSpawnRules(
          modifiedState2,
          comboBreakEvent,
          eventRules,
          randomGenerator
        );
      }
    }
    return modifiedState2;
  }
  const increment = mergedTilesCount;
  const incrementEvent = {
    type: "COMBO_INCREMENT",
    incrementAmount: increment
  };
  let modifiedState = processTotemEffects(
    gameState,
    incrementEvent,
    randomGenerator
  );
  const finalIncrement = incrementEvent.incrementAmount || increment;
  modifiedState = {
    ...modifiedState,
    comboMultiplier: gameState.comboMultiplier + finalIncrement
  };
  modifiedState = updateTriggerStates(modifiedState);
  return modifiedState;
}
function calculateComboScore(baseScore, comboMultiplier) {
  if (comboMultiplier <= 0) {
    return baseScore;
  }
  return baseScore * comboMultiplier;
}

// src/powerCards.ts
function clearTileStatuses(tiles) {
  const clearedTiles = [...tiles];
  clearedTiles.forEach((tile) => {
    if (tile && !tile.isEmpty) {
      tile.status = "normal";
    }
  });
  return clearedTiles;
}
function performPowerCardSplit(tiles, tilePos, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!tilePos || tilePos.row === void 0 || tilePos.col === void 0) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position not provided"
    };
  }
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position out of bounds"
    };
  }
  const tileData = getTile(newTiles, tilePos.row, tilePos.col, boardSize);
  if (tileData.isEmpty || tileData.value <= 2) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const splitValue = tileData.value / 2;
  setTile(
    newTiles,
    {
      value: splitValue,
      status: "split",
      meta: {},
      row: tilePos.row,
      col: tilePos.col,
      isEmpty: false,
      effect: tileData.effect
    },
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Split doesn't give score
  };
}
function performPowerCardMultiply(tiles, tilePos, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!tilePos || tilePos.row === void 0 || tilePos.col === void 0) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position not provided"
    };
  }
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position out of bounds"
    };
  }
  const tileData = getTile(newTiles, tilePos.row, tilePos.col, boardSize);
  if (tileData.isEmpty || !tileData.value) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const multipliedValue = tileData.value * 2;
  setTile(
    newTiles,
    {
      value: multipliedValue,
      status: "multiplied",
      meta: {},
      row: tilePos.row,
      col: tilePos.col,
      isEmpty: false,
      effect: tileData.effect
    },
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Multiply doesn't give score
  };
}
function performPowerCardShuffle(tiles, randomGenerator, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  const existingTiles = [];
  for (let i = 0; i < newTiles.length; i++) {
    if (!newTiles[i].isEmpty) {
      existingTiles.push({
        ...newTiles[i],
        status: "shuffled"
        // Mark as shuffled for animation
      });
    }
  }
  if (existingTiles.length === 0) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  for (let i = 0; i < newTiles.length; i++) {
    const { row, col } = indexToRowCol(i, boardSize);
    newTiles[i] = createEmptyTile(row, col);
  }
  for (let i = existingTiles.length - 1; i > 0; i--) {
    const j = Math.floor(
      randomGenerator.getRandom(RNG_NAMESPACES.SHUFFLE) * (i + 1)
    );
    [existingTiles[i], existingTiles[j]] = [existingTiles[j], existingTiles[i]];
  }
  const availablePositions = [];
  for (let i = 0; i < newTiles.length; i++) {
    availablePositions.push(i);
  }
  for (let i = availablePositions.length - 1; i > 0; i--) {
    const j = Math.floor(
      randomGenerator.getRandom(RNG_NAMESPACES.SHUFFLE) * (i + 1)
    );
    [availablePositions[i], availablePositions[j]] = [
      availablePositions[j],
      availablePositions[i]
    ];
  }
  for (let i = 0; i < existingTiles.length; i++) {
    const targetIndex = availablePositions[i];
    const { row, col } = indexToRowCol(targetIndex, boardSize);
    newTiles[targetIndex] = {
      ...existingTiles[i],
      row,
      col
    };
  }
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Shuffle doesn't give score
  };
}
function performPowerCardLightning(tiles, column, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (column === void 0 || column < 0 || column >= boardSize) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Invalid column"
    };
  }
  let hasValidTiles = false;
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (tile && tile.value) {
      hasValidTiles = true;
      break;
    }
  }
  if (!hasValidTiles) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  let totalScore = 0;
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (!tile.isEmpty) {
      const newValue = tile.value * 2;
      setTile(
        newTiles,
        {
          isEmpty: false,
          row,
          col: column,
          value: newValue,
          status: "lightning",
          // Mark as lightning for animation
          meta: {},
          effect: tile.effect
        },
        boardSize
      );
      totalScore += newValue;
    }
  }
  return {
    tiles: newTiles,
    success: true,
    score: totalScore
  };
}
function performPowerCardRadiate(tiles, tilePos, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!tilePos || tilePos.row === void 0 || tilePos.col === void 0) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position not provided"
    };
  }
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile position out of bounds"
    };
  }
  const centerTile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);
  if (!centerTile || !centerTile.value) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const adjacentPositions = [
    { row: tilePos.row - 1, col: tilePos.col - 1 },
    // Top-left
    { row: tilePos.row - 1, col: tilePos.col },
    // Top
    { row: tilePos.row - 1, col: tilePos.col + 1 },
    // Top-right
    { row: tilePos.row, col: tilePos.col - 1 },
    // Left
    { row: tilePos.row, col: tilePos.col + 1 },
    // Right
    { row: tilePos.row + 1, col: tilePos.col - 1 },
    // Bottom-left
    { row: tilePos.row + 1, col: tilePos.col },
    // Bottom
    { row: tilePos.row + 1, col: tilePos.col + 1 }
    // Bottom-right
  ];
  let totalScore = 0;
  let affectedTiles = 0;
  for (const pos of adjacentPositions) {
    if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
    const adjacentTile = getTile(newTiles, pos.row, pos.col, boardSize);
    if (!adjacentTile.isEmpty) {
      const newValue = adjacentTile.value * 2;
      setTile(
        newTiles,
        {
          value: newValue,
          status: "radiated",
          // Mark as radiated for animation
          meta: {},
          row: pos.row,
          col: pos.col,
          isEmpty: false,
          effect: adjacentTile.effect
        },
        boardSize
      );
      totalScore += newValue;
      affectedTiles++;
    }
  }
  if (affectedTiles === 0) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  return {
    tiles: newTiles,
    success: true,
    score: totalScore
  };
}
function performPowerCardClone(tiles, sourceTilePos, targetTilePos, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!sourceTilePos || sourceTilePos.row === void 0 || sourceTilePos.col === void 0 || !targetTilePos || targetTilePos.row === void 0 || targetTilePos.col === void 0) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position not provided"
    };
  }
  if (!isValidPosition(sourceTilePos.row, sourceTilePos.col, boardSize) || !isValidPosition(targetTilePos.row, targetTilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position out of bounds"
    };
  }
  const sourceTile = getTile(
    newTiles,
    sourceTilePos.row,
    sourceTilePos.col,
    boardSize
  );
  if (sourceTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const targetTile = getTile(
    newTiles,
    targetTilePos.row,
    targetTilePos.col,
    boardSize
  );
  if (!targetTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const isAdjacent = Math.abs(sourceTilePos.row - targetTilePos.row) + Math.abs(sourceTilePos.col - targetTilePos.col) === 1;
  if (!isAdjacent) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  setTile(
    newTiles,
    {
      value: sourceTile.value,
      status: "cloned",
      meta: {},
      row: targetTilePos.row,
      col: targetTilePos.col,
      isEmpty: false,
      effect: sourceTile.effect
    },
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Clone doesn't give score
  };
}
function performPowerCardSwap(tiles, tile1, tile2, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!tile1 || tile1.row === void 0 || tile1.col === void 0 || !tile2 || tile2.row === void 0 || tile2.col === void 0) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile positions not provided"
    };
  }
  if (!isValidPosition(tile1.row, tile1.col, boardSize) || !isValidPosition(tile2.row, tile2.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Tile positions out of bounds"
    };
  }
  if (tile1.row === tile2.row && tile1.col === tile2.col) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tileData1 = getTile(newTiles, tile1.row, tile1.col, boardSize);
  const tileData2 = getTile(newTiles, tile2.row, tile2.col, boardSize);
  if (tileData1.isEmpty || tileData2.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  setTile(
    newTiles,
    !tileData2.isEmpty ? {
      ...tileData2,
      row: tile1.row,
      col: tile1.col,
      status: "swapped",
      meta: {}
    } : createEmptyTile(tile1.row, tile1.col),
    boardSize
  );
  setTile(
    newTiles,
    tileData1 ? {
      ...tileData1,
      row: tile2.row,
      col: tile2.col,
      status: "swapped",
      meta: {}
    } : createEmptyTile(tile2.row, tile2.col),
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Swap doesn't give score
  };
}
function performPowerCardVortex(tiles, quadrantPos, boardSize) {
  if (void 0 === quadrantPos.row || void 0 === quadrantPos.col) {
    return {
      tiles,
      success: false,
      score: 0,
      error: "Row or column not provided"
    };
  }
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!isValidPosition(quadrantPos.row, quadrantPos.col, boardSize) || !isValidPosition(quadrantPos.row + 1, quadrantPos.col + 1, boardSize) || !isValidPosition(quadrantPos.row + 1, quadrantPos.col, boardSize) || !isValidPosition(quadrantPos.row, quadrantPos.col + 1, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Invalid quadrant position"
    };
  }
  const topLeft = getTile(
    newTiles,
    quadrantPos.row,
    quadrantPos.col,
    boardSize
  );
  const topRight = getTile(
    newTiles,
    quadrantPos.row,
    quadrantPos.col + 1,
    boardSize
  );
  const bottomLeft = getTile(
    newTiles,
    quadrantPos.row + 1,
    quadrantPos.col,
    boardSize
  );
  const bottomRight = getTile(
    newTiles,
    quadrantPos.row + 1,
    quadrantPos.col + 1,
    boardSize
  );
  setTile(
    newTiles,
    {
      ...topLeft,
      row: quadrantPos.row,
      col: quadrantPos.col + 1
    },
    boardSize
  );
  setTile(
    newTiles,
    {
      ...topRight,
      row: quadrantPos.row + 1,
      col: quadrantPos.col + 1
    },
    boardSize
  );
  setTile(
    newTiles,
    {
      ...bottomRight,
      row: quadrantPos.row + 1,
      col: quadrantPos.col
    },
    boardSize
  );
  setTile(
    newTiles,
    {
      ...bottomLeft,
      row: quadrantPos.row,
      col: quadrantPos.col
    },
    boardSize
  );
  if (getTile(newTiles, quadrantPos.row, quadrantPos.col, boardSize)) {
    getTile(newTiles, quadrantPos.row, quadrantPos.col, boardSize).status = "rotated";
  }
  if (getTile(newTiles, quadrantPos.row, quadrantPos.col + 1, boardSize)) {
    getTile(newTiles, quadrantPos.row, quadrantPos.col + 1, boardSize).status = "rotated";
  }
  if (getTile(newTiles, quadrantPos.row + 1, quadrantPos.col, boardSize)) {
    getTile(newTiles, quadrantPos.row + 1, quadrantPos.col, boardSize).status = "rotated";
  }
  if (getTile(newTiles, quadrantPos.row + 1, quadrantPos.col + 1, boardSize)) {
    getTile(
      newTiles,
      quadrantPos.row + 1,
      quadrantPos.col + 1,
      boardSize
    ).status = "rotated";
  }
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Vortex is a utility card that doesn't generate score
  };
}
function performPowerCardTeleport(tiles, sourceTilePos, targetTilePos, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!sourceTilePos || sourceTilePos.row === void 0 || sourceTilePos.col === void 0 || !targetTilePos || targetTilePos.row === void 0 || targetTilePos.col === void 0) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position not provided"
    };
  }
  if (!isValidPosition(sourceTilePos.row, sourceTilePos.col, boardSize) || !isValidPosition(targetTilePos.row, targetTilePos.col, boardSize)) {
    return {
      tiles: newTiles,
      success: false,
      score: 0,
      error: "Source or target tile position out of bounds"
    };
  }
  if (sourceTilePos.row === targetTilePos.row && sourceTilePos.col === targetTilePos.col) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const sourceTile = getTile(
    newTiles,
    sourceTilePos.row,
    sourceTilePos.col,
    boardSize
  );
  if (sourceTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const targetTile = getTile(
    newTiles,
    targetTilePos.row,
    targetTilePos.col,
    boardSize
  );
  if (!targetTile.isEmpty) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  setTile(
    newTiles,
    {
      value: sourceTile.value,
      status: "teleported",
      meta: {},
      row: targetTilePos.row,
      col: targetTilePos.col,
      isEmpty: false,
      effect: sourceTile.effect
    },
    boardSize
  );
  setTile(
    newTiles,
    createEmptyTile(sourceTilePos.row, sourceTilePos.col),
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // Teleport doesn't give score
  };
}
function performPowerCardBomb(tiles, targetTile, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!targetTile) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tilePos = { row: targetTile.row, col: targetTile.col };
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);
  if (tile.isEmpty && !tile.effect) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const negativeScore = tile.isEmpty ? 0 : -tile.value;
  setTile(
    newTiles,
    {
      ...tile,
      isEmpty: true,
      value: 0,
      effect: void 0,
      status: "bombed"
    },
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: negativeScore
    // Negative score to reduce player's score
  };
}
function performPowerCardDestroy(tiles, targetTile, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!targetTile) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tilePos = { row: targetTile.row, col: targetTile.col };
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);
  if (tile.isEmpty || tile.effect) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const negativeScore = -tile.value;
  setTile(
    newTiles,
    {
      ...tile,
      isEmpty: true,
      value: 0,
      status: "destroyed"
    },
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: negativeScore
    // Negative score to reduce player's score
  };
}
function performPowerCardClear(tiles, column, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (column === void 0 || column < 0 || column >= boardSize) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  let hasClearableTiles = false;
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (!tile.isEmpty && !tile.effect) {
      hasClearableTiles = true;
      break;
    }
  }
  if (!hasClearableTiles) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(newTiles, row, column, boardSize);
    if (!tile.isEmpty && !tile.effect) {
      setTile(
        newTiles,
        {
          ...tile,
          isEmpty: true,
          value: 0,
          status: "purged"
        },
        boardSize
      );
    }
  }
  return {
    tiles: newTiles,
    success: true,
    score: 0
    // No score change for purge
  };
}
function performPowerCardDouble(tiles, targetTile, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  if (!targetTile) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tilePos = { row: targetTile.row, col: targetTile.col };
  if (!isValidPosition(tilePos.row, tilePos.col, boardSize)) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const tile = getTile(newTiles, tilePos.row, tilePos.col, boardSize);
  if (tile.isEmpty || tile.effect) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  const newValue = tile.value * 2;
  setTile(
    newTiles,
    {
      ...tile,
      value: newValue,
      status: "amplified"
    },
    boardSize
  );
  return {
    tiles: newTiles,
    success: true,
    score: newValue
    // Add the new value as score
  };
}
function performPowerCardTransform(tiles, numEffects, randomGenerator, boardSize) {
  const clearedTiles = clearTileStatuses(tiles);
  const newTiles = [...clearedTiles];
  const tilesWithEffects = [];
  for (let i = 0; i < newTiles.length; i++) {
    if (newTiles[i].effect && newTiles[i].effect?.type !== "none") {
      tilesWithEffects.push(i);
    }
  }
  if (tilesWithEffects.length === 0) {
    return { tiles: newTiles, success: false, score: 0 };
  }
  for (let i = tilesWithEffects.length - 1; i > 0; i--) {
    const j = Math.floor(
      randomGenerator.getRandom(RNG_NAMESPACES.SHUFFLE) * (i + 1)
    );
    [tilesWithEffects[i], tilesWithEffects[j]] = [
      tilesWithEffects[j],
      tilesWithEffects[i]
    ];
  }
  const tilesToTransform = tilesWithEffects.slice(
    0,
    Math.min(numEffects, tilesWithEffects.length)
  );
  for (const index of tilesToTransform) {
    const { row, col } = indexToRowCol(index, boardSize);
    const tile = getTile(newTiles, row, col, boardSize);
    setTile(
      newTiles,
      {
        ...tile,
        effect: void 0,
        status: "normal"
      },
      boardSize
    );
  }
  return {
    tiles: newTiles,
    success: true,
    score: 0
  };
}

// src/validation.ts
function hasValidSplitTiles(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);
      if (!tile.isEmpty && tile.value > 2) {
        return true;
      }
    }
  }
  return false;
}
function hasValidMultiplyTiles(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);
      if (!tile.isEmpty) {
        return true;
      }
    }
  }
  return false;
}
function hasValidShuffleTiles(tiles) {
  let tileCount = 0;
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty) {
      tileCount++;
    }
  }
  return tileCount >= 2;
}
function hasValidLightningTiles(tiles) {
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty) {
      return true;
    }
  }
  return false;
}
function hasValidRadiateTiles(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const centerTile = getTile(tiles, row, col, boardSize);
      if (centerTile.isEmpty) continue;
      const adjacentPositions = [
        { row: row - 1, col: col - 1 },
        // Top-left
        { row: row - 1, col },
        // Top
        { row: row - 1, col: col + 1 },
        // Top-right
        { row, col: col - 1 },
        // Left
        { row, col: col + 1 },
        // Right
        { row: row + 1, col: col - 1 },
        // Bottom-left
        { row: row + 1, col },
        // Bottom
        { row: row + 1, col: col + 1 }
        // Bottom-right
      ];
      for (const pos of adjacentPositions) {
        if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
        const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
        if (!adjacentTile.isEmpty) {
          return true;
        }
      }
    }
  }
  return false;
}
function hasValidCloneTiles(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);
      if (tile.isEmpty) continue;
      const adjacentPositions = [
        { row: row - 1, col },
        // Up
        { row: row + 1, col },
        // Down
        { row, col: col - 1 },
        // Left
        { row, col: col + 1 }
        // Right
      ];
      for (const pos of adjacentPositions) {
        if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
        const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
        if (adjacentTile.isEmpty) {
          return true;
        }
      }
    }
  }
  return false;
}
function hasValidSwapTiles(tiles) {
  let tileCount = 0;
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty) {
      tileCount++;
    }
  }
  return tileCount >= 2;
}
function hasValidVortexTiles(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize - 1; row++) {
    for (let col = 0; col < boardSize - 1; col++) {
      if (!isValidPosition(row, col, boardSize)) continue;
      if (!isValidPosition(row, col + 1, boardSize)) continue;
      if (!isValidPosition(row + 1, col, boardSize)) continue;
      if (!isValidPosition(row + 1, col + 1, boardSize)) continue;
      const topLeft = getTile(tiles, row, col, boardSize);
      const topRight = getTile(tiles, row, col + 1, boardSize);
      const bottomLeft = getTile(tiles, row + 1, col, boardSize);
      const bottomRight = getTile(tiles, row + 1, col + 1, boardSize);
      if (!topLeft.isEmpty || !topRight.isEmpty || !bottomLeft.isEmpty || !bottomRight.isEmpty) {
        return true;
      }
    }
  }
  return false;
}
function hasValidTeleportTiles(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  let hasSourceTiles = false;
  let hasEmptySpaces = false;
  for (let row = 0; row < boardSize; row++) {
    for (let col = 0; col < boardSize; col++) {
      const tile = getTile(tiles, row, col, boardSize);
      if (!tile.isEmpty) {
        hasSourceTiles = true;
      } else if (tile.isEmpty) {
        hasEmptySpaces = true;
      }
    }
  }
  return hasSourceTiles && hasEmptySpaces;
}
function isValidSwapPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  if (!isValidPosition(row, col, boardSize)) return false;
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty;
}
function isValidVortexPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  if (row >= boardSize - 1 || col >= boardSize - 1) {
    return false;
  }
  const topLeft = getTile(tiles, row, col, boardSize);
  const topRight = getTile(tiles, row, col + 1, boardSize);
  const bottomLeft = getTile(tiles, row + 1, col, boardSize);
  const bottomRight = getTile(tiles, row + 1, col + 1, boardSize);
  return !topLeft.isEmpty || !topRight.isEmpty || !bottomLeft.isEmpty || !bottomRight.isEmpty;
}
function isValidSplitPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty && tile.value > 2;
}
function isValidMultiplyPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty;
}
function isValidRadiatePosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  if (tile.isEmpty) return false;
  const adjacentPositions = [
    { row: row - 1, col: col - 1 },
    // Top-left
    { row: row - 1, col },
    // Top
    { row: row - 1, col: col + 1 },
    // Top-right
    { row, col: col - 1 },
    // Left
    { row, col: col + 1 },
    // Right
    { row: row + 1, col: col - 1 },
    // Bottom-left
    { row: row + 1, col },
    // Bottom
    { row: row + 1, col: col + 1 }
    // Bottom-right
  ];
  for (const pos of adjacentPositions) {
    if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
    const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
    if (!adjacentTile.isEmpty) {
      return true;
    }
  }
  return false;
}
function isValidCloneSourcePosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  if (tile.isEmpty) return false;
  const adjacentPositions = [
    { row: row - 1, col },
    // Up
    { row: row + 1, col },
    // Down
    { row, col: col - 1 },
    // Left
    { row, col: col + 1 }
    // Right
  ];
  for (const pos of adjacentPositions) {
    if (!isValidPosition(pos.row, pos.col, boardSize)) continue;
    const adjacentTile = getTile(tiles, pos.row, pos.col, boardSize);
    if (adjacentTile.isEmpty) {
      return true;
    }
  }
  return false;
}
function isValidCloneTargetPosition(tiles, row, col, sourcePos) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  if (!tile.isEmpty) {
    return false;
  }
  if (sourcePos) {
    const isAdjacent = Math.abs(sourcePos.row - row) + Math.abs(sourcePos.col - col) === 1;
    return isAdjacent;
  }
  return true;
}
function isValidLightningColumn(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  for (let r = 0; r < boardSize; r++) {
    const tile = getTile(tiles, r, col, boardSize);
    if (!tile.isEmpty) {
      return true;
    }
  }
  return false;
}
function isValidTeleportSourcePosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty;
}
function isValidTeleportTargetPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return tile.isEmpty;
}
function hasValidBombTiles(tiles) {
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty || tiles[i].effect) {
      return true;
    }
  }
  return false;
}
function isValidBombPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty || !!tile.effect;
}
function hasValidDestroyTiles(tiles) {
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty && !tiles[i].effect?.active) {
      return true;
    }
  }
  return false;
}
function isValidDestroyPosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty && !tile.effect?.active;
}
function hasValidClearColumns(tiles) {
  const boardSize = Math.sqrt(tiles.length);
  for (let col = 0; col < boardSize; col++) {
    for (let row = 0; row < boardSize; row++) {
      const tile = getTile(tiles, row, col, boardSize);
      if (!tile.isEmpty && !tile.effect?.active) {
        return true;
      }
    }
  }
  return false;
}
function isValidClearColumn(tiles, col) {
  const boardSize = Math.sqrt(tiles.length);
  for (let row = 0; row < boardSize; row++) {
    const tile = getTile(tiles, row, col, boardSize);
    if (!tile.isEmpty && !tile.effect?.active) {
      return true;
    }
  }
  return false;
}
function hasValidDoubleTiles(tiles) {
  for (let i = 0; i < tiles.length; i++) {
    if (!tiles[i].isEmpty && !tiles[i].effect?.active) {
      return true;
    }
  }
  return false;
}
function isValidDoublePosition(tiles, row, col) {
  const boardSize = Math.sqrt(tiles.length);
  const tile = getTile(tiles, row, col, boardSize);
  return !tile.isEmpty && !tile.effect?.active;
}
function hasValidTransformTiles(tiles) {
  for (let i = 0; i < tiles.length; i++) {
    if (tiles[i].effect && tiles[i].effect?.type !== "none") {
      return true;
    }
  }
  return false;
}

// src/shards.ts
function calculateShards(currentShards, shardsToAdd) {
  return Math.min(currentShards + shardsToAdd, SHARDS_PER_CARD);
}

// src/util.ts
function hashGameState(state) {
  return computeStateHash(state);
}

// src/actionExecutor.ts
function executeSwipeAction(state, direction, rng) {
  const workingState = resetTriggeredStates(state);
  const result = performSwipe(workingState, direction, rng);
  if (result.moved) {
    let newState = result.gameState;
    newState = updateComboMultiplier(
      newState,
      result.mergedTilesCount,
      rng
    );
    const totalScore = result.score >= 0 ? calculateComboScore(result.score, newState.comboMultiplier) : result.score;
    let shardsToAdd = result.mergedTilesCount;
    if (result.mergedTilesCount > 0) {
      const shardEvent = {
        type: "POST_SWIPE",
        mergedTilesCount: result.mergedTilesCount,
        mergeOccurred: true,
        shardsMultiplier: 1};
      newState = processTotemEffects(newState, shardEvent, rng);
      const shardMultiplier = shardEvent.shardsMultiplier || 1;
      shardsToAdd = result.mergedTilesCount * shardMultiplier;
    }
    const addTileResult = addRandomTileWithEffects(newState, rng);
    newState = addTileResult.gameState;
    newState = updateTriggerStates(newState);
    newState = {
      ...newState,
      shards: calculateShards(newState.shards, shardsToAdd)
    };
    let cardDrawn = false;
    let drawnCard;
    if (canDrawCard(newState)) {
      const drawResult = performDrawCard(newState);
      if (drawResult.success) {
        drawnCard = drawCardFromDeck(rng, newState.deck.nextCardIndex);
        newState = {
          ...newState,
          hand: {
            ...newState.hand,
            cards: [...newState.hand.cards, drawnCard]
          },
          shards: drawResult.shards,
          deck: {
            ...newState.deck,
            nextCardIndex: drawResult.deckNextCardIndex,
            remainingCards: drawResult.deckRemainingCards
          }
        };
        cardDrawn = true;
      }
    }
    const moveCompletedEvent = {
      type: "MOVE_COMPLETED"
    };
    newState = processGlobalEffects(newState, moveCompletedEvent, rng);
    return {
      success: true,
      newState,
      scoreAdded: totalScore,
      shardsAdded: shardsToAdd,
      moved: true,
      cardDrawn,
      drawnCard
    };
  } else {
    let newState = result.gameState;
    newState = updateComboMultiplier(newState, 0, rng);
    const failedSwipeEvent = {
      type: "FAILED_SWIPE"};
    newState = processTotemEffects(newState, failedSwipeEvent, rng);
    const addTileResult = addRandomTileWithEffects(newState, rng);
    newState = addTileResult.gameState;
    const moveCompletedEvent = {
      type: "MOVE_COMPLETED"
    };
    newState = processGlobalEffects(newState, moveCompletedEvent, rng);
    return {
      success: true,
      newState,
      scoreAdded: 0,
      shardsAdded: 0,
      moved: false,
      cardDrawn: false
    };
  }
}
function executePlayCardAction(state, action, actionData, cardIndex, rng) {
  let newState = { ...state };
  let operationSuccess = false;
  let scoreAdded = 0;
  let error;
  switch (action) {
    case "split": {
      const result = performPowerCardSplit(
        newState.board.tiles,
        actionData.tile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_split";
      }
      break;
    }
    case "multiply": {
      const result = performPowerCardMultiply(
        newState.board.tiles,
        actionData.tile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_multiply";
      }
      break;
    }
    case "shuffle": {
      const result = performPowerCardShuffle(
        newState.board.tiles,
        rng,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_shuffle";
      }
      break;
    }
    case "lightning": {
      const result = performPowerCardLightning(
        newState.board.tiles,
        actionData.column,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_lightning";
      }
      break;
    }
    case "radiate": {
      const result = performPowerCardRadiate(
        newState.board.tiles,
        actionData.tile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_radiate";
      }
      break;
    }
    case "clone": {
      const result = performPowerCardClone(
        newState.board.tiles,
        actionData.sourceTile,
        actionData.targetTile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_clone";
      }
      break;
    }
    case "swap": {
      const result = performPowerCardSwap(
        newState.board.tiles,
        actionData.tile1,
        actionData.tile2,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_swap";
      }
      break;
    }
    case "vortex": {
      const result = performPowerCardVortex(
        newState.board.tiles,
        {
          row: actionData.row,
          col: actionData.column
        },
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_vortex";
      }
      break;
    }
    case "teleport": {
      const result = performPowerCardTeleport(
        newState.board.tiles,
        actionData.sourceTile,
        actionData.targetTile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_teleport";
      }
      break;
    }
    case "bomb": {
      const result = performPowerCardBomb(
        newState.board.tiles,
        actionData.tile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_bomb";
      }
      break;
    }
    case "destroy": {
      const result = performPowerCardDestroy(
        newState.board.tiles,
        actionData.tile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_destroy";
      }
      break;
    }
    case "clear": {
      const result = performPowerCardClear(
        newState.board.tiles,
        actionData.column,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_clear";
      }
      break;
    }
    case "double": {
      const result = performPowerCardDouble(
        newState.board.tiles,
        actionData.tile,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_double";
      }
      break;
    }
    case "transform": {
      const card = newState.hand.cards.find((c) => c.type === "transform");
      const numEffects = card?.value || 1;
      const result = performPowerCardTransform(
        newState.board.tiles,
        numEffects,
        rng,
        newState.board.size
      );
      if (result.success) {
        newState.board.tiles = result.tiles;
        newState.combo = 0;
        operationSuccess = true;
        scoreAdded = result.score;
      } else {
        error = "invalid_transform";
      }
      break;
    }
    default:
      error = "unknown_card_action";
      break;
  }
  if (operationSuccess) {
    if (newState.hand.cards[cardIndex]) {
      newState.hand.cards.splice(cardIndex, 1);
    }
    newState = updateTriggerStates(newState);
  }
  return {
    success: operationSuccess,
    newState,
    scoreAdded,
    error
  };
}
function executeSpawnTotemAction(state, totemType, cardIndex) {
  const newState = { ...state };
  if (cardIndex < 0 || cardIndex >= newState.hand.cards.length) {
    return {
      success: false,
      newState: state,
      error: `Invalid card index: ${cardIndex}`
    };
  }
  const totemId = `totem_${newState.moveIndex + 1}_${totemType}`;
  const newTotem = {
    id: totemId,
    type: totemType,
    config: initializeTotemConfig(totemType),
    name: totemType,
    description: totemType,
    active: true
  };
  newState.totems = {
    ...newState.totems,
    active: [...newState.totems.active, newTotem]
  };
  newState.hand.cards.splice(cardIndex, 1);
  return {
    success: true,
    newState,
    scoreAdded: 0
  };
}
function executeAction(state, action, rng) {
  switch (action.type) {
    case "SWIPE": {
      const payload = action.payload;
      return executeSwipeAction(state, payload.direction, rng);
    }
    case "PLAY_CARD": {
      const payload = action.payload;
      return executePlayCardAction(
        state,
        payload.action,
        payload,
        payload.cardIndex,
        rng
      );
    }
    case "SPAWN_TOTEM": {
      const payload = action.payload;
      return executeSpawnTotemAction(
        state,
        payload.totemType,
        payload.cardIndex
      );
    }
    default:
      return {
        success: false,
        newState: state,
        error: `Unknown action type: ${action.type}`
      };
  }
}

export { DECK_SIZE, DEFAULT_BOARD_SIZE, DEFAULT_TILE_SIZE, MAX_ACTIVE_TOTEMS, MAX_BOARD_SIZE, MAX_HAND_SIZE, MIN_BOARD_SIZE, OperationType, POWER_CARDS, PassThroughRandomGenerator, RNG_NAMESPACES, RandomGenerator, SHARDS_PER_CARD, TOTEM_TYPES, addRandomValue as addRandomTile, addRandomTileWithEffects, addRandomValue, applyEffectToTile, attemptSpawnEffectOnTile, buildInitialBoard, calculateComboScore, calculateShards, canApplyEffectToTile, canDrawCard, canTilesMergeTogether, canValueMerge, canValueMove, canonicalStringify, computeActionHash, computeActionHashAsync, computeStateHash, computeStateHashAsync, countActiveEffects, createAmplifyEffect, createBlackHoleEffect, createEmptyTile, createFreezeEffect, createGlobalEffect, createStoneEffect, createTileEffect, drawCardFromDeck, executeAction, executePlayCardAction, executeSpawnTotemAction, executeSwipeAction, findBlackHoleInPath, findValidSpawnPositions, getAdjacentTiles, getAmplifyMultiplier, getComboProgress, getEffectToPreserveAtSource, getMergeCountProgress, getMoveProgress, getRNGIndices, getScoreProgress, getSpawnConfig, getTile, hasValidBombTiles, hasValidClearColumns, hasValidCloneTiles, hasValidDestroyTiles, hasValidDoubleTiles, hasValidLightningTiles, hasValidMultiplyTiles, hasValidRadiateTiles, hasValidShuffleTiles, hasValidSplitTiles, hasValidSwapTiles, hasValidTeleportTiles, hasValidTransformTiles, hasValidVortexTiles, hashGameState, indexToRowCol, initRandomSeeds, initializeEventTriggerStates, initializeTotemConfig, isAmplifyTile, isBlackHoleTile, isTriggerConditionMet, isValidBombPosition, isValidClearColumn, isValidCloneSourcePosition, isValidCloneTargetPosition, isValidDestroyPosition, isValidDoublePosition, isValidLightningColumn, isValidMultiplyPosition, isValidPosition, isValidRadiatePosition, isValidSplitPosition, isValidSwapPosition, isValidTeleportSourcePosition, isValidTeleportTargetPosition, isValidVortexPosition, markTriggersActivated, performDrawCard, performPowerCardBomb, performPowerCardClear, performPowerCardClone, performPowerCardDestroy, performPowerCardDouble, performPowerCardLightning, performPowerCardMultiply, performPowerCardRadiate, performPowerCardShuffle, performPowerCardSplit, performPowerCardSwap, performPowerCardTeleport, performPowerCardTransform, performPowerCardVortex, performSwipe, processAmplifyEffect, processBlackHoleDestruction, processEventSpawnRules, processFreezeRemovalFromAdjacentMerge, processGlobalEffects, processLockTriggerOnMerge, processTileEffectsOnMerge, processTotemEffects, removeBlackHoleWithShards, resetTriggeredStates, rowColToIndex, selectSpawnPosition, setTile, setTileAt, shouldSpawnEffect, spawnTileEffects, tileHasEffect, updateComboMultiplier, updateTriggerStates, validateBoardConfig };
//# sourceMappingURL=index.js.map
//# sourceMappingURL=index.js.map