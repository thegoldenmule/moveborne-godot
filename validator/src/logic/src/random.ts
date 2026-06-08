import seedrandom from "seedrandom";

export type RNGNamespace =
  | "tile-gen"
  | "shuffle"
  | "effect-spawn"
  | "totem-spawn"
  | "card-draw";

export interface IRandomGenerator {
  getRandom(namespace: RNGNamespace): number;
  getIndices(): Record<RNGNamespace, number>;
  getSeeds(): Record<RNGNamespace, number>;
  getState(namespace: RNGNamespace): string;
  getAllStates(): Record<RNGNamespace, string>;
  clone(): IRandomGenerator;
}

export const PassThroughRandomGenerator: IRandomGenerator = {
  getRandom: () => 0,
  getIndices: () => ({
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0,
  }),
  getSeeds: () => ({
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0,
  }),
  getState: () => "",
  getAllStates: () => ({
    "tile-gen": "",
    shuffle: "",
    "effect-spawn": "",
    "totem-spawn": "",
    "card-draw": "",
  }),
  clone: () =>
    new RandomGenerator(
      {
        "tile-gen": 0,
        shuffle: 0,
        "effect-spawn": 0,
        "totem-spawn": 0,
        "card-draw": 0,
      },
      {
        "tile-gen": 0,
        shuffle: 0,
        "effect-spawn": 0,
        "totem-spawn": 0,
        "card-draw": 0,
      },
    ),
};

export class RandomGenerator implements IRandomGenerator {
  private rngInstances: Map<RNGNamespace, seedrandom.PRNG>;
  private rngIndices: Record<RNGNamespace, number>;
  private seeds: Record<RNGNamespace, number>;

  constructor(
    seeds: Record<RNGNamespace, number>,
    indices: Record<RNGNamespace, number>,
  ) {
    this.seeds = { ...seeds };
    this.rngIndices = { ...indices };
    this.rngInstances = new Map();

    for (const namespace of Object.keys(seeds) as RNGNamespace[]) {
      this.rngInstances.set(namespace, seedrandom(seeds[namespace].toString()));
    }

    for (const [namespace, targetIndex] of Object.entries(indices) as [
      RNGNamespace,
      number,
    ][]) {
      const rng = this.rngInstances.get(namespace);
      if (!rng) continue;

      for (let i = 0; i < targetIndex; i++) {
        rng();
      }
    }
  }

  getRandom(namespace: RNGNamespace): number {
    const rng = this.rngInstances.get(namespace);
    if (!rng) {
      throw new Error(
        `RNG namespace '${namespace}' not initialized. Check RandomGenerator constructor.`,
      );
    }

    const value = rng();
    this.rngIndices[namespace]++;
    return value;
  }

  getIndices(): Record<RNGNamespace, number> {
    return { ...this.rngIndices };
  }

  getSeeds(): Record<RNGNamespace, number> {
    return { ...this.seeds };
  }

  getState(namespace: RNGNamespace): string {
    const index = this.rngIndices[namespace];
    const isInitialized = this.rngInstances.has(namespace);
    return `${namespace}: ${
      isInitialized ? "initialized" : "not initialized"
    }, index=${index}`;
  }

  getAllStates(): Record<RNGNamespace, string> {
    const namespaces: RNGNamespace[] = [
      "tile-gen",
      "shuffle",
      "effect-spawn",
      "totem-spawn",
      "card-draw",
    ];
    const states: Partial<Record<RNGNamespace, string>> = {};

    for (const namespace of namespaces) {
      states[namespace] = this.getState(namespace);
    }

    return states as Record<RNGNamespace, string>;
  }

  clone(): IRandomGenerator {
    return new RandomGenerator(this.seeds, this.rngIndices);
  }
}

export function initRandomSeeds(
  seeds: Record<RNGNamespace, number>,
  indices: Record<RNGNamespace, number>,
): void {
  const rngInstances = new Map<RNGNamespace, seedrandom.PRNG>();
  const rngIndices: Record<RNGNamespace, number> = {
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0,
  };

  for (const namespace of Object.keys(seeds) as RNGNamespace[]) {
    rngInstances.set(namespace, seedrandom(seeds[namespace].toString()));
    rngIndices[namespace] = indices[namespace];
  }

  for (const [namespace, targetIndex] of Object.entries(rngIndices) as [
    RNGNamespace,
    number,
  ][]) {
    const rng = rngInstances.get(namespace);
    if (!rng) continue;

    for (let i = 0; i < targetIndex; i++) {
      rng();
    }
  }
}

export function getRNGIndices(): Record<RNGNamespace, number> {
  return {
    "tile-gen": 0,
    shuffle: 0,
    "effect-spawn": 0,
    "totem-spawn": 0,
    "card-draw": 0,
  };
}
