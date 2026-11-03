import {localizeElement,localeReady} from './site-l10n.mjs?v=community-settings-20261103-v10';
import {avatarDataUrl,readAccount} from './community-account-data.mjs';
const nav=document.querySelector('#account-nav'),summary=document.querySelector('#account-summary'),actions=document.querySelector('#account-actions');
let client,revision=0;
function guest(){
 summary.replaceChildren();const avatar=document.createElement('span');avatar.className='account-avatar-pending account-guest-avatar';avatar.setAttribute('aria-hidden','true');const label=document.createElement('span');label.className='community-account-name';localizeElement(label,'siteGuest');summary.append(avatar,label);actions.replaceChildren();
 for(const [mode,key] of [['signin','siteLogin'],['signup','siteRegister']]){
  const a=document.createElement('a');a.href='community/?auth='+mode;localizeElement(a,key);actions.append(a);
 }
 nav.setAttribute('aria-busy','false');
}
function retry(){
 guest();const a=document.createElement('button');a.type='button';a.style.cssText='border:0;background:none;color:inherit;cursor:pointer;font:inherit';localizeElement(a,'siteAccountRetry');a.addEventListener('click',()=>void (client?refresh():start().catch(retry)));actions.append(a);nav.setAttribute('aria-busy','false');
}
async function refresh(){
 const current=++revision;
 try{
  const account=await readAccount(client);
  if(current!==revision)return;
  if(!account){guest();return;}
  const link=summary;actions.replaceChildren();const profileLink=document.createElement('a');profileLink.href='community/';localizeElement(profileLink,'siteAccount');actions.append(profileLink);link.replaceChildren();
  const avatar=document.createElement('span');avatar.className='account-avatar-pending';avatar.setAttribute('aria-hidden','true');
  const name=document.createElement('span');name.className='community-account-name';name.textContent=account.name||'';
  if(!account.name)localizeElement(name,'siteAccount');
  link.append(avatar,name);nav.setAttribute('aria-busy','false');
  // Avatar errors must not turn a verified signed-in account into a guest.
  const {data,error}=await client.functions.invoke('ensure-generated-avatar',{body:{}});
  if(error)return;
  const src=await avatarDataUrl(data?.avatar);
  const {data:latest}=await client.auth.getSession();
  if(!src||current!==revision||latest.session?.user.id!==account.id)return;
  const img=document.createElement('img');img.alt='';img.width=34;img.height=34;img.src=src;avatar.replaceWith(img);
 }catch{if(current===revision)retry();}
}
async function start(){
 await localeReady;
 const response=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Configuration unavailable');
 const config=await response.json();if(config.origin!=='https://api.kongye.space')throw Error('Invalid deployment');
 client=globalThis.supabase.createClient(config.origin,config.anonKey,{
  auth:{storageKey:'sb-api-auth-token',persistSession:true,autoRefreshToken:true,detectSessionInUrl:false},
  global:{fetch:(url,options={})=>fetch(url,{...options,signal:options.signal||AbortSignal.timeout(15000)})}
 });
 client.auth.onAuthStateChange(()=>{revision++;setTimeout(()=>void refresh(),0);});
 window.addEventListener('pageshow',()=>void refresh());
 window.addEventListener('focus',()=>void refresh());
 window.addEventListener('storage',event=>{if(event.key==='sb-api-auth-token'||event.key===null){revision++;void refresh();}});
 await refresh();
}
void start().catch(retry);
