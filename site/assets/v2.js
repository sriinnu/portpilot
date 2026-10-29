(() => {
  const field=document.querySelector('[data-point-field]');if(!field)return;
  const canvas=field.querySelector('canvas'),ctx=canvas.getContext('2d');
  if(!ctx){field.classList.add('no-canvas');return;}
  const reduce=matchMedia('(prefers-reduced-motion: reduce)');
  const pauseButton=field.querySelector('[data-field-pause]');
  const buttons=[...field.querySelectorAll('[data-node]')],hub=field.querySelector('.field-hub');
  const modules=[
    {x:-2.05,y:-1.25,z:1.25,w:1.65,d:.12,name:'Dev server',port:3000,bind:'127.0.0.1',project:'workshop/web'},
    {x:1.8,y:-1.5,z:1.8,w:.78,d:.1,name:'iOS Simulator',port:5050,bind:'127.0.0.1',project:'simulator/host-service'},
    {x:-1.8,y:1.6,z:1.2,w:1.3,d:.1,name:'Network app',port:41641,bind:'0.0.0.0',project:'network/client'},
    {x:2,y:1.35,z:1.25,w:1.65,d:.12,name:'macOS app',port:8080,bind:'127.0.0.1',project:'workshop/native'}
  ];
  const core={x:0,y:0,z:.6,w:.95,d:.95};
  let width=0,height=0,scale=1,yaw=-.13,targetYaw=-.13,selected=0,paused=reduce.matches,visible=true,raf=0,last=0,phase=0;
  let ink,accent,muted,bg;
  // Deterministic surface samples keep the drawing stable while it rotates.
  let seed=83;
  const random=()=>{seed=(seed*16807)%2147483647;return(seed-1)/2147483646;};
  const points=[],edges=[];
  const edge=(a,b,group=-1)=>edges.push({a,b,group});
  const app=(m,group)=>{
    const {x,y,z,w}=m,bottom=.12;
    const p=(u,v,depth=0)=>[x+u,y+depth,v];
    const segment=(u,v,a,b)=>edge(p(u,v),p(a,b),group);
    const roundRect=(left,low,width,high,r=.08,depth=0)=>{
      const corners=[[left+r,low+r,Math.PI],[left+width-r,low+r,Math.PI*1.5],[left+width-r,low+high-r,0],[left+r,low+high-r,Math.PI*.5]];
      const path=[];
      for(const [cx,cz,start] of corners)for(let i=0;i<=6;i++){const a=start+i*Math.PI/12;path.push(p(cx+Math.cos(a)*r,cz+Math.sin(a)*r,depth));}
      path.forEach((q,i)=>edge(q,path[(i+1)%path.length],group));
    };
    const circle=(u,v,r)=>{for(let i=0;i<24;i++){const a=i*Math.PI/12,b=(i+1)*Math.PI/12;segment(u+Math.cos(a)*r,v+Math.sin(a)*r,u+Math.cos(b)*r,v+Math.sin(b)*r);}};
    roundRect(-w/2,bottom,w,z-bottom,.09);roundRect(-w/2,bottom,w,z-bottom,.09,.08);
    for(let i=0;i<560;i++)points.push({p:p((random()-.5)*w,bottom+random()*(z-bottom)),group,alpha:.1+random()*.3});
    if(group===1){
      // A phone running an app in the local iOS simulator.
      roundRect(-w/2+.06,bottom+.13,w-.12,z-bottom-.23,.055,-.008);
      segment(-.12,z-.095,.12,z-.095);segment(-.12,bottom+.065,.12,bottom+.065);
      for(let row=0;row<3;row++)for(let col=0;col<3;col++)roundRect(-.26+col*.19,z-.47-row*.27,.13,.16,.025,-.015);
    }else if(group===2){
      // An app icon: connected peers rather than an anonymous server block.
      for(let row=0;row<3;row++)for(let col=0;col<3;col++){
        const u=-.3+col*.3,v=z-.3-row*.3;circle(u,v,.055);
        if(col<2)segment(u+.065,v,u+.235,v);
        if(row<2)segment(u,v-.065,u,v-.235);
      }
    }else{
      // Familiar browser and native-window chrome with fine content lines.
      segment(-w/2,z-.23,w/2,z-.23);
      for(let i=0;i<3;i++)circle(-w/2+.15+i*.13,z-.12,.03);
      if(group===0){
        roundRect(-.22,z-.17,.8,.1,.025,-.01);
        segment(-.2,.45,-.4,.62);segment(-.4,.62,-.2,.79);
        segment(.2,.45,.4,.62);segment(.4,.62,.2,.79);segment(-.08,.4,.08,.83);
      }else{
        segment(-w/2+.4,bottom,-w/2+.4,z-.23);
        for(let i=0;i<4;i++)segment(-w/2+.12,z-.4-i*.15,-w/2+.28,z-.4-i*.15);
        for(let i=0;i<4;i++)segment(-.25,z-.45-i*.15,w/2-.18,z-.45-i*.15);
      }
    }
    edge(p(0,0),p(0,.1),group);
  };
  modules.forEach(app);
  for(let i=0;i<48;i++){
    const a=i*Math.PI/24,b=(i+1)*Math.PI/24;
    edge([Math.cos(a)*.6,Math.sin(a)*.6,.08],[Math.cos(b)*.6,Math.sin(b)*.6,.08],4);
  }
  const project=([x,y,z])=>{
    const c=Math.cos(yaw),s=Math.sin(yaw),a=x*c-y*s,b=x*s+y*c;
    return {x:width*.51+(a-b)*scale,y:height*.54+(a+b)*scale*.43-z*scale*1.03};
  };
  const line=(a,b,color,alpha=1,lineWidth=.65)=>{
    const p=project(a),q=project(b);ctx.globalAlpha=alpha;ctx.strokeStyle=color;ctx.lineWidth=lineWidth;ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(q.x,q.y);ctx.stroke();
  };
  const palette=()=>{const styles=getComputedStyle(field);ink=styles.getPropertyValue('--ink').trim();accent=styles.getPropertyValue('--accent').trim();muted=styles.getPropertyValue('--muted').trim();bg=styles.getPropertyValue('--bg').trim();};
  const draw=()=>{
    if(!width)return;
    ctx.clearRect(0,0,width,height);
    // A drafting plane, dimension lines and a faint elevation trace.
    for(let i=-4;i<=4;i++){
      line([i,-3.4,0],[i,3.4,0],muted,.12,.5);
      line([-3.6,i,0],[3.6,i,0],muted,.12,.5);
    }
    [[[-3.4,-2.8,0],[3.4,-2.8,0]],[[3.4,-2.8,0],[3.4,2.8,0]],[[3.4,2.8,0],[-3.4,2.8,0]],[[-3.4,2.8,0],[-3.4,-2.8,0]]].forEach(([a,b])=>line(a,b,ink,.3));
    for(let t=-3;t<=3;t+=.2){line([t,-2.93,0],[t,-2.82,0],muted,.4,.5);}
    modules.forEach((m,i)=>{
      line([m.x,m.y,.02],[m.x,0,.02],i===selected?accent:muted,.6,.85);
      line([m.x,0,.02],[0,0,.02],i===selected?accent:muted,.6,.85);
      line([m.x,m.y,0],[m.x,m.y,m.z],accent,i===selected?.75:.2,.7);
    });
    for(const point of points){const p=project(point.p);ctx.fillStyle=point.group===selected||point.group===4?accent:ink;ctx.globalAlpha=point.alpha*(point.group===selected?1:.8);ctx.fillRect(p.x,p.y,1,1);}
    for(const e of edges)line(e.a,e.b,e.group===selected?accent:ink,e.group===selected?.85:.52,.7);
    // These are observation markers travelling towards the app, not network packets.
    modules.forEach((m,i)=>{
      const progress=(phase*.17+i*.24)%1;
      const from=[m.x,m.y,m.z*.6],to=[0,0,core.z];
      const p=project(from.map((v,j)=>v+(to[j]-v)*progress));
      ctx.globalAlpha=.9;ctx.fillStyle=accent;ctx.beginPath();ctx.arc(p.x,p.y,2.2,0,Math.PI*2);ctx.fill();
      const anchor=project([m.x,m.y,m.z+.15]);
      const side=m.x<0?-1:1;
      buttons[i].style.left=`${Math.max(55,Math.min(width-55,anchor.x+side*20))}px`;
      buttons[i].style.top=`${anchor.y-26}px`;
    });
    const center=project([0,0,.68]);hub.style.left=center.x+'px';hub.style.top=center.y+'px';
    ctx.globalAlpha=1;
    const p=project([0,0,0]);ctx.strokeStyle=accent;ctx.globalAlpha=.3;ctx.lineWidth=.65;
    ctx.beginPath();ctx.ellipse(p.x,p.y,scale*.94,scale*.4,0,0,Math.PI*2);ctx.stroke();ctx.globalAlpha=1;
  };
  const canMove=()=>!paused&&!reduce.matches&&visible&&!document.hidden;
  const tick=time=>{
    raf=0;if(!canMove())return;
    if(time-last>=40){const dt=last?Math.min((time-last)/1000,.08):0;phase+=dt;yaw+=(targetYaw-yaw)*.08;draw();last=time;}
    raf=requestAnimationFrame(tick);
  };
  const sync=()=>{if(raf)cancelAnimationFrame(raf);raf=0;last=0;draw();if(canMove())raf=requestAnimationFrame(tick);};
  const resize=()=>{const r=field.getBoundingClientRect();width=r.width;height=r.height;const ratio=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio);ctx.setTransform(ratio,0,0,ratio,0,0);scale=Math.min(width/11.6,height/5.3);draw();};
  buttons.forEach((button,i)=>button.addEventListener('click',()=>{
    selected=i;buttons.forEach((b,n)=>b.setAttribute('aria-pressed',String(n===i)));
    const m=modules[i],name=document.querySelector('[data-field-process]');name.replaceChildren(document.createTextNode(m.name+' '));const port=document.createElement('b');port.textContent=':'+m.port;name.append(port);
    document.querySelector('[data-field-bind]').textContent=m.bind;document.querySelector('[data-field-project]').textContent=m.project;draw();
  }));
  field.addEventListener('pointermove',event=>{if(event.pointerType==='touch'||!canMove())return;const r=field.getBoundingClientRect();targetYaw=-.13+((event.clientX-r.left)/width-.5)*.22;});
  field.addEventListener('pointerleave',()=>{targetYaw=-.13;});
  const setPause=value=>{paused=value;field.dataset.paused=String(value);pauseButton.setAttribute('aria-pressed',String(value));pauseButton.textContent=value?'Resume motion ▷':'Pause motion Ⅱ';sync();};
  pauseButton.addEventListener('click',()=>setPause(!paused));
  reduce.addEventListener('change',event=>setPause(event.matches));
  document.addEventListener('visibilitychange',sync);
  new ResizeObserver(resize).observe(field);
  new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;sync();},{rootMargin:'100px'}).observe(field);
  new MutationObserver(()=>{palette();draw();}).observe(document.documentElement,{attributes:true,attributeFilter:['data-theme']});
  palette();resize();setPause(paused);
})();
