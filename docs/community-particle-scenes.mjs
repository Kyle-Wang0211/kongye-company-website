import * as THREE from './viewer/vendor/three/build/three.module.js';
import { MeshSurfaceSampler } from './vendor/three-activity/MeshSurfaceSampler.js';

const POINT_COUNTS = { ceramic: 7500, resort: 7400, courtyard: 7200 };
const SEEDS = { ceramic: 28731, resort: 96173, courtyard: 54109 };

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

// Each shape is sampled once with a repeatable sequence. Only sampled positions
// survive construction, so source meshes never reach the renderer.
function sampleSurface(geometry, count, transform, random, positions) {
  const material = new THREE.MeshBasicMaterial();
  const mesh = new THREE.Mesh(geometry, material);
  mesh.position.set(...(transform.position || [0, 0, 0]));
  mesh.rotation.set(...(transform.rotation || [0, 0, 0]));
  mesh.scale.set(...(transform.scale || [1, 1, 1]));
  mesh.updateMatrixWorld(true);
  const sampler = new MeshSurfaceSampler(mesh).setRandomGenerator(random).build();
  const point = new THREE.Vector3();
  for (let i = 0; i < count; i += 1) {
    sampler.sample(point);
    point.applyMatrix4(mesh.matrixWorld);
    positions.push(point.x, point.y, point.z);
  }
  geometry.dispose();
  material.dispose();
}

function vessel(profile, count, position, rotation, random, positions) {
  const curve = profile.map(([radius, height]) => new THREE.Vector2(radius, height));
  sampleSurface(new THREE.LatheGeometry(curve, 72), count, { position, rotation }, random, positions);
}

function ceramic(random, positions) {
  vessel([[0.4, 0], [0.75, 0.12], [1.08, 0.7], [1.12, 1.35], [0.95, 2.0], [0.5, 2.6], [0.46, 3.2], [0.55, 3.26]],
    1800, [-6.4, -2.1, 0.3], [0.06, 0, -0.09], random, positions);
  vessel([[0.5, 0], [0.7, 0.15], [0.95, 0.7], [1.42, 1.35], [1.5, 1.5], [1.4, 1.55]],
    1350, [-2.8, -1.8, 1.1], [0, 0, 0.08], random, positions);
  vessel([[0.52, 0], [0.7, 0.12], [1.0, 0.8], [1.05, 1.8], [0.9, 2.8], [0.48, 3.4], [0.48, 4.1], [0.6, 4.16]],
    1900, [0.4, -2.3, -0.5], [-0.04, 0, 0.035], random, positions);
  vessel([[0.4, 0], [0.9, 0.1], [1.26, 0.9], [1.32, 1.55], [1.1, 2.1], [0.82, 2.3], [0.8, 2.45]],
    1500, [4.2, -2.0, 0.6], [0.07, 0, -0.06], random, positions);
  vessel([[0.3, 0], [0.64, 0.16], [0.75, 1.1], [0.55, 2.0], [0.38, 2.3], [0.38, 2.95]],
    750, [7.2, -1.8, -1.0], [0, 0, 0.12], random, positions);
  // A narrow floating ground gives the objects depth while leaving white space.
  sampleSurface(new THREE.PlaneGeometry(20, 3), 200,
    { position: [0, -2.4, 0], rotation: [-Math.PI / 2, 0, 0] }, random, positions);
}

function mountainGeometry(offset, scale, seed) {
  const geometry = new THREE.PlaneGeometry(22, 5.0, 120, 30);
  geometry.rotateX(-Math.PI / 2);
  const vertices = geometry.getAttribute('position');
  for (let i = 0; i < vertices.count; i += 1) {
    const x = vertices.getX(i);
    const z = vertices.getZ(i);
    const envelope = Math.max(0, 1 - Math.pow(Math.abs(x) / 11.2, 4));
    const ridge = Math.sin(x * 0.55 + seed) * 0.65
      + Math.sin(x * 1.11 + seed * 2) * 0.25
      + Math.cos(z * 0.7 + x * 0.24) * 0.4;
    vertices.setY(i, offset + envelope * (scale + ridge * scale) - Math.abs(z) * 0.14);
  }
  geometry.computeVertexNormals();
  return geometry;
}

function resort(random, positions) {
  for (let layer = 0; layer < 4; layer += 1) {
    sampleSurface(mountainGeometry(-2.8 + layer * 0.32, 0.8 + layer * 0.42, layer * 1.7), 1450,
      { position: [0, 0, -3 + layer * 1.9] }, random, positions);
  }
  // A small open pavilion, described by thin columns and a flat circular canopy.
  sampleSurface(new THREE.CylinderGeometry(1.25, 1.25, 0.12, 48), 350,
    { position: [3.0, 1.25, 0.2] }, random, positions);
  sampleSurface(new THREE.CylinderGeometry(1.45, 1.45, 0.12, 48), 300,
    { position: [3.0, -0.6, 0.2] }, random, positions);
  for (let i = 0; i < 6; i += 1) {
    const angle = i * Math.PI / 3;
    sampleSurface(new THREE.CylinderGeometry(0.035, 0.035, 1.85, 6), 100,
      { position: [3 + Math.cos(angle), 0.33, 0.2 + Math.sin(angle)] }, random, positions);
  }
  sampleSurface(new THREE.PlaneGeometry(19, 2.8), 350,
    { position: [0, -2.8, 4.4], rotation: [-Math.PI / 2, 0, -0.05] }, random, positions);
}

function branch(start, end, radius, count, random, positions) {
  const direction = new THREE.Vector3().subVectors(end, start);
  const geometry = new THREE.CylinderGeometry(radius * 0.4, radius, direction.length(), 7);
  const rotation = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), direction.normalize());
  geometry.applyQuaternion(rotation);
  const center = start.clone().add(end).multiplyScalar(0.5);
  sampleSurface(geometry, count, { position: center.toArray() }, random, positions);
}

function courtyard(random, positions) {
  for (let ring = 0; ring < 3; ring += 1) {
    sampleSurface(new THREE.TorusGeometry(2.5 + ring * 0.32, 0.07, 6, 128), 850,
      { position: [-0.3, -1.8 - ring * 0.18, 0.1], rotation: [-Math.PI / 2, 0, 0], scale: [1.6, 1, 1] }, random, positions);
  }
  sampleSurface(new THREE.CylinderGeometry(2.25, 2.25, 0.05, 72), 650,
    { position: [-0.3, -2.0, 0.1], scale: [1.6, 1, 1] }, random, positions);
  // Bare branching silhouettes keep the courtyard open to the white background.
  const trees = [
    { x: -6.3, z: 0.4, lean: 0.75 },
    { x: 5.8, z: -0.8, lean: -0.8 },
  ];
  for (const tree of trees) {
    const base = new THREE.Vector3(tree.x, -2.0, tree.z);
    const fork = new THREE.Vector3(tree.x + tree.lean * 0.4, 0.0, tree.z);
    const crown = new THREE.Vector3(tree.x + tree.lean, 2.6, tree.z - 0.2);
    branch(base, fork, 0.15, 450, random, positions);
    branch(fork, crown, 0.09, 350, random, positions);
    for (let i = 0; i < 5; i += 1) {
      const side = i % 2 === 0 ? -1 : 1;
      const origin = fork.clone().lerp(crown, 0.12 + i * 0.15);
      const tip = origin.clone().add(new THREE.Vector3(side * (1.1 + i * 0.12), 0.8 + (i % 3) * 0.18, Math.sin(i * 2.2) * 0.8));
      branch(origin, tip, 0.045, 150, random, positions);
      const twig = tip.clone().add(new THREE.Vector3(side * 0.5, 0.7, 0.25));
      branch(tip, twig, 0.016, 80, random, positions);
    }
  }
  sampleSurface(new THREE.PlaneGeometry(21, 4.5), 100,
    { position: [0, -2.1, 0], rotation: [-Math.PI / 2, 0, 0] }, random, positions);
}

function makeConnections(positions) {
  const cells = new Map();
  const segments = [];
  const cellSize = 1.1;
  const keyAt = (x, y, z) => `${x},${y},${z}`;
  // One bounded local lookup per point. No frame-time work or all-pairs search.
  for (let i = 0; i < positions.length; i += 3) {
    const x = positions[i];
    const y = positions[i + 1];
    const z = positions[i + 2];
    const cellX = Math.floor(x / cellSize);
    const cellY = Math.floor(y / cellSize);
    const cellZ = Math.floor(z / cellSize);
    const key = keyAt(cellX, cellY, cellZ);
    const nearby = cells.get(key);
    if (nearby !== undefined && (i / 3) % 13 === 0 && segments.length < 1200 * 6) {
      const dx = x - positions[nearby];
      const dy = y - positions[nearby + 1];
      const dz = z - positions[nearby + 2];
      const distanceSquared = dx * dx + dy * dy + dz * dz;
      if (distanceSquared > 0.08 && distanceSquared < 1.1) {
        segments.push(x, y, z, positions[nearby], positions[nearby + 1], positions[nearby + 2]);
      }
    }
    cells.set(key, i);
  }
  return segments;
}

export function createActivityScene(activity, index = 0) {
  const slug = typeof activity === 'string' ? activity : activity?.slug;
  const kind = Object.hasOwn(POINT_COUNTS, slug) ? slug : ['ceramic', 'resort', 'courtyard'][Math.abs(index) % 3];
  const random = seededRandom(SEEDS[kind]);
  const positions = [];
  ({ ceramic, resort, courtyard })[kind](random, positions);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xffffff);
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  const shades = [];
  const sizes = [];
  for (let i = 0; i < positions.length; i += 3) {
    const depth = THREE.MathUtils.clamp((positions[i + 2] + 4) / 10, 0, 1);
    shades.push(0.02 + depth * 0.10 + random() * 0.08);
    sizes.push(2.1 + random() * 1.3);
  }
  geometry.setAttribute('shade', new THREE.Float32BufferAttribute(shades, 1));
  geometry.setAttribute('pointSize', new THREE.Float32BufferAttribute(sizes, 1));
  const material = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: { pixelRatio: { value: 1 } },
    vertexShader: `
      uniform float pixelRatio;
      attribute float shade;
      attribute float pointSize;
      varying float vShade;
      void main() {
        vShade = shade;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        gl_PointSize = pointSize * pixelRatio;
      }
    `,
    fragmentShader: `
      varying float vShade;
      void main() {
        float radius = length(gl_PointCoord - vec2(0.5));
        if (radius > 0.5) discard;
        float alpha = 1.0 - smoothstep(0.30, 0.5, radius);
        gl_FragColor = vec4(vec3(vShade), alpha * 0.92);
      }
    `,
  });
  scene.add(new THREE.Points(geometry, material));

  const connections = makeConnections(positions);
  const lineGeometry = new THREE.BufferGeometry();
  lineGeometry.setAttribute('position', new THREE.Float32BufferAttribute(connections, 3));
  const lineMaterial = new THREE.LineBasicMaterial({ color: 0x777777, transparent: true, opacity: 0.25, depthWrite: false });
  scene.add(new THREE.LineSegments(lineGeometry, lineMaterial));
  scene.userData.activityKind = kind;
  scene.userData.pointCount = positions.length / 3;
  scene.userData.lineCount = connections.length / 6;
  scene.userData.seed = SEEDS[kind];

  const camera = new THREE.OrthographicCamera(-12, 12, 4, -4, 0.1, 100);
  camera.position.set(0, 7.5, 19);
  camera.lookAt(0, -0.1, 0);
  function resize(width, height) {
    material.uniforms.pixelRatio.value = Math.min(globalThis.devicePixelRatio || 1, 2);
    const aspect = Math.max(1, width) / Math.max(1, height);
    const viewWidth = Math.max(24, 8 * aspect);
    const viewHeight = viewWidth / aspect;
    camera.left = -viewWidth / 2;
    camera.right = viewWidth / 2;
    camera.top = viewHeight / 2;
    camera.bottom = -viewHeight / 2;
    camera.updateProjectionMatrix();
  }
  function dispose() {
    geometry.dispose();
    material.dispose();
    lineGeometry.dispose();
    lineMaterial.dispose();
    scene.clear();
  }
  return { scene, camera, resize, dispose };
}
