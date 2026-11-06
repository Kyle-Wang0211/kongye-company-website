import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const generated = readFileSync(new URL('../docs/community/flutter_bootstrap.js', import.meta.url), 'utf8');
const template = readFileSync(new URL('../source/community_app/web/flutter_bootstrap.js', import.meta.url), 'utf8');

function loadOptions(script, baseURI) {
  const calls = [];
  const flutter = {loader: {load(options) { calls.push(options); }}};
  vm.runInNewContext(script, {
    window: {_flutter: flutter},
    _flutter: flutter,
    navigator: {vendor: '', userAgent: ''},
    document: {
      baseURI,
      createElement() {
        return {getContext() {return null;}};
      },
    },
    URL, WebAssembly, Uint8Array, Intl, console,
  }, {timeout: 1000});
  assert.equal(calls.length, 1);
  return JSON.parse(JSON.stringify(calls[0]));
}

test('generated bootstrap loads local CanvasKit against the document base with default loader behavior', () => {
  for (const baseURI of [
    'https://kongye.space/',
    'https://kongye.space/community/',
    'https://example.test/nested/community/',
    'http://localhost:8080/community/?test=1#test',
  ]) {
    assert.deepEqual(loadOptions(generated, baseURI), {
      config: {canvasKitBaseUrl: new URL('canvaskit/', baseURI).href},
      serviceWorkerSettings: {serviceWorkerVersion: '3024844990'},
    });
  }
});

test('future builds retain Flutter generator tokens and the same loader options', () => {
  assert.equal((template.match(/{{flutter_js}}/g) || []).length, 1);
  assert.equal((template.match(/{{flutter_build_config}}/g) || []).length, 1);
  assert.equal((template.match(/{{flutter_service_worker_version}}/g) || []).length, 1);
  const substituted = template
    .replace('{{flutter_js}}', '')
    .replace('{{flutter_build_config}}', '')
    .replace('{{flutter_service_worker_version}}', '"future-build-version"');
  for (const baseURI of ['https://kongye.space/', 'https://kongye.space/community/']) {
    assert.deepEqual(loadOptions(substituted, baseURI), {
      config: {canvasKitBaseUrl: new URL('canvaskit/', baseURI).href},
      serviceWorkerSettings: {serviceWorkerVersion: 'future-build-version'},
    });
  }
});

test('all shipped CanvasKit WASM variants match the generated engine identity', () => {
  const match = generated.match(/_flutter\.buildConfig = ([^\n]+);/);
  const config = JSON.parse(match[1]);
  assert.equal(config.engineRevision, '5d531788691ec3404cac0cee66ead4007b177363');
  for (const relativePath of ['canvaskit.wasm', 'chromium/canvaskit.wasm', 'webparagraph/canvaskit.wasm']) {
    const bytes = readFileSync(new URL(`../docs/community/canvaskit/${relativePath}`, import.meta.url));
    const hash = createHash('sha256').update(bytes).digest('hex');
    assert.equal(hash, config.wasmHashes[relativePath]);
  }
});
