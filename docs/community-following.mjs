import {accountClientReady,getAccountClient} from './community-account.mjs?v=search-results-users-20261113-v1';
import {localizeElement,localeEvent} from './site-l10n.mjs?v=account-library-20261106-v44';
import {createPublicAvatarReader} from './community-public-avatar.mjs?v=rds-web-20261104-7931926b3d74';

const opener=document.querySelector('#following-link');
const dialog=document.querySelector('#following-dialog');
const list=document.querySelector('#following-list');
const status=document.querySelector('#following-status');
const more=document.querySelector('#following-more');
const pageSize=30;
let client,owner=null,generation=0,loading=false,cursor=null,hasMore=true,failed=false;
let avatarReader,avatarReaderPending;
const visibleIds=new Set();

function clear(){
 generation++;
 owner=null;
 loading=false;
 cursor=null;
 hasMore=true;
 failed=false;
 visibleIds.clear();
 list.replaceChildren();
 list.setAttribute('aria-busy','false');
 status.textContent='';
 delete status.dataset.i18n;
 more.hidden=true;
 more.disabled=false;
}
function isCurrent(epoch,accountId){
 return generation===epoch&&owner===accountId&&dialog.open;
}
function updateControls(){
 more.hidden=!hasMore&&!failed;
 more.disabled=loading;
 localizeElement(more,loading?'navFollowingLoading':failed?'navFollowingRetry':'navFollowingMore');
 list.setAttribute('aria-busy',String(loading));
}
function showFailure(){
 failed=true;
 localizeElement(status,'socialFollowingLoadFailed');
 updateControls();
}
async function publicAvatars(){
 if(avatarReader)return avatarReader;
 if(!avatarReaderPending){
  avatarReaderPending=(async()=>{
   const response=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)});
   if(!response.ok)throw Error('Configuration unavailable');
   const config=await response.json();
   if(config.origin!=='https://api.kongye.space'||typeof config.anonKey!=='string')throw Error('Invalid deployment');
   avatarReader=createPublicAvatarReader(config);
   return avatarReader;
  })().finally(()=>{avatarReaderPending=null;});
 }
 return avatarReaderPending;
}
async function addAvatar(avatar,id,epoch,accountId){
 try{
  const reader=await publicAvatars();
  if(!isCurrent(epoch,accountId))return;
  const src=await reader.read(id);
  if(!src||!isCurrent(epoch,accountId)||!avatar.isConnected)return;
  const image=document.createElement('img');
  image.src=src;
  image.alt='';
  image.width=32;
  image.height=32;
  avatar.replaceChildren(image);
 }catch{}
}
function appendPerson(person,epoch,accountId){
 if(visibleIds.has(person.id))return;
 visibleIds.add(person.id);
 const link=document.createElement('a');
 link.className='following-person';
 link.href='community/?profile='+encodeURIComponent(person.id);
 const avatar=document.createElement('span');
 avatar.className='following-avatar';
 avatar.setAttribute('aria-hidden','true');
 const identity=document.createElement('span');
 const name=document.createElement('span');
 name.textContent=person.display_name||person.handle||person.id;
 identity.append(name);
 if(person.handle){
  const handle=document.createElement('small');
  handle.textContent='@'+person.handle;
  identity.append(handle);
 }
 link.append(avatar,identity);
 list.append(link);
 void addAvatar(avatar,person.id,epoch,accountId);
}
async function loadPage(){
 if(loading||!owner||!dialog.open||(!hasMore&&!failed))return;
 const epoch=generation,accountId=owner;
 loading=true;
 failed=false;
 localizeElement(status,'navFollowingLoading');
 updateControls();
 try{
  const {data:sessionData,error:sessionError}=await client.auth.getSession();
  if(!isCurrent(epoch,accountId))return;
  if(sessionError)throw sessionError;
  if(sessionData.session?.user.id!==accountId){clear();dialog.close();return;}
  const {data,error}=await client.rpc('get_my_following',{
   p_limit:pageSize,
   p_before_followed_at:cursor?.followed_at??null,
   p_before_user_id:cursor?.id??null,
  });
  if(!isCurrent(epoch,accountId))return;
  if(error)throw error;
  const {data:latest,error:latestError}=await client.auth.getSession();
  if(!isCurrent(epoch,accountId))return;
  if(latestError)throw latestError;
  if(latest.session?.user.id!==accountId){clear();dialog.close();return;}
  if(!Array.isArray(data)||data.some(person=>!person||typeof person.id!=='string'||!person.id))throw Error('Invalid following response');
  const nextCursor=data.at(-1);
  if(data.length>=pageSize&&typeof nextCursor.followed_at!=='string')throw Error('Missing following cursor');
  if(cursor&&nextCursor?.id===cursor.id&&nextCursor?.followed_at===cursor.followed_at)throw Error('Following cursor did not advance');
  for(const person of data)appendPerson(person,epoch,accountId);
  cursor=nextCursor??cursor;
  hasMore=data.length>=pageSize;
  if(visibleIds.size){status.textContent='';delete status.dataset.i18n;}
  else localizeElement(status,'socialFollowingEmpty');
 }catch{
  if(isCurrent(epoch,accountId))showFailure();
 }finally{
  if(isCurrent(epoch,accountId)){loading=false;updateControls();}
 }
}
let subscribedClient;
async function connect(){
 client=await accountClientReady.catch(()=>getAccountClient());
 if(subscribedClient!==client){
  subscribedClient=client;
  client.auth.onAuthStateChange((event,session)=>{
   if(event==='SIGNED_OUT'||(owner&&owner!==session?.user.id)){
    clear();
    if(dialog.open)dialog.close();
   }
  });
 }
}
opener.addEventListener('click',async()=>{
 clear();
 const epoch=generation;
 try{
  await connect();
  if(generation!==epoch)return;
  const {data,error}=await client.auth.getSession();
  if(generation!==epoch)return;
  if(error)throw error;
  if(!data.session){location.assign('community/?auth=signin');return;}
  owner=data.session.user.id;
  if(!dialog.open)dialog.showModal();
  void loadPage();
 }catch{
  if(generation!==epoch)return;
  if(!dialog.open)dialog.showModal();
  showFailure();
 }
});
more.addEventListener('click',()=>{
 if(owner)void loadPage();
 else opener.click();
});
document.querySelector('#close-following').addEventListener('click',()=>dialog.close());
dialog.addEventListener('close',()=>{clear();opener.focus();});
window.addEventListener(localeEvent,updateControls);

// Direct navigation reuses this page's existing panel and session lifecycle.
if (typeof location !== 'undefined' && location.href) {
  const handoff = new URL(location.href);
  if (handoff.searchParams.get('panel') === 'following') {
    opener.click();
    handoff.searchParams.delete('panel');
    history.replaceState(history.state, '', handoff);
  }
}
