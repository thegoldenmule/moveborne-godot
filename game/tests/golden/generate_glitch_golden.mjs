import * as L from './mb-logic.mjs';
import fs from 'fs';

const snap = o => JSON.parse(JSON.stringify(o));
const SEEDS = { 'tile-gen': 12345, 'shuffle': 12346, 'effect-spawn': 12347, 'totem-spawn': 12348, 'card-draw': 12349 };
const ZERO = { 'tile-gen': 0, 'shuffle': 0, 'effect-spawn': 0, 'totem-spawn': 0, 'card-draw': 0 };

function board4() {
  const t = [];
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) t.push(L.createEmptyTile(r, c));
  return { tiles: t, size: 4 };
}

function baseState(overrides = {}) {
  return {
    board: board4(),
    hand: { cards: [] },
    deck: { remainingCards: 12, nextCardIndex: 0 },
    score: 0, shards: 0, combo: 0, comboMultiplier: 0,
    totems: { active: [] },
    moveIndex: 0,
    randomSeeds: SEEDS, rngIndices: ZERO,
    ...overrides,
  };
}

function glitch(movesRemaining, id = 'trigger_0_effect_777', triggerId = 'trigger_0', cfg = {}) {
  return {
    id, type: 'glitch', movesRemaining, maxMoves: 10, triggerId,
    filterConfig: { slices: 10, offset: 5, direction: 0, fillMode: 0, seed: 1234.5, average: false, minSize: 8, sampleSize: 512, ...cfg },
  };
}

const cases = [];
function record(name, state) {
  const input = snap(state);
  const rng = new L.RandomGenerator(state.randomSeeds, state.rngIndices);
  const result = L.processGlobalEffects(snap(state), { type: 'MOVE_COMPLETED' }, rng);
  cases.push({ name, input, outputHash: L.computeStateHash(result), output: snap(result), rngIndicesAfter: rng.getIndices() });
}

// 1. no globalEffects -> unchanged, no rng drawn
record('no_effects', baseState());
// 2. one glitch remaining 10 -> 9 + reseed (2 effect-spawn draws)
record('tick_one', baseState({ globalEffects: [glitch(10)] }));
// 3. one glitch remaining 1 -> removed (empty array), NO draw
record('tick_remove', baseState({ globalEffects: [glitch(1)] }));
// 4. two: first survives (5), second removed (1) -> 2 draws (first only), order preserved
record('tick_mixed', baseState({ globalEffects: [glitch(5), glitch(1, 'trigger_1_effect_888', 'trigger_1')] }));
// 5. two both survive (5, 3) -> 4 draws in array order
record('tick_two', baseState({ globalEffects: [glitch(5), glitch(3, 'trigger_1_effect_999', 'trigger_1')] }));
// 6. realistic: createGlobalEffect (advances effect-spawn x2) then tick from those indices
{
  const rng = new L.RandomGenerator(SEEDS, ZERO);
  const created = L.createGlobalEffect(
    { trigger: { event: 'COMBO_BREAK', minCombo: 3 }, effect: 'freeze', spawnCount: 1, globalEffect: { type: 'glitch', duration: 10, config: { slices: 10, offset: 5 } } },
    'trigger_0', rng);
  record('created_then_tick', baseState({ globalEffects: [created], rngIndices: rng.getIndices() }));
}

fs.writeFileSync(
  '/Users/benjaminjordan/projects/thegoldenmule/godot-llm-workflow/llm-workflow/tests/golden/glitch_golden.json',
  JSON.stringify({ cases }, null, 2));
console.log(`OK: ${cases.length} cases`);
for (const c of cases) console.log(`  ${c.name}: hash=${c.outputHash.slice(0, 12)} eff-spawn idx=${c.rngIndicesAfter['effect-spawn']}`);
