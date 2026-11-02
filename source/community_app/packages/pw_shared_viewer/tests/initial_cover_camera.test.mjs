import test from 'node:test';
import assert from 'node:assert/strict';
import * as RealTHREE from '../web/vendor/three/build/three.module.js';
import { createViewerWithDependencies } from '../web/viewer.mjs';

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
function fixture(){
  const pending=new Map();let renderer,camera,controls;
  class Loader {register(factory){this.pluginFactory=factory;return this;}loadAsync(url){const d=deferred();pending.set(url,d);return d.promise;}}
  class Renderer {
    constructor({canvas}){renderer=this;this.domElement=canvas;this.capabilities={isWebGL2:true};this.renders=0;this.disposals=0;}
    setSize(w,h,style){this.size=[w,h,style];}
    setPixelRatio(r){this.ratio=r;}
    setAnimationLoop(fn){this.loop=fn;}
    render(scene, camera){this.renders++;this.frames??=[];this.frames.push({position:camera.position.toArray(),quaternion:camera.quaternion.toArray(),up:camera.up.toArray(),fov:camera.fov,aspect:camera.aspect,zoom:camera.zoom,projection:camera.projectionMatrix.toArray()});}
    dispose(){this.disposals++;}
  }
  class Camera extends RealTHREE.PerspectiveCamera {constructor(...args){super(...args);camera=this;}updateProjectionMatrix(){super.updateProjectionMatrix();this.updated=true;}}
  class Controls {
    constructor(camera){controls=this;this.camera=camera;this.target=new Vec();this.disposals=0;this.events=new Map();}
    update(){this.camera.lookAt(this.target);this.camera.updateMatrixWorld();}
    dispose(){this.disposals++;}saveState(){this.saved=true;}
    addEventListener(name,fn){this.events.set(name,fn);}removeEventListener(name){this.events.delete(name);}
    start(){this.events.get('start')?.();}
  }
  const THREE={...RealTHREE,REVISION:'186',WebGLRenderer:Renderer,Scene:Object3D,PerspectiveCamera:Camera,
    AmbientLight:Object3D,DirectionalLight:Object3D,Vector3:Vec,Mesh,Points,
    MeshStandardMaterial:Material,PointsMaterial:Material};
  const pointerEvents=new Map();
  const canvas={clientWidth:320,clientHeight:200,toDataURL:type=>{renderer.captured=renderer.frames.at(-1);return `data:${type};base64,ok`;},
    addEventListener:(k,v)=>pointerEvents.set(k,v),removeEventListener:k=>pointerEvents.delete(k),
    getBoundingClientRect:()=>({left:0,top:0,width:320,height:200})};
  const api={THREE,OrbitControls:Controls,GLTFLoader:Loader,PLYLoader:Loader};
  const viewer=createViewerWithDependencies(canvas,{pixelRatio:2},api);
  return {viewer,pending,canvas,renderer,camera,controls,pointerEvents};
}
function glb(){
  const scene=new Object3D();const texture={isTexture:true,image:{width:8,height:8},disposals:0,dispose(){this.disposals++;}};
  const material=new Material({map:texture,normalMap:texture});const geometry=new Geometry(true);
  const mesh=new Mesh(geometry,material);scene.add(mesh);
  return {scene,material,geometry,texture};
}


test('canonical cover equals initial viewer pose and projection at all viewport aspects', async()=>{
  for(const [w,h] of [[320,320],[320,720],[720,320]]) {
    const {viewer,pending,renderer,camera,controls}=fixture();
    viewer.resize(w,h,1);
    const asset=glb();
    const load=viewer.load({url:'same.glb',format:'glb'});
    pending.get('same.glb').resolve(asset);await load;
    const initial=renderer.frames.at(-1);
    viewer.capture('image/png',undefined,true);
    assert.deepEqual(renderer.captured,initial);
    const position = asset.geometry.getAttribute('position');
    for(let i=0;i<position.count;i++) {
      const projected = new Vec().fromBufferAttribute(position,i).project(camera);
      assert.ok(Math.abs(projected.x)<=1 && Math.abs(projected.y)<=1);
    }
    camera.position.set(17,23,-18);controls.target.set(4,3,2);camera.zoom=1.7;
    controls.start();controls.update();camera.updateProjectionMatrix();
    const before=viewer.getState().camera;
    viewer.capture('image/png',undefined,true);
    assert.deepEqual(renderer.captured,initial);
    assert.deepEqual(viewer.getState().camera,before);
    assert.equal(camera.zoom,1.7);
    assert.deepEqual(renderer.frames.at(-1).position,[17,23,-18]);
    viewer.dispose();
  }
});

test('new producer geometry gets its own canonical fit while user orbit stays intact',async()=>{
  const {viewer,pending,renderer,camera,controls}=fixture();
  const first=viewer.load({url:'sparse.ply',format:'ply'});
  pending.get('sparse.ply').resolve(new Geometry());await first;
  camera.position.set(1,2,30);controls.start();controls.update();
  const user=viewer.getState().camera;
  const second=viewer.load({url:'dense.ply',format:'ply',preserveCamera:true});
  const dense=new Geometry();dense.translate(100,0,0);
  pending.get('dense.ply').resolve(dense);await second;
  assert.deepEqual(viewer.getState().camera,user);
  viewer.capture('image/png',undefined,true);
  assert.ok(renderer.captured.position[0]>100);
  assert.deepEqual(viewer.getState().camera,user);
  viewer.dispose();
});
