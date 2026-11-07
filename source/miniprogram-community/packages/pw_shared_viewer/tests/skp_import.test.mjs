import test from 'node:test';
import assert from 'node:assert/strict';
import { assertSkpDisplayCompatibility } from '../web/skp_policy.mjs';

function model(overrides = {}) {
  return { version: '3.0.1', root: { faces: [{}] }, definitions: new Map(), materials: [], ...overrides };
}
test('legacy projected front and back textures cannot silently approximate UVs', () => {
  for (const flag of ['uvProjected', 'uvProjectedBack']) {
    assert.throws(() => assertSkpDisplayCompatibility(model({ root: { faces: [{ [flag]: true }] } }), true), /投影纹理/);
  }
});
test('modern textured files are rejected when upstream cannot identify projected UVs', () => {
  assert.throws(() => assertSkpDisplayCompatibility(model({ materials: [{ texture: {} }] }), false), /纹理/);
});
test('empty or missing texture payloads are not accepted as successful imports', () => {
  assert.throws(() => assertSkpDisplayCompatibility(model({ root: { faces: [] } }), true), /面/);
  assert.throws(() => assertSkpDisplayCompatibility(model({ materials: [{ texture: { data: null } }] }), true), /纹理/);
});
test('ordinary textured legacy surface files preserve source version in receipt', () => {
  const receipt = assertSkpDisplayCompatibility(model({ materials: [{ texture: { data: new Uint8Array([1]) } }] }), true);
  assert.equal(receipt.sourceVersion, '3.0.1');
  assert.equal(receipt.sourceFaceCount, 1);
});
