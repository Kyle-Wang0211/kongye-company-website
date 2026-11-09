import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {readAccount} from '../docs/community-account-data.mjs';

function boot(options={}) {
  const elements = new Map(), timers = new Map();
  let timerId = 0;
  class Element {
    children = []; dataset = {}; attributes = {}; style = {}; listeners = new Map();
    open = false;
    constructor(tag = 'span') { this.tag = tag; }
    append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    replaceWith(node) { const parent = this.parent; node.parent = parent; parent.children[parent.children.indexOf(this)] = node; }
    remove() { if (this.parent) this.parent.children = this.parent.children.filter(node => node !== this); }
    setAttribute(key, value) { this.attributes[key] = value; }
    getAttribute(key) { return key === 'src' ? this.src : this.attributes[key]; }
    removeAttribute(key) { delete this.attributes[key]; }
    querySelector(selector) {
      const matches = node => selector.startsWith('.') ? node.className?.split(' ').includes(selector.slice(1)) : node.tag === selector;
      for (const child of this.children) { if (matches(child)) return child; const nested = child.querySelector(selector); if (nested) return nested; }
      return null;
    }
    querySelectorAll(selector) { const nodes = []; for (const child of this.children) { if (selector === 'a, button' && ['a', 'button'].includes(child.tag)) nodes.push(child); nodes.push(...child.querySelectorAll(selector)); } return nodes; }
    contains(node) { return node === this || this.children.some(child => child.contains(node)); }
    addEventListener(name, listener) { const rows = this.listeners.get(name) || []; rows.push(listener); this.listeners.set(name, rows); }
    emit(name, values = {}) { const event = {target:this, preventDefault(){this.prevented=true;}, ...values}; for (const listener of this.listeners.get(name) || []) listener(event); return event; }
    focus() { document.activeElement = this; }
  }
  const document = new Element('document');
  document.createElement = tag => new Element(tag);
  document.querySelector = selector => elements.get(selector) || null;
  for (const id of ['account-nav','account-summary','account-actions','account-menu','my-profile-link']) elements.set('#'+id, new Element(id === 'account-menu' ? 'details' : 'div'));
  const menu = elements.get('#account-menu'); menu.append(elements.get('#account-summary'), elements.get('#account-actions'));
  const window = new Element('window');
  const storage = options.storage||new Map(), persistent=options.persistent||new Map();
  const source = readFileSync(new URL('../docs/community-account.mjs', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace(/^export /gm, '')
    .replace('const accountClientReady=start();\nvoid accountClientReady.catch(retry);','') +
    '\nglobalThis.hooks={render,guest,refresh,start,retry,owner:()=>displayedId,setClient:value=>client=value};';
  const localizeElement = (node,key) => { node.dataset.i18n=key; node.textContent=key; };
  const context = {document,window,localizeElement,localeReady:Promise.resolve(),localeEvent:'pw:localechange',
    sessionStorage:{getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},
    localStorage:{getItem:key=>persistent.get(key),setItem:(key,value)=>persistent.set(key,value),removeItem:key=>persistent.delete(key)},
    fetch:options.fetch, supabase:options.supabase,AbortSignal,location:{assign(){}},
    setTimeout:callback=>{timers.set(++timerId,callback);return timerId;},clearTimeout:id=>timers.delete(id),
    readAccount:options.readAccount||async function(){throw Error('offline');}, avatarDataUrl:async()=>null};
  vm.runInNewContext(source,context);
  return {document,window,menu,storage,persistent,context,get:id=>elements.get('#'+id),hooks:context.hooks,
    flush(){for(const [id,callback] of [...timers]){timers.delete(id);callback();}}};
}
const settle = () => new Promise(resolve=>setImmediate(resolve));
const account = {id:'actor-a',name:'Real name',following_count:7,followers_count:12};
function connect(page,rpc) {
  const session = {user:{id:account.id}};
  page.hooks.setClient({auth:{getSession:async()=>({data:{session}})},rpc});
  return session;
}
test('member card reuses profile and avatar presentation and links to three account lists',()=>{
  const page=boot();page.hooks.render(account,'data:image/png;base64,same');
  const actions=page.get('account-actions');
  assert.equal(actions.children[0].href,'community/?profile=actor-a');
  assert.equal(actions.querySelector('.account-card-name').textContent,'Real name');
  assert.equal(actions.querySelector('img').src,'data:image/png;base64,same');
  assert.equal(actions.querySelector('.account-following-count').textContent,'7');
  assert.equal(actions.querySelector('.account-followers-count').textContent,'12');
  assert.deepEqual(actions.children.filter(node=>node.className==='account-library-link').map(node=>node.href),
    ['community/#/likes','community/#/favorites','community/#/history']);
});
test('mouse hover opens immediately and delayed pointer leave permits travel into the panel',()=>{
  const page=boot();page.hooks.render(account);
  page.menu.emit('pointerenter',{pointerType:'mouse'});assert.equal(page.menu.open,true);
  page.menu.emit('pointerleave');page.menu.emit('pointerenter',{pointerType:'mouse'});page.flush();
  assert.equal(page.menu.open,true);
  page.menu.emit('pointerleave');page.flush();assert.equal(page.menu.open,false);
  page.menu.emit('pointerenter',{pointerType:'touch'});assert.equal(page.menu.open,false);
});
test('keyboard focus opens the menu and Escape closes it with focus returned',()=>{
  const page=boot();page.hooks.render(account);
  page.menu.emit('focusin');assert.equal(page.menu.open,true);
  page.get('account-summary').emit('keydown',{key:'ArrowDown'});
  assert.equal(page.document.activeElement,page.get('account-actions').children[0]);
  page.document.emit('keydown',{key:'Escape'});assert.equal(page.menu.open,false);
  assert.equal(page.document.activeElement,page.get('account-summary'));
});
test('library counts are lazy, single-flight, cached, and render true zero',async()=>{
  const page=boot();let resolve,calls=0;
  connect(page,()=>{calls++;return new Promise(done=>resolve=done);});page.hooks.render(account);
  assert.equal(calls,0);
  page.menu.emit('pointerenter',{pointerType:'mouse'});page.menu.emit('pointerenter',{pointerType:'mouse'});await settle();
  assert.equal(calls,1);assert.equal(page.get('account-actions').querySelector('.account-likes-count').textContent,'—');
  resolve({data:{likes_count:0,favorites_count:3,history_count:9},error:null});await settle();
  assert.equal(page.get('account-actions').querySelector('.account-likes-count').textContent,'0');
  assert.equal(page.get('account-actions').querySelector('.account-favorites-count').textContent,'3');
  page.menu.emit('pointerenter',{pointerType:'mouse'});await settle();assert.equal(calls,1);
});
test('late count responses cannot populate another account, and failures remain unknown',async()=>{
  const page=boot();let resolve;
  const session=connect(page,()=>new Promise(done=>resolve=done));page.hooks.render(account);
  page.menu.emit('pointerenter',{pointerType:'mouse'});await settle();
  session.user.id='actor-b';page.hooks.render({id:'actor-b',name:'B'});
  resolve({data:{likes_count:99,favorites_count:99,history_count:99},error:null});await settle();
  assert.equal(page.get('account-actions').querySelector('.account-likes-count').textContent,'—');
  assert.equal(page.get('account-actions').querySelector('.account-followers-count').textContent,'—');
});
test('guest menu retains sign in and register and starts no library requests',()=>{
  const page=boot();page.hooks.guest();page.menu.emit('pointerenter',{pointerType:'mouse'});
  assert.deepEqual(page.get('account-actions').children.map(node=>node.href),['community/?auth=signin','community/?auth=signup']);
});
test('readAccount retains measured following and follower counts and uses unknown for missing values',async()=>{
  const client={auth:{getSession:async()=>({data:{session:{user:{id:'a'}}}}),getUser:async()=>({data:{user:{id:'a',user_metadata:{}}}})},
    rpc:async()=>({data:[{display_name:'Alice',following_count:0,followers_count:4}]})};
  const row=await readAccount(client);assert.equal(row.following_count,0);assert.equal(row.followers_count,4);
  client.rpc=async()=>({data:[{display_name:'Alice',following_count:-1}]});
  const unknown=await readAccount(client);assert.equal(unknown.following_count,null);assert.equal(unknown.followers_count,null);
});

test('same-account refresh keeps both decoded avatars and existing menu nodes',()=>{
  const page=boot();page.hooks.render(account,'data:image/png;base64,same');
  const headerAvatar=page.get('account-summary').querySelector('img');
  const profile=page.get('account-actions').children[0],menuAvatar=profile.querySelector('img');
  page.hooks.render({...account,name:'Updated name'});
  assert.equal(page.get('account-summary').querySelector('img'),headerAvatar);
  assert.equal(page.get('account-actions').children[0],profile);
  assert.equal(profile.querySelector('img'),menuAvatar);
  assert.equal(profile.querySelector('.account-card-name').textContent,'Updated name');
});
test('valid presentation cache stays visible during failed canonical transport',async()=>{
  const page=boot();connect(page,async()=>({data:null}));
  page.storage.set('pw-current-account-presentation-rds-v1',JSON.stringify({account,until:Date.now()+299000}));
  await page.hooks.refresh();
  const profile=page.get('account-actions').children[0];
  assert.equal(profile.querySelector('.account-card-name').textContent,account.name);
  await page.hooks.refresh();assert.equal(page.get('account-actions').children[0],profile);
});
test('native details toggle supports tap and count failure retries on reopening',async()=>{
  const page=boot();let calls=0;
  connect(page,async()=>{calls++;return calls===1?{error:Error('offline')}:{data:{likes_count:1,favorites_count:2,history_count:3}};});
  page.hooks.render(account);
  page.menu.open=true;page.menu.emit('toggle');await settle();
  assert.equal(page.get('account-summary').attributes['aria-expanded'],'true');
  assert.equal(page.get('account-actions').querySelector('.account-likes-count').textContent,'—');
  page.menu.open=false;page.menu.emit('toggle');page.menu.open=true;page.menu.emit('toggle');await settle();
  assert.equal(calls,2);assert.equal(page.get('account-actions').querySelector('.account-likes-count').textContent,'1');
});
test('session switch while RPC is pending discards the response even before another render',async()=>{
  const page=boot();let resolve;
  const session=connect(page,()=>new Promise(done=>resolve=done));page.hooks.render(account);
  page.menu.open=true;page.menu.emit('toggle');await settle();session.user.id='actor-b';
  resolve({data:{likes_count:55,favorites_count:55,history_count:55}});await settle();
  assert.equal(page.get('account-actions').querySelector('.account-likes-count').textContent,'—');
});

const cacheKey='pw-current-account-presentation-rds-v1';
const defer=()=>{let resolve;const promise=new Promise(done=>resolve=done);return {promise,resolve};};
const sessionFor=id=>({data:{session:id?{user:{id,user_metadata:{display_name:'Session '+id}}}:null}});
function sdk(page,id,read=()=>sessionFor(id)) {
  page.hooks.setClient({auth:{getSession:async()=>read()},functions:{invoke:async()=>({error:Error('avatar offline')})}});
}

test('SDK restoration is neutral and cannot open a false login path',async()=>{
  const pending=defer(),page=boot();
  sdk(page,account.id,()=>pending.promise);
  const request=page.hooks.refresh();await settle();
  assert.equal(page.get('account-actions').children.length,0);
  assert.equal(page.get('account-summary').emit('click').prevented,true);
  assert.equal(page.get('my-profile-link').emit('click').prevented,true);
  pending.resolve(sessionFor(account.id));await request;
  assert.equal(page.hooks.owner(),account.id);
  assert.equal(page.get('account-summary').querySelector('.community-account-name').textContent,'Session '+account.id);
  assert(!page.get('account-actions').children.some(node=>node.href==='community/?auth=signin'));
});

test('same-owner persistent presentation appears before delayed server revalidation and updates canonically',async()=>{
  const pending=defer();let calls=0;
  const page=boot({readAccount:()=>{calls++;return pending.promise;}});
  page.persistent.set(cacheKey,JSON.stringify({account,until:Date.now()+60000}));
  sdk(page,account.id);
  const request=page.hooks.refresh();await settle();
  assert.equal(page.hooks.owner(),account.id);
  assert.equal(page.get('account-summary').querySelector('.community-account-name').textContent,account.name);
  assert.equal(calls,1,'cache must not suppress canonical revalidation');
  pending.resolve({...account,name:'Canonical rename'});await request;
  assert.equal(page.get('account-summary').querySelector('.community-account-name').textContent,'Canonical rename');
  assert.equal(JSON.parse(page.persistent.get(cacheKey)).account.name,'Canonical rename');
});

test('closing and reopening keeps presentation only when official SDK restores its owner',async()=>{
  const persistent=new Map();
  const first=boot({persistent,readAccount:async()=>account});sdk(first,account.id);await first.hooks.refresh();
  assert(persistent.has(cacheKey));
  const next=boot({persistent});sdk(next,account.id);await next.hooks.refresh();
  assert.equal(next.get('account-summary').querySelector('.community-account-name').textContent,account.name);
  const signedOut=boot({persistent});sdk(signedOut,null);await signedOut.hooks.refresh();
  assert.equal(signedOut.hooks.owner(),null);
  assert.equal(persistent.has(cacheKey),false,'presentation never creates a session');
});

test('a cached different owner is never presented and revoked verification clears both stores',async()=>{
  const page=boot({readAccount:async()=>null});
  const saved=JSON.stringify({account,until:Date.now()+60000});page.storage.set(cacheKey,saved);page.persistent.set(cacheKey,saved);
  const pending=defer();page.context.readAccount=()=>pending.promise;sdk(page,'actor-b');
  const request=page.hooks.refresh();await settle();
  assert.equal(page.hooks.owner(),'actor-b');
  assert.equal(page.get('account-summary').querySelector('.community-account-name').textContent,'Session actor-b');
  pending.resolve(null);await request;
  assert.equal(page.hooks.owner(),null);assert.equal(page.storage.has(cacheKey),false);assert.equal(page.persistent.has(cacheKey),false);
});

test('transient SDK read failure exposes retry without claiming signed out',async()=>{
  const page=boot();sdk(page,account.id,()=>({error:Error('restore offline')}));
  await page.hooks.refresh();
  assert(!page.get('account-actions').children.some(node=>node.href==='community/?auth=signin'));
  assert.equal(page.get('account-actions').children[0].dataset.i18n,'siteAccountRetry');
});

test('startup is single-flight and focus revalidates without blanking cached account',async()=>{
  const pending=defer();let creations=0,fetches=0,listener;
  const client={auth:{getSession:async()=>sessionFor(account.id),onAuthStateChange:fn=>listener=fn},functions:{invoke:async()=>({data:{}})}};
  const page=boot({fetch:async()=>{fetches++;return {ok:true,json:async()=>({origin:'https://api.kongye.space',anonKey:'synthetic'})};},supabase:{createClient:()=>{creations++;return client;}},readAccount:()=>pending.promise});
  page.persistent.set(cacheKey,JSON.stringify({account,until:Date.now()+60000}));
  const first=page.hooks.start(),second=page.hooks.start();await settle();
  assert.equal(creations,1);assert.equal(fetches,1);
  assert.equal(page.hooks.owner(),account.id);
  page.window.emit('focus');
  assert.equal(page.persistent.has(cacheKey),true);assert.equal(page.hooks.owner(),account.id);
  pending.resolve(account);await Promise.all([first,second]);
  listener('SIGNED_OUT',null);
  assert.equal(page.hooks.owner(),null);assert.equal(page.persistent.has(cacheKey),false);
});
