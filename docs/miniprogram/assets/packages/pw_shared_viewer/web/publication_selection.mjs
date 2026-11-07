// Presentation adapter only: pinned Three.js Box3/Plane/BoxHelper APIs.
// No geometry export, clipping mesh construction or source-model normalization.
import * as THREE from './vendor/three/build/three.module.js';

export function sourceWorldBounds(model) {
  if (!model) return null;
  let unsupported = false, meshes = 0;
  model.traverse(node => {
    if (node.isSkinnedMesh || node.morphTargetInfluences?.length) unsupported = true;
    if (node.isMesh) meshes++;
  });
  if (unsupported || !meshes) return null;
  model.updateWorldMatrix(true, true);
  const bounds = new THREE.Box3().setFromObject(model, true);
  const min = bounds.min.toArray(), max = bounds.max.toArray();
  if (![...min, ...max].every(Number.isFinite) || min.some((v,i) => max[i] <= v)) return null;
  return {min, max};
}

export function selectionPlanes(box) {
  if (!box || box.v !== 2 || ![box.cx,box.cy,box.cz,box.sx,box.sy,box.sz].every(Number.isFinite) ||
      [box.sx,box.sy,box.sz].some(v => v <= 0) || !Array.isArray(box.rot) ||
      box.rot.length !== 9 || !box.rot.every(Number.isFinite)) throw new Error('Invalid selection box');
  const r = box.rot;
  const axes = [0,1,2].map(i => new THREE.Vector3(r[i],r[i+3],r[i+6]));
  if (axes.some(a => Math.abs(a.lengthSq()-1) > 1e-6) ||
      Math.abs(axes[0].dot(axes[1])) > 1e-6 || Math.abs(axes[0].dot(axes[2])) > 1e-6 ||
      Math.abs(axes[1].dot(axes[2])) > 1e-6 ||
      Math.abs(axes[0].clone().cross(axes[1]).dot(axes[2])-1) > 1e-6) throw new Error('Selection rotation must be orthonormal');
  const center = new THREE.Vector3(box.cx,box.cy,box.cz);
  return axes.flatMap((axis,i) => [1,-1].map(sign => {
    const normal = axis.clone().multiplyScalar(sign);
    return new THREE.Plane(normal, [box.sx,box.sy,box.sz][i]/2 - normal.dot(center));
  }));
}

export function createSelectionPreview({scene,renderer,getModel}) {
  let helper = null, outside = null, originals = [], priorLocalClipping = false, checkedModel = null;
  function clear() {
    for (const [material,planes,intersection] of originals) {
      material.clippingPlanes = planes; material.clipIntersection = intersection; material.needsUpdate = true;
    }
    if (originals.length) renderer.localClippingEnabled = priorLocalClipping;
    originals = [];
    if (outside) {
      scene.remove(outside); outside.traverse(node => {
        for (const m of Array.isArray(node.material) ? node.material : [node.material]) m?.dispose();
      }); outside = null;
    }
    if (helper) { scene.remove(helper); helper.geometry.dispose(); helper.material.dispose(); helper = null; }
  }
  function set(box, decorations = true) {
    if (box == null) { clear(); return; }
    const model = getModel();
    if (checkedModel !== model) {
      if (!sourceWorldBounds(model)) throw new Error('Source GLB bounds unavailable');
      checkedModel = model;
    }
    const planes = selectionPlanes(box); // validate before disturbing existing preview
    clear();
    const materials = new Set();
    model.traverse(node => { for (const m of Array.isArray(node.material) ? node.material : [node.material]) if (m) materials.add(m); });
    priorLocalClipping = renderer.localClippingEnabled;
    for (const m of materials) {
      originals.push([m,m.clippingPlanes,m.clipIntersection]);
      m.clippingPlanes = planes; m.clipIntersection = false; m.needsUpdate = true;
    }
    renderer.localClippingEnabled = true;
    if (!decorations) return;
    // Red outside indication is a second material pass through the SAME meshes,
    // using Three's documented clipIntersection; no mesh cutting/export occurs.
    outside = model.clone(true);
    const inverse = planes.map(p => p.clone().negate());
    outside.traverse(node => {
      if (!node.material) return;
      const tint = () => new THREE.MeshBasicMaterial({color:0xff4141, transparent:true, opacity:0.38,
        depthWrite:false, side:THREE.DoubleSide, clippingPlanes:inverse, clipIntersection:true});
      node.material = Array.isArray(node.material) ? node.material.map(tint) : tint();
    });
    scene.add(outside);
    const surrogate = new THREE.Mesh(new THREE.BoxGeometry(box.sx,box.sy,box.sz));
    helper = new THREE.BoxHelper(surrogate,0x9cf3cf);
    surrogate.geometry.dispose(); surrogate.material.dispose();
    const r = box.rot;
    helper.matrixAutoUpdate = false;
    helper.matrix.set(r[0],r[1],r[2],box.cx,r[3],r[4],r[5],box.cy,r[6],r[7],r[8],box.cz,0,0,0,1);
    helper.material.depthTest = false;
    helper.renderOrder = 1000;
    scene.add(helper);
  }
  return {set,clear};
}
