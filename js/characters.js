// characters.js - Building the clay people: makePerson, pose, 2-Pack, Ricky, the cops, Grandma, Gary, the cop car.
"use strict";
// ===================================================================== people
const WHITE=clay("#f8f6f0",.4),BLACK=clay("#0a0a0c",.3),MOUTH=clay("#3a1414",.6);
function makePerson(o){
  const H=o.h||1.8,g=new THREE.Group();
  const mSkin=clay(o.skin),mTop=o.topMat||clay(o.top||o.skin),mPants=clay(o.pants||"#33343a"),mShoe=clay(o.shoes||"#1c1c1e",.5);
  const mSleeve=o.sleeveMat||(o.shirtless?mSkin:mTop);
  const hipY=.47*H,legs=[],arms=[];
  for(const s of [-1,1]){const p=new THREE.Group();p.position.set(s*.085*H,hipY,0);g.add(p);
    M(cyl(.062*H,.055*H,.44*H,10),mPants,0,-.22*H,0,p);M(box(.1*H,.065*H,.18*H),mShoe,0,-.44*H,.035*H,p);legs.push(p);}
  const body=new THREE.Group();body.position.y=hipY;g.add(body);
  M(sph(.135*H,14,10),mPants,0,.01*H,0,body).scale.set(1.05,.55,.78);
  M(cyl(.15*H,.13*H,.32*H,16),mTop,0,.17*H,0,body).scale.z=.74;
  M(sph(.15*H,16,10),mTop,0,.33*H,0,body).scale.set(1,.42,.74);
  if(o.belly)M(sph(.12*H,14,10),mTop,0,.12*H,.045*H,body).scale.set(1.05,1,o.belly);
  for(const s of [-1,1]){const p=new THREE.Group();p.position.set(s*.185*H,.31*H,0);body.add(p);
    M(cyl(.045*H,.04*H,.29*H,10),mSleeve,0,-.145*H,0,p);M(sph(.045*H,10,8),mSkin,0,-.3*H,0,p);arms.push(p);}
  const head=new THREE.Group();head.position.y=.36*H;body.add(head);
  M(cyl(.04*H,.045*H,.07*H,8),mSkin,0,.02*H,0,head);
  const hs=.115*H,hy=.05*H+hs;
  M(lumpy(sph(hs,18,14),.004*H),mSkin,0,hy,0,head);
  for(const s of [-1,1]){M(sph(.026*H,10,8),WHITE,s*.042*H,hy+.02*H,.093*H,head);M(sph(.014*H,8,6),BLACK,s*.042*H,hy+.02*H,.116*H,head);
    M(sph(.02*H,8,6),mSkin,s*.118*H,hy,0,head).scale.set(.5,1,.8);}
  M(sph(.022*H,8,6),mSkin,0,hy-.005*H,.114*H,head);
  const mouth=M(sph(.032*H,10,6),MOUTH,0,hy-.05*H,.1*H,head);mouth.scale.set(1,.3,.45);
  if(o.hair&&o.style!=="bald"){const mh=clay(o.hair);
    const cap=M(sph(hs*1.05,18,10,0,o.style==="bob"?Math.PI*.6:Math.PI*.48),mh,0,hy+.004*H,-.012*H,head);cap.rotation.x=-.25;
    if(o.style==="bun")M(lumpy(sph(hs*.42,12,9),.004),mh,0,hy+hs*.78,-hs*.55,head);
    if(o.style==="long")M(box(hs*1.9,hs*1.7,hs*.45),mh,0,hy-hs*.55,-hs*.72,head);}
  if(o.glasses)for(const s of [-1,1]){const r=M(tor(.03*H,.005*H,6,14),BLACK,s*.042*H,hy+.02*H,.118*H,head);}
  if(o.mustache)M(box(.08*H,.018*H,.02*H),clay(o.hair||"#3a2a1a"),0,hy-.03*H,.116*H,head);
  const rig={g,legs,arms,body,head,mouth,H,hy,hs,talk:0,phase:0};
  scene.add(g);return rig;
}
// pose: arms as [forward-raise (negative = up/forward), outward]; legs swing with the walk phase
function pose(r,p){
  const sw=p.walk?Math.sin(r.phase)*p.walk:0;
  r.legs[0].rotation.x=sw;r.legs[1].rotation.x=-sw;
  const aR=p.armR||[-sw*.8,.08],aL=p.armL||[sw*.8,.08];
  r.arms[0].rotation.set(aR[0],0,-aR[1]);r.arms[1].rotation.set(aL[0],0,aL[1]);
  r.body.rotation.set(p.lean||0,0,p.tilt||0);
  r.head.rotation.set(p.nod||0,p.look||0,0);
  r.body.position.y=.47*r.H+(p.bob||0);
  const open=r.talk>0?.35+.65*Math.abs(Math.sin(clock*17+r.H*9)):(p.mouth||0);
  r.mouth.scale.y=.3+open*.9;
}
function place(r,x,z,yaw,y){r.g.position.set(x,y===undefined?groundY(x,z):y,z);r.g.rotation.y=yaw;}

// 2-Pack: bald, shirtless, tattooed, red bandana, gold chain, a hall-monitor sash
function make2Pack(){
  const tp=makePerson({h:1.8,skin:"#6e4228",shirtless:true,pants:"#2a4a7a",shoes:"#f4f4f4",style:"bald"});
  const H=1.8,b=tp.body,skin=clay("#6e4228",.6),red=clay("#c4162a",.8),gold=clay("#f2c230",.15);
  for(const s of [-1,1]){M(sph(.08*H,12,8),skin,s*.07*H,.27*H,.085*H,b).scale.set(1,.7,.4);for(let k=0;k<3;k++)M(sph(.03*H,8,6),skin,s*.032*H,(.17-.045*k)*H,.093*H,b).scale.set(1,.7,.4);}
  const ink={fg:"#1a2030",font:"'Bungee',Impact,sans-serif",weight:"400"};
  sign("911",.11*H,.04*H,ink,0,.305*H,.117*H,b);
  sign("SNITCH 4 LIFE",.2*H,.03*H,ink,0,.045*H,.102*H,b);
  sign("NEIGHBORHOOD\nWATCH",.25*H,.1*H,ink,0,.2*H,-.12*H,b,Math.PI);
  const hy=tp.hy,hs=tp.hs;
  const band=M(tor(hs*.98,hs*.17,8,24),red,0,hy+hs*.42,0,tp.head);band.rotation.x=Math.PI/2+.12;
  M(sph(hs*.24,10,8),red,0,hy+hs*.45,-hs*.98,tp.head);
  for(const s of [-1,1]){const t=M(new THREE.ConeGeometry(hs*.13,hs*.6,6),red,s*.07*H*.4,hy+hs*.12,-hs*1.08,tp.head);t.rotation.set(-2.6,0,s*.35);}
  M(sph(.01*H,6,6),clay("#1a2030"),-.042*H,hy-.035*H,.11*H,tp.head).scale.set(.8,1.6,.6);
  const ch=M(tor(.105*H,.011*H,6,22),gold,0,.335*H,.03*H,b);ch.rotation.x=Math.PI/2-.45;
  M(cyl(.025*H,.025*H,.07*H,8),gold,0,.25*H,.12*H,b).rotation.z=Math.PI/2;
  const sash=M(box(.07*H,.5*H,.012*H),clay("#ff8a1a",.8),0,.17*H,.112*H,b);sash.rotation.z=.62;
  const sashB=M(box(.07*H,.5*H,.012*H),clay("#ff8a1a",.8),0,.17*H,-.112*H,b);sashB.rotation.z=-.62;
  for(let k=0;k<3;k++)M(tor(.135*H,.012*H,6,22),clay(k%2?"#f4f0e6":"#c4162a",.8),0,.06*H+.02*H*k,0,b).rotation.x=Math.PI/2;
  // binoculars (shown while spying)
  const bn=new THREE.Group();bn.position.set(0,hy+.02*H,.17*H);tp.head.add(bn);
  for(const s of [-1,1]){const c=M(cyl(.025*H,.03*H,.1*H,10),clay("#1a1a1e",.4),s*.042*H,0,0,bn);c.rotation.x=Math.PI/2;}
  bn.visible=false;tp.bino=bn;
  return tp;
}
function stripesMat(a,b){const c=document.createElement("canvas");c.width=c.height=64;const g=c.getContext("2d");for(let k=0;k<8;k++){g.fillStyle=k%2?a:b;g.fillRect(0,k*8,64,8);}
  const t=new THREE.CanvasTexture(c);t.wrapS=t.wrapT=THREE.RepeatWrapping;t.repeat.set(1,2);return new THREE.MeshStandardMaterial({map:t,roughness:.9});}
function makeRicky(){
  const sm=stripesMat("#141414","#f4f0e6");
  const r=makePerson({h:1.76,skin:"#e8b48a",topMat:sm,sleeveMat:sm,pants:"#1a1a1e",shoes:"#0a0a0c",hair:"#141010",style:"short"});
  M(box(r.hs*2.05,r.hs*.3,r.hs*.4),clay("#0a0a0c",.3),0,r.hy+.02*r.H,r.hs*.82,r.head);
  M(sph(r.hs*1.06,16,10,0,Math.PI*.5),clay("#141414",.95),0,r.hy+.01,0,r.head);
  const bag=new THREE.Group();bag.position.set(.12*r.H,.3*r.H,-.2*r.H);r.body.add(bag);
  M(lumpy(sph(.26,14,10),.03),clay("#c8b080",.95),0,0,0,bag).scale.set(1,1.1,.9);
  M(cyl(.07,.07,.12,8),clay("#c8b080",.95),0,.3,0,bag);
  sign("$",.26,.26,{fg:"#2a7a3a"},0,0,.24,bag);
  r.bag=bag;return r;
}
function makeCop(name,o){
  const r=makePerson(Object.assign({h:1.8,top:"#1a2a5a",pants:"#1a2a5a",shoes:"#0a0a0c",style:"short"},o));
  const cop=clay("#1a2a5a",.6),hs=r.hs,hy=r.hy;
  M(cyl(hs*.98,hs*.98,hs*.4,16),cop,0,hy+hs*.72,0,r.head);
  M(cyl(hs*1.12,hs*1.12,hs*.1,16),cop,0,hy+hs*.95,0,r.head);
  M(box(hs*.9,hs*.06,hs*.5),clay("#0a0a0c",.15),0,hy+hs*.55,hs*.85,r.head).rotation.x=.25;
  M(sph(hs*.14,8,6),clay("#f2c230",.15),0,hy+hs*.8,hs*.98,r.head);
  M(sph(.03*r.H,8,6),clay("#f2c230",.15),.07*r.H,.27*r.H,.11*r.H,r.body);
  const d=M(tor(.08,.035,8,14),clay("#e84a9a",.3),0,-.33*r.H,.03,r.arms[0]);d.rotation.y=Math.PI/2;r.donut=d;
  r.name=name;return r;
}
function makeGranny(){
  const r=makePerson({h:1.5,skin:"#ecc0a0",top:"#b88ac8",pants:"#6a5a7a",shoes:"#4a3a3a",hair:"#d8d8d8",style:"bun",glasses:true});
  const wk=new THREE.Group();wk.position.set(0,0,.48);r.g.add(wk);const alu=clay("#c8ccd4",.25);
  for(const sx of [-.24,.24]){for(const sz of [-.14,.14])M(cyl(.025,.025,.8,6),alu,sx,.4,sz,wk);const bar=M(cyl(.03,.03,.36,6),alu,sx,.8,0,wk);bar.rotation.x=Math.PI/2;M(sph(.06,8,6),clay("#e8f040"),sx,.04,-.14,wk);}
  return r;
}
function makeGary(){
  const g=makePerson({h:1.72,skin:"#c8a888",top:"#7a7258",pants:"#4a4436",shoes:"#2a2a2a",hair:"#6a5a3a",style:"long",belly:.55});
  M(lumpy(sph(g.hs*.92,14,10,0,Math.PI*.55),.01),clay("#3a4a2a",.95),0,g.hy+g.hs*.15,0,g.head);
  M(lumpy(sph(g.hs*.6,12,8),.01),clay("#6a5a3a"),0,g.hy-g.hs*.7,g.hs*.35,g.head).scale.set(1,1.1,.7);
  for(const s of [-1,1])M(sph(g.hs*.18,8,6),clay("#5a3a4a"),s*.042*g.H,g.hy-.005*g.H,.1*g.H,g.head).scale.set(1,.45,.4);
  const pipe=new THREE.Group();pipe.position.set(0,-.32*g.H,.04);g.arms[0].add(pipe);
  M(cyl(.018,.018,.18,8),new THREE.MeshStandardMaterial({color:0xe8f0ff,roughness:.1,transparent:true,opacity:.6}),0,0,0,pipe).rotation.x=Math.PI/2;
  g.ember=M(sph(.03,8,6),glow("#ff8a1a",3),0,0,.1,pipe);
  const outer=new THREE.Group();outer.position.set(-1.95,.21,.73);outer.rotation.y=Math.PI/2;scene.add(outer);
  const inner=new THREE.Group();inner.rotation.x=-Math.PI/2;outer.add(inner);
  scene.remove(g.g);inner.add(g.g);
  const bl=M(lumpy(sph(1,20,12),.06),clay("#6a4a6a",.98),-2.55,.28,.73);bl.scale.set(.82,.24,.44);
  for(let k=0;k<4;k++)M(sph(.17,8,6),clay("#4a3a2a",.95),-3.1+.33*k,.5,.73+.1*Math.sin(k*3),scene,false).scale.set(1,.25,1);
  g.smoke=[];for(let k=0;k<7;k++){const s=M(sph(.12,8,6),new THREE.MeshStandardMaterial({color:0xe8e8e8,transparent:true,opacity:.5,roughness:1}),0,-9,0,scene,false);s.castShadow=false;g.smoke.push(s);}
  return g;
}
function makeCar(){
  const g=new THREE.Group();scene.add(g);const bk=clay("#141418",.35),wh=clay("#f4f2ee",.35);
  M(box(4.4,.9,1.9),bk,0,.75,0,g);M(box(2.2,.5,1.94),wh,.1,.8,0,g);M(box(2.4,.75,1.7),wh,-.2,1.5,0,g);
  for(const x of [-.75,.45])M(box(1,.5,1.74),clay("#1a2230",.1),x,1.55,0,g,false);
  M(box(.08,.4,1.5),clay("#1a2230",.1),.9,1.5,0,g,false);
  for(const s of [-1,1])sign("POLICE",1.6,.3,{fg:"#141414"},.1,.85,s*.98,g,s>0?0:Math.PI);
  for(const x of [-1.4,1.4])for(const z of [-.9,.9]){const w=M(cyl(.36,.36,.3,14),clay("#121214",.5),x,.36,z,g);w.rotation.x=Math.PI/2;}
  for(const z of [-.6,.6])M(box(.05,.18,.3),glow("#fff6c8",1),2.2,.85,z,g,false);
  const lr=M(box(.4,.18,.35),glow("#ff1a1a",1),-.2,1.97,-.25,g),lb=M(box(.4,.18,.35),glow("#1a4aff",1),-.2,1.97,.25,g);
  return {g,lr,lb,x:42,z:2.7,h:Math.PI,state:"parked",queue:[],t:0,cur:null,honk:0};
}
