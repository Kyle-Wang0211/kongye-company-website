import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
class Element {
 children=[];dataset={};style={};attrs={};textContent='';
 append(...nodes){for(const node of nodes){node.parent=this;this.children.push(node);}}
 replaceChildren(...nodes){this.children=[];this.append(...nodes);}
 setAttribute(k,v){this.attrs[k]=v;}
 addEventListener(){}
 querySelector(s){return this.children.find(n=>'.'+n.className===s)||null;}
 remove(){if(this.parent)this.parent.children=this.parent.children.filter(n=>n!==this);}
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));
async function boot(id='11111111-1111-4111-8111-111111111111',origin='https://api.kongye.space'){
 const nav=new Element(),summary=new Element(),actions=new Element();let callback,clientOptions,calls=0;
 const source=readFileSync(new URL('../docs/community-account.mjs',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
 const client={auth:{getSession:async()=>({data:{session:id?{user:{id}}:null}}),onAuthStateChange:fn=>callback=fn},functions:{invoke:async()=>({error:Error('avatar unavailable')})}};
 vm.runInNewContext(source,{Map,JSON,Date,Promise,AbortSignal,setTimeout:fn=>{queueMicrotask(fn);return 1;},localeReady:Promise.resolve(),localizeElement:(node,key)=>node.textContent=key,readAccount:async()=>id?{id,name:'member'}:null,avatarDataUrl:async()=>null,fetch:async()=>({ok:true,json:async()=>({origin,anonKey:'public-test'})}),document:{querySelector:s=>({'#account-nav':nav,'#account-summary':summary,'#account-actions':actions})[s],createElement:()=>new Element()},sessionStorage:{getItem:()=>null,setItem(){},removeItem(){}},window:{addEventListener(){}},globalThis:{supabase:{createClient:(url,key,options)=>{calls++;clientOptions={url,key,...options};return client;}}}});
 await settle();await settle();return {nav,summary,actions,clientOptions,calls,signOut:async()=>{id=null;callback('SIGNED_OUT',null);await settle();}};
}
test('new-project member sees + linking into existing GLB publication flow',async()=>{const page=await boot();assert.equal(page.nav.children.length,1);assert.equal(page.nav.children[0].textContent,'+');assert.equal(page.nav.children[0].href,'community/?publish=1');assert.equal(page.clientOptions.auth.storageKey,'sb-api-rds20261104-auth-token');});
test('guest and sign-out remove publication entry',async()=>{const guest=await boot(null);assert.equal(guest.nav.children.length,0);const page=await boot();await page.signOut();assert.equal(page.nav.children.length,0);});
test('other project config cannot create an SDK client',async()=>{const page=await boot(null,'https://unapproved.example');assert.equal(page.calls,0);});
