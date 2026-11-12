// Account transport reuses Supabase's official session lifecycle, not a second login system.
export async function readAccount(client){
 const {data:cached,error:sessionError}=await client.auth.getSession();if(sessionError)throw sessionError;
 if(!cached.session)return null;
 const {data,error}=await client.auth.getUser();
 if(error){if(error.status===401||error.status===403)return null;throw error;}
 if(!data.user)return null;
 const id=data.user.id;
 const {data:profile,error:profileError}=await client.rpc('get_social_profile',{p_user_id:id});
 const {data:latest}=await client.auth.getSession();if(latest.session?.user.id!==id)return null;
 const meta=data.user.user_metadata||{};
 if(profileError)throw profileError;
 const social=profile?.[0];
 const count=value=>Number.isSafeInteger(value)&&value>=0?value:null;
 return {id,name:social?.display_name||meta.display_name||meta.full_name||meta.name||'',
  following_count:count(social?.following_count),followers_count:count(social?.followers_count),
  public_account_number:typeof social?.public_account_number==='string'?social.public_account_number:null};
}
export async function avatarDataUrl(value){
 if(value?.version!=='jdenticon-3.3.0-pw-v2'||typeof value.png_base64!=='string'||value.png_base64.length>22000||!(/^[a-f0-9]{64}$/).test(value.png_sha256)||!(/^[a-f0-9]{64}$/).test(value.pixel_sha256))return null;
 try{
  const png=Uint8Array.from(atob(value.png_base64),c=>c.charCodeAt(0));
  if(png.length<100||png.length>16384||[137,80,78,71,13,10,26,10].some((b,i)=>png[i]!==b))return null;
  const view=new DataView(png.buffer);if(view.getUint32(16)!==128||view.getUint32(20)!==128)return null;
  const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',png))].map(x=>x.toString(16).padStart(2,'0')).join('');
  return hash===value.png_sha256?'data:image/png;base64,'+value.png_base64:null;
 }catch{return null;}
}
