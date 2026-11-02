import test from 'node:test';
import assert from 'node:assert/strict';
import * as RealTHREE from '../web/vendor/three/build/three.module.js';
import { readFileSync } from 'node:fs';
const controlsPath=new URL('../web/vendor/three/examples/jsm/controls/OrbitControls.js',import.meta.url);
const threePath=new URL('../web/vendor/three/build/three.module.js',import.meta.url).href;
const controlsSource=readFileSync(controlsPath,'utf8').replace("from 'three'","from '"+threePath+"'");
const {OrbitControls: RealOrbitControls}=await import('data:text/javascript;base64,'+Buffer.from(controlsSource).toString('base64'));
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
    render(){this.renders++;}
    dispose(){this.disposals++;}
  }
  class Camera extends RealTHREE.PerspectiveCamera {constructor(...args){super(...args);camera=this;}updateProjectionMatrix(){super.updateProjectionMatrix();this.updated=true;}}
  class Controls extends RealOrbitControls {constructor(camera,element){super(camera,element);controls=this;}}
  const THREE={...RealTHREE,REVISION:'186',WebGLRenderer:Renderer,Scene:Object3D,PerspectiveCamera:Camera,
    AmbientLight:Object3D,DirectionalLight:Object3D,Vector3:Vec,Mesh,Points,
    MeshStandardMaterial:Material,PointsMaterial:Material};
  const pointerEvents=new Map();
  const document={createElement(){return null;},addEventListener(){},removeEventListener(){}};
  const canvas={style:{},ownerDocument:document,getRootNode:()=>document,
    setPointerCapture(){},releasePointerCapture(){},
    clientWidth:320,clientHeight:200,toDataURL:type=>`data:${type};base64,ok`,
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


for (const [name,button] of [['rotate',0],['pan',2],['dolly',1]]) {
  test(name+' applies direct pointer delta and is exactly stationary when input stops', async()=>{
    const {viewer,pending,renderer,camera,controls}=fixture();
    viewer.resize(320,200,1);
    const load=viewer.load({url:'model.glb',format:'glb'});
    pending.get('model.glb').resolve(glb());await load;
    viewer.configure({interactive:true,autoRotate:false});
    const sample=()=>({position:camera.position.toArray(),quaternion:camera.quaternion.toArray(),
      target:controls.target.toArray(),zoom:camera.zoom,projection:camera.projectionMatrix.toArray()});
    const before=sample();
    const event=(x,y)=>({pointerId:1,pointerType:'mouse',button,
      clientX:x,clientY:y,pageX:x,pageY:y,ctrlKey:false,metaKey:false,shiftKey:false,preventDefault(){}});
    controls._onPointerDown(event(120,80));
    controls._onPointerMove(event(175,110));
    const stopped=sample();
    assert.notDeepEqual(stopped,before,'actual input must move the camera immediately');
    // Finger remains down but no longer moves: no animation integration.
    for(let frame=1;frame<=30;frame++){renderer.loop(frame*20);assert.deepEqual(sample(),stopped);}
    controls._onPointerUp(event(175,110));
    for(let frame=31;frame<=90;frame++){renderer.loop(frame*20);assert.deepEqual(sample(),stopped);}
    viewer.dispose();
  });
}

test('wheel zoom stops on its input event and touch stops preview autorotation',async()=>{
  const {viewer,pending,renderer,camera,controls}=fixture();
  const load=viewer.load({url:'model.glb',format:'glb'});
  pending.get('model.glb').resolve(glb());await load;
  viewer.configure({interactive:true,autoRotate:true,autoRotateUntilTouched:true});
  controls._onMouseWheel({clientX:100,clientY:100,deltaY:-120,deltaMode:0,ctrlKey:false,preventDefault(){}});
  const after=viewer.getState().camera;
  const zoom=camera.zoom;
  assert.equal(viewer.getState().autoRotate,false);
  for(let i=1;i<=90;i++){renderer.loop(i*20);assert.deepEqual(viewer.getState().camera,after);assert.equal(camera.zoom,zoom);}
  viewer.dispose();
});
