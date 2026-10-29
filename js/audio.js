// audio.js - The beat and the sound effects (all made in code).
"use strict";
// ===================================================================== sound
let ac=null,master,musicG,sfxG,noise,nextBar=0,barN=0;
function initAudio(){if(ac)return;try{ac=new (window.AudioContext||window.webkitAudioContext)();}catch(e){ac=null;return;}
  master=ac.createGain();master.gain.value=.8;master.connect(ac.destination);musicG=ac.createGain();musicG.gain.value=S.musicOn?.3:0;musicG.connect(master);sfxG=ac.createGain();sfxG.gain.value=.7;sfxG.connect(master);
  noise=ac.createBuffer(1,ac.sampleRate,ac.sampleRate);const d=noise.getChannelData(0);for(let i=0;i<d.length;i++)d[i]=Math.random()*2-1;
  nextBar=ac.currentTime+.1;setInterval(schedule,60);}
const mf=m=>440*Math.pow(2,(m-69)/12);
function env(g,t,a,peak,dec){g.gain.setValueAtTime(0.0001,t);g.gain.exponentialRampToValueAtTime(peak,t+a);g.gain.exponentialRampToValueAtTime(0.0001,t+a+dec);}
function osc(type,f,t,dur,peak,dest,f2){const o=ac.createOscillator(),g=ac.createGain();o.type=type;o.frequency.setValueAtTime(f,t);if(f2)o.frequency.exponentialRampToValueAtTime(f2,t+dur);env(g,t,.005,peak,dur);o.connect(g);g.connect(dest);o.start(t);o.stop(t+dur+.05);}
function nz(t,dur,peak,hp,dest){const s=ac.createBufferSource(),f=ac.createBiquadFilter(),g=ac.createGain();s.buffer=noise;f.type="highpass";f.frequency.value=hp;env(g,t,.002,peak,dur);s.connect(f);f.connect(g);g.connect(dest);s.start(t,Math.random()*.5);s.stop(t+dur+.05);}
const PROG=[[45,[57,60,64]],[41,[53,57,60]],[48,[55,60,64]],[40,[56,59,64]]];
function schedule(){if(!ac)return;const beat=60/90,bar=4*beat;
  while(nextBar<ac.currentTime+.25){const t=nextBar,[root,ch]=PROG[barN%4];
    if(S.mode!=="title"||barN>=0){
      osc("sine",150,t,.32,.9,musicG,42);osc("sine",150,t+2*beat,.3,.6,musicG,42);osc("sine",150,t+2.5*beat,.3,.5,musicG,42);
      nz(t+beat,.16,.35,1500,musicG);nz(t+3*beat,.16,.35,1500,musicG);
      for(let h=0;h<8;h++)nz(t+h*beat/2+(h%2?.025:0),.04,h%2?.12:.08,7000,musicG);
      osc("sine",mf(root),t,bar*.9,.28,musicG);
      ch.forEach(n=>osc("triangle",mf(n),t,2.2,.045,musicG));ch.forEach(n=>osc("triangle",mf(n),t+2.5*beat,.6,.025,musicG));}
    nextBar+=bar;barN++;}}
function sfx(name,arg){if(!ac)return;const t=ac.currentTime;
  if(name==="shutter"){nz(t,.05,.6,2000,sfxG);nz(t+.07,.04,.4,3000,sfxG);}
  else if(name==="click")osc("square",900,t,.03,.12,sfxG);
  else if(name==="tick")osc("sine",1200,t,.08,.2,sfxG);
  else if(name==="buzz")osc("sawtooth",110,t,.35,.25,sfxG);
  else if(name==="honk"){osc("square",330,t,.28,.12,sfxG);osc("square",415,t,.28,.12,sfxG);}
  else if(name==="door")nz(t,.12,.4,400,sfxG);
  else if(name==="pickup"){nz(t,.06,.3,800,sfxG);osc("sine",350,t+.15,.6,.1,sfxG);osc("sine",440,t+.15,.6,.1,sfxG);}
  else if(name==="win"){[523,659,784,1046].forEach((f,i)=>osc("triangle",f,t+i*.08,.25,.18,sfxG));}
  else if(name==="siren"){const o=ac.createOscillator(),g=ac.createGain();o.type="sine";o.frequency.setValueAtTime(700,t);for(let i=0;i<4;i++){o.frequency.linearRampToValueAtTime(1000,t+i*.6+.3);o.frequency.linearRampToValueAtTime(700,t+i*.6+.6);}env(g,t,.05,.12,2.4);o.connect(g);g.connect(sfxG);o.start(t);o.stop(t+2.6);}
  else if(name==="whistle"){const o=ac.createOscillator(),l=ac.createOscillator(),lg=ac.createGain(),g=ac.createGain();o.type="sine";o.frequency.value=2500;l.frequency.value=38;lg.gain.value=160;l.connect(lg);lg.connect(o.frequency);env(g,t,.01,.22,.22);o.connect(g);g.connect(sfxG);o.start(t);l.start(t);o.stop(t+.3);l.stop(t+.3);}
  else if(name==="snore"){const L=arg||1;const o=ac.createOscillator(),f=ac.createBiquadFilter(),g=ac.createGain();o.type="sawtooth";o.frequency.setValueAtTime(70,t);o.frequency.linearRampToValueAtTime(95,t+.7);o.frequency.linearRampToValueAtTime(60,t+1.3);f.type="lowpass";f.frequency.value=500;g.gain.setValueAtTime(.0001,t);g.gain.exponentialRampToValueAtTime(.12*L,t+.4);g.gain.exponentialRampToValueAtTime(.0001,t+1.4);o.connect(f);f.connect(g);g.connect(sfxG);o.start(t);o.stop(t+1.5);}
  else if(name==="hangup")osc("sine",120,t,.25,.6,sfxG,60);
  else if(name==="busy"){for(let i=0;i<4;i++){osc("sine",480,t+i*.5,.25,.15,sfxG);osc("sine",620,t+i*.5,.25,.15,sfxG);}}
  else if(name==="cuffs"){osc("sine",2400,t,.12,.3,sfxG);osc("sine",1800,t+.05,.25,.2,sfxG);nz(t,.05,.3,4000,sfxG);}
  else if(name==="cash"){osc("square",1320,t,.06,.1,sfxG);osc("square",1760,t+.07,.12,.1,sfxG);}
  else if(name==="knock"){for(let i=0;i<3;i++){osc("sine",140,t+i*.18,.1,.5,sfxG,70);nz(t+i*.18,.03,.25,600,sfxG);}}
  else if(name==="step"){osc("triangle",660,t,.08,.14,sfxG);osc("triangle",990,t+.07,.12,.14,sfxG);}
  else if(name==="dtmf"){const F={1:[697,1209],2:[697,1336],3:[697,1477],4:[770,1209],5:[770,1336],6:[770,1477],7:[852,1209],8:[852,1336],9:[852,1477],"*":[941,1209],0:[941,1336],"#":[941,1477]}[arg]||[697,1209];F.forEach(f=>osc("sine",f,t,.16,.12,sfxG));}
}
