import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { verifyBundle } from '../web/bundle_identity.mjs';

const digest = async bytes => Buffer.from(await webcrypto.subtle.digest('SHA-256', bytes)).toString('hex');
async function fixture(count) {
  const assets = new Map(Array.from({ length: count }, (_, i) => [`asset-${String(i).padStart(2, '0')}.js`, new TextEncoder().encode(`engine ${i}`)]));
  const files = Object.fromEntries(await Promise.all([...assets].map(async ([path, bytes]) => [path, await digest(bytes)])));
  return { assets, manifest: { files, bundle_sha256: await digest(new TextEncoder().encode(JSON.stringify(files))) } };
}
const turn = () => new Promise(resolve => setImmediate(resolve));
async function until(predicate) {
  for (let i = 0; i < 1000; i++) { if (predicate()) return; await turn(); }
  throw Error('Expected verification milestone was not reached');
}

test('all assets verify with at most four fetched buffers alive through hashing', async () => {
  for (const count of [1, 3, 9, 27]) {
    const { assets, manifest } = await fixture(count);
    let alive = 0, peak = 0;
    const visited = [];
    const crypto = { subtle: { digest: async (algorithm, bytes) => {
      const resource = [...assets.values()].includes(bytes);
      if (resource) await turn();
      try { return await webcrypto.subtle.digest(algorithm, bytes); }
      finally { if (resource) alive--; }
    } } };
    const result = await verifyBundle({ manifest, crypto, fetchResource: async path => {
      visited.push(path); peak = Math.max(peak, ++alive);
      return assets.get(path);
    } });
    assert.equal(result, manifest.bundle_sha256);
    assert.deepEqual([...visited].sort(), [...assets.keys()].sort());
    assert.equal(peak, Math.min(4, count));
    assert.equal(alive, 0);
  }
});

test('invalid paths, resource hashes and canonical identity never fetch assets', async () => {
  for (const mutation of [m => { m.files['../escape'] = 'a'.repeat(64); }, m => { m.files['asset-00.js'] = 'broken'; }, m => { m.bundle_sha256 = '0'.repeat(64); }]) {
    const { manifest } = await fixture(2); mutation(manifest);
    let calls = 0;
    await assert.rejects(verifyBundle({ manifest, crypto: webcrypto, fetchResource: async () => { calls++; } }));
    assert.equal(calls, 0);
  }
});

test('tampered asset bytes reject verification', async () => {
  const { assets, manifest } = await fixture(9);
  await assert.rejects(verifyBundle({ manifest, crypto: webcrypto, fetchResource: async path => path === 'asset-02.js' ? new Uint8Array([0]) : assets.get(path) }), /Viewer resource identity mismatch: asset-02.js/);
});

test('first failure stops new starts and waits for every in-flight request', async () => {
  const { assets, manifest } = await fixture(9);
  const pending = new Map(), started = [];
  let settled = false;
  const firstError = Error('first network failure');
  const result = verifyBundle({ manifest, crypto: webcrypto, fetchResource: path => {
    started.push(path);
    return new Promise((resolve, reject) => pending.set(path, { resolve, reject }));
  } });
  const observed = result.then(() => { settled = true; return null; }, error => { settled = true; return error; });
  await until(() => started.length === 4);
  pending.get(started[0]).reject(firstError);
  await turn(); await turn();
  assert.equal(settled, false);
  assert.equal(started.length, 4);
  pending.get(started[1]).reject(Error('later failure'));
  for (const path of started.slice(2)) pending.get(path).resolve(assets.get(path));
  assert.equal(await observed, firstError);
  assert.equal(started.length, 4);
});
