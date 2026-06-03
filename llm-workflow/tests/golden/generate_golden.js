const seedrandom = require('seedrandom');
const fs = require('fs');

// --- custom hash, transcribed exactly from src/logic/src/hashing.ts ---
function customHash(input){
  const enc = new TextEncoder();
  const data = enc.encode(input);
  let h0=0x6a09e667,h1=0xbb67ae85,h2=0x3c6ef372,h3=0xa54ff53a,h4=0x510e527f,h5=0x9b05688c,h6=0x1f83d9ab,h7=0x5be0cd19;
  for(let i=0;i<data.length;i++){const b=data[i];
    h0=((h0<<5)-h0+b)|0; h1=((h1<<7)-h1+b)|0; h2=((h2<<11)-h2+b)|0; h3=((h3<<13)-h3+b)|0;
    h4=((h4<<17)-h4+b)|0; h5=((h5<<19)-h5+b)|0; h6=((h6<<23)-h6+b)|0; h7=((h7<<29)-h7+b)|0;}
  const hx=n=>(n>>>0).toString(16).padStart(8,'0');
  return hx(h0)+hx(h1)+hx(h2)+hx(h3)+hx(h4)+hx(h5)+hx(h6)+hx(h7);
}
const stable = require('json-stable-stringify');
const canonical = o => stable(o,{space:2}) || "{}";

// double -> 64-bit hex (unambiguous golden representation)
function f64hex(x){const b=Buffer.alloc(8);b.writeDoubleBE(x);return b.toString('hex');}

const golden = {note:"Golden vectors for Moveborne→Godot determinism parity. seedrandom@3.0.5 default (53-bit double), custom rolling hash, json-stable-stringify space:2.", rng:{}, hash:[], canonical:[]};

// RNG: first 20 outputs for representative integer seeds (used as base-10 strings)
for(const seed of [0,1,2,3,4,5,42,100,1234567, 4,5,6,7,8]){ /* dups harmless */ }
for(const seed of [0,1,2,3,4,5,42,100,1234567]){
  const r=seedrandom(String(seed));
  const vals=[],hex=[];
  for(let i=0;i<20;i++){const v=r();vals.push(v);hex.push(f64hex(v));}
  golden.rng[String(seed)]={decimal:vals.map(String),f64be:hex};
}

// hash: plain strings
for(const s of ["", "a", "abc", "hello world", "{}", "moveborne"]) golden.hash.push({input:s, hash:customHash(s)});

// canonical JSON + hash of representative nested objects (key sort, arrays, numbers, optional-omission)
const sampleState = {
  score: 0, shards: 0, combo: 0, comboMultiplier: 1, moveIndex: 0,
  board: { size: 4, tiles: [ {isEmpty:true,value:0,row:0,col:0,status:"normal"}, {isEmpty:false,value:2,row:0,col:1,status:"normal"} ] },
  hand: { cards: [] }, deck: { remainingCards: 12, nextCardIndex: 0 }, totems: { active: [] },
  randomSeeds: {"tile-gen":4,"shuffle":5,"effect-spawn":6,"totem-spawn":7,"card-draw":8},
  rngIndices: {"tile-gen":0,"shuffle":0,"effect-spawn":0,"totem-spawn":0,"card-draw":0},
};
const objs = [ {b:2,a:1,c:[3,2,1]}, {z:{y:1,x:2},a:[{k:2,j:1}]}, {n:0.5,m:1,opt:undefined,arr:[]}, sampleState ];
for(const o of objs){ const c=canonical(o); golden.canonical.push({canonical:c, hash:customHash(c)}); }

fs.writeFileSync('/tmp/mb-golden/determinism_golden.json', JSON.stringify(golden,null,2));
console.log("seed 4 -> first5:", golden.rng["4"].decimal.slice(0,5).join(", "));
console.log("hash('abc') =", customHash("abc"));
console.log("\n--- canonical({b:2,a:1,c:[3,2,1]}) ---\n"+canonical({b:2,a:1,c:[3,2,1]}));
console.log("\n--- canonical({n:0.5,m:1,opt:undefined,arr:[]}) [note opt omitted] ---\n"+canonical({n:0.5,m:1,opt:undefined,arr:[]}));
console.log("\nGolden file written:", fs.statSync('/tmp/mb-golden/determinism_golden.json').size, "bytes");
