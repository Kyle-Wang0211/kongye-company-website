import * as THREE from 'three';
import {createActiveTheoryPane} from './vendor/portfolio-glass/pane.mjs';
import {t,localeEvent} from './site-l10n.mjs?v=rds-web-20261104-8271d4741e79';
const stage=document.querySelector('.community-screen-stage');
const links=[...document.querySelectorAll('.community-feature-screen')];
const choices=[...document.querySelectorAll('.community-screen-choice')];
const keys=['siteScreenOne','siteScreenTwo','siteScreenThree'];
const motion=matchMedia('(prefers-reduced-motion: reduce)');
let selected=1,renderer,scene,camera,pane,meshes=[],groups=[],textures=[],frame=0,last=0,visible=true;
let width=0,height=0,screenWidth=1,viewWidth=1,dead=false;
try{const raw=sessionStorage.getItem('pw-community-screen'),value=Number(raw);if(raw!==null&&Number.isInteger(value)&&value>=0&&value<3)selected=value;}catch{}
const relative=index=>(index-selected+4)%3-1;
function select(index){
 selected=(index+3)%3;
 links.forEach((link,i)=>{link.dataset.position=['left','center','right'][relative(i)+1];choices[i].setAttribute('aria-pressed',String(i===selected));});
 try{sessionStorage.setItem('pw-community-screen',String(selected));}catch{}
 requestFrame();
}
choices.forEach((button,index)=>button.addEventListener('click',()=>select(index)));
document.querySelector('.community-screen-switcher').addEventListener('keydown',event=>{
 if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
 event.preventDefault();select(event.key==='Home'?0:event.key==='End'?2:selected+(event.key==='ArrowLeft'?-1:1));choices[selected].focus();
});
let down=null,suppressClickUntil=0;
stage.addEventListener('pointerdown',event=>{if(event.isPrimary&&event.button===0)down={x:event.clientX,y:event.clientY,id:event.pointerId};});
stage.addEventListener('pointerup',event=>{
 if(!down||event.pointerId!==down.id)return;
 const dx=event.clientX-down.x,dy=event.clientY-down.y;down=null;
 if(Math.abs(dx)>40&&Math.abs(dx)>Math.abs(dy)){select(selected+(dx<0?1:-1));suppressClickUntil=performance.now()+250;}
});
stage.addEventListener('pointercancel',()=>{down=null;});
stage.addEventListener('click',event=>{if(performance.now()<suppressClickUntil)event.preventDefault();},true);
function labels(){
 choices.forEach((button,i)=>button.setAttribute('aria-label',t(keys[i])));
 if(!pane)return;
 textures.forEach(texture=>texture.dispose());textures=[];
 for(let i=0;i<meshes.length;i++){
  const canvas=document.createElement('canvas');canvas.width=1024;canvas.height=640;
  const context=canvas.getContext('2d');
  context.textAlign='center';context.textBaseline='middle';context.fillStyle='#222';context.font='500 76px -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif';context.fillText(t(keys[i]),512,270);
  context.fillStyle='#737373';context.font='28px -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif';context.fillText(t('siteScreenPlaceholder'),512,365);
  const texture=new THREE.CanvasTexture(canvas);texture.colorSpace=THREE.SRGBColorSpace;texture.flipY=true;textures.push(texture);
  meshes[i].material.uniforms.tProjectPreview.value=texture;meshes[i].material.uniforms.uProjectPreview.value=1;
 }
 requestFrame();
}
function resize(){
 if(!renderer||dead)return;
 width=stage.clientWidth;height=stage.clientHeight;if(!width||!height)return;
 renderer.setSize(width,height,false);camera.aspect=width/height;camera.updateProjectionMatrix();
 const viewHeight=2*camera.position.z*Math.tan(THREE.MathUtils.degToRad(camera.fov/2));
 viewWidth=viewHeight*camera.aspect;screenWidth=Math.min(5,viewWidth*.56);
 requestFrame();
}
const projected=new THREE.Vector3();
function placeLink(index){
 const mesh=meshes[index],box=pane.geometry.boundingBox;
 mesh.updateWorldMatrix(true,false);
 let left=Infinity,top=Infinity,right=-Infinity,bottom=-Infinity;
 for(const x of [box.min.x,box.max.x])for(const y of [box.min.y,box.max.y])for(const z of [box.min.z,box.max.z]){
  projected.set(x,y,z).applyMatrix4(mesh.matrixWorld).project(camera);
  const px=(projected.x+1)*width/2,py=(1-projected.y)*height/2;
  left=Math.min(left,px);right=Math.max(right,px);top=Math.min(top,py);bottom=Math.max(bottom,py);
 }
 Object.assign(links[index].style,{left:left+'px',top:top+'px',width:(right-left)+'px',height:(bottom-top)+'px',transform:'none',zIndex:String(relative(index)===0?2:1)});
}
function requestFrame(){if(renderer&&!dead&&visible&&!document.hidden&&!frame)frame=requestAnimationFrame(render);}
function render(time){
 frame=0;if(dead||!visible||document.hidden)return;
 const dt=Math.min(.05,Math.max(.001,(time-last)/1000||1/60));last=time;
 let moving=false;
 groups.forEach((group,index)=>{
  const side=relative(index),depth=side===0?0:-1.25;
  const x=side*viewWidth*.285*(camera.position.z-depth)/camera.position.z;
  const targetScale=screenWidth*(side===0?1:.91);
  const snap=motion.matches||!group.userData.placed;
  group.position.x=snap?x:THREE.MathUtils.damp(group.position.x,x,11,dt);
  group.position.z=snap?depth:THREE.MathUtils.damp(group.position.z,depth,11,dt);
  const scale=snap?targetScale:THREE.MathUtils.damp(group.scale.x,targetScale,11,dt);group.scale.setScalar(scale);
  group.rotation.set(0,0,0);group.userData.placed=true;
  if(Math.abs(group.position.x-x)+Math.abs(group.position.z-depth)+Math.abs(scale-targetScale)>.001)moving=true;
 });
 scene.updateMatrixWorld(true);camera.updateMatrixWorld(true);
 // The portfolio's existing two-pass glass material is unchanged. There is no
 // rail/orbit, and every screen's plane stays parallel to the camera's image.
 pane.capture(renderer,scene,camera,meshes);renderer.render(scene,camera);
 groups.forEach((_,index)=>placeLink(index));
 stage.dataset.renderer='glass';
 if(moving)requestFrame();
}
function dispose(){
 if(dead)return;dead=true;cancelAnimationFrame(frame);resizeObserver.disconnect();visibilityObserver.disconnect();
 textures.forEach(texture=>texture.dispose());pane?.dispose();renderer?.dispose();
}
const resizeObserver=new ResizeObserver(resize);
const visibilityObserver=new IntersectionObserver(entries=>{visible=entries[0]?.isIntersecting??true;if(visible)requestFrame();},{rootMargin:'100px'});
async function start(){
 try{
  renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});
  renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setClearColor(0xffffff,0);renderer.outputColorSpace=THREE.SRGBColorSpace;
  renderer.domElement.className='community-screen-canvas';renderer.domElement.setAttribute('aria-hidden','true');stage.prepend(renderer.domElement);
  scene=new THREE.Scene();scene.background=new THREE.Color(0xffffff);
  camera=new THREE.PerspectiveCamera(35,1,.1,100);camera.position.set(0,0,5.5);camera.lookAt(0,0,0);
  pane=createActiveTheoryPane();pane.geometry.computeBoundingBox();
  links.forEach((_,index)=>{const group=new THREE.Group(),mesh=new THREE.Mesh(pane.geometry,pane.createMaterial());mesh.scale.copy(pane.scale);mesh.rotation.z=Math.PI;mesh.frustumCulled=false;group.add(mesh);scene.add(group);groups.push(group);meshes.push(mesh);});
  await pane.assetsReady;if(dead)return;
  labels();resizeObserver.observe(stage);visibilityObserver.observe(stage);resize();
 }catch(error){console.warn('[CommunityScreens] glass unavailable',error);stage.dataset.renderer='fallback';renderer?.domElement.remove();}
}
window.addEventListener(localeEvent,labels);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)requestFrame();});
window.addEventListener('pagehide',event=>{if(!event.persisted)dispose();});
window.addEventListener('pageshow',()=>requestFrame());
select(selected);labels();void start();
