import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { verifyBundle } from '../web/bundle_identity.mjs';

const digest = async bytes => Buffer.from(await webcrypto.subtle.digest('SHA-256', bytes)).toString('hex');
const bytes = new TextEncoder().encode('immutable engine');
async function fixture(overrides = {}) {
  const files = { 'vendor/engine.js': await digest(bytes) };
  const manifest = { files, bundle_sha256: await digest(new TextEncoder().encode(JSON.stringify(files))) };
  return { manifest, fetchResource: async () => bytes, crypto: webcrypto, ...overrides };
}
test('changed engine bytes are rejected before renderer initialization', async () => {
  const options = await fixture({ fetchResource: async () => new Uint8Array([0]) });
  await assert.rejects(verifyBundle(options), /identity mismatch/);
});
test('manifest cannot authorize parent paths or another origin', async () => {
  for (const path of ['../secret', 'https://other.test/code.js', '/code.js', 'a%2fb', 'a?b', 'a\\b']) {
    const files = { [path]: await digest(bytes) };
    const manifest = { files, bundle_sha256: await digest(new TextEncoder().encode(JSON.stringify(files))) };
    await assert.rejects(verifyBundle(await fixture({ manifest })), /Invalid bundle path/);
  }
});
test('a complete bundle reports its verified content identity', async () => {
  const options = await fixture();
  assert.equal(await verifyBundle(options), options.manifest.bundle_sha256);
});
