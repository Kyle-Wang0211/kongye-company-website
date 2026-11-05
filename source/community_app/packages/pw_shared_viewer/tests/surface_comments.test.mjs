import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../web/vendor/three/build/three.module.js';
import {createSurfaceComments, validateAnchor} from '../web/surface_comments.mjs';
import {createHostBridge, installHostBridge} from '../web/host_bridge.mjs';
function fixture(withDom = false, format = 'glb') {
 const elements=[];
 function element(tag) {
   const node={tag,style:{},attributes:{},children:[],listeners:new Map(),textContent:'',
    animate(keyframes, options){this.animation={keyframes,options,cancel(){this.cancelled=true;}};return this.animation;},setAttribute(k,v){this.attributes[k]=v;},appendChild(child){this.children.push(child);},
    replaceChildren(){this.children=[];},remove(){this.removed=true;},addEventListener(k,v){this.listeners.set(k,v);}};
   elements.push(node);return node;
 }
 const document=withDom ? {body:element('body'),createElement:element} : undefined;
 const events = new Map(), emitted = [];
 const canvas = {ownerDocument:document,addEventListener:(k,f)=>events.set(k,f), removeEventListener:k=>events.delete(k),
   getBoundingClientRect:()=>({left:0,top:0,width:200,height:200})};
 const root = new THREE.Group(); root.position.set(2,0,0); root.scale.set(2,1,1);
 const mesh = new THREE.Mesh(new THREE.BoxGeometry(2,2,2), new THREE.MeshBasicMaterial()); root.add(mesh);
 const camera = new THREE.PerspectiveCamera(45,1,0.01,100); camera.position.set(2,0,5);camera.lookAt(2,0,0);camera.updateMatrixWorld();
 const controls={target:new THREE.Vector3(2,0,0),autoRotate:true,update(){camera.lookAt(this.target);camera.updateMatrixWorld();}};
 const surface=createSurfaceComments({THREE,canvas,camera,controls,getModel:()=>root,getFormat:()=> format,getOverviewDistance:()=>5,emit:(type,detail)=>emitted.push({type,...detail})});
 const pointer=(type,x=100,y=100,id=1)=>events.get(type)?.({clientX:x,clientY:y,pointerId:id,button:0,isPrimary:id===1});
 return {surface,pointer,emitted,root,camera,controls,events,elements,document,canvas};
}
test('actual raycast returns root-local point/normal and scene camera only in explicit mode',()=>{
 const f=fixture();f.pointer('pointerdown');f.pointer('pointerup');assert.equal(f.emitted.length,0);
 f.surface.setMode(true);assert.equal(f.controls.autoRotate,false);
 f.pointer('pointerdown');f.pointer('pointerup');assert.equal(f.emitted.length,1);
 const a=f.emitted[0].anchor;assert.ok(Math.abs(a.position[0])<1e-10);assert.ok(Math.abs(a.position[2]-1)<1e-10);
 assert.deepEqual(a.normal,[0,0,1]);assert.deepEqual(a.cameraPosition,[2,0,5]);assert.deepEqual(a.cameraTarget,[2,0,0]);
 f.surface.setMode(false);f.pointer('pointerdown');f.pointer('pointerup');assert.equal(f.emitted.length,1);f.surface.dispose();assert.equal(f.events.size,0);
});

test('zoom reveals full plain text and images beside a point; zoom out and occlusion hide content',()=>{
 const f=fixture(true),body='<script>not markup</script>\n完整评论 😃';
 f.surface.setMarkers([{id:'near',number:1,anchor:{position:[0,0,1]},previewText:body,
   previewImages:['https://media.example/comment.png']}]);
 const label=f.elements.find(e=>e.attributes['data-comment-content']==='near');
 assert.ok(label);assert.equal(label.style.display,'none');
 const image=f.elements.find(e=>e.tag==='img');assert.equal(image.src,undefined);
 f.camera.position.z=3;f.controls.update();f.surface.update();
 assert.equal(label.style.display,'block');
 assert.ok(f.elements.some(e=>e.textContent===body));assert.equal(image.src,'https://media.example/comment.png');
 f.camera.position.z=5;f.controls.update();f.surface.update();assert.equal(label.style.display,'none');
 f.camera.position.z=-3;f.controls.update();f.surface.update();assert.equal(label.style.display,'none');
 assert.throws(()=>f.surface.setMarkers([{id:'bad',number:2,anchor:{position:[0,0,0]},previewImages:['javascript:alert(1)']} ]));
 f.surface.clear();assert.equal(f.document.body.children[0].children.length,0);
});
test('drag, long excursion, pinch and cancellation never place pins',()=>{
 const f=fixture();f.surface.setMode(true);
 f.pointer('pointerdown');f.pointer('pointermove',110);f.pointer('pointermove');f.pointer('pointerup');
 f.pointer('pointerdown');f.pointer('pointerdown',100,100,2);f.pointer('pointerup',100,100,2);f.pointer('pointerup');
 f.pointer('pointerdown');f.pointer('pointercancel');f.pointer('pointerup');assert.equal(f.emitted.length,0);
 f.pointer('pointerdown');f.pointer('pointerup');assert.equal(f.emitted.length,1);f.surface.dispose();
});
test('host panel layout follows zoomed visible point without DOM preview and clears exactly once',()=>{
 const f=fixture(true);
 f.surface.setMarkers([{id:'host',number:1,anchor:{position:[0,0,1]}}]);
 const layouts=()=>f.emitted.filter(e=>e.type==='pw-viewer-surface-marker-layout');
 assert.equal(layouts().length,0);
 f.camera.position.z=3;f.controls.update();f.surface.update();
 assert.equal(layouts().length,1);
 assert.deepEqual(layouts().at(-1).layout,{id:'host',x:.5,y:.5,expanded:true});
 const count=layouts().length;f.surface.update();assert.equal(layouts().length,count);
 f.camera.position.x+=.2;f.controls.update();f.surface.update();
 assert.notEqual(layouts().at(-1).layout.x,.5);
 f.camera.position.z=5;f.controls.update();f.surface.update();
 assert.equal(layouts().at(-1).layout,null);
 const cleared=layouts().length;f.surface.clear();assert.equal(layouts().length,cleared);
 f.surface.dispose();
});
test('wheel over a pin reaches OrbitControls canvas while body scrolling remains local',()=>{
 const f=fixture(true),wheels=[];
 f.document.defaultView={WheelEvent:class {constructor(type,options){this.type=type;Object.assign(this,options);}}};
 f.canvas.dispatchEvent=event=>wheels.push(event);
 f.surface.setMarkers([{id:'wheel',number:1,anchor:{position:[0,0,1]},previewText:'正文'}]);
 const button=f.document.body.children[0].children[0];let prevented=0;
 const wheel=button.listeners.get('wheel');assert.equal(typeof wheel,'function');
 wheel({target:button,deltaX:0,deltaY:-100,deltaZ:0,deltaMode:0,clientX:100,clientY:100,preventDefault(){prevented++;},stopPropagation(){}});
 assert.equal(wheels.length,1);assert.equal(wheels[0].deltaY,-100);assert.equal(prevented,1);
 const content=f.elements.find(e=>e.attributes['data-comment-content']==='wheel');content.contains=target=>target===content;
 wheel({target:content});assert.equal(wheels.length,1);
 f.surface.dispose();
});
test('selected visible point supplies collapsed host position, hidden model removes host layout',()=>{
 const f=fixture(true);
 f.surface.setMarkers([{id:'selected',number:1,selected:true,anchor:{position:[0,0,1]}}]);
 assert.deepEqual(f.emitted.at(-1).layout,{id:'selected',x:.5,y:.5,expanded:false});
 f.root.visible=false;f.surface.update();assert.equal(f.emitted.at(-1).layout,null);
 f.surface.dispose();
});
test('focus restores stored scene camera without model reload and rejects malformed input',()=>{
 const f=fixture();f.surface.focus({position:[0,0,1],cameraPosition:[8,4,6],cameraTarget:[2,0,0]});
 assert.deepEqual(f.camera.position.toArray(),[8,4,6]);assert.deepEqual(f.controls.target.toArray(),[2,0,0]);
 for(const position of [[0,0],[0,NaN,1],[0,Infinity,1],[0,0,1e20]])assert.throws(()=>validateAnchor({position}));
 assert.throws(()=>f.surface.setMarkers(Array(257).fill({id:'a',number:1,anchor:{position:[0,0,0]}})));
 f.surface.clear();f.surface.dispose();
});
test('bridge maps all surface arguments and keeps exact protocol/origin event route',async()=>{
 const f=fixture(),sent=[];const viewer={setSurfaceCommentMode:x=>f.surface.setMode(x),setSurfaceCommentMarkers:x=>f.surface.setMarkers(x),focusSurfaceComment:x=>f.surface.focus(x)};
 const bridge=createHostBridge({ready:Promise.resolve(viewer),send:x=>sent.push(x)});
 assert.equal((await bridge.request({id:'m',method:'setSurfaceCommentMode',args:{enabled:true}})).ok,true);
 assert.equal((await bridge.request({id:'f',method:'focusSurfaceComment',args:{anchor:{position:[0,0,0],cameraPosition:[3,3,3],cameraTarget:[0,0,0]}}})).ok,true);
 assert.deepEqual(f.camera.position.toArray(),[3,3,3]);
 const listeners=new Map(),packets=[],parent={postMessage:x=>packets.push(x)};
 const host={parent,location:{origin:'https://viewer.test'},pwSharedViewerReady:Promise.resolve({getState:()=>({})}),addEventListener:(k,v)=>listeners.set(k,v),removeEventListener:k=>listeners.delete(k)};
 installHostBridge(host);await Promise.resolve();listeners.get('pw-viewer-surface-picked')({type:'pw-viewer-surface-picked',detail:{anchor:{position:[1,2,3]}}});
 assert.equal(packets.at(-1).protocol,'PW_SHARED_VIEWER_V1');assert.equal(packets.at(-1).type,'pw-viewer-surface-picked');
 listeners.get('pw-viewer-surface-marker-layout')({type:'pw-viewer-surface-marker-layout',detail:{layout:{id:'a',x:.2,y:.3,expanded:true}}});
 assert.equal(packets.at(-1).type,'pw-viewer-surface-marker-layout');assert.equal(packets.at(-1).layout.x,.2);
 listeners.get('pagehide')({persisted:false});assert.equal(listeners.has('pw-viewer-surface-picked'),false);f.surface.dispose();
 assert.equal(listeners.has('pw-viewer-surface-marker-layout'),false);
});

test('white point overlay projects actual root-local anchors, selects by id and clears DOM',()=>{
 const f=fixture(true);
 f.surface.setMarkers([{id:'comment-7',number:7,selected:true,anchor:{position:[0,0,1]}}]);
 const overlay=f.document.body.children[0],button=overlay.children[0];
 assert.equal(button.textContent,'');assert.equal(button.attributes['aria-pressed'],'true');
 assert.equal(button.style.left,'100px');assert.equal(button.style.top,'100px');assert.equal(button.style.opacity,'1');
 button.listeners.get('click')({stopPropagation(){}});
 assert.deepEqual(f.emitted.at(-1),{type:'pw-viewer-surface-marker-selected',id:'comment-7'});
 f.root.position.x=3;f.surface.update();assert.notEqual(button.style.left,'100px');
 const before=overlay.children;
 assert.throws(()=>f.surface.setMarkers([{id:'bad',number:0,anchor:{position:[0,0,0]}}]));
 assert.equal(overlay.children,before);
 f.surface.clear();assert.equal(overlay.children.length,0);assert.equal(f.surface.enabled,false);
 f.surface.dispose();assert.equal(overlay.removed,true);
});

test('click opens only its spatial comment immediately without requiring a Flutter echo',()=>{
 const f=fixture(true);
 f.surface.setMarkers([
  {id:'one',number:1,anchor:{position:[-.2,0,1]},previewText:'one body'},
  {id:'two',number:2,anchor:{position:[.2,0,1]},previewText:'two body'}]);
 const one=f.document.body.children[0].children[0],two=f.document.body.children[0].children[1];
 const body=id=>f.elements.find(e=>e.attributes['data-comment-content']===id);
 one.listeners.get('click')({target:one,stopPropagation(){}});
 assert.equal(one.attributes['aria-pressed'],'true');assert.equal(two.attributes['aria-pressed'],'false');
 assert.equal(body('one').style.display,'block');assert.equal(body('two').style.display,'none');
 assert.deepEqual(f.emitted.findLast(e=>e.type==='pw-viewer-surface-marker-selected'),{type:'pw-viewer-surface-marker-selected',id:'one'});
 const previous=one.style.left;f.camera.position.x+=.3;f.controls.update();f.surface.update();
 assert.notEqual(one.style.left,previous);assert.equal(body('one').style.display,'block');
 two.listeners.get('click')({target:two,stopPropagation(){}});
 assert.equal(body('one').style.display,'none');assert.equal(body('two').style.display,'block');
 f.surface.dispose();
});

test('pin pointerdown freezes rotation before release and replayed identical markers preserve the click target',()=>{
 const f=fixture(true),values=[{id:'one',number:1,anchor:{position:[0,0,1]},previewText:'one body'}];
 f.surface.setMarkers(values);const one=f.document.body.children[0].children[0];
 one.listeners.get('pointerdown')({target:one,stopPropagation(){}});
 assert.equal(f.controls.autoRotate,false);
 f.surface.setMarkers(values);
 assert.equal(f.document.body.children[0].children[0],one,'identical host echo must not replace a pressed pin');
 one.listeners.get('click')({target:one,stopPropagation(){}});
 assert.equal(one.attributes['aria-pressed'],'true');
 f.surface.dispose();
});

test('occluded pins cannot select or expose a spatial card through a direct click replay',()=>{
 const f=fixture(true);f.surface.setMarkers([{id:'back',number:1,anchor:{position:[0,0,-1]},previewText:'not visible through model'}]);
 const button=f.document.body.children[0].children[0];
 assert.equal(button.disabled,true);assert.equal(button.style.pointerEvents,'none');
 button.listeners.get('click')({target:button,stopPropagation(){}});
 assert.equal(button.attributes['aria-pressed'],'false');
 assert.equal(f.elements.find(e=>e.attributes['data-comment-content']==='back').style.display,'none');
 assert.equal(f.emitted.some(e=>e.type==='pw-viewer-surface-marker-selected'),false);f.surface.dispose();
});

function pointFixture() {
 const f=fixture(true,'ply');f.root.clear();
 const geometry=new THREE.BufferGeometry();
 geometry.setAttribute('position',new THREE.Float32BufferAttribute([.025,0,0, .025,0,-1],3));
 const points=new THREE.Points(geometry,new THREE.PointsMaterial({size:.005}));
 points.position.set(0,.01,0);f.root.add(points);return {...f,points};
}
test('PLY tap stores actual indexed vertex in root coordinates, not closest ray position',()=>{
 const f=pointFixture();f.surface.setMode(true);f.pointer('pointerdown');f.pointer('pointerup');
 const picked=f.emitted.find(e=>e.type==='pw-viewer-surface-picked');assert.ok(picked);
 assert.ok(Math.abs(picked.anchor.position[0]-.025)<1e-7);assert.ok(Math.abs(picked.anchor.position[1]-.01)<1e-7);
 assert.equal(picked.anchor.position[2],0);assert.equal(picked.anchor.normal,undefined);
 assert.deepEqual(picked.anchor.cameraPosition,[2,0,5]);
 f.surface.setMarkers([{id:'ply',number:1,selected:true,anchor:picked.anchor}]);
 const button=f.document.body.children[0].children[0];assert.equal(button.style.display,'block');
 f.camera.position.set(5,3,4);f.controls.update();f.surface.focus(picked.anchor);
 assert.deepEqual(f.camera.position.toArray(),[2,0,5]);assert.equal(button.disabled,false);f.surface.dispose();
});
test('PLY selection follows CSS pixel tolerance across zoom and cannot attach in empty space',()=>{
 const f=pointFixture();f.surface.setMode(true);
 f.pointer('pointerdown',130);f.pointer('pointerup',130);assert.equal(f.emitted.filter(e=>e.type==='pw-viewer-surface-picked').length,0);
 f.camera.position.z=1;f.controls.update();
 f.pointer('pointerdown');f.pointer('pointerup');assert.equal(f.emitted.filter(e=>e.type==='pw-viewer-surface-picked').length,0);
 f.points.geometry.attributes.position.setXYZ(0,.001,0,0);
 f.pointer('pointerdown');f.pointer('pointerup');assert.equal(f.emitted.filter(e=>e.type==='pw-viewer-surface-picked').length,1);f.surface.dispose();
});
test('PLY marker animation projects pins without scanning every point each frame',()=>{
 const f=pointFixture();let raycasts=0;f.points.raycast=()=>raycasts++;
 f.surface.setMarkers([{id:'ply',number:1,selected:true,anchor:{position:[.025,.01,0]}}]);
 for(let n=0;n<20;n++){f.camera.position.x+=.01;f.controls.update();f.surface.update();}
 assert.equal(raycasts,0);assert.equal(f.document.body.children[0].children[0].style.display,'block');f.surface.dispose();
});

test('indexed PLY point buffers anchor the original vertex index and ignore invisible clouds',()=>{
 const f=pointFixture();f.points.geometry.setIndex([1,0]);f.surface.setMode(true);
 f.points.visible=false;f.pointer('pointerdown');f.pointer('pointerup');
 assert.equal(f.emitted.filter(e=>e.type==='pw-viewer-surface-picked').length,0);
 f.points.visible=true;f.pointer('pointerdown');f.pointer('pointerup');
 const anchor=f.emitted.find(e=>e.type==='pw-viewer-surface-picked').anchor;
 assert.equal(anchor.position[2],0);
 assert.deepEqual(validateAnchor(JSON.parse(JSON.stringify(anchor))),anchor);f.surface.dispose();
});


test('white solid point and slow soft halo follow projection and selection', () => {
 const f=fixture(true);
 f.surface.setMarkers([{id:'draft-point',number:1,selected:true,anchor:{position:[0,0,1]}}]);
 const button=f.document.body.children[0].children[0];
 const [halo,dot]=button.children;
 assert.equal(button.style.background,'transparent');
 assert.equal(dot.style.background,'#fff');
 assert.equal(dot.style.width,'12px');
 assert.equal(halo.style.background,'#fff');
 assert.equal(halo.style.filter,'blur(4px)');
 assert.equal(halo.animation.options.duration,2400);
 assert.equal(halo.animation.options.iterations,Infinity);
 assert.deepEqual(halo.animation.keyframes.map(frame=>frame.opacity),[.2,.6,.2]);
 assert.equal(dot.style.opacity,undefined,'solid point stays visible while only halo pulses');
 assert.equal(button.style.left,'100px');
 f.camera.position.x+=.5; f.controls.update(); f.surface.update();
 assert.notEqual(button.style.left,'100px');
 f.surface.setMarkers([]);
 assert.equal(halo.animation.cancelled,true);
 assert.equal(f.document.body.children[0].children.length,0);
 f.surface.dispose();
});


test('draft and saved selected or unselected points remain white without rendered numbers', () => {
 const f=fixture(true),anchor={position:[0,0,1]};
 let point;
 for (const value of [
   {id:'pw-draft-comment-point',number:1,selected:true},
   {id:'saved-comment-id',number:718,selected:false},
   {id:'saved-comment-id',number:23,selected:true},
 ]) {
   f.surface.setMarkers([{...value,anchor}]);
   const button=f.document.body.children[0].children[0];
   const [halo,dot]=button.children;
   assert.equal(button.textContent,'');
   assert.equal(button.attributes['aria-label'],'查看评论点位');
   assert.equal(button.children.every(child=>child.textContent===''),true);
   assert.equal(dot.style.background,'#fff');
   assert.equal(halo.style.background,'#fff');
   assert.equal(button.style.left,'100px');
   assert.equal(button.style.top,'100px');
   point=button;
 }
 f.surface.setMode(false);
 assert.equal(f.document.body.children[0].children[0],point,'leaving pick mode keeps the locked point');
 point.listeners.get('click')({target:point,stopPropagation(){}});
 assert.deepEqual(f.emitted.findLast(e=>e.type==='pw-viewer-surface-marker-selected'),
   {type:'pw-viewer-surface-marker-selected',id:'saved-comment-id'});
 f.camera.position.x+=.5; f.camera.position.z=4; f.controls.update(); f.surface.update();
 assert.notEqual(point.style.left,'100px');
 assert.equal(point.textContent,'');
 f.surface.dispose();
});
