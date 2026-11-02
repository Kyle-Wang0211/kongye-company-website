const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const root=path.join(__dirname,'../docs');
test('homepage embeds the exact production viewer and existing local models',()=>{
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 assert(!html.includes('sketchfab.com/models/'));
 const frames=[...html.matchAll(/data-src="([^"]+)"/g)].map(x=>x[1]);
 assert.equal(frames.length,3);
 for(const src of frames){const u=new URL(src.replaceAll('&amp;','&'),'https://kongye.space/');assert.equal(u.pathname,'/viewer/index.html');assert.equal(u.searchParams.get('format'),'glb'); const model=new URL(u.searchParams.get('model'),u);assert(model.pathname.startsWith('/assets/models/'));assert(fs.existsSync(path.join(root,model.pathname)));}
 const base=path.join(root,'viewer');const m=JSON.parse(fs.readFileSync(path.join(base,'BUNDLE_MANIFEST.json')));
 assert.equal(m.bundle_sha256,'79050a1530ee45051c094ef6876407671a1450de58d09b82dae8063fc40223da');
 for(const [name,sha] of Object.entries(m.files))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(base,name))).digest('hex'),sha,name);
});

test('product leads the page and company identity remains at the bottom',()=>{
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 const header=html.match(/<header[\s\S]*?<\/header>/)[0];
 assert(header.includes('窗后城'));assert(!header.includes('空也'));
 assert(html.indexOf('id="about"')>html.indexOf('id="contact"'));
 assert(html.includes('北京空也科技有限公司'));
});
