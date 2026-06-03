import * as L from './mb-logic.mjs';
import fs from 'fs';
const snap = o => JSON.parse(JSON.stringify(o));
function E(r,c){return{isEmpty:true,value:0,row:r,col:c,status:'normal'};}
function V(r,c,v){return{isEmpty:false,value:v,row:r,col:c,status:'normal',meta:{}};}
function VE(r,c,v,eff){return{isEmpty:false,value:v,row:r,col:c,status:'normal',meta:{},effect:L.createTileEffect(eff)};}
function BH(r,c){return{isEmpty:true,value:0,row:r,col:c,status:'normal',effect:L.createTileEffect('black_hole')};}

const size=4; const t=[];
for(let r=0;r<size;r++)for(let c=0;c<size;c++)t.push(E(r,c));
const set=(r,c,tile)=>t[r*size+c]=tile;
set(0,0,VE(0,0,8,'amplify')); set(0,1,V(0,1,8)); set(0,2,V(0,2,4)); set(0,3,V(0,3,4));
set(1,0,V(1,0,4)); set(1,1,V(1,1,2));
set(2,0,BH(2,0)); set(2,1,V(2,1,2)); set(2,2,V(2,2,2));
set(3,0,VE(3,0,16,'lock')); set(3,3,V(3,3,16));

function totem(type,id){return{id,type,config:L.initializeTotemConfig(type),name:type,description:type,active:true};}
const mkCard=(type,id)=>({...L.POWER_CARDS[type],id});

const initial={
  board:{tiles:t,size},
  hand:{cards:[mkCard('combo_guardian','h0'), mkCard('double','h1')]},
  deck:{remainingCards:10,nextCardIndex:2},
  score:500, shards:3, combo:0, comboMultiplier:2,
  totems:{active:[totem('momentum_idol','tm0'), totem('scavenger','ts0')]},
  moveIndex:7,
  randomSeeds:{'tile-gen':4242,'shuffle':4243,'effect-spawn':4244,'totem-spawn':4245,'card-draw':4246},
  rngIndices:{'tile-gen':3,'shuffle':1,'effect-spawn':0,'totem-spawn':2,'card-draw':0},
};

const seq=[
  {t:'card', a:'double', p:{tile:{row:1,col:0}}, ci:1},   // double (1,0)=4 -> 8; hand=[combo_guardian]
  {t:'totem', tt:'combo_saver', ci:0},                    // spawn combo_saver via combo_guardian; hand=[]
  {t:'swipe', d:'left'},                                  // amplify merge, normal merge, black-hole destroy, lock merge, totems active
  {t:'swipe', d:'down'},
  {t:'swipe', d:'up'},
  {t:'swipe', d:'right'},
];

let state=snap(initial); const steps=[];
for(const s of seq){
  const rng=new L.RandomGenerator(state.randomSeeds, state.rngIndices);
  let next, info={};
  if(s.t==='swipe'){
    const res=L.executeSwipeAction(state, s.d, rng);
    next={...res.newState, score:res.newState.score+(res.scoreAdded||0), rngIndices:rng.getIndices(), moveIndex:state.moveIndex+(res.cardDrawn?2:1)};
    info={kind:'swipe', dir:s.d, scoreAdded:res.scoreAdded, cardDrawn:res.cardDrawn, moved:res.moved};
  } else if(s.t==='card'){
    const res=L.executePlayCardAction(state, s.a, s.p, s.ci, rng);
    next={...res.newState, score:res.newState.score+(res.scoreAdded||0), rngIndices:rng.getIndices(), moveIndex:state.moveIndex+1};
    info={kind:'card', action:s.a, params:s.p, cardIndex:s.ci, success:res.success, scoreAdded:res.scoreAdded};
  } else {
    const res=L.executeSpawnTotemAction(state, s.tt, s.ci);
    next={...res.newState, score:res.newState.score+(res.scoreAdded||0), rngIndices:rng.getIndices(), moveIndex:state.moveIndex+1};
    info={kind:'totem', totemType:s.tt, cardIndex:s.ci, success:res.success};
  }
  next = snap(next);
  steps.push({...info, hash:L.computeStateHash(next)});
  state=next;
}
fs.writeFileSync('/Users/benjaminjordan/projects/thegoldenmule/godot-llm-workflow/llm-workflow/tests/golden/combined_golden.json', JSON.stringify({initial:snap(initial), steps}, null, 2));
console.log('steps:', steps.map(s=>`${s.kind}:${s.dir||s.action||s.totemType}=${s.hash.slice(0,8)}`).join('  '));
