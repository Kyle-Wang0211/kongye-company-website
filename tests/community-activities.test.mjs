import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {ActivityEditor,listActivities,normalizeActivities,carouselPosition,selectedActivityIndex,safeActivityUrl,bindActivityDetail} from '../docs/community-activities.mjs';
const content={title:'活动',cover_url:'https://kongye.space/a.png',sort_order:2,template_key:'article',detail:{sections:[]}};
const row={id:'id-1',slug:'one',revision:1,content};
test('catalog public read honors successful empty and arbitrary length lists',async()=>{
 let name;
 assert.deepEqual(await listActivities({rpc:async value=>{name=value;return {data:[]};}}),[]);assert.equal(name,'list_community_activities');
 const rows=normalizeActivities(Array.from({length:8},(_,i)=>({...row,id:'id-'+i,slug:'item-'+i,content:{...content,sort_order:8-i}})));
 assert.equal(rows.length,8);assert.equal(rows[0].id,'id-7');assert.equal(selectedActivityIndex(rows,'id-3'),4);
 assert.equal(selectedActivityIndex([],null),0);
 assert.throws(()=>normalizeActivities(null));assert.throws(()=>normalizeActivities([row,row]));
});
test('carousel keeps one center and at most two neighbors for all counts',()=>{
 for(let count=1;count<=10;count++)for(let selected=0;selected<count;selected++){
  const positions=Array.from({length:count},(_,i)=>carouselPosition(i,selected,count));
  assert.equal(positions.filter(x=>x==='center').length,1);assert.equal(positions.filter(x=>x!=='hidden').length,Math.min(count,3));
 }
});
test('trusted URLs reject schemes, credentials, foreign covers and encoded evasions',()=>{
 for(const value of ['javascript:alert(1)','data:image/svg+xml,x','//evil.example/a','https://kongye.space.evil/a','https://u:p@kongye.space/a','https://kongye.space\\@evil/a',' https://kongye.space/a','https://evil.test/a'])assert.throws(()=>safeActivityUrl(value));
 assert.equal(safeActivityUrl('/assets/a.png'),'https://kongye.space/assets/a.png');
 assert.equal(safeActivityUrl('https://commons.wikimedia.org/a',{external:true}),'https://commons.wikimedia.org/a');
});
function clientWith(handler){return {auth:{getSession:async()=>({data:{session:{user:{id:'owner'}}}})},rpc:handler};}
test('editor uses exact RPC args and immutable expected draft revision',async()=>{
 const calls=[];const client=clientWith(async(...args)=>{calls.push(args);return {data:{id:'one',draft_revision:4}};});
 const editor=new ActivityEditor(client);const old={id:'one',slug:'ceramic',draft_revision:3};
 for(const action of ['list','save','publish','withdraw'])await editor.manage(action,action==='list'?null:old,action==='save'?content:null);
 assert.deepEqual(calls[1],['manage_community_activity',{p_action:'save',p_id:'one',p_expected_revision:3,p_slug:'ceramic',p_content:content}]);
 assert.deepEqual(calls[0][1],{p_action:'list',p_id:null,p_expected_revision:null,p_slug:null,p_content:null});
 const stale=new ActivityEditor(clientWith(async()=>({error:Error('revision conflict')})));
 await assert.rejects(stale.manage('publish',old),/revision conflict/);
});
test('editor fails closed for missing and switched sessions and discarded generations',async()=>{
 let count=0;const client=clientWith(async()=>({data:[]}));
 client.auth.getSession=async()=>({data:{session:{user:{id:++count===1?'owner':'other'}}}});
 await assert.rejects(new ActivityEditor(client).manage('list'),/账号已变化/);
 const noSession=clientWith(()=>{throw Error('must not call');});noSession.auth.getSession=async()=>({data:{session:null}});
 await assert.rejects(new ActivityEditor(noSession).manage('list'),/先登录/);
 const invalidate=clientWith(async()=>{editor.invalidate();return {data:[]};});const editor=new ActivityEditor(invalidate);
 await assert.rejects(editor.manage('list'),/账号已变化/);
});
test('cover uses authenticated official Storage with versioned no-overwrite path',async()=>{
 let uploaded;
 const client=clientWith(()=>{});client.storage={from(bucket){assert.equal(bucket,'activity-covers');return {upload:async(path,file,options)=>{uploaded={path,options};return {};},getPublicUrl:path=>({data:{publicUrl:'https://api.kongye.space/storage/v1/object/public/activity-covers/'+path}})};}};
 const editor=new ActivityEditor(client);await editor.upload({type:'image/png',size:30});
 assert.match(uploaded.path,/^[a-f0-9-]{36}\.png$/);assert.equal(uploaded.options.upsert,false);
 await assert.rejects(editor.upload({type:'image/svg+xml',size:10}));
});
test('detail uses text nodes and safe resource setters and fails template mismatches',()=>{
 const text={nodeValue:'old'};let visited=false;
 const image={};const root={ownerDocument:{createTreeWalker(){return {nextNode(){if(visited)return false;visited=true;this.currentNode=text;return true;}};}},querySelectorAll:()=>[image]};
 bindActivityDetail(root,{templateVersion:'test',textBlocks:['<img src=x onerror=alert(1)>'],attributes:[{tag:'img',index:0,src:'https://kongye.space/safe.png',alt:'<script>'}]},'test');
 assert.equal(text.nodeValue,'<img src=x onerror=alert(1)>');assert.equal(image.src,'https://kongye.space/safe.png');assert.equal(image.alt,'<script>');
 assert.throws(()=>bindActivityDetail(root,{templateVersion:'wrong'},'test'),/版本不匹配/);
 assert.throws(()=>bindActivityDetail(root,{templateVersion:'test',textBlocks:[],attributes:[{tag:'script',index:0}]},'test'));
 assert.throws(()=>bindActivityDetail(root,{templateVersion:'test',textBlocks:[],attributes:[{tag:'a',index:0,href:'javascript:alert(1)'}]},'test'));
});
test('admin shares existing account module and never obtains a privileged client',async()=>{
 const source=await readFile(new URL('../docs/activity-admin.mjs',import.meta.url),'utf8');
 assert.match(source,/community-account\.mjs\?v=account-restore-20261109-v2/);assert.match(source,/new ActivityEditor\(client\)/);
 assert.doesNotMatch(source,/service_role|serviceKey|auth\.admin|signUp\(|createClient\(/);
 const publicEntry=await readFile(new URL('../docs/community-screens.mjs',import.meta.url),'utf8');
 assert.doesNotMatch(publicEntry,/porcelain-ink|landscape-ink|courtyard-ink/);
 const detailEntry=await readFile(new URL('../docs/screen-page.mjs',import.meta.url),'utf8');assert.match(detailEntry,/活动未发布或已下线/);
});

test('cover upload and helper match frozen bucket 8 MiB boundary',async()=>{
 let count=0;
 const client=clientWith(()=>{});client.storage={from:()=>({upload:async()=>{count++;return {};},getPublicUrl:()=>({data:{publicUrl:'https://api.kongye.space/cover.png'}})})};
 const editor=new ActivityEditor(client);
 await editor.upload({type:'image/png',size:8388608});assert.equal(count,1);
 await assert.rejects(editor.upload({type:'image/png',size:8388609}),/8 MiB/);assert.equal(count,1);
 const html=await readFile(new URL('../docs/activity-admin.html',import.meta.url),'utf8');
 assert.match(html,/最大 8 MiB/);assert.doesNotMatch(html,/10 MB/);
});

test('admin summary field preserves existing details and saves edited summary for every template',async()=>{
 const {runInNewContext}=await import('node:vm');
 const source=await readFile(new URL('../docs/activity-admin.mjs',import.meta.url),'utf8');
 const renderer=source.slice(source.search(/function renderDetail\(\)\s*\{/),source.search(/function show\(row\)\s*\{/));
 for(const template of ['article','ceramic','resort']){
  const original={summary:'原有简介',sections:[{heading:'原有标题',body:'原有正文'}],templateVersion:template+'-20261110-v1',textBlocks:['原有文字']};
  const detail=structuredClone(original),controls=[];
  runInNewContext(renderer+'renderDetail();',{detail,detailFields:{replaceChildren(){}},editorField:(label,value,set)=>controls.push({label,value,set}),document:{querySelector:()=>({hidden:false})}});
  const summary=controls.find(control=>control.label==='活动简介');assert.equal(summary.value,'原有简介');
  summary.set('更新后的简介');assert.equal(detail.summary,'更新后的简介');assert.deepEqual(detail.sections,original.sections);assert.deepEqual(detail.textBlocks,original.textBlocks);assert.equal(original.summary,'原有简介');
  let saved;
  const editor=new ActivityEditor(clientWith(async(name,args)=>{saved=args.p_content;return {data:{id:'one'}};}));
  await editor.manage('save',{id:'one',slug:'one',draft_revision:1},{...content,template_key:template,detail});
  assert.equal(saved.detail.summary,'更新后的简介');assert.deepEqual(saved.detail.sections,original.sections);
 }
 assert.match(source,/detail:\s*\{\s*summary:\s*'',\s*sections:/);
});
