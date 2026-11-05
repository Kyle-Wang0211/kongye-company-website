import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

class Element {
 children=[];dataset={};style={};attributes={};listeners=new Map();
 append(...nodes){for(const node of nodes){node.parent=this;this.children.push(node);}}
 replaceChildren(...nodes){this.children=[];this.append(...nodes);}
 setAttribute(k,v){this.attributes[k]=v;}
 removeAttribute(k){delete this.attributes[k];}
 addEventListener(k,v){this.listeners.set(k,v);}
 remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);}
 querySelector(selector){return this.children.find(x=>selector==='[data-logout-retry]'?x.dataset.logoutRetry:selector.startsWith('.')?x.className===selector.slice(1):x.tag===selector)||null;}
}
function boot(action){
 const nav=new Element(),summary=new Element(),actions=new Element();
 const elements={'#account-nav':nav,'#account-summary':summary,'#account-actions':actions};
 const storage=new Map();
 const source=readFileSync(new URL('../docs/community-account.mjs',import.meta.url),'utf8')
  .replace(/^import .*;\n/gm,'').replace('void start().catch(retry);','')+
  '\nglobalThis.hooks={render,owner:()=>displayedId,setClient:value=>client=value};';
 const context={document:{querySelector:s=>elements[s],createElement:tag=>Object.assign(new Element(),{tag})},
  localizeElement:(node,key)=>{node.dataset.i18n=key;node.textContent=key;},localeReady:Promise.resolve(),
  sessionStorage:{removeItem:k=>storage.delete(k)},setTimeout:()=>1};
 vm.runInNewContext(source,context);
 context.hooks.setClient({auth:{signOut:action}});
 const render=id=>{context.hooks.render({id,name:'Name '+id});return actions.children.find(x=>x.dataset.i18n==='meSignOut');};
 return {actions,hooks:context.hooks,render};
}

test('member menu opens own profile and sign out requests local scope once',async()=>{
 let complete;const pending=new Promise(resolve=>complete=resolve);const calls=[];
 const page=boot(options=>{calls.push(options);return pending;});const button=page.render('actor A');
 assert.equal(page.actions.children[0].href,'community/?profile=actor%20A');
 const first=button.listeners.get('click')();await button.listeners.get('click')();
 assert.equal(calls.length,1);assert.equal(calls[0].scope,'local');assert.equal(button.disabled,true);
 complete({error:null});await first;
 assert.equal(page.hooks.owner(),null);assert(!page.actions.children.some(x=>x.dataset.i18n==='meSignOut'));
});

test('sign out failure retains authenticated presentation and allows retry',async()=>{
 const page=boot(async()=>({error:Error('offline')}));const button=page.render('actor-a');
 await button.listeners.get('click')();
 assert.equal(page.hooks.owner(),'actor-a');assert.equal(button.disabled,false);
 assert.equal(page.actions.querySelector('[data-logout-retry]').attributes.role,'alert');
});

test('late sign out result cannot replace another account presentation',async()=>{
 let complete;const page=boot(()=>new Promise(resolve=>complete=resolve));
 const button=page.render('actor-a');const pending=button.listeners.get('click')();
 page.render('actor-b');complete({error:null});await pending;
 assert.equal(page.hooks.owner(),'actor-b');
 assert.equal(page.actions.children[0].href,'community/?profile=actor-b');
});
