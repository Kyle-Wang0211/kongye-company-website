import {feedUrl,workUrl,authorUrl,assetUrl,checkModel,formatCount,publishedLabel,modelUrl} from './community-data.mjs';
import {examples} from './community-examples.mjs';
const grid=document.querySelector('#community-grid'),status=document.querySelector('#feed-status'),more=document.querySelector('#feed-more');
const dialog=document.querySelector('#work-dialog'),frame=dialog.querySelector('iframe'),title=dialog.querySelector('h2');
let config,cursor,busy=false,selectedId,selectedExample;const seen=new Set(),authors=new Map();
const headers=()=>({apikey:config.anonKey,Authorization:'Bearer '+config.anonKey});
async function read(url){const response=await fetch(url,{headers:headers(),signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('社区暂时未能连接，请重试或进入完整社区');const rows=await response.json();if(!Array.isArray(rows))throw Error('社区返回格式异常');return rows;}
function closeViewer(){frame.removeAttribute('src');if(dialog.open)dialog.close();}
dialog.querySelector('button').addEventListener('click',closeViewer);
dialog.addEventListener('close',()=>frame.removeAttribute('src'));
dialog.addEventListener('cancel',closeViewer);
function authorName(work){return work.example?work.author:authors.get(work.user_id)?.display_name||'unknown';}
function openWork(work){
 try{if(!work.example)checkModel(work);selectedId=work.id;selectedExample=Boolean(work.example);
 dialog.querySelectorAll('.work-actions a').forEach(a=>a.hidden=selectedExample);document.querySelector('#share-status').textContent='';title.textContent=work.title||'未命名作品';
 const meta=document.querySelector('#work-meta');meta.replaceChildren();
 const info=document.createElement('p');info.textContent=authorName(work)+(publishedLabel(work.published_at)?' · '+publishedLabel(work.published_at):'');meta.append(info);
 if(work.description){const description=document.createElement('p');description.textContent=work.description;meta.append(description);}
 dialog.showModal();const url=new URL('viewer/index.html',location.href);url.searchParams.set('model',work.example?new URL(work.model,location.href).href:modelUrl(config.origin,work.model_storage_path));url.searchParams.set('format',work.format);frame.src=url.href;
 }catch(e){status.textContent=e.message;}
}
async function readAuthors(rows){
 const ids=[...new Set(rows.map(w=>w.user_id).filter(Boolean))].filter(id=>!authors.has(id));
 if(!ids.length)return;
 for(const profile of await read(authorUrl(config.origin,ids)))authors.set(profile.id,profile);
}
function cardFor(work){
 const card=document.createElement('article');card.className='community-card';if(work.example)card.dataset.example=work.id;
 const open=document.createElement('button');open.type='button';open.className='community-open';open.setAttribute('aria-label','查看 '+(work.title||'未命名作品'));
 const picture=document.createElement('div');picture.className='community-picture';
 if(work.thumbnail_storage_path||work.example){try{const img=document.createElement('img');img.src=work.example?new URL(work.thumbnail,location.href).href:assetUrl(config.origin,'thumbnails',work.thumbnail_storage_path);img.alt=work.title||'三维作品';img.loading='lazy';img.decoding='async';img.addEventListener('error',()=>{img.remove();picture.textContent='3D';},{once:true});picture.append(img);}catch{picture.textContent='3D';}}else picture.textContent='3D';
 const label=document.createElement('span');label.className='community-card-title';label.textContent=work.title||'未命名作品';open.append(picture,label);open.addEventListener('click',()=>openWork(work));
 const row=document.createElement('div');row.className='community-author-row';
 const avatar=document.createElement('span');avatar.className='community-avatar';avatar.setAttribute('aria-hidden','true');
 const author=document.createElement('span');author.className='community-author';author.textContent=authorName(work);
 const like=document.createElement('a');like.className='community-like';like.href='community/';like.setAttribute('aria-label','登录后点赞');
 const heart=document.createElement('span');heart.className='community-heart';heart.setAttribute('aria-hidden','true');heart.textContent='♡';like.append(heart);
 if(Number.isSafeInteger(work.likes_count)&&work.likes_count>0){const count=document.createElement('span');count.textContent=formatCount(work.likes_count);like.append(count);}
 row.append(avatar,author);if(!work.example)row.append(like);card.append(open,row);
 const date=publishedLabel(work.published_at);if(date){const time=document.createElement('time');time.dateTime=work.published_at;time.textContent=date;card.append(time);}
 return card;
}
async function load(){
 if(busy)return;busy=true;more.disabled=true;status.textContent='正在读取社区作品…';
 try{
 config??=await fetch('community-config.json').then(r=>{if(!r.ok)throw Error();return r.json();});
 if(config.origin!=='https://api.kongye.space')throw Error('社区配置不可用');
 const rows=await read(feedUrl(config.origin,cursor));
 await readAuthors(rows);
 for(const work of rows){if(seen.has(work.id))continue;seen.add(work.id);grid.insertBefore(cardFor(work),grid.querySelector('[data-example]'));}
 cursor=rows.at(-1)||cursor;more.textContent='加载更多';status.textContent=seen.size?'点击作品，旋转、缩放查看。':'社区暂时没有公开作品。';more.hidden=rows.length<12;
 }catch(e){status.textContent=e.message||'社区暂时未能连接，请重试';more.textContent='重新加载';more.hidden=false;}
 finally{busy=false;more.disabled=false;}
}
more.addEventListener('click',load);
document.querySelector('#share-work').addEventListener('click',async()=>{
 const url=new URL(location.href);url.search='';url.hash='';url.searchParams.set(selectedExample?'example':'work',selectedId);
 const feedback=document.querySelector('#share-status');
 try{await navigator.clipboard.writeText(url.href);feedback.textContent='链接已复制';}catch{feedback.textContent=url.href;}
});
for(const work of examples)grid.append(cardFor(work));
const exampleId=new URL(location.href).searchParams.get('example');
if(exampleId){const example=examples.find(w=>w.id===exampleId);if(example)openWork(example);}
load().then(async()=>{
 const id=new URL(location.href).searchParams.get('work');if(!id||!config)return;
 try{const rows=await read(workUrl(config.origin,id));if(!rows[0])throw Error();await readAuthors(rows);openWork(rows[0]);}catch{status.textContent='分享的作品暂不可访问，可能已取消公开。';}
});
window.addEventListener('pagehide',closeViewer);
