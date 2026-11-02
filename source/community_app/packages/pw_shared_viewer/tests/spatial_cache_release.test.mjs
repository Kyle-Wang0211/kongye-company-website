import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
test('spatial release versions the browser iframe entry and both changed nested modules',()=>{
 const expected='spatial-comments-20261102-v3';
 assert(read('../lib/src/viewer_web.dart').includes('index.html?v='+expected));
 assert(read('../web/index.html').includes("./viewer.mjs?v="+expected));
 assert(read('../web/viewer.mjs').includes("./surface_comments.mjs?v="+expected));
});
