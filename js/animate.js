// animate.js - Animating everybody every frame.
"use strict";
// ===================================================================== animation of everybody
function animateAll(dt){
  if(!C.mama.active){W_.tlT+=dt;const ph=W_.tlT%14;setLight(ph<6?"green":ph<7.5?"yellow":"red");}
  const beat=clock*1.5; // 90 BPM
  // 2-Pack
  const gy=groundY(P.x,P.z);tp.g.visible=!S.binoOn;
  place(tp,P.x,P.z,P.yaw,gy);
  if(S.mode==="puzzle")pose(tp,{armR:[-2.75,.55],armL:[-.6,.15],nod:.05});
  else if(S.binoOn)pose(tp,{armR:[-2.45,.42],armL:[-2.45,.42]});
  else if(S.lock&&S.lock.kind==="rhythm"){const hit=S.lock.next>0&&((clock-S.lock.t0)%S.lock.B)<.2;pose(tp,{armR:[-2.6,.5],armL:[hit?-2.9:-1.6,.3],lean:-.05,mouth:hit?.9:.2});}
  else if(S.fin&&S.fin.cuffed)pose(tp,{armR:[.6,.2],armL:[.6,.2],nod:.15,mouth:.2});
  else if(S.lock&&(S.lock.kind==="record"||S.lock.kind==="scene"))pose(tp,{armR:[-2.75,.55],armL:[-.6,.15],nod:.05});
  else if(W.sq.held&&!S.binoOn)pose(tp,{walk:P.moving?.5:0,armL:[-1.5,.15],armR:P.moving?null:[-.4,.2]});
  else if(S.lock&&S.lock.kind==="ruler")pose(tp,{armR:[-.9,.15],armL:[-.9,.15],lean:.45,nod:.4});
  else if(P.moving)pose(tp,{walk:P.run?.95:.55,lean:P.run?.3:.05,armR:P.run?[-1.3*Math.sin(tp.phase),.1]:null,armL:P.run?[1.3*Math.sin(tp.phase),.1]:null,bob:P.run?.04*Math.abs(Math.sin(tp.phase)):0});
  else{const b=Math.abs(Math.sin(Math.PI*beat)),alt=Math.floor(beat)%2;pose(tp,{nod:.13*b,armR:[alt?-.5-.7*b:-.35,.3],armL:[alt?-.25:-.45-.6*b,.28],bob:-.02*b,mouth:.15});}
  // cops
  for(const w of [W.dan,W.steve]){if(!w.visible)continue;const r=w.rig;place(r,w.x,w.z,w.yaw);
    const idleDonut=car.state==="parked"||w.lost;const bite=idleDonut&&((clock*.5+(r===steve?.3:0))%1)<.2;
    if(w.moving)pose(r,{walk:.55,armR:[-.3,.1]});else pose(r,{armR:idleDonut?[bite?-2.4:-1.2,.25]:[-.4,.1],armL:[-.15,.12],mouth:bite?.5:0});
    r.donut.visible=car.state==="parked"||car.state==="leaving"||!!w.escort;}
  if(car.state==="leaving")for(const w of [W.dan,W.steve])if(!w.escort)w.yaw=turnToward(w.yaw,Math.PI*.5,3*dt);
  // Ricky
  if(W.ricky.visible){const w=W.ricky;place(ricky,w.x,w.z,w.yaw);pose(ricky,w.moving?{walk:.45,armR:[-.25,.1],armL:[.2,.1]}:{armR:[-.3,.1],armL:[0,.1],look:.2*Math.sin(clock)});}
  if(W.granny.visible){const w=W.granny;place(granny,w.x,w.z,w.yaw);pose(granny,{walk:w.moving?.22:0,lean:.3,armR:[-1.05,.02],armL:[-1.05,.02]});}
  if(timmy.g.visible){place(timmy,16.5,-3.75,0);pose(timmy,{armR:[-1.2,.1],armL:[-.6-.4*Math.abs(Math.sin(clock*1.5)),.1],look:.2*Math.sin(clock)});}
  if(W.mail.visible){const w=W.mail,mc=C.mail;place(mailman,w.x,w.z,w.yaw);
    const look=mc.sus>0?clamp(angDiff(w.yaw,Math.atan2(P.x-w.x,P.z-w.z)),-1.2,1.2):0;
    if(w.moving)pose(mailman,{walk:.5,armR:[-.3,.1],armL:[.2,.1],look});
    else if(mc.bending){const bnd=.5+.5*Math.sin(clock*3);pose(mailman,{armR:[-1.4,-.1-.15*bnd],armL:[-1.4,.1+.2*bnd],nod:.2,look:.15*Math.sin(clock*.7)});W.letter.rotation.y=.8*bnd;}
    else pose(mailman,{armR:[-.2,.1],armL:[-.2,.1],look});
    W.letter.visible=!!mc.bending;}
  if(W.mama.g.visible){place(W.mama,17.1,-6.7,0,.4);pose(W.mama,{armR:[-.35,.55],armL:[-.35,.55],lean:-.05,nod:-.05});}
  // stage 2 cast
  if(W.dad.on||W.dad.fall>=0){const o=W.dad.outer;const sn=dadSnoring()&&!W.dad.awake;
    if(W.dad.awake&&W.dad.fall>=0){W.dad.fall=Math.min(1,W.dad.fall+dt*2.2);const u=W.dad.fall;o.position.y=lerp(1.02,.2,u*u);o.position.z=HAMMOCK[1]-.85*u;o.rotation.z=.6*Math.sin(u*Math.PI);}
    pose(W.dad,{armR:W.dad.awake?[-2.6,.6]:[-.2,.4],armL:W.dad.awake?[-2.6,.6]:[-.4,.6],mouth:sn?.9:.3});
    W.zz.forEach((z,k)=>{const u=(clock*.4+k/3)%1;z.visible=!W.dad.awake&&W.dad.on;z.position.set(HAMMOCK[0]-1.1+.4*u,1.4+1.3*u,HAMMOCK[1]+.2);z.scale.setScalar(.4+.9*u);});
    if(sn&&!W.dad.snd&&C.daddy.active&&Math.hypot(P.x-HAMMOCK[0],P.z-HAMMOCK[1])<16){sfx("snore");}W.dad.snd=sn;}
  else W.zz.forEach(z=>z.visible=false);
  if(W.sq.g.visible){const q=W.sq;
    if(q.held){const hp=new THREE.Vector3();tp.arms[1].children[1].getWorldPosition(hp);q.g.position.set(hp.x,hp.y-.25,hp.z);q.g.rotation.set(.3*Math.sin(clock*20),P.yaw+Math.PI,.4*Math.sin(clock*17));}
    else if(q.jailed){q.g.position.set(JAIL[0],.62,JAIL[1]);q.g.rotation.set(0,.4*Math.sin(clock*1.3),0);}
    else{q.g.position.set(q.x,groundY(q.x,q.z)+(q.moving?.06*Math.abs(Math.sin(clock*22)):0),q.z);q.g.rotation.set(0,q.yaw,0);}}
  for(const L of W.liners){if(!L.rig.g.visible)continue;if(L.told)L.yaw=turnToward(L.yaw,Math.atan2(W.baby.x-L.x,W.baby.z-L.z),4*dt);place(L.rig,L.x,L.z,L.yaw);
    pose(L.rig,L.told?{armR:[-.9,.45],armL:[-.9,.45],nod:-.1}:{armR:[-.15,.1],armL:[-.15,.1],look:.25*Math.sin(clock*.6+L.x)});}
  place(W.vendor,CART[0]+.95,CART[1],-Math.PI/2);pose(W.vendor,{armR:[-1.1+.3*Math.sin(clock*2),.1],armL:[-.9,.1]});
  if(W.baby.visible){const b=W.baby;W.babyRig.phase+=0;place(W.babyRig,b.x,b.z,b.yaw,groundY(b.x,b.z)+.12);W.babyRig.g.rotation.x=1.15;
    const cr=Math.sin(clock*7);pose(W.babyRig,{armR:[-1.2+.4*cr,.05],armL:[-1.2-.4*cr,.05],nod:-1.0});W.babyRig.legs[0].rotation.x=-1.3+.3*cr;W.babyRig.legs[1].rotation.x=-1.3-.3*cr;}
  // Gary: smoking, waving at 2-Pack
  const near=Math.hypot(P.x+2.8,P.z-.73)<3.2;
  const smoking=(clock*.33)%1<.4;
  if(S.fin&&S.fin.garyPhone)pose(gary,{armR:[-2.9,.75],armL:[-.3,.25],look:.3});
  else pose(gary,{armR:smoking?[-2.6,.35]:[-.5,.2],armL:near?[-2.6+.3*Math.sin(clock*12),.4]:[-.3,.25],look:near?.4:0});
  gary.ember.material.emissiveIntensity=smoking?4+2*Math.sin(clock*20):.6;
  const mp=new THREE.Vector3();gary.mouth.getWorldPosition(mp);
  gary.smoke.forEach((s,k)=>{const u=(clock*.42+k/7)%1;s.position.set(mp.x+.25*Math.sin(k+clock),mp.y+.1+1.6*u,mp.z+.1*Math.cos(k*2+clock));const sc=(.4+1.6*u)*(1-u);s.scale.setScalar(Math.max(.01,sc));});
  // talking decays
  for(const r of [tp,ricky,gary,dan,steve,granny,timmy,mailman,W.mama,W.dad,W.vendor,...W.liners.map(L=>L.rig)])r.talk=Math.max(0,r.talk-dt);
  // Gary says hi
  if(S.mode==="play"&&near&&clock>(S.garyT||0)){S.garyT=clock+40;say("GARY","Heyyyy, 2-Pack!",1.8);setTimeout(()=>{if(S.mode==="play")say("TWOPACK","Don't you 'hey 2-Pack' me, Gary!",2.2);},1900);}
}
