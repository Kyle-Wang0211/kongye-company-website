import {localizeElement,localeReady} from './site-l10n.mjs?v=community-sidebar-20261105-v36';
import {avatarDataUrl,readAccount} from './community-account-data.mjs';
const nav=document.querySelector('#account-nav'),summary=document.querySelector('#account-summary'),actions=document.querySelector('#account-actions');
const lifetime=300000,storageKey='pw-current-account-presentation-rds-v1';
let publishLink,signingOut=false;
let client,revision=0,displayedId=null,pending,scheduled=false,rerun=false;
const cache=new Map();
function forget(){cache.clear();try{sessionStorage.removeItem(storageKey);}catch{}}
function guest(){
 publishLink?.remove();publishLink=null;
 const profile=document.querySelector('#my-profile-link');if(profile)profile.href='community/?auth=signin';
 displayedId=null;summary.replaceChildren();const avatar=document.createElement('span');avatar.className='account-avatar-pending account-guest-avatar';avatar.setAttribute('aria-hidden','true');const label=document.createElement('span');label.className='community-account-name';localizeElement(label,document.querySelector('#upload-work')?'siteLogin':'siteGuest');summary.append(avatar,label);actions.replaceChildren();
 for(const [mode,key] of [['signin','siteLogin'],['signup','siteRegister']]){const a=document.createElement('a');a.href='community/?auth='+mode;localizeElement(a,key);actions.append(a);}
 nav.setAttribute('aria-busy','false');
}
function retry(){
 if(displayedId)return; // A transient refresh failure keeps the current presentation.
 guest();const a=document.createElement('button');a.type='button';a.style.cssText='border:0;background:none;color:inherit;cursor:pointer;font:inherit';localizeElement(a,'siteAccountRetry');a.addEventListener('click',()=>void (client?refresh():start().catch(retry)));actions.append(a);
}
async function signOutAccount(owner,button){
 if(signingOut||displayedId!==owner||!client)return;
 signingOut=true;button.disabled=true;actions.querySelector('[data-logout-retry]')?.remove();
 try{
  const {error}=await client.auth.signOut({scope:'local'});if(error)throw error;
  if(displayedId===owner){revision++;forget();guest();}else schedule();
 }catch{
  if(displayedId===owner){
   const message=document.createElement('span');message.dataset.logoutRetry='true';message.setAttribute('role','alert');
   localizeElement(message,'authRetry');actions.append(message);
  }
 }finally{signingOut=false;if(displayedId===owner)button.disabled=false;}
}
function render(account,src){
 const profile=document.querySelector('#my-profile-link');if(profile)profile.href='community/?profile='+encodeURIComponent(account.id);
 if(!document.querySelector('#upload-work')&&!publishLink){publishLink=document.createElement('a');publishLink.href='community/?publish=1';publishLink.textContent='+';publishLink.setAttribute('aria-label','发布作品');publishLink.title='发布作品';publishLink.style.cssText='font-size:28px;line-height:1;text-decoration:none';nav.append(publishLink);}
 if(displayedId!==account.id){
  summary.replaceChildren();actions.replaceChildren();const profileLink=document.createElement('a');profileLink.href='community/?profile='+encodeURIComponent(account.id);localizeElement(profileLink,'siteAccount');actions.append(profileLink);
  const logout=document.createElement('button');logout.type='button';logout.style.cssText='border:0;background:none;color:inherit;cursor:pointer;font:inherit';localizeElement(logout,'meSignOut');logout.addEventListener('click',()=>signOutAccount(account.id,logout));actions.append(logout);
  const avatar=document.createElement('span');avatar.className='account-avatar-pending';avatar.setAttribute('aria-hidden','true');const name=document.createElement('span');name.className='community-account-name';summary.append(avatar,name);displayedId=account.id;
 }
 const name=summary.querySelector('.community-account-name');
 if(account.name){delete name.dataset.i18n;name.textContent=account.name;}else localizeElement(name,'siteAccount');
 if(src){const current=summary.querySelector('img');if(current?.getAttribute('src')!==src){const img=document.createElement('img');img.alt='';img.width=34;img.height=34;img.src=src;(current||summary.querySelector('.account-avatar-pending')).replaceWith(img);}}
 nav.setAttribute('aria-busy','false');
}
async function cachedPresentation(id){
 const memory=cache.get(id);if(memory?.until>Date.now())return memory;
 try{
  const saved=JSON.parse(sessionStorage.getItem(storageKey)||'null');
  if(saved?.account?.id!==id||typeof saved.account.name!=='string'||!Number.isFinite(saved.until)||saved.until<=Date.now()||saved.until>Date.now()+lifetime)return null;
  const src=saved.avatar?await avatarDataUrl(saved.avatar):null;
  const row={...saved,src};cache.set(id,row);return row;
 }catch{return null;}
}
async function update(){
 const current=revision;
 try{
  const {data,error}=await client.auth.getSession();if(error)throw error;
  if(current!==revision)return;
  const id=data.session?.user.id;
  if(!id){forget();guest();return;}
  if(displayedId&&displayedId!==id)guest();
  const saved=await cachedPresentation(id);if(current!==revision)return;
  if(saved){render(saved.account,saved.src);return;}
  const account=await readAccount(client);if(current!==revision)return;
  if(!account){forget();guest();return;}
  render(account);
  // Keep existing pixels while refreshing; failed avatar transport never signs out a user.
  const {data:result,error:avatarError}=await client.functions.invoke('ensure-generated-avatar',{body:{}});
  const avatar=avatarError?null:result?.avatar;
  const src=avatar?await avatarDataUrl(avatar):null;
  const {data:latest}=await client.auth.getSession();
  if(current!==revision||latest.session?.user.id!==account.id)return;
  render(account,src);
  const row={account,avatar:src?avatar:null,src,until:Date.now()+(src?lifetime:30000)};cache.clear();cache.set(id,row);
  try{sessionStorage.setItem(storageKey,JSON.stringify({account,avatar:row.avatar,until:row.until}));}catch{}
 }catch{if(current===revision)retry();}
}
function refresh(){
 if(pending){rerun=true;return pending;}
 pending=update().finally(()=>{pending=null;if(rerun){rerun=false;schedule();}});return pending;
}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(()=>{scheduled=false;void refresh();},0);}
async function start(){
 await localeReady;
 const response=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Configuration unavailable');
 const config=await response.json();if(config.origin!=='https://api.kongye.space')throw Error('Invalid deployment');
 client=globalThis.supabase.createClient(config.origin,config.anonKey,{
  auth:{storageKey:'sb-api-rds20261104-auth-token',persistSession:true,autoRefreshToken:true,detectSessionInUrl:false},
  global:{fetch:(url,options={})=>fetch(url,{...options,signal:options.signal||AbortSignal.timeout(15000)})}
 });
 client.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT'||(displayedId&&displayedId!==session?.user.id)){revision++;forget();guest();}
  else if(event==='USER_UPDATED'){revision++;forget();}
  schedule();
 });
 window.addEventListener('pageshow',schedule);window.addEventListener('focus',schedule);
 window.addEventListener('storage',event=>{
  if(event.key!=='sb-api-rds20261104-auth-token'&&event.key!==null)return;
  revision++;let nextId;try{nextId=event.newValue?JSON.parse(event.newValue)?.user?.id:null;}catch{}
  if(event.key===null||!nextId||nextId!==displayedId){forget();guest();}
  schedule();
 });
 await refresh();
 return client;
}
// Following can recover through the same account startup path after a network failure.
export function getAccountClient(){return client?Promise.resolve(client):start();}
export const accountClientReady=start();
void accountClientReady.catch(retry);
