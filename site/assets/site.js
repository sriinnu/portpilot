(() => {
  const $ = (s,root=document) => root.querySelector(s);
  const $$ = (s,root=document) => [...root.querySelectorAll(s)];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const themeButton=$('[data-theme-toggle]');
  const isV2=document.body.classList.contains('v2');
  const setTheme=value=>{
    document.documentElement.dataset.theme=value;
    themeButton?.setAttribute('aria-label',`Switch to ${value==='light'?'dark':'light'} appearance`);
    const icon=isV2?`favicon-v2-${value}.svg`:value==='light'?'favicon-light.svg':'favicon.svg';
    $('link[rel="icon"]')?.setAttribute('href',`/assets/${icon}`);
    $('meta[name="theme-color"]')?.setAttribute('content',getComputedStyle(document.body).getPropertyValue('--bg').trim());
  };
  const base=document.body.dataset.base||'';
  const themeKey=isV2?'portpilot-v2-theme':'portpilot-site-theme';
  let saved;
  try{saved=localStorage.getItem(themeKey);}catch{}
  setTheme(saved==='light'||(!saved&&isV2)?'light':'dark');
  themeButton?.addEventListener('click',()=>{
    const next=document.documentElement.dataset.theme==='light'?'dark':'light';
    setTheme(next);try{localStorage.setItem(themeKey,next);}catch{}
  });

  const observatory=$('[data-observatory]');
  if(observatory){
    const listeners={
      3000:{name:'node',bind:'127.0.0.1',project:'workshop/web'},
      5432:{name:'postgres',bind:'127.0.0.1',project:'workshop/data'},
      8080:{name:'python',bind:'0.0.0.0',project:'workshop/api'},
      6379:{name:'redis',bind:'127.0.0.1',project:'workshop/cache'}
    };
    $$('[data-listener]',observatory).forEach(button=>button.addEventListener('click',()=>{
      const port=button.dataset.listener,entry=listeners[port];
      $$('[data-listener]',observatory).forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
      const name=$('[data-listener-name]');name.replaceChildren(document.createTextNode(entry.name+' '));
      const number=document.createElement('span');number.textContent=':'+port;name.append(number);
      $('[data-listener-bind]').textContent=entry.bind;
      $('[data-listener-project]').textContent=entry.project;
    }));
    const svg=$('svg',observatory),button=$('[data-motion-toggle]');
    const pause=on=>{
      if(on)svg.pauseAnimations();else svg.unpauseAnimations();
      button.setAttribute('aria-pressed',String(on));
      button.textContent=on?'Resume motion ▷':'Pause motion Ⅱ';
    };
    pause(reduced.matches);
    button.addEventListener('click',()=>pause(button.getAttribute('aria-pressed')!=='true'));
    reduced.addEventListener('change',event=>pause(event.matches));
  }

  const surfaceButtons=$$('[data-surface]');
  if(surfaceButtons.length){
    const target=$('[data-surface-content]'),appView=target.innerHTML;
    const section=target.closest('section');
    const appTabs={
      listeners:{head:['PORT','PROCESS','BIND'],rows:[['3000','node','127.0.0.1'],['5432','postgres','127.0.0.1'],['6379','redis','127.0.0.1'],['8080','python','0.0.0.0']],note:'One listener uses a wider bind address.',detail:'A bind address alone does not prove network reachability.'},
      connections:{head:['PROCESS','REMOTE','STATE'],rows:[['node','127.0.0.1:5432','ESTABLISHED'],['node','127.0.0.1:6379','ESTABLISHED'],['python','127.0.0.1:3000','ESTABLISHED']],note:'See the other end of a connection.',detail:'Connection details depend on operating-system visibility.'},
      schedules:{head:['SCHEDULE','COMMAND','SOURCE'],rows:[['0 9 * * 1-5','backup.sh','user crontab'],['*/15 * * * *','sync.sh','user crontab'],['30 18 * * *','report.sh','user crontab']],note:'Inspect scheduled commands alongside your processes.',detail:'Illustrative entries. Nothing here runs or changes your machine.'}
    };
    let appTab='listeners',active,manualAt=null,frame;
    const renderApp=()=>{
      const view=appTabs[appTab],app=$('.mini-app',target);
      if(!app)return;
      const nav=$('.mini-nav',app);nav.setAttribute('role','tablist');nav.setAttribute('aria-label','Workspace preview');
      nav.innerHTML=Object.keys(appTabs).map(key=>`<button type="button" role="tab" id="preview-${key}" aria-controls="preview-table" aria-selected="${key===appTab}" tabindex="${key===appTab?0:-1}" data-app-tab="${key}">${key[0].toUpperCase()+key.slice(1)}</button>`).join('');
      const table=$('.mini-table',app);table.id='preview-table';table.setAttribute('role','tabpanel');table.setAttribute('aria-labelledby',`preview-${appTab}`);
      table.innerHTML=`<div class="mini-table-head">${view.head.map(x=>`<span>${x}</span>`).join('')}</div>`+view.rows.map(row=>`<div><strong>${row[0]}</strong><span>${row[1]}</span><code>${row[2]}</code></div>`).join('');
      $('.mini-note',app).innerHTML=`<span class="status-dot"></span> ${view.note}<br><small>${view.detail}</small>`;
    };
    const views={
      app:{title:'PortPilot / workspace',html:appView,link:'/guide/app/',label:'Explore the app guide ↗'},
      cli:{title:'portpilot / command line',html:'<pre class="terminal-pane"><span class="prompt">$ portpilot list --start 3000 --end 9000</span>\n\nPORT     PROTO   PID     COMMAND\n3000     TCP     7124    node\n5432     TCP     4382    postgres\n6379     TCP     5091    redis\n8080     TCP     6210    python\n\n<span class="prompt">$ portpilot find --start 3000 --end 3100</span>\n3001\n\n<span class="prompt">$ portpilot list --json</span>\n…</pre>',link:'/guide/cli/',label:'Open the CLI reference ↗'},
      tui:{title:'portpilot-tui / terminal workspace',html:'<pre class="terminal-pane"><span class="prompt">$ portpilot tui</span>\n\n┌─ PortPilot ────────────────────────┐\n│  PORT    PROCESS       PROTOCOL   │\n│  <span class="prompt">3000    node          TCP</span>        │\n│  5432    postgres      TCP        │\n│  6379    redis         TCP        │\n│  8080    python        TCP        │\n│                                  │\n│  Your terminal. One shared core.  │\n└──────────────────────────────────┘</pre>',link:'/guide/install/#source',label:'Build the terminal tools ↗'}
    };
    const select=(button,manual=false)=>{
      if(manual){manualAt=scrollY;history.replaceState(null,'',`#${button.id}`);}
      if(active===button)return;
      active=button;
      const view=views[button.dataset.surface];
      surfaceButtons.forEach(b=>{b.setAttribute('aria-selected',String(b===button));b.tabIndex=b===button?0:-1;});
      target.innerHTML=view.html;
      $('[data-surface-title]').textContent=view.title;
      const link=$('[data-surface-link]');link.href=base+view.link;link.textContent=view.label;
      $('#surface-panel').setAttribute('aria-labelledby',button.id);
      if(button.dataset.surface==='app')renderApp();
    };
    surfaceButtons.forEach((b,i)=>{
      b.addEventListener('click',()=>select(b,true));
      b.addEventListener('keydown',event=>{
        let next;if(['ArrowDown','ArrowRight'].includes(event.key))next=(i+1)%surfaceButtons.length;
        if(['ArrowUp','ArrowLeft'].includes(event.key))next=(i+surfaceButtons.length-1)%surfaceButtons.length;
        if(event.key==='Home')next=0;if(event.key==='End')next=surfaceButtons.length-1;
        if(next!==undefined){event.preventDefault();select(surfaceButtons[next],true);surfaceButtons[next].focus();}
      });
    });
    target.addEventListener('click',event=>{
      const button=event.target.closest('[data-app-tab]');if(!button)return;
      appTab=button.dataset.appTab;manualAt=scrollY;renderApp();$(`[data-app-tab="${appTab}"]`,target).focus({preventScroll:true});
    });
    target.addEventListener('keydown',event=>{
      const button=event.target.closest('[data-app-tab]');if(!button)return;
      const keys=Object.keys(appTabs),i=keys.indexOf(appTab);let next;
      if(event.key==='ArrowRight')next=(i+1)%keys.length;
      if(event.key==='ArrowLeft')next=(i+keys.length-1)%keys.length;
      if(event.key==='Home')next=0;if(event.key==='End')next=keys.length-1;
      if(next!==undefined){event.preventDefault();appTab=keys[next];manualAt=scrollY;renderApp();$(`[data-app-tab="${appTab}"]`,target).focus({preventScroll:true});}
    });
    const fromHash=()=>{const button=surfaceButtons.find(b=>`#${b.id}`===location.hash);if(button)select(button);};
    select(surfaceButtons[0]);fromHash();addEventListener('hashchange',fromHash);
    const scrollSelect=()=>{
      frame=null;
      if(!matchMedia('(min-width: 851px)').matches||reduced.matches||target.contains(document.activeElement))return;
      if(manualAt!==null&&Math.abs(scrollY-manualAt)<Math.max(160,innerHeight*.2))return;
      manualAt=null;
      const marker=innerHeight*.48;
      const button=surfaceButtons.find(b=>{const r=b.getBoundingClientRect();return r.top<=marker&&r.bottom>=marker;});
      if(button)select(button);
    };
    addEventListener('scroll',()=>{if(!frame)frame=requestAnimationFrame(scrollSelect);},{passive:true});
    addEventListener('resize',()=>{if(!frame)frame=requestAnimationFrame(scrollSelect);});
  }

  $$('[data-copy]').forEach(button=>button.addEventListener('click',async()=>{
    const code=$('pre code',button.closest('.code-block'));
    try{
      await navigator.clipboard.writeText(code.textContent);
      button.textContent='Copied ✓';$('[data-copy-status]').textContent='Commands copied.';
    }catch{
      const range=document.createRange();range.selectNodeContents(code);
      const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);
      button.textContent='Selected';$('[data-copy-status]').textContent='Clipboard unavailable. Commands selected for manual copying.';
    }
    setTimeout(()=>{button.textContent='Copy';},2200);
  }));

  const dialog=$('.search-dialog'),input=$('[data-search-input]'),results=$('.search-results'),status=$('.search-status');
  let index,loading,opener,request=0;
  const load=()=>index?Promise.resolve(index):(loading??=fetch(base+'/search-index.json').then(r=>{if(!r.ok)throw new Error('index');return r.json();}).then(data=>index=data).catch(error=>{loading=undefined;throw error;}));
  const render=async()=>{
    const seq=++request,query=input.value.trim().toLowerCase(),words=query.split(/\s+/).filter(Boolean);
    try{
      const data=await load();if(seq!==request)return;
      const matches=data.map(page=>{
        const title=page.title.toLowerCase(),description=page.description.toLowerCase(),text=page.text.toLowerCase();
        let score=0;
        for(const word of words){if(!`${title} ${description} ${text}`.includes(word))return null;score+=title.includes(word)?12:description.includes(word)?5:1;}
        const heading=words.length?page.headings.filter(h=>words.every(w=>(h.text||h.title).toLowerCase().includes(w))).sort((a,b)=>words.filter(w=>b.title.toLowerCase().includes(w)).length-words.filter(w=>a.title.toLowerCase().includes(w)).length)[0]:null;
        if(heading)score+=8;
        return {page,score,heading};
      }).filter(Boolean).sort((a,b)=>b.score-a.score).slice(0,8);
      results.replaceChildren();
      status.textContent=words.length?(matches.length?`${matches.length} ${matches.length===1?'guide':'guides'} found`:'No matches. Try “install”, “CLI”, “proxy” or “development”.'):'Browse the field guide, or search for a command.';
      matches.forEach(({page,heading})=>{
        const a=document.createElement('a');a.href=page.url+(heading?'#'+heading.id:'');
        const h=document.createElement('h3');h.textContent=page.title;
        const p=document.createElement('p');p.textContent=page.description;
        a.append(h,p);
        if(heading){const small=document.createElement('small');small.textContent='↳ '+heading.title;a.append(small);}
        results.append(a);
      });
    }catch{status.textContent='Search could not load. Browse the field guide below.';results.replaceChildren();const a=document.createElement('a');a.href=base+'/guide/';a.textContent='Open the field guide ↗';results.append(a);}
  };
  const open=()=>{if(dialog.open)return;opener=document.activeElement;dialog.showModal();input.focus();render();};
  $$('[data-search-open]').forEach(b=>b.addEventListener('click',open));
  $('[data-search-close]').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('close',()=>opener?.focus());
  dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
  input.addEventListener('input',render);
  dialog.addEventListener('keydown',event=>{
    if(event.key==='Escape'){event.preventDefault();dialog.close();return;}
    const links=$$('a',results),active=links.indexOf(document.activeElement);
    if(event.key==='ArrowDown'){event.preventDefault();links[Math.min(active+1,links.length-1)]?.focus();}
    if(event.key==='ArrowUp'){event.preventDefault();if(active<=0)input.focus();else links[active-1]?.focus();}
    if(event.key==='Enter'&&document.activeElement===input&&links[0]){event.preventDefault();links[0].click();}
  });
  document.addEventListener('keydown',event=>{
    const editing=/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)||document.activeElement?.isContentEditable;
    if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='k'){event.preventDefault();dialog.open?dialog.close():open();}
    else if(event.key==='/'&&!editing&&!dialog.open){event.preventDefault();open();}
  });
  const mobileGuide=$('.docs-sidebar details');
  if(mobileGuide&&matchMedia('(max-width:600px)').matches)mobileGuide.open=false;
  const sections=$$('.prose>section');
  if(sections.length&&'IntersectionObserver' in window){
    const observer=new IntersectionObserver(entries=>{
      const entry=entries.find(e=>e.isIntersecting);if(!entry)return;
      $$('.docs-toc nav a').forEach(a=>{if(a.hash==='#'+entry.target.id)a.setAttribute('aria-current','location');else a.removeAttribute('aria-current');});
    },{rootMargin:'-5% 0px -65% 0px'});
    sections.forEach(s=>observer.observe(s));
  }
})();
