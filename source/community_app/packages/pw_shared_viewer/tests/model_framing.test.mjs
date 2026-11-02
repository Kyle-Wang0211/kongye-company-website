import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../web/vendor/three/build/three.module.js';
import { framingForObject, adjustedFoV } from '../web/model_framing.mjs';
import { modelSceneSource, reduceVerticesSource } from './model_framing_reference.mjs';

// Execute the pinned original methods, removing TypeScript annotations only.
const reduceVertices = new Function('Vector3', `${reduceVerticesSource}; return reduceVertices;`)(THREE.Vector3);
const source = modelSceneSource.replaceAll(': number', '').replaceAll(': Vector3', '').replaceAll(': boolean', '').replaceAll('center!', 'center');
const referenceMethods = new Function('reduceVertices', `return {${source.replace(/\n  (setBakedShadowVisibility|idealCameraDistance|adjustedFoV)/g, '\n  ,$1')}}`)(reduceVertices);
async function reference(object) {
  const center = new THREE.Box3().setFromObject(object, true).getCenter(new THREE.Vector3());
  const ref = { ...referenceMethods, models: [object], target: { remove() {}, add() {} },
    element: { requestUpdate() {}, updateComplete: Promise.resolve() }, bakedShadows: [],
    getTarget: () => center, boundingSphere: new THREE.Sphere(), framedFoVDeg: 45,
  };
  await ref.updateFraming();
  return ref;
}
function mesh(x, y, z) { return new THREE.Mesh(new THREE.BoxGeometry(x, y, z)); }
for (const [label, dimensions] of [['tall', [1, 8, 1]], ['wide', [8, 1, 3]], ['cube', [2, 2, 2]]]) {
  test(`${label} geometry agrees with exact pinned Google reference`, async () => {
    const object = mesh(...dimensions);
    const actual = framingForObject(object, 45), expected = await reference(object);
    assert.equal(actual.idealAspect, expected.idealAspect);
    assert.equal(actual.radius, expected.boundingSphere.radius);
    assert.deepEqual(actual.center, expected.boundingSphere.center);
    for (const aspect of [0.25, 0.75, 1, 4 / 3, 3]) {
      expected.aspect = aspect;
      assert.equal(adjustedFoV(45, actual.idealAspect, aspect), expected.adjustedFoV(45));
    }
  });
}
test('offset geometry retains its actual center and translation invariant ideal aspect', () => {
  const object = mesh(2, 7, 3), initial = framingForObject(object, 45);
  object.position.set(120, -40, 30);
  const shifted = framingForObject(object, 45);
  assert.deepEqual(shifted.center.toArray(), [120, -40, 30]);
  assert.equal(shifted.idealAspect, initial.idealAspect);
});
test('ideal aspect responds to geometry; empty, invisible and nonfinite input has no framing', () => {
  assert.ok(framingForObject(mesh(1, 8, 1), 45).idealAspect < framingForObject(mesh(8, 1, 3), 45).idealAspect);
  assert.equal(framingForObject(new THREE.Group(), 45), null);
  const hidden = mesh(1, 1, 1); hidden.visible = false;
  assert.equal(framingForObject(hidden, 45), null);
  const invalid = new THREE.Points(new THREE.BufferGeometry().setAttribute('position',
    new THREE.Float32BufferAttribute([NaN, 0, 0], 3)));
  assert.equal(framingForObject(invalid, 45), null);
});

test('reference excerpts retain pinned byte identities and copied reducer is exact',async()=>{
  const {readFile}=await import('node:fs/promises');
  const {createHash}=await import('node:crypto');
  const hash=text=>createHash('sha256').update(text).digest('hex');
  const metadata=JSON.parse(await readFile(new URL('../web/MODEL_FRAMING_UPSTREAM.json',import.meta.url),'utf8'));
  assert.equal(hash(modelSceneSource),metadata.reference_tests.excerpts_sha256.modelSceneSource);
  assert.equal(hash(reduceVerticesSource),metadata.reference_tests.excerpts_sha256.reduceVerticesSource);
  const adaptation=await readFile(new URL('../web/model_framing.mjs',import.meta.url),'utf8');
  assert.ok(adaptation.includes(reduceVerticesSource));
  assert.equal(hash(adaptation),metadata.adaptation_sha256);
});

test('nested transformed geometry agrees with original reference arithmetic',async()=>{
  const object=new THREE.Group(), child=mesh(3,5,2);
  child.position.set(4,-2,8);child.rotation.set(0.1,0.7,0.3);child.scale.set(1,1.2,0.8);
  object.add(child);object.position.set(7,10,-3);
  const actual=framingForObject(object,45), expected=await reference(object);
  assert.equal(actual.idealAspect,expected.idealAspect);
  assert.equal(actual.radius,expected.boundingSphere.radius);
  assert.deepEqual(actual.center,expected.boundingSphere.center);
});
