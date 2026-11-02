export function feedUrl(origin, cursor) {
  const url = new URL('/rest/v1/works', origin);
  url.search = new URLSearchParams({select:'id,title,format,model_storage_path,thumbnail_storage_path,file_size_bytes,published_at', visibility:'eq.public',published_at:'not.is.null',moderation_status:'eq.ok',order:'published_at.desc,id.desc',limit:'12'});
  if(cursor) {
    if(!/^[0-9a-f-]{36}$/i.test(cursor.id)||!/^\d{4}-\d\d-\d\dT[\d:.+Z-]+$/.test(cursor.published_at)) throw Error('无效作品游标');
    url.searchParams.set('or',`(published_at.lt.${cursor.published_at},and(published_at.eq.${cursor.published_at},id.lt.${cursor.id}))`);
  }
  return url;
}
export function assetUrl(origin,bucket,path) {
  if(!['works','thumbnails'].includes(bucket)||typeof path!=='string'||!path||path.startsWith('/')||path.split('/').some(p=>!p||p==='.'||p==='..')||/[\\?#:]/.test(path))throw Error('无效作品地址');
  return new URL('/storage/v1/object/public/'+bucket+'/'+path.split('/').map(encodeURIComponent).join('/'),origin).href;
}
export function checkModel(work){
  if(!['glb','ply'].includes(work.format))throw Error('请在社区中查看此格式');
  if(!Number.isSafeInteger(work.file_size_bytes)||work.file_size_bytes<=0||work.file_size_bytes>128*1024*1024)throw Error('该作品较大或大小未确认，请进入完整社区查看');
}

export function workUrl(origin,id){
 if(!/^[0-9a-f-]{36}$/i.test(id))throw Error('无效作品链接');
 const url=feedUrl(origin);url.searchParams.set('id','eq.'+id);url.searchParams.set('limit','1');return url;
}
