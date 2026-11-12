import {feedUrl,formatCount,currentLocale} from './community-data.mjs?v=account-library-20261106-v44';

export async function requestCommunitySearch(client, action, query) {
  const {data,error}=await client.rpc('community_search',{p_action:action,p_query:query.trim()});
  if(error||!data||typeof data!=='object')throw Error('Search unavailable');
  if(action==='users'){
    if(!Array.isArray(data.users)||data.users.some(user=>
      typeof user?.id!=='string'||!/^[0-9a-f-]{36}$/i.test(user.id)||
      typeof user.display_name!=='string'||
      (user.avatar_url!==null&&typeof user.avatar_url!=='string')||
      typeof user.public_account_number!=='string'||
      !Number.isSafeInteger(user.follower_count)||user.follower_count<0))throw Error('Invalid users');
    return data.users;
  }
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

export function installCommunitySearch({getClient,getConfig,createCard,attachWorkGrid,onWorkCardsRendered,clearResults,renderUserAvatar,getViewerId}){
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
    if(entry.value.trim())homeTimer=setTimeout(()=>void suggestHome(),200);
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
  style.textContent=`.pw-community-search{box-sizing:border-box;width:100vw;height:100dvh;max-width:none;max-height:none;margin:0;padding:24px;border:0;background:#fff;color:#111}.pw-community-search::backdrop{background:#fff}.pw-community-search header{display:flex;align-items:center;gap:12px;max-width:900px;margin:auto}.pw-community-search input{min-width:0;flex:1;font:inherit;border:1px solid #bbb;border-radius:8px;padding:12px;background:#f5f5f5;color:#111}.pw-community-search header>button{font:inherit;cursor:pointer;background:#fff;border:0;color:#111;padding:12px}.pw-community-search [role=status]{max-width:1600px;margin:20px auto;color:#666}.pw-community-search .search-retry{border:1px solid #aaa;border-radius:6px;background:#fff;padding:8px 12px;cursor:pointer}@media(max-width:600px){.pw-community-search{padding:12px}.pw-community-search header{gap:2px}.pw-community-search header>button{padding:10px}}`;
  document.head.append(style);
  const page=document.createElement('dialog');page.className='pw-community-search';
  page.setAttribute('aria-label',label('搜索作品','Search works'));
  const bar=document.createElement('header'),back=document.createElement('button'),input=document.createElement('input'),clear=document.createElement('button'),submit=document.createElement('button');
  for(const button of [back,clear,submit])button.type='button';
  back.textContent=label('返回','Back');input.type='search';input.maxLength=128;input.placeholder=label('搜索作品或用户','Search works or users');input.setAttribute('aria-label',input.placeholder);
  clear.textContent=label('清除','Clear');submit.textContent=label('搜索','Search');
  const inputGroup=document.createElement('div');inputGroup.className='pw-search-input-group';
  const liveSuggestions=document.createElement('ul');liveSuggestions.className='pw-search-suggestions';liveSuggestions.hidden=true;liveSuggestions.setAttribute('role','listbox');
  inputGroup.append(input,liveSuggestions);
  const tabs=document.createElement('div');tabs.className='pw-search-tabs';tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label',label('搜索结果','Search results'));
  const workTab=document.createElement('button'),userTab=document.createElement('button');
  workTab.textContent=label('作品','Works');userTab.textContent=label('用户','Users');
  for(const button of [workTab,userTab]){button.type='button';button.setAttribute('role','tab');}
  workTab.id='pw-search-work-tab';userTab.id='pw-search-user-tab';tabs.append(workTab,userTab);
  const feedback=document.createElement('p');feedback.setAttribute('role','status');
  const resultsArea=document.createElement('div');resultsArea.className='pw-search-results';
  const workGrid=document.createElement('div');workGrid.className='community-grid pw-search-work-grid';workGrid.id='pw-search-works';
  const userList=document.createElement('div');userList.className='pw-search-users';userList.id='pw-search-users';
  workGrid.setAttribute('role','tabpanel');userList.setAttribute('role','tabpanel');
  workTab.setAttribute('aria-controls',workGrid.id);userTab.setAttribute('aria-controls',userList.id);
  workGrid.setAttribute('aria-labelledby',workTab.id);userList.setAttribute('aria-labelledby',userTab.id);
  resultsArea.append(workGrid,userList);bar.append(back,inputGroup,clear,submit);page.append(bar,tabs,feedback,resultsArea);document.body.append(page);
  attachWorkGrid(workGrid);
  let generation=0,timer,activeTab='works';
  function updateTabs(){
    workTab.setAttribute('aria-selected',String(activeTab==='works'));
    userTab.setAttribute('aria-selected',String(activeTab==='users'));
    workGrid.hidden=activeTab!=='works';userList.hidden=activeTab!=='users';
  }
  updateTabs();
  function invalidate(){
    clearTimeout(timer);generation++;clearResults(resultsArea);
    workGrid.replaceChildren();userList.replaceChildren();liveSuggestions.replaceChildren();liveSuggestions.hidden=true;feedback.replaceChildren();
  }
  function renderUsers(users,client,revision){
    const current=()=>revision===generation&&page.open&&activeTab==='users';
    for(const user of users){
      const row=document.createElement('div');row.className='pw-search-user-row';
      const link=document.createElement('a');link.className='following-person';link.href='/community/?profile='+encodeURIComponent(user.id);
      const avatar=document.createElement('span');avatar.className='following-avatar';avatar.setAttribute('aria-hidden','true');
      const identity=document.createElement('span');identity.className='pw-search-user-identity';
      const name=document.createElement('strong');name.textContent=user.display_name;
      const meta=document.createElement('span');meta.className='pw-search-user-meta';
      const followers=document.createElement('span');
      const renderCount=count=>{followers.textContent=label(formatCount(count)+'粉丝',formatCount(count)+' followers');};
      renderCount(user.follower_count);
      const number=document.createElement('span');number.textContent=label('窗后城号 '+user.public_account_number,'ID '+user.public_account_number);
      meta.append(followers,number);identity.append(name,meta);link.append(avatar,identity);row.append(link);userList.append(row);
      renderUserAvatar(avatar,user);
      if(getViewerId()===user.id)continue;
      const follow=document.createElement('button');follow.type='button';follow.className='pw-search-follow';row.append(follow);
      let profile;
      async function loadState(){
        follow.disabled=true;follow.textContent=label('加载中…','Loading…');
        try{
          const {data,error}=await client.rpc('get_social_profile',{p_user_id:user.id});
          if(error||!Array.isArray(data)||!data[0])throw Error('Follow unavailable');
          if(!current())return;
          profile=data[0];
          if(Number.isSafeInteger(profile.followers_count))renderCount(profile.followers_count);
          follow.textContent=profile.is_following?label('已关注','Following'):label('关注','Follow');
          follow.setAttribute('aria-pressed',String(!!profile.is_following));follow.onclick=()=>void toggleFollow();
        }catch{
          if(!current())return;
          follow.textContent=label('重试','Retry');follow.onclick=()=>void loadState();
        }finally{if(current())follow.disabled=false;}
      }
      async function toggleFollow(){
        follow.disabled=true;
        try{
          const {data:session,error:sessionError}=await client.auth.getSession();
          if(sessionError)throw sessionError;
          if(!session.session){location.assign('/community/?auth=signin');return;}
          const {data,error}=await client.auth.getUser();
          if(error)throw error;
          if(!data.user){location.assign('/community/?auth=signin');return;}
          if(data.user.id===user.id){follow.hidden=true;return;}
          const request=profile.is_following
            ?client.from('follows').delete().eq('follower_id',data.user.id).eq('followee_id',user.id)
            :client.from('follows').upsert({follower_id:data.user.id,followee_id:user.id},{onConflict:'follower_id,followee_id',ignoreDuplicates:true});
          const result=await request;if(result.error)throw result.error;
          await loadState();
        }catch{if(current()){follow.textContent=label('重试','Retry');follow.onclick=()=>void loadState();}}
        finally{if(current())follow.disabled=false;}
      }
      void loadState();
    }
  }
  async function runResults({showSuggestions=false}={}){
    const query=input.value.trim();invalidate();updateTabs();if(!query)return;
    const revision=generation,tab=activeTab;
    feedback.textContent=label('加载中…','Loading…');
    try{
      const client=await getClient();
      const titles=showSuggestions?requestCommunitySearch(client,'suggest',query).catch(()=>[]):Promise.resolve([]);
      const values=requestCommunitySearch(client,tab==='users'?'users':'search',query);
      const [suggested,found]=await Promise.all([titles,values]);
      const results=tab==='works'?await hydrateSearchWorks(client,getConfig(),found):found;
      if(revision!==generation||!page.open)return;
      feedback.textContent=results.length?'':(tab==='users'?label('未找到相关用户','No matching users'):label('未找到相关作品','No matching works'));
      if(tab==='works'){
        workGrid.replaceChildren(...results.map(createCard));onWorkCardsRendered(results);
      }else renderUsers(results,client,revision);
      if(showSuggestions&&document.activeElement===input&&suggested.length){
        renderSuggestionRows(liveSuggestions,suggested,{
          onSearch:title=>{input.value=title;activeTab='works';void runResults();},
          onFill:title=>{input.value=title;input.focus();void runResults({showSuggestions:true});}
        });
        liveSuggestions.hidden=false;
      }
    }catch{
      if(revision!==generation||!page.open)return;
      feedback.textContent=label('搜索暂不可用','Search unavailable');
      const retry=document.createElement('button');retry.type='button';retry.className='search-retry';retry.textContent=label('重试','Retry');retry.addEventListener('click',()=>void runResults());feedback.append(retry);
    }
  }
  function show(){if(!page.open)page.showModal();input.focus();}
  function close(){invalidate();page.close();entry.focus();}
  function leave(){
    if(history.state?.pwCommunitySearch)history.back();
    else{const url=new URL(location.href);url.searchParams.delete('search');history.replaceState(history.state,'',url);close();}
  }
  function openHomeSearch(){
    dismissSuggestions();input.value=entry.value;if(!input.value.trim())return;
    if(!new URL(location.href).searchParams.has('search')){const url=new URL(location.href);url.searchParams.set('search','1');history.pushState({pwCommunitySearch:true},'',url);}
    activeTab='works';show();void runResults();
  }
  priorSearch.addEventListener('submit',event=>{event.preventDefault();if(!composing)openHomeSearch();});
  input.addEventListener('input',()=>{invalidate();if(input.value.trim())timer=setTimeout(()=>void runResults({showSuggestions:true}),200);});
  input.addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.isComposing){event.preventDefault();void runResults();}});
  clear.addEventListener('click',()=>{input.value='';invalidate();input.focus();});
  submit.addEventListener('click',()=>void runResults());
  for(const [button,tab] of [[workTab,'works'],[userTab,'users']])button.addEventListener('click',()=>{if(activeTab!==tab){activeTab=tab;updateTabs();void runResults();}});
  page.addEventListener('click',event=>{if(!inputGroup.contains(event.target))liveSuggestions.hidden=true;});
  back.addEventListener('click',leave);page.addEventListener('cancel',event=>{event.preventDefault();leave();});
  window.addEventListener('popstate',()=>{if(new URL(location.href).searchParams.has('search')){show();if(input.value.trim())void runResults();}else close();});
  if(new URL(location.href).searchParams.has('search'))show();
}
