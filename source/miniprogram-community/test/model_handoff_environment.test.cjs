const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../web/model_handoff.js'),'utf8');
function load(userAgent,miniProgram) {
 const timers=[];const window={wx:{miniProgram}};
 vm.runInNewContext(source,{window,navigator:{userAgent},setTimeout(fn){timers.push(fn);return timers.length;},clearTimeout(){}});
 return {window,timers};
}
test('plain browser rejects native environment before requesting a draft',async()=>{
 let calls=0;const {window}=load('Chrome',{getEnv(){calls++;}});
 assert.equal(await window.pwCanUseModelPicker(),false);assert.equal(calls,0);
});
test('missing native callback resolves unavailable after its bounded wait',async()=>{
 const {window,timers}=load('MicroMessenger',{getEnv(){}});
 const result=window.pwCanUseModelPicker();timers[0]();assert.equal(await result,false);
});
test('official native environment is accepted',async()=>{
 const {window}=load('MicroMessenger',{getEnv(options){options.success({miniprogram:true});}});
 assert.equal(await window.pwCanUseModelPicker(),true);
});
