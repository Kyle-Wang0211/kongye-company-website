import test from 'node:test';
import assert from 'node:assert/strict';
import * as RealTHREE from '../web/vendor/three/build/three.module.js';
import { createViewerWithDependencies } from '../web/viewer.mjs';
import { adjustedFoV } from '../web/model_framing.mjs';

class Vec extends RealTHREE.Vector3 {}
class Object3D extends RealTHREE.Object3D {}
class Geometry extends RealTHREE.BufferGeometry {
  constructor(indexed=false){super();this.setAttribute('position',new RealTHREE.Float32BufferAttribute([
    -4,3,4, 8,3,4, 2,-3,4, 2,9,4, 2,3,-2, 2,3,10,
  ],3));if(indexed)this.setIndex([0,1,2,3,4,5]);this.disposals=0;}
  computeVertexNormals(){this.normals=true;super.computeVertexNormals();}
  dispose(){this.disposals++;super.dispose();}
}
class Material {
  constructor(props={}){Object.assign(this,props);this.disposals=0;}
  dispose(){this.disposals++;}
}
class Mesh extends RealTHREE.Mesh {}
class Points extends RealTHREE.Points {}
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};}
function fixture(options = {}){
  const pending=new Map();let renderer,camera,controls;
  class Loader {register(factory){this.pluginFactory=factory;return this;}loadAsync(url,onProgress){const d=deferred();d.progress=onProgress;pending.set(url,d);return d.promise;}}
  class Renderer {
    constructor({canvas}){renderer=this;this.domElement=canvas;this.capabilities={isWebGL2:true};this.renders=0;this.disposals=0;}
    setSize(w,h,style){this.size=[w,h,style];}
    setPixelRatio(r){this.ratio=r;}
    setAnimationLoop(fn){this.loop=fn;}
    render(){this.renders++;}
    dispose(){this.disposals++;}
  }
  class Camera extends RealTHREE.PerspectiveCamera {constructor(...args){super(...args);camera=this;}updateProjectionMatrix(){super.updateProjectionMatrix();this.updated=true;}}
  class Controls {
    constructor(camera){controls=this;this.camera=camera;this.target=new Vec();this.disposals=0;this.events=new Map();}
    update(){this.camera.lookAt(this.target);this.camera.updateMatrixWorld();}
    dispose(){this.disposals++;}saveState(){this.saved=true;this.savedPosition=this.camera.position.clone();this.savedTarget=this.target.clone();}reset(){if(this.savedPosition)this.camera.position.copy(this.savedPosition);if(this.savedTarget)this.target.copy(this.savedTarget);this.update();}
    addEventListener(name,fn){this.events.set(name,fn);}removeEventListener(name){this.events.delete(name);}
    start(){this.events.get('start')?.();}
  }
  const THREE={...RealTHREE,REVISION:'186',WebGLRenderer:Renderer,Scene:Object3D,PerspectiveCamera:Camera,
    AmbientLight:Object3D,DirectionalLight:Object3D,Vector3:Vec,Mesh,Points,
    MeshStandardMaterial:Material,PointsMaterial:Material};
  const pointerEvents=new Map();
  const canvas={clientWidth:320,clientHeight:200,toDataURL:type=>`data:${type};base64,ok`,
    addEventListener:(k,v)=>pointerEvents.set(k,v),removeEventListener:k=>pointerEvents.delete(k),
    getBoundingClientRect:()=>({left:0,top:0,width:320,height:200})};
  const api={THREE,OrbitControls:Controls,GLTFLoader:Loader,PLYLoader:Loader};
  const viewer=createViewerWithDependencies(canvas,{pixelRatio:2,...options},api);
  return {viewer,pending,canvas,renderer,camera,controls,pointerEvents};
}
function glb(){
  const scene=new Object3D();const texture={isTexture:true,image:{width:8,height:8},disposals:0,dispose(){this.disposals++;}};
  const material=new Material({map:texture,normalMap:texture});const geometry=new Geometry(true);
  const mesh=new Mesh(geometry,material);scene.add(mesh);
  return {scene,material,geometry,texture};
}

test('GLB retains upstream materials and reports normal maps; failed replacement retains old scene',async()=>{
  const {viewer,pending}=fixture();const asset=glb();const load=viewer.load({url:'one.glb',format:'glb'});
  pending.get('one.glb').resolve(asset);assert.equal((await load).status,'loaded');
  assert.equal(viewer.getState().meshCount,1);assert.equal(viewer.getState().normalMapCount,1);
  assert.equal(viewer.getState().textureCount,1);assert.equal(viewer.getState().loadedTextureCount,1);assert.equal(asset.material.disposals,0);
  const failed=viewer.load({url:'bad.glb',format:'glb'});pending.get('bad.glb').reject(new Error('broken'));
  await assert.rejects(failed,/broken/);assert.equal(viewer.getState().url,'one.glb');
  assert.equal(viewer.getState().meshCount,1);assert.equal(asset.geometry.disposals,0);
  viewer.dispose();assert.equal(asset.geometry.disposals,1);assert.equal(asset.material.disposals,1);assert.equal(asset.texture.disposals,1);
});

test('latest request wins and stale assets are disposed without replacing visible content',async()=>{
  const {viewer,pending}=fixture();const old=glb(),latest=glb();
  const a=viewer.load({url:'slow.glb',format:'glb'}),b=viewer.load({url:'fast.glb',format:'glb'});
  pending.get('fast.glb').resolve(latest);await b;pending.get('slow.glb').resolve(old);
  assert.equal((await a).status,'superseded');assert.equal(viewer.getState().url,'fast.glb');
  assert.equal(old.geometry.disposals,1);assert.equal(latest.geometry.disposals,0);viewer.dispose();
});

test('PLY point to indexed mesh transition preserves camera only when requested',async()=>{
  const {viewer,pending}=fixture();const p=viewer.load({url:'cloud.ply',format:'ply'});
  pending.get('cloud.ply').resolve(new Geometry(false));await p;
  assert.equal(viewer.getState().pointCount,6);assert.equal(viewer.getState().meshCount,0);
  const before=viewer.getState().camera;
  const m=viewer.load({url:'mesh.ply',format:'ply',preserveCamera:true});const geometry=new Geometry(true);
  pending.get('mesh.ply').resolve(geometry);await m;
  assert.equal(viewer.getState().meshCount,1);assert.equal(viewer.getState().triangleCount,2);
  assert.deepEqual(viewer.getState().camera,before);assert.equal(geometry.normals,true);viewer.dispose();
});

test('resize, capture, pause/resume and idempotent dispose have explicit lifecycle',()=>{
  const {viewer}=fixture();viewer.resize(500,250,1.5);assert.equal(viewer.getState().width,500);
  assert.equal(viewer.getState().height,250);viewer.pause();assert.equal(viewer.getState().paused,true);
  assert.equal(viewer.capture(), 'data:image/png;base64,ok');viewer.resume();assert.equal(viewer.getState().paused,false);
  viewer.dispose();viewer.dispose();assert.equal(viewer.getState().disposed,true);
  assert.throws(()=>viewer.capture(),/disposed/);assert.throws(()=>viewer.resize(10,10),/disposed/);
});

test('dispose during pending load discards and frees late resources',async()=>{
  const {viewer,pending}=fixture();const asset=glb();const p=viewer.load({url:'late.glb',format:'glb'});
  viewer.dispose();pending.get('late.glb').resolve(asset);assert.equal((await p).status,'superseded');
  assert.equal(asset.geometry.disposals,1);assert.equal(asset.texture.disposals,1);
});

test('invalid replacement format reports error and keeps previously loaded asset',async()=>{
  const {viewer,pending}=fixture();const p=viewer.load({url:'valid.glb',format:'glb'});pending.get('valid.glb').resolve(glb());await p;
  await assert.rejects(viewer.load({url:'unsupported.obj',format:'obj'}),/Unsupported/);
  assert.equal(viewer.getState().url,'valid.glb');viewer.dispose();
});


test('a GPU submission failure during replacement rolls back to the intact old artifact and camera',async()=>{
  const {viewer,pending,renderer}=fixture();const old=glb(),replacement=glb();
  const first=viewer.load({url:'old.glb',format:'glb'});pending.get('old.glb').resolve(old);await first;
  const before=viewer.getState().camera;const render=renderer.render.bind(renderer);let fail=true;
  renderer.render=()=>{if(fail){fail=false;throw new Error('GPU submission failed');}render();};
  const next=viewer.load({url:'replacement.glb',format:'glb'});pending.get('replacement.glb').resolve(replacement);
  await assert.rejects(next,/GPU submission failed/);
  assert.equal(viewer.getState().url,'old.glb');assert.deepEqual(viewer.getState().camera,before);
  assert.equal(old.geometry.disposals,0);assert.equal(replacement.geometry.disposals,1);viewer.dispose();
});


function assertVisible(geometry, camera, object = new RealTHREE.Object3D()) {
  camera.updateMatrixWorld();object.updateWorldMatrix(true,true);
  const vertices=geometry.getAttribute('position');
  for(let index=0;index<vertices.count;index++) {
    const vertex=new RealTHREE.Vector3().fromBufferAttribute(vertices,index).applyMatrix4(object.matrixWorld).project(camera);
    assert.ok(Math.abs(vertex.x)<=1 && Math.abs(vertex.y)<=1 && Math.abs(vertex.z)<=1, `clipped vertex: ${vertex.toArray()}`);
  }
}
for (const [width,height] of [[200,400],[100,400],[800,400]]) {
  test(`initial framing contains real geometry at ${width}x${height}`,async()=>{
    const {viewer,pending,camera}=fixture();viewer.resize(width,height);
    const asset=glb();const load=viewer.load({url:'framed.glb',format:'glb'});pending.get('framed.glb').resolve(asset);await load;
    assertVisible(asset.geometry,camera);viewer.dispose();
  });
}

test('loaded aspect is finite geometry state; untouched resizing reframes without changing center or orbit',async()=>{
  const {viewer,pending,camera,controls}=fixture();
  assert.equal(viewer.getState().idealAspect,null);
  const asset=glb();const load=viewer.load({url:'framed.glb',format:'glb'});pending.get('framed.glb').resolve(asset);await load;
  const idealAspect=viewer.getState().idealAspect;
  assert.ok(Number.isFinite(idealAspect) && idealAspect>0);
  const position=camera.position.clone(), target=controls.target.clone();
  for(const [w,h] of [[180,600],[800,150],[300,400]]) {
    viewer.resize(w,h);assertVisible(asset.geometry,camera);
    assert.deepEqual(camera.position,position);assert.deepEqual(controls.target,target);
    assert.equal(viewer.getState().idealAspect,idealAspect);
  }
  camera.position.set(12,15,29);controls.update();
  assert.equal(viewer.getState().idealAspect,idealAspect);viewer.dispose();
});

test('resize preserves the current user orbit instead of silently reframing the model',async()=>{
  const {viewer,pending,camera,controls}=fixture();
  const load=viewer.load({url:'framed.glb',format:'glb'});pending.get('framed.glb').resolve(glb());await load;
  controls.start();camera.position.set(12,15,29);controls.target.set(4,6,9);
  const before=viewer.getState().camera;viewer.resize(180,600);
  assert.deepEqual(viewer.getState().camera,before);assert.equal(camera.aspect,0.3);viewer.dispose();
});

test('product configuration delegates interaction and rotation to upstream controls', async()=>{
 const f=fixture();
 f.viewer.configure({interactive:false,autoRotate:true,autoRotateSpeed:0.7,background:0x123456,pointSize:0.012});
 assert.equal(f.controls.enabled,false);assert.equal(f.controls.autoRotate,true);assert.equal(f.controls.autoRotateSpeed,0.7);
 assert.equal(f.viewer.getState().interactionEnabled,false);assert.equal(f.viewer.getState().background,0x123456);
 const loaded=f.viewer.load({url:'points.ply',format:'ply'});
 f.pending.get('points.ply').resolve(new Geometry(false));await loaded;
 assert.equal(f.viewer.getState().pointSize,0.012);
 assert.throws(()=>f.viewer.configure({pointSize:-1}));
 f.viewer.dispose();
});

for(const [label,dimensions] of [['tall',[1,8,1]],['wide',[8,1,3]],['cube',[2,2,2]],['flat-XZ',[8,0.05,8]]]) {
  test(`${label} runtime geometry stays contained across viewport changes and automatic orbits`,async()=>{
    const {viewer,pending,camera,controls}=fixture();
    const scene=new RealTHREE.Group();scene.add(new RealTHREE.Mesh(new RealTHREE.BoxGeometry(...dimensions),new Material()));
    scene.position.set(10,-5,7);
    const load=viewer.load({url:`${label}.glb`,format:'glb'});pending.get(`${label}.glb`).resolve({scene});await load;
    assertVisible(scene.children[0].geometry,camera,scene.children[0]);
    const aspect=viewer.getState().idealAspect, target=controls.target.clone();
    assert.deepEqual(target.toArray(),[10,-5,7]);
    const distance=camera.position.distanceTo(target);
    for(const [w,h] of [[150,600],[800,200],[300,400]]) {
      viewer.resize(w,h);
      const verticalHalfFov=RealTHREE.MathUtils.degToRad(camera.fov)/2;
      const horizontalHalfFov=Math.atan(Math.tan(verticalHalfFov)*camera.aspect);
      assert.ok(Math.min(verticalHalfFov,horizontalHalfFov)>=Math.PI/8-1e-12,
        'documented spherical framing keeps both FOV axes at least the base framing angle');
      for(const [theta,phi] of [[0,0.1],[1,Math.PI/2],[4,Math.PI-0.1]]) {
        camera.position.setFromSphericalCoords(distance,phi,theta).add(target);controls.update();
        assertVisible(scene.children[0].geometry,camera,scene.children[0]);
        assert.equal(viewer.getState().idealAspect,aspect);
      }
    }
    controls.start();camera.zoom=2.3;camera.position.addScalar(0.25);controls.target.addScalar(0.5);
    const position=camera.position.clone(),userTarget=controls.target.clone(),fov=camera.fov;
    viewer.resize(100,900);
    assert.equal(camera.fov,fov);assert.equal(camera.zoom,2.3);
    assert.deepEqual(camera.position,position);assert.deepEqual(controls.target,userTarget);
    viewer.dispose();assert.equal(viewer.getState().idealAspect,null);
  });
}

test('empty loaded geometry has null aspect and failed replacement retains previous framing',async()=>{
  const {viewer,pending,renderer,camera}=fixture();
  const first=viewer.load({url:'valid.glb',format:'glb'});pending.get('valid.glb').resolve(glb());await first;
  const original=viewer.getState().idealAspect, fov=camera.fov;
  const render=renderer.render.bind(renderer);let fail=true;
  renderer.render=()=>{if(fail){fail=false;throw new Error('submit');}render();};
  const next=viewer.load({url:'tall.glb',format:'glb'});
  const scene=new RealTHREE.Group();scene.add(new RealTHREE.Mesh(new RealTHREE.BoxGeometry(1,20,1),new Material()));
  pending.get('tall.glb').resolve({scene});await assert.rejects(next,/submit/);
  assert.equal(viewer.getState().idealAspect,original);assert.equal(camera.fov,fov);
  const empty=viewer.load({url:'empty.glb',format:'glb'});pending.get('empty.glb').resolve({scene:new RealTHREE.Group()});await empty;
  assert.equal(viewer.getState().idealAspect,null);viewer.dispose();
});

test('surface mode preserves loaded model and controls, focus camera and lifecycle cleanup',async()=>{
 const f=fixture();const asset=glb();const first=f.viewer.load({url:'surface.glb',format:'glb'});f.pending.get('surface.glb').resolve(asset);await first;
 const before=f.viewer.getState().camera;
 f.viewer.configure({autoRotate:true,autoRotateUntilTouched:true});
 f.viewer.setSurfaceCommentMode(true);assert.equal(f.viewer.getState().surfaceCommentMode,true);assert.equal(f.controls.autoRotate,false);
 f.viewer.configure({autoRotate:true});assert.equal(f.controls.autoRotate,false);
 f.viewer.setSurfaceCommentMarkers([{id:'one',number:1,anchor:{position:[0,0,0]}}]);
 f.viewer.setSurfaceCommentMode(false);assert.deepEqual(f.viewer.getState().camera,before);assert.equal(asset.geometry.disposals,0);
 f.viewer.focusSurfaceComment({position:[0,0,0],cameraPosition:[9,8,7],cameraTarget:[2,3,4]});
 assert.deepEqual(f.viewer.getState().camera.position,{x:9,y:8,z:7});assert.deepEqual(f.viewer.getState().camera.target,{x:2,y:3,z:4});
 const cloud=f.viewer.load({url:'cloud.ply',format:'ply'});f.pending.get('cloud.ply').resolve(new Geometry());await cloud;
 assert.equal(f.viewer.getState().surfaceCommentMode,false);f.viewer.setSurfaceCommentMode(true);assert.equal(f.viewer.getState().surfaceCommentMode,true);
 f.viewer.dispose();assert.equal(f.pointerEvents.size,0);
});


test('official loader byte progress retains URL semantics and ignores superseded callbacks',async()=>{
 const events=[],responses=[];
 const f=fixture({onDownloadProgress:p=>events.push(p)});
 const original='https://assets.example/models/scene.glb?token=test';
 const a=f.viewer.load({url:original,format:'glb'},p=>responses.push(p));
 const first=f.pending.get(original);
 first.progress({loaded:2,total:8,lengthComputable:true});
 assert.deepEqual(events,[{receivedBytes:2,totalBytes:8}]);
 assert.deepEqual(responses,events);
 const b=f.viewer.load({url:'second.glb',format:'glb'});
 first.progress({loaded:8,total:8,lengthComputable:true});
 assert.equal(events.length,1);
 f.pending.get('second.glb').progress({loaded:3,total:0,lengthComputable:false});
 assert.deepEqual(events.at(-1),{receivedBytes:3,totalBytes:null});
 f.pending.get('second.glb').resolve(glb());await b;
 first.resolve(glb());await a;
 f.viewer.dispose();
 first.progress({loaded:8,total:8,lengthComputable:true});
 assert.equal(events.length,2);
});

test('publication camera framing roundtrips official perspective camera and validates before mutation',async()=>{
 const f=fixture();const loading=f.viewer.load({url:'publication.glb',format:'glb'});
 f.pending.get('publication.glb').resolve(glb());await loading;
 const original=f.viewer.getCameraFraming();
 const selected={projection:'perspective',position:[12,8,16],target:[1,2,3],up:[0,1,0],fov_y_degrees:55,aspect:1.5};
 f.viewer.setCameraFraming(selected);
 const actual=f.viewer.getCameraFraming();
 assert.deepEqual(actual.position,selected.position);assert.deepEqual(actual.target,selected.target);
 assert.equal(actual.fov_y_degrees,55);assert.equal(actual.projection,'perspective');
 for(const mutation of [{position:[NaN,0,0]},{fov_y_degrees:180},{up:[0,0,0]},{position:[1,2,3]},{aspect:0}]) {
   assert.throws(()=>f.viewer.setCameraFraming({...selected,...mutation}),/camera/i);
   assert.deepEqual(f.viewer.getCameraFraming(),actual);
 }
 f.viewer.resetCamera();assert.notDeepEqual(f.viewer.getCameraFraming().position,selected.position);
 assert.deepEqual(f.viewer.getCameraFraming().target,original.target);f.viewer.dispose();
});


test('explicit camera FOV survives resize without inventing interaction and clears on reset or new fit',async()=>{
 const f=fixture();f.viewer.resize(600,400);
 const first=f.viewer.load({url:'framing-first.glb',format:'glb'});
 f.pending.get('framing-first.glb').resolve(glb());await first;
 const selected={projection:'perspective',position:[12,8,16],target:[1,2,3],up:[0,1,0],fov_y_degrees:55,aspect:1.5};
 f.viewer.setCameraFraming(selected);assert.equal(f.viewer.getState().userHasInteracted,false);
 f.viewer.resize(400,600);
 assert.equal(f.viewer.getCameraFraming().fov_y_degrees,55);
 assert.deepEqual(f.viewer.getCameraFraming().position,selected.position);
 assert.equal(f.viewer.getState().userHasInteracted,false);
 f.viewer.resetCamera();assert.equal(f.viewer.getCameraFraming().fov_y_degrees,adjustedFoV(45,1,400/600));
 f.viewer.resize(800,400);assert.equal(f.viewer.getCameraFraming().fov_y_degrees,45);
 f.viewer.setCameraFraming(selected);
 const retained=f.viewer.load({url:'framing-preserved.glb',format:'glb',preserveCamera:true});
 f.pending.get('framing-preserved.glb').resolve(glb());await retained;
 f.viewer.resize(400,600);assert.equal(f.viewer.getCameraFraming().fov_y_degrees,55);
 const replacement=f.viewer.load({url:'framing-new.glb',format:'glb'});
 f.pending.get('framing-new.glb').resolve(glb());await replacement;
 assert.equal(f.viewer.getCameraFraming().fov_y_degrees,adjustedFoV(45,1,400/600));
 f.viewer.resize(800,400);assert.equal(f.viewer.getCameraFraming().fov_y_degrees,45);
 assert.equal(f.viewer.getState().userHasInteracted,false);f.viewer.dispose();
});
