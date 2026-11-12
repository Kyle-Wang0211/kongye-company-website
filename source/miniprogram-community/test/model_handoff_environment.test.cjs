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
 const {window}=load('MicroMessenger',{getEnv(callback){assert.equal(typeof callback,'function');callback({miniprogram:true});}});
 assert.equal(await window.pwCanUseModelPicker(),true);
});

const draft=JSON.stringify({id:'00000000-0000-4000-8000-000000000002',grant:'A'.repeat(43)});
test('late environment callback cannot post a grant or redirect after timeout',async()=>{
 let callback,posts=0,redirects=0;
 const {window,timers}=load('MicroMessenger',{
  getEnv(fn){assert.equal(typeof fn,'function');callback=fn;},postMessage(){posts++;},redirectTo(){redirects++;},
 });
 const result=assert.rejects(window.pwOpenModelPicker(draft),/native_picker_timeout/);
 timers[0]();await result;callback({miniprogram:true});
 assert.equal(posts,0);assert.equal(redirects,0);
});
test('timeout covers redirect completion and ignores its late callbacks',async()=>{
 let callbacks;
 const {window,timers}=load('MicroMessenger',{
  getEnv(callback){assert.equal(typeof callback,'function');callback({miniprogram:true});},postMessage(){},redirectTo(options){callbacks=options;},
 });
 const result=assert.rejects(window.pwOpenModelPicker(draft),/native_picker_timeout/);
 timers[0]();await result;callbacks.success();callbacks.fail(Error('late'));
});
