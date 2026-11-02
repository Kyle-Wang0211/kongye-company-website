import {feedUrl,workUrl,assetUrl,checkModel} from './community-data.mjs';
const grid=document.querySelector('#community-grid'),status=document.querySelector('#feed-status'),more=document.querySelector('#feed-more');
const dialog=document.querySelector('#work-dialog'),frame=dialog.querySelector('iframe'),title=dialog.querySelector('h2');
let config,cursor,busy=false,selectedId;const seen=new Set();
function closeViewer(){frame.removeAttribute('src');if(dialog.open)dialog.close();}
dialog.querySelector('button').addEventListener('click',closeViewer);
dialog.addEventListener('close',()=>frame.removeAttribute('src'));
dialog.addEventListener('cancel',closeViewer);
function openWork(work){
 try{checkModel(work);document.querySelectorAll('.scan-card[open]').forEach(c=>{c.open=false;c.querySelector('iframe').removeAttribute('src');});
 selectedId=work.id;document.querySelector('#share-status').textContent='';title.textContent=work.title||'未命名作品';dialog.showModal();
 const url=new URL('viewer/index.html',location.href);url.searchParams.set('model',assetUrl(config.origin,'works',work.model_storage_path));url.searchParams.set('format',work.format);frame.src=url.href;
 }catch(e){status.textContent=e.message;}
}
async function load(){
 if(busy)return;busy=true;more.disabled=true;status.textContent='正在读取社区作品…';
 try{
 config??=await fetch('community-config.json').then(r=>{if(!r.ok)throw Error();return r.json();});
 if(config.origin!=='https://api.kongye.space')throw Error('社区配置不可用');
 const response=await fetch(feedUrl(config.origin,cursor),{headers:{apikey:config.anonKey,Authorization:'Bearer '+config.anonKey},signal:AbortSignal.timeout(15000)});
 if(!response.ok)throw Error('社区暂时未能连接，请重试或进入完整社区');
 const rows=await response.json();if(!Array.isArray(rows))throw Error('社区返回格式异常');
 for(const work of rows){if(seen.has(work.id))continue;seen.add(work.id);
 const card=document.createElement('button');card.type='button';card.className='community-card';
 const picture=document.createElement('div');picture.className='community-picture';
 if(work.thumbnail_storage_path){try{const img=document.createElement('img');img.src=assetUrl(config.origin,'thumbnails',work.thumbnail_storage_path);img.alt=work.title||'三维作品';img.loading='lazy';img.decoding='async';img.addEventListener('error',()=>{img.remove();picture.textContent='3D';},{once:true});picture.append(img);}catch{picture.textContent='3D';}}else picture.textContent='3D';
 const label=document.createElement('span');label.className='community-card-title';label.textContent=work.title||'未命名作品';
 const action=document.createElement('span');action.className='community-card-action';action.textContent='打开作品 ↗';card.append(picture,label,action);card.addEventListener('click',()=>openWork(work));grid.append(card);
 }
 cursor=rows.at(-1)||cursor;more.textContent='加载更多';status.textContent=seen.size?'点击作品，旋转、缩放查看。':'社区暂时没有公开作品。';more.hidden=rows.length<12;
 }catch(e){status.textContent=e.message||'社区暂时未能连接，请重试';more.textContent='重新加载';more.hidden=false;}
 finally{busy=false;more.disabled=false;}
}
more.addEventListener('click',load);
document.querySelector('#share-work').addEventListener('click',async()=>{
 const url=new URL(location.href);url.search='';url.hash='';url.searchParams.set('work',selectedId);
 const feedback=document.querySelector('#share-status');
 try{await navigator.clipboard.writeText(url.href);feedback.textContent='链接已复制';}catch{feedback.textContent=url.href;}
});
load().then(async()=>{
 const id=new URL(location.href).searchParams.get('work');if(!id||!config)return;
 try{const response=await fetch(workUrl(config.origin,id),{headers:{apikey:config.anonKey,Authorization:'Bearer '+config.anonKey},signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error();const rows=await response.json();if(!rows[0])throw Error();openWork(rows[0]);}catch{status.textContent='分享的作品暂不可访问，可能已取消公开。';}
});
window.addEventListener('pagehide',closeViewer);
