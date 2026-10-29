import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {join,dirname} from 'node:path';

const hero=`<section class="hero-v2 wrap" aria-labelledby="hero-title">
  <div class="field-caption"><span><i class="status-dot"></i> PORTPILOT / THE LOCAL OBSERVATORY</span><span>FIG. 01 — A MACHINE, IN FOCUS</span></div>
  <div class="hero-v2-copy"><p class="eyebrow">A SMALL TOOL FOR THE WHOLE PICTURE</p><h1 id="hero-title">Know what’s<br><em>listening.</em></h1><p class="hero-description">The ports. The processes. <br>The things you left running. <br>Bring your machine back into focus.</p><div class="actions"><a class="button primary" href="#install">Get PortPilot <span>↓</span></a><a class="text-link" href="/guide/cli/">Meet the CLI ↗</a></div><div class="hero-meta"><span>macOS app</span><span>CLI & TUI</span><span>Open source</span></div></div>
  <div class="machine-field" data-point-field><canvas aria-hidden="true"></canvas><p class="sr-only">An illustrative drawing of local apps and services. Observation markers travel inward to PortPilot, which reads the operating system. Select an app to inspect its sample details.</p><div class="field-orientation" aria-hidden="true">LOCAL GRID / 127.0.0.1<br><span>OS OBSERVATIONS → PORTPILOT</span></div><div class="field-nodes"><button type="button" data-node="0" aria-pressed="true"><span>01 / WEB APP</span><strong>Dev server <b>:3000</b></strong></button><button type="button" data-node="1" aria-pressed="false"><span>02 / iOS SIMULATOR</span><strong>iOS Simulator <b>:5050</b></strong></button><button type="button" data-node="2" aria-pressed="false"><span>03 / NETWORK APP</span><strong>Network app <b>:41641</b></strong></button><button type="button" data-node="3" aria-pressed="false"><span>04 / macOS APP</span><strong>macOS app <b>:8080</b></strong></button></div><span class="field-hub" aria-hidden="true">P<span>/</span><small>PORTPILOT</small></span><div class="field-key"><span><i></i> OBSERVATION</span><button type="button" data-field-pause aria-pressed="false">Pause motion Ⅱ</button></div></div>
  <div class="field-readout" aria-live="polite"><span class="readout-label">SELECT AN APP ↗<small>ILLUSTRATIVE DATA</small></span><div><span>PROCESS / PORT</span><strong data-field-process>Dev server <b>:3000</b></strong></div><div><span>BIND ADDRESS</span><strong data-field-bind>127.0.0.1</strong></div><div><span>PROJECT</span><strong data-field-project>workshop/web</strong></div><p>PortPilot reads local OS observations.<br>This is illustrative, not a live snapshot.</p></div>
</section>`;

export async function buildV2(out,{publicOrigin=''}={}){
  const pages=[];
  async function walk(dir){for(const entry of await readdir(dir,{withFileTypes:true})){if(['v2','assets','studies'].includes(entry.name))continue;const path=join(dir,entry.name);if(entry.isDirectory())await walk(path);else if(entry.name.endsWith('.html'))pages.push(path);}}
  await walk(out);
  for(const path of pages){
    let html=await readFile(path,'utf8');
    if(path===join(out,'index.html'))html=html.replace(/<section class="hero wrap"[\s\S]*?<\/section>/,hero);
    html=html.replace(/href="\/(?!assets\/|studies\/)([^"]*)"/g,'href="/v2/$1"')
      .replace(/<body class="([^"]*)">/,'<body class="$1 v2" data-base="/v2">')
      .replace('</head>','<link rel="stylesheet" href="/assets/v2.css"><script src="/assets/v2.js" defer></script></head>');
    const dest=join(out,'v2',path.slice(out.length+1));await mkdir(dirname(dest),{recursive:true});await writeFile(dest,html);
  }
  const index=JSON.parse(await readFile(join(out,'search-index.json'),'utf8')).map(page=>({...page,url:'/v2'+page.url}));
  await writeFile(join(out,'v2/search-index.json'),JSON.stringify(index));
  if(publicOrigin){
    const origin=publicOrigin.replace(/\/$/,'');
    for(const path of pages){
      let html=await readFile(path,'utf8');
      html=html.replace(/href="\/(?!assets\/|studies\/)([^"]*)"/g,'href="/classic/$1"')
        .replace(/<body class="([^"]*)">/,'<body class="$1" data-base="/classic">');
      const dest=join(out,'classic',path.slice(out.length+1));await mkdir(dirname(dest),{recursive:true});await writeFile(dest,html);
    }
    const classicIndex=JSON.parse(await readFile(join(out,'search-index.json'),'utf8')).map(page=>({...page,url:'/classic'+page.url}));
    await writeFile(join(out,'classic/search-index.json'),JSON.stringify(classicIndex));
    for(const path of pages){
      const relative=path.slice(out.length+1);
      let html=await readFile(join(out,'v2',relative),'utf8');
      const pathname=relative==='index.html'?'/':`/${relative.replace(/index\.html$/,'')}`;
      const canonical=`${origin}${pathname}`;
      html=html.replaceAll('href="/v2/','href="/')
        .replace('data-base="/v2"','data-base=""')
        .replace('<meta name="robots" content="noindex, nofollow">','<meta name="robots" content="index, follow">')
        .replace('</head>',`<link rel="canonical" href="${canonical}"><meta property="og:url" content="${canonical}"></head>`);
      await writeFile(path,html);
    }
    const publicIndex=index.map(page=>({...page,url:page.url.replace(/^\/v2/, '')||'/'}));
    await writeFile(join(out,'search-index.json'),JSON.stringify(publicIndex));
  }
  console.log(JSON.stringify({variant:'v2',pages:pages.length,url:'http://127.0.0.1:4328/v2/'}));
}
