import {feedUrl,checkModel,currentLocale} from './community-data.mjs?v=account-library-20261106-v44';

export async function requestCommunitySearch(client, action, query) {
  const {data,error}=await client.rpc('community_search',{p_action:action,p_query:query.trim()});
  if(error||!data||typeof data!=='object')throw Error('Search unavailable');
  if(action==='suggest'){
    if(!Array.isArray(data.suggestions)||data.suggestions.some(value=>typeof value!=='string'))throw Error('Invalid suggestions');
    return data.suggestions;
  }
  if(!Array.isArray(data.works)||data.works.some(value=>typeof value?.id!=='string'||!/^[0-9a-f-]{36}$/i.test(value.id)))throw Error('Invalid works');
  return data.works.map(value=>value.id);
}

export async function hydrateSearchWorks(client,config,ids){
  if(!ids.length)return [];
  const {data,error}=await client.from('works').select(feedUrl(config.origin).searchParams.get('select'))
    .in('id',ids).eq('visibility','public').eq('moderation_status','ok')
    .is('deleted_at',null).not('published_at','is',null);
  if(error||!Array.isArray(data))throw Error('Search unavailable');
  const byId=new Map(data.map(work=>[work.id,work]));
  return ids.filter(id=>byId.has(id)).map(id=>byId.get(id));
}

export function installCommunitySearch({getClient,getConfig,onOpenWork}){
  const header=document.querySelector('.community-header');
  if(!header||header.querySelector('[data-community-search]'))return;
  const zh=()=>currentLocale()==='zh';
  const label=(cn,en)=>zh()?cn:en;
  const entry=document.createElement('button');
  entry.type='button';entry.className='header-action';entry.dataset.communitySearch='';
  entry.textContent=label('搜索','Search');
  entry.setAttribute('aria-label',label('搜索作品','Search works'));
  header.insertBefore(entry,header.querySelector('#account-nav'));
  const style=document.createElement('style');
  style.textContent=`.pw-community-search{box-sizing:border-box;width:100vw;height:100dvh;max-width:none;max-height:none;margin:0;padding:24px;border:0;background:#fff;color:#111}.pw-community-search::backdrop{background:#fff}.pw-community-search header{display:flex;align-items:center;gap:12px;max-width:900px;margin:auto}.pw-community-search input{min-width:0;flex:1;font:inherit;border:1px solid #bbb;border-radius:8px;padding:12px;background:#f5f5f5;color:#111}.pw-community-search button{font:inherit;cursor:pointer;background:#fff;border:0;color:#111;padding:12px}.pw-community-search ul{list-style:none;padding:0;max-width:900px;margin:20px auto}.pw-community-search li button{display:block;width:100%;text-align:left;border-bottom:1px solid #eee;padding:18px 12px}.pw-community-search [role=status]{max-width:900px;margin:20px auto;color:#666}.pw-community-search .search-retry{border:1px solid #aaa;border-radius:6px}@media(max-width:600px){.pw-community-search{padding:12px}.pw-community-search header{gap:2px}.pw-community-search button{padding:10px}}`;
  document.head.append(style);
  const page=document.createElement('dialog');page.className='pw-community-search';
  page.setAttribute('aria-label',label('搜索作品','Search works'));
  const bar=document.createElement('header'),back=document.createElement('button'),input=document.createElement('input'),clear=document.createElement('button'),submit=document.createElement('button');
  for(const button of [back,clear,submit])button.type='button';
  back.textContent=label('返回','Back');input.type='search';input.maxLength=128;input.placeholder=label('搜索作品','Search works');input.setAttribute('aria-label',input.placeholder);
  clear.textContent=label('清除','Clear');submit.textContent=label('搜索','Search');
  const feedback=document.createElement('p');feedback.setAttribute('role','status');
  const list=document.createElement('ul');
  bar.append(back,input,clear,submit);page.append(bar,feedback,list);document.body.append(page);
  let generation=0,timer,submitted=false;
  function invalidate(){clearTimeout(timer);generation++;list.replaceChildren();feedback.replaceChildren();}
  async function run(action){
    const query=input.value.trim();invalidate();if(!query)return;
    submitted=action==='search';const revision=generation;
    feedback.textContent=label('加载中…','Loading…');
    try{
      const client=await getClient();
      const values=await requestCommunitySearch(client,action,query);
      const results=action==='search'?await hydrateSearchWorks(client,getConfig(),values):values;
      if(revision!==generation||!page.open)return;
      feedback.textContent=results.length?'':label('未找到相关作品','No matching works');
      for(const result of results){
        const item=document.createElement('li'),button=document.createElement('button');button.type='button';
        button.textContent=action==='search'?result.title:result;
        button.addEventListener('click',()=>{
          if(action==='suggest'){input.value=result;void run('search');}
          else{try{checkModel(result);onOpenWork(result);}catch{feedback.textContent=label('作品暂不可用','Work unavailable');}}
        });
        item.append(button);list.append(item);
      }
    }catch{
      if(revision!==generation||!page.open)return;
      feedback.textContent=label('搜索暂不可用','Search unavailable');
      const retry=document.createElement('button');retry.type='button';retry.className='search-retry';retry.textContent=label('重试','Retry');retry.addEventListener('click',()=>void run(action));feedback.append(retry);
    }
  }
  function show(){if(!page.open)page.showModal();input.focus();}
  function close(){invalidate();page.close();entry.focus();}
  function leave(){
    if(history.state?.pwCommunitySearch)history.back();
    else{const url=new URL(location.href);url.searchParams.delete('search');history.replaceState(history.state,'',url);close();}
  }
  entry.addEventListener('click',()=>{
    if(!new URL(location.href).searchParams.has('search')){const url=new URL(location.href);url.searchParams.set('search','1');history.pushState({pwCommunitySearch:true},'',url);}
    show();
  });
  input.addEventListener('input',()=>{invalidate();submitted=false;if(input.value.trim())timer=setTimeout(()=>void run('suggest'),200);});
  input.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();void run('search');}});
  clear.addEventListener('click',()=>{input.value='';submitted=false;invalidate();input.focus();});
  submit.addEventListener('click',()=>void run('search'));
  back.addEventListener('click',leave);
  page.addEventListener('cancel',event=>{event.preventDefault();leave();});
  window.addEventListener('popstate',()=>{if(new URL(location.href).searchParams.has('search')){show();if(input.value.trim())void run(submitted?'search':'suggest');}else close();});
  if(new URL(location.href).searchParams.has('search'))show();
}
