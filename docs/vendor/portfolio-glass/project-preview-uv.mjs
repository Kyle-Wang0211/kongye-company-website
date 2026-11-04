import * as THREE from "three";
import { DecalGeometry } from "three/examples/jsm/geometries/DecalGeometry.js";

/** Native Three projector; copy UVs only, never its rebuilt positions/normals. */
export function bindProjectPreviewUv(geometry                      ) {
  geometry.computeBoundingBox();
  const bounds = geometry.boundingBox ;
  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  // A tiny pad keeps boundary vertices inside the native decal clip volume.
  size.x *= 1.00001; size.y *= 1.00001; size.z = 1;
  const temporaryMaterial = new THREE.MeshBasicMaterial();
  const projector = new DecalGeometry(new THREE.Mesh(geometry, temporaryMaterial), center,
    new THREE.Euler(0, 0, Math.PI), size);
  try {
    const source = geometry.getAttribute("position"), projected = projector.getAttribute("position");
    if (source.count !== projected.count) throw new Error("Preview projection changed glass vertex order");
    for (let index = 0; index < source.array.length; index++) {
      if (Math.abs(source.array[index] - projected.array[index]) > 1e-7) {
        throw new Error("Preview projection changed glass vertices");
      }
    }
    geometry.setAttribute("projectUv", projector.getAttribute("uv").clone());
  } finally { projector.dispose(); temporaryMaterial.dispose(); }
}
