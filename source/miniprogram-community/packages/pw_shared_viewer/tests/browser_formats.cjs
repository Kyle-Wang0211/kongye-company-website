async page => {
  const errors=[],external=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('request',r=>{if(!/^(http:\/\/127\.0\.0\.1:8974\/|data:|blob:)/.test(r.url()))external.push(r.url());});
  await page.setViewportSize({width:390,height:844});
  await page.goto('http://127.0.0.1:8974/');
  const result=await page.evaluate(async()=>{
    const c=await window.pwSharedViewerReady;
    await c.load({url:'/fixtures/textured.skp',format:'skp'});
    const skp=c.getState();
    const image=await createImageBitmap(await(await fetch(c.capture())).blob());
    const canvas=new OffscreenCanvas(image.width,image.height),ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);image.close();
    const pixels=ctx.getImageData(0,0,canvas.width,canvas.height).data;let visiblePixels=0;for(let i=0;i<pixels.length;i+=4)if(pixels[i]+pixels[i+1]+pixels[i+2]>30)visiblePixels++;
    await c.load({url:'/fixtures/sparse.ply',format:'ply'});const ply=c.getState();
    await c.load({url:'/fixtures/final.glb',format:'glb'});const glb=c.getState();
    let rejected=false;try{await c.load({url:'/fixtures/sparse.ply',format:'skp'});}catch{rejected=true;}
    const failed=c.getState();
    return{skp,ply,glb,failed,rejected,visiblePixels};
  });
  if(result.skp.triangleCount!==4||result.skp.loadedTextureCount!==1||result.skp.importInfo.sourceSha256!=='f68a36f4578ffb8533eae9a29c1b3dc2f6b5683bacc3e53c52fc5406b1375688'||result.visiblePixels<100)throw Error('SKP real-render mismatch:'+JSON.stringify(result));
  if(result.ply.pointCount!==49253||result.glb.triangleCount!==70564||result.glb.loadedTextureCount!==80||!result.rejected||result.failed.meshCount!==40)throw Error('GLB/PLY/rollback mismatch');
  if(!result.glb.bundleIdentity||external.length||errors.length)throw Error(JSON.stringify({external,errors}));
  // Screenshot storage is supplied by the external test runner.
  return{status:'PASS_REAL_BROWSER_SKP_GLB_PLY',result,external,errors};
}
