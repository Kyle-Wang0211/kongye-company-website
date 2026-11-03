import {avatarDataUrl} from './community-account-data.mjs';

// Read only the backend's public-author projection. Never forward a private session.
export function createPublicAvatarReader({origin,anonKey,fetcher=fetch,now=Date.now,maxEntries=256}){
 const cache=new Map(),pending=new Map();let epoch=0;
 const limit=Math.max(1,Math.min(256,Number.isSafeInteger(maxEntries)?maxEntries:256));
 function clear(){epoch++;cache.clear();pending.clear();}
 async function read(id){
  if(origin!=='https://api.kongye.space'||typeof anonKey!=='string'||!(/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i).test(id))return null;
  const cached=cache.get(id);if(cached&&cached.until>now())return cached.src;
  cache.delete(id);if(pending.has(id))return pending.get(id);
  const generation=epoch;
  const request=(async()=>{
   try{
    const response=await fetcher(origin+'/functions/v1/read-generated-avatar',{method:'POST',headers:{apikey:anonKey,Authorization:'Bearer '+anonKey,'Content-Type':'application/json'},body:JSON.stringify({profile_user_id:id,context:'public'}),cache:'no-store',signal:AbortSignal.timeout(15000)});
    if(!response.ok&&response.status!==404)return null;
    const src=response.status===404?null:await avatarDataUrl((await response.json())?.avatar);
    if(generation===epoch&&(src||response.status===404)){
     cache.set(id,{src,until:now()+(src?300000:30000)});
     while(cache.size>limit)cache.delete(cache.keys().next().value);
    }
    return src;
   }catch{return null;}
  })();
  pending.set(id,request);
  try{return await request;}finally{if(pending.get(id)===request)pending.delete(id);}
 }
 return {read,clear};
}
