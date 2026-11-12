import {test} from 'node:test';
import assert from 'node:assert/strict';
import {requestCommunitySearch,hydrateSearchWorks} from '../docs/community-search.mjs';

test('single Chinese character uses native RDS RPC and preserves its order',async()=>{
 const client={rpc:async(name,params)=>{
  assert.equal(name,'community_search');assert.deepEqual(params,{p_action:'suggest',p_query:'中'});
  return {data:{suggestions:['中国','中山']},error:null};
 }};
 assert.deepEqual(await requestCommunitySearch(client,'suggest','中'),['中国','中山']);
});
test('search hydration preserves native result order and current publication filters',async()=>{
 const operations=[];
 const query={select(value){operations.push(['select',value]);return this;},in(key,values){operations.push(['in',key,values]);return this;},eq(key,value){operations.push(['eq',key,value]);return this;},is(key,value){operations.push(['is',key,value]);return this;},not(key,op,value){operations.push(['not',key,op,value]);return Promise.resolve({data:[{id:'a'},{id:'b'}],error:null});}};
 const result=await hydrateSearchWorks({from:table=>{assert.equal(table,'works');return query;}},{origin:'https://api.kongye.space'},['b','a']);
 assert.deepEqual(result.map(work=>work.id),['b','a']);
 assert(operations.some(row=>row[0]==='eq'&&row[1]==='visibility'&&row[2]==='public'));
 assert(operations.some(row=>row[0]==='is'&&row[1]==='deleted_at'&&row[2]===null));
});
test('RPC failure stays observable',async()=>{
 await assert.rejects(requestCommunitySearch({rpc:async()=>({data:null,error:{message:'unavailable'}})},'suggest','中'));
});
