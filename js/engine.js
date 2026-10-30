// engine.js - Shared helpers, the renderer, lights, surface materials, text signs.
"use strict";
const TAU=Math.PI*2;
const $=s=>document.querySelector(s);
const rand=(a,b)=>a+Math.random()*(b-a);
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const lerp=(a,b,u)=>a+(b-a)*u;
function angDiff(a,b){let d=(b-a)%TAU;if(d>Math.PI)d-=TAU;if(d<-Math.PI)d+=TAU;return d;}
function turnToward(cur,tgt,max){return cur+clamp(angDiff(cur,tgt),-max,max);}
const fmt=s=>{s=Math.max(0,Math.ceil(s));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0");};

// ===================================================================== renderer
const canvas=$("#cv");
const renderer=new THREE.WebGLRenderer({canvas,antialias:true});
renderer.setPixelRatio(Math.min(window.devicePixelRatio||1,2));
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
const scene=new THREE.Scene();
const SKY=0xb9d0e4;
scene.background=new THREE.Color(SKY);
scene.fog=new THREE.Fog(SKY,45,120);
const camera=new THREE.PerspectiveCamera(55,1,0.1,300);
scene.add(new THREE.HemisphereLight(0xe2ecff,0x6a5a40,0.78));
const sun=new THREE.DirectionalLight(0xfff0d8,0.92);
sun.castShadow=true;
sun.shadow.mapSize.set(2048,2048);
Object.assign(sun.shadow.camera,{left:-26,right:26,top:26,bottom:-26,near:1,far:90});
sun.shadow.bias=-0.0006;
scene.add(sun);scene.add(sun.target);

// Clean color materials; legacy clay() name retained for existing callers.
const MATS={};
function clay(hex,rough=0.86){const k=hex+"|"+rough;if(!MATS[k])MATS[k]=new THREE.MeshStandardMaterial({color:hex,roughness:rough,metalness:0});return MATS[k];}
function glow(hex,i=1.5){return new THREE.MeshStandardMaterial({color:hex,emissive:hex,emissiveIntensity:i,roughness:.4});}
const box=(w,h,d)=>new THREE.BoxGeometry(w,h,d);
const sph=(r,w=16,h=12,ts=0,tl=Math.PI)=>new THREE.SphereGeometry(r,w,h,0,TAU,ts,tl);
const cyl=(rt,rb,h,s=14,hs=1,open=false,t0=0,tl=TAU)=>new THREE.CylinderGeometry(rt,rb,h,s,hs,open,t0,tl);
const tor=(r,t,rs=8,ts=24)=>new THREE.TorusGeometry(r,t,rs,ts);
function lumpy(geo,amt){const p=geo.attributes.position,v=new THREE.Vector3(),n=new THREE.Vector3();
  for(let i=0;i<p.count;i++){v.fromBufferAttribute(p,i);const k=Math.sin(v.x*23.1+1.3)*Math.sin(v.y*19.7+.7)*Math.sin(v.z*21.3+2.1);n.copy(v).normalize();v.addScaledVector(n,amt*k);p.setXYZ(i,v.x,v.y,v.z);}
  geo.computeVertexNormals();return geo;}
function M(geo,mat,x=0,y=0,z=0,parent=scene,cast=true){const m=new THREE.Mesh(geo,mat);m.position.set(x,y,z);m.castShadow=cast;m.receiveShadow=true;parent.add(m);return m;}

// text on a plane (signs, graffiti, tattoos). Planes face +z (toward the street).
function textTex(text,o){const W=512,H=Math.max(32,Math.round(512*o.h/o.w));const c=document.createElement("canvas");c.width=W;c.height=H;const g=c.getContext("2d");
  if(o.bg){g.fillStyle=o.bg;g.fillRect(0,0,W,H);}
  const lines=text.split("\n");let fs=H*0.78/lines.length;g.font=`${o.weight||"900"} ${fs}px ${o.font||"Impact, 'Arial Black', sans-serif"}`;
  const widest=Math.max(...lines.map(l=>g.measureText(l).width));if(widest>W*0.92){fs*=W*0.92/widest;g.font=`${o.weight||"900"} ${fs}px ${o.font||"Impact, 'Arial Black', sans-serif"}`;}
  g.fillStyle=o.fg||"#111";g.textAlign="center";g.textBaseline="middle";
  lines.forEach((l,i)=>g.fillText(l,W/2,H/2+(i-(lines.length-1)/2)*fs*1.02));
  const t=new THREE.CanvasTexture(c);t.anisotropy=4;return t;}
function sign(text,w,h,o,x,y,z,parent=scene,ry=0){const m=new THREE.Mesh(new THREE.PlaneGeometry(w,h),new THREE.MeshStandardMaterial({map:textTex(text,Object.assign({w,h},o)),transparent:!o.bg,alphaTest:o.bg?0:0.1,roughness:.8}));
  m.position.set(x,y,z);m.rotation.y=ry;m.receiveShadow=true;parent.add(m);return m;}
