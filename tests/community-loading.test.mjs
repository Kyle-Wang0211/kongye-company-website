import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import * as data from '../docs/community-data.mjs';
import {legacyWorkIds,workCovers} from '../docs/community-work-links.mjs';

class Element {
  children=[]; dataset={}; listeners=new Map(); attributes={}; textContent='';
  append(...nodes){this.children.push(...nodes);}
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
function boot(search=''){
 const grid=new Element(),status=new Element(),more=new Element(),dialog=new Element();dialog.parts={iframe:new Element(),h2:new Element(),button:new Element()};
 const elements={'#community-grid':grid,'#feed-status':status,'#feed-more':more,'#work-dialog':dialog,'#share-work':new Element(),'#share-status':new Element(),'#work-meta':new Element()};
 const pending=[];
 const fetch=(url,options)=>{const gate=defer();pending.push({url:String(url),options,...gate});return gate.promise;};
 const source=readFileSync(new URL('../docs/community-feed.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
 vm.runInNewContext(source,{...data,legacyWorkIds,workCovers,document:{querySelector:s=>elements[s],createElement:()=>new Element()},fetch,URL,AbortSignal,location:{href:'https://kongye.space/'+search},navigator:{},window:{addEventListener(){}}});
 return {grid,status,more,pending,dialog,elements};
}
async function configure(page){page.pending.shift().resolve(response({origin:'https://api.kongye.space',anonKey:'public'}));await settle();}
async function completeFeed(page,rows=[work]){page.pending.shift().resolve(response(rows));await settle();if(rows.length){page.pending.shift().resolve(response([{id:work.user_id,display_name:'窗后城'}]));await settle();}}

test('refresh waits for real feed and authors without flashing local-only cards',async()=>{
 const page=boot();assert.equal(page.grid.children.length,0,'no local-only version while config loads');
 await configure(page);assert.equal(page.grid.children.length,0,'no local-only version while feed loads');
 page.pending.shift().resolve(response([work]));await settle();assert.equal(page.grid.children.length,0,'wait for real authors');
 page.pending.shift().resolve(response([{id:work.user_id,display_name:'窗后城'}]));await settle();
 assert.equal(page.grid.children.length,1);assert(!page.grid.children.some(x=>x.dataset.example));
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


test('legacy links and new shares resolve to the same real work identity',async()=>{
 const slug=Object.keys(legacyWorkIds)[0];assert(slug);
 const page=boot('?example='+slug);await configure(page);await completeFeed(page,[]);
 const lookup=page.pending.shift();assert.equal(new URL(lookup.url).searchParams.get('id'),'eq.'+legacyWorkIds[slug]);
 lookup.resolve(response([{...work,id:legacyWorkIds[slug]}]));await settle();
 page.pending.shift().resolve(response([{id:work.user_id,display_name:'窗后城'}]));await settle();
 assert.equal(page.dialog.open,true);assert(page.dialog.parts.iframe.src.includes('model='));
 await page.elements['#share-work'].listeners.get('click')();
 const shared=new URL(page.elements['#share-status'].textContent);assert.equal(shared.searchParams.get('work'),legacyWorkIds[slug]);assert(!shared.searchParams.has('example'));
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
 page.pending.shift().resolve(response([{id:work.user_id,display_name:'林远'}]));await retry;
 assert.equal(page.dialog.open,true);
});
