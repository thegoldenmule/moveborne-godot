import * as L from './mb-logic.mjs';
import fs from 'fs';
const snap = o => JSON.parse(JSON.stringify(o));
function E(r,c){return{isEmpty:true,value:0,row:r,col:c,status:'normal'};}
function V(r,c,v){return{isEmpty:false,value:v,row:r,col:c,status:'normal',meta:{}};}
function baseState(){
  const size=4; const t=[];
  for(let r=0;r<size;r++)for(let c=0;c<size;c++)t.push(E(r,c));
  const put=(r,c,v)=>t[r*size+c]=V(r,c,v);
  put(0,0,4);put(0,1,4);put(0,2,8);
  put(1,0,2);put(1,2,8);put(1,3,16);
  put(2,1,32);put(2,3,4);
  put(3,0,16);put(3,2,2);put(3,3,2);
  return {board:{tiles:t,size},hand:{cards:[]},deck:{remainingCards:9,nextCardIndex:3},score:1000,shards:3,combo:5,comboMultiplier:4,totems:{active:[]},moveIndex:10,randomSeeds:{'tile-gen':777,'shuffle':778,'effect-spawn':779,'totem-spawn':780,'card-draw':781},rngIndices:{'tile-gen':5,'shuffle':2,'effect-spawn':0,'totem-spawn':0,'card-draw':1}};
}
function handFor(action){
  const mk=(type,id)=>({...L.POWER_CARDS[type],id});
  return [mk(action,'hand_0'), mk('bomb','filler_1'), mk('clear','filler_2')];
}
const cases=[
  {action:'bomb', params:{tile:{row:0,col:2}}},
  {action:'double', params:{tile:{row:1,col:3}}},
  {action:'lightning', params:{column:0}},
  {action:'destroy', params:{tile:{row:2,col:3}}},
  {action:'swap', params:{tile1:{row:0,col:0},tile2:{row:2,col:1}}},
  {action:'teleport', params:{sourceTile:{row:3,col:0},targetTile:{row:3,col:1}}},
  {action:'vortex', params:{row:0,column:0}},
  {action:'shuffle', params:{}},
];
const out=[];
for(const cs of cases){
  const state=baseState(); state.hand.cards=handFor(cs.action);
  const initial=snap(state);
  const rng=new L.RandomGenerator(state.randomSeeds, state.rngIndices);
  const res=L.executePlayCardAction(state, cs.action, cs.params, 0, rng);
  const next={...res.newState, score:res.newState.score+(res.scoreAdded||0), rngIndices:rng.getIndices(), moveIndex:state.moveIndex+1};
  const hash=L.computeStateHash(next);
  out.push({action:cs.action, params:cs.params, cardIndex:0, state:initial, hash, success:res.success, scoreAdded:res.scoreAdded});
}
fs.writeFileSync('/Users/benjaminjordan/projects/thegoldenmule/godot-llm-workflow/llm-workflow/tests/golden/playcard_golden.json', JSON.stringify(out,null,2));
console.log('cases:', out.map(o=>`${o.action}(ok=${o.success},+${o.scoreAdded})`).join('  '));
