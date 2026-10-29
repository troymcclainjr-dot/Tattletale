// interact.js - The E key: what 2-Pack can do where he's standing.
"use strict";
// ===================================================================== interactions
function nearestInteract(){
  if(S.lock)return null;
  for(const c of Object.values(C)){if(!c.active||!c.act||c.dispatched||c.handling)continue;const a=c.act();if(a){const d=Math.hypot(P.x-a.x,P.z-a.z);if(d<a.r&&d>=(a.rmin||0))return {kind:"crime",label:a.label,fn:a.fn};}}
  for(const ph of W_.phones)if(Math.hypot(P.x-ph.x,P.z-(ph.z+.55))<1.25)return {kind:"phone",ph,label:"Use payphone"};
  if(Math.hypot(P.x-36.2,P.z+1.7)<2.3){
    if(car.state!=="parked")return {kind:"copsaway",label:"Precinct 9 (cops out on a call)"};
    return {kind:"cops",label:C.ricky.active&&cur(C.ricky).k==="getdan"?"Get Officer Dan":"Tell the cops"};}
  return null;
}
function pendingEvidence(){return Object.values(C).filter(c=>c.active&&cur(c).k==="call"&&!c.dispatched&&!c.handling);}
function nextHint(){const c=Object.values(C).filter(c=>c.active&&c.id!=="gary"&&!c.dispatched&&!c.handling).sort((a,b)=>a.left-b.left)[0]||C.gary;return `${short(c)}: ${stepText(cur(c))}`;}
function interact(){
  if(S.binoOn||S.lock)return;const it=nearestInteract();if(!it)return;
  if(it.kind==="crime"){it.fn();return;}
  if(it.kind==="copsaway"){toast("The cops are out on a call. Come back when the car's back.");return;}
  if(it.kind==="phone"&&C.cops.active&&cur(C.cops).k==="call911"){call911(it.ph);return;}
  const r=C.ricky;
  if(it.kind==="cops"&&r.active&&cur(r).k==="getdan"&&!W.dan.escort){startEscort();return;}
  const ev=pendingEvidence();
  if(!ev.length){say("TWOPACK","Hold up. I need evidence first.",1.8);toast(`Nothing to call in yet. ${nextHint()}`);return;}
  if(it.kind==="cops"){say("DAN","Sir... we're on our lunch break.",2.0);later(2.1,()=>{say("TWOPACK","It's TEN in the MORNIN'!",1.8);dispatch(pendingEvidence().map(c=>c.id));});return;}
  openPuzzle(it.ph,ev);
}
