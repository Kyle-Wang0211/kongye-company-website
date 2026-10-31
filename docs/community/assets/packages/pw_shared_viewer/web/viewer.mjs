import { createSurfaceComments } from './surface_comments.mjs';
import { useOfficialTextureLoader } from './image_loader_lifecycle.mjs';
import { framingForObject, adjustedFoV } from './model_framing.mjs';
// Host/lifecycle adapter only. Rendering, loaders, materials and controls are upstream Three.js.
const ENGINE_VERSION = '0.186.1';
let officialDependencies;
const ownedScenes = new WeakMap();

async function dependencies() {
  officialDependencies ??= Promise.all([
    import('./vendor/three/build/three.module.js'),
    import('./vendor/three/examples/jsm/controls/OrbitControls.js'),
    import('./vendor/three/examples/jsm/loaders/GLTFLoader.js'),
    import('./vendor/three/examples/jsm/loaders/PLYLoader.js'),
  ]).then(([THREE, controls, gltf, ply]) => ({
    THREE, OrbitControls: controls.OrbitControls, GLTFLoader: gltf.GLTFLoader, PLYLoader: ply.PLYLoader,
  }));
  return officialDependencies;
}

export async function create(canvas, options = {}) {
  if (!canvas || typeof canvas.getContext !== 'function') throw new Error('A canvas is required');
  const context = canvas.getContext('webgl2', { antialias: true, alpha: false });
  if (!context) throw new Error('WebGL2 is unavailable on this device');
  return createViewerWithDependencies(canvas, { ...options, context }, await dependencies());
}

function materialsOf(node) {
  return Array.isArray(node.material) ? node.material : node.material ? [node.material] : [];
}

function texturesOf(material) {
  return Object.values(material).filter(value => value?.isTexture);
}

function disposeObject(object) {
  if (!object) return;
  const geometries = new Set(), materials = new Set(), textures = new Set(), skeletons = new Set();
  for (const root of ownedScenes.get(object) ?? [object]) root.traverse(node => {
    if (node.geometry) geometries.add(node.geometry);
    if (node.skeleton) skeletons.add(node.skeleton);
    for (const material of materialsOf(node)) {
      materials.add(material);
      for (const texture of texturesOf(material)) textures.add(texture);
    }
  });
  for (const geometry of geometries) geometry.dispose();
  for (const material of materials) material.dispose();
  const images = new Set();
  for (const texture of textures) {
    texture.dispose();
    if (texture.source?.data && typeof texture.source.data.close === 'function') images.add(texture.source.data);
  }
  for (const image of images) image.close();
  for (const skeleton of skeletons) skeleton.dispose?.();
}

function statistics(object) {
  let meshCount = 0, pointCount = 0, triangleCount = 0, normalMapCount = 0;
  const textures = new Set(), materials = new Set();
  object?.traverse(node => {
    const vertices = node.geometry?.getAttribute('position')?.count ?? 0;
    if (node.isMesh) {
      meshCount++;
      triangleCount += (node.geometry.index?.count ?? vertices) / 3;
    }
    if (node.isPoints) pointCount += vertices;
    for (const material of materialsOf(node)) materials.add(material);
  });
  for (const material of materials) {
    if (material.normalMap) normalMapCount++;
    for (const texture of texturesOf(material)) textures.add(texture);
  }
  const loadedTextureCount = [...textures].filter(texture => {
    const image = texture.image ?? texture.source?.data;
    return image && (image.width > 0 || image.height > 0 || image.data?.length > 0);
  }).length;
  return { meshCount, pointCount, triangleCount, materialCount: materials.size,
    textureCount: textures.size, loadedTextureCount, normalMapCount };
}

// Dependency injection is for lifecycle tests on machines without a GPU, not an alternative renderer.
export function createViewerWithDependencies(canvas, options = {}, api) {
  const { THREE, OrbitControls, GLTFLoader, PLYLoader } = api;
  const renderer = new THREE.WebGLRenderer({ canvas, context: options.context, antialias: true, alpha: false });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x000000);
  const camera = new THREE.PerspectiveCamera(45, 1, 0.001, 1000);
  camera.position.set(0, 0, 3);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.screenSpacePanning = true;
  const ambient = new THREE.AmbientLight(0xffffff, 2);
  const key = new THREE.DirectionalLight(0xffffff, 3);
  key.position.set(3, 5, 4);
  scene.add(ambient, key);
  const gltfLoader = new GLTFLoader(), plyLoader = new PLYLoader();
  useOfficialTextureLoader(gltfLoader, THREE);
  let current = null, request = 0, disposed = false, paused = false;
  let importAbort = null, importInfo = null;
  let framing = null, userHasInteracted = false;
  const framedFoVDeg = 45;
  // Selected product configuration: Google's documented external FramingInfo
  // fieldOfViewAspect=1 bounds both camera axes by the framing sphere. Keep the
  // separate geometry-derived idealAspect for the community card's shape.
  const fieldOfViewAspect = 1;
  let width = 1, height = 1, pixelRatio = 1, status = 'empty', error = null, url = null, format = null;

  const surfaceComments = createSurfaceComments({THREE, canvas, camera, controls,
    getModel: () => current, getFormat: () => format,
    getOverviewDistance: () => framing?.idealCameraDistance * 1.05,
    emit: (type, detail) => options.onSurfaceEvent?.(type, detail)});
  const assertActive = () => { if (disposed) throw new Error('Viewer is disposed'); };
  let lastAnimationTime = null, maxFps = 60;
  const render = time => {
    if (disposed) return;
    if (typeof time === 'number' && lastAnimationTime !== null && time - lastAnimationTime < 1000 / maxFps) return;
    const delta = typeof time === 'number' && lastAnimationTime !== null ? Math.max(0, (time - lastAnimationTime) / 1000) : 0;
    if (typeof time === 'number') lastAnimationTime = time;
    controls.update(delta); renderer.render(scene, camera); surfaceComments.update();
  };
  let background = 0x000000, pointSize = options.pointSize ?? 0.005, autoRotateUntilTouched = false;
  const stopOnTouch = () => {
    userHasInteracted = true;
    if (autoRotateUntilTouched) { controls.autoRotate = false; autoRotateUntilTouched = false; notify(); }
  };
  controls.addEventListener?.('start', stopOnTouch);
  const coordinates = vector => ({ x: vector.x, y: vector.y, z: vector.z });
  const getState = () => ({
    engine: 'three', engineVersion: ENGINE_VERSION, engineRevision: THREE.REVISION,
    bundleIdentity: options.bundleIdentity ?? null,
    importInfo, idealAspect: framing?.idealAspect ?? null,
    status, error, url, format, width, height, pixelRatio, paused, disposed,
    surfaceCommentMode: surfaceComments.enabled,
    background, pointSize, maxFps, interactionEnabled: controls.enabled !== false,
    autoRotate: controls.autoRotate === true, autoRotateUntilTouched,
    ...statistics(current), camera: { position: coordinates(camera.position), target: coordinates(controls.target),
      near: camera.near, far: camera.far },
  });
  const notify = () => {
    try { options.onStateChange?.(getState()); }
    catch (failure) { console.warn('Viewer state observer failed', failure); }
  };

  function fit(nextFraming) {
    if (!nextFraming) return;
    const { center, radius, idealCameraDistance } = nextFraming;
    controls.target.copy(center);
    // Use Google's adjustedFoV with its documented spherical framing default.
    // This retains containment at the host's existing orbit and at automatic
    // rotations, including flat geometry, with the existing 5% distance margin.
    camera.fov = adjustedFoV(framedFoVDeg, fieldOfViewAspect, camera.aspect);
    camera.position.copy(center).add(
      new THREE.Vector3(1.8, 1.2, 1.8).normalize().multiplyScalar(idealCameraDistance * 1.05));
    camera.near = Math.max(radius / 10000, 0.000001);
    camera.far = Math.max(radius * 1000, camera.near * 1000);
    camera.updateProjectionMatrix();
    controls.minDistance = camera.near * 2;
    controls.maxDistance = camera.far / 2;
    controls.update();
    controls.saveState();
  }

  async function load(input) {
    assertActive();
    surfaceComments.clear();
    const ticket = ++request;
    importAbort?.abort();
    const abort = new AbortController();
    importAbort = abort;
    status = 'loading'; error = null; notify();
    let candidate = null, replacementStarted = false, previous = null, cameraBefore = null;
    let candidateImportInfo = null;
    try {
      if (!input?.url || !['glb', 'ply', 'skp'].includes(input.format)) throw new Error('Unsupported model format; use glb, ply or skp');
      if (input.format === 'glb' || input.format === 'skp') {
        let gltf;
        if (input.format === 'skp') {
          const converter = options.convertSkpUrl ?? (await import('./skp_import.mjs')).convertSkpUrl;
          const converted = await converter(input.url, { signal: abort.signal });
          candidateImportInfo = { ...converted.info, fidelity: 'surface-preview-not-lossless-certified' };
          gltf = await gltfLoader.parseAsync(converted.bytes, '');
        } else gltf = await gltfLoader.loadAsync(input.url);
        candidate = gltf.scene;
        if (!candidate) throw new Error('GLB has no default scene');
        ownedScenes.set(candidate, gltf.scenes?.length ? gltf.scenes : [candidate]);
      } else {
        const geometry = await plyLoader.loadAsync(input.url);
        const colored = !!geometry.getAttribute('color');
        if (geometry.index) {
          if (!geometry.getAttribute('normal')) geometry.computeVertexNormals();
          candidate = new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({
            color: 0xffffff, vertexColors: colored, side: THREE.DoubleSide,
          }));
        } else {
          candidate = new THREE.Points(geometry, new THREE.PointsMaterial({
            color: 0xffffff, vertexColors: colored, size: pointSize, sizeAttenuation: true,
          }));
        }
      }
      if (disposed || ticket !== request) {
        disposeObject(candidate);
        return { status: 'superseded' };
      }
      // The old model remains until the complete upstream load succeeds.
      const candidateFraming = framingForObject(candidate, framedFoVDeg);
      previous = current;
      cameraBefore = { position: new THREE.Vector3().copy(camera.position),
        target: new THREE.Vector3().copy(controls.target), quaternion: camera.quaternion?.clone(),
        fov: camera.fov, near: camera.near, far: camera.far, minDistance: controls.minDistance, maxDistance: controls.maxDistance };
      replacementStarted = true;
      const shouldFit = !previous || !input.preserveCamera;
      if (shouldFit) fit(candidateFraming);
      scene.add(candidate);
      if (previous) scene.remove(previous);
      render();
      current = candidate; url = input.url; format = input.format; status = 'ready'; error = null;
      importInfo = candidateImportInfo;
      framing = candidateFraming;
      if (shouldFit) userHasInteracted = false;
      replacementStarted = false;
      disposeObject(previous);
      notify();
      return { ...getState(), status: 'loaded' };
    } catch (failure) {
      if (replacementStarted) {
        scene.remove(candidate);
        if (previous) scene.add(previous);
        camera.position.copy(cameraBefore.position);
        controls.target.copy(cameraBefore.target);
        if (cameraBefore.quaternion) camera.quaternion.copy(cameraBefore.quaternion);
        camera.fov = cameraBefore.fov;
        camera.near = cameraBefore.near; camera.far = cameraBefore.far;
        controls.minDistance = cameraBefore.minDistance; controls.maxDistance = cameraBefore.maxDistance;
        camera.updateProjectionMatrix();
        try { render(); } catch { /* A lost context can also prevent restoring the old frame. */ }
      }
      if (candidate && candidate !== current) disposeObject(candidate);
      if (disposed || ticket !== request) return { status: 'superseded' };
      status = 'error'; error = failure instanceof Error ? failure.message : String(failure);
      notify(); throw failure;
    } finally {
      if (importAbort === abort) importAbort = null;
    }
  }

  function configure(config = {}) {
    assertActive();
    for (const key of ['interactive', 'autoRotate', 'autoRotateUntilTouched']) {
      if (key in config && typeof config[key] !== 'boolean') throw new Error(`Invalid ${key}`);
    }
    if ('maxFps' in config && (!Number.isFinite(config.maxFps) || config.maxFps < 1 || config.maxFps > 60)) throw new Error('Invalid frame budget');
    if ('background' in config && (!Number.isInteger(config.background) || config.background < 0 || config.background > 0xffffff)) throw new Error('Invalid background');
    if ('pointSize' in config && (!Number.isFinite(config.pointSize) || config.pointSize <= 0)) throw new Error('Invalid point size');
    if ('autoRotateSpeed' in config && !Number.isFinite(config.autoRotateSpeed)) throw new Error('Invalid rotation speed');
    if ('maxFps' in config) maxFps = config.maxFps;
    if ('interactive' in config) controls.enabled = config.interactive;
    if ('autoRotate' in config) controls.autoRotate = config.autoRotate;
    if ('autoRotateUntilTouched' in config) autoRotateUntilTouched = config.autoRotateUntilTouched;
    if (surfaceComments.enabled) { controls.autoRotate = false; autoRotateUntilTouched = false; }
    if ('autoRotateSpeed' in config) controls.autoRotateSpeed = config.autoRotateSpeed;
    if ('background' in config) { background = config.background; scene.background = new THREE.Color(background); }
    if ('pointSize' in config) {
      pointSize = config.pointSize;
      current?.traverse(node => { if (node.isPoints) for (const material of materialsOf(node)) material.size = pointSize; });
    }
    render(); notify(); return getState();
  }
  function resetCamera() {
    assertActive(); controls.reset?.(); userHasInteracted = false;
    if (framing) camera.fov = adjustedFoV(framedFoVDeg, fieldOfViewAspect, camera.aspect);
    camera.updateProjectionMatrix(); render(); notify(); return getState();
  }

  function resize(nextWidth = canvas.clientWidth, nextHeight = canvas.clientHeight, nextPixelRatio = options.pixelRatio ?? globalThis.devicePixelRatio ?? 1) {
    assertActive();
    width = Math.max(1, Math.floor(Number(nextWidth) || 1));
    height = Math.max(1, Math.floor(Number(nextHeight) || 1));
    pixelRatio = Math.max(0.25, Math.min(3, Number(nextPixelRatio) || 1));
    renderer.setPixelRatio(pixelRatio);
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    // Before interaction, follow Google's viewport framing without moving the
    // center/orbit. Once the user starts controls, preserve their orbit and zoom.
    if (framing && !userHasInteracted) {
      camera.fov = adjustedFoV(framedFoVDeg, fieldOfViewAspect, camera.aspect);
    }
    camera.updateProjectionMatrix(); render(); notify();
  }
  function capture(type = 'image/png', quality) {
    assertActive(); render();
    return renderer.domElement.toDataURL(type, quality);
  }
  function pause() { assertActive(); lastAnimationTime = null; paused = true; renderer.setAnimationLoop(null); notify(); }
  function resume() { assertActive(); lastAnimationTime = null; paused = false; renderer.setAnimationLoop(render); notify(); }
  function dispose() {
    if (disposed) return;
    disposed = true; request++; renderer.setAnimationLoop(null);
    importAbort?.abort(); importAbort = null;
    controls.removeEventListener?.('start', stopOnTouch);
    surfaceComments.dispose();
    controls.dispose();
    if (current) scene.remove(current);
    disposeObject(current); current = null; framing = null;
    renderer.dispose(); status = 'disposed'; notify();
  }
  function setSurfaceCommentMode(enabled) {
    assertActive(); surfaceComments.setMode(enabled);
    if (enabled) { autoRotateUntilTouched = false; userHasInteracted = true; }
    render(); notify();
  }
  function setSurfaceCommentMarkers(markers) { assertActive(); surfaceComments.setMarkers(markers); render(); }
  function focusSurfaceComment(anchor) {
    assertActive(); surfaceComments.focus(anchor); autoRotateUntilTouched = false; userHasInteracted = true; render(); notify();
  }
  resize(); resume();
  return { setSurfaceCommentMode, setSurfaceCommentMarkers, focusSurfaceComment, load, configure, resetCamera, resize, capture, pause, resume, dispose, getState };
}

if (typeof window !== 'undefined') window.PWSharedViewer = Object.freeze({ create, engineVersion: ENGINE_VERSION });
