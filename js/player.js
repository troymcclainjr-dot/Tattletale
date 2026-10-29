// player.js - 2-Pack's controls, the binoculars (evidence), the camera.
"use strict";
// ===================================================================== player, binoculars, camera
const ray=new THREE.Raycaster();
function resolve(o,r){
  for(const s of SOLIDS){
    if(s.c){const dx=o.x-s.x,dz=o.z-s.z,d=Math.hypot(dx,dz),rr=s.r+r;if(d<rr&&d>1e-4){o.x=s.x+dx/d*rr;o.z=s.z+dz/d*rr;}}
    else{const cx=clamp(o.x,s.x0,s.x1),cz=clamp(o.z,s.z0,s.z1),dx=o.x-cx,dz=o.z-cz,d=Math.hypot(dx,dz);
      if(d<r){if(d>1e-4){o.x=cx+dx/d*r;o.z=cz+dz/d*r;}else{const opts=[[s.x0-r-o.x,0],[s.x1+r-o.x,0],[0,s.z0-r-o.z],[0,s.z1+r-o.z]].sort((a,b)=>Math.abs(a[0]+a[1])-Math.abs(b[0]+b[1]));o.x+=opts[0][0];o.z+=opts[0][1];}}}
  }
  for(const b of bodies){if(b===playerBody||!b.on())continue;const p=b.pos(),dx=o.x-p.x,dz=o.z-p.z,d=Math.hypot(dx,dz),rr=b.r+r;if(d<rr&&d>1e-4){o.x=p.x+dx/d*rr;o.z=p.z+dz/d*rr;}}
  for(const cb of carBoxes()){const dx=o.x-cb.x,dz=o.z-cb.z,hx=2.2+r,hz=.95+r;
    if(Math.abs(dx)<hx&&Math.abs(dz)<hz){if(hx-Math.abs(dx)<hz-Math.abs(dz))o.x=cb.x+Math.sign(dx||1)*hx;else o.z=cb.z+Math.sign(dz||1)*hz;}}
  o.x=clamp(o.x,BOUNDS.x0,BOUNDS.x1);o.z=clamp(o.z,BOUNDS.z0,BOUNDS.z1);
}
function updatePlayer(dt){
  P.moving=false;P.run=false;
  if(S.binoOn||S.lock)return;
  if(K.arrowleft)camYaw+=1.9*dt;if(K.arrowright)camYaw-=1.9*dt;
  const fw=(K.w||K.arrowup?1:0)-(K.s||K.arrowdown?1:0),rt=(K.d?1:0)-(K.a?1:0);
  const fx=Math.sin(camYaw),fz=Math.cos(camYaw);
  const dx=fx*fw-fz*rt,dz=fz*fw+fx*rt;
  if(dx||dz){
    const want=Math.atan2(dx,dz);P.yaw=turnToward(P.yaw,want,11*dt);
    const align=Math.max(0,Math.cos(angDiff(P.yaw,want)));P.run=!!K.shift;
    const sp=(P.run?6.4:3.3)*align*align*align;const ox=P.x,oz=P.z;
    P.x+=Math.sin(P.yaw)*sp*dt;P.z+=Math.cos(P.yaw)*sp*dt;resolve(P,.33);
    const moved=Math.hypot(P.x-ox,P.z-oz);P.moving=moved>.002;tp.phase+=moved*(P.run?2.6:3.2);
  }
}
function updateBino(dt){
  const want=(rmb||K[" "])&&S.mode==="play"&&!S.lock;
  if(want&&!S.binoOn){S.binoOn=true;binoYaw=camYaw;binoPitch=.02;binoFov=22;}
  if(!want&&S.binoOn){S.binoOn=false;camYaw=binoYaw;}
  ["#bino","#reticle","#binolabel","#binotop"].forEach(q=>$(q).hidden=!S.binoOn);
  tp.bino.visible=S.binoOn;
  if(!S.binoOn){S.ev=0;S.evId=null;return;}
  if(K.a||K.arrowleft)binoYaw+=.9*dt*(binoFov/16);if(K.d||K.arrowright)binoYaw-=.9*dt*(binoFov/16);
  if(K.w||K.arrowup)binoPitch+=.6*dt*(binoFov/16);if(K.s||K.arrowdown)binoPitch-=.6*dt*(binoFov/16);
  binoPitch=clamp(binoPitch,-.5,.45);
  P.yaw=turnToward(P.yaw,binoYaw,8*dt);
  // what's in the circle?
  const eye=new THREE.Vector3(P.x,groundY(P.x,P.z)+1.68,P.z);
  const dir=new THREE.Vector3(Math.sin(binoYaw)*Math.cos(binoPitch),Math.sin(binoPitch),Math.cos(binoYaw)*Math.cos(binoPitch));
  let best=null,bestA=.065*(binoFov/16)+.02,label="";
  for(const c of Object.values(C)){
    if(!c.active)continue;const t=c.target(),v=t.clone().sub(eye),d=v.length(),a=v.normalize().angleTo(dir);
    if(a<bestA){ray.set(eye,v);ray.far=d-.7;const hit=ray.intersectObjects(OCCLUDERS,false).length>0;if(!hit){best=c;bestA=a;best.d=d;}}
  }
  let prog=0;
  if(best){const st=cur(best),nm=short(best).toUpperCase();
    const spyable=(st.k==="spy"||st.k==="tail")&&!best.dispatched&&!best.handling&&(!best.spyOk||best.spyOk());
    if(!spyable){S.ev=0;
      label=`${nm} · `+(best.dispatched?"COPS ON THE WAY":best.id==="mama"&&st.k==="spy"?"WAIT FOR THE RED LIGHT":best.id==="cops"&&st.k==="spy"?"WAIT TILL THEY PARK":st.k==="tail"?(best.sus>0?"ACTING NORMAL...":best.bending?"GOT THIS ONE. NEXT STOP.":"WAIT TILL HE BENDS ONE"):"NEXT: "+st.m);}
    else if(best.d<4){label="TOO CLOSE. BACK UP.";S.ev=0;}
    else{if(S.evId!==best.id){S.evId=best.id;S.ev=0;}S.ev+=dt/1.3;label=`${nm} · ${Math.round(best.d*3.3)} FT`;prog=S.ev;
      if(S.ev>=1){S.ev=0;sfx("shutter");
        if(st.k==="tail"){best.photos++;best.lastPhoto=best.stop;pop(best.target(),`PHOTO ${best.photos}/2`);if(best.photos>=2){say(...best.line,2.6);adv(best);}}
        else{if(best.onSpy)best.onSpy();else{say(...best.line,2.8);pop(best.target(),"EVIDENCE");}adv(best);}}}
  }else{S.ev=0;S.evId=null;label="NOTHING TO REPORT. YET.";}
  $("#ring").setAttribute("stroke-dashoffset",(213.6*(1-clamp(prog,0,1))).toFixed(1));
  $("#binolabel").textContent=label;
}
const camPos=new THREE.Vector3(),camLook=new THREE.Vector3();
function updateCamera(dt,snap){
  if(S.mode==="title"){const a=clock*.08;camera.fov=40;camera.position.set(6+Math.cos(a)*16,6.5,6+Math.sin(a)*9);camera.lookAt(4,1.2,-2);camera.updateProjectionMatrix();return;}
  if(S.mode==="cut"&&S.fin){const c=S.fin.cam,k=S.fin.snap||snap?1:Math.min(1,dt*2.5);S.fin.snap=false;camPos.lerp(c.p,k);camLook.lerp(c.l,k);camera.fov=lerp(camera.fov,c.f,k);camera.position.copy(camPos);camera.lookAt(camLook);camera.updateProjectionMatrix();return;}
  if(S.mode==="puzzle"&&S.pz){const t=S.pz.focus.target();const want=new THREE.Vector3(t.x-2.6,2.5,Math.max(t.z+6.5,4));
    camPos.lerp(want,snap?1:Math.min(1,dt*3));camLook.lerp(t,snap?1:Math.min(1,dt*4));camera.fov=lerp(camera.fov,38,Math.min(1,dt*3));camera.position.copy(camPos);camera.lookAt(camLook);camera.updateProjectionMatrix();return;}
  if(S.binoOn){const gy=groundY(P.x,P.z);camera.position.set(P.x+Math.sin(binoYaw)*.25,gy+1.68,P.z+Math.cos(binoYaw)*.25);
    camera.lookAt(camera.position.x+Math.sin(binoYaw)*Math.cos(binoPitch),camera.position.y+Math.sin(binoPitch),camera.position.z+Math.cos(binoYaw)*Math.cos(binoPitch));
    camera.fov=binoFov;camera.updateProjectionMatrix();camPos.copy(camera.position);return;}
  const gy=groundY(P.x,P.z),head=new THREE.Vector3(P.x,gy+1.5,P.z),dist=5.6;
  const want=new THREE.Vector3(P.x-Math.sin(camYaw)*Math.cos(camPitch)*dist,gy+1.5+Math.sin(camPitch)*dist,P.z-Math.cos(camYaw)*Math.cos(camPitch)*dist);
  const v=want.clone().sub(head),L=v.length();ray.set(head,v.normalize());ray.far=L;const hit=ray.intersectObjects(OCCLUDERS,false)[0];
  if(hit)want.copy(head).addScaledVector(v,Math.max(.8,hit.distance-.35));
  camPos.lerp(want,snap?1:Math.min(1,dt*9));camLook.lerp(head,snap?1:Math.min(1,dt*12));
  camera.fov=lerp(camera.fov,55,Math.min(1,dt*6));camera.position.copy(camPos);camera.lookAt(camLook);camera.updateProjectionMatrix();
}
