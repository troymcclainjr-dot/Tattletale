// hud.js - On-screen stuff: subtitles, toasts, markers, the case file, the mini-map.
"use strict";
// ===================================================================== HUD
let subQ=[],subT=0;
const NAMES={TWOPACK:"2-Pack",COPS:"Dan & Steve",OPERATOR:"911",DAN:"Officer Dan",STEVE:"Officer Steve",GARY:"Gary",RICKY:"Ricky",TIMMY:"Little Timmy",MAMA:"Timmy's mama",GRANDMA:"Grandma",MAILMAN:"The mailman",MOM:"2-Pack's mama",DADDY:"2-Pack's daddy",VENDOR:"Ice-cream man",LINER:"Somebody in line"};
function say(who,text,dur=2.4){subQ.push([who,text,dur]);}
function updateSubs(dt){
  subT-=dt;
  if(subT<=0){const el=$("#subs");if(subQ.length){const [who,text,dur]=subQ.shift();el.innerHTML="<b></b><span></span>";el.firstChild.textContent=NAMES[who]||who;el.lastChild.textContent=text;el.hidden=false;subT=dur;
      const rigs={TWOPACK:[tp],GARY:[gary],RICKY:[ricky],DAN:[dan],STEVE:[steve],COPS:[dan,steve],TIMMY:[timmy],MAMA:[W.mama],GRANDMA:[granny],MAILMAN:[mailman],DADDY:[W.dad],VENDOR:[W.vendor]}[who]||[];rigs.forEach(r=>r.talk=dur*.85);}
    else el.hidden=true;}
}
let toastT=0;
function toast(t){const el=$("#toast");el.textContent=t;el.hidden=false;toastT=3.6;}
function pop(v,text){const d=document.createElement("div");d.className="mk pop";d.textContent=text;$("#markers").appendChild(d);d._v=v.clone().add(new THREE.Vector3(0,1,0));d._pop=1;setTimeout(()=>d.remove(),1700);}
function proj(v){const p=v.clone().project(camera);return {x:(p.x+1)/2*innerWidth,y:(1-p.y)/2*innerHeight,ok:p.z<1&&p.z>-1};}
let hudT=0;
function markPos(c){if(c.act&&!c.dispatched&&!c.handling){const a=c.act();if(a)return new THREE.Vector3(a.x,.3,a.z);}return c.target();}
const mini=$("#mini"),mg=mini.getContext("2d");
function drawMini(){
  const w=mini.clientWidth,h=mini.clientHeight;if(!w)return;const dpr=Math.min(2,window.devicePixelRatio||1);
  if(mini.width!==Math.round(w*dpr)){mini.width=Math.round(w*dpr);mini.height=Math.round(h*dpr);}
  mg.setTransform(dpr,0,0,dpr,0,0);
  const X=x=>5+(x+33)/79*(w-10),Z=z=>3+(z+8)/27*(h-6);
  const band=(z0,z1,c)=>{mg.fillStyle=c;mg.fillRect(0,Z(z0),w,Z(z1)-Z(z0));};
  mg.fillStyle="#14203f";mg.fillRect(0,0,w,h);
  band(-8,-7,"#3a3f55");band(-7,-3.2,"#4d6a3a");band(-3.2,0,"#8a8679");band(0,13,"#2b2c33");band(13,19,"#8a8679");
  mg.fillStyle="#2c5bd6";mg.fillRect(X(31.5),Z(-8),X(40.5)-X(31.5),Z(-6.2)-Z(-8));
  mg.fillStyle="#f6f1e3";mg.font="700 9px 'Courier Prime',monospace";mg.textBaseline="top";mg.fillText("P9",X(35),Z(-7.9));
  mg.fillText("BANK",X(26.4),Z(-7.9));
  for(const ph of W_.phones){mg.fillStyle="#6aa0ff";mg.fillRect(X(ph.x)-2.5,Z(ph.z)-2.5,5,5);}
  mg.fillStyle="#6aa0ff";mg.beginPath();mg.arc(X(MAILDROP[0]),Z(MAILDROP[1]),2.6,0,TAU);mg.fill();
  for(const c of Object.values(C)){if(!c.active||c.handling)continue;const st=cur(c),t=markPos(c);
    mg.fillStyle=c.dispatched?"#6aa0ff":(st.k==="spy"||st.k==="tail")?"#ff3b4e":"#f2d24a";
    mg.beginPath();mg.arc(X(t.x),Z(t.z),c.id==="gary"?3:4.2,0,TAU);mg.fill();mg.strokeStyle="#14203f";mg.lineWidth=1;mg.stroke();}
  mg.fillStyle="#f6f1e3";mg.fillRect(X(car.x)-5,Z(car.z)-2.5,10,5);
  if(W.dan.escort){mg.fillStyle="#2c5bd6";mg.beginPath();mg.arc(X(W.dan.x),Z(W.dan.z),3,0,TAU);mg.fill();}
  const px=X(P.x),pz=Z(P.z),fx=Math.sin(P.yaw),fz=Math.cos(P.yaw);
  mg.fillStyle="#f2d24a";mg.strokeStyle="#14203f";mg.beginPath();mg.moveTo(px+fx*7,pz+fz*7);mg.lineTo(px-fz*4-fx*3,pz+fx*4-fz*3);mg.lineTo(px+fz*4-fx*3,pz-fx*4-fz*3);mg.closePath();mg.fill();mg.stroke();
}
function updateHUD(dt){
  toastT-=dt;if(toastT<=0)$("#toast").hidden=true;
  const live=S.mode==="play"||S.mode==="puzzle";
  // markers
  for(const c of Object.values(C)){
    if(!c.mk){c.mk=document.createElement("div");c.mk.className="mk";$("#markers").appendChild(c.mk);}
    const st=cur(c),t=markPos(c),d=Math.hypot(t.x-P.x,t.z-P.z),spyish=st.k==="spy"||st.k==="tail";
    const show=c.active&&!c.handling&&live&&!S.lock&&d<38&&!(S.binoOn&&spyish);
    if(!show){c.mk.hidden=true;continue;}
    const p=proj(new THREE.Vector3(t.x,t.y+.9,t.z));if(!p.ok){c.mk.hidden=true;continue;}
    c.mk.hidden=false;c.mk.style.left=p.x+"px";c.mk.style.top=p.y+"px";
    const cls=c.dispatched?"mk dis":spyish?"mk":"mk ev";if(c.mk.className!==cls)c.mk.className=cls;
    const tx=c.dispatched?"COPS COMING":(st.k==="lead"&&W.dan.lost?"DAN STOPPED":st.m);if(c.mk.textContent!==tx)c.mk.textContent=tx;
  }
  for(const d of document.querySelectorAll(".mk.pop")){const p=proj(d._v);d.style.left=p.x+"px";d.style.top=p.y+"px";d.hidden=!p.ok;}
  // prompt
  const pr=$("#prompt");
  if(S.mode==="play"&&!S.binoOn&&!S.lock){const it=nearestInteract();if(it){pr.hidden=false;const t=it.label;if(pr.dataset.t!==t){pr.dataset.t=t;pr.innerHTML=`<kbd>E</kbd><span></span>`;pr.lastChild.textContent=t;}}else pr.hidden=true;}
  else pr.hidden=true;
  // live cam during the puzzle
  if(S.mode==="puzzle"&&S.pz){const f=S.pz.focus;$("#lclbl").textContent=`LIVE · ${short(f).toUpperCase()}`;const big=$("#lcbig");big.textContent=f.left===Infinity?"∞":fmt(f.left);big.className="big"+(f.left<10?" urgent":"");$("#lcwhat").textContent=f.title;
    if(!f.active&&!S.pz.done){toast("Too late. They got away.");closePuzzle();}}
  hudT-=dt;if(hudT>0)return;hudT=.15;
  if(live)drawMini();
  $("#score").textContent=S.score.toLocaleString();
  $("#rank").textContent=RANKS.filter(r=>S.score>=r[0]).pop()[1];
  document.querySelectorAll("#strikes i").forEach((i,k)=>i.classList.toggle("on",k<S.strikes));
  $("#still").textContent=S.still?`Gary: still there ×${S.still}`:"";
  const need=needList();const tkey=S.stage+"|"+[...S.told].join(",")+(C.cops.active?"|c":"");
  if($("#told").dataset.k!==tkey){$("#told").dataset.k=tkey;$("#stagelbl").textContent=`${STAGES[S.stage].name.toUpperCase()} · TOLD ON ${need.filter(i=>S.told.has(i)).length}/${need.length}`;
    $("#told").innerHTML="";need.concat(C.cops.active?["cops"]:[]).forEach(id=>{const sp=document.createElement("span");sp.textContent=TOLD_NAMES[id];if(S.told.has(id))sp.className="on";$("#told").appendChild(sp);});}
  // case file
  const list=Object.values(C).filter(c=>c.active).sort((a,b)=>(a.left===Infinity)-(b.left===Infinity)||a.left-b.left);
  const host=$("#cases");
  for(const c of Object.values(C))if(c.el&&!c.active){c.el.remove();c.el=null;}
  list.forEach(c=>{
    if(!c.el){c.el=document.createElement("div");c.el.innerHTML=`<div class="no"></div><div class="t"></div><div class="who"></div><div class="dir"><b></b><span></span></div><div class="nx"></div><div class="st"><span class="chip"></span><span class="tm"></span></div><div class="bar"><span></span></div>`;
      c.el.querySelector(".no").textContent=`CASE #0911-${String(c.no).padStart(3,"0")}`;c.el.querySelector(".t").textContent=c.title;c.el.querySelector(".who").textContent=c.who;}
    host.appendChild(c.el);
    const urgent=!c.dispatched&&!c.handling&&c.left<15;
    c.el.className="case"+(c.id==="gary"?" gary":"")+(c.dispatched?" dis":c.si>0?" ev":"")+(urgent?" urgent":"");
    const t=markPos(c),dx=t.x-P.x,dz=t.z-P.z,ang=Math.atan2(dx,dz)-(S.binoOn?binoYaw:camYaw);
    c.el.querySelector(".dir b").style.transform=`rotate(${(-ang*180/Math.PI).toFixed(0)}deg)`;
    c.el.querySelector(".dir span").textContent=Math.round(Math.hypot(dx,dz)*3.3)+" ft";
    const st=cur(c);
    c.el.querySelector(".nx").textContent=c.dispatched?"Cops on the way.":c.handling?"Going down right now.":stepText(st);
    c.el.querySelector(".chip").textContent=c.dispatched?"DISPATCHED":c.handling?"GOING DOWN":(st.k==="lead"&&W.dan.lost)?"DAN STOPPED":`STEP ${c.si+1}/${c.steps.length}`;
    c.el.querySelector(".tm").textContent=c.left===Infinity?"no rush":(c.dispatched||c.handling)?"paused":fmt(c.left);
    c.el.querySelector(".bar span").style.width=(c.left===Infinity?100:clamp(c.left/c.full,0,1)*100)+"%";
  });
}
