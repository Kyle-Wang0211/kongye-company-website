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
  function renderSuggestionRows(container,titles,{onSearch,onFill}){
    container.replaceChildren();
    for(const title of titles.slice(0,10)){
      const item=document.createElement('li');item.className='pw-suggestion-row';
      const text=document.createElement('button'),fill=document.createElement('button');
      text.type=fill.type='button';text.className='pw-suggestion-text';fill.className='pw-suggestion-fill';
      text.textContent=title;text.title=label('搜索“'+title+'”','Search “'+title+'”');
      if(container.getAttribute('role')==='listbox')text.setAttribute('role','option');
      fill.textContent='↖';fill.title=label('填入搜索框继续输入','Fill search field to keep typing');
      fill.setAttribute('aria-label',label('填入“'+title+'”','Fill “'+title+'”'));
      text.addEventListener('click',()=>onSearch(title));
      fill.addEventListener('mousedown',event=>event.preventDefault());
      fill.addEventListener('click',()=>onFill(title));
      item.append(text,fill);container.append(item);
    }
  }
  const priorSearch=document.querySelector('#community-search');
  const entry=document.querySelector('#community-query');
  if(!priorSearch||!entry)return;
  priorSearch.dataset.communitySearch='';
  const suggestions=document.createElement('ul');
  suggestions.id='community-search-suggestions';suggestions.className='community-search-suggestions';
  suggestions.hidden=true;suggestions.setAttribute('role','listbox');
  entry.setAttribute('role','combobox');entry.setAttribute('aria-autocomplete','list');
  entry.setAttribute('aria-controls',suggestions.id);entry.setAttribute('aria-expanded','false');
  priorSearch.append(suggestions);
  let homeTimer,homeGeneration=0,composing=false;
  function dismissSuggestions(){
    clearTimeout(homeTimer);homeGeneration++;
    suggestions.hidden=true;entry.setAttribute('aria-expanded','false');
  }
  async function suggestHome(){
    const query=entry.value.trim(),revision=++homeGeneration;
    if(!query){dismissSuggestions();return;}
    try{
      const values=await requestCommunitySearch(await getClient(),'suggest',query);
      if(revision!==homeGeneration||entry.value.trim()!==query)return;
      renderSuggestionRows(suggestions,values,{
        onSearch:title=>{
          entry.value=title;document.querySelector('#community-search-clear').hidden=false;
          openHomeSearch();
        },
        onFill:title=>{
          entry.value=title;document.querySelector('#community-search-clear').hidden=false;
          entry.focus();queueSuggestions();
        }
      });
      suggestions.hidden=!values.length;entry.setAttribute('aria-expanded',String(values.length>0));
    }catch{if(revision===homeGeneration)dismissSuggestions();}
  }
  function queueSuggestions(){
    dismissSuggestions();
    if(entry.value.trim())homeTimer=setTimeout(()=>void suggestHome(),160);
  }
  entry.addEventListener('input',queueSuggestions);
  entry.addEventListener('compositionstart',()=>{composing=true;});
  entry.addEventListener('compositionend',()=>{composing=false;queueSuggestions();});
  entry.addEventListener('focus',()=>{if(entry.value.trim())queueSuggestions();});
  entry.addEventListener('keydown',event=>{
    if(event.key==='Escape')dismissSuggestions();
    if(event.key==='ArrowDown'&&!suggestions.hidden){event.preventDefault();suggestions.querySelector('button')?.focus();}
  });
  suggestions.addEventListener('keydown',event=>{
    const buttons=[...suggestions.querySelectorAll('.pw-suggestion-text')],index=buttons.indexOf(document.activeElement);
    if(event.key==='ArrowDown'||event.key==='ArrowUp'){
      event.preventDefault();buttons[(index+(event.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length]?.focus();
    }
    if(event.key==='Escape'){entry.focus();dismissSuggestions();}
  });
  document.addEventListener('click',event=>{if(!priorSearch.contains(event.target))dismissSuggestions();});
  document.querySelector('#community-search-clear').addEventListener('click',dismissSuggestions);
  const style=document.createElement('style');
  style.textContent=`.pw-community-search{box-sizing:border-box;width:100vw;height:100dvh;max-width:none;max-height:none;margin:0;padding:24px;border:0;background:#fff;color:#111}.pw-community-search::backdrop{background:#fff}.pw-community-search header{display:flex;align-items:center;gap:12px;max-width:900px;margin:auto}.pw-community-search input{min-width:0;flex:1;font:inherit;border:1px solid #bbb;border-radius:8px;padding:12px;background:#f5f5f5;color:#111}.pw-community-search button{font:inherit;cursor:pointer;background:#fff;border:0;color:#111;padding:12px}.pw-community-search ul{list-style:none;padding:0;max-width:900px;margin:20px auto}.pw-community-search li:not(.pw-suggestion-row) button{display:block;width:100%;text-align:left;border-bottom:1px solid #eee;padding:18px 12px}.pw-community-search [role=status]{max-width:900px;margin:20px auto;color:#666}.pw-community-search .search-retry{border:1px solid #aaa;border-radius:6px}@media(max-width:600px){.pw-community-search{padding:12px}.pw-community-search header{gap:2px}.pw-community-search button{padding:10px}}`;
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
      if(action==='suggest'){
        renderSuggestionRows(list,results,{
          onSearch:title=>{input.value=title;void run('search');},
          onFill:title=>{input.value=title;submitted=false;input.focus();void run('suggest');}
        });
      }else{
        for(const result of results){
          const item=document.createElement('li'),button=document.createElement('button');button.type='button';
          button.textContent=result.title;
          button.addEventListener('click',()=>{
            try{checkModel(result);onOpenWork(result);}catch{feedback.textContent=label('作品暂不可用','Work unavailable');}
          });
          item.append(button);list.append(item);
        }
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
  function openHomeSearch(){
    dismissSuggestions();input.value=entry.value;
    if(!input.value.trim())return;
    if(!new URL(location.href).searchParams.has('search')){const url=new URL(location.href);url.searchParams.set('search','1');history.pushState({pwCommunitySearch:true},'',url);}
    show();void run('search');
  }
  priorSearch.addEventListener('submit',event=>{event.preventDefault();if(!composing)openHomeSearch();});
  input.addEventListener('input',()=>{invalidate();submitted=false;if(input.value.trim())timer=setTimeout(()=>void run('suggest'),200);});
  input.addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.isComposing){event.preventDefault();void run('search');}});
  clear.addEventListener('click',()=>{input.value='';submitted=false;invalidate();input.focus();});
  submit.addEventListener('click',()=>void run('search'));
  back.addEventListener('click',leave);
  page.addEventListener('cancel',event=>{event.preventDefault();leave();});
  window.addEventListener('popstate',()=>{if(new URL(location.href).searchParams.has('search')){show();if(input.value.trim())void run(submitted?'search':'suggest');}else close();});
  if(new URL(location.href).searchParams.has('search'))show();
}
