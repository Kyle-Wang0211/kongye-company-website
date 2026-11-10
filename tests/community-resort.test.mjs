import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resortConfig, validateResortConfig, buildResortViewerUrl, bindResortAnnotations} from '../docs/community-resort.mjs';

const point = {id:'reception',category:'reception',title:'山前接待处',description:'抵达与问询。',localPosition:{x:12,y:9,z:3}};
const config = {...resortConfig,sourceUrl:'https://example.org/ept.json',points:[point]};

test('resort uses the existing streaming viewer and encodes the source URL',()=>{
 const url = new URL(buildResortViewerUrl(config,'https://site.test/screen.html?screen=2'));
 assert.equal(url.pathname,'/pointcloud-viewer/');
 assert.equal(url.searchParams.get('source'),config.sourceUrl);
});

test('resort requires finite model coordinates and rejects duplicate or unclassified points',()=>{
 assert.doesNotThrow(()=>validateResortConfig(config));
 for(const points of [[{...point,localPosition:{x:NaN,y:0,z:0}}],[{...point,localPosition:null}],[point,point],[{...point,category:'unknown'}]]) {
  assert.throws(()=>validateResortConfig({...config,points}));
 }
 assert.throws(()=>validateResortConfig({...config,sourceUrl:'javascript:alert(1)'}));
 assert.throws(()=>validateResortConfig({...config,sourceUrl:'//unknown.test/ept.json'}));
});

test('resort reuses native annotations with model XYZ and selection callbacks',()=>{
 let annotations,callback,selected;
 const overlay = {};
 const viewer = {annotateElements:{overlay},annotate:{loadAnnotations(value){annotations=value;},setOnSelect(value){callback=value;}}};
 assert.equal(bindResortAnnotations(viewer,[point],value=>{selected=value;}),overlay);
 assert.deepEqual(annotations[0].localPosition,point.localPosition);
 assert.equal(annotations[0].id,point.id);
 assert.equal(typeof annotations[0].createdAt,'number');
 callback('reception');
 assert.equal(selected,point);
 callback('unknown');
 assert.equal(selected,point);
});

test('screen two mounts the resort while retaining the ceramic event entry',async()=>{
 const source = await readFile(new URL('../docs/screen-page.mjs',import.meta.url),'utf8');
 assert.match(source,/mountCeramicEvent/);
 assert.match(source,/content\.template_key\s*===\s*'resort'/);
 assert.match(source,/mountCommunityResort/);
});
