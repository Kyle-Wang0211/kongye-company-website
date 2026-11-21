import * as THREE from 'three';
import { OrbitControls } from './package/examples/jsm/controls/OrbitControls.js';

const canvas = document.querySelector('canvas');
const status = document.querySelector('#status');
const panel = document.querySelector('.controls');

async function load(url, reader) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response[reader]();
}

async function showModel() {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setClearColor(0xffffff);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  const [model, positions, edges] = await Promise.all([
    load('./tiles-20261121/model.json', 'json'),
    load('./tiles-20261121/positions.bin', 'arrayBuffer'),
    load('./tiles-20261121/edges.bin', 'arrayBuffer'),
  ]);
  if (positions.byteLength !== model.vertices * 12 || edges.byteLength !== model.indices * 4) {
    throw new Error('线框文件读取不完整');
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
  geometry.setIndex(new THREE.BufferAttribute(new Uint32Array(edges), 1));
  const bounds = new THREE.Box3(new THREE.Vector3(...model.min), new THREE.Vector3(...model.max));
  geometry.boundingBox = bounds;
  geometry.boundingSphere = bounds.getBoundingSphere(new THREE.Sphere());

  const opacity = { scan: 0.023, roof: 0.065, wall: 0.65 };
  const materials = model.groups.map((group, index) => {
    geometry.addGroup(group.start, group.count, index);
    return new THREE.LineBasicMaterial({
      color: 0x000000,
      transparent: true,
      opacity: opacity[group.name],
      depthTest: false,
      depthWrite: false,
    });
  });
  const wireframe = new THREE.LineSegments(geometry, materials);
  const scene = new THREE.Scene();
  scene.add(wireframe);

  const camera = new THREE.PerspectiveCamera(35, 1, 0.003, 80);
  const controls = new OrbitControls(camera, canvas);
  controls.touches.TWO = THREE.TOUCH.DOLLY_ROTATE;
  controls.rotateSpeed = 0.65;
  controls.minDistance = 0.06;
  controls.maxDistance = 35;
  controls.zoomToCursor = true;

  let pendingRender = 0;
  function requestRender() {
    if (pendingRender) return;
    pendingRender = requestAnimationFrame(() => {
      pendingRender = 0;
      renderer.render(scene, camera);
    });
  }
  controls.addEventListener('change', requestRender);

  function resetView() {
    const size = bounds.getSize(new THREE.Vector3());
    const center = bounds.getCenter(new THREE.Vector3());
    const verticalHalfAngle = THREE.MathUtils.degToRad(camera.fov * 0.5);
    const distance = Math.max(size.x / camera.aspect, size.y) / (2 * Math.tan(verticalHalfAngle));
    camera.position.copy(center).addScaledVector(new THREE.Vector3(0.18, 0.12, -1).normalize(), distance * 1.26);
    controls.target.copy(center);
    controls.update();
    requestRender();
  }
  function resize() {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    requestRender();
  }

  // Trackpads report a two-finger swipe as a wheel event. OrbitControls
  // supplies the rotation, and handles pinch/modified wheel as zoom.
  canvas.addEventListener('wheel', event => {
    if (event.ctrlKey || event.metaKey || event.deltaMode !== WheelEvent.DOM_DELTA_PIXEL) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const radiansPerPixel = Math.PI / canvas.clientHeight;
    controls.rotateLeft(event.deltaX * radiansPerPixel);
    controls.rotateUp(event.deltaY * radiansPerPixel);
  }, { capture: true, passive: false });

  canvas.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) return;
    event.preventDefault();
    if (event.key === 'ArrowLeft') controls.rotateLeft(0.12);
    if (event.key === 'ArrowRight') controls.rotateLeft(-0.12);
    if (event.key === 'ArrowUp') controls.rotateUp(0.12);
    if (event.key === 'ArrowDown') controls.rotateUp(-0.12);
  });
  panel.querySelector('button').addEventListener('click', resetView);
  window.addEventListener('resize', resize);
  resize();
  resetView();
  if (new URLSearchParams(location.search).has('detail')) {
    controls.target.set(0.49, 0.09, 0);
    const distance = 0.78 * Math.max(1, 1 / camera.aspect);
    camera.position.copy(controls.target)
      .addScaledVector(new THREE.Vector3(0.46, 0.19, -1).normalize(), distance);
    controls.update();
  }
  renderer.render(scene, camera);
  status.hidden = true;
  panel.hidden = false;
}

showModel().catch(error => {
  console.error(error);
  status.textContent = '线框加载失败，请刷新页面。';
});
