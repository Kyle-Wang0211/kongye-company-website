import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {localeStorageKey,readLocale,persistLocale,localeReady,setLocale,t,applyLocale} from '../docs/site-l10n.mjs?v=community-account-20261103-v9';
import {publishedLabel} from '../docs/community-data.mjs';
await localeReady;
const storage=value=>({value,getItem(key){assert.equal(key,localeStorageKey);return this.value;},setItem(key,value){assert.equal(key,localeStorageKey);this.value=value;}});
test('locale preference uses Flutter shared_preferences prefix and JSON string encoding',()=>{
 const prefs=storage('"en"');assert.equal(readLocale(prefs,'zh-CN'),'en');
 persistLocale(prefs,'zh');assert.equal(prefs.value,'"zh"');assert.equal(readLocale(prefs,'en-US'),'zh');
 assert.equal(readLocale(storage(null),'zh-Hans-CN'),'zh');assert.equal(readLocale(storage(null),'fr-FR'),'en');
 assert.equal(readLocale(storage('damaged'),'en-US'),'en');assert.equal(readLocale(storage('"fr"'),'zh-CN'),'zh');
 const blocked={getItem(){throw Error();},setItem(){throw Error();}};assert.equal(readLocale(blocked,'en'),'en');assert.doesNotThrow(()=>persistLocale(blocked,'en'));
 assert.throws(()=>persistLocale(prefs,'fr'));
});
test('paired exported catalogs cover all homepage keys and dynamic template placeholders',async()=>{
 const zh=JSON.parse(await readFile(new URL('../docs/i18n/zh.json',import.meta.url),'utf8'));
 const en=JSON.parse(await readFile(new URL('../docs/i18n/en.json',import.meta.url),'utf8'));
 const html=await readFile(new URL('../docs/index.html',import.meta.url),'utf8');
 for(const [,key] of html.matchAll(/data-i18n(?:-aria|-content)?="([^"]+)"/g)){assert.equal(typeof zh[key],'string',key);assert.equal(typeof en[key],'string',key);}
 for(const key of Object.keys(zh)){assert.equal(typeof en[key],'string',key);assert.deepEqual([...zh[key].matchAll(/\{(\w+)\}/g)].map(m=>m[1]).sort(),[...en[key].matchAll(/\{(\w+)\}/g)].map(m=>m[1]).sort(),key);}
});
test('language changes update metadata and accessible text without replacing user content',()=>{
 const node=(key,field='i18n')=>({dataset:{[field]:key},textContent:'',attributes:{},setAttribute(k,v){this.attributes[k]=v;}});
 const title=node('siteTitle'),description=node('siteDescription','i18nContent'),aria=node('siteHome','i18nAria');
 const untouched={textContent:'我的真实作品 / Real username'};
 const doc={documentElement:{},querySelectorAll(selector){return selector==='[data-i18n]'?[title]:selector==='[data-i18n-aria]'?[aria]:[description];},getElementById(){return null;}};
 setLocale('en');applyLocale(doc);assert.equal(doc.documentElement.lang,'en');assert.match(title.textContent,/Chuang Hou Cheng/);assert.match(aria.attributes['aria-label'],/home/);assert.match(description.attributes.content,/official website/);assert.equal(untouched.textContent,'我的真实作品 / Real username');
 assert.equal(t('siteViewWork',{title:'我的作品'}),'View 我的作品');setLocale('zh');applyLocale(doc);assert.equal(doc.documentElement.lang,'zh-CN');assert.match(title.textContent,/窗后城/);
});
test('rolling24h and calendar-relative timestamps retain semantics in both languages',()=>{
 const now=new Date(2026,10,4,13,45),date=(day,hour=10)=>new Date(2026,10,day,hour).toISOString();
 setLocale('en');assert.equal(publishedLabel(date(3),now),'Yesterday');assert.equal(publishedLabel(date(2),now),'The day before yesterday');assert.equal(publishedLabel(date(1),now),'11/1');assert.equal(publishedLabel(new Date(now-86400000).toISOString(),now),'13:45');assert.equal(publishedLabel('invalid',now),'');
 setLocale('zh');assert.equal(publishedLabel(date(3),now),'昨天');assert.equal(publishedLabel(date(2),now),'前天');assert.equal(publishedLabel(date(1),now),'11月1日');
});

test('nested browser modules and translation catalogs share the release cache identity', async()=>{
 const release='community-account-20261103-v9';
 for (const [file,dependency] of [['community-feed.js','community-data.mjs'],['community-data.mjs','site-l10n.mjs'],['gallery.js','site-l10n.mjs'],['motion.js','site-l10n.mjs']]) {
  const source=await readFile(new URL('../docs/'+file,import.meta.url),'utf8');
  assert.ok(source.includes(dependency+'?v='+release),file+' must invalidate nested dependency');
 }
 const source=await readFile(new URL('../docs/site-l10n.mjs',import.meta.url),'utf8');
 assert.ok(source.includes('url.searchParams.set(\'v\', releaseVersion)'));
 assert.ok(source.includes("const releaseVersion = '"+release+"'"));
});
