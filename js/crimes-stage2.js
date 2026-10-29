// crimes-stage2.js - Stage 2 crimes: Mama, Daddy, the squirrel, the baby, and the finale (the cops).
"use strict";
// ---- STAGE 2: verse 3. Everybody he's ever told on.
defCrime("mama",{title:"Running a red light",who:"2-Pack's mama",time:90,pts:240,
  line:["TWOPACK","I told on my mama for runnin' a light,"],
  describe:"My mama. Pink car. Rolled right through it.",
  target:()=>new THREE.Vector3(W.mamaCar.x,1.1,W.mamaCar.z),
  steps:[{k:"spy",t:"Catch her running the red light at the crosswalk. Binoculars, while it's red.",m:"!"},
         {k:"call",t:()=>"Call it in from a payphone. Remember her plate?"+(C.mama.hint?` It starts ${C.mama.plate.slice(0,C.mama.hint)}...`:""),m:"CALL IT IN"}],
  puzzle:"plate",
  start(){const mc=W.mamaCar;this.plate=String(1000+Math.random()*9000|0);this.hint=0;setPlate(this.plate);mc.x=-56;mc.g.visible=true;mc.stopped=false;},
  update(dt){const mc=W.mamaCar;
    if(this.dispatched){if(!mc.stopped&&(mc.x<-27||mc.x>40))mc.x=-26;mc.stopped=true;setLight("green");place2(mc);return;}
    const sp=(mc.x>-6&&mc.x<8)?2.3:6.5;let blocked=false;
    for(const b of bodies){if(!b.on())continue;const p=b.pos(),ahead=p.x-mc.x;if(ahead>0&&ahead<3.0+b.r&&Math.abs(p.z-mc.z)<1.0+b.r)blocked=true;}
    if(blocked){mc.honk-=dt;if(mc.honk<=0){sfx("honk");mc.honk=2.2;}}else{mc.x+=sp*dt;mc.honk=0;}
    if(mc.x>72)mc.x=-58;
    setLight(mc.x>-17&&mc.x<-6?"yellow":(mc.x>=-6&&mc.x<9?"red":"green"));
    place2(mc);},
  spyOk(){return W_.tlState==="red"&&W.mamaCar.x>-5&&W.mamaCar.x<8;},
  onSpy(){pop(this.target(),`PLATE ${this.plate}`);say("TWOPACK",`Plate ${this.plate.split("").join("-")}! Got it!`,2.2);},
  end(){W.mamaCar.g.visible=false;},
  bust:[["STEVE","Ma'am, you ran that light.",1.8],["MOM","Baby, you told on your own MAMA?!",2.2]],
  slots:t=>[[t.x-1.2,LANE2-1.55],[t.x+1.2,LANE2-1.55]]});
function place2(mc){mc.g.position.set(mc.x,0,mc.z);mc.g.rotation.y=0;}

defCrime("daddy",{title:"Snoring in public",who:"2-Pack's daddy",time:85,pts:220,
  line:["TWOPACK","I told on my daddy for snorin' at night,"],
  describe:"My daddy. In a hammock. Sounds like a leaf blower.",
  target:()=>new THREE.Vector3(HAMMOCK[0],1.1,HAMMOCK[1]),
  steps:[{k:"record",t:()=>`Record his snoring on your flip phone (${C.daddy.snores||0}/3). Close, but not too close.`,m:"RECORD"},
         {k:"play",t:"Play it back right in his ear",m:"PLAY IT BACK"}],
  start(){this.snores=0;resetDad();W.dad.on=true;},
  act(){const k=cur(this).k;
    if(k==="record")return {x:HAMMOCK[0],z:HAMMOCK[1],r:5.4,rmin:2.0,label:"Record the snoring",fn:()=>startRecord(this)};
    if(k==="play")return {x:HAMMOCK[0]-.9,z:HAMMOCK[1]+1.05,r:1.1,label:"Play it back in his ear",fn:()=>{this.handling=true;P.yaw=Math.PI;sfx("snore",1.6);
      later(.5,()=>{W.dad.awake=true;W.dad.fall=0;});
      talk([["DADDY","WHAT?! WHO'S SNORIN'?!",1.6],["TWOPACK","You. You snorin'.",1.4],["TWOPACK","I told on my daddy for snorin' at night,",2.3]],()=>{busted(this,"WIDE AWAKE!");later(3,()=>{if(!C.daddy.active)resetDad();});});}};
    return null;},
  end(){W.dad.on=false;}});

defCrime("squirrel",{title:"Stole Gary's lunch",who:"A squirrel",time:80,pts:220,
  line:["TWOPACK","I told on a squirrel - now that squirrel's in JAIL!"],
  describe:"Squirrel. Fluffy tail. Armed with a sandwich.",
  target:()=>new THREE.Vector3(W.sq.x,.45,W.sq.z),
  steps:[{k:"catch",t:"Catch the squirrel. He's fast: run (Shift), corner him, grab him (E).",m:"CATCH HIM"},{k:"jail",t:"Lock him up in the County Jail",m:"LOCK HIM UP"}],
  start(){const q=W.sq;q.x=-6.4;q.z=-.9;q.yaw=Math.PI;q.g.visible=true;q.held=false;q.jailed=false;q.tired=0;q.run=0;q.wT=0;say("GARY","2-Pack! A squirrel took my sandwich!",2.0);},
  update(dt){updateSquirrel(dt,this);},
  act(){const k=cur(this).k,q=W.sq;
    if(k==="catch"&&!q.held)return {x:q.x,z:q.z,r:1.05,label:"Grab the squirrel",fn:()=>{q.held=true;sfx("cash");pop(new THREE.Vector3(q.x,.5,q.z),"GOTCHA");adv(this);}};
    if(k==="jail")return {x:JAIL[0],z:JAIL[1]+1.1,r:1.05,label:"Lock him up",fn:()=>{q.held=false;q.jailed=true;this.handling=true;P.yaw=Math.PI;sfx("cuffs");
      talk([["TWOPACK","I told on a squirrel - now that squirrel's in JAIL!",2.6]],()=>busted(this,"LOCKED UP!"));}};
    return null;},
  end(why){if(why!=="busted"){W.sq.g.visible=false;W.sq.held=false;W.sq.jailed=false;}}});
function updateSquirrel(dt,c){
  const q=W.sq;if(q.held||q.jailed)return;
  const dx=q.x-P.x,dz=q.z-P.z,d=Math.hypot(dx,dz);let want,spd;
  q.tired-=dt;q.zigT-=dt;if(q.zigT<=0){q.zig=rand(-.9,.9);q.zigT=rand(.35,.8);}
  if(d<5.2&&q.tired<=0){want=Math.atan2(dx,dz)+q.zig;spd=5.0;q.run+=dt;if(q.run>3.2){q.tired=1.8;q.run=0;}}
  else{q.run=Math.max(0,q.run-dt);q.wT-=dt;if(q.wT<=0){q.wYaw=rand(0,TAU);q.wT=rand(1.5,3.5);}want=q.wYaw;spd=q.tired>0?1.6:1.1;}
  q.yaw=turnToward(q.yaw,want,10*dt);
  const al=Math.max(0,Math.cos(angDiff(q.yaw,want)));const st=spd*al*al*dt;
  const fx=Math.sin(q.yaw),fz=Math.cos(q.yaw),nx=q.x+fx*st,nz=q.z+fz*st;
  const out=nx<-31.5||nx>30||nz<-6||nz>-.25;
  if(out||blockedAhead(q.body,nx,nz,fx,fz,q.r)){q.wYaw=q.yaw+(Math.random()<.5?1:-1)*rand(1.6,2.6);q.zig=angDiff(Math.atan2(dx,dz),q.wYaw);q.zigT=.5;if(d>=5.2)q.wT=1.2;q.moving=false;}
  else{q.x=nx;q.z=nz;q.moving=st>1e-4;}
}

defCrime("baby",{title:"Cutting the line",who:"A baby",time:52,pts:240,
  line:["TWOPACK","I told on a baby for cuttin' the line,"],
  describe:"Baby. Diaper. No respect for the line.",
  target:()=>new THREE.Vector3(W.baby.x,.35,W.baby.z),
  steps:[{k:"spy",t:"Catch her cutting the ice-cream line. Binoculars.",m:"!"},{k:"tell",t:()=>`Tell everybody in line (${C.baby.told||0}/4) before she gets her cone`,m:"TELL THE LINE"}],
  start(){this.told=0;W.liners.forEach(L=>{L.told=false;L.yaw=Math.PI/2;L.rig.g.visible=true;});
    const b=W.baby;b.x=19.2;b.z=CART[1]+.82;b.yaw=Math.PI/2;b.visible=true;W.babyRig.g.visible=true;b.target=[CART[0]-.75,CART[1]+.82];b.speed=4.6/(this.time*Math.max(.65,1-S.score/8000)*.92);},
  update(dt){if(this.handling)return;stepWalker(W.baby,dt);},
  act(){if(cur(this).k!=="tell")return null;let best=null,bd=1.6;
    for(const L of W.liners){if(L.told)continue;const d=Math.hypot(P.x-L.x,P.z-L.z);if(d<bd){bd=d;best=L;}}
    if(!best)return null;
    return {x:best.x,z:best.z,r:1.6,label:"Tell 'em: that baby cut",fn:()=>{best.told=true;this.told++;sfx("step");
      const lines=["Hey! She cut!","Is that a... baby?","Unbelievable.","I been here since noon!"];say("LINER",lines[(this.told-1)%4],1.4);
      if(this.told>=4){this.handling=true;talk([["TWOPACK","I told on a baby for cuttin' the line,",2.4],["VENDOR","Back of the line, kid.",1.6]],()=>busted(this,"BACK OF THE LINE!"));}
      else toast(`Told ${this.told}/4. Keep goin'.`);}};},
  end(){W.baby.visible=false;W.babyRig.g.visible=false;W.liners.forEach(L=>L.rig.g.visible=false);}});

// ---- the finale: the cops parked in the fire lane
defCrime("cops",{title:"Parked in the fire lane",who:"Officers Dan & Steve",time:Infinity,pts:1000,
  line:["TWOPACK","I told on the COPS - now the cops in a hurry!"],
  describe:"The police. In the fire lane. Eating donuts.",
  target:()=>new THREE.Vector3(car.x,1.5,car.z),
  steps:[{k:"spy",t:"Photograph the cop car parked in the fire lane",m:"!"},{k:"call911",t:"Call 911 on the cops. Any payphone.",m:"CALL 911"},{k:"precinct",t:"Report this... to the POLICE. Go to Precinct 9.",m:"PRECINCT 9"}],
  start(){toast("Wait... is that the cop car? In the FIRE LANE?");},
  spyOk(){return car.state==="hydrant";},
  act(){if(cur(this).k==="precinct")return {x:36.2,z:-1.7,r:2.4,label:"Report the cops to the police",fn:startFinale};return null;}});
