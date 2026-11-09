import {localizeElement,localeReady} from './site-l10n.mjs?v=account-library-20261106-v44';
import {avatarDataUrl,readAccount} from './community-account-data.mjs?v=account-restore-20261109-v2';
const nav=document.querySelector('#account-nav'),summary=document.querySelector('#account-summary'),actions=document.querySelector('#account-actions');
const lifetime=86400000,storageKey='pw-current-account-presentation-rds-v1';
let publishLink,signingOut=false;
let client,revision=0,displayedId=null,pending,scheduled=false,rerun=false,startPending,sessionResolved=false,restorationFailed=false;
const cache=new Map();
const accountMenu=document.querySelector('#account-menu');
const libraryLifetime=60000;
let closeTimer,menuGeneration=0,menuName,menuAvatar,followingCount,followersCount;
let countNodes={},libraryCache,libraryPending;
function countText(value){return Number.isSafeInteger(value)&&value>=0?String(value):'—';}
function renderLibraryCounts(row){
 for(const key of ['likes','favorites','history'])if(countNodes[key])countNodes[key].textContent=countText(row?.[key+'_count']);
}
async function loadLibraryCounts(){
 const owner=displayedId,epoch=menuGeneration;
 if(!owner||!client)return;
 if(libraryCache?.owner===owner&&libraryCache.until>Date.now()){renderLibraryCounts(libraryCache.row);return;}
 if(libraryPending?.owner===owner&&libraryPending.epoch===epoch)return libraryPending.promise;
 const request={owner,epoch};
 request.promise=(async()=>{
  try{
   const {data:before,error:beforeError}=await client.auth.getSession();
   if(beforeError||before.session?.user.id!==owner||menuGeneration!==epoch||displayedId!==owner)return;
   const {data,error}=await client.rpc('get_my_library_counts');
   if(error)throw error;
   const {data:after,error:afterError}=await client.auth.getSession();
   if(afterError||after.session?.user.id!==owner||menuGeneration!==epoch||displayedId!==owner)return;
   const row=Array.isArray(data)?data[0]:data;
   if(!row||['likes_count','favorites_count','history_count'].some(key=>!Number.isSafeInteger(row[key])||row[key]<0))return;
   libraryCache={owner,row,until:Date.now()+libraryLifetime};renderLibraryCounts(row);
  }catch{/* Counts can retry on the next menu opening while existing account pixels stay visible. */}
  finally{if(libraryPending===request)libraryPending=null;}
 })();
 libraryPending=request;return request.promise;
}
function openAccountMenu(focus=false){
 if(!sessionResolved&&!restorationFailed)return;
 clearTimeout(closeTimer);accountMenu.open=true;summary.setAttribute('aria-expanded','true');
 void loadLibraryCounts();
 if(focus)actions.querySelector('a')?.focus();
}
function closeAccountMenu(){
 clearTimeout(closeTimer);accountMenu.open=false;summary.setAttribute('aria-expanded','false');
}
if(accountMenu){
 summary.setAttribute('aria-expanded',String(accountMenu.open));
 summary.setAttribute('aria-controls','account-actions');
 accountMenu.addEventListener('pointerenter',event=>{if(event.pointerType!=='touch')openAccountMenu();});
 accountMenu.addEventListener('pointerleave',()=>{
  clearTimeout(closeTimer);closeTimer=setTimeout(()=>{
   if(!accountMenu.contains(document.activeElement))closeAccountMenu();
  },180);
 });
 accountMenu.addEventListener('focusin',event=>{
  clearTimeout(closeTimer);
  if(event.target!==summary)openAccountMenu();
 });
 accountMenu.addEventListener('focusout',()=>{
  clearTimeout(closeTimer);closeTimer=setTimeout(()=>{
   if(!accountMenu.contains(document.activeElement))closeAccountMenu();
  },0);
 });
 summary.addEventListener('click',event=>{
  if(!sessionResolved){event.preventDefault();if(restorationFailed)openAccountMenu();return;}
  if(displayedId){event.preventDefault();location.assign('community/?profile='+encodeURIComponent(displayedId));}
 });
 summary.addEventListener('keydown',event=>{
  if(event.key==='ArrowDown'){event.preventDefault();openAccountMenu(true);}
 });
 accountMenu.addEventListener('toggle',()=>{
  summary.setAttribute('aria-expanded',String(accountMenu.open));
  if(accountMenu.open)void loadLibraryCounts();
 });
 document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&accountMenu.open){event.preventDefault();closeAccountMenu();summary.focus();}
 });
 document.addEventListener('click',event=>{if(!accountMenu.contains(event.target))closeAccountMenu();});
}

document.querySelector('#my-profile-link')?.addEventListener('click',event=>{if(!sessionResolved)event.preventDefault();});

function forget(){cache.clear();libraryCache=null;for(const storage of presentationStores())try{storage.removeItem(storageKey);}catch{}}
function presentationStores(){const stores=[];try{stores.push(sessionStorage);}catch{}try{stores.push(localStorage);}catch{}return stores;}
function remember(row){for(const storage of presentationStores())try{storage.setItem(storageKey,JSON.stringify(row));}catch{}}
function guest(){
 sessionResolved=true;restorationFailed=false;
 publishLink?.remove();publishLink=null;
 const profile=document.querySelector('#my-profile-link');if(profile)profile.href='community/?auth=signin';
 menuGeneration++;libraryCache=null;countNodes={};displayedId=null;summary.replaceChildren();const avatar=document.createElement('span');avatar.className='account-avatar-pending account-guest-avatar';avatar.setAttribute('aria-hidden','true');const label=document.createElement('span');label.className='community-account-name';localizeElement(label,document.querySelector('#upload-work')?'siteLogin':'siteGuest');summary.append(avatar,label);actions.replaceChildren();
 for(const [mode,key] of [['signin','siteLogin'],['signup','siteRegister']]){const a=document.createElement('a');a.href='community/?auth='+mode;localizeElement(a,key);actions.append(a);}
 nav.setAttribute('aria-busy','false');
}
function retry(){
 restorationFailed=true;
 if(displayedId)return; // A transient refresh failure keeps the current presentation.
 nav.setAttribute('aria-busy','false');actions.replaceChildren();const a=document.createElement('button');a.type='button';a.style.cssText='border:0;background:none;color:inherit;cursor:pointer;font:inherit';localizeElement(a,'siteAccountRetry');a.addEventListener('click',()=>void (client?refresh():start().catch(retry)));actions.append(a);
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
 sessionResolved=true;restorationFailed=false;
 const profile=document.querySelector('#my-profile-link');if(profile)profile.href='community/?profile='+encodeURIComponent(account.id);
 if(!document.querySelector('#upload-work')&&!publishLink){publishLink=document.createElement('a');publishLink.href='community/?publish=1';publishLink.textContent='+';publishLink.setAttribute('aria-label','发布作品');publishLink.title='发布作品';publishLink.style.cssText='font-size:28px;line-height:1;text-decoration:none';nav.append(publishLink);}
 if(displayedId!==account.id){
  menuGeneration++;libraryCache=null;countNodes={};
  summary.replaceChildren();actions.replaceChildren();
  const profileLink=document.createElement('a');profileLink.href='community/?profile='+encodeURIComponent(account.id);profileLink.className='account-profile-card';
  menuAvatar=document.createElement('span');menuAvatar.className='account-card-avatar account-avatar-pending';menuAvatar.setAttribute('aria-hidden','true');
  menuName=document.createElement('span');menuName.className='account-card-name';profileLink.append(menuAvatar,menuName);actions.append(profileLink);
  const stats=document.createElement('div');stats.className='account-social-counts';
  for(const [kind,key] of [['following','socialFollowing'],['followers','socialFollowers']]){
   const stat=document.createElement('span');stat.className='account-social-stat';
   const value=document.createElement('strong');value.className='account-'+kind+'-count';
   if(kind==='following')followingCount=value;else followersCount=value;
   const label=document.createElement('span');localizeElement(label,key);stat.append(value,label);stats.append(stat);
  }
  actions.append(stats);
  for(const [kind,key] of [['likes','webAccountLikes'],['favorites','webAccountFavorites'],['history','webAccountHistory']]){
   const link=document.createElement('a');link.className='account-library-link';link.href='community/#/'+kind;
   const label=document.createElement('span');localizeElement(label,key);
   const value=document.createElement('span');value.className='account-'+kind+'-count account-library-count';value.textContent='—';countNodes[kind]=value;
   link.append(label,value);actions.append(link);
  }
  const logout=document.createElement('button');logout.type='button';logout.className='account-logout';localizeElement(logout,'meSignOut');logout.addEventListener('click',()=>signOutAccount(account.id,logout));actions.append(logout);
  const avatar=document.createElement('span');avatar.className='account-avatar-pending';avatar.setAttribute('aria-hidden','true');const name=document.createElement('span');name.className='community-account-name';summary.append(avatar,name);displayedId=account.id;
 }
 const name=summary.querySelector('.community-account-name');
 for(const node of [name,menuName]){
  if(account.name){delete node.dataset.i18n;node.textContent=account.name;}else localizeElement(node,'siteAccount');
 }
 followingCount.textContent=countText(account.following_count);followersCount.textContent=countText(account.followers_count);
 if(src){
  for(const [container,size] of [[summary,34],[menuAvatar,48]]){
   const current=container.querySelector('img');
   if(current?.getAttribute('src')===src)continue;
   const img=document.createElement('img');img.alt='';img.width=size;img.height=size;img.src=src;
   if(container===summary)(current||summary.querySelector('.account-avatar-pending')).replaceWith(img);
   else menuAvatar.replaceChildren(img);
  }
 }
 nav.setAttribute('aria-busy','false');
 if(accountMenu?.open)void loadLibraryCounts();
}
async function cachedPresentation(id){
 const memory=cache.get(id);if(memory?.until>Date.now())return memory;
 for(const storage of presentationStores())try{
  const saved=JSON.parse(storage.getItem(storageKey)||'null');
  if(saved?.account?.id!==id||typeof saved.account.name!=='string'||!Number.isFinite(saved.until)||saved.until<=Date.now()||saved.until>Date.now()+lifetime)continue;
  const src=saved.avatar?await avatarDataUrl(saved.avatar):null;
  const row={...saved,src};cache.set(id,row);return row;
 }catch{}
 return null;
}
async function update(){
 const current=revision;
 try{
  const {data,error}=await client.auth.getSession();if(error)throw error;
  if(current!==revision)return;
  const id=data.session?.user.id;
  if(!id){forget();guest();return;}
  if(displayedId&&displayedId!==id){forget();guest();}
  const saved=await cachedPresentation(id);if(current!==revision)return;
  const {data:confirmed,error:confirmationError}=await client.auth.getSession();
  if(confirmationError)throw confirmationError;
  if(current!==revision)return;
  if(confirmed.session?.user.id!==id){schedule();return;}
  if(saved)render(saved.account,saved.src);
  else if(!displayedId){
   const meta=data.session.user.user_metadata||{};
   render({id,name:meta.display_name||meta.full_name||meta.name||''});
  }
  const account=await readAccount(client);if(current!==revision)return;
  const {data:verified,error:verificationError}=await client.auth.getSession();
  if(verificationError)throw verificationError;
  if(current!==revision)return;
  if(verified.session?.user.id!==id){schedule();return;}
  if(!account){forget();guest();return;}
  if(account.id!==id){schedule();return;}
  render(account);
  // Persist approved presentation before the independent avatar request.
  const prior=cache.get(id);
  const presentation={account,avatar:prior?.avatar||null,src:prior?.src||null,until:Date.now()+lifetime};
  cache.clear();cache.set(id,presentation);
  remember({account,avatar:presentation.avatar,until:presentation.until});
  // Keep existing pixels while refreshing; failed avatar transport never signs out a user.
  const {data:result,error:avatarError}=await client.functions.invoke('ensure-generated-avatar',{body:{}});
  const avatar=(avatarError?null:result?.avatar)||presentation.avatar;
  const src=(avatar?await avatarDataUrl(avatar):null)||presentation.src;
  const {data:latest}=await client.auth.getSession();
  if(current!==revision||latest.session?.user.id!==account.id)return;
  render(account,src);
  const row={account,avatar:src?avatar:null,src,until:Date.now()+lifetime};cache.clear();cache.set(id,row);
  remember({account,avatar:row.avatar,until:row.until});
 }catch{if(current===revision)retry();}
}
function refresh(){
 if(pending){rerun=true;return pending;}
 pending=update().finally(()=>{pending=null;if(rerun){rerun=false;schedule();}});return pending;
}
function schedule(){if(scheduled)return;scheduled=true;setTimeout(()=>{scheduled=false;void refresh();},0);}
async function startAccount(){
 await localeReady;
 const response=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Configuration unavailable');
 const config=await response.json();if(config.origin!=='https://api.kongye.space')throw Error('Invalid deployment');
 client=globalThis.supabase.createClient(config.origin,config.anonKey,{
  auth:{storageKey:'sb-api-rds20261104-auth-token',persistSession:true,autoRefreshToken:true,detectSessionInUrl:false},
  global:{fetch:(url,options={})=>fetch(url,{...options,signal:options.signal||AbortSignal.timeout(15000)})}
 });
 client.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT'||(displayedId&&displayedId!==session?.user.id)){revision++;forget();guest();}
  else if(event==='USER_UPDATED'){revision++;libraryCache=null;}
  schedule();
 });
 const revalidate=()=>{revision++;schedule();};
 window.addEventListener('pageshow',revalidate);window.addEventListener('focus',revalidate);
 window.addEventListener('storage',event=>{if(event.key==='pw-profile-presentation-changed-v1')revalidate();});
 window.addEventListener('storage',event=>{
  if(event.key!=='sb-api-rds20261104-auth-token'&&event.key!==null)return;
  revision++;let nextId;try{nextId=event.newValue?JSON.parse(event.newValue)?.user?.id:null;}catch{}
  if(event.key===null||!nextId||nextId!==displayedId){forget();guest();}
  schedule();
 });
 await refresh();
 return client;
}
// A single startup owns the SDK client and auth listeners, including retries.
function start(){
 if(startPending)return startPending;
 startPending=startAccount().catch(error=>{startPending=null;throw error;});
 return startPending;
}
// Following can recover through the same account startup path after a network failure.
export function getAccountClient(){return client?Promise.resolve(client):start();}
export const accountClientReady=start();
void accountClientReady.catch(retry);
