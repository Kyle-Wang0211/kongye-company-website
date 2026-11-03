import {feedUrl,workUrl,authorUrl,assetUrl,checkModel,formatCount,publishedLabel,modelUrl,translatedError,t,currentLocale,localizeElement,initSiteLocale,localeReady,localeEvent} from './community-data.mjs?v=community-settings-20261103-v11';
import {legacyWorkIds,workCovers} from './community-work-links.mjs?v=community-settings-20261103-v11';
const grid=document.querySelector('#community-grid'),status=document.querySelector('#feed-status'),more=document.querySelector('#feed-more');
let config,cursor,busy=false,shareResolved=false,pageFailed=false,authorEpoch=0,refreshPending=false,refreshTimer,refreshFailed=false;const cards=new Map();const seen=new Set(),authors=new Map(),authorRequests=new Map(),authorNodes=new Map(),authorFailures=new Set();
const headers=()=>({apikey:config.anonKey,Authorization:'Bearer '+config.anonKey});
async function read(url){const response=await fetch(url,{headers:headers(),cache:'no-store',signal:AbortSignal.timeout(15000)});if(!response.ok)throw translatedError('siteFeedConnection');const rows=await response.json();if(!Array.isArray(rows))throw translatedError('siteFeedFormat');return rows;}
function renderAuthor(id,author,avatar){
 const profile=authors.get(id);
 author.classList.remove('is-loading');avatar.classList.remove('is-loading');
 delete author.dataset.i18nAria;author.removeAttribute('aria-label');author.setAttribute('aria-busy','false');
 author.replaceChildren();author.style.display='';
 if(profile){author.textContent=profile.display_name;return;}
 if(!id||authorFailures.has(id)){
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
  const url=new URL('community/',location.href);url.searchParams.set('work',work.id);url.searchParams.set('release','community-settings-20261103-v11');
  location.assign(url.href);
 }catch(e){localizeElement(status,e.localeKey||'siteFeedRetry');}
}
async function readAuthors(rows){
 const ids=[...new Set(rows.map(w=>w.user_id).filter(Boolean))].filter(id=>!authors.has(id)&&!authorRequests.has(id));
 if(!ids.length)return;
 for(const id of ids){authorFailures.delete(id);refreshAuthor(id);}
 const epoch=authorEpoch;
 const request=Promise.resolve().then(()=>read(authorUrl(config.origin,ids)));
 for(const id of ids)authorRequests.set(id,request);
 try{
  const profiles=await request;if(epoch!==authorEpoch)return;
  for(const profile of profiles){
   if(ids.includes(profile?.id)&&typeof profile.display_name==='string'&&profile.display_name.trim())authors.set(profile.id,profile);
  }
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
 if(work.thumbnail_storage_path||workCovers[work.model_storage_path]){
  try{
   const img=document.createElement('img');img.alt=work.title||t('siteWorkImage');if(!work.title)img.dataset.i18nAlt='siteWorkImage';img.className='community-cover-image';img.loading='lazy';img.decoding='async';
   picture.classList.add('is-loading');picture.dataset.mediaState='loading';
   let settled=false,deadline,observer;
   const fail=()=>{if(settled)return;settled=true;clearTimeout(deadline);observer?.disconnect();picture.classList.remove('is-loading');picture.dataset.mediaState='error';img.remove();localizeElement(picture,'siteCoverUnavailable');};
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
  }catch{picture.classList.remove('is-loading');picture.dataset.mediaState='error';localizeElement(picture,'siteCoverUnavailable');}
 }else{picture.dataset.mediaState='empty';localizeElement(picture,'siteNoCover');}
 const label=document.createElement('span');label.className='community-card-title';work.title?label.textContent=work.title:localizeElement(label,'siteUntitled');open.append(picture,label);open.addEventListener('click',()=>openWork(work));
 const row=document.createElement('div');row.className='community-author-row';
 const avatar=document.createElement('span');avatar.className='community-avatar';avatar.setAttribute('aria-hidden','true');
 const author=document.createElement('span');author.className='community-author';author.style.cssText='position:relative;overflow:hidden;min-width:0;min-height:1em';
 if(!authorNodes.has(work.user_id))authorNodes.set(work.user_id,new Set());
 authorNodes.get(work.user_id).add({author,avatar});renderAuthor(work.user_id,author,avatar);
 const like=document.createElement('a');like.className='community-like';like.href='community/?work='+encodeURIComponent(work.id)+'&release=community-settings-20261103-v11';localizeElement(like,'siteLikeSignIn',{},'aria-label');
 const heart=document.createElement('span');heart.className='community-heart';heart.setAttribute('aria-hidden','true');heart.textContent='♡';like.append(heart);
 if(Number.isSafeInteger(work.likes_count)&&work.likes_count>0){const count=document.createElement('span');count.textContent=formatCount(work.likes_count);like.append(count);}
 row.append(avatar,author,like);card.append(open,row);
 const date=publishedLabel(work.published_at);const time=document.createElement('time');time.dataset.publishedAt=work.published_at||'';if(date){time.dateTime=work.published_at;time.textContent=date;}else time.setAttribute('aria-hidden','true');card.append(time);
 cards.set(work.id,{card,work,author,avatar});return card;
}
function loadingShells(){
 const shells=[];
 for(let i=0;i<12;i++){
  const shell=document.createElement('article');shell.className='community-skeleton';shell.setAttribute('aria-hidden','true');
  for(const name of ['community-picture is-loading','skeleton-title','skeleton-author','skeleton-time']){const part=document.createElement('div');part.className=name;shell.append(part);}
  grid.append(shell);shells.push(shell);
 }
 return shells;
}
async function load(){
 if(busy)return;busy=true;pageFailed=false;more.disabled=true;grid.setAttribute('aria-busy','true');const shells=loadingShells();localizeElement(status,'siteFeedLoading');
 try{
 config??=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)}).then(r=>{if(!r.ok)throw Error();return r.json();});
 if(config.origin!=='https://api.kongye.space')throw translatedError('siteConfigUnavailable');
 const rows=await read(feedUrl(config.origin,cursor));
 for(const shell of shells)shell.remove();
 for(const work of rows){if(seen.has(work.id))continue;const card=cardFor(work);seen.add(work.id);grid.append(card);}
 void readAuthors(rows);
 cursor=rows.at(-1)||cursor;localizeElement(more,'siteLoadMore');localizeElement(status,seen.size?'siteFeedHint':'siteFeedEmpty');more.hidden=rows.length<12;
 await openSharedWork();
 }catch(e){pageFailed=true;localizeElement(status,e.localeKey||'siteFeedRetry');localizeElement(more,'siteReload');more.hidden=false;}
 finally{for(const shell of shells)shell.remove();busy=false;more.disabled=false;grid.setAttribute('aria-busy','false');drainRefresh();}
}
// Refresh the loaded window atomically, not just the next (older) page.
// Foreground events and backend notifications share this single-flight entry.
function requestRefresh(){
 if(document.visibilityState==='hidden')return;
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
  authorEpoch++;authors.clear();authorRequests.clear();authorFailures.clear();authorNodes.clear();seen.clear();
  for(const work of rows){
   if(seen.has(work.id))continue;
   let entry=cards.get(work.id);
   if(!entry||JSON.stringify(entry.work)!==JSON.stringify(work)){
    const old=entry?.card;const card=cardFor(work);
    if(old){old.replaceChildren(...card.children);entry=cards.get(work.id);entry.card=old;}else entry=cards.get(work.id);
   }
   if(!authorNodes.has(work.user_id))authorNodes.set(work.user_id,new Set());
   const nodes=authorNodes.get(work.user_id);if(![...nodes].some(node=>node.author===entry.author))nodes.add({author:entry.author,avatar:entry.avatar});
   renderAuthor(work.user_id,entry.author,entry.avatar);grid.append(entry.card);seen.add(work.id);
  }
  cursor=nextCursor;more.hidden=!hasMore;pageFailed=false;refreshFailed=false;localizeElement(more,'siteLoadMore');localizeElement(status,rows.length?'siteFeedHint':'siteFeedEmpty');
  if(anchor?.isConnected&&Number.isFinite(before))window.scrollBy?.(0,anchor.getBoundingClientRect().top-before);
  // Author endpoint accepts at most twelve IDs; each batch is independent.
  for(let i=0;i<rows.length;i+=12)void readAuthors(rows.slice(i,i+12));
  await openSharedWork();
 }catch(e){pageFailed=true;refreshFailed=true;localizeElement(status,e.localeKey||'siteFeedRetry');localizeElement(more,'siteReload');more.hidden=false;}
 finally{busy=false;more.disabled=false;drainRefresh();}
}
window.addEventListener('focus',requestRefresh);
window.addEventListener('pageshow',requestRefresh);
document.addEventListener?.('visibilitychange',()=>{if(document.visibilityState==='visible')requestRefresh();});
// Pure invalidation hook; does not claim a backend subscription is connected.
window.addEventListener('pw-community-feed-invalidated',requestRefresh);
more.addEventListener('click',()=>refreshFailed?requestRefresh():load());
if(typeof IntersectionObserver==='function'){const paging=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)&&!busy&&!pageFailed&&!more.hidden&&!more.disabled)void load();},{rootMargin:'400px'});paging.observe(more);window.addEventListener('pagehide',()=>paging.disconnect());window.addEventListener('pageshow',()=>paging.observe(more));}
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
