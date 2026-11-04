import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../web/vendor/three/build/three.module.js';
import { sourceWorldBounds, selectionPlanes, createSelectionPreview } from '../web/publication_selection.mjs';

test('bounds retain original glTF world translation, rotation and nonuniform scale', () => {
  const root = new THREE.Group();
  root.position.set(10, -4, 7); root.rotation.z = Math.PI / 2; root.scale.set(2, 3, 4);
  root.add(new THREE.Mesh(new THREE.BoxGeometry(2, 4, 6), new THREE.MeshBasicMaterial()));
  const before = root.matrix.clone();
  const bounds = sourceWorldBounds(root);
  for (const [key, expected] of Object.entries({min:[4,-6,-5],max:[16,-2,19]}))
    expected.forEach((v,i) => assert.ok(Math.abs(bounds[key][i]-v)<1e-10));
  assert.deepEqual(root.position.toArray(), [10, -4, 7]);
  assert.equal(before.elements[12], 0); // traversal updates matrices, never model coordinates
});

test('rotated source-world OBB planes retain inside and exclude outside', () => {
  const box = {v: 2, cx: 10, cy: -4, cz: 7, sx: 2, sy: 4, sz: 6,
    rot: [0,-1,0, 1,0,0, 0,0,1]};
  const planes = selectionPlanes(box);
  const inside = new THREE.Vector3(11.9, -3.1, 9.9);
  assert.ok(planes.every(p => p.distanceToPoint(inside) >= 0));
  assert.ok(planes.some(p => p.distanceToPoint(new THREE.Vector3(10,-2,7)) < 0));
  assert.throws(() => selectionPlanes({...box, rot: [2,0,0,0,1,0,0,0,1]}));
});

test('unknown, empty and animated geometry fail closed', () => {
  assert.equal(sourceWorldBounds(new THREE.Group()), null);
  const root = new THREE.Group(); root.add(new THREE.SkinnedMesh(new THREE.BoxGeometry(),new THREE.MeshBasicMaterial()));
  assert.equal(sourceWorldBounds(root), null);
});

test('clear restores materials; preview does not mutate geometry or root transforms', () => {
  const material = new THREE.MeshBasicMaterial();
  const prior = [new THREE.Plane(new THREE.Vector3(1,0,0), 12)]; material.clippingPlanes = prior;
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(), material);
  const scene = new THREE.Scene(); scene.add(mesh);
  const renderer = {localClippingEnabled: false};
  const preview = createSelectionPreview({scene, renderer, getModel: () => mesh});
  const bytes = mesh.geometry.attributes.position.array.slice();
  preview.set({v:2,cx:0,cy:0,cz:0,sx:1,sy:1,sz:1,rot:[1,0,0,0,1,0,0,0,1]});
  assert.equal(material.clippingPlanes.length,6);
  assert.equal(scene.children.length,3);
  preview.clear();
  assert.equal(material.clippingPlanes,prior);
  assert.equal(renderer.localClippingEnabled,false);
  assert.equal(scene.children.length,1);
  assert.deepEqual(mesh.geometry.attributes.position.array,bytes);
});
