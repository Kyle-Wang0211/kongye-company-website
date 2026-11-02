const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const root=path.join(__dirname,'../docs');
test('homepage embeds the exact production viewer and existing local models',()=>{
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 assert(!html.includes('sketchfab.com/models/'));
 const base=path.join(root,'viewer');const m=JSON.parse(fs.readFileSync(path.join(base,'BUNDLE_MANIFEST.json')));
 assert.equal(m.bundle_sha256,'186816180c6fd4d745965d92feded8333edef2e35a6660d3499da9aca190817c');
 for(const [name,sha] of Object.entries(m.files))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(base,name))).digest('hex'),sha,name);
});

test('product leads the page and company identity remains at the bottom',()=>{
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 const header=html.match(/<header[\s\S]*?<\/header>/)[0];
 assert(header.includes('窗后城'));assert(!header.includes('空也'));
 assert(html.indexOf('id="about"')>html.indexOf('id="contact"'));
 assert(html.includes('北京空也科技有限公司'));
});
test('public community leads the page without marketing hero or eager renderers',()=>{
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 assert(!html.includes('class="hero wrap"'));
 assert(!html.includes('id="showcase"'));
 assert.equal((html.match(/<iframe/g)||[]).length,0);
 assert(!html.includes('<dialog'));
 assert(fs.readFileSync(path.join(root,'community-feed.js'),'utf8').includes('location.assign(url.href)'));
 assert(!/<iframe[^>]+src="community\//.test(html));
 assert(html.includes('community-feed.js'));
});
