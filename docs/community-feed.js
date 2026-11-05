import {feedUrl,workUrl,authorUrl,assetUrl,publicationCoverAspect,checkModel,formatCount,publishedLabel,modelUrl,translatedError,t,currentLocale,localizeElement,initSiteLocale,localeReady,localeEvent} from './community-data.mjs?v=shared-community-20261106-v40';
import {legacyWorkIds,workCovers} from './community-work-links.mjs?v=rds-web-20261104-7931926b3d74';
import {createPublicAvatarReader} from './community-public-avatar.mjs?v=rds-web-20261104-7931926b3d74';
const grid=document.querySelector('#community-grid'),status=document.querySelector('#feed-status'),more=document.querySelector('#feed-more');
let config,cursor,paging,busy=false,shareResolved=false,pageFailed=false,authorEpoch=0,refreshPending=false,refreshTimer,refreshFailed=false,lastFeedRead=0;const cards=new Map();const seen=new Set(),authors=new Map(),authorRequests=new Map(),authorNodes=new Map(),authorFailures=new Set();
const authorFreshness=new Map(),authorLifetime=300000;
try{const saved=JSON.parse(sessionStorage.getItem('pw-public-authors-v1')||'[]');for(const [id,row] of saved)if(row.until>Date.now()&&row.until<=Date.now()+authorLifetime&&typeof row.profile?.display_name==='string'&&row.profile.id===id){authors.set(id,row.profile);authorFreshness.set(id,row.until);}}catch{}
function saveAuthors(){try{sessionStorage.setItem('pw-public-authors-v1',JSON.stringify([...authors].slice(-256).map(([id,profile])=>[id,{profile,until:authorFreshness.get(id)||0}])));}catch{}}
const headers=()=>({apikey:config.anonKey,Authorization:'Bearer '+config.anonKey});
async function read(url){const response=await fetch(url,{headers:headers(),cache:'no-store',signal:AbortSignal.timeout(15000)});if(!response.ok)throw translatedError('siteFeedConnection');const rows=await response.json();if(!Array.isArray(rows))throw translatedError('siteFeedFormat');return rows;}
let avatarReader;const avatarTokens=new WeakMap(),avatarObservers=new Map();
function renderAvatar(avatar,id,profile){
 // Keep already decoded pixels while the same public author is revalidated.
 if(profile&&avatar.dataset.authorId===id&&avatar.querySelector('img'))return;
 avatarObservers.get(avatar)?.disconnect();avatarObservers.delete(avatar);
 avatar.replaceChildren();avatar.style.color='';avatar.classList.add('is-loading');avatar.dataset.authorId=id||'';
 const token={};avatarTokens.set(avatar,token);if(!profile)return;
 const epoch=authorEpoch;const current=()=>epoch===authorEpoch&&avatarTokens.get(avatar)===token;
 const load=async()=>{
  avatarReader??=createPublicAvatarReader({...config,fetcher:fetch});
  const src=await avatarReader.read(id);if(!current())return;
  if(!src){avatar.classList.remove('is-loading');return;}
  const img=document.createElement('img');img.alt='';img.width=16;img.height=16;img.decoding='async';
  img.style.cssText='position:relative;z-index:1;display:block;width:100%;height:100%;border-radius:50%;object-fit:cover;visibility:hidden';
  img.addEventListener('load',async()=>{
   try{await img.decode();}catch{if(current()&&avatar.children[0]===img){img.remove();avatar.style.color='';avatar.classList.remove('is-loading');}return;}
   if(!current()||avatar.children[0]!==img)return;
   avatar.style.color='transparent';img.style.visibility='visible';avatar.classList.remove('is-loading');
  });
  img.addEventListener('error',()=>{if(!current()||avatar.children[0]!==img)return;img.remove();avatar.style.color='';avatar.classList.remove('is-loading');});
  avatar.append(img);img.src=src;
 };
 if(typeof IntersectionObserver==='function'){
  const observer=new IntersectionObserver(entries=>{if(!current()){observer.disconnect();avatarObservers.delete(avatar);return;}if(entries.some(e=>e.isIntersecting)){observer.disconnect();avatarObservers.delete(avatar);void load();}},{rootMargin:'200px'});avatarObservers.set(avatar,observer);observer.observe(avatar);
 }else void load();
}
function renderAuthor(id,author,avatar){
 const profile=authors.get(id);
 author.classList.remove('is-loading');
 delete author.dataset.i18nAria;author.removeAttribute('aria-label');author.setAttribute('aria-busy','false');
 author.replaceChildren();author.style.display='';
 renderAvatar(avatar,id,profile);
 if(profile){
  author.textContent=profile.display_name;
  const href='/community/?profile='+encodeURIComponent(id);
  const visit=event=>{event.stopPropagation();window.location.assign(href);};
  for(const node of [author,avatar]){
   node.setAttribute('role','link');node.setAttribute('tabindex','0');node.style.cursor='pointer';
   node.removeAttribute('aria-hidden');node.setAttribute('aria-label',profile.display_name);
   node.onclick=visit;node.onkeydown=event=>{if(event.key==='Enter'){event.preventDefault();visit(event);}};
  }
  return;
 }
 if(!id||authorFailures.has(id)){
  avatar.classList.remove('is-loading');
  author.style.display='flex';const label=document.createElement('span');label.style.cssText='overflow:hidden;text-overflow:ellipsis;min-width:0;flex:1';localizeElement(label,'siteAuthorUnavailable');author.append(label);
  if(id){const retry=document.createElement('button');retry.type='button';retry.style.cssText='background:none;border:0;padding:0 0 0 5px;font:inherit;cursor:pointer;flex:none';localizeElement(retry,'siteAuthorRetry');retry.addEventListener('click',()=>void readAuthors([{user_id:id}]));author.append(retry);}
  return;
 }
 author.textContent='';author.classList.add('is-loading');avatar.classList.add('is-loading');
 author.setAttribute('aria-busy','true');localizeElement(author,'siteAuthorLoading',{},'aria-label');
}
function refreshAuthor(id){for(const {author,avatar} of authorNodes.get(id)||[])renderAuthor(id,author,avatar);}
function openWork(work){
 try{
  checkModel(work);
  try{sessionStorage.setItem('pw-opening-work-v1',JSON.stringify({savedAt:Date.now(),work,profile:authors.get(work.user_id)||null}));}catch{/* Navigation remains available when browser storage is disabled. */}
  const url=new URL('community/',location.href);url.searchParams.set('work',work.id);url.searchParams.set('release','streaming-profiles-20261103-v14');
  location.assign(url.href);
 }catch(e){localizeElement(status,e.localeKey||'siteFeedRetry');}
}
async function readAuthors(rows){
 const ids=[...new Set(rows.map(w=>w.user_id).filter(Boolean))].filter(id=>(!authors.has(id)||(authorFreshness.get(id)||0)<=Date.now())&&!authorRequests.has(id));
 if(!ids.length)return;
 for(const id of ids){authorFailures.delete(id);refreshAuthor(id);}
 const epoch=authorEpoch;
 const request=Promise.resolve().then(()=>read(authorUrl(config.origin,ids)));
 for(const id of ids)authorRequests.set(id,request);
 try{
  const profiles=await request;if(epoch!==authorEpoch)return;
  for(const profile of profiles){
   if(ids.includes(profile?.id)&&typeof profile.display_name==='string'&&profile.display_name.trim()){authors.set(profile.id,profile);authorFreshness.set(profile.id,Date.now()+authorLifetime);}
  }
  saveAuthors();
 }catch{/* Author lookup cannot invalidate already loaded works or pagination. */}
 finally{
  for(const id of epoch===authorEpoch?ids:[]){
   if(authorRequests.get(id)===request)authorRequests.delete(id);
   if(!authors.has(id))authorFailures.add(id);
   refreshAuthor(id);
  }
 }
}
function cardFor(work){
 const card=document.createElement('article');card.className='community-card';
 const open=document.createElement('button');open.type='button';open.className='community-open';localizeElement(open,'siteViewWork',{title:work.title||t('siteUntitled')},'aria-label');
 const picture=document.createElement('div');picture.className='community-picture';
 const coverAspect=publicationCoverAspect(work);
 if(coverAspect!==null)picture.style.aspectRatio=String(coverAspect);
 const label=document.createElement('span');label.className='community-card-title';work.title?label.textContent=work.title:localizeElement(label,'siteUntitled');
 const coverMessage=key=>{const message=document.createElement('span');message.className='community-cover-message';localizeElement(message,key);picture.replaceChildren(message,label);};
 if(work.thumbnail_storage_path||workCovers[work.model_storage_path]){
  try{
   const img=document.createElement('img');img.alt=work.title||t('siteWorkImage');if(!work.title)img.dataset.i18nAlt='siteWorkImage';img.className='community-cover-image';if(coverAspect!==null)img.style.objectFit='contain';img.loading=seen.size<4?'eager':'lazy';if(seen.size<2)img.fetchPriority='high';img.decoding='async';
   picture.classList.add('is-loading');picture.dataset.mediaState='loading';
   let settled=false,deadline,observer;
   const fail=()=>{if(settled)return;settled=true;clearTimeout(deadline);observer?.disconnect();picture.classList.remove('is-loading');picture.dataset.mediaState='error';img.remove();coverMessage('siteCoverUnavailable');};
   const startDeadline=()=>{if(!settled&&!deadline)deadline=setTimeout(fail,30000);};
   if(typeof IntersectionObserver==='function'){observer=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){startDeadline();observer.disconnect();}},{rootMargin:'600px'});observer.observe(picture);}else startDeadline();
   img.addEventListener('load',async()=>{
    if(settled)return;
    try{await img.decode();if(settled)return;if(!img.naturalWidth||!img.naturalHeight)throw Error('Empty cover');
     settled=true;clearTimeout(deadline);observer?.disconnect();picture.classList.remove('is-loading');picture.dataset.mediaState='ready';img.classList.add('is-ready');
    }catch{fail();}
   },{once:true});
   img.addEventListener('error',fail,{once:true});picture.append(img);
   img.src=work.thumbnail_storage_path?assetUrl(config.origin,'thumbnails',work.thumbnail_storage_path):new URL(workCovers[work.model_storage_path],location.href).href;
  }catch{picture.classList.remove('is-loading');picture.dataset.mediaState='error';coverMessage('siteCoverUnavailable');}
 }else{picture.dataset.mediaState='empty';coverMessage('siteNoCover');}
 picture.append(label);open.append(picture);open.addEventListener('click',()=>openWork(work));
 const row=document.createElement('div');row.className='community-author-row';
 const avatar=document.createElement('span');avatar.className='community-avatar';avatar.setAttribute('aria-hidden','true');
 const author=document.createElement('span');author.className='community-author';author.style.cssText='position:relative;overflow:hidden;min-width:0;min-height:1em';
 if(!authorNodes.has(work.user_id))authorNodes.set(work.user_id,new Set());
 authorNodes.get(work.user_id).add({author,avatar});renderAuthor(work.user_id,author,avatar);
 const like=document.createElement('a');like.className='community-like';like.href='community/?work='+encodeURIComponent(work.id)+'&release=streaming-profiles-20261103-v14';localizeElement(like,'siteLikeSignIn',{},'aria-label');
 const heart=document.createElement('span');heart.className='community-heart';heart.setAttribute('aria-hidden','true');heart.textContent='♡';like.append(heart);
 const count=document.createElement('span');count.textContent=formatCount(Number.isSafeInteger(work.likes_count)&&work.likes_count>0?work.likes_count:0);like.append(count);
 row.append(avatar,author,like);card.append(open,row);
 cards.set(work.id,{card,work,author,avatar});return card;
}
function loadingShells(){
 const shells=[];
 for(let i=0;i<12;i++){
  const shell=document.createElement('article');shell.className='community-skeleton';shell.setAttribute('aria-hidden','true');
  const picture=document.createElement('div');picture.className='community-picture is-loading';
  const row=document.createElement('div');row.className='community-author-row';
  const author=document.createElement('div');author.className='skeleton-author';row.append(author);shell.append(picture,row);
  grid.append(shell);shells.push(shell);
 }
 return shells;
}
async function load(){
 if(busy)return;busy=true;pageFailed=false;more.disabled=true;grid.setAttribute('aria-busy','true');const shells=loadingShells();status.replaceChildren();delete status.dataset.i18n;
 try{
 config??=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)}).then(r=>{if(!r.ok)throw Error();return r.json();});
 if(config.origin!=='https://api.kongye.space')throw translatedError('siteConfigUnavailable');
 const rows=await read(feedUrl(config.origin,cursor));lastFeedRead=Date.now();
 for(const shell of shells)shell.remove();
 for(const work of rows){if(seen.has(work.id))continue;const card=cardFor(work);seen.add(work.id);grid.append(card);}
 void readAuthors(rows);
 cursor=rows.at(-1)||cursor;localizeElement(more,'siteLoadMore');localizeElement(status,seen.size?'siteFeedHint':'siteFeedEmpty');more.hidden=rows.length<12;
 await openSharedWork();
 }catch(e){pageFailed=true;localizeElement(status,e.localeKey||'siteFeedRetry');localizeElement(more,'siteReload');more.hidden=false;}
 finally{for(const shell of shells)shell.remove();busy=false;more.disabled=false;grid.setAttribute('aria-busy','false');drainRefresh();syncPaging();}
}
// Refresh the loaded window atomically, not just the next (older) page.
// Foreground events and backend notifications share this single-flight entry.
function requestRefresh(force=false){
 if(document.visibilityState==='hidden'||(!force&&(!config||Date.now()-lastFeedRead<60000)))return;
 refreshPending=true;
 if(refreshTimer!==undefined)return;
 refreshTimer=setTimeout(()=>{refreshTimer=undefined;drainRefresh();},100);
}
function drainRefresh(){if(document.visibilityState!=='hidden'&&refreshPending&&!busy&&refreshTimer===undefined){refreshPending=false;void refreshLoaded();}}
async function refreshLoaded(){
 if(!config){void load();return;}
 busy=true;more.disabled=true;
 try{
  const target=Math.max(12,seen.size),rows=[];let nextCursor,hasMore=true;
  while(rows.length<target&&hasMore){
   const page=await read(feedUrl(config.origin,nextCursor));
   rows.push(...page);nextCursor=page.at(-1)||nextCursor;hasMore=page.length===12;
  }
  // Retain the visible card's screen position when new works precede it.
  const keep=new Set(rows.map(work=>work.id));
  const anchor=[...cards.entries()].filter(([id])=>keep.has(id)).map(([,entry])=>entry.card).find(card=>card.getBoundingClientRect?.().bottom>0);
  const before=anchor?.getBoundingClientRect?.().top;
  for(const [id,entry] of cards)if(!keep.has(id)){entry.card.remove();cards.delete(id);}
  // Browser back/forward restoration keeps decoded covers and existing author pixels.
  authorFailures.clear();authorNodes.clear();seen.clear();
  for(const work of rows){
   if(seen.has(work.id))continue;
   let entry=cards.get(work.id);
   if(!entry||JSON.stringify(entry.work)!==JSON.stringify(work)){
    const old=entry?.card;const card=cardFor(work);
    if(old){old.replaceChildren(...card.children);entry=cards.get(work.id);entry.card=old;}else entry=cards.get(work.id);
   }
   if(!authorNodes.has(work.user_id))authorNodes.set(work.user_id,new Set());
   const nodes=authorNodes.get(work.user_id);if(![...nodes].some(node=>node.author===entry.author))nodes.add({author:entry.author,avatar:entry.avatar});
   grid.append(entry.card);seen.add(work.id);
  }
  lastFeedRead=Date.now();cursor=nextCursor;more.hidden=!hasMore;pageFailed=false;refreshFailed=false;localizeElement(more,'siteLoadMore');localizeElement(status,rows.length?'siteFeedHint':'siteFeedEmpty');
  if(anchor?.isConnected&&Number.isFinite(before))window.scrollBy?.(0,anchor.getBoundingClientRect().top-before);
  // Author endpoint accepts at most twelve IDs; each batch is independent.
  for(let i=0;i<rows.length;i+=12)void readAuthors(rows.slice(i,i+12));
  await openSharedWork();
 }catch(e){pageFailed=true;refreshFailed=true;localizeElement(status,e.localeKey||'siteFeedRetry');localizeElement(more,'siteReload');more.hidden=false;}
 finally{busy=false;more.disabled=false;drainRefresh();syncPaging();}
}
window.addEventListener('focus',()=>requestRefresh());
window.addEventListener('pageshow',()=>requestRefresh());
document.addEventListener?.('visibilitychange',()=>{if(document.visibilityState==='visible')requestRefresh();});
// Pure invalidation hook; does not claim a backend subscription is connected.
window.addEventListener('pw-community-feed-invalidated',()=>requestRefresh(true));
more.addEventListener('click',()=>refreshFailed?requestRefresh(true):load());
function syncPaging(){
 if(!paging)return; // The button remains an accessible fallback on older browsers.
 const automatic=!pageFailed;
 more.tabIndex=automatic?-1:0;
 more.setAttribute('aria-hidden',String(automatic));
 Object.assign(more.style,automatic?{visibility:'hidden',height:'1px',minHeight:'1px',padding:'0',border:'0',overflow:'hidden'}:{visibility:'',height:'',minHeight:'',padding:'',border:'',overflow:''});
 // An intersection can arrive while the previous page is busy. Re-arm after
 // settling so a still-visible sentinel fills a short viewport automatically.
 paging.disconnect();
 if(!busy&&!pageFailed&&!more.hidden&&document.visibilityState!=='hidden')paging.observe(more);
}
if(typeof IntersectionObserver==='function'){
 paging=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)&&!busy&&!pageFailed&&!more.hidden&&!more.disabled)void load();},{rootMargin:'400px'});
 syncPaging();window.addEventListener('pagehide',()=>paging.disconnect());window.addEventListener('pageshow',syncPaging);
}
async function openSharedWork(){
 if(shareResolved)return;
 const params=new URL(location.href).searchParams;
 const id=params.get('work')||legacyWorkIds[params.get('example')];
 if(!id){shareResolved=true;if(params.has('example'))localizeElement(status,'siteSharedUnavailable');return;}
 const rows=await read(workUrl(config.origin,id));
 if(!rows[0]){shareResolved=true;localizeElement(status,'siteSharedNotPublic');return;}
 openWork(rows[0]);shareResolved=true;
}
window.addEventListener(localeEvent,()=>{
 for(const time of grid.querySelectorAll('time[data-published-at]'))time.textContent=publishedLabel(time.dataset.publishedAt);
 for(const img of grid.querySelectorAll('[data-i18n-alt]'))img.alt=t(img.dataset.i18nAlt);
 for(const open of grid.querySelectorAll('[data-i18n-values]')){
  const title=open.querySelector('.community-card-title');
  if(title?.dataset.i18n==='siteUntitled')localizeElement(open,'siteViewWork',{title:t('siteUntitled')},'aria-label');
 }
});
if(document.documentElement)initSiteLocale().then(load).catch(()=>{more.hidden=false;more.disabled=false;});
else load();
