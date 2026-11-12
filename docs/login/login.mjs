import {startDeviceLogin} from './device-login.mjs';
const strings={
zh:{brand:'窗后城',title:'登录',intro:'登录后点赞、评论与分享你的空间。',passwordTab:'密码登录',codeTab:'验证码登录',qrTab:'扫码登录',account:'邮箱或手机号',password:'密码',code:'验证码',sendCode:'获取验证码',signIn:'登录',signup:'注册账号',other:'其他登录与找回密码',qrTitle:'使用 App 扫码登录',qrHint:'打开窗后城 App，进入个人页，点击右上角扫一扫。',showQr:'显示登录二维码',refreshQr:'刷新二维码',qrConfirm:'请在手机上确认登录。首次使用需由本人关联扫码身份。',privacy:'隐私政策',terms:'用户协议',loading:'正在连接…',sent:'验证码已发送，请查看短信或邮箱。',invalid:'请输入有效邮箱，或带国际区号的手机号。',failed:'操作未完成，请重试。',success:'登录成功，正在返回…',qrError:'扫码登录暂时不可用，请使用密码或验证码登录。',native:'请返回 App 完成身份关联。'},
en:{brand:'Chuang Hou Cheng',title:'Sign in',intro:'Sign in to like, comment and share your spaces.',passwordTab:'Password',codeTab:'Verification code',qrTab:'Scan QR code',account:'Email or phone number',password:'Password',code:'Verification code',sendCode:'Get code',signIn:'Sign in',signup:'Create account',other:'Other sign-in and password recovery',qrTitle:'Scan with the App',qrHint:'Open Chuang Hou Cheng, go to your profile and tap the scanner at the top right.',showQr:'Show sign-in QR code',refreshQr:'Refresh QR code',qrConfirm:'Confirm on your phone. Link your scan identity yourself on first use.',privacy:'Privacy policy',terms:'Terms of use',loading:'Connecting…',sent:'Code sent. Check your messages or email.',invalid:'Enter a valid email or phone number including its country calling code.',failed:'Could not complete the action. Please try again.',success:'Signed in. Returning…',qrError:'QR sign-in is unavailable. Use password or verification code.',native:'Return to the App to finish linking your identity.'}}
const $=id=>document.getElementById(id);
const query=new URLSearchParams(location.search);
let language=query.get('lang')==='en'||localStorage.getItem('pw-site-locale')==='en'?'en':'zh';
let method='password',client,busy=false,qrGeneration=0,remaining=0,stopQr=()=>{};
const text=key=>strings[language][key];
const status=(key,error=false)=>{$('status').textContent=text(key);$('status').classList.toggle('error',error)};
function localize(){document.documentElement.lang=language==='zh'?'zh-CN':'en';document.querySelectorAll('[data-i18n]').forEach(e=>e.textContent=text(e.dataset.i18n));$('language').textContent=language==='zh'?'EN':'中';document.querySelector('nav').setAttribute('aria-label',language==='zh'?'登录方式':'Sign-in method');if(remaining)$('send-code').textContent=`${remaining}s`;}
$('language').onclick=()=>{language=language==='zh'?'en':'zh';localStorage.setItem('pw-site-locale',language);localize()};localize();
function account(){const value=$('account').value.trim();if(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))return {email:value};const phone=value.replace(/[\s()-]/g,'');if(/^\+?[1-9]\d{7,14}$/.test(phone)){if(/^1[3-9]\d{9}$/.test(phone))return {phone:'+86'+phone};if(phone.startsWith('+'))return {phone};}throw new Error('invalid-account');}
function destination(){const raw=query.get('returnTo')||(query.get('callback')?sessionStorage.getItem('pw-qr-return-to'):null);try{const u=new URL(raw||'/community/',location.origin);if(u.origin===location.origin&&!u.pathname.startsWith('/login')&&!u.pathname.startsWith('/casdoor'))return u.href;}catch{}return location.origin+'/community/';}
function complete(){const target=destination();sessionStorage.removeItem('pw-qr-return-to');status('success');if(window.parent!==window){window.parent.postMessage({type:'pw-qr-login-complete'},location.origin);}else{location.replace(target);}}
async function showQr(){
 const generation=++qrGeneration;stopQr();
 const stage=$('qr-stage');stage.replaceChildren(document.createTextNode(text('loading')));$('refresh-qr').hidden=false;
 try{
  await ready;
  const response=await fetch('/casdoor/api/get-application?id=admin/pocketworld-supabase',{credentials:'omit'});
  const application=await response.json();
  if(application.status!=='ok'||!application.data?.clientId)throw new Error('Product application missing');
  if(generation!==qrGeneration)return;
  const {data,error}=await client.auth.signInWithOAuth({provider:'custom:casdoor',options:{skipBrowserRedirect:true,redirectTo:location.origin+'/login/?callback=1'}});
  if(error)throw error;
  const authorization=await fetch('/qr-login/authorize',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({authorizationUrl:data.url})});
  if(!authorization.ok)throw new Error('Authorization unavailable');
  const result=await authorization.json();
  const oauth=new URL(result.url);
  if(oauth.origin!==location.origin||oauth.pathname!=='/casdoor/login/oauth/authorize'||
    oauth.searchParams.get('client_id')!==application.data.clientId||
    oauth.searchParams.get('redirect_uri')!=='https://api.kongye.space/auth/v1/callback')throw new Error('Unexpected authorization');
  if(generation!==qrGeneration)return;
  sessionStorage.setItem('pw-qr-return-to',destination());
  const stop=await startDeviceLogin(application.data.clientId,stage,{title:text('qrTitle'),code:language==='zh'?'确认码':'Confirmation code'},oauth,
    async callback=>{
      if(generation!==qrGeneration)return;
      status('loading');
      location.assign(callback);
    },
    ()=>{if(generation===qrGeneration)stage.replaceChildren(document.createTextNode(text('qrError')));});
  if(generation!==qrGeneration)stop();else stopQr=stop;
 }catch{if(generation===qrGeneration)stage.replaceChildren(document.createTextNode(text('qrError')));}
}
window.addEventListener('pagehide',()=>{qrGeneration++;stopQr();});
$('load-qr').onclick=showQr;$('refresh-qr').onclick=showQr;
document.querySelectorAll('[data-method]').forEach(button=>button.onclick=()=>{if(busy)return;method=button.dataset.method;document.querySelectorAll('[data-method]').forEach(b=>{b.classList.toggle('selected',b===button);b.setAttribute('aria-pressed',String(b===button));});document.body.classList.toggle('qr-only',method==='qr');$('password-fields').hidden=method==='code';$('code-fields').hidden=method!=='code';$('password').required=method==='password';$('code').required=method==='code';$('status').textContent='';if(method==='qr')showQr();});
$('send-code').onclick=async()=>{if(busy||remaining)return;busy=true;$('send-code').disabled=true;try{await ready;const id=account();const {error}=await client.auth.signInWithOtp({...id,options:{shouldCreateUser:false,emailRedirectTo:location.origin+'/login/?callback=1'}});if(error)throw error;remaining=60;status('sent');}catch(error){status(error.message==='invalid-account'?'invalid':'failed',true);}finally{busy=false;$('send-code').disabled=remaining>0;}};
setInterval(()=>{if(remaining){remaining--;$('send-code').textContent=remaining?`${remaining}s`:text('sendCode');$('send-code').disabled=remaining>0;}},1000);
$('login-form').onsubmit=async event=>{event.preventDefault();if(busy)return;busy=true;$('submit').disabled=true;status('loading');try{await ready;const id=account();let result;if(method==='password')result=await client.auth.signInWithPassword({...id,password:$('password').value});else result=await client.auth.verifyOtp({...id,token:$('code').value.trim(),type:id.phone?'sms':'email'});if(result.error)throw result.error;if(!result.data.session)throw new Error('missing-session');$('password').value='';$('code').value='';complete();}catch(error){status(error.message==='invalid-account'?'invalid':'failed',true);}finally{busy=false;$('submit').disabled=false;}};
window.addEventListener('message',async event=>{if(event.origin!==location.origin||event.data?.type!=='pw-qr-login-complete')return;await ready;const {data}=await client.auth.getSession();if(data.session)complete();});
const ready=(async()=>{const response=await fetch('/community-config.json',{cache:'no-cache'});if(!response.ok)throw new Error('config');const config=await response.json();if(!window.supabase)throw new Error('sdk');client=window.supabase.createClient(config.origin,config.anonKey,{auth:{storageKey:'sb-api-rds20261104-auth-token',persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,flowType:'pkce'}});if(query.get('native-link')){status('native');return;}if(query.get('callback')){const {data,error}=await client.auth.getSession();if(error||!data.session)throw new Error('callback');history.replaceState(null,'','/login/');complete();}})();ready.catch(()=>status('failed',true));
