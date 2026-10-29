// state.js - Game state, the player, and build() which puts the whole world together.
"use strict";
// ===================================================================== state
let clock=0;
const S={mode:"title",score:0,strikes:0,busts:0,still:0,time:0,caseNo:0,spawnT:5,firstEv:true,binoOn:false,ev:0,evId:null,musicOn:true,next:"granny"};
const P={x:.6,z:-4,yaw:Math.PI/2,phase:0,moving:false,run:false};
let camYaw=Math.PI/2,camPitch=.32,binoYaw=0,binoPitch=0,binoFov=16;
const K={};let rmb=false,drag=null;

let tp,ricky,granny,gary,timmy,mailman,dan,steve,car,carBody,playerBody;
const W={};
function build(){
  buildBlock();
  tp=make2Pack();
  ricky=makeRicky();granny=makeGranny();gary=makeGary();
  timmy=makePerson({h:.95,skin:"#8a5a3c",top:"#2a8a3a",pants:"#f2c21a",shoes:"#c4162a",hair:"#3a2414",style:"short"});
  mailman=makePerson({h:1.75,skin:"#e8b48a",top:"#6a8ac8",pants:"#2a3a6a",hair:"#5a3a1a",style:"short",mustache:true});
  const strap=M(box(.05,.62,.03),clay("#5a3a24"),0,.2*1.75,0,mailman.body);strap.rotation.z=.7;strap.position.z=.12;
  M(box(.32,.3,.12),clay("#5a3a24"),-.2,.05,.14,mailman.body);
  W.letter=M(box(.26,.14,.01),clay("#f4f0e6"),0,-.36*1.75,.08,mailman.arms[0]);
  dan=makeCop("DAN",{skin:"#e8b48a",hair:"#5a3a1a",mustache:true,belly:1.45});
  steve=makeCop("STEVE",{h:1.88,skin:"#c48e64",hair:"#141010",glasses:true});
  car=makeCar();
  playerBody=addBody({r:.33,pos:()=>P,on:()=>true});
  buildStage2();
  W.ricky=makeWalker(ricky,.32,1.15);W.granny=makeWalker(granny,.42,.33);
  W.dan=makeWalker(dan,.34,1.6);W.steve=makeWalker(steve,.34,1.6);
  for(const k of ["ricky","granny","dan","steve"]){const w=W[k];w.body=addBody({r:w.r,pos:()=>w,on:()=>w.visible});}
  addBody({r:.3,pos:()=>({x:16.5,z:-3.75}),on:()=>timmy.g.visible});
  W.mail=makeWalker(mailman,.34,1.0);W.mail.body=addBody({r:.34,pos:()=>W.mail,on:()=>W.mail.visible});
  W.mama=makePerson({h:1.68,skin:"#8a5a3c",top:"#e84a9a",pants:"#2a2a30",shoes:"#f4f0e6",hair:"#141010",style:"bun"});W.mama.g.visible=false;addBody({r:.3,pos:()=>({x:17.1,z:-6.7}),on:()=>W.mama.g.visible});
  tp.cup=M(cyl(.05,.04,.13,10),clay("#f8e04a",.25),0,-.33*1.8,.04,tp.arms[1]);tp.cup.visible=false;
  W.bills=[];for(let k=0;k<6;k++){const b=M(box(.24,.012,.11),new THREE.MeshStandardMaterial({color:0x5ab05a,emissive:0x2a7a2a,emissiveIntensity:.5,roughness:.6}),0,.19,0,scene,false);b.visible=false;b.userData.t=0;W.bills.push(b);}
  carBody={r:0,pos:()=>car,on:()=>false};
  ricky.g.visible=granny.g.visible=timmy.g.visible=mailman.g.visible=false;
  W_.standClosed.visible=true;W_.standSign.visible=false;
  copsHome();
}
function copsHome(){
  for(const [w,x,z] of [[W.dan,35.2,-2.75],[W.steve,37.3,-2.7]]){if(w.escort)continue;w.x=x;w.z=z;w.yaw=0;w.target=null;w.visible=true;w.rig.g.visible=true;}
}
