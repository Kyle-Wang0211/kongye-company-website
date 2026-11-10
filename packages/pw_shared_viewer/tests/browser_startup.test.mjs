import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const website = new URL('../../../../../docs/community/assets/packages/pw_shared_viewer/web/',import.meta.url);
const html = fs.readFileSync(new URL('index.html',website),'utf8');

test('website HTML initializes through release manifest only with explicit evidence scope',async()=>{
  const manifest = JSON.parse(fs.readFileSync(new URL('BUNDLE_MANIFEST.json',website)));
  const elements=new Map();
  for(const id of ['viewer','status','download','download-value','download-number']) {
    elements.set(`#${id}`,{setAttribute(){},classList:{toggle(){}},style:{}});
  }
  let reads=0,options;
  const controller={getState:()=>({disposed:false}),resize(){}};
  const window={location:{origin:'https://example.test'},addEventListener(){},dispatchEvent(){}};
  window.parent=window;
  const context=vm.createContext({window,document:{querySelector:id=>elements.get(id),documentElement:{},addEventListener(){}},
    readReleaseIdentity:async()=>{reads++;return manifest.bundle_sha256;},
    verifyLocalBundle:()=>{throw new Error('Full runtime audit must not run for website');},
    create:async(canvas,value)=>{options=value;return controller;},installHostBridge(){},CustomEvent:class{},URLSearchParams,location:{search:''}});
  vm.runInContext(html.match(/<script type="module">([\s\S]*?)<\/script>/)[1].replace(/^\s*import .*;$/gm,''),context);
  await window.pwSharedViewerReady;
  assert.equal(reads,1);
  assert.equal(options.bundleIdentity,manifest.bundle_sha256);
  assert.equal(options.bundleIdentityScope,'release-manifest');
  assert.equal(options.runtimeBundleBytesVerified,false);
});
