async page => {
  const errors=[],external=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('request',r=>{if(!/^(http:\/\/127\.0\.0\.1:8975\/|data:|blob:)/.test(r.url()))external.push(r.url());});
  await page.setViewportSize({width:390,height:844});
  await page.goto('http://127.0.0.1:8975/?model=/fixtures/textured.skp&format=skp');
  await page.waitForFunction(()=>window.pwFlutterHostReady===true||window.pwFlutterHostError,{timeout:60000});
  const error=await page.evaluate(()=>window.pwFlutterHostError);
  if(error)throw Error(error);
  const frame=page.frames().find(f=>f.url().includes('/assets/packages/pw_shared_viewer/web/index.html'));
  if(!frame)throw Error('Missing actual Flutter iframe');
  const state=await frame.evaluate(()=>window.pwSharedViewerController.getState());
  if(state.format!=='skp'||state.triangleCount!==4||state.loadedTextureCount!==1||state.bundleIdentity!=='3b86e3e3610dd563e577a697daa82db7f2d6d7e7ce6f8ed63548e658b46cac61')throw Error(JSON.stringify(state));
  if(errors.length||external.length)throw Error(JSON.stringify({errors,external}));
  return{status:'PASS_FLUTTER_WEB_SKP_HOST',state,errors,external};
}
