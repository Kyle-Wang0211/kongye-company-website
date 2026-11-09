import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=name=>readFileSync(new URL('../docs/'+name,import.meta.url),'utf8');
test('homepage and feed/following reuse exactly one versioned account module',()=>{
 const entry=read('index.html').match(/src="(community-account\.mjs[^\"]*)"/)[1];
 for(const name of ['community-feed.js','community-following.mjs']){
  const imported=read(name).match(/from '\.\/(community-account\.mjs[^']*)'/)[1];
  assert.equal(imported,entry,name+' must not start a second SDK client through a different ESM URL');
 }
});
test('initial unresolved account markup is neutral instead of signed-out',()=>{
 const summary=read('index.html').match(/<summary id="account-summary"[\s\S]*?<\/summary>/)[0];
 assert.match(summary,/data-i18n="siteAccount"/);
 assert.doesNotMatch(summary,/data-i18n="siteLogin"/);
});
