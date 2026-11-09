import {test} from 'node:test';
import assert from 'node:assert/strict';
import {avatarDataUrl,readAccount} from '../docs/community-account-data.mjs';
const session=id=>({data:{session:id?{user:{id}}:null}});
const client=(status=200)=>({auth:{getSession:async()=>session('A'),getUser:async()=>status===200?{data:{user:{id:'A',user_metadata:{display_name:'metadata'}}}}:{error:{status}}},rpc:async()=>({data:[{display_name:'真实用户名'}]})});
test('guest never requests authenticated data',async()=>{assert.equal(await readAccount({auth:{getSession:async()=>session(null)}}),null);});
test('server profile hydrates verified identity, revoked tokens become guest',async()=>{assert.deepEqual(await readAccount(client()),{id:'A',name:'真实用户名',following_count:null,followers_count:null});assert.equal(await readAccount(client(401)),null);assert.equal(await readAccount(client(403)),null);});
test('network errors stay errors and cannot masquerade as signed out',async()=>{await assert.rejects(readAccount(client(503)));});
test('account switching discards stale asynchronous profile result',async()=>{const c=client();let count=0;c.auth.getSession=async()=>session(++count===1?'A':'B');assert.equal(await readAccount(c),null);});
test('missing profile uses existing account metadata without invented username',async()=>{const c=client();c.rpc=async()=>({error:Error('offline')});assert.equal((await readAccount(c)).name,'metadata');});
test('avatar parser preserves official PNG size and digest validation',async()=>{
 const png=new Uint8Array(100);png.set([137,80,78,71,13,10,26,10]);const view=new DataView(png.buffer);view.setUint32(16,128);view.setUint32(20,128);
 const sha=Buffer.from(await crypto.subtle.digest('SHA-256',png)).toString('hex');
 const value={version:'jdenticon-3.3.0-pw-v2',png_base64:Buffer.from(png).toString('base64'),png_sha256:sha,pixel_sha256:'a'.repeat(64)};
 assert.match(await avatarDataUrl(value),/^data:image\/png;base64,/);
 assert.equal(await avatarDataUrl({...value,png_sha256:'b'.repeat(64)}),null);
 assert.equal(await avatarDataUrl({...value,version:'other'}),null);
 view.setUint32(16,256);assert.equal(await avatarDataUrl({...value,png_base64:Buffer.from(png).toString('base64')}),null);
});
