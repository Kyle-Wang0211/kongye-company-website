// Derived local real-WebGL acceptance, no product dependencies or user browser.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {chromium} = require('/Users/kaidongwang/Developer/pw-original-sculpt-20261030/source/e2e/node_modules/playwright-core');
const ROOT = path.resolve(__dirname, '../../..');
const VIEWER = path.join(ROOT, 'packages/pw_shared_viewer/web');
const OUT = path.resolve(ROOT, '../evidence/frontend-completion-20261030/browser');
const PHASE = process.argv[2] || 'green';
const result = {phase:PHASE,scope:'Local headless Chrome actual WebGL and input; not Flutter WebView or physical phone',checks:[],samples:[],errors:[],requests:[]};
function check(name, value) {if(!value)throw Error(name);result.checks.push(name);console.log('PASS '+name);}
async function main() {
 fs.mkdirSync(OUT,{recursive:true});
 const imageFixture=path.join(ROOT,'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png');
 const PNG_1PX=fs.readFileSync(imageFixture);result.imageFixture={path:path.relative(ROOT,imageFixture),sha256:crypto.createHash('sha256').update(PNG_1PX).digest('hex')};
 const server=http.createServer((req,res)=>{
  const url=new URL(req.url,'http://127.0.0.1');let file;
  if(url.pathname==='/comment.png'){res.writeHead(200,{'content-type':'image/png','cache-control':'no-store'});res.end(PNG_1PX);return;}
  if(url.pathname==='/Duck.glb')file=path.join(ROOT,'assets/models/Duck.glb');
  else if(url.pathname.startsWith('/viewer/'))file=path.resolve(VIEWER,url.pathname.slice(8));
  if(!file||(!file.startsWith(VIEWER+path.sep)&&file!==path.join(ROOT,'assets/models/Duck.glb'))||!fs.existsSync(file)){res.writeHead(404);res.end();return;}
  const ext=path.extname(file);res.writeHead(200,{'content-type':({'.mjs':'text/javascript','.js':'text/javascript','.html':'text/html','.glb':'model/gltf-binary','.wasm':'application/wasm','.json':'application/json'})[ext]||'application/octet-stream','cache-control':'no-store'});fs.createReadStream(file).pipe(res);
 });
 await new Promise((resolve,reject)=>server.once('error',reject).listen(43320,'127.0.0.1',resolve));
 fs.writeFileSync(path.join(OUT,PHASE+'-server.json'),JSON.stringify({pid:process.pid,port:43320,viewer:VIEWER,duckSHA256:crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,'assets/models/Duck.glb'))).digest('hex')}));
 let browser,page;
 try{
  browser=await chromium.launch({channel:'chrome',headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const context=await browser.newContext({viewport:{width:390,height:844}});page=await context.newPage();page.setDefaultTimeout(12000);
  page.on('pageerror',e=>result.errors.push(String(e)));page.on('request',r=>{if(/comment\.png|Duck\.glb/.test(r.url()))result.requests.push(r.url());});
  await page.goto('http://127.0.0.1:43320/viewer/index.html?model=/Duck.glb&format=glb');
  await page.waitForFunction(()=>window.pwSharedViewerController?.getState().status==='ready');
  result.initial=await page.evaluate(()=>{
   window.__picked=[];window.__layouts=[];window.__selected=[];
   window.addEventListener('pw-viewer-surface-picked',e=>window.__picked.push(e.detail.anchor));
   window.addEventListener('pw-viewer-surface-marker-layout',e=>window.__layouts.push(e.detail));
   window.addEventListener('pw-viewer-surface-marker-selected',e=>window.__selected.push(e.detail));
   const v=window.pwSharedViewerController;v.configure({autoRotate:false});v.setSurfaceCommentMode(true);return v.getState();
  });
  await page.locator('canvas').click();await page.waitForFunction(()=>window.__picked.length===1);
  const anchor=await page.evaluate(()=>window.__picked[0]);result.anchor=anchor;
  await page.evaluate(anchor=>{const v=window.pwSharedViewerController;v.setSurfaceCommentMode(false);v.setSurfaceCommentMarkers([{id:'zoom-1',number:1,anchor,previewText:'模型纹理评论 😃\n完整文字与参考图片。\n'+('模型表面纹理细节很好，继续看完整评论。\n'.repeat(35)),previewImages:[location.origin+'/comment.png']}]);},anchor);
  const content=page.locator('[data-comment-content="zoom-1"]');
  check('overview only numbered point; no early image request',!await content.isVisible()&&!result.requests.some(u=>u.endsWith('/comment.png')));
  const glbCount=result.requests.filter(u=>u.includes('Duck.glb')).length;
  await page.mouse.move(PHASE==='probe'?80:195,422);
  if(PHASE==='red'){
   await page.mouse.wheel(0,-1200);await page.waitForTimeout(700);
   result.legacyWheel1200=await page.evaluate(()=>({state:window.pwSharedViewerController.getState(),contentVisible:document.querySelector('[data-comment-content]')?.getBoundingClientRect().width>0,layout:window.__layouts.at(-1)}));
   await page.evaluate(()=>window.pwSharedViewerController.resetCamera());
  }
  let expanded=false;
  for(let i=0;i<12;i++){
   await page.mouse.wheel(0,-100);await page.waitForTimeout(150);
   const sample=await page.evaluate(()=>({state:window.pwSharedViewerController.getState(),layout:window.__layouts.at(-1),contentVisible:!!document.querySelector('[data-comment-content]')?.getBoundingClientRect().width}));
   result.samples.push(sample);
   if(sample.contentVisible){expanded=true;break;}
  }
  check('actual wheel zoom reveals full content',expanded);
  const box=await content.boundingBox();result.mobileBox=box;
  check('floating card fits mobile viewport',box&&box.x>=0&&box.x+box.width<=390&&box.y>=0&&box.y+box.height<=844);
  const cameraBeforeScroll=await page.evaluate(()=>window.pwSharedViewerController.getState().camera);
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.wheel(0,200);await page.waitForTimeout(200);
  for(let i=0;i<8&&!await content.locator('img').evaluate(el=>el.complete&&el.naturalWidth>0);i++){await page.mouse.wheel(0,200);await page.waitForTimeout(150);}
  const scrollReadback=await content.evaluate(el=>({top:el.scrollTop,height:el.scrollHeight,client:el.clientHeight}));
  const cameraAfterScroll=await page.evaluate(()=>window.pwSharedViewerController.getState().camera);result.bodyScroll={scrollReadback,cameraBeforeScroll,cameraAfterScroll};
  check('long comment body scrolls without zooming model',scrollReadback.top>0&&JSON.stringify(cameraBeforeScroll)===JSON.stringify(cameraAfterScroll));
  await page.waitForFunction(()=>document.querySelector('[data-comment-content] img')?.naturalWidth>0);check('actual lazy image decodes after scrolling into view',true);
  for(let i=0;i<12;i++){
   const visible=await content.locator('img').evaluate(el=>{const a=el.getBoundingClientRect(),b=el.parentElement.getBoundingClientRect();return a.top>=b.top&&a.bottom<=b.bottom&&a.width>0&&a.height>0;});
   if(visible)break;await page.mouse.wheel(0,200);await page.waitForTimeout(100);
  }
  result.imageBox=await content.locator('img').boundingBox();
  check('actual attachment pixels fit visible card and viewport',result.imageBox&&result.imageBox.y>=box.y&&result.imageBox.y+result.imageBox.height<=box.y+box.height&&result.imageBox.x>=0&&result.imageBox.x+result.imageBox.width<=390);
  await page.screenshot({path:path.join(OUT,PHASE+'-mobile.png')});
  const layout=await page.evaluate(()=>window.__layouts.at(-1)?.layout);result.expandedLayout=layout;
  check('expanded point emits validated normalized host layout',layout?.id==='zoom-1'&&layout.expanded===true&&layout.x>=0&&layout.x<=1&&layout.y>=0&&layout.y<=1);
  await page.evaluate(()=>window.pwSharedViewerController.setSurfaceCommentMarkers([{id:'host-1',number:2,anchor:window.__picked[0]}]));
  await page.waitForFunction(()=>window.__layouts.at(-1)?.layout?.id==='host-1'&&window.__layouts.at(-1)?.layout?.expanded===true);
  check('host marker without DOM preview still reports expanded layout',true);
  await page.getByRole('button',{name:'查看评论 2',exact:true}).click();
  check('real marker click delivers identity',await page.evaluate(()=>window.__selected.at(-1)?.id==='host-1'));
  await page.setViewportSize({width:844,height:390});await page.waitForTimeout(300);
  const landscapeLayout=await page.evaluate(()=>window.__layouts.at(-1)?.layout);result.landscapeLayout=landscapeLayout;
  check('landscape host layout remains normalized',landscapeLayout&&landscapeLayout.x>=0&&landscapeLayout.x<=1&&landscapeLayout.y>=0&&landscapeLayout.y<=1);
  await page.screenshot({path:path.join(OUT,PHASE+'-landscape.png')});
  await page.mouse.move(70,195);await page.mouse.down();await page.mouse.move(265,195,{steps:20});await page.mouse.up();await page.waitForTimeout(300);
  const occlusion=await page.evaluate(()=>({opacity:document.querySelector('button[aria-label="查看评论 2"]')?.style.opacity,display:document.querySelector('button[aria-label="查看评论 2"]')?.style.display,layout:window.__layouts.at(-1)?.layout}));result.occlusion=occlusion;
  check('real orbit hides floating host content behind model or viewport',occlusion.layout===null&&(occlusion.opacity==='0.25'||occlusion.display==='none'));
  // Setup for the independent zoom-out check: use original captured-view command, never mutate camera directly.
  await page.evaluate(anchor=>window.pwSharedViewerController.focusSurfaceComment(anchor),anchor);
  const pin=await page.getByRole('button',{name:'查看评论 2',exact:true}).boundingBox();await page.mouse.move(pin.x+pin.width/2,pin.y+pin.height/2);
  for(let i=0;i<12;i++){await page.mouse.wheel(0,-100);await page.waitForTimeout(100);if(await page.evaluate(()=>window.__layouts.at(-1)?.layout?.expanded===true))break;}
  check('original camera restore plus real wheel reopens content',await page.evaluate(()=>window.__layouts.at(-1)?.layout?.expanded===true));
  await page.mouse.move(422,195);for(let i=0;i<12;i++){await page.mouse.wheel(0,100);await page.waitForTimeout(100);if(await page.evaluate(()=>window.__layouts.at(-1)?.layout?.expanded!==true))break;}
  check('zoom out hides automatic floating content',await page.evaluate(()=>window.__layouts.at(-1)?.layout?.expanded!==true));
  await page.evaluate(()=>window.pwSharedViewerController.setSurfaceCommentMarkers([]));
  check('clear removes pins content and host layout',await page.getByRole('button',{name:/查看评论/}).count()===0&&await page.evaluate(()=>window.__layouts.at(-1)?.layout===null));
  check('interaction never reloads model',result.requests.filter(u=>u.includes('Duck.glb')).length===glbCount);
  check('no runtime page errors',result.errors.length===0);result.status='PASS';
 }catch(e){result.status='FAIL';result.failure=String(e);process.exitCode=1;if(page){result.final=await page.evaluate(()=>({state:window.pwSharedViewerController?.getState(),layouts:window.__layouts,body:document.body.innerText.slice(0,1000)})).catch(()=>null);await page.screenshot({path:path.join(OUT,PHASE+'-failure.png')}).catch(()=>{});}console.error(String(e));}
 finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));result.serverStopped=true;fs.writeFileSync(path.join(OUT,PHASE+'-result.json'),JSON.stringify(result,null,2)+'\n');}
}
main().catch(e=>{console.error(e);process.exitCode=1});
