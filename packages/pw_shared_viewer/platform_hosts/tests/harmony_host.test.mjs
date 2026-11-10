import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { stripTypeScriptTypes } from 'node:module';
import { stageAssets, stageHost, verifyBundle, assetDeclarations } from '../harmony/stage_assets.mjs';

// Executes the actual transport class with ArkWeb boundary stubs. This is a host
// contract test, explicitly not ArkTS compilation or an ArkWeb rendering test.
const sourceUrl = new URL('../harmony/ets/PwArkWebHost.ets', import.meta.url);
const manifest = JSON.parse(await fs.readFile(new URL('../../web/BUNDLE_MANIFEST.json', import.meta.url)));
const EXPECTED_BUNDLE = manifest.bundle_sha256;
const assetSource = assetDeclarations(manifest);
class Controller {
  scripts = [];
  deleted = [];
  fail = false;
  runJavaScript(script) { this.scripts.push(script); return this.fail ? Promise.reject(Error('script failed')) : Promise.resolve(''); }
  deleteJavaScriptRegister(name) { this.deleted.push(name); }
}
class Response {
  setResponseHeader(v) { this.headers = v; }
  setResponseCode(v) { this.code = v; }
  setReasonMessage(v) { this.reason = v; }
  setResponseMimeType(v) { this.mime = v; }
  setResponseEncoding(v) { this.encoding = v; }
  setResponseData(v) { this.body = v; }
}
globalThis.__pwArkTest = { webview: { WebviewController: Controller }, Response };
let source = await fs.readFile(sourceUrl, 'utf8');
source = source.replace("import { webview } from '@kit.ArkWeb';", 'const webview = globalThis.__pwArkTest.webview;\nconst WebResourceResponse = globalThis.__pwArkTest.Response;');
source = source.replace("import { BUNDLE_SHA256, ASSET_PATHS } from './SharedViewerAssets';", assetSource);
const { PwArkWebHost, ENTRY, ORIGIN, PROTOCOL } = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
function readyHost() {
  const host = new PwArkWebHost();
  host.pageBegin(ENTRY);
  host.postMessage(JSON.stringify({ protocol: PROTOCOL, type: 'pw-viewer-ready', state: {bundleIdentity: EXPECTED_BUNDLE} }));
  assert.equal(host.isReady(), true);
  return host;
}
function reply(host, extra = {}) {
  const script = host.controller.scripts.at(-1);
  const packet = JSON.parse(script.slice('window.PWSharedBridge.request('.length, script.indexOf(').catch')));
  host.postMessage(JSON.stringify({protocol: PROTOCOL, id: packet.id, ok: true, result: null, ...extra}));
  return packet;
}

test('packaged allowlist exactly matches the frozen shared bundle', async () => {
  assert.equal((await verifyBundle()).bundle_sha256, EXPECTED_BUNDLE);
  const paths = JSON.parse(assetSource.match(/ASSET_PATHS: string\[\] = (\[[\s\S]*\]);/)[1]);
  assert.deepEqual(paths, [...Object.keys(manifest.files), 'BUNDLE_MANIFEST.json', 'bundle_identity.json'].sort());
  assert.equal(assetSource, assetDeclarations(manifest));
  assert.ok(assetSource.includes(EXPECTED_BUNDLE));
});

test('staging is byte-exact, idempotent, rejects changed files, extra files and symlinks', async () => {
  const temp = await fs.mkdtemp(path.join(await fs.realpath(os.tmpdir()), 'pw-ark-assets-'));
  try {
    assert.equal((await stageAssets(temp)).files, Object.keys(manifest.files).length + 2);
    await stageAssets(temp);
    const staged = path.join(temp, 'pw_shared_viewer');
    const file = path.join(staged, 'index.html');
    const original = await fs.readFile(file);
    await fs.writeFile(file, 'tampered');
    await assert.rejects(stageAssets(temp), /Refusing to overwrite/);
    await fs.writeFile(file, original);
    await fs.writeFile(path.join(staged, 'extra.js'), 'extra');
    await assert.rejects(stageAssets(temp), /Unexpected staged asset/);
    await fs.unlink(path.join(staged, 'extra.js'));
    await fs.unlink(file);
    await fs.symlink('/etc/hosts', file);
    await assert.rejects(stageAssets(temp), /Symlink/);
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('every module gets its exact bytes, JavaScript MIME and no network fallback', () => {
  const host = readyHost();
  const content = Uint8Array.from([0, 255, 17, 48]);
  const reads = [];
  host.setAssetReader(p => { reads.push(p); return content; });
  for (const relative of Object.keys(manifest.files)) {
    const response = host.intercept(`${ORIGIN}/${relative}`, 'GET');
    assert.equal(response.code, 200);
    assert.deepEqual(new Uint8Array(response.body), content);
    assert.equal(reads.at(-1), `pw_shared_viewer/${relative}`);
    if (/\.m?js$/.test(relative)) assert.equal(response.mime, 'text/javascript');
    assert.ok(response.headers.find(h => h.headerKey === 'Content-Security-Policy').headerValue.includes("frame-src 'none'"));
  }
  for (const url of ['https://evil.example/index.html', `${ORIGIN}.evil/index.html`, `${ORIGIN}/../index.html`, `${ORIGIN}/%2e%2e/index.html`, `${ORIGIN}/index.html?x=1`, `${ORIGIN}/missing.mjs`, 'file:///etc/hosts']) {
    assert.equal(host.intercept(url, 'GET').code, 404, url);
    assert.equal(host.allowNavigation(url, true), false, url);
  }
  assert.equal(host.intercept(ENTRY, 'POST').code, 404);
  assert.equal(host.allowNavigation(ENTRY, false), false);
  assert.equal(host.allowNavigation(ENTRY, true), true);
  host.setAssetReader(() => { throw Error('missing'); });
  assert.equal(host.intercept(ENTRY, 'GET').code, 500);
  host.dispose();
});

test('model registration freezes bytes and only GLB/PLY/SKP registered loads pass', async () => {
  const host = readyHost();
  const input = Uint8Array.from([0, 1, 2, 3]);
  const url = host.registerModel(input, 'ply');
  input.fill(99);
  assert.deepEqual(new Uint8Array(host.intercept(url, 'GET').body), Uint8Array.from([0, 1, 2, 3]));
  assert.throws(() => host.registerModel(input, 'obj'), /GLB, PLY or SKP/);
  const skpUrl = host.registerModel(input, 'skp');
  const skpLoad = host.request('load', {url: skpUrl, format:'skp'});
  reply(host); await skpLoad;
  await assert.rejects(host.request('load', {url: 'https://other/model.glb', format:'glb'}));
  await assert.rejects(host.request('load', {url, format:'glb'}));
  const load = host.request('load', {url, format:'ply'});
  assert.equal(reply(host).method, 'load');
  await load;
  host.unregisterModel(url);
  assert.equal(host.intercept(url, 'GET').code, 404);
  host.dispose();
});

test('protocol gate, request correlation, script errors and reload reject pending work', async () => {
  const host = new PwArkWebHost();
  host.pageBegin(ENTRY);
  host.postMessage('{broken');
  host.postMessage('null');
  host.postMessage('42');
  host.postMessage(JSON.stringify({protocol: 'WRONG', type: 'pw-viewer-ready', state: {bundleIdentity: EXPECTED_BUNDLE}}));
  assert.equal(host.isReady(), false);
  host.postMessage(JSON.stringify({protocol: PROTOCOL, id: 'host-ready', ok: true, result: {bundleIdentity: EXPECTED_BUNDLE}}));
  const result = host.request('getState');
  reply(host, {result: {engine: 'three'}});
  assert.equal(JSON.parse(await result).result.engine, 'three');
  const reload = host.request('capture');
  const rejected = assert.rejects(reload, /document changed/);
  host.pageBegin(ENTRY);
  await rejected;
  assert.equal(host.isReady(), false);
  host.postMessage(JSON.stringify({protocol: PROTOCOL, type: 'pw-viewer-ready', state: {bundleIdentity: EXPECTED_BUNDLE}}));
  host.controller.fail = true;
  await assert.rejects(host.request('getState'), /dispatch failed/);
  host.dispose();
});

test('hidden-before-ready pauses; lifecycle and disposal clear model access and bridge', async () => {
  const host = new PwArkWebHost();
  host.setForeground(false);
  host.pageBegin(ENTRY);
  host.postMessage(JSON.stringify({protocol: PROTOCOL, type:'pw-viewer-ready', state: {bundleIdentity: EXPECTED_BUNDLE}}));
  assert.equal(reply(host).method, 'pause');
  host.setForeground(true);
  assert.equal(reply(host).method, 'resume');
  const url = host.registerModel(Uint8Array.from([1]), 'glb');
  const pending = host.request('getState');
  const rejected = assert.rejects(pending, /disposed/);
  host.dispose();
  await rejected;
  assert.equal(host.intercept(url, 'GET').code, 404);
  assert.equal(host.isReady(), false);
  assert.deepEqual(host.controller.deleted, ['PWSharedHost']);
  assert.equal(host.allowNavigation(ENTRY, true), false);
  host.dispose();
});


test('ready receipt mismatch never attaches and rejects queued operations', async () => {
  const host = readyHost();
  const pending = host.request('getState');
  const rejected = assert.rejects(pending, /receipt does not match/);
  host.postMessage(JSON.stringify({ protocol: PROTOCOL, type: 'pw-viewer-ready', state: {bundleIdentity: '0'.repeat(64)} }));
  await rejected;
  assert.equal(host.isReady(), false);
  await assert.rejects(host.request('capture'), /not ready/);
  host.dispose();
});


test('complete source overlay generates identity declarations without modifying renderer', async () => {
  const temp = await fs.mkdtemp(path.join(await fs.realpath(os.tmpdir()), 'pw-ark-overlay-'));
  try {
    const raw = path.join(temp, 'rawfile');
    const ets = path.join(temp, 'ets');
    const staged = await stageHost(raw, ets);
    assert.equal(staged.bundle_sha256, EXPECTED_BUNDLE);
    assert.equal(await fs.readFile(path.join(ets, 'SharedViewerAssets.ets'), 'utf8'), assetSource);
    assert.equal(await fs.readFile(path.join(ets, 'PwArkWebHost.ets'), 'utf8'), await fs.readFile(sourceUrl, 'utf8'));
    const receipt = JSON.parse(await fs.readFile(path.join(raw, 'pw_shared_viewer/bundle_identity.json'), 'utf8'));
    assert.equal(receipt.bundle_sha256, EXPECTED_BUNDLE);
    await stageHost(raw, ets);
    await fs.writeFile(path.join(ets, 'PwArkWebHost.ets'), 'changed');
    await assert.rejects(stageHost(raw, ets), /Refusing to overwrite host source/);
  } finally { await fs.rm(temp, {recursive: true, force: true}); }
});
