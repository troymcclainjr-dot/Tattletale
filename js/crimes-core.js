// crimes-core.js - How a crime works: steps, timers, spawning, stages, dispatching the cop car.
"use strict";
// ===================================================================== crimes
// Every crime gets reported its own way. A case is a list of steps; the case file always shows the next one.
const RANKS=[[0,"Hall Monitor"],[600,"Block Captain"],[1500,"Neighborhood Watch"],[3000,"Precinct Pest"],[5000,"Snitch 4 Life"]];
const C={};
const LATER=[];
function later(sec,fn){LATER.push([clock+sec,fn]);}
function runLater(){for(let i=LATER.length-1;i>=0;i--)if(clock>=LATER[i][0]){const f=LATER[i][1];LATER.splice(i,1);f();}}
function talk(lines,done){let t=0;lines.forEach(([w,x,d])=>{say(w,x,d);t+=d;});if(done)later(t,done);}
function defCrime(id,o){C[id]=Object.assign({id,active:false,dispatched:false,handling:false,left:0,cool:0,el:null,mk:null,si:0},o);}
const cur=c=>c.steps[Math.min(c.si,c.steps.length-1)];
const stepText=st=>typeof st.t==="function"?st.t():st.t;
const short=c=>c.who.split(" ·")[0];
function adv(c){c.si++;sfx("step");toast(`${short(c)}: ${stepText(cur(c))}`);}
const MAILSTOPS=[[-26.25,-2.3],[-20.45,-2.3],[-13.45,-2.3]];
const MAILDROP=[5.9,-3.0];

const STAGES={1:{pool:["ricky","granny","timmy","lawn","mail"],first:"granny",name:"Stage 1",sub:"Snitch Season"},
              2:{pool:["mama","daddy","squirrel","baby"],first:"daddy",name:"Stage 2",sub:"Verse 3: everybody he's ever told on"}};
const TOLD_NAMES={ricky:"Ricky",granny:"Grandma",timmy:"Timmy",lawn:"Lawn",mail:"Mailman",gary:"Gary",mama:"Mama",daddy:"Daddy",squirrel:"Squirrel",baby:"Baby",cops:"The cops"};
function needList(){return STAGES[S.stage].pool.concat(["gary"]);}
function checkStage(){
  if(S.mode!=="play"&&S.mode!=="puzzle")return;
  const done=needList().every(id=>S.told.has(id));if(!done)return;
  if(S.stage===1)later(1.8,stage1Clear);
  else if(!C.cops.active&&!S.finaleQueued){S.finaleQueued=true;startFinaleSetup();}
}
const POOL_ALL=["ricky","granny","timmy","lawn","mail","mama","daddy","squirrel","baby"];
const EXPIRE={ricky:"Ricky got away. With the bag.",granny:"Grandma made it across. Free woman.",timmy:"Timmy sold out. He's a millionaire now.",lawn:"Mrs. Johnson watered it. Evidence destroyed.",mail:"The mail got delivered. Bent.",
  mama:"Mama made it home. She's gonna act like nothin' happened.",daddy:"Daddy woke up on his own. Evidence: gone.",squirrel:"The squirrel ate the evidence.",baby:"The baby got her cone. Sprinkles and everything."};

function startCrime(id){const c=C[id];c.active=true;c.si=0;c.dispatched=false;c.handling=false;c.no=++S.caseNo;
  c.left=c.time===Infinity?Infinity:c.time*Math.max(.65,1-S.score/8000);c.full=c.left;if(c.start)c.start();
  if(id!=="gary"){toast(`New case: ${c.title}. ${stepText(cur(c))}`);sfx("tick");}}
function endCrime(c,why){
  c.active=false;c.cool=22;if(S.lock&&S.lock.c===c)endLock();if(c.end)c.end(why);
  if(why==="expired"&&S.strikes<3){S.strikes++;toast(EXPIRE[c.id]);sfx("buzz");if(S.strikes>=3)later(1.4,gameOver);}
}
function activeCount(){return STAGES[S.stage].pool.filter(id=>C[id].active).length;}
function penalty(sec){for(const c of pendingEvidence())if(c.left!==Infinity)c.left-=sec;
  const el=$("#pzpen");el.textContent=`-${sec}s`;el.hidden=false;clearTimeout(penalty.t);penalty.t=setTimeout(()=>el.hidden=true,900);}

function updateCrimes(dt){
  for(const c of Object.values(C)){
    if(!c.active){c.cool-=dt;continue;}
    if(c.update)c.update(dt);
    if(c.active&&!c.dispatched&&!c.handling&&c.left!==Infinity){c.left-=dt;if(c.left<=0)endCrime(c,"expired");}
  }
  updateEscort(dt);updateLock(dt);
  const max=S.stage===2?2:(S.score>=1500?3:2);
  if(!S.finaleQueued&&activeCount()<max){S.spawnT-=dt;if(S.spawnT<=0){
    const pool=STAGES[S.stage].pool;
    let id=S.next&&!C[S.next].active?S.next:null;S.next=id==="granny"?"ricky":null;
    if(!id){const opts=pool.filter(k=>!C[k].active&&C[k].cool<=0);const fresh=opts.filter(k=>!S.told.has(k));const from=fresh.length?fresh:opts;if(from.length)id=from[Math.random()*from.length|0];}
    if(id)startCrime(id);S.spawnT=id===STAGES[S.stage].first?9:rand(10,17);}}
}
function dispatch(ids){
  for(const id of ids){const c=C[id];c.dispatched=true;car.queue.push(id);}
  if(car.state==="parked"){car.state="leaving";car.t=0;}
}
