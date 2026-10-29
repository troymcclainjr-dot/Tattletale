// minigames.js - Hands-on minigames: the whistle on the beat, the ruler, recording the snoring, the 911 call.
"use strict";
// ---- hands-on minigames: the whistle (on the beat) and the ruler
function startRhythm(c){const B=60/90;c.frozen=true;S.lock={kind:"rhythm",c,t0:clock+1.2,n:6,hits:0,judged:[],next:0,B};P.yaw=Math.PI;
  $("#lkeye").textContent="CITIZEN'S CITATION";$("#lkt").textContent="Blow the whistle on the beat";
  $("#lkbody").innerHTML=`<div class="track"><span id="lkhead" class="head"></span>${[0,1,2,3,4,5].map(i=>`<span class="pip" style="left:${((i+1)/7*100).toFixed(2)}%"></span>`).join("")}</div>`;
  $("#lkmsg").textContent="Press E as the line crosses each dot. Hit 4 of 6. Esc to back off.";$("#lock").hidden=false;
  say("TWOPACK","Hold it right there, ma'am!",1.4);}
const inch=v=>{const e=Math.round(v*16);if(e===0)return "0 in";if(e===16)return "1 in";let a=e,b=16;while(a%2===0){a/=2;b/=2;}return `${a}/${b} in`;};
function startRuler(c){S.lock={kind:"ruler",c,t:rand(0,1.8),v:0};
  $("#lkeye").textContent="LAWN INSPECTION";$("#lkt").textContent="Measure the grass";
  let ticks="";for(let i=0;i<=16;i++){const x=(i/16*100).toFixed(2);ticks+=`<span class="tk" style="left:${x}%;height:${i%4===0?60:i%2===0?40:24}%"></span>`;if(i%4===0)ticks+=`<span class="lb" style="left:${x}%">${["0","1/4","1/2","3/4","1"][i/4]}</span>`;}
  $("#lkbody").innerHTML=`<div class="ruler"><span class="band"></span>${ticks}<span id="lkneedle" class="needle"></span></div><div class="read">Reading: <b id="lkread">0 in</b></div>`;
  $("#lkmsg").textContent="Press E when it reads exactly 1/4 inch. Esc to stop.";$("#lock").hidden=false;}
function endLock(){S.lock=null;$("#lock").hidden=true;}
const dadSnoring=()=>((clock%3.2)<1.6);
function startRecord(c){S.lock={kind:"record",c,was:dadSnoring()};P.yaw=Math.atan2(HAMMOCK[0]-P.x,HAMMOCK[1]-P.z);
  $("#lkeye").textContent="FLIP PHONE · VOICE MEMO";$("#lkt").textContent="Record the snoring";
  $("#lkbody").innerHTML=`<div class="rec"><div class="vu"><span id="lkvu" style="width:5%"></span></div><div class="read">Snores on tape: <b id="lkn">0/3</b></div></div>`;
  $("#lkmsg").textContent="Hold still. It records every snore. Esc to stop.";$("#lock").hidden=false;sfx("click");}
function call911(ph){P.x=ph.x;P.z=ph.z+.72;P.yaw=Math.PI;S.lock={kind:"scene"};const c=C.cops;sfx("pickup");
  [0,.15,.3].forEach(t=>later(.5+t,()=>sfx("dtmf",["9","1","1"][Math.round(t/.15)])));
  later(1.0,()=>talk([["OPERATOR","Nine-one-one, what's your emer-",1.4],["TWOPACK","It's me.",1.0]],()=>{sfx("hangup");later(.3,()=>sfx("busy"));
    talk([["TWOPACK","Hello? ...HELLO?! Y'all hung up on a SNITCH?!",2.4],["TWOPACK","I'm reportin' this... to the POLICE!",2.2]],()=>{endLock();adv(c);});}));}
function cancelLock(){const L=S.lock;if(!L||L.kind==="scene")return;if(L.kind==="rhythm")L.c.frozen=false;endLock();}
function updateLock(dt){const L=S.lock;if(!L)return;
  if(L.kind==="rhythm"){const B=L.B;
    while(L.next<L.n&&clock>=L.t0+L.next*B){sfx("tick");L.next++;}
    const u=(clock-(L.t0-B))/((L.n+1)*B);const h=$("#lkhead");if(h)h.style.left=(clamp(u,0,1)*100).toFixed(2)+"%";
    if(clock>L.t0+(L.n-1)*B+.4){const c=L.c,ok=L.hits>=4;endLock();
      if(ok){c.handling=true;sfx("win");talk([["TWOPACK","Ma'am. That's a citation.",1.8],["GRANDMA","Sonny, I'm ninety-one.",1.8]],()=>busted(c,"CITED!"));}
      else{c.frozen=false;toast(`Off the beat (${L.hits}/6). You need 4. Try again.`);sfx("buzz");}}}
  else if(L.kind==="record"){const sn=dadSnoring(),c=L.c;const vu=$("#lkvu");if(vu)vu.style.width=(sn?55+40*Math.abs(Math.sin(clock*9)):6+4*Math.sin(clock*5)).toFixed(0)+"%";
    if(sn&&!L.was){c.snores=(c.snores||0)+1;pop(new THREE.Vector3(HAMMOCK[0],1.2,HAMMOCK[1]),`SNORE ${c.snores}/3`);const n=$("#lkn");if(n)n.textContent=`${c.snores}/3`;
      if(c.snores>=3){endLock();sfx("shutter");adv(c);}}
    L.was=sn;}
  else if(L.kind==="ruler"){L.t+=dt;L.v=.5-.5*Math.cos(L.t*TAU/1.8);const n=$("#lkneedle");if(n)n.style.left=(L.v*100).toFixed(2)+"%";const r=$("#lkread");if(r)r.textContent=inch(L.v);}
}
function lockPress(){const L=S.lock;if(!L)return;
  if(L.kind==="rhythm"){const i=Math.round((clock-L.t0)/L.B),bt=L.t0+i*L.B;
    if(i>=0&&i<L.n&&!L.judged[i]&&Math.abs(clock-bt)<.17){L.judged[i]=1;L.hits++;sfx("whistle");const pp=document.querySelectorAll("#lock .pip")[i];if(pp)pp.classList.add("hit");}
    else sfx("click");}
  else if(L.kind==="ruler"){const c=L.c;
    if(Math.abs(L.v-.25)<.04){endLock();sfx("shutter");say(...c.line,2.6);pop(c.target(),"1/4 INCH");adv(c);}
    else{c.left-=3;sfx("buzz");$("#lkmsg").textContent=`That reads ${inch(L.v)}. Again. (-3s)`;}}
}
