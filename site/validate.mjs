import {readFile,readdir} from 'node:fs/promises';
import {dirname,join,relative,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=dirname(fileURLToPath(import.meta.url));
const out=join(root,'dist');
const publicMode=process.argv.includes('--public');
const origin='https://portpilot.srinivas.dev';

async function walk(dir){
  const files=[];
  for(const entry of await readdir(dir,{withFileTypes:true})){
    const path=join(dir,entry.name);
    if(entry.isDirectory())files.push(...await walk(path));else files.push(path);
  }
  return files;
}

const files=await walk(out);
const htmlFiles=files.filter(path=>path.endsWith('.html'));
const known=new Set(files.map(path=>relative(out,path).split(sep).join('/')));
const ids=new Map();
const failures=[];
let references=0;

for(const path of htmlFiles){
  const rel=relative(out,path).split(sep).join('/');
  const html=await readFile(path,'utf8');
  const pageIds=[...html.matchAll(/\sid="([^"]+)"/g)].map(match=>match[1]);
  const duplicates=pageIds.filter((id,index)=>pageIds.indexOf(id)!==index);
  if(duplicates.length)failures.push(`${rel}: duplicate IDs ${[...new Set(duplicates)].join(', ')}`);
  ids.set(rel,new Set(pageIds));

  for(const match of html.matchAll(/\s(?:href|src)="([^"]+)"/g)){
    const value=match[1];
    if(!value.startsWith('/')&&!value.startsWith('#'))continue;
    references++;
    const [rawPath,fragment='']=value.split('#',2);
    let targetRel;
    if(!rawPath)targetRel=rel;
    else {
      const clean=decodeURI(rawPath.split('?')[0]);
      targetRel=clean.endsWith('/')?`${clean.slice(1)}index.html`:clean.slice(1);
    }
    if(!known.has(targetRel)){
      failures.push(`${rel}: missing ${value}`);
      continue;
    }
    if(fragment&&targetRel.endsWith('.html')){
      if(!ids.has(targetRel))ids.set(targetRel,new Set([...((await readFile(join(out,targetRel),'utf8')).matchAll(/\sid="([^"]+)"/g))].map(item=>item[1])));
      if(!ids.get(targetRel).has(decodeURIComponent(fragment)))failures.push(`${rel}: missing anchor ${value}`);
    }
  }
}

const rootHtml=await readFile(join(out,'index.html'),'utf8');
const v2Html=await readFile(join(out,'v2/index.html'),'utf8');
const robots=await readFile(join(out,'robots.txt'),'utf8');
const headers=await readFile(join(out,'_headers'),'utf8');
const info=JSON.parse(await readFile(join(out,'build-info.json'),'utf8'));

if(!headers.includes("Content-Security-Policy: default-src 'self'"))failures.push('_headers: missing CSP');
if(!headers.includes('X-Content-Type-Options: nosniff'))failures.push('_headers: missing nosniff');
if(publicMode){
  if(!rootHtml.includes('class="hero-v2 wrap"'))failures.push('public root is not V2');
  if(!rootHtml.includes('content="index, follow"'))failures.push('public root is not indexable');
  if(!rootHtml.includes(`rel="canonical" href="${origin}/"`))failures.push('public root canonical is missing');
  if(!v2Html.includes('content="noindex, nofollow"'))failures.push('/v2 alias must remain noindex');
  if(!known.has('classic/index.html'))failures.push('/classic original is missing');
  if(!robots.includes('Allow: /')||!robots.includes(`${origin}/sitemap.xml`))failures.push('public robots policy is wrong');
  if(info.preview||info.origin!==origin)failures.push('public build-info is wrong');
  if(!known.has('sitemap.xml'))failures.push('public sitemap is missing');
}else{
  if(!rootHtml.includes('content="noindex, nofollow"')||!v2Html.includes('content="noindex, nofollow"'))failures.push('preview pages must be noindex');
  if(!robots.includes('Disallow: /'))failures.push('preview robots policy is wrong');
  if(!info.preview||info.origin!==null)failures.push('preview build-info is wrong');
}

if(failures.length){
  console.error(JSON.stringify({mode:publicMode?'public':'preview',htmlPages:htmlFiles.length,references,failures},null,2));
  process.exit(1);
}

console.log(JSON.stringify({mode:publicMode?'public':'preview',htmlPages:htmlFiles.length,references,sourceVersion:info.sourceVersion,sourceCommit:info.sourceCommit},null,2));
