import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {readReleaseIdentity} from '../web/bundle_identity.mjs';

const identity = async files => [...new Uint8Array(await webcrypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(files))))].map(n => n.toString(16).padStart(2, '0')).join('');
async function fixture() {
  const files = Object.fromEntries(Array.from({length:28}, (_, n) => [`asset-${String(n).padStart(2, '0')}.mjs`, 'a'.repeat(64)]));
  return {schema:'PW_SHARED_VIEWER_BUNDLE_V1',engine:'three',engine_version:'0.186.1',upstream_commit:'9b4a2ac29c63ccb43fd51c5661f2f873ac2c39b8',files,bundle_sha256:await identity(files)};
}

test('browser identity reads only the release manifest without fetching bundle files', async () => {
  const manifest = await fixture(), requests = [];
  const result = await readReleaseIdentity(new URL('https://example.test/viewer/'), {
    crypto:webcrypto, fetch:async url => { requests.push(String(url)); return {ok:true,json:async()=>manifest}; },
  });
  assert.equal(result,manifest.bundle_sha256);
  assert.deepEqual(requests,['https://example.test/viewer/BUNDLE_MANIFEST.json']);
});

test('browser release identity rejects malformed or inconsistent manifests', async () => {
  for (const mutate of [m=>{m.schema='WRONG';},m=>{m.engine_version='old';},m=>{m.files['../escape']='a'.repeat(64);},m=>{m.files['viewer.mjs']='broken';},m=>{m.bundle_sha256='0'.repeat(64);},m=>{m.files={};},m=>{m.files=['a'.repeat(64)];}]) {
    const manifest = await fixture(); mutate(manifest);
    await assert.rejects(readReleaseIdentity(new URL('https://example.test/viewer/'), {crypto:webcrypto,fetch:async()=>({ok:true,json:async()=>manifest})}));
  }
});

test('unavailable manifest fails browser initialization', async () => {
  await assert.rejects(readReleaseIdentity(new URL('https://example.test/viewer/'), {crypto:webcrypto,fetch:async()=>({ok:false})}),/manifest is unavailable/);
});
