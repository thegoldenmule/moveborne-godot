import * as L from './mb-logic.mjs';
import fs from 'fs';
const snap = o => JSON.parse(JSON.stringify(o));
function emptyTile(r,c){return{isEmpty:true,value:0,row:r,col:c,status:'normal'};}
function valTile(r,c,v){return{isEmpty:false,value:v,row:r,col:c,status:'normal'};}
const size=4; const tiles=[];
for(let r=0;r<size;r++)for(let c=0;c<size;c++)tiles.push(emptyTile(r,c));
for(let r=0;r<2;r++)for(let c=0;c<size;c++)tiles[r*size+c]=valTile(r,c,2);
const initial={board:{tiles,size},hand:{cards:[]},deck:{remainingCards:12,nextCardIndex:0},score:0,shards:0,combo:0,comboMultiplier:1,totems:{active:[]},moveIndex:0,randomSeeds:{'tile-gen':12345,'shuffle':12346,'effect-spawn':12347,'totem-spawn':12348,'card-draw':12349},rngIndices:{'tile-gen':0,'shuffle':0,'effect-spawn':0,'totem-spawn':0,'card-draw':0}};
const initialSnapshot = snap(initial);
const seq=['down','down','left','right','up','down','left','up','right','down','left','right','up','down','left','right','up','down','left','right'];

function assertRowMajor(st, label){
  const sz=st.board.size;
  st.board.tiles.forEach((t,i)=>{ if(t.row!==Math.floor(i/sz)||t.col!==i%sz) throw new Error(`${label} idx${i} (${t.row},${t.col}) != expected (${Math.floor(i/sz)},${i%sz})`); });
}
assertRowMajor(initialSnapshot,'initial');

let state=initial; const steps=[];
for(const dir of seq){
  const rng=new L.RandomGenerator(state.randomSeeds,state.rngIndices);
  const res=L.executeSwipeAction(state,dir,rng);
  const next={...res.newState, score:res.newState.score+(res.scoreAdded||0), rngIndices:rng.getIndices(), moveIndex:state.moveIndex+(res.cardDrawn?2:1)};
  const hash=L.computeStateHash(next);
  const s=snap(next);                       // clean deep snapshot, taken before any later mutation
  assertRowMajor(s, `step ${steps.length} ${dir}`);
  if(L.computeStateHash(s)!==hash) throw new Error(`snapshot hash mismatch at step ${steps.length}`);
  steps.push({dir,scoreAdded:res.scoreAdded,shardsAdded:res.shardsAdded,moved:res.moved,cardDrawn:res.cardDrawn,hash,state:s});
  state=next;
}
fs.writeFileSync('/Users/benjaminjordan/projects/thegoldenmule/godot-llm-workflow/llm-workflow/tests/golden/engine_swipe_golden.json', JSON.stringify({initial:initialSnapshot,steps},null,2));
console.log(`OK: ${steps.length} steps, all row-major, all snapshot hashes consistent.`);
console.log('cards drawn at steps:', steps.map((s,i)=>s.cardDrawn?i:null).filter(x=>x!==null));
console.log('first 3 hashes:', steps.slice(0,3).map(s=>s.hash.slice(0,16)));
