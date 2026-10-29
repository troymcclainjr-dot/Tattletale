// crimes-stage1.js - Stage 1 crimes: Gary, Ricky (and Dan's escort), Grandma, Timmy, the lawn, the mailman.
"use strict";
defCrime("gary",{title:"Smoking crack in the gutter",who:"Gary · since 2009",time:Infinity,pts:0,
  line:["TWOPACK","They still smokin' crack in my gutter... and they STILL THERE!"],
  describe:"Gary. He's in the gutter. He's always in the gutter.",
  target:()=>new THREE.Vector3(-3.55,.45,.73),
  steps:[{k:"spy",t:"Spy on him with binoculars",m:"!"},{k:"call",t:"Call it in: any payphone, or Precinct 9",m:"CALL IT IN"}],
  bust:[["COPS","Hey, Gary!",1.6],["GARY","Heyyy, fellas!",1.8]],
  slots:t=>[[t.x+.3,1.75],[t.x+1.5,1.75]]});

defCrime("ricky",{title:"Bank robbery",who:"Ricky",time:130,pts:600,
  line:["TWOPACK","Striped shirt, eye mask, and a big bag of cash!"],
  describe:"Striped shirt, eye mask, and a big bag of cash!",
  target:()=>new THREE.Vector3(W.ricky.x,1.2,W.ricky.z),
  steps:[{k:"cash",t:()=>`Follow the money: pick up the bills he's dropping (${Math.min(3,C.ricky.cash||0)}/3)`,m:"FOLLOW THE $"},
         {k:"spy",t:"ID him with binoculars",m:"!"},
         {k:"getdan",t:"Go get Officer Dan at Precinct 9 (east end). Ricky won't wait.",m:"GET DAN"},
         {k:"lead",t:"Lead Dan to Ricky. Don't lose him.",m:"LEAD DAN"}],
  start(){const w=W.ricky;w.x=28;w.z=-6.2;w.yaw=0;w.visible=true;ricky.g.visible=true;w.route=[[28,-1.05],[-26,-1.05],[39,-1.05]];w.ri=0;w.target=w.route[0];
    this.cash=0;this.dropT=1.5;this.frozen=false;W.bills.forEach(b=>b.visible=false);},
  update(dt){const w=W.ricky;
    if(this.frozen){w.target=null;w.yaw=turnToward(w.yaw,Math.atan2(W.dan.x-w.x,W.dan.z-w.z),4*dt);return;}
    if(stepWalker(w,dt)){w.ri=w.ri>=2?1:w.ri+1;w.target=w.route[w.ri];}
    this.dropT-=dt;                                           // a trail of dropped cash
    if(this.dropT<=0&&w.moving&&w.z>-2){this.dropT=4.2;
      const b=W.bills.find(b=>!b.visible)||W.bills.reduce((a,b)=>a.userData.t<b.userData.t?a:b);
      b.position.set(w.x-Math.sin(w.yaw)*.5,.18,w.z-Math.cos(w.yaw)*.5);b.rotation.y=rand(0,TAU);b.userData.t=clock;b.visible=true;}
    for(const b of W.bills){if(!b.visible)continue;b.position.y=.19+.03*Math.sin(clock*4+b.userData.t);b.rotation.y+=dt*.8;
      if(S.mode==="play"&&Math.hypot(P.x-b.position.x,P.z-b.position.z)<.8){b.visible=false;this.cash++;sfx("cash");pop(b.position,`$ ${Math.min(this.cash,3)}/3`);
        if(cur(this).k==="cash"&&this.cash>=3)adv(this);}}
  },
  end(){W.ricky.visible=false;ricky.g.visible=false;W.bills.forEach(b=>b.visible=false);if(W.dan.escort==="follow")sendDanHome();}});

defCrime("granny",{title:"Jaywalking",who:"Grandma",time:62,pts:180,
  line:["TWOPACK","Saw Grandma jaywalkin' - she ain't even use the signs!"],
  describe:"Grandma. Walker. Tennis balls. No crosswalk.",
  target:()=>new THREE.Vector3(W.granny.x,1.1,W.granny.z),
  steps:[{k:"spy",t:"Catch her in the act with binoculars",m:"!"},{k:"whistle",t:"Get in front of her in the street and blow your whistle on the beat",m:"WHISTLE"}],
  start(){const w=W.granny;w.x=7.2;w.z=-4.6;w.yaw=0;w.visible=true;granny.g.visible=true;w.target=[7.2,14.6];this.frozen=false;},
  update(dt){const w=W.granny;if(this.frozen||this.dispatched)return;if(!w.target&&w.z<14)w.target=[7.2,14.6];stepWalker(w,dt);},
  act(){if(cur(this).k!=="whistle"||this.frozen)return null;const w=W.granny;if(w.z<.3)return null;
    return {x:w.x,z:w.z+1.35,r:1.0,label:"Blow the whistle",fn:()=>startRhythm(this)};},
  end(){W.granny.visible=false;granny.g.visible=false;},
  bust:[],slots:t=>[[t.x+1.2,t.z],[t.x-1.2,t.z]]});

defCrime("timmy",{title:"Unlicensed lemonade stand",who:"Little Timmy",time:80,pts:160,
  line:["TWOPACK","No permit, no license - I need SWAT on demand!"],
  describe:"Little Timmy runnin' a lemonade stand.",
  target:()=>new THREE.Vector3(16.5,.9,-3.6),
  steps:[{k:"buy",t:"Go undercover: buy a cup at his stand",m:"BUY ONE"},{k:"mama",t:"Tell his mama: knock on the door of the house behind the stand",m:"KNOCK"}],
  start(){timmy.g.visible=true;W_.standSign.visible=true;W_.standClosed.visible=false;this.busy=false;},
  act(){if(this.busy)return null;const k=cur(this).k;
    if(k==="buy")return {x:16.5,z:-2.25,r:1.1,label:"Buy a lemonade (25¢)",fn:()=>{this.busy=true;P.yaw=Math.PI;
      talk([["TWOPACK","One lemonade, please.",1.4],["TIMMY","That's 25 cents.",1.4]],()=>{this.busy=false;if(!this.active)return;tp.cup.visible=true;sfx("cash");
        pop(new THREE.Vector3(16.5,.4,-2.6),"RECEIPT");say(...this.line,2.4);adv(this);});}};
    if(k==="mama")return {x:17.1,z:-5.4,r:1.0,label:"Knock on the door",fn:()=>{this.busy=true;this.handling=true;P.yaw=Math.PI;sfx("knock");if(P.z<-5.35)P.z=-5.35;
      later(.9,()=>{W.mama.g.visible=true;sfx("door");});
      later(1.0,()=>talk([["MAMA","Can I help y-",1.0],["TWOPACK","Ma'am. Your son is runnin' an unlicensed business.",2.3],["MAMA","TIMMY! Get in this house!",1.9],["TIMMY","Mooom!",1.1]],
        ()=>{busted(this,"GROUNDED!");later(1.6,()=>{W.mama.g.visible=false;sfx("door");});}));}};
    return null;},
  end(){timmy.g.visible=false;W_.standSign.visible=false;W_.standClosed.visible=true;tp.cup.visible=false;},
  bust:[],slots:t=>[[15.2,-1.6],[17.8,-1.6]]});

defCrime("lawn",{title:"Lawn a quarter inch too brown",who:"Mrs. Johnson",time:90,pts:130,
  line:["TWOPACK","Mrs. Johnson's lawn is a quarter inch too brown!"],
  describe:"Mrs. Johnson's lawn is a quarter inch too brown!",
  target:()=>new THREE.Vector3(11.5,.2,-5),
  steps:[{k:"measure",t:"Measure it: stand on her lawn and get out your ruler",m:"MEASURE"},{k:"mail",t:"Mail a complaint: the blue mailbox near your house",m:"MAIL IT"}],
  start(){W_.lawn.material=clay("#8a6a3a",.95);},
  act(){const k=cur(this).k;
    if(k==="measure")return {x:11.5,z:-4.7,r:2.3,label:"Measure the grass",fn:()=>startRuler(this)};
    if(k==="mail")return {x:MAILDROP[0],z:MAILDROP[1]+.78,r:1.0,label:"Mail the complaint",fn:()=>{P.yaw=Math.PI;sfx("door");say("TWOPACK","Dear Precinct 9. Enclosed: one quarter inch.",2.2);dispatch(["lawn"]);}};
    return null;},
  end(why){if(why==="expired")W_.lawn.material=clay("#6a8a3a",.95);},
  bust:[["STEVE","That is... a little brown.",1.8]],
  slots:t=>[[10.8,-1.6],[12.4,-1.6]]});

defCrime("mail",{title:"Bending the mail",who:"The mailman",time:100,pts:200,
  line:["TWOPACK","I told on the mailman for bendin' my mail,"],
  describe:"The mailman. Bending it. On purpose.",
  target:()=>new THREE.Vector3(W.mail.x,1.2,W.mail.z),
  steps:[{k:"tail",t:()=>`Tail him and photograph him bending mail (${C.mail.photos||0}/2). Stay out of his sight.`,m:"TAIL HIM"},{k:"call",t:"Call it in from a payphone",m:"CALL IT IN"}],
  start(){const w=W.mail;w.x=MAILSTOPS[0][0];w.z=MAILSTOPS[0][1];w.yaw=-Math.PI/2;w.visible=true;mailman.g.visible=true;w.target=null;
    this.stop=0;this.dir=1;this.bendT=4.5;this.bending=true;this.photos=0;this.lastPhoto=-1;this.spotT=0;this.sus=0;},
  update(dt){const w=W.mail;
    if(this.dispatched){this.bending=false;w.target=null;return;}
    if(this.bendT>0){this.bending=true;w.yaw=turnToward(w.yaw,-Math.PI/2,4*dt);this.bendT-=dt;
      if(this.bendT<=0){this.bending=false;let n=this.stop+this.dir;if(n<0||n>2){this.dir*=-1;n=this.stop+this.dir;}this.stop=n;w.target=MAILSTOPS[n];}}
    else if(stepWalker(w,dt))this.bendT=4.5;
    this.sus=Math.max(0,this.sus-dt);this.spotT-=dt;
    if(cur(this).k==="tail"&&this.spotT<=0&&S.mode==="play"){const dx=P.x-w.x,dz=P.z-w.z,d=Math.hypot(dx,dz)||1,dot=(dx*Math.sin(w.yaw)+dz*Math.cos(w.yaw))/d;
      if(d<(this.bending?3.2:7.5)&&dot>.5){this.spotT=7;this.sus=3;toast(this.photos?"He saw you. Your photos are no good now. Hang back.":"He saw you. Hang back and use the binoculars.");
        this.photos=0;this.lastPhoto=-1;say("MAILMAN","...Mornin'.",1.3);sfx("buzz");}}
  },
  spyOk(){return this.bending&&this.stop!==this.lastPhoto&&this.sus<=0;},
  end(){W.mail.visible=false;mailman.g.visible=false;},
  bust:[["DAN","Sir, step away from the mail.",1.8]],
  slots:t=>[[t.x+1.2,t.z+.3],[t.x-1.2,t.z+.3]]});


// ---- Ricky: Officer Dan follows 2-Pack on foot
function startEscort(){const d=W.dan,r=C.ricky;d.escort="follow";d.lost=false;d.speed=2.6;adv(r);
  talk([["TWOPACK","Officer - that's HIM! Right there, walkin' past!",2.2],["DAN","Sir... we're on our lunch break.",1.8],["TWOPACK","It's TEN in the MORNIN'!",1.6],["DAN","...Fine. Lead the way.",1.6]]);}
function sendDanHome(){const d=W.dan;d.escort="home";d.lost=false;d.speed=1.8;d.path=[[35.2,-1.6],[35.2,-2.75]];d.target=[d.x,-1.6];}
function updateEscort(dt){
  const d=W.dan,r=C.ricky;if(!d.escort)return;
  if(d.escort==="follow"){
    const dp=Math.hypot(P.x-d.x,P.z-d.z);
    if(!d.lost&&dp>13){d.lost=true;d.target=null;say("DAN","I'm gonna finish this donut.",1.8);toast("You lost Dan. Go back for him.");}
    else if(d.lost&&dp<6){d.lost=false;say("DAN","Alright, alright.",1.2);}
    if(!d.lost)d.target=dp>2.3?[P.x+(d.x-P.x)/dp*1.7,P.z+(d.z-P.z)/dp*1.7]:null;
    stepWalker(d,dt);
    if(r.active&&Math.hypot(d.x-W.ricky.x,d.z-W.ricky.z)<3.2){d.escort="bust";d.target=null;r.frozen=true;r.handling=true;
      talk([["RICKY","Mornin', officers.",1.6],["DAN","Mornin', Ricky.",1.4],["DAN","Nice bag, Ricky.",1.5],["RICKY","Thanks. I stole it.",1.8]],()=>{busted(r,"BUSTED!");sendDanHome();});}
  }else if(d.escort==="bust"){d.yaw=turnToward(d.yaw,Math.atan2(W.ricky.x-d.x,W.ricky.z-d.z),4*dt);}
  else if(d.escort==="home"){if(stepWalker(d,dt)){if(d.path.length)d.target=d.path.shift();else{d.escort=null;d.yaw=0;d.speed=1.6;}}}
}
