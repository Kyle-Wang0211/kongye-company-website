import test from 'node:test';
import assert from 'node:assert/strict';
import {useOfficialTextureLoader} from '../web/image_loader_lifecycle.mjs';
test('official fallback is parser-local and preserves manager and request configuration',()=>{
 let factory;
 const gltf={register(fn){factory=fn;}};
 class TextureLoader{constructor(manager){this.manager=manager;}setCrossOrigin(value){this.crossOrigin=value;}setRequestHeader(value){this.requestHeader=value;}}
 useOfficialTextureLoader(gltf,{TextureLoader});
 const manager={},headers={Accept:'image/*'},parser={options:{manager,crossOrigin:'anonymous',requestHeader:headers},textureLoader:{original:true}};
 const other={options:{manager:{},crossOrigin:'use-credentials',requestHeader:{}},textureLoader:{original:true}};
 const untouched=other.textureLoader;
 factory(parser).beforeRoot();
 assert.ok(parser.textureLoader instanceof TextureLoader);
 assert.equal(parser.textureLoader.manager,manager);assert.equal(parser.textureLoader.requestHeader,headers);assert.equal(parser.textureLoader.crossOrigin,'anonymous');assert.equal(other.textureLoader,untouched);
 factory(other).beforeRoot();assert.notEqual(parser.textureLoader,other.textureLoader);
});
