// puzzles.js - Broken payphone puzzles: wires, keypad, phone menu, Mama's plate.
"use strict";
// ===================================================================== puzzles
const PZ_KINDS=["wires","keypad","menu"];let pzLast=-1;
function openPuzzle(ph,ev){
  P.x=ph.x;P.z=ph.z+.72;P.yaw=Math.PI;S.binoOn=false;rmb=false;K[" "]=false;pz.keyHandler=null;["#bino","#reticle","#binolabel","#binotop"].forEach(s=>$(s).hidden=true);
  const focus=ev.slice().sort((a,b)=>a.left-b.left)[0];
  let k;do{k=Math.random()*3|0;}while(k===pzLast);pzLast=k;
  const plateCase=ev.find(c=>c.puzzle==="plate");
  S.mode="puzzle";S.pz={focus:plateCase||focus,kind:plateCase?"plate":PZ_KINDS[k],done:false};
  $("#puzzle").hidden=false;$("#livecam").hidden=false;$("#prompt").hidden=true;$("#cases").hidden=true;$("#mini").hidden=true;
  $("#pz").innerHTML="";
  ({wires:pzWires,keypad:pzKeypad,menu:pzMenu,plate:pzPlate})[S.pz.kind]($("#pz"),solved);
  sfx("pickup");
}
function closePuzzle(){S.mode="play";$("#mini").hidden=false;$("#cases").hidden=false;S.pz=null;$("#puzzle").hidden=true;$("#livecam").hidden=true;$("#pz").innerHTML="";canvas.focus();updateCamera(0,true);}
function solved(){
  if(!S.pz||S.pz.done)return;S.pz.done=true;sfx("win");
  say("OPERATOR","Nine-one-one, what's your emer-",1.4);
  setTimeout(()=>{say("TWOPACK","It's me.",1.2);const ev=pendingEvidence();dispatch(ev.map(c=>c.id));},1450);
  setTimeout(()=>{if(S.mode==="puzzle")closePuzzle();},2700);
}
function msg(el,t,cls){el.textContent=t;el.className="pzmsg"+(cls?" "+cls:"");}
function setHead(eye,title,sub){$("#pzeye").textContent=eye;$("#pztitle").textContent=title;$("#pzsub").textContent=sub;}

// 1) rewire the payphone: rotate tiles until the handset connects to the line
function pzWires(root,done){
  setHead("PAYPHONE · OUT OF ORDER","Rewire the handset","Click the tiles to turn them. Connect the phone on the left to the LINE on the right.");
  const R=4,Cn=5,N=1,E=2,S_=4,Wd=8;const rot=m=>((m<<1)|(m>>3))&15;const opp={1:4,2:8,4:1,8:2};
  const r0=Math.random()*R|0;const path=[];let r=r0,c=0;const seen=new Set();
  while(true){path.push([r,c]);seen.add(r+","+c);if(c===Cn-1)break;
    const opts=[];if(r>0&&!seen.has((r-1)+","+c)&&Math.random()<.45)opts.push([r-1,c]);if(r<R-1&&!seen.has((r+1)+","+c)&&Math.random()<.45)opts.push([r+1,c]);opts.sort(()=>Math.random()-.5);
    const nx=opts.length&&path.length<14?opts[0]:[r,c+1];
    // don't step vertically twice into a dead end: always fine, since moving right is never blocked
    [r,c]=nx;}
  const rEnd=path[path.length-1][0];
  const dirOf=(a,b)=>b[0]<a[0]?N:b[0]>a[0]?S_:b[1]>a[1]?E:Wd;
  const grid=[];for(let i=0;i<R;i++){grid.push([]);for(let j=0;j<Cn;j++)grid[i].push([5,3,7,3,5][Math.random()*5|0]);}
  path.forEach((p,i)=>{const inn=i===0?Wd:opp[dirOf(path[i-1],p)],out=i===path.length-1?E:dirOf(p,path[i+1]);grid[p[0]][p[1]]=inn|out;});
  const turns=grid.map(row=>row.map(()=>0));
  const cur=(i,j)=>{let m=grid[i][j];for(let k=0;k<turns[i][j]%4;k++)m=rot(m);return m;};
  function powered(){const on=new Set();if(!(cur(r0,0)&Wd))return {on,ok:false};const q=[[r0,0]];on.add(r0+","+0);let ok=false;
    while(q.length){const [i,j]=q.shift();const m=cur(i,j);if(i===rEnd&&j===Cn-1&&(m&E))ok=true;
      for(const [d,di,dj] of [[N,-1,0],[E,0,1],[S_,1,0],[Wd,0,-1]]){if(!(m&d))continue;const a=i+di,b=j+dj;if(a<0||b<0||a>=R||b>=Cn)continue;if(on.has(a+","+b))continue;if(cur(a,b)&opp[d]){on.add(a+","+b);q.push([a,b]);}}}
    return {on,ok};}
  do{for(let i=0;i<R;i++)for(let j=0;j<Cn;j++)turns[i][j]=Math.random()*4|0;}while(powered().ok);
  const wrap=document.createElement("div");wrap.className="wires";root.appendChild(wrap);
  const m=document.createElement("div");m.className="pzmsg";root.appendChild(m);msg(m,"Line: dead.","bad");
  const cells=[];
  for(let i=0;i<R;i++){
    const l=document.createElement("div");l.className="end";l.innerHTML=i===r0?"☎":"";wrap.appendChild(l);
    for(let j=0;j<Cn;j++){const b=document.createElement("button");b.className="cell";b.setAttribute("aria-label",`Tile row ${i+1} column ${j+1}`);
      const base=grid[i][j];let paths="";for(const [d,x,y] of [[N,30,4],[E,56,30],[S_,30,56],[Wd,4,30]])if(base&d)paths+=`<line x1="30" y1="30" x2="${x}" y2="${y}"/>`;
      b.innerHTML=`<svg viewBox="0 0 60 60" style="transform:rotate(${turns[i][j]*90}deg)"><g stroke-width="10" stroke-linecap="round" stroke="#7a84a0">${paths}</g><circle cx="30" cy="30" r="6" fill="#7a84a0"/></svg>`;
      b.onclick=()=>{if(S.pz.done)return;turns[i][j]++;b.firstChild.style.transform=`rotate(${turns[i][j]*90}deg)`;sfx("click");paint();};
      wrap.appendChild(b);cells.push([i,j,b]);}
    const rr=document.createElement("div");rr.className="end"+(i===rEnd?" live":"");rr.innerHTML=i===rEnd?"LINE":"";wrap.appendChild(rr);
  }
  function paint(){const {on,ok}=powered();for(const [i,j,b] of cells){const col=on.has(i+","+j)?"#f2d24a":"#7a84a0";b.querySelector("g").setAttribute("stroke",col);b.querySelector("circle").setAttribute("fill",col);}
    if(ok){msg(m,"Dial tone!","good");done();}}
  paint();
}
// 2) the busted keypad: repeat the tones it plays back
function pzKeypad(root,done){
  setHead("PAYPHONE · KEYPAD SCRAMBLED","Dial what the phone dials","The buttons are wired wrong. Watch which ones light up, then press them in the same order.");
  const keys=["1","2","3","4","5","6","7","8","9","*","0","#"];const pad=document.createElement("div");pad.className="keypad";root.appendChild(pad);
  const m=document.createElement("div");m.className="pzmsg";root.appendChild(m);
  const btn={};keys.forEach(k=>{const b=document.createElement("button");b.textContent=k;b.onclick=()=>press(k);pad.appendChild(b);btn[k]=b;});
  let seq=[],pos=0,listening=false,round=0;const len=4+Math.min(2,Math.floor(S.score/1500));
  function flash(k,ms=300){btn[k].classList.add("lit");sfx("dtmf",k);setTimeout(()=>btn[k].classList.remove("lit"),ms);}
  function play(){listening=false;pos=0;msg(m,"Listen...");seq=[];for(let i=0;i<len;i++)seq.push(keys[Math.random()*12|0]);
    seq.forEach((k,i)=>setTimeout(()=>{if(S.pz&&!S.pz.done)flash(k);},600+i*560));
    setTimeout(()=>{listening=true;msg(m,"Your turn.");},600+seq.length*560);}
  function press(k){if(!listening||S.pz.done)return;flash(k,160);
    if(k===seq[pos]){pos++;if(pos===seq.length){listening=false;msg(m,"Connected!","good");done();}}
    else{listening=false;msg(m,"Wrong number. -4 seconds.","bad");pad.classList.remove("shake");void pad.offsetWidth;pad.classList.add("shake");sfx("buzz");penalty(4);round++;setTimeout(play,900);}}
  pz.keyHandler=k=>{if(btn[k])press(k);};
  play();
}
// 3) Precinct 9's phone menu
function pzMenu(root,done){
  const f=S.pz.focus;
  setHead("PRECINCT 9 · AUTOMATED LINE","Get through the phone menu","Pick the right option. Wrong answers put you back on hold.");
  const steps=[
    {q:"Thank you for calling Precinct 9. Our menu has changed, mostly because of you. Please choose from the following options.",o:[["To report a crime",1],["For donut orders",0],["To hear the hold music again",0]]},
    {q:"Is the crime happening right now?",o:[["Yes. Right now. Right there.",1],["It's been happening since 2009",f.id==="gary"?1:0],["I just wanted to see if you'd pick up",0]]},
    {q:"Please describe the suspect, in one breath.",o:[[f.describe,1],["Tall-ish? Some kind of hat?",0],["*heavy breathing*",0]]},
  ];
  let i=0;const box_=document.createElement("div");box_.className="menu";root.appendChild(box_);const m=document.createElement("div");m.className="pzmsg";root.appendChild(m);
  function show(){box_.innerHTML="";const st=steps[i];const q=document.createElement("div");q.className="q";q.textContent=st.q;box_.appendChild(q);
    const opts=st.o.slice().sort(()=>Math.random()-.5);
    opts.forEach((o,k)=>{const b=document.createElement("button");b.innerHTML=`<kbd>${k+1}</kbd><span></span>`;b.querySelector("span").textContent=o[0];b.onclick=()=>pick(o);box_.appendChild(b);});
    pz.keyHandler=key=>{const n=+key;if(n>=1&&n<=opts.length)pick(opts[n-1]);};}
  function pick(o){if(S.pz.done)return;sfx("dtmf",String(1+Math.random()*9|0));
    if(o[1]){i++;msg(m,"");if(i===steps.length){msg(m,"Transferring you to a human...","good");done();}else show();}
    else{msg(m,"Your call is important to us. -4 seconds.","bad");box_.classList.remove("shake");void box_.offsetWidth;box_.classList.add("shake");sfx("buzz");penalty(4);i=0;setTimeout(show,700);}}
  show();
}
// 4) Mama's plate: dial it from memory
function pzPlate(root,done){
  const c=S.pz.focus;
  setHead("PAYPHONE · TRAFFIC DIVISION","Dial in her license plate","You saw it on the photo. Four digits. No peeking.");
  const disp=document.createElement("div");disp.className="plate";root.appendChild(disp);
  const pad=document.createElement("div");pad.className="keypad";root.appendChild(pad);
  const m=document.createElement("div");m.className="pzmsg";root.appendChild(m);
  let got="";const show=()=>{disp.textContent=(got+"____").slice(0,4).split("").join(" ");};show();
  const press=k=>{if(S.pz.done)return;if(k==="*"){got=got.slice(0,-1);show();return;}if(k==="#")return;got+=k;sfx("dtmf",k);show();
    if(got.length===4){if(got===c.plate){msg(m,"That's her. Connecting...","good");done();}
      else{c.hint=Math.min(3,(c.hint||0)+1);msg(m,`Not her plate. -4 seconds. Starts with ${c.plate.slice(0,c.hint)}...`,"bad");pad.classList.remove("shake");void pad.offsetWidth;pad.classList.add("shake");sfx("buzz");penalty(4);got="";setTimeout(show,500);}}};
  ["1","2","3","4","5","6","7","8","9","*","0","#"].forEach(k=>{const b=document.createElement("button");b.textContent=k==="*"?"⌫":k;b.setAttribute("aria-label",k==="*"?"Delete":k);b.onclick=()=>press(k);pad.appendChild(b);});
  pz.keyHandler=k=>{if(/^[0-9]$/.test(k))press(k);else if(k==="Backspace")press("*");};
}
const pz={keyHandler:null};
