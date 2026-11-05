import {test} from 'node:test';import assert from 'node:assert/strict';import {feedUrl,workUrl,assetUrl,checkModel,authorUrl,formatCount,publishedLabel,modelUrl,publicationCoverAspect} from '../docs/community-data.mjs';
test('anonymous feed explicitly selects only public, published, moderated work',()=>{const u=feedUrl('https://api.kongye.space');assert.equal(u.searchParams.get('visibility'),'eq.public');assert.equal(u.searchParams.get('moderation_status'),'eq.ok');assert.equal(u.searchParams.get('published_at'),'not.is.null');assert.equal(u.searchParams.get('limit'),'12');});
test('asset paths cannot redirect to other origins or escape buckets',()=>{for(const p of ['../secret','https://evil/x','/secret','x?token=1','x\\y'])assert.throws(()=>assetUrl('https://api.kongye.space','works',p));assert.equal(assetUrl('https://api.kongye.space','works','a/model.glb'),'https://api.kongye.space/storage/v1/object/public/works/a/model.glb');});
test('large, unknown size and unsupported models do not allocate a viewer',()=>{for(const w of [{format:'glb',file_size_bytes:null},{format:'glb',file_size_bytes:129*1024*1024},{format:'spz',file_size_bytes:100}])assert.throws(()=>checkModel(w));assert.doesNotThrow(()=>checkModel({format:'ply',file_size_bytes:100}));});

test('shared work links keep all public access filters',()=>{const u=workUrl('https://api.kongye.space','12345678-1234-1234-1234-123456789abc');assert.equal(u.searchParams.get('id'),'eq.12345678-1234-1234-1234-123456789abc');assert.equal(u.searchParams.get('visibility'),'eq.public');assert.equal(u.searchParams.get('moderation_status'),'eq.ok');assert.throws(()=>workUrl('https://api.kongye.space','x,visibility.eq.private'));});

test('author projection contains public presentation fields only and is bounded',()=>{const u=authorUrl('https://api.kongye.space',['12345678-1234-1234-1234-123456789abc']);assert.equal(u.pathname,'/rest/v1/community_author_profiles');assert.equal(u.searchParams.get('select'),'id,display_name,avatar_url,handle');assert.throws(()=>authorUrl('https://api.kongye.space',['x),email.eq.secret']));assert.throws(()=>authorUrl('https://api.kongye.space',Array.from({length:13},(_,i)=>String(i).padStart(36,'a'))));});
test('counts match production WorkCard and timestamps are actual valid values',()=>{assert.deepEqual([0,999,1000,9999,10000,11500].map(formatCount),['0','999','1.0K','10.0K','10K','12K']);assert.equal(formatCount(null),'');assert.equal(publishedLabel(null),'');assert.equal(publishedLabel('invalid'),'');assert.equal(publishedLabel(new Date(2026,10,2,10).toISOString(),new Date(2026,10,2,12)),'10:00');});

test('the three former local links point to real backend works, with no separate local feed',async()=>{const {legacyWorkIds}=await import('../docs/community-work-links.mjs');assert.equal(Object.keys(legacyWorkIds).length,3);assert.equal(new Set(Object.values(legacyWorkIds)).size,3);for(const id of Object.values(legacyWorkIds))assert.match(id,/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/);const {readFileSync}=await import('node:fs');const js=readFileSync(new URL('../docs/community-feed.js',import.meta.url),'utf8');assert(!js.includes('community-examples.mjs'));assert(!js.includes('selectedExample'));});

test('new production publication assets use the review-checked signed delivery endpoint',()=>{const path='a'.repeat(64)+'/source.glb';const u=new URL(modelUrl('https://api.kongye.space',path));assert.equal(u.pathname,'/functions/v1/publication-model');assert.equal(u.searchParams.get('path'),path);assert(modelUrl('https://api.kongye.space','owner/legacy.glb').includes('/object/public/works/'));});

test('publication times follow rolling24h then local calendar yesterday/previousday/date',()=>{
 const now=new Date(2026,10,4,13,45);
 assert.equal(publishedLabel(new Date(2026,10,3,13,46).toISOString(),now),'13:46');
 assert.equal(publishedLabel(new Date(now.getTime()-86400000+1).toISOString(),now),'13:45');
 assert.equal(publishedLabel(new Date(now.getTime()-86400000).toISOString(),now),'13:45');
 assert.equal(publishedLabel(new Date(now.getTime()-86400000-1).toISOString(),now),'昨天');
 assert.equal(publishedLabel(new Date(2026,10,2,18).toISOString(),now),'前天');
 assert.equal(publishedLabel(new Date(2026,10,1,18).toISOString(),now),'11月1日');
 assert.equal(publishedLabel('invalid',now),'');
 assert.equal(publishedLabel(new Date(2026,10,5,18).toISOString(),now),'11月5日');
});


test('publication covers accept only the exact same-origin reviewed endpoint and UUID query',()=>{
 const origin='https://api.kongye.space',id='12345678-1234-4234-8234-123456789abc';
 const path='/functions/v1/publication-cover?work_id='+id;
 assert.equal(assetUrl(origin,'thumbnails',path),origin+path);
 for(const invalid of [path+'&token=x',path+'#fragment',path+'&work_id='+id,path+'/',path.replace(id,'invalid'),'https://other.test'+path,'//other.test'+path,path.replace('publication-cover','publication-model')])assert.throws(()=>assetUrl(origin,'thumbnails',invalid));
 assert.throws(()=>assetUrl(origin,'works',path));
 assert.throws(()=>assetUrl('http://api.kongye.space','thumbnails',path));
});

test('only a new work-bound cover with a valid framing descriptor changes card aspect',()=>{
 const id='12345678-1234-4234-8234-123456789abc';
 const work={id,thumbnail_storage_path:'/functions/v1/publication-cover?work_id='+id,initial_view:{schema:'pw.camera-framing.v1',aspect:1.5}};
 assert.equal(publicationCoverAspect(work),1.5);
 assert.equal(publicationCoverAspect({...work,initial_view:{...work.initial_view,aspect:.5}}),.5);
 for(const aspect of [0,-1,Infinity,NaN,'1.5',.09,10.01])assert.equal(publicationCoverAspect({...work,initial_view:{...work.initial_view,aspect}}),null);
 for(const patch of [{initial_view:null},{initial_view:{schema:'unknown',aspect:1.5}},{thumbnail_storage_path:'owner/legacy.png'},{id:'another-work'}])assert.equal(publicationCoverAspect({...work,...patch}),null);
});
