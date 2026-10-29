// movement.js - Collision bodies and NPC walking. Nobody walks sideways; nobody passes through anybody.
"use strict";
// ===================================================================== bodies (for "nobody passes through anybody")
const bodies=[];
function addBody(o){bodies.push(o);return o;}
function carBoxes(){const a=[];if(car&&car.state!=="hidden")a.push(car);if(W.mamaCar&&W.mamaCar.g.visible)a.push(W.mamaCar);return a;}
function blockedAhead(self,nx,nz,fx,fz,r){
  for(const b of bodies){if(b===self||!b.on())continue;const p=b.pos();const dx=p.x-nx,dz=p.z-nz;const rr=r+b.r;
    if(dx*dx+dz*dz<rr*rr&&(dx*fx+dz*fz)>-0.05)return b;}
  for(const cb of carBoxes()){if(self===carBody&&cb===car)continue;const dx=nx-cb.x,dz=nz-cb.z;if(Math.abs(dx)<2.2+r&&Math.abs(dz)<.95+r&&(-dx*fx-dz*fz)>-0.3)return carBody;}
  for(const s of SOLIDS){if(s.c){const dx=s.x-nx,dz=s.z-nz;if(dx*dx+dz*dz<(s.r+r)**2&&(dx*fx+dz*fz)>0)return s;}
    else if(nx>s.x0-r&&nx<s.x1+r&&nz>s.z0-r&&nz<s.z1+r){const cx=clamp(nx,s.x0,s.x1)-nx,cz=clamp(nz,s.z0,s.z1)-nz;if(cx*fx+cz*fz>=0)return s;}}
  return null;
}
// NPC walker: turns in place to face where it's going, then walks forward. Never walks sideways or backwards.
function makeWalker(rig,r,speed){return {rig,r,x:0,z:0,yaw:0,speed,target:null,moving:false,waiting:0,visible:false};}
function stepWalker(w,dt){
  w.moving=false;const tg=w.detour||w.target;if(!tg)return true;
  const dx=tg[0]-w.x,dz=tg[1]-w.z,d=Math.hypot(dx,dz);
  if(d<.06){if(w.detour){w.detour=null;return false;}w.target=null;return true;}
  const want=Math.atan2(dx,dz);w.yaw=turnToward(w.yaw,want,5*dt);
  if(Math.abs(angDiff(w.yaw,want))>.3)return false;
  const fx=Math.sin(w.yaw),fz=Math.cos(w.yaw),st=Math.min(d,w.speed*dt);
  const blk=blockedAhead(w.body,w.x+fx*st,w.z+fz*st,fx,fz,w.r);
  if(blk){w.waiting+=dt;
    if(blk.c===1&&!w.detour&&w.waiting>.4){const px=-fz,pz=fx,side=((blk.x-w.x)*px+(blk.z-w.z)*pz)>0?-1:1,off=blk.r+w.r+.3;w.detour=[blk.x+px*side*off+fx*.35,blk.z+pz*side*off+fz*.35];w.waiting=0;}
    else if(w.detour&&w.waiting>1.5){w.detour=null;w.waiting=0;}
    return false;}
  w.waiting=0;w.x+=fx*st;w.z+=fz*st;w.moving=true;w.rig.phase+=st*(4.2/w.rig.H);return false;
}
