import test from 'node:test';
import assert from 'node:assert/strict';
import {miniProgramDestination,miniProgramTitle} from '../../docs/miniprogram-navigation.mjs';
const current='https://kongye.space/screen.html?screen=1&mini=1';
test('all three covers preserve the mini program context',()=>{
 for(let screen=1;screen<=3;screen++){
  assert.equal(miniProgramDestination(`screen.html?screen=${screen}`,current),`https://kongye.space/screen.html?screen=${screen}&mini=1`);
 }
});
test('community return uses the original mobile feed',()=>{
 assert.equal(miniProgramDestination('./',current),'https://kongye.space/miniprogram/?feed=1');
});
test('work, profile, auth and message routes retain their parameters',()=>{
 for(const query of ['work=one','profile=author','auth=signin','publish=1']){
  const url=new URL(miniProgramDestination(`community/?${query}`,current));
  assert.equal(url.pathname,'/miniprogram/');
  assert.equal(url.searchParams.get('feed'),'1');
  const [key,value]=query.split('=');
  assert.equal(url.searchParams.get(key),value);
 }
 assert.equal(new URL(miniProgramDestination('community/#/messages',current)).hash,'#/messages');
});
test('normal website routes and external destinations retain behavior',()=>{
 for(const href of ['community/?work=one','./','https://example.com/','mailto:info@example.com','/pointcloud-viewer/?source=a']){
  assert.equal(miniProgramDestination(href,'https://kongye.space/screen.html?screen=1'),new URL(href,current).href);
 }
 assert.equal(miniProgramDestination('https://example.com/',current),'https://example.com/');
 assert.equal(miniProgramDestination('mailto:info@example.com',current),'mailto:info@example.com');
 assert.equal(miniProgramDestination('/pointcloud-viewer/?source=a',current),'https://kongye.space/pointcloud-viewer/?source=a');
});

test('featured markup is the exact shared website section',async()=>{
 const {readFile}=await import('node:fs/promises');
 const index=await readFile(new URL('../../docs/index.html',import.meta.url),'utf8');
 const featured=await readFile(new URL('../../docs/miniprogram-featured.html',import.meta.url),'utf8');
 const section=index.slice(index.indexOf('    <div class="community-screen-overflow">'),index.indexOf('    <section class="community-section wrap"')).trim();
 assert.ok(featured.includes(section));
 for(const name of ['styles.css','community-screens.css','community-screens.mjs']){
  const tag=index.split('\n').find(line=>line.includes(name)&&line.includes('<'));
  assert.ok(featured.includes(tag.trim()));
 }
});

test('mini program title remains Chinese on every activity page',()=>{
 for(let screen=1;screen<=3;screen++){
  assert.equal(miniProgramTitle(`https://kongye.space/screen.html?screen=${screen}&mini=1`,'English title'),'窗后城');
 }
 assert.equal(miniProgramTitle('https://kongye.space/screen.html?screen=1','Website title'),'Website title');
});
