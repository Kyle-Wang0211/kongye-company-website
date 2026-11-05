import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../web/index.html', import.meta.url), 'utf8');
function fixture() {
  const elements = new Map();
  for (const id of ['viewer', 'status', 'download', 'download-value', 'download-number']) {
    const classes = new Set();
    elements.set(`#${id}`, {hidden:false, textContent:id === 'download-number' ? '0%' : '',
      style:{}, setAttribute(){}, classList:{toggle(name, enabled){ enabled ? classes.add(name) : classes.delete(name); }, contains:name=>classes.has(name)}});
  }
  const window = {location:{origin:'https://viewer.example'},addEventListener(){},dispatchEvent(){}};
  window.parent=window;
  const context=vm.createContext({window, document:{querySelector:id=>elements.get(id),documentElement:{}},
    verifyLocalBundle:()=>new Promise(()=>{}),installHostBridge(){},CustomEvent:class{},URLSearchParams,
    location:{search:''}});
  const script=html.match(/<script type="module">([\s\S]*?)<\/script>/)[1].replace(/^\s*import .*;$/gm,'');
  vm.runInContext(script,context);
  return {elements,context,progress:window.pwSharedViewerDownloadProgress,
    state:value=>vm.runInContext(`stateChanged(${JSON.stringify(value)})`,context)};
}

test('shared iframe first HTML displays centered ring and zero without phase text',()=>{
  assert.match(html, /id="download-number">0%/);
  assert.doesNotMatch(html, /正在初始化|正在加载/);
  const f=fixture();
  assert.equal(f.elements.get('#download').hidden,false);
  assert.equal(f.elements.get('#download-number').textContent,'0%');
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
  f.progress({receivedBytes:0,totalBytes:8});
  f.progress({receivedBytes:8,totalBytes:8});
  f.state({status:'loading'});
  assert.equal(f.elements.get('#download-number').textContent,'100%');
  f.state({status:'error'});
  assert.equal(f.elements.get('#download').hidden,true);
});

test('unknown total shows honest indeterminate ring',()=>{
  const f=fixture();f.progress({receivedBytes:300,totalBytes:null});
  assert.equal(f.elements.get('#download-number').textContent,'—');
  assert.equal(f.elements.get('#download').classList.contains('indeterminate'),true);
});
