import {installCommunitySearch} from './community-search.mjs?v=rds-pg-trgm-20261112-v1';
import {attachCommunityMasonry} from './community-masonry.mjs?v=natural-covers-20261110-v2';
import {accountClientReady,getAccountClient} from './community-account.mjs?v=account-restore-20261109-v2';
import {feedUrl,workUrl,authorUrl,assetUrl,publicationCoverAspect,checkModel,formatCount,publishedLabel,modelUrl,translatedError,t,currentLocale,localizeElement,initSiteLocale,localeReady,localeEvent} from './community-data.mjs?v=account-library-20261106-v44';
import {legacyWorkIds,workCovers} from './community-work-links.mjs?v=rds-web-20261104-7931926b3d74';
import {createPublicAvatarReader} from './community-public-avatar.mjs?v=rds-web-20261104-7931926b3d74';
const grid=document.querySelector('#community-grid'),status=document.querySelector('#feed-status'),more=document.querySelector('#feed-more');
attachCommunityMasonry(grid);
let config,cursor,paging,busy=false,shareResolved=false,pageFailed=false,authorEpoch=0,authorReadRevision=0,refreshPending=false,refreshTimer,refreshFailed=false,lastFeedRead=0;const cards=new Map();const seen=new Set(),authors=new Map(),authorRequests=new Map(),authorNodes=new Map(),authorFailures=new Set();
let viewerId = null, viewerGeneration = 0, authRevision = 0;
let accountBound = false, accountConnecting;
let publicOrder = [], ownPublicWorks = [], ownRequest;
const searchForm = document.querySelector('#community-search');
const searchInput = document.querySelector('#community-query');
const clearSearch = document.querySelector('#community-search-clear');
const categoryNav = document.querySelector('#community-categories');
let activeQuery = '', activeCategory = 'all', filterRevision = 0, filterPending = false;
let categoryCatalogPromise;

function renderDiscoveryControls() {
  const zh = currentLocale() === 'zh';
  const names = zh
    ? {all: '全部', art: '艺术', life: '生活', scene: '场景'}
    : {all: 'All', art: 'Art', life: 'Life', scene: 'Places'};
  searchForm.setAttribute('aria-label', zh ? '搜索社区作品' : 'Search community works');
  const hint = zh ? '搜索作品关键词' : 'Search works by keyword';
  searchForm.querySelector('label').textContent = hint;
  searchInput.placeholder = hint;
  clearSearch.hidden = searchInput.value.length === 0;
  clearSearch.setAttribute('aria-label', zh ? '清除搜索' : 'Clear search');
  const submit = searchForm.querySelector('[type="submit"]');
  submit.setAttribute('aria-label', zh ? '搜索' : 'Search');
  submit.querySelector('span').textContent = zh ? '搜索' : 'Search';
  categoryNav.setAttribute('aria-label', zh ? '作品分类' : 'Work categories');
  for (const button of categoryNav.querySelectorAll('[data-category]')) {
    button.textContent = names[button.dataset.category];
    button.setAttribute('aria-pressed', String(button.dataset.category === activeCategory));
  }
}

function categoryCatalog() {
  categoryCatalogPromise ??= fetch('community-work-categories.json?v=discovery-20261110-v1')
    .then(response => {
      if (!response.ok) throw translatedError('siteFeedConnection');
      return response.json();
    }).then(catalog => {
      if (catalog.schemaVersion !== 1 || !catalog.assignments ||
          Object.entries(catalog.assignments).some(([id, category]) =>
            !/^[0-9a-f-]{36}$/i.test(id) || !['art', 'life', 'scene'].includes(category))) {
        throw translatedError('siteFeedFormat');
      }
      return catalog.assignments;
    }).catch(error => {
      categoryCatalogPromise = undefined;
      throw error;
    });
  return categoryCatalogPromise;
}

async function readFeed(after, filters) {
  const url = feedUrl(config.origin, after);
  if (filters.query) {
    const pattern = '%' + filters.query.replace(/[\\%_]/g, '\\$&') + '%';
    const value = '"' + pattern.replace(/[\\"]/g, '\\$&') + '"';
    url.searchParams.set('and', `(or(title.ilike.${value},description.ilike.${value}))`);
  }
  if (filters.category !== 'all') {
    const assignments = await categoryCatalog();
    const ids = Object.keys(assignments).filter(id => assignments[id] === filters.category);
    if (!ids.length) return [];
    url.searchParams.set('id', 'in.(' + ids.join(',') + ')');
  }
  if (filters.owner) {
    url.searchParams.set('user_id', 'eq.' + filters.owner);
    url.searchParams.set('deleted_at', 'is.null');
    url.searchParams.set('select', url.searchParams.get('select') + ',visibility,moderation_status,deleted_at');
  }
  return read(url);
}

function changeDiscoveryFilters(category = activeCategory) {
  const query = searchInput.value.trim();
  if (query === activeQuery && category === activeCategory) return;
  activeQuery = query;
  activeCategory = category;
  filterRevision++;
  filterPending = true;
  renderDiscoveryControls();
  drainRefresh();
}
searchForm.addEventListener('submit', event => {
  event.preventDefault();
  changeDiscoveryFilters();
});
searchInput.addEventListener('input', () => { clearSearch.hidden = searchInput.value.length === 0; });
clearSearch.addEventListener('click', () => {
  searchInput.value = '';
  renderDiscoveryControls();
  changeDiscoveryFilters();
  searchInput.focus();
});
categoryNav.addEventListener('click', event => {
  const button = event.target.closest('[data-category]');
  if (button) changeDiscoveryFilters(button.dataset.category);
});
function orderVisibleCards() {
  const allowed = new Set([...publicOrder, ...ownPublicWorks.map(work => work.id)]);
  for (const [id, entry] of cards) {
    if (!allowed.has(id)) {
      entry.card.remove();
      cards.delete(id);
      seen.delete(id);
    }
  }
  const own = viewerId ? [...cards.values()].filter(entry => entry.work.user_id === viewerId) : [];
  own.sort((a, b) => Date.parse(b.work.published_at) - Date.parse(a.work.published_at) ||
    b.work.id.localeCompare(a.work.id));
  const others = publicOrder.map(id => cards.get(id))
    .filter(entry => entry && (!viewerId || entry.work.user_id !== viewerId));
  seen.clear();
  for (const entry of [...own, ...others]) {
    seen.add(entry.work.id);
    grid.append(entry.card);
    localizeElement(entry.like, viewerId ? 'commentLikeCount' : 'siteLikeSignIn',
      {count: formatCount(entry.work.likes_count || 0)}, 'aria-label');
  }
}
function reconcileCard(work) {
  let entry = cards.get(work.id);
  if (!entry || JSON.stringify(entry.work) !== JSON.stringify(work)) {
    const existingCard = entry?.card;
    const replacement = cardFor(work);
    entry = cards.get(work.id);
    if (existingCard) {
      existingCard.replaceChildren(...replacement.children);
      entry.card = existingCard;
    }
  }
  if (!authorNodes.has(work.user_id)) authorNodes.set(work.user_id, new Set());
  const nodes = authorNodes.get(work.user_id);
  if (![...nodes].some(node => node.author === entry.author)) {
    nodes.add({author: entry.author, avatar: entry.avatar});
  }
  return entry;
}
async function refreshOwnPublicWorks() {
  if (!viewerId || !config) return;
  const owner = viewerId, generation = viewerGeneration, revision = filterRevision;
  const filters = {query: activeQuery, category: activeCategory, owner};
  if (ownRequest?.generation === generation && ownRequest?.revision === revision) return ownRequest.promise;
  const request = {generation, revision};
  request.promise = (async () => {
    const own = [];
    let after;
    do {
      const page = await readFeed(after, filters);
      if (generation !== viewerGeneration || revision !== filterRevision) return;
      own.push(...page.filter(work => work.user_id === owner && work.visibility === 'public' &&
        work.moderation_status === 'ok' && work.deleted_at === null && Number.isFinite(Date.parse(work.published_at))));
      if (page.length < 12) break;
      const next = page.at(-1);
      if (next.id === after?.id) throw translatedError('siteFeedFormat');
      after = next;
    } while (true);
    if (generation !== viewerGeneration || revision !== filterRevision) return;
    ownPublicWorks = [...new Map(own.map(work => [work.id, work])).values()];
    for (const work of ownPublicWorks) reconcileCard(work);
    orderVisibleCards();
    for (let i = 0; i < own.length; i += 12) void readAuthors(own.slice(i, i + 12));
  })().catch(() => {
    // Public pagination stays available when an author query fails.
  }).finally(() => {
    if (ownRequest === request) ownRequest = null;
  });
  ownRequest = request;
  return request.promise;
}
function setViewer(id) {
  const next = typeof id === 'string' && /^[a-f0-9-]{36}$/i.test(id) ? id : null;
  if (next === viewerId) return;
  viewerId = next;
  viewerGeneration++;
  ownPublicWorks = [];
  orderVisibleCards();
  void refreshOwnPublicWorks();
}
async function bindAccount(client) {
  if (accountBound) return;
  accountBound = true;
  client.auth.onAuthStateChange((_event, session) => {
    authRevision++;
    setViewer(session?.user?.id);
  });
  const revision = authRevision;
  const {data, error} = await client.auth.getSession();
  if (!error && revision === authRevision) setViewer(data.session?.user?.id);
}
function recoverAccount() {
  if (accountBound || accountConnecting) return;
  accountConnecting = getAccountClient().then(bindAccount).catch(() => {})
    .finally(() => { accountConnecting = null; });
}
accountConnecting = accountClientReady.then(bindAccount).catch(() => {})
  .finally(() => { accountConnecting = null; });
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
 const epoch=authorReadRevision;
 const request=Promise.resolve().then(()=>read(authorUrl(config.origin,ids)));
 for(const id of ids)authorRequests.set(id,request);
 try{
  const profiles=await request;if(epoch!==authorReadRevision)return;
  for(const profile of profiles){
   if(ids.includes(profile?.id)&&typeof profile.display_name==='string'&&profile.display_name.trim()){authors.set(profile.id,profile);authorFreshness.set(profile.id,Date.now()+authorLifetime);}
  }
  saveAuthors();
 }catch{/* Author lookup cannot invalidate already loaded works or pagination. */}
 finally{
  for(const id of epoch===authorReadRevision?ids:[]){
   if(authorRequests.get(id)===request)authorRequests.delete(id);
   if(!authors.has(id))authorFailures.add(id);
   refreshAuthor(id);
  }
  syncAuthorNameRefresh();
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
     picture.style.aspectRatio=String(img.naturalWidth/img.naturalHeight);
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
 const like=document.createElement('a');like.className='community-like';like.href='community/?work='+encodeURIComponent(work.id)+'&release=streaming-profiles-20261103-v14';localizeElement(like,viewerId?'commentLikeCount':'siteLikeSignIn',{count:formatCount(work.likes_count||0)},'aria-label');
 const heart=document.createElement('span');heart.className='community-heart';heart.setAttribute('aria-hidden','true');heart.textContent='♡';like.append(heart);
 const count=document.createElement('span');count.textContent=formatCount(Number.isSafeInteger(work.likes_count)&&work.likes_count>0?work.likes_count:0);like.append(count);
 row.append(avatar,author,like);card.append(open,row);
 cards.set(work.id,{card,work,author,avatar,like});return card;
}
function loadingShells(){
 const shells=[];
 for(let i=0;i<12;i++){
  const shell=document.createElement('article');shell.className='community-skeleton';shell.setAttribute('aria-hidden','true');
  const picture=document.createElement('div');picture.className='community-picture is-loading';
  const information=document.createElement('div');information.className='skeleton-information';
  const title=document.createElement('div');title.className='skeleton-title';
  const row=document.createElement('div');row.className='skeleton-author-row';
  const avatar=document.createElement('div');avatar.className='skeleton-avatar';
  const author=document.createElement('div');author.className='skeleton-author';
  const like=document.createElement('div');like.className='skeleton-like';
  row.append(avatar,author,like);information.append(title,row);shell.append(picture,information);
  grid.append(shell);shells.push(shell);
 }
 return shells;
}
async function load(){
 const revision=filterRevision,filters={query:activeQuery,category:activeCategory};
 if(busy)return;busy=true;pageFailed=false;more.disabled=true;grid.setAttribute('aria-busy','true');const shells=loadingShells();status.replaceChildren();delete status.dataset.i18n;
 try{
 config??=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)}).then(r=>{if(!r.ok)throw Error();return r.json();});
 if(config.origin!=='https://api.kongye.space')throw translatedError('siteConfigUnavailable');
 installCommunitySearch({getClient:getAccountClient,getConfig:()=>config,onOpenWork:openWork});
 const rows=await readFeed(cursor,filters);if(revision!==filterRevision)return;lastFeedRead=Date.now();
 for(const shell of shells)shell.remove();
 for(const work of rows){if(!publicOrder.includes(work.id))publicOrder.push(work.id);if(seen.has(work.id))continue;const card=cardFor(work);seen.add(work.id);grid.append(card);}
 orderVisibleCards();void refreshOwnPublicWorks();
 void readAuthors(rows);
 cursor=rows.at(-1)||cursor;localizeElement(more,'siteLoadMore');localizeElement(status,seen.size?'siteFeedHint':'siteFeedEmpty');more.hidden=rows.length<12;
 await openSharedWork();
 }catch(e){if(revision!==filterRevision)return;pageFailed=true;localizeElement(status,e.localeKey||'siteFeedRetry');localizeElement(more,'siteReload');more.hidden=false;}
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
function drainRefresh(){
 if(document.visibilityState==='hidden'||busy)return;
 if(filterPending){
  filterPending=false;refreshPending=false;cursor=undefined;publicOrder=[];ownPublicWorks=[];
  cards.clear();seen.clear();authorNodes.clear();grid.replaceChildren();
  pageFailed=false;refreshFailed=false;more.hidden=true;
  void load();return;
 }
 if(refreshPending&&refreshTimer===undefined){refreshPending=false;void refreshLoaded();}
}
async function refreshLoaded(){
 if(!config){void load();return;}
 busy=true;more.disabled=true;
 const revision=filterRevision,filters={query:activeQuery,category:activeCategory};
 try{
  const target=Math.max(12,publicOrder.length),rows=[];let nextCursor,hasMore=true;
  while(rows.length<target&&hasMore){
   const page=await readFeed(nextCursor,filters);if(revision!==filterRevision)return;
   rows.push(...page);nextCursor=page.at(-1)||nextCursor;hasMore=page.length===12;
  }
  // Retain the visible card's screen position when new works precede it.
  const keep=new Set([...rows,...ownPublicWorks].map(work=>work.id));
  const anchor=[...cards.entries()].filter(([id])=>keep.has(id)).map(([,entry])=>entry.card).find(card=>card.getBoundingClientRect?.().bottom>0);
  const before=anchor?.getBoundingClientRect?.().top;
  for(const [id,entry] of cards)if(!keep.has(id)){entry.card.remove();cards.delete(id);}
  publicOrder=[...new Set(rows.map(work=>work.id))];
  // Browser back/forward restoration keeps decoded covers and existing author pixels.
  authorFailures.clear();authorNodes.clear();seen.clear();
  for(const work of [...rows,...ownPublicWorks]){
   if(seen.has(work.id))continue;
   const entry=reconcileCard(work);
   grid.append(entry.card);seen.add(work.id);
  }
  orderVisibleCards();void refreshOwnPublicWorks();
  lastFeedRead=Date.now();cursor=nextCursor;more.hidden=!hasMore;pageFailed=false;refreshFailed=false;localizeElement(more,'siteLoadMore');localizeElement(status,rows.length?'siteFeedHint':'siteFeedEmpty');
  if(anchor?.isConnected&&Number.isFinite(before))window.scrollBy?.(0,anchor.getBoundingClientRect().top-before);
  // Author endpoint accepts at most twelve IDs; each batch is independent.
  for(let i=0;i<rows.length;i+=12)void readAuthors(rows.slice(i,i+12));
  await openSharedWork();
 }catch(e){if(revision!==filterRevision)return;pageFailed=true;refreshFailed=true;localizeElement(status,e.localeKey||'siteFeedRetry');localizeElement(more,'siteReload');more.hidden=false;}
 finally{busy=false;more.disabled=false;drainRefresh();syncPaging();}
}
let authorNameTimer;
function refreshVisibleAuthorNames(){
 if(document.visibilityState==='hidden'||!config)return;
 const ids=[...authorNodes].filter(([,nodes])=>[...nodes].some(({author})=>{
  if(!author.isConnected)return false;
  const rect=author.getBoundingClientRect?.();
  return rect&&rect.bottom>0&&rect.top<(window.innerHeight||0);
 })).map(([id])=>id);
 for(const id of ids)if(!authorRequests.has(id))authorFreshness.delete(id);
 for(let i=0;i<ids.length;i+=12)void readAuthors(ids.slice(i,i+12).map(user_id=>({user_id})));
}
function syncAuthorNameRefresh(){
 clearTimeout(authorNameTimer);authorNameTimer=null;
 if(document.visibilityState==='hidden'||!config||!authorNodes.size)return;
 authorNameTimer=setTimeout(()=>{refreshVisibleAuthorNames();syncAuthorNameRefresh();},2000);
}
window.addEventListener('pagehide',()=>{clearTimeout(authorNameTimer);authorNameTimer=null;});
window.addEventListener('pageshow',syncAuthorNameRefresh);
document.addEventListener?.('visibilitychange',syncAuthorNameRefresh);
function revalidateAuthorNames(){
 authorReadRevision++;authorRequests.clear();authorFreshness.clear();
 if(!config)return;
 // The card map can preserve DOM without retaining transport rows.
 const ids=[...authorNodes.keys()];
 for(let i=0;i<ids.length;i+=12)void readAuthors(ids.slice(i,i+12).map(user_id=>({user_id})));
}
window.addEventListener('focus',()=>{recoverAccount();revalidateAuthorNames();requestRefresh();});
window.addEventListener('storage',event=>{if(event.key==='pw-profile-presentation-changed-v1')revalidateAuthorNames();});
window.addEventListener('pageshow',()=>{revalidateAuthorNames();requestRefresh();});
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
 renderDiscoveryControls();
 for(const time of grid.querySelectorAll('time[data-published-at]'))time.textContent=publishedLabel(time.dataset.publishedAt);
 for(const img of grid.querySelectorAll('[data-i18n-alt]'))img.alt=t(img.dataset.i18nAlt);
 for(const open of grid.querySelectorAll('[data-i18n-values]')){
  const title=open.querySelector('.community-card-title');
  if(title?.dataset.i18n==='siteUntitled')localizeElement(open,'siteViewWork',{title:t('siteUntitled')},'aria-label');
 }
});
if(document.documentElement)initSiteLocale().then(()=>{renderDiscoveryControls();return load();}).catch(()=>{more.hidden=false;more.disabled=false;});
else load();
