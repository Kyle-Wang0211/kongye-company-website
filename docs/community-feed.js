import {feedUrl,workUrl,authorUrl,assetUrl,checkModel,formatCount,publishedLabel,modelUrl} from './community-data.mjs';
import {legacyWorkIds,workCovers} from './community-work-links.mjs?v=aligned-grid-staged-loading-20261102-v6';
const grid=document.querySelector('#community-grid'),status=document.querySelector('#feed-status'),more=document.querySelector('#feed-more');
let config,cursor,busy=false,shareResolved=false,pageFailed=false;const seen=new Set(),authors=new Map();
const headers=()=>({apikey:config.anonKey,Authorization:'Bearer '+config.anonKey});
async function read(url){const response=await fetch(url,{headers:headers(),signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('社区暂时未能连接，请重试或进入完整社区');const rows=await response.json();if(!Array.isArray(rows))throw Error('社区返回格式异常');return rows;}
function authorName(work){return authors.get(work.user_id)?.display_name||'unknown';}
function openWork(work){
 try{
  checkModel(work);
  const url=new URL('community/',location.href);url.searchParams.set('work',work.id);url.searchParams.set('release','aligned-grid-staged-loading-20261102-v6');
  location.assign(url.href);
 }catch(e){status.textContent=e.message;}
}
async function readAuthors(rows){
 const ids=[...new Set(rows.map(w=>w.user_id).filter(Boolean))].filter(id=>!authors.has(id));
 if(!ids.length)return;
 for(const profile of await read(authorUrl(config.origin,ids)))authors.set(profile.id,profile);
}
function cardFor(work){
 const card=document.createElement('article');card.className='community-card';
 const open=document.createElement('button');open.type='button';open.className='community-open';open.setAttribute('aria-label','查看 '+(work.title||'未命名作品'));
 const picture=document.createElement('div');picture.className='community-picture';
 if(work.thumbnail_storage_path||workCovers[work.model_storage_path]){
  try{
   const img=document.createElement('img');img.alt=work.title||'三维作品';img.className='community-cover-image';img.loading='lazy';img.decoding='async';
   picture.classList.add('is-loading');picture.dataset.mediaState='loading';
   let settled=false,deadline,observer;
   const fail=()=>{if(settled)return;settled=true;clearTimeout(deadline);observer?.disconnect();picture.classList.remove('is-loading');picture.dataset.mediaState='error';img.remove();picture.textContent='封面暂不可用';};
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
  }catch{picture.classList.remove('is-loading');picture.dataset.mediaState='error';picture.textContent='封面暂不可用';}
 }else{picture.dataset.mediaState='empty';picture.textContent='暂无封面';}
 const label=document.createElement('span');label.className='community-card-title';label.textContent=work.title||'未命名作品';open.append(picture,label);open.addEventListener('click',()=>openWork(work));
 const row=document.createElement('div');row.className='community-author-row';
 const avatar=document.createElement('span');avatar.className='community-avatar';avatar.setAttribute('aria-hidden','true');
 const author=document.createElement('span');author.className='community-author';author.textContent=authorName(work);
 const like=document.createElement('a');like.className='community-like';like.href='community/?work='+encodeURIComponent(work.id)+'&release=aligned-grid-staged-loading-20261102-v6';like.setAttribute('aria-label','登录后点赞');
 const heart=document.createElement('span');heart.className='community-heart';heart.setAttribute('aria-hidden','true');heart.textContent='♡';like.append(heart);
 if(Number.isSafeInteger(work.likes_count)&&work.likes_count>0){const count=document.createElement('span');count.textContent=formatCount(work.likes_count);like.append(count);}
 row.append(avatar,author,like);card.append(open,row);
 const date=publishedLabel(work.published_at);const time=document.createElement('time');if(date){time.dateTime=work.published_at;time.textContent=date;}else time.setAttribute('aria-hidden','true');card.append(time);
 return card;
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
 if(busy)return;busy=true;pageFailed=false;more.disabled=true;grid.setAttribute('aria-busy','true');const shells=loadingShells();status.textContent='正在读取社区作品…';
 try{
 config??=await fetch('community-config.json',{signal:AbortSignal.timeout(15000)}).then(r=>{if(!r.ok)throw Error();return r.json();});
 if(config.origin!=='https://api.kongye.space')throw Error('社区配置不可用');
 const rows=await read(feedUrl(config.origin,cursor));
 await readAuthors(rows);
 for(const shell of shells)shell.remove();
 for(const work of rows){if(seen.has(work.id))continue;const card=cardFor(work);seen.add(work.id);grid.append(card);}
 cursor=rows.at(-1)||cursor;more.textContent='加载更多';status.textContent=seen.size?'点击作品，旋转、缩放查看。':'社区暂时没有公开作品。';more.hidden=rows.length<12;
 await openSharedWork();
 }catch(e){pageFailed=true;status.textContent=e.message||'社区暂时未能连接，请重试';more.textContent='重新加载';more.hidden=false;}
 finally{for(const shell of shells)shell.remove();busy=false;more.disabled=false;grid.setAttribute('aria-busy','false');}
}
more.addEventListener('click',load);
if(typeof IntersectionObserver==='function'){const paging=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)&&!busy&&!pageFailed&&!more.hidden&&!more.disabled)void load();},{rootMargin:'400px'});paging.observe(more);window.addEventListener('pagehide',()=>paging.disconnect());window.addEventListener('pageshow',()=>paging.observe(more));}
async function openSharedWork(){
 if(shareResolved)return;
 const params=new URL(location.href).searchParams;
 const id=params.get('work')||legacyWorkIds[params.get('example')];
 if(!id){shareResolved=true;if(params.has('example'))status.textContent='分享的作品暂不可访问。';return;}
 const rows=await read(workUrl(config.origin,id));
 if(!rows[0]){shareResolved=true;status.textContent='分享的作品暂不可访问，可能已取消公开。';return;}
 await readAuthors(rows);openWork(rows[0]);shareResolved=true;
}
load();
