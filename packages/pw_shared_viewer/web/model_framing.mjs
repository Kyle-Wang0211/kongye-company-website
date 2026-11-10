/* @license
 * Copyright 2025 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Modified for the shared viewer: synchronous static-scene framing only.
// Upstream identity, exact source lines and all adaptation boundaries are recorded
// in MODEL_FRAMING_UPSTREAM.json. No rendering engine or control replacement.
import { Box3, Vector3 } from './vendor/three/build/three.module.js';

// Exact Three.js SceneUtils.reduceVertices, MIT; see vendor/three/LICENSE.
function reduceVertices( object, func, initialValue ) {

	let value = initialValue;
	const vertex = new Vector3();

	object.updateWorldMatrix( true, true );

	object.traverseVisible( ( child ) => {

		const { geometry } = child;

		if ( geometry !== undefined ) {

			const { position } = geometry.attributes;

			if ( position !== undefined ) {

				for ( let i = 0, l = position.count; i < l; i ++ ) {

					if ( child.isMesh ) {

						child.getVertexPosition( i, vertex );

					} else {

						vertex.fromBufferAttribute( position, i );

					}

					if ( ! child.isSkinnedMesh ) {

						vertex.applyMatrix4( child.matrixWorld );

					}

					value = func( value, vertex );

				}

			}

		}

	} );

	return value;

}

// Google ModelScene.updateBoundingBox/updateFraming arithmetic, with the host's
// existing bounding-box center in place of model-viewer's reactive cameraTarget.
export function framingForObject(object, framedFoVDeg = 45) {
  const boundingBox = reduceVertices(object, (box, vertex) => box.expandByPoint(vertex), new Box3());
  if (boundingBox.isEmpty()) return null;
  const center = boundingBox.getCenter(new Vector3());
  if (![center.x, center.y, center.z].every(Number.isFinite)) return null;
  const radiusSquared = (value, vertex) => Math.max(value, center.distanceToSquared(vertex));
  const maxRadiusSq = reduceVertices(object, radiusSquared, 0);
  const radius = Math.sqrt(maxRadiusSq);
  if (!Number.isFinite(radius) || radius <= 0) return null;
  const idealCameraDistance = radius / Math.sin((framedFoVDeg / 2) * Math.PI / 180);
  const horizontalTanFov = (value, vertex) => {
    vertex.sub(center);
    const radiusXZ = Math.sqrt(vertex.x * vertex.x + vertex.z * vertex.z);
    return Math.max(value, radiusXZ / (idealCameraDistance - Math.abs(vertex.y)));
  };
  const maxAspect = reduceVertices(object, horizontalTanFov, 0);
  const idealAspect = maxAspect / Math.tan((framedFoVDeg / 2) * Math.PI / 180);
  if (!Number.isFinite(idealAspect) || idealAspect <= 0) return null;
  return { center, radius, idealAspect, idealCameraDistance };
}

// Google ModelScene.adjustedFoV, with scene fields passed explicitly.
export function adjustedFoV(fovDeg, idealAspect, aspect) {
  const vertical = Math.tan((fovDeg / 2) * Math.PI / 180) * Math.max(1, idealAspect / aspect);
  return 2 * Math.atan(vertical) * 180 / Math.PI;
}
