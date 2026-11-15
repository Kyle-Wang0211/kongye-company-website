// Adapted from Casdoor v4.26.0 DeviceLoginPanel.tsx and AuthBackend.ts.
// Copyright The Casdoor Authors. Licensed under Apache-2.0.
// Pinned source: 1658baf628c760b4d04c259b364af1a91462deb1.
// Casdoor owns device codes, approval, expiry, token verification and OAuth PKCE.
export async function startDeviceLogin(client, stage, labels, oauth, done, failed) {
  if(typeof client!=='string'||!client)throw new Error('Missing product client');
  let stopped=false,timer,device,deadline;
  const abort=new AbortController();
  const call=async(path,params)=>{
    const response=await fetch('/casdoor/api/'+path+'?'+new URLSearchParams(params),{
      method:'POST',credentials:'include',signal:abort.signal,
    });
    return await response.json();
  };
  const stop=()=>{stopped=true;clearTimeout(timer);abort.abort();};
  const fail=()=>{if(stopped)return;stop();failed();};
  const scope=oauth.searchParams.get('scope')||'openid profile email';
  device=await call('device-auth',{client_id:client,scope});
  if(!device.device_code||!device.verification_uri||!(Number(device.expires_in)>0))throw new Error('Incomplete device authorization');
  const verification=new URL(device.verification_uri);
  if(verification.origin!=='https://kongye.space'||!/^\/casdoor\/login\/oauth\/device\/[A-Za-z0-9-]+$/.test(verification.pathname))throw new Error('Unexpected QR destination');
  deadline=Date.now()+Number(device.expires_in)*1000;
  const qr=window.qrcode(0,'M');qr.addData(verification.href);qr.make();
  const image=new Image();image.src=qr.createDataURL(6,4);image.alt=labels.title;image.width=256;image.height=256;
  const caption=document.createElement('p');caption.className='muted small';caption.textContent=labels.code+': '+device.user_code;
  const box=document.createElement('div');box.className='qr-image';box.append(image,caption);stage.replaceChildren(box);
  const interval=Math.max(1,Number(device.interval)||5)*1000;
  const poll=async()=>{
    if(stopped)return;
    if(Date.now()>=deadline){fail();return;}
    try{
      const token=await call('login/oauth/access_token',{client_id:client,grant_type:'urn:ietf:params:oauth:grant-type:device_code',device_code:device.device_code});
      if(stopped)return;
      if(token.access_token){
        // Casdoor's official OAuth device completion returns the authorization
        // code for this existing GoTrue flow, including its state and PKCE.
        const params=oauth.searchParams;
        const completion={deviceCode:device.device_code,responseType:'code',clientId:client,
          redirectUri:params.get('redirect_uri'),scope,state:params.get('state'),
          code_challenge:params.get('code_challenge'),code_challenge_method:params.get('code_challenge_method')};
        if(params.get('nonce'))completion.nonce=params.get('nonce');
        const result=await call('device-auth-complete',completion);
        if(stopped)return;
        if(result.status!=='ok'||typeof result.data!=='string'||!result.data)throw new Error('Authorization did not complete');
        const callback=new URL(completion.redirectUri);
        callback.searchParams.set('code',result.data);
        callback.searchParams.set('state',completion.state);
        callback.searchParams.set('iss','https://kongye.space/casdoor');
        stop();await done(callback.href);return;
      }
      if(token.error!=='authorization_pending')throw new Error('Device authorization ended');
      timer=setTimeout(poll,interval);
    }catch(error){if(!stopped)fail();}
  };
  timer=setTimeout(poll,interval);
  return stop;
}
