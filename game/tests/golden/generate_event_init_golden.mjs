import * as L from './mb-logic.mjs';
import fs from 'fs';

const snap = o => JSON.parse(JSON.stringify(o));
const SEEDS = { 'tile-gen': 12345, 'shuffle': 12346, 'effect-spawn': 12347, 'totem-spawn': 12348, 'card-draw': 12349 };
const ZERO = { 'tile-gen': 0, 'shuffle': 0, 'effect-spawn': 0, 'totem-spawn': 0, 'card-draw': 0 };

function board4() { const t = []; for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) t.push(L.createEmptyTile(r, c)); return { tiles: t, size: 4 }; }
function baseState(o = {}) {
  return { board: board4(), hand: { cards: [] }, deck: { remainingCards: 12, nextCardIndex: 0 },
    score: 0, shards: 0, combo: 0, comboMultiplier: 0, totems: { active: [] }, moveIndex: 0,
    randomSeeds: SEEDS, rngIndices: ZERO, ...o };
}

const cases = [];
function record(name, rules, state) {
  const result = L.initializeEventTriggerStates(rules, state);
  cases.push({
    name,
    eventRules: snap(rules),
    state: snap(state),
    output: result === undefined ? null : snap(result),
    outputHash: L.computeStateHash({ ets: result }),  // undefined -> JS drops key, matching Godot's null-drop
  });
}

// 1. no rules -> undefined
record('no_rules', [], baseState());
// 2. the real Fracture rule (COMBO_BREAK minCombo 3, freeze, targetPositions, icon, globalEffect)
record('fracture', [
  { trigger: { event: 'COMBO_BREAK', minCombo: 3 }, effect: 'freeze', spawnCount: 1, targetPositions: 'random',
    icon: '/assets/event-spawners/icon-fracture.png', globalEffect: { type: 'glitch', duration: 10, config: { slices: 10, offset: 5 } } },
], baseState());
// 3. multiple rules, mixed events, non-zero progress source
record('multi', [
  { trigger: { event: 'COMBO_BREAK', minCombo: 5 }, effect: 'stone', spawnCount: 2, targetPositions: 'random', icon: 'a' },
  { trigger: { event: 'SCORE_MILESTONE', threshold: 1000 }, effect: 'lock', spawnCount: 1, targetPositions: 'highest_value' },
], baseState({ comboMultiplier: 2, score: 500 }));
// 4. minimal rule: no targetPositions / no icon (keys omitted)
record('minimal', [
  { trigger: { event: 'MOVE_COUNT', moves: 10 }, effect: 'decay', spawnCount: 1 },
], baseState({ moveIndex: 4 }));
// 5. merge-count progress
record('merge_count', [
  { trigger: { event: 'MERGE_COUNT', count: 8 }, effect: 'amplify', spawnCount: 1, targetPositions: 'random' },
], baseState({ totalMerges: 3 }));

fs.writeFileSync(
  '/Users/benjaminjordan/projects/thegoldenmule/godot-llm-workflow/llm-workflow/tests/golden/event_init_golden.json',
  JSON.stringify({ cases }, null, 2));
console.log(`OK: ${cases.length} cases`);
for (const c of cases) console.log(`  ${c.name}: ${c.output ? c.output.length + ' triggers' : 'null'} hash=${c.outputHash.slice(0, 10)}`);
