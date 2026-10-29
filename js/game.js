// game.js - Flow: start, stages, the music video, the finale, game over, keyboard/mouse, the main loop.
"use strict";
// ===================================================================== flow
function resetGame(stage,keep){
  const carry=keep?{score:S.score,busts:S.busts,still:S.still,time:S.time}:{score:0,busts:0,still:0,time:0};
  Object.assign(S,{strikes:0,caseNo:0,spawnT:5,firstEv:true,next:STAGES[stage].first,garyT:0,stage,told:new Set(),finaleQueued:false,fin:null},carry);
  LATER.length=0;endLock();
  for(const c of Object.values(C)){if(c.active&&c.end)c.end("reset");c.active=false;c.si=0;c.dispatched=false;c.handling=false;c.frozen=false;c.cool=0;if(c.el){c.el.remove();c.el=null;}}
  W.dan.escort=null;W.dan.lost=false;W.dan.speed=1.6;W.dan.detour=null;tp.cup.visible=false;W.mama.g.visible=false;W.bills.forEach(b=>b.visible=false);
  W.sq.g.visible=false;W.sq.held=false;W.sq.jailed=false;W.mamaCar.g.visible=false;W.liners.forEach(L=>L.rig.g.visible=false);W.baby.visible=false;W.babyRig.g.visible=false;
  resetDad();W.dad.on=stage===2;W.ricky.visible=false;ricky.g.visible=false;
  for(const w of [W.dan,W.steve]){w.target=null;w.detour=null;}
  W_.lawn.material=clay("#8a6a3a",.95);
  car.x=42;car.h=Math.PI;car.state="parked";car.queue=[];car.onArrive=null;copsHome();
  if(stage===2)Object.assign(P,{x:-3,z:-1.6,yaw:-Math.PI/2});else Object.assign(P,{x:.6,z:-4,yaw:Math.PI/2});camYaw=P.yaw;camPitch=.32;
  startCrime("gary");subQ=[];
}
function showHUD(on){["#plate","#cases","#keys","#mini"].forEach(q=>$(q).hidden=!on);if(!on)["#prompt","#lock"].forEach(q=>$(q).hidden=true);}
function card(t,sub,secs){$("#sctitle").textContent=t;$("#scsub").textContent=sub;$("#stagecard").hidden=false;clearTimeout(card.t);card.t=setTimeout(()=>$("#stagecard").hidden=true,secs*1000);}
function saveStage(n){try{localStorage.setItem("tt2pack_stage",String(n));}catch(e){}}
function savedStage(){try{return +(localStorage.getItem("tt2pack_stage")||1);}catch(e){return 1;}}
function startStage(n,keep){
  initAudio();if(ac&&ac.state==="suspended")ac.resume();if(musicG)musicG.gain.value=S.musicOn?.3:0;
  resetGame(n,keep);S.mode="play";
  ["#title","#over","#mv"].forEach(q=>$(q).hidden=true);showHUD(true);
  canvas.focus();updateCamera(0,true);
  card(STAGES[n].name.toUpperCase(),STAGES[n].sub,3.2);
  if(n===2){say("TWOPACK","I told on my mama for runnin' a light,",2.3);later(3.4,()=>toast("New side of the block: the crosswalk, Daddy's hammock, the squirrel, the ice-cream line."));}
}
function stage1Clear(){
  if(S.mode!=="play"&&S.mode!=="puzzle")return;if(S.mode==="puzzle")closePuzzle();endLock();
  S.mode="cut";S.binoOn=false;rmb=false;for(const k in K)K[k]=false;showHUD(false);saveStage(2);
  card("STAGE 1 CLEAR","Everybody on the block got told on.",3);say("TWOPACK","Snitch season, baby!",2);sfx("win");
  later(3.2,playVideo);
}
function playVideo(){
  S.mode="video";if(musicG)musicG.gain.value=0;
  const mv=$("#mv"),v=$("#mvv");mv.hidden=false;$("#mvmsg").textContent="";$("#mvplay").hidden=true;
  v.onended=()=>startStage(2,true);
  v.onerror=null;const srcs=v.querySelectorAll("source");srcs[srcs.length-1].onerror=()=>{$("#mvmsg").textContent="The music video couldn't load here. Skip ahead to Stage 2.";};
  v.load();v.currentTime=0;const pr=v.play();if(pr&&pr.catch)pr.catch(()=>{$("#mvplay").hidden=false;});
  $("#mvskip").focus();
}
$("#mvplay").onclick=()=>{$("#mvplay").hidden=true;$("#mvv").play().catch(()=>{});};
$("#mvskip").onclick=()=>{const v=$("#mvv");v.pause();startStage(2,true);};
function startFinaleSetup(){
  const go=()=>{if(car.state!=="parked"){later(1,go);return;}
    for(const w of [W.dan,W.steve]){w.visible=false;w.rig.g.visible=false;}car.state="tohydrant";startCrime("cops");};
  go();
}
function startFinale(){
  const c=C.cops;c.handling=true;S.mode="cut";S.binoOn=false;showHUD(false);
  S.fin={cam:{p:new THREE.Vector3(39.4,2.3,5.4),l:new THREE.Vector3(35.4,1.1,-1.3),f:44},cuffed:false,garyPhone:false};
  Object.assign(P,{x:36.2,z:-1.9,yaw:0});
  say("TWOPACK","I'm reportin' this... to the POLICE!",2.0);
  later(1.2,()=>{sfx("siren");car.goal=30.6;car.state="goto";car.onArrive=()=>{
    sfx("door");const sl=[[35.0,-.9],[37.4,-.9]];[W.dan,W.steve].forEach((w,k)=>{w.x=car.x-.6+1.2*k;w.z=car.z-1.25;w.yaw=Math.PI;w.visible=true;w.rig.g.visible=true;w.target=sl[k];});
    talk([["TWOPACK","FINALLY! He right there, y'all! Right th- wait. What y'all doin'?",3.0],["STEVE","Sir, somebody called in a public nuisance.",2.4]],()=>{
      sfx("cuffs");S.fin.cuffed=true;
      later(.8,()=>{S.fin.cam={p:new THREE.Vector3(-1.4,1.5,4.2),l:new THREE.Vector3(-3.3,.5,.75),f:36};S.fin.garyPhone=true;S.fin.snap=true;
        talk([["GARY","Yeah, that's him, officer.",1.8],["GARY","...Heyyyy, 2-Pack.",2.0]],()=>{
          S.fin.garyPhone=false;S.fin.cam={p:new THREE.Vector3(39.4,2.3,5.4),l:new THREE.Vector3(35.4,1.1,-1.3),f:44};S.fin.snap=true;
          talk([["TWOPACK","...Officer. Ricky got your wallet.",2.2]],()=>{
            const w=W.ricky;w.x=46;w.z=.8;w.yaw=-Math.PI/2;w.visible=true;ricky.g.visible=true;w.speed=3.6;w.target=[-30,.8];S.fin.ricky=true;
            later(1.4,()=>talk([["DAN","...RICKYYYY!",2.0]],()=>later(1.8,()=>{S.told.add("cops");S.score+=1000;finishGame();})));});});});});};});
}
function updateFinale(dt){
  if(!S.fin)return;for(const w of [W.dan,W.steve])if(w.visible){if(stepWalker(w,dt))w.yaw=turnToward(w.yaw,Math.atan2(P.x-w.x,P.z-w.z),4*dt);}
  if(S.fin.ricky){stepWalker(W.ricky,dt);}
}
function finishGame(){
  S.mode="over";showHUD(false);$("#overtitle").textContent="Stage 2 clear";
  $("#o1").textContent=S.score.toLocaleString();$("#o2").textContent=S.busts;$("#o3").textContent=S.still;$("#o4").textContent=fmt(S.time);
  $("#overline").textContent="Gary called it in. To be continued...";$("#again2").hidden=false;$("#over").hidden=false;$("#again").focus();
}
function startGame(){
  initAudio();if(ac&&ac.state==="suspended")ac.resume();
  resetGame(1);S.mode="play";
  ["#title","#over","#mv"].forEach(q=>$(q).hidden=true);showHUD(true);
  canvas.focus();updateCamera(0,true);card("STAGE 1","Snitch Season",2.6);
  say("TWOPACK","Yeah... this one goes out to Precinct Nine.",2.4);
  later(2.6,()=>toast("Every crime gets reported its own way. Your case file says what to do next."));
}
function gameOver(){
  if(S.mode==="over")return;if(S.mode==="puzzle")closePuzzle();
  S.mode="over";S.binoOn=false;rmb=false;for(const k in K)K[k]=false;
  ["#plate","#cases","#keys","#prompt","#mini"].forEach(s=>$(s).hidden=true);endLock();
  $("#o1").textContent=S.score.toLocaleString();$("#o2").textContent=S.busts;$("#o3").textContent=S.still;$("#o4").textContent=fmt(S.time);
  $("#overline").textContent="I keep on callin', but nothin' gets done";$("#overtitle").textContent="Shift over";$("#again2").hidden=S.stage!==2;
  $("#over").hidden=false;$("#again").focus();
}
$("#start").onclick=startGame;$("#again").onclick=startGame;$("#cont").onclick=()=>startStage(2,false);$("#again2").onclick=()=>startStage(2,false);
if(savedStage()>=2)$("#cont").hidden=false;$("#hang").onclick=()=>{if(S.mode==="puzzle"){sfx("buzz");closePuzzle();}};

// input
addEventListener("keydown",e=>{
  const k=e.key.toLowerCase();
  if(S.mode==="puzzle"){if(k==="escape")$("#hang").click();else if(pz.keyHandler)pz.keyHandler(e.key);return;}
  if(S.mode==="cut"||S.mode==="video")return;
  if(k==="p"&&(S.mode==="play"||S.mode==="pause")){S.mode=S.mode==="play"?"pause":"play";$("#pause").hidden=S.mode!=="pause";if(ac)S.mode==="pause"?ac.suspend():ac.resume();return;}
  if(k==="m"){S.musicOn=!S.musicOn;if(musicG)musicG.gain.value=S.musicOn?.3:0;toast(S.musicOn?"Music on":"Music off");return;}
  if(S.mode!=="play")return;
  if([" ","arrowup","arrowdown","arrowleft","arrowright"].includes(k))e.preventDefault();
  if(S.lock){if(k==="e"&&!e.repeat)lockPress();else if(k==="escape")cancelLock();return;}
  K[k]=true;if(k==="e"&&!e.repeat)interact();
});
addEventListener("keyup",e=>{K[e.key.toLowerCase()]=false;});
addEventListener("blur",()=>{for(const k in K)K[k]=false;rmb=false;drag=null;});
canvas.addEventListener("contextmenu",e=>e.preventDefault());
canvas.addEventListener("mousedown",e=>{canvas.focus();if(e.button===2)rmb=true;else if(e.button===0)drag={x:e.clientX,y:e.clientY};});
addEventListener("mouseup",e=>{if(e.button===2)rmb=false;if(e.button===0)drag=null;});
addEventListener("mousemove",e=>{
  if(S.mode!=="play")return;
  if(S.binoOn){const s=.0022*(binoFov/16);binoYaw-=e.movementX*s;binoPitch=clamp(binoPitch-e.movementY*s,-.5,.45);return;}
  if(drag){camYaw-=e.movementX*.006;camPitch=clamp(camPitch+e.movementY*.004,.05,.95);}
});
canvas.addEventListener("wheel",e=>{if(S.binoOn){binoFov=clamp(binoFov+Math.sign(e.deltaY)*3,8,34);e.preventDefault();}},{passive:false});
document.addEventListener("visibilitychange",()=>{if(document.hidden&&S.mode==="play"){S.mode="pause";$("#pause").hidden=false;if(ac)ac.suspend();}});

function resize(){const w=innerWidth,h=innerHeight;const r=Math.min(w,h)*.36,cx=w/2,cy=h/2,o=r*.72;$("#binosvg").setAttribute("viewBox",`0 0 ${w} ${h}`);for(const id of ["#binorect","#binoshade"]){$(id).setAttribute("width",w);$(id).setAttribute("height",h);}[["#bc1",cx-o],["#bc2",cx+o]].forEach(([id,x])=>{const c=$(id);c.setAttribute("cx",x);c.setAttribute("cy",cy);c.setAttribute("r",r);});renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();}
addEventListener("resize",resize);

// ===================================================================== loop
let last=performance.now();
function tick(dt){
  clock+=dt;runLater();
  if(S.mode==="play"||S.mode==="puzzle"){S.time+=dt;updateCrimes(dt);updateCar(dt);if(S.mode==="play"){updatePlayer(dt);updateBino(dt);}}
  else{updateCar(dt);if(S.mode==="cut")updateFinale(dt);}
  animateAll(dt);updateCamera(dt);updateSubs(dt);updateHUD(dt);
  sun.position.set(P.x+14,26,P.z+12);sun.target.position.set(P.x,0,P.z);
}
function frame(now){
  const dt=Math.min(.05,(now-last)/1000);last=now;
  if(S.mode!=="pause")tick(dt);
  renderer.render(scene,camera);
  requestAnimationFrame(frame);
}
S.stage=1;S.told=new Set();build();resize();startCrime("gary");updateCamera(0,true);
window.__tt={S,C,P,car,W,W_,K,tick,interact,openPuzzle,nearestInteract,lockPress,startCrime,cur,startStage,stage1Clear,playVideo,checkStage,aim:(y,p)=>{binoYaw=y;binoPitch=p;},render:()=>renderer.render(scene,camera)};
requestAnimationFrame(frame);
