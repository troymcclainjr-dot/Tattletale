// world.js - The block: street, houses, shops, Precinct 9, payphones, Gary's spot, and the Stage 2 props (traffic light, hammock, jail, ice-cream line).
"use strict";
// ===================================================================== the block
// World units: x runs east, the street runs along x. Houses on the north side (negative z), the street at z 0..14.
function groundY(x,z){if(z<0&&z>-3.2)return .16;if(z<=-3.2)return .12;if(z>=13)return .16;return 0;}
const SOLIDS=[];const OCCLUDERS=[];
const solidC=(x,z,r)=>SOLIDS.push({c:1,x,z,r});
const solidB=(x0,x1,z0,z1)=>SOLIDS.push({c:0,x0,x1,z0,z1});
const BOUNDS={x0:-32,x1:45,z0:-6.0,z1:18.4};

const W_={};
function buildBlock(){
  const asphalt=clay("#3a3a40",.95),side=clay("#a8a49a"),curb=clay("#c8c4b8");
  M(box(130,.1,14),asphalt,6,-.05,7,scene,false);
  M(box(130,.16,3.2),side,6,.08,-1.6,scene,false);
  M(box(130,.18,.25),curb,6,.09,0,scene,false);
  M(box(130,.12,4),clay("#6a8a3a",.95),6,.06,-5,scene,false);
  M(box(130,.16,6),side,6,.08,16,scene,false);
  for(let k=0;k<26;k++)M(box(2,.012,.15),clay("#f2c21a"),-50+k*5,.006,7,scene,false);
  for(let k=0;k<20;k++){const c=M(box(rand(.4,1.2),.01,.03),clay("#5a5a54"),rand(-30,44),.166,-rand(.4,2.8),scene,false);c.rotation.y=rand(-1,1);}
  // the crosswalk Grandma is NOT using
  for(let k=0;k<5;k++)M(box(.55,.012,12.6),clay("#e8e4d6"),1.3+k*1.0,.007,6.7,scene,false);
  // houses
  const cols=["#8a4a3a","#6a5a7a","#4a6a7a","#8a7a4a","#7a3a3a","#5a6a4a","#7a6a5a","#4a4a5a"];
  const houses=[-30,-24,-18,-12,-6,6,12,17];
  houses.forEach((x,k)=>{
    const w=x===17?5:5.6;const graf=x===-6||x===6||x===12;const h=graf?7.6:5.6+((k*37)%25)/10;
    const hm=M(box(w,h,7),clay(cols[k%cols.length]),x,h/2,-10.5);OCCLUDERS.push(hm);
    M(box(w+.2,.3,7.2),clay("#2a2624"),x,h+.15,-10.5);
    for(const wx of [-1.5,1.4])for(const wz of (graf?[2.0]:[2.0,4.3])){const boarded=((k*7+wx*3+wz)|0)%3===0;
      M(box(1.1,1.2,.06),boarded?clay("#8a6a3a"):clay("#1a2230",.15),x+wx,wz,-6.98,scene,false);
      if(boarded)for(let b=0;b<2;b++){const bd=M(box(1.3,.18,.05),clay("#9a7a4a"),x+wx,wz+.25-.5*b,-6.93,scene,false);bd.rotation.z=b?.3:-.3;}}
    M(box(1,2.1,.08),clay("#3a2414"),x+.1,1.05,-6.97,scene,false);
    M(box(1.6,.4,.9),curb,x+.1,.2,-6.55);
  });
  sign("2-PACK IS A\nSNITCH",4.6,1.6,{fg:"#e84a9a",font:"'Bungee',Impact,sans-serif",weight:"400"},-6,4.8,-6.94);
  sign("SNITCHES GET\nSTITCHES",4.4,1.5,{fg:"#2ad0e8",font:"'Bungee',Impact,sans-serif",weight:"400"},6,4.8,-6.94);
  sign("STILL THERE",4.4,.8,{fg:"#f2c21a",font:"'Bungee',Impact,sans-serif",weight:"400"},12,4.8,-6.94);
  // 2-Pack's house
  const hm=clay("#b8a070");
  const tph=M(box(5.6,7,7),hm,0,3.5,-10.5);OCCLUDERS.push(tph);
  M(box(5.8,.3,7.2),clay("#2a2624"),0,7.15,-10.5);
  M(box(1.4,1.2,.06),clay("#1a2230",.15),1.8,1.75,-6.98,scene,false);
  for(let k=0;k<9;k++)M(box(1.4,.04,.1),clay("#f4f0e6"),1.8,2.25-k*.11,-6.9,scene,false);
  M(box(1,2.1,.08),clay("#c4162a",.5),-1,1.05,-6.97,scene,false);
  M(box(1.6,.4,.9),curb,-1,.2,-6.55);
  M(box(1.9,.3,.04),clay("#1a3a8a"),-1,2.6,-6.93,scene,false);
  sign("NEIGHBORHOOD WATCH",1.8,.18,{fg:"#f2c21a"},-1,2.6,-6.9);
  // store, bank, precinct, liquor
  [[22.5,"CORNER STORE","#4a6a4a",6],[28,"BANK","#c8c0a8",5],[43.5,"LIQUOR","#6a4a7a",6]].forEach(([x,n,c,w])=>{
    OCCLUDERS.push(M(box(w,7,7),clay(c),x,3.5,-10.5));
    M(box(w*.8,.7,.1),clay("#f4f0e6"),x,4.2,-6.95,scene,false);
    sign(n,w*.75,.55,{fg:n==="LIQUOR"?"#c4162a":"#141414"},x,4.2,-6.89);
    M(box(1.4,2.4,.08),clay("#1a2230",.15),x,1.2,-6.96,scene,false);
  });
  OCCLUDERS.push(M(box(9,8,8),clay("#5a6a8a"),36,4,-11));
  M(box(6.5,.9,.12),clay("#1a2a5a"),36,5.6,-6.94,scene,false);
  sign("POLICE  ·  PRECINCT 9",6.1,.6,{fg:"#f4f0e6"},36,5.6,-6.87);
  M(box(2.2,2.8,.08),clay("#1a2230",.15),36,1.4,-6.96,scene,false);
  for(const s of [-1,1])M(sph(.3),glow("#3a8aff",2),36+s*1.8,3,-6.8);
  for(let k=0;k<4;k++)M(box(5,.18*(k+1),.62),curb,36,.09*(k+1),-(3.6+.6*k));
  solidB(33.5,38.5,-5.7,-3.3);
  M(box(.6,.12,.6),clay("#f4e2d4"),37.6,.8,-5.0);
  for(let k=0;k<3;k++){const d=M(tor(.12,.05,8,14),clay("#e84a9a",.3),37.45+.15*k,.88,-5.0);d.rotation.x=Math.PI/2;}
  // street furniture
  for(const x of [-24,-12,4,14,30,40]){M(cyl(.07,.07,5,8),clay("#2a2a2e"),x,2.5,-.2);M(box(.9,.2,.35),clay("#2a2a2e"),x,5,.2);solidC(x,-.2,.12);}
  for(const x of [-8.5,9.6,25]){M(cyl(.15,.17,.7,10),clay("#c4162a",.3),x,.5,-.32);M(sph(.17),clay("#c4162a",.3),x,.86,-.32);solidC(x,-.32,.22);}
  for(const x of [-15.8,4.8,26.4]){M(cyl(.3,.27,.9,12),clay("#5a6a5a",.4),x,.57,-3.5);solidC(x,-3.5,.34);}
  const pl=M(cyl(.03,.03,80,6),clay("#141414"),6,6.4,.3);pl.rotation.z=Math.PI/2;
  for(const s of [-1,1])M(box(.15,.12,.3),clay("#f4f4f4"),13+s*.15,6.0,.3);
  // payphones
  W_.phones=[[-10.5,-3.0],[2.8,-3.0],[19.6,-3.0]].map(([x,z])=>{
    const g=new THREE.Group();g.position.set(x,.12,z);scene.add(g);
    M(cyl(.06,.06,1.3,8),clay("#6a7078",.4),0,.65,-.05,g);
    M(box(.55,.8,.3),clay("#2c5bd6",.35),0,1.45,0,g);
    M(box(.38,.24,.04),clay("#c8ccd4",.3),0,1.6,.16,g);
    M(box(.1,.42,.1),clay("#141414"),-.2,1.42,.18,g);
    for(let k=0;k<6;k++)M(box(.08,.06,.03),clay("#f4f0e6"),-.03+(k%3)*.08,1.36-(k/3|0)*.08,.16,g,false);
    sign("PHONE",.5,.13,{fg:"#f4f0e6",bg:"#14203f"},0,1.97,.16,g);
    const out=sign("OUT OF\nORDER",.42,.24,{fg:"#c4162a",bg:"#f2d24a",font:"'Courier New',monospace",weight:"700"},.03,1.18,.155,g);out.rotation.z=.12;
    solidC(x,z,.36);
    return {x,z,g};
  });
  // the lemonade stand
  const st=new THREE.Group();st.position.set(16.5,.12,-3.05);scene.add(st);
  const wd=clay("#c8a060",.7);
  M(box(1.4,.06,.6),wd,0,.8,0,st);M(box(1.4,.75,.05),wd,0,.42,.3,st);
  for(const s of [-1,1])M(box(.06,1.6,.06),wd,s*.67,.8,-.25,st);
  M(box(1.5,.3,.05),wd,0,1.6,-.25,st);
  M(cyl(.12,.12,.28,10),clay("#f8e04a",.1),-.35,.97,0,st);
  for(let k=0;k<3;k++)M(cyl(.05,.04,.12,8),clay("#f4f0e6",.3),.1+k*.15,.89,.05,st);
  sign("LEMONADE\n25 CENTS",1.25,.55,{fg:"#c4162a"},0,.48,.33,st);
  W_.standSign=sign("OPEN",1.3,.26,{fg:"#14203f",bg:"#f2d24a"},0,1.6,-.22,st);
  W_.standClosed=sign("CLOSED",1.3,.26,{fg:"#f4f0e6",bg:"#c4162a"},0,1.6,-.215,st);
  solidB(15.75,17.25,-3.4,-2.7);
  // Mrs. Johnson's lawn
  W_.lawn=M(box(5.4,.03,3.4),clay("#8a6a3a",.95),11.5,.135,-5.0,scene,false);
  M(cyl(.03,.03,.7,6),clay("#7a4a24"),9.5,.4,-3.5);solidC(9.5,-3.5,.1);
  sign("THE JOHNSONS",.9,.16,{fg:"#2a1a10",bg:"#f4f0e6"},9.5,.8,-3.47);
  // a house mailbox for the mailman
  for(const x of [-27,-21.2,-14.2]){M(cyl(.04,.04,1,6),clay("#7a4a24"),x,.6,-3.0);M(box(.3,.3,.5),clay("#2a3a6a",.4),x,1.15,-3.0);solidC(x,-3.0,.2);}
  // the blue mail drop (Mrs. Johnson's complaint goes in here)
  const mb=new THREE.Group();mb.position.set(5.9,.16,-3.0);scene.add(mb);
  M(box(.62,.85,.56),clay("#1f4fa8",.4),0,.72,0,mb);const dome=M(cyl(.28,.28,.62,14,1,false,0,Math.PI),clay("#1f4fa8",.4),0,1.14,0,mb);dome.rotation.z=Math.PI/2;
  for(const sx of [-.26,.26])for(const sz of [-.22,.22])M(box(.06,.3,.06),clay("#1a1a1e"),sx,.15,sz,mb);
  M(box(.4,.05,.02),clay("#141414"),0,1.0,.29,mb);sign("MAIL",.42,.14,{fg:"#f4f0e6"},0,.75,.285,mb);solidC(5.9,-3.0,.42);
  // Gary's spot, in the gutter. He lies along it, feet at x=-1.95, head toward -x.
  const alu=clay("#c8ccd4",.25);
  M(box(.9,.02,.6),clay("#8a6a3a",.95),-1.1,.012,1.4,scene,false);
  sign("WELCOME",.7,.18,{fg:"#2a1a10"},-1.1,.026,1.4,scene).rotation.x=-Math.PI/2;
  const cart=new THREE.Group();cart.position.set(-5.9,0,1.15);cart.rotation.y=.3;scene.add(cart);
  for(const sx of [-.4,.4]){M(box(.03,.55,.9),alu,sx,.75,0,cart);for(const sy of [-.4,.4]){M(sph(.07,8,6),clay("#141414"),sx,.07,sy,cart);M(cyl(.02,.02,.45,6),alu,sx,.3,sy,cart);}}
  for(const sy of [-.45,.45])M(box(.83,.55,.03),alu,0,.75,sy,cart);
  ["#6a5a3a","#3a5a6a","#8a3a3a","#c8c0a8"].forEach((c,k)=>M(lumpy(sph(.3,12,9),.05),clay(c,.95),(k%2-.5)*.35,1.05,((k/2|0)-.5)*.4,cart).scale.set(1.15,1,1));
  solidC(-5.9,1.15,.6);
  M(cyl(.04,.04,.9,6),clay("#7a4a24"),-4.55,.45,.6);M(box(.8,.4,.04),clay("#f4f0e6"),-4.55,.95,.58);
  sign("WELCOME\nHOME",.7,.32,{fg:"#c4162a"},-4.55,.95,.61);solidC(-4.55,.6,.12);
  M(cyl(.06,.06,1,6),clay("#7a4a24"),-1.25,.5,.35);M(box(.3,.3,.5),clay("#2a3a6a",.4),-1.25,1.1,.35);
  sign("GARY",.26,.08,{fg:"#f4f0e6"},-1.25,1.1,.61);solidC(-1.25,.35,.2);
  M(sph(.38,12,8),clay("#141414"),-7.2,.62,.4).scale.set(1,.6,1);M(cyl(.04,.04,.5,6),alu,-7.2,.25,.4);solidC(-7.2,.4,.4);
  solidB(-3.85,-1.85,.48,.98);                  // Gary himself
  // the far side: a chain-link fence, some pines
  const fence=M(box(100,2,.05),new THREE.MeshStandardMaterial({color:0x9aa0a8,roughness:.4,transparent:true,opacity:.45}),6,1,18.9,scene,false);fence.castShadow=false;
  for(let k=0;k<12;k++){const x=-34+k*7+rand(-1.5,1.5),z=21+rand(0,3),s=rand(1,1.6);M(cyl(.12*s,.15*s,.8*s,8),clay("#5a3a24"),x,.4*s,z);for(let j=0;j<3;j++)M(new THREE.ConeGeometry((1-j*.25)*s,1.3*s,9),clay("#2f5a3a"),x,(1.1+j*.75)*s,z);}
  // the precinct garage for the cop car, and west/east end walls so the block reads as closed
  for(const x of [BOUNDS.x0-1.2,BOUNDS.x1+1.6]){M(box(1,5,10.4),clay("#4a4a52"),x,2.5,-4.9,scene,false);M(box(1,5,7),clay("#4a4a52"),x,2.5,16.5,scene,false);}
  // the fire lane (no parking. not even you, officers)
  M(box(5,.19,.27),clay("#c4162a",.5),9.6,.1,0,scene,false);
  sign("FIRE LANE",1.4,.12,{fg:"#f4f0e6"},9.6,.03,.6,scene).rotation.x=-Math.PI/2;
}

// ===================================================================== stage 2: the west end and the crosswalk
const JAIL=[-9.0,-4.7],HAMMOCK=[-17.5,-5.0],CART=[24.6,-2.2],LINE_X=[23.5,22.6,21.7,20.8],LANE2=10.5;
function makeSedan(color){
  const g=new THREE.Group();scene.add(g);const m=clay(color,.3);
  M(box(4.2,.85,1.85),m,0,.72,0,g);M(box(2.3,.7,1.7),m,-.2,1.45,0,g);
  for(const x of [-.75,.4])M(box(.95,.48,1.74),clay("#1a2230",.1),x,1.5,0,g,false);
  M(box(.08,.4,1.5),clay("#1a2230",.1),.9,1.45,0,g,false);
  for(const x of [-1.35,1.35])for(const z of [-.88,.88]){const w=M(cyl(.36,.36,.3,14),clay("#121214",.5),x,.36,z,g);w.rotation.x=Math.PI/2;}
  for(const z of [-.6,.6])M(box(.05,.16,.3),glow("#fff6c8",1),2.11,.8,z,g,false);
  for(const z of [-.6,.6])M(box(.05,.14,.3),glow("#ff2a2a",1.2),-2.11,.8,z,g,false);
  const plate=new THREE.Mesh(new THREE.PlaneGeometry(.62,.24),new THREE.MeshStandardMaterial({map:textTex("0000",{w:.62,h:.24,fg:"#14203f",bg:"#f4f4ee",font:"'Courier New',monospace",weight:"700"}),roughness:.6}));
  plate.position.set(-2.12,.62,0);plate.rotation.y=-Math.PI/2;g.add(plate);
  const d=M(sph(.12,10,8),clay("#e84a9a",.6),.3,1.95,-.3,g);       // the fuzzy dice-ish pom on the roof (it's her car)
  return {g,plate,x:-58,z:LANE2,honk:0,stopped:false};
}
function setPlate(t){const mc=W.mamaCar;mc.plate.material.map=textTex(t.split("").join(" "),{w:.62,h:.24,fg:"#14203f",bg:"#f4f4ee",font:"'Courier New',monospace",weight:"700"});mc.plate.material.needsUpdate=true;}
function buildStage2(){
  // the traffic light at the crosswalk (it faces eastbound traffic in the far lane)
  const tl=new THREE.Group();tl.position.set(-.5,0,13.6);scene.add(tl);
  M(cyl(.09,.11,4.6,8),clay("#2a2a2e"),0,2.3,0,tl);const arm=M(cyl(.06,.06,3.3,6),clay("#2a2a2e"),0,4.5,-1.6,tl);arm.rotation.x=Math.PI/2;
  M(box(.4,1.15,.42),clay("#1c1c20"),0,3.95,-3.1,tl);
  const lamp=(c,y)=>{const m=new THREE.MeshStandardMaterial({color:c,emissive:c,emissiveIntensity:.08,roughness:.4});M(sph(.13,10,8),m,-.22,y,-3.1,tl);return m;};
  W_.tl={r:lamp(0xff2a2a,4.3),y:lamp(0xffc21a,3.95),g:lamp(0x2aff6a,3.6)};W_.tlState="green";W_.tlT=0;
  M(box(.3,.012,5.6),clay("#f4f0e6"),-.9,.008,LANE2,scene,false);   // stop line
  solidC(-.5,13.6,.14);
  W.mamaCar=makeSedan("#e84a9a");W.mamaCar.g.visible=false;
  // Daddy's hammock
  for(const sx of [-1,1]){M(cyl(.1,.12,1.7,8),clay("#7a4a24"),HAMMOCK[0]+sx*1.4,.95,HAMMOCK[1]);solidC(HAMMOCK[0]+sx*1.4,HAMMOCK[1],.14);}
  const hm=M(lumpy(sph(1,18,10),.03),clay("#d8c8a0",.95),HAMMOCK[0],.82,HAMMOCK[1]);hm.scale.set(1.35,.22,.45);
  solidB(HAMMOCK[0]-1.4,HAMMOCK[0]+1.4,HAMMOCK[1]-.45,HAMMOCK[1]+.45);
  W.dad=makePerson({h:1.8,skin:"#8a5a3c",top:"#f4f0e6",pants:"#4a4a5a",shoes:"#2a2a2a",style:"bald",belly:1.4,mustache:true,hair:"#141010"});
  const dOuter=new THREE.Group();scene.add(dOuter);const dInner=new THREE.Group();dInner.rotation.x=-Math.PI/2;dOuter.add(dInner);scene.remove(W.dad.g);dInner.add(W.dad.g);
  dOuter.rotation.y=Math.PI/2;W.dad.outer=dOuter;W.dad.inner=dInner;
  W.zz=[0,1,2].map(()=>{const z=sign("Z",.32,.32,{fg:"#f4f0e6"},0,0,0,scene);z.visible=false;return z;});
  // the squirrel and his tiny county jail
  const q=new THREE.Group();scene.add(q);const fur=clay("#8a5a34",.85);
  M(lumpy(sph(.2,12,9),.01),fur,0,.2,0,q).scale.set(.8,.85,1.25);M(sph(.15,12,9),fur,0,.36,.2,q);
  const tail=M(lumpy(sph(.2,12,9),.03),fur,0,.42,-.28,q);tail.scale.set(.7,1.5,.7);tail.rotation.x=-.4;
  for(const sx of [-1,1]){M(sph(.03,8,6),BLACK,sx*.07,.4,.33,q);M(new THREE.ConeGeometry(.04,.09,6),fur,sx*.07,.52,.17,q);}
  M(box(.16,.05,.12),clay("#e8c890"),0,.3,.36,q);                       // Gary's sandwich
  W.sq={g:q,x:0,z:0,yaw:0,r:.22,held:false,jailed:false,tired:0,run:0,zig:0,zigT:0,wT:0,wYaw:0,moving:false};
  W.sq.body=addBody({r:.22,pos:()=>W.sq,on:()=>W.sq.g.visible&&!W.sq.held&&!W.sq.jailed});q.visible=false;
  const jail=new THREE.Group();jail.position.set(JAIL[0],.12,JAIL[1]);scene.add(jail);const iron=clay("#3a3a3e",.35);
  M(box(1.0,.5,.8),clay("#8a8a90"),0,.25,0,jail);M(box(1.0,.06,.8),iron,0,1.2,0,jail);
  for(let k=0;k<8;k++){M(cyl(.025,.025,.7,6),iron,-.44+k*.126,.85,.4,jail);M(cyl(.025,.025,.7,6),iron,-.44+k*.126,.85,-.4,jail);}
  for(const sx of [-.5,.5])for(let k=0;k<6;k++)M(cyl(.025,.025,.7,6),iron,sx,.85,-.34+k*.136,jail);
  sign("COUNTY JAIL",.8,.16,{fg:"#141414",bg:"#f4f0e6"},0,1.38,.4,jail);solidC(JAIL[0],JAIL[1],.62);
  // the ice-cream cart, the vendor, the line
  const cart=new THREE.Group();cart.position.set(CART[0],.16,CART[1]);scene.add(cart);
  M(box(1.1,.85,.9),clay("#f4f2ee",.35),0,.62,0,cart);M(cyl(.04,.04,1.3,6),clay("#c8ccd4",.3),0,1.55,0,cart);
  const umb=M(new THREE.ConeGeometry(1.1,.45,16),stripesMat("#e84a9a","#f4f0e6"),0,2.25,0,cart);
  for(const sx of [-.4,.4])for(const sz of [-.35,.35]){const w=M(cyl(.12,.12,.06,10),clay("#141414"),sx,.12,sz,cart);w.rotation.z=Math.PI/2;}
  sign("ICE CREAM",.85,.2,{fg:"#e84a9a"},-.56,.75,0,cart,-Math.PI/2);solidC(CART[0],CART[1],.72);
  W.vendor=makePerson({h:1.78,skin:"#c48e64",top:"#f4f0e6",pants:"#3a3a40",hair:"#141010",style:"short"});
  M(cyl(.12,.12,.12,12),clay("#f4f0e6"),0,W.vendor.hy+W.vendor.hs*.95,0,W.vendor.head);
  addBody({r:.3,pos:()=>({x:CART[0]+.95,z:CART[1]}),on:()=>true});
  const looks=[[1.7,"#e8b48a","#c8642a","long","#2ad0a8"],[1.85,"#5c3a26","#141010","short","#ff8a1a"],[1.6,"#c48e64","#3a2a1a","bob","#8a2ad0"],[1.78,"#f0c8a8","#e8c46a","short","#2a6ac8"]];
  W.liners=looks.map(([h,sk,hc,st,tc],k)=>{const r=makePerson({h,skin:sk,hair:hc,style:st,top:tc,pants:"#2a2a30"});r.g.visible=false;
    const L={rig:r,x:LINE_X[k],z:CART[1],yaw:Math.PI/2,told:false};addBody({r:.32,pos:()=>L,on:()=>r.g.visible});return L;});
  W.babyRig=makePerson({h:.55,skin:"#f0c8a8",top:"#f8f4ee",pants:"#f8f4ee",shoes:"#f0c8a8",hair:"#e8c46a",style:"short"});
  W.babyRig.g.rotation.order="YXZ";W.babyRig.g.visible=false;
  W.baby=makeWalker(W.babyRig,.2,.11);W.baby.body=addBody({r:.2,pos:()=>W.baby,on:()=>W.baby.visible});
  resetDad();
}
function resetDad(){const o=W.dad.outer;o.position.set(HAMMOCK[0]+.9,1.02,HAMMOCK[1]);o.rotation.set(0,Math.PI/2,0);W.dad.awake=false;W.dad.fall=-1;}
function setLight(st){if(W_.tlState===st)return;W_.tlState=st;W_.tl.r.emissiveIntensity=st==="red"?3:.08;W_.tl.y.emissiveIntensity=st==="yellow"?3:.08;W_.tl.g.emissiveIntensity=st==="green"?3:.08;}
