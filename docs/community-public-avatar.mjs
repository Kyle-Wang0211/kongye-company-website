import {avatarDataUrl} from './community-account-data.mjs';

// Only public-author PNGs are cached; private sessions never enter this reader.
export function createPublicAvatarReader({origin,anonKey,fetcher=fetch,now=Date.now,maxEntries=256}){
 const cache=new Map(),pending=new Map();let epoch=0;
 const limit=Math.max(1,Math.min(256,Number.isSafeInteger(maxEntries)?maxEntries:256));
 const storageKey='pw-public-author-avatars-v1:'+origin;
 let stored=new Map();
 try{const rows=JSON.parse(sessionStorage.getItem(storageKey)||'[]');if(Array.isArray(rows))stored=new Map(rows.filter(row=>Array.isArray(row)&&row.length===2).slice(-limit));}catch{}
 function persist(){try{sessionStorage.setItem(storageKey,JSON.stringify([...stored].slice(-limit)));}catch{}}
 function remember(id,row){cache.delete(id);cache.set(id,row);while(cache.size>limit)cache.delete(cache.keys().next().value);}
 function clear(){epoch++;cache.clear();pending.clear();stored.clear();try{sessionStorage.removeItem(storageKey);}catch{}}
 // Synchronous access is restricted to PNGs already verified in this document.
 function peek(id){const row=cache.get(id);return row?.until>now()?row.src:null;}
 async function read(id){
  if(origin!=='https://api.kongye.space'||typeof anonKey!=='string'||!(/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i).test(id))return null;
  const cached=cache.get(id);if(cached&&cached.until>now())return cached.src;
  cache.delete(id);if(pending.has(id))return pending.get(id);
  const generation=epoch;
  const request=(async()=>{
   try{
    const saved=stored.get(id);
    if(saved&&Number.isFinite(saved.until)&&saved.until>now()&&saved.until<=now()+300000){
     const src=saved.avatar?await avatarDataUrl(saved.avatar):null;
     if(generation!==epoch)return null;
     if(src||saved.missing===true){remember(id,{src,until:saved.until});return src;}
    }
    stored.delete(id);
    const response=await fetcher(origin+'/functions/v1/read-generated-avatar',{method:'POST',headers:{apikey:anonKey,Authorization:'Bearer '+anonKey,'Content-Type':'application/json'},body:JSON.stringify({profile_user_id:id,context:'public'}),cache:'no-store',signal:AbortSignal.timeout(15000)});
    if(!response.ok&&response.status!==404)return null;
    const avatar=response.status===404?null:(await response.json())?.avatar;
    const src=avatar?await avatarDataUrl(avatar):null;
    if(generation===epoch&&(src||response.status===404)){
     const until=now()+(src?300000:30000);remember(id,{src,until});
     stored.delete(id);stored.set(id,{avatar,missing:response.status===404,until});while(stored.size>limit)stored.delete(stored.keys().next().value);persist();
    }
    return generation===epoch?src:null;
   }catch{return null;}
  })();
  pending.set(id,request);
  try{return await request;}finally{if(pending.get(id)===request)pending.delete(id);}
 }
 return {read,peek,clear};
}
