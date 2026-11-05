import test from 'node:test';
import assert from 'node:assert/strict';
import { createHostBridge, installHostBridge } from '../web/host_bridge.mjs';

test('host bridge waits for official viewer readiness and returns correlated responses', async () => {
  let ready; const sent = [], calls = [];
  const bridge = createHostBridge({ ready: new Promise(resolve => { ready = resolve; }), send: value => sent.push(value) });
  const response = bridge.request({ id: 'job-1', method: 'load', args: {url: '/model.glb', format: 'glb'} });
  await Promise.resolve(); assert.equal(calls.length, 0);
  ready({ load: async args => { calls.push(args); return {status:'loaded'}; } });
  assert.deepEqual(await response, {protocol:'PW_SHARED_VIEWER_V1',id:'job-1',ok:true,result:{status:'loaded'}});
  assert.deepEqual(calls, [{url:'/model.glb',format:'glb'}]); assert.equal(sent.length, 1);
});

test('unknown methods and missing request identities never invoke the viewer', async () => {
  let called = 0;
  const viewer = { getState() { called++; } };
  Object.defineProperty(viewer, 'constructor', {get() { called++; throw new Error('must not access'); }});
  const bridge = createHostBridge({ready:Promise.resolve(viewer),send:()=>{}});
  assert.equal((await bridge.request({id:'x',method:'constructor'})).ok,false);
  assert.equal((await bridge.request({method:'getState'})).ok,false);
  assert.equal(called,0);
});

test('viewer failures return structured errors without losing the correlation id', async () => {
  const bridge = createHostBridge({ready:Promise.resolve({load:async()=>{throw new Error('invalid model');}}),send:()=>{}});
  const response = await bridge.request({id:'bad-model',method:'load',args:{url:'/bad.glb',format:'glb'}});
  assert.equal(response.id,'bad-model'); assert.equal(response.ok,false); assert.equal(response.error.message,'invalid model');
});

test('lifecycle methods keep typed argument mapping', async () => {
  const calls = [];
  const viewer = {resize:(...args)=>calls.push(['resize',...args]),capture:(...args)=>calls.push(['capture',...args]),pause:()=>calls.push(['pause'])};
  const bridge = createHostBridge({ready:Promise.resolve(viewer),send:()=>{}});
  await bridge.request({id:'1',method:'resize',args:{width:390,height:844,pixelRatio:2}});
  await bridge.request({id:'2',method:'capture',args:{type:'image/jpeg',quality:0.8}});
  await bridge.request({id:'3',method:'pause'});
  assert.deepEqual(calls,[['resize',390,844,2],['capture','image/jpeg',0.8],['pause']]);
});

test('iframe messages require the exact parent and origin', async () => {
  const listeners = new Map(), sent = [];
  const parent = {postMessage:packet => sent.push(packet)};
  const viewer = {getState:() => ({status:'ready'}), pause:() => 'paused'};
  const hostWindow = {
    parent,location:{origin:'https://viewer.example'},pwSharedViewerReady:Promise.resolve(viewer),
    addEventListener:(name,fn) => listeners.set(name,fn),
    removeEventListener:(name,fn) => { if (listeners.get(name)===fn) listeners.delete(name); },
  };
  installHostBridge(hostWindow); await Promise.resolve();
  const request = {type:'pw-shared-request',request:{id:'pause-1',method:'pause'}};
  listeners.get('message')({source:parent,origin:'https://other.example',data:request});
  listeners.get('message')({source:{},origin:'https://viewer.example',data:request});
  await Promise.resolve(); assert.equal(sent.filter(x => x.id==='pause-1').length,0);
  listeners.get('message')({source:parent,origin:'https://viewer.example',data:request});
  await Promise.resolve(); await Promise.resolve();
  assert.equal(sent.find(x => x.id==='pause-1')?.result,'paused');
  listeners.get('pagehide')({persisted:false}); assert.equal(listeners.has('message'),false);
});

// Real native transport must be ready even when ES modules start after the
// navigation delegate finished. No host-side evaluation kick is required.
test('native channel emits readiness after delayed module initialization', async () => {
  let resolveReady;
  const sent = [], listeners = new Map();
  const host = {PWSharedHost:{postMessage:s=>sent.push(JSON.parse(s))},
    pwSharedViewerReady:new Promise(resolve=>{resolveReady=resolve;}),
    addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:()=>{}};
  installHostBridge(host);
  await Promise.resolve(); assert.equal(sent.length,0);
  resolveReady({getState:()=>({status:'empty'})});
  await Promise.resolve(); await Promise.resolve();
  assert.equal(sent.length,1);
  assert.equal(sent[0].type,'pw-viewer-ready');
  assert.equal(sent[0].state.status,'empty');
});


test('download UI accepts observed byte progress before renderer readiness',async()=>{
 const events=[],sent=[];
 const bridge=createHostBridge({ready:new Promise(()=>{}),send:p=>sent.push(p),onDownloadProgress:p=>events.push(p)});
 assert.equal((await bridge.request({id:'progress',method:'setDownloadProgress',args:{receivedBytes:2,totalBytes:8}})).ok,true);
 assert.deepEqual(events,[{receivedBytes:2,totalBytes:8}]);
 assert.equal((await bridge.request({id:'invalid',method:'setDownloadProgress',args:{receivedBytes:-1,totalBytes:8}})).ok,false);
 assert.equal(events.length,1);
});

test('official loader progress is correlated with its original load request',async()=>{
 const sent=[];
 const bridge=createHostBridge({ready:Promise.resolve({load:async(args,progress)=>{
   assert.equal(args.url,'https://assets.example/models/scene.glb');
   progress({receivedBytes:3,totalBytes:8});return {status:'loaded'};
 }}),send:p=>sent.push(p)});
 await bridge.request({id:'model-A',method:'load',args:{url:'https://assets.example/models/scene.glb',format:'glb'}});
 assert.deepEqual(sent[0],{protocol:'PW_SHARED_VIEWER_V1',type:'pw-viewer-download-progress',id:'model-A',receivedBytes:3,totalBytes:8});
});
