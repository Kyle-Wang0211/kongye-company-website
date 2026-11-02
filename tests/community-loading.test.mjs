import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import * as data from '../docs/community-data.mjs';
import {legacyWorkIds,workCovers} from '../docs/community-work-links.mjs';

class Element {
  children=[]; dataset={}; listeners=new Map(); attributes={}; style={}; textContent='';
  classList={add:(name)=>{this.className=((this.className||'')+' '+name).trim();},remove:(name)=>{this.className=(this.className||'').split(' ').filter(x=>x!==name).join(' ');},contains:(name)=>(this.className||'').split(' ').includes(name)};
  append(...nodes){for(const node of nodes){node.parent=this;this.children.push(node);}}
  remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);}
  decode=async()=>{};
  insertBefore(node,before){const i=this.children.indexOf(before);if(i<0)this.append(node);else this.children.splice(i,0,node);}
  replaceChildren(...nodes){this.children=[...nodes];}
  setAttribute(k,v){this.attributes[k]=v;}
  removeAttribute(k){delete this.attributes[k];}
  addEventListener(name,fn){this.listeners.set(name,fn);}
  querySelector(selector){return selector==='[data-example]'?this.children.find(x=>x.dataset.example)||null:this.parts?.[selector];}
  querySelectorAll(){return [];}
  showModal(){this.open=true;}
  close(){this.open=false;}
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const defer=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const response=value=>({ok:true,json:async()=>value});
const work={id:'12345678-1234-4234-8234-123456789abc',user_id:'12345678-1234-4234-8234-123456789abd',title:'真实社区作品',format:'glb',file_size_bytes:100,model_storage_path:'owner/model.glb',published_at:'2026-11-02T04:00:00Z'};
function boot(search='',{intersection=false}={}){
 const grid=new Element(),status=new Element(),more=new Element(),dialog=new Element();dialog.parts={iframe:new Element(),h2:new Element(),button:new Element()};
 const elements={'#community-grid':grid,'#feed-status':status,'#feed-more':more,'#work-dialog':dialog,'#share-work':new Element(),'#share-status':new Element(),'#work-meta':new Element()};
 const pending=[],timers=new Map(),observers=[],navigations=[],events=new Map();let clock=0;
 class Observer{constructor(callback){this.callback=callback;observers.push(this);}observe(target){this.target=target;}disconnect(){this.target=null;}}
 const fetch=(url,options)=>{const gate=defer();pending.push({url:String(url),options,...gate});return gate.promise;};
 const source=readFileSync(new URL('../docs/community-feed.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
 vm.runInNewContext(source,{...(intersection?{IntersectionObserver:Observer}:{}),...data,legacyWorkIds,workCovers,document:{querySelector:s=>elements[s],createElement:()=>new Element()},fetch,URL,AbortSignal,location:{href:'https://kongye.space/'+search,assign:url=>navigations.push(url)},navigator:{},setTimeout:(f)=>{const id=++clock;timers.set(id,f);return id;},clearTimeout:id=>timers.delete(id),window:{addEventListener:(name,callback)=>events.set(name,callback)}});
 return {grid,status,more,pending,dialog,elements,timers,navigations,events,intersect:target=>{for(const observer of observers)if(observer.target===target)observer.callback([{isIntersecting:true}]);}};
}
async function configure(page){page.pending.shift().resolve(response({origin:'https://api.kongye.space',anonKey:'public'}));await settle();}
async function completeFeed(page,rows=[work]){page.pending.shift().resolve(response(rows));await settle();if(rows.length){page.pending.shift().resolve(response([{id:work.user_id,display_name:'窗后城'}]));await settle();}}

const realCards=page=>page.grid.children.filter(e=>e.className==='community-card');
test('refresh reserves inert shimmer shells before real metadata without flashing local-only works',async()=>{
 const page=boot();assert.equal(realCards(page).length,0);assert.equal(page.grid.children.length,12);
 assert(page.grid.children.every(e=>e.attributes['aria-hidden']==='true'));
 await configure(page);assert.equal(realCards(page).length,0);
 page.pending.shift().resolve(response([work]));await settle();assert.equal(realCards(page).length,1);
 assert.equal(realCards(page)[0].children[1].children[1].attributes['aria-busy'],'true');
 page.pending.shift().resolve(response([{id:work.user_id,display_name:'窗后城'}]));await settle();
 assert.equal(page.grid.children.length,1);assert.equal(realCards(page).length,1);assert(!page.grid.children.some(x=>x.dataset.example));
});

test('failed feed offers retry without substituting three local works; retry stays deduplicated',async()=>{
 const page=boot();await configure(page);page.pending.shift().reject(Error('offline'));await settle();
 assert.equal(page.grid.children.length,0);assert.equal(page.more.textContent,'重新加载');assert.equal(page.more.disabled,false);
 const retry=page.more.listeners.get('click')();await completeFeed(page);await retry;assert.equal(page.grid.children.length,1);
 const again=page.more.listeners.get('click')();page.pending.shift().resolve(response([work]));await again;
 assert.equal(page.grid.children.length,1);
});

test('config request has a bounded timeout so a stalled config can fail visibly',()=>{
 const page=boot();assert(page.pending[0].options?.signal instanceof AbortSignal);
});

test('metadata appears before independent cover decode and frame geometry never switches to natural aspect',async()=>{
 const page=boot();await configure(page);
 await completeFeed(page,[{...work,description:'Only in details',thumbnail_storage_path:'owner/cover.png'}]);
 const card=realCards(page)[0],picture=card.children[0].children[0],image=picture.children[0];
 assert.equal(card.children[0].children[1].textContent,work.title);
 assert.equal(card.children[1].children[1].textContent,'窗后城');
 assert.equal(picture.dataset.mediaState,'loading');
 const decode=defer();image.decode=()=>decode.promise;image.naturalWidth=1920;image.naturalHeight=1080;
 image.listeners.get('load')();await settle();assert.equal(picture.dataset.mediaState,'loading');
 decode.resolve();await settle();assert.equal(picture.dataset.mediaState,'ready');
 assert.equal(picture.style.aspectRatio,undefined);assert(image.classList.contains('is-ready'));
 assert(!JSON.stringify(card,(key,value)=>key==='parent'?undefined:value).includes('Only in details'));
});

test('cover error and deadline stop shimmer while retaining usable metadata',async()=>{
 for(const mode of ['error','deadline']){
  const page=boot();await configure(page);await completeFeed(page,[{...work,thumbnail_storage_path:'owner/cover.png'}]);
  const card=realCards(page)[0],picture=card.children[0].children[0],image=picture.children[0];
  if(mode==='error')image.listeners.get('error')();else [...page.timers.values()][0]();
  assert.equal(picture.dataset.mediaState,'error');assert(!picture.classList.contains('is-loading'));
  assert.equal(card.children[0].children[1].textContent,work.title);
 }
});

test('pagination keeps existing cards while bounded shimmer shells await the next page',async()=>{
 const page=boot();await configure(page);await completeFeed(page,[work]);
 const existing=page.grid.children[0];const retry=page.more.listeners.get('click')();
 assert.equal(page.grid.children[0],existing);assert.equal(page.grid.children.length,13);
 page.pending.shift().reject(Error('offline'));await retry;
 assert.deepEqual(page.grid.children,[existing]);assert.equal(page.more.textContent,'重新加载');
});

test('scroll pagination is single-flight and a failed page waits for explicit retry',async()=>{
 const page=boot('',{intersection:true});await configure(page);
 await completeFeed(page,Array.from({length:12},(_,i)=>({...work,id:work.id.slice(0,-3)+String(i).padStart(3,'0')})));
 page.intersect(page.more);page.intersect(page.more);assert.equal(page.pending.length,1);
 page.pending.shift().reject(Error('offline'));await settle();
 page.intersect(page.more);assert.equal(page.pending.length,0,'no automatic failure loop');
 const retry=page.more.listeners.get('click')();assert.equal(page.pending.length,1);
 page.pending.shift().resolve(response([]));await retry;assert.equal(page.more.hidden,true);
});

test('browser Back restores automatic pagination after cached page navigation',async()=>{
 const page=boot('',{intersection:true});await configure(page);
 await completeFeed(page,Array.from({length:12},(_,i)=>({...work,id:work.id.slice(0,-3)+String(i).padStart(3,'0')})));
 page.events.get('pagehide')();page.intersect(page.more);assert.equal(page.pending.length,0);
 page.events.get('pageshow')?.();page.intersect(page.more);assert.equal(page.pending.length,1);
 page.pending.shift().resolve(response([]));await settle();
});

test('legacy links and new shares resolve to the same real work identity',async()=>{
 const slug=Object.keys(legacyWorkIds)[0];assert(slug);
 const page=boot('?example='+slug);await configure(page);await completeFeed(page,[]);
 const lookup=page.pending.shift();assert.equal(new URL(lookup.url).searchParams.get('id'),'eq.'+legacyWorkIds[slug]);
 lookup.resolve(response([{...work,id:legacyWorkIds[slug]}]));await settle();
 assert.equal(page.pending.length,0);
 assert.equal(page.dialog.open,undefined);assert.equal(new URL(page.navigations.at(-1)).pathname,'/community/');assert.equal(new URL(page.navigations.at(-1)).searchParams.get('work'),legacyWorkIds[slug]);
 assert.equal(new URL(page.navigations.at(-1)).searchParams.get('release'),'shared-bilingual-comments-20261103-v8');
});

for(const failure of ['config','lookup'])test('direct work link recovers after '+failure+' failure',async()=>{
 const page=boot('?work='+work.id);
 if(failure==='config'){page.pending.shift().reject(Error('offline'));await settle();}
 else {await configure(page);await completeFeed(page,[]);page.pending.shift().reject(Error('offline'));await settle();}
 assert.equal(page.more.textContent,'重新加载');
 const retry=page.more.listeners.get('click')();
 if(failure==='config')await configure(page);
 await completeFeed(page,[]);
 const lookup=page.pending.shift();assert.equal(new URL(lookup.url).searchParams.get('id'),'eq.'+work.id);
 lookup.resolve(response([work]));await settle();
 await retry;assert.equal(page.pending.length,0);
 assert.equal(new URL(page.navigations.at(-1)).searchParams.get('work'),work.id);
});


test('slow author lookup leaves real cards and cover requests usable before hydrating the same nodes',async()=>{
 const page=boot();await configure(page);
 page.pending.shift().resolve(response([{...work,thumbnail_storage_path:'owner/cover.png',likes_count:8}]));await settle();
 const card=realCards(page)[0],author=card.children[1].children[1],picture=card.children[0].children[0],image=picture.children[0];
 assert.equal(card.children[0].children[1].textContent,work.title);
 assert.match(image.src,/owner\/cover.png$/);assert.equal(picture.dataset.mediaState,'loading');
 assert.equal(card.children[1].children[2].children[1].textContent,'8');
 assert.equal(author.textContent,'');assert.equal(author.attributes['aria-busy'],'true');assert(author.classList.contains('is-loading'));
 assert.equal(page.grid.attributes['aria-busy'],'false');assert.equal(page.more.disabled,false);
 const request=page.pending.shift();assert.match(request.url,/community_author_profiles/);
 request.resolve(response([{id:work.user_id,display_name:'真实作者'}]));await settle();
 assert.equal(realCards(page)[0],card);assert.equal(card.children[1].children[1],author);assert.equal(author.textContent,'真实作者');assert.equal(author.attributes['aria-busy'],'false');assert(!author.classList.contains('is-loading'));
});

test('failed author lookup retains works and exposes a local retry without failing the feed',async()=>{
 const page=boot();await configure(page);page.pending.shift().resolve(response([work]));await settle();
 const card=realCards(page)[0],author=card.children[1].children[1];
 page.pending.shift().reject(Error('authors offline'));await settle();
 assert.equal(realCards(page)[0],card);assert.equal(page.grid.attributes['aria-busy'],'false');assert.equal(page.more.textContent,data.t('siteLoadMore'));assert.equal(page.status.textContent,data.t('siteFeedHint'));
 assert.equal(author.children[0].textContent,data.t('siteAuthorUnavailable'));assert(!author.classList.contains('is-loading'));
 author.children[1].listeners.get('click')();await settle();assert.equal(author.attributes['aria-busy'],'true');
 page.pending.shift().resolve(response([{id:work.user_id,display_name:'恢复后的真实作者'}]));await settle();
 assert.equal(realCards(page)[0],card);assert.equal(author.textContent,'恢复后的真实作者');
});

test('pagination advances while author request is pending and binds one shared lookup to actual user IDs',async()=>{
 const page=boot();await configure(page);
 const first=Array.from({length:12},(_,i)=>({...work,id:work.id.slice(0,-3)+String(i).padStart(3,'0')}));
 page.pending.shift().resolve(response(first));await settle();const authorsRequest=page.pending.shift();
 const next=page.more.listeners.get('click')();const worksRequest=page.pending.shift();assert.equal(new URL(worksRequest.url).searchParams.has('or'),true);
 worksRequest.resolve(response([{...work,id:'22345678-1234-4234-8234-123456789abc'}]));await next;
 assert.equal(realCards(page).length,13);assert.equal(page.pending.length,0,'same user shares the still pending author query');
 authorsRequest.resolve(response([{id:'92345678-1234-4234-8234-123456789abd',display_name:'不相关账号'},{id:work.user_id,display_name:'正确账号'}]));await settle();
 for(const card of realCards(page))assert.equal(card.children[1].children[1].textContent,'正确账号');
});

test('an absent profile never fabricates an author identity or accepts unrelated profiles',async()=>{
 const page=boot();await configure(page);page.pending.shift().resolve(response([work]));await settle();
 page.pending.shift().resolve(response([{id:'92345678-1234-4234-8234-123456789abd',display_name:'别人的账号'}]));await settle();
 const author=realCards(page)[0].children[1].children[1];assert.equal(author.children[0].textContent,data.t('siteAuthorUnavailable'));assert.equal(author.textContent,'');assert(!author.classList.contains('is-loading'));
});


test('out-of-order author batches hydrate only cards belonging to each returned user',async()=>{
 const page=boot();await configure(page);page.pending.shift().resolve(response([work]));await settle();const firstAuthors=page.pending.shift();
 const other={...work,id:'22345678-1234-4234-8234-123456789abc',user_id:'22345678-1234-4234-8234-123456789abd'};
 const next=page.more.listeners.get('click')();page.pending.shift().resolve(response([other]));await next;await settle();const secondAuthors=page.pending.shift();
 secondAuthors.resolve(response([{id:other.user_id,display_name:'第二位真实作者'}]));await settle();
 assert.equal(realCards(page)[1].children[1].children[1].textContent,'第二位真实作者');assert.equal(realCards(page)[0].children[1].children[1].attributes['aria-busy'],'true');
 firstAuthors.resolve(response([{id:work.user_id,display_name:'第一位真实作者'}]));await settle();
 assert.equal(realCards(page)[0].children[1].children[1].textContent,'第一位真实作者');assert.equal(realCards(page)[1].children[1].children[1].textContent,'第二位真实作者');
});
