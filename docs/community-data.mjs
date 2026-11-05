import {t} from './site-l10n.mjs?v=shared-community-20261106-v40';
export {t, currentLocale, localizeElement, initSiteLocale, localeReady, localeEvent} from './site-l10n.mjs?v=shared-community-20261106-v40';
export function translatedError(key){const error=new Error(t(key));error.localeKey=key;return error;}
export function feedUrl(origin, cursor) {
  const url = new URL('/rest/v1/works', origin);
  url.search = new URLSearchParams({select:'id,user_id,title,description,format,model_storage_path,thumbnail_storage_path,file_size_bytes,likes_count,published_at,initial_view', visibility:'eq.public',published_at:'not.is.null',moderation_status:'eq.ok',order:'published_at.desc,id.desc',limit:'12'});
  if(cursor) {
    if(!/^[0-9a-f-]{36}$/i.test(cursor.id)||!/^\d{4}-\d\d-\d\dT[\d:.+Z-]+$/.test(cursor.published_at)) throw translatedError('siteInvalidCursor');
    url.searchParams.set('or',`(published_at.lt.${cursor.published_at},and(published_at.eq.${cursor.published_at},id.lt.${cursor.id}))`);
  }
  return url;
}
const publicationCoverPath=/^\/functions\/v1\/publication-cover[?]work_id=([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})$/;
export function publicationCoverAspect(work) {
  const path = work.thumbnail_storage_path;
  const cover = typeof path === 'string' ? publicationCoverPath.exec(path) : null;
  const view = work.initial_view;
  if (!cover || typeof work.id !== 'string' ||
      cover[1].toLowerCase() !== work.id.toLowerCase() ||
      view?.schema !== 'pw.camera-framing.v1' ||
      !Number.isFinite(view.aspect) || view.aspect < .1 || view.aspect > 10) {
    return null;
  }
  return view.aspect;
}
export function assetUrl(origin,bucket,path) {
  if (bucket === 'thumbnails' && typeof path === 'string' && publicationCoverPath.test(path)) {
    const api = new URL(origin);
    if (api.protocol !== 'https:') throw translatedError('siteInvalidAsset');
    return new URL(path, api.origin).href;
  }
  if(!['works','thumbnails'].includes(bucket)||typeof path!=='string'||!path||path.startsWith('/')||path.split('/').some(p=>!p||p==='.'||p==='..')||/[\\?#:]/.test(path))throw translatedError('siteInvalidAsset');
  return new URL('/storage/v1/object/public/'+bucket+'/'+path.split('/').map(encodeURIComponent).join('/'),origin).href;
}
export function checkModel(work){
  if(!['glb','ply'].includes(work.format))throw translatedError('siteUnsupportedFormat');
  if(!Number.isSafeInteger(work.file_size_bytes)||work.file_size_bytes<=0||work.file_size_bytes>128*1024*1024)throw translatedError('siteLargeWork');
}

export function workUrl(origin,id){
 if(!/^[0-9a-f-]{36}$/i.test(id))throw translatedError('siteInvalidWork');
 const url=feedUrl(origin);url.searchParams.set('id','eq.'+id);url.searchParams.set('limit','1');return url;
}

export function authorUrl(origin,ids){
 const unique=[...new Set(ids)];
 if(unique.length>12||unique.some(id=>!/^[0-9a-f-]{36}$/i.test(id)))throw translatedError('siteInvalidAuthors');
 const url=new URL('/rest/v1/community_author_profiles',origin);
 url.search=new URLSearchParams({select:'id,display_name,avatar_url,handle',id:'in.('+unique.join(',')+')'});return url;
}
// Same count thresholds as production WorkCard.formatCount.
export function formatCount(n){if(!Number.isSafeInteger(n)||n<0)return '';if(n>=10000)return Math.round(n/1000)+'K';if(n>=1000)return (n/1000).toFixed(1)+'K';return String(n);}
export function publishedLabel(value,now=new Date()){
 const date=new Date(value);if(!value||!Number.isFinite(date.getTime())||!Number.isFinite(now.getTime()))return '';
 const elapsed=now.getTime()-date.getTime();
 if(elapsed>=0&&elapsed<=86400000)return String(date.getHours()).padStart(2,'0')+':'+String(date.getMinutes()).padStart(2,'0');
 const day=d=>Date.UTC(d.getFullYear(),d.getMonth(),d.getDate());const days=(day(now)-day(date))/86400000;
 if(days===1)return t('siteYesterday');if(days===2)return t('siteDayBeforeYesterday');
 return t('siteMonthDay',{month:date.getMonth()+1,day:date.getDate()});
}

export function modelUrl(origin,path){
 if(typeof path==='string'&&/^[a-f0-9]{64}\/source[.]glb$/.test(path)){const url=new URL('/functions/v1/publication-model',origin);url.searchParams.set('path',path);return url.href;}
 return assetUrl(origin,'works',path);
}
