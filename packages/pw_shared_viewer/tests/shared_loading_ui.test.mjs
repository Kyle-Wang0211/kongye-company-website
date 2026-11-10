import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../web/index.html', import.meta.url), 'utf8');
function fixture() {
  const elements = new Map();
  for (const id of ['viewer', 'status', 'download', 'download-value', 'download-number']) {
    const classes = new Set(id === 'download' ?
      (html.match(/<div id="download"[^>]*class="([^"]*)"/)?.[1] ?? '').split(' ').filter(Boolean) : []);
    elements.set(`#${id}`, {hidden:false, textContent:id === 'download-number' ?
      html.match(/<span id="download-number">([^<]*)<\/span>/)[1] : '',
      style:{}, setAttribute(){}, classList:{toggle(name, enabled){ enabled ? classes.add(name) : classes.delete(name); }, contains:name=>classes.has(name)}});
  }
  const window = {location:{origin:'https://viewer.example'},addEventListener(){},dispatchEvent(){}};
  window.parent=window;
  let rejectReady;
  const context=vm.createContext({window, document:{querySelector:id=>elements.get(id),documentElement:{}},
    verifyLocalBundle:()=>new Promise((_,reject)=>{rejectReady=reject;}),installHostBridge(){},CustomEvent:class{},URLSearchParams,
    location:{search:''}});
  const script=html.match(/<script type="module">([\s\S]*?)<\/script>/)[1].replace(/^\s*import .*;$/gm,'');
  vm.runInContext(script,context);
  return {elements,context,progress:window.pwSharedViewerDownloadProgress,
    initializationFailed:async()=>{rejectReady(new Error('initialization failed'));await window.pwSharedViewerReady.catch(()=>{});},
    state:value=>vm.runInContext(`stateChanged(${JSON.stringify(value)})`,context)};
}

test('shared iframe starts with indeterminate ring and no unmeasured percentage',()=>{
  assert.match(html, /id="download-number"><\/span>/);
  assert.doesNotMatch(html, /正在初始化|正在加载/);
  const f=fixture();
  assert.equal(f.elements.get('#download').hidden,false);
  assert.equal(f.elements.get('#download-number').textContent,'');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),true);
});

test('actual byte progress survives decoding and only ready/error removes ring',()=>{
  const f=fixture();
  f.progress({receivedBytes:3,totalBytes:8});
  assert.equal(f.elements.get('#download-number').textContent,'37%');
  f.progress({receivedBytes:8,totalBytes:8});
  f.state({status:'loading'});
  assert.equal(f.elements.get('#download-number').textContent,'100%');
  assert.equal(f.elements.get('#download').hidden,false);
  f.state({status:'ready'});
  assert.equal(f.elements.get('#download').hidden,true);
  f.state({status:'loading'});
  assert.equal(f.elements.get('#download-number').textContent,'');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),true);
  f.progress({receivedBytes:8,totalBytes:8});
  assert.equal(f.elements.get('#download-number').textContent,'100%');
  f.state({status:'error'});
  assert.equal(f.elements.get('#download').hidden,true);
});

test('unknown total shows honest indeterminate ring',()=>{
  const f=fixture();f.progress({receivedBytes:300,totalBytes:null});
  assert.equal(f.elements.get('#download-number').textContent,'—');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),true);
});

for (const terminal of [{status:'ready'}, {status:'error'}, {status:'disposed',disposed:true}]) {
  test(`late progress after ${terminal.status} cannot cover the completed scene`,()=>{
    const f=fixture();
    f.state({status:'loading'});
    f.progress({receivedBytes:8,totalBytes:8});
    f.state(terminal);
    assert.equal(f.elements.get('#download').hidden,true);
    for (const progress of [{receivedBytes:0,totalBytes:1},
      {receivedBytes:300,totalBytes:null}, {receivedBytes:8,totalBytes:8}]) {
      f.progress(progress);
      assert.equal(f.elements.get('#download').hidden,true);
      assert.equal(f.elements.get('#download-number').textContent,'100%');
    }
  });
}

test('explicit next loading reopens progress after ready or error without accepting terminal late events',()=>{
  const f=fixture();
  for (const terminal of [{status:'ready'},{status:'error'}]) {
    f.progress({receivedBytes:3,totalBytes:8});
    f.state(terminal);
    f.progress({receivedBytes:0,totalBytes:1});
    f.state({status:'loading'});
    assert.equal(f.elements.get('#download').hidden,false);
    assert.equal(f.elements.get('#download-number').textContent,'');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),true);
    f.progress({receivedBytes:2,totalBytes:8});
    assert.equal(f.elements.get('#download-number').textContent,'25%');
    f.progress({receivedBytes:7,totalBytes:8});
    assert.equal(f.elements.get('#download-number').textContent,'87%');
  }
});

test('late host progress cannot reopen initialization failure',async()=>{
  const f=fixture();
  await f.initializationFailed();
  assert.equal(f.elements.get('#download').hidden,true);
  f.progress({receivedBytes:0,totalBytes:1});
  assert.equal(f.elements.get('#download').hidden,true);
});

test('zero without a denominator stays blank until real byte denominator arrives',()=>{
  const f=fixture();
  f.progress({receivedBytes:0,totalBytes:null});
  assert.equal(f.elements.get('#download-number').textContent,'');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),true);
  f.progress({receivedBytes:0,totalBytes:8});
  assert.equal(f.elements.get('#download-number').textContent,'0%');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),false);
  f.progress({receivedBytes:2,totalBytes:8});
  assert.equal(f.elements.get('#download-number').textContent,'25%');
});
