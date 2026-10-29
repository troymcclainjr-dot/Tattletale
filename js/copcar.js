// copcar.js - The cop car: leaving the station, driving to a crime, the bust, coming home.
"use strict";
// ===================================================================== the cop car
function updateCar(dt){
  car.t+=dt;
  const cops=[W.dan,W.steve].filter(w=>!w.escort);
  if(car.state==="leaving"){                // the cops amble down the steps and get in
    if(car.t>2.2){for(const w of cops){w.visible=false;w.rig.g.visible=false;}car.state="pick";sfx("siren");}
  }
  if(car.state==="pick"){
    car.queue=car.queue.filter(id=>C[id].active);
    if(!car.queue.length){car.state="home";}
    else{car.queue.sort((a,b)=>Math.abs(C[a].target().x-car.x)-Math.abs(C[b].target().x-car.x));car.cur=car.queue.shift();
      const t=C[car.cur].target();car.stopX=clamp(t.x+3.6,-27,42);car.state="drive";}
  }
  if(car.state==="drive"||car.state==="home"||car.state==="tohydrant"||car.state==="goto"){
    const goal={home:42,drive:car.stopX,tohydrant:9.6,goto:car.goal}[car.state];const dir=Math.sign(goal-car.x);
    const wantH=dir<0?Math.PI:0;
    if(Math.abs(goal-car.x)<.05){car.x=goal;
      if(car.state==="home"){car.h=turnToward(car.h,Math.PI,2.6*dt);if(Math.abs(angDiff(car.h,Math.PI))<.01){car.state="parked";copsHome();sfx("door");}}
      else if(car.state==="tohydrant"){car.state="hydrant";sfx("door");}
      else if(car.state==="goto"){car.state="idle";if(car.onArrive){const f=car.onArrive;car.onArrive=null;f();}}
      else{car.state="arrive";car.t=0;}
    }else if(Math.abs(angDiff(car.h,wantH))>.01){car.h=turnToward(car.h,wantH,2.6*dt);}  // turn around in place before driving
    else{
      const fx=Math.cos(car.h);let blocked=false;
      for(const b of bodies){if(!b.on())continue;const p=b.pos();const ahead=(p.x-car.x)*fx;if(ahead>0&&ahead<3.1+b.r&&Math.abs(p.z-car.z)<1.0+b.r)blocked=true;}
      if(blocked){if(car.honk<=0){sfx("honk");car.honk=2.5;}}
      else{const sp=Math.min(9,1.2+Math.abs(goal-car.x)*1.4);car.x+=Math.sign(goal-car.x)*Math.min(Math.abs(goal-car.x),sp*dt);}
    }
  }
  car.honk-=dt;
  if(car.state==="arrive"){                 // the cops get out and walk over
    const c=C[car.cur],t=c.target();
    if(car.t<.05){const sl=c.slots(t);cops.forEach((w,k)=>{w.x=car.x-.6+1.2*k;w.z=car.z-1.25;w.yaw=Math.PI;w.visible=true;w.rig.g.visible=true;w.target=freeSpot(sl[k][0],sl[k][1],w);});sfx("door");}
    let there=0;for(const w of cops){if(stepWalker(w,dt)){w.yaw=turnToward(w.yaw,Math.atan2(t.x-w.x,t.z-w.z),4*dt);there++;}}
    if((there===cops.length&&car.t>1)||car.t>9){car.state="bust";car.t=0;car.lines=c.bust.slice();car.lineT=0;}
  }
  if(car.state==="bust"){
    const c=C[car.cur],t=c.target();for(const w of cops)w.yaw=turnToward(w.yaw,Math.atan2(t.x-w.x,t.z-w.z),4*dt);
    car.lineT-=dt;
    if(car.lineT<=0){if(car.lines.length){const [who,txt,d]=car.lines.shift();say(who,txt,d);car.lineT=d;}
      else{busted(c);car.state="return";car.t=0;cops.forEach(w=>{w.target=[car.x+(w===W.dan?-.6:.6),car.z-1.25];});}}
  }
  if(car.state==="return"){
    let back=0;for(const w of cops)if(stepWalker(w,dt))back++;
    if(back===cops.length||car.t>8){for(const w of cops){w.visible=false;w.rig.g.visible=false;}car.state="pick";}
  }
  car.g.position.set(car.x,0,car.z);car.g.rotation.y=car.h;
  const flash=!["parked","leaving","hydrant","idle"].includes(car.state);
  car.lr.material.emissiveIntensity=flash?(Math.sin(clock*14)>0?4:.2):.6;car.lb.material.emissiveIntensity=flash?(Math.sin(clock*14)>0?.2:4):.6;
}
function freeSpot(x,z,self){
  for(let k=0;k<10;k++){const ox=x+(k%2?1:-1)*Math.ceil(k/2)*.5;let ok=true;
    for(const b of bodies){if(b===self.body||!b.on())continue;const p=b.pos();if(Math.hypot(p.x-ox,p.z-z)<b.r+self.r+.1)ok=false;}
    for(const s of SOLIDS){if(s.c?Math.hypot(s.x-ox,s.z-z)<s.r+self.r:(ox>s.x0-self.r&&ox<s.x1+self.r&&z>s.z0-self.r&&z<s.z1+self.r))ok=false;}
    if(ok)return [ox,z];}
  return [x,z];
}
function busted(c,label){
  const t=c.target();pop(t,c.id==="gary"?"STILL THERE":(label||"BUSTED!"));
  S.told.add(c.id);
  if(c.id==="gary"){S.still++;c.si=0;c.dispatched=false;toast("He's still there.");sfx("buzz");checkStage();return;}
  S.busts++;const bonus=Math.round(c.pts*(1+Math.max(0,c.left)/c.full));S.score+=bonus;toast(`${short(c)} busted · +${bonus}`);sfx("win");
  endCrime(c,"busted");checkStage();
}
