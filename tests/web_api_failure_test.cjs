// API failure behavior with controlled fetch responses; no server or database writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function harness(file, name) {
  const events = [], calls = [];
  let reply = async () => ({ok:true,status:200,text:async()=>JSON.stringify({success:true,data:[]})});
  const storage = () => ({getItem:()=>null,setItem(){},removeItem(){}});
  const context = {
    console, URLSearchParams, AbortController, FormData, CustomEvent:class {constructor(type,options){this.type=type;this.detail=options?.detail;}},
    localStorage:storage(),sessionStorage:storage(),
    document:{cookie:''},
    setTimeout:()=>1,clearTimeout(){},
    fetch:async (...args)=>{calls.push(args);return reply(...args);},
    dispatchEvent:event=>events.push(event)
  };
  context.window=context;
  vm.runInNewContext(`${fs.readFileSync(file,'utf8')}\nglobalThis.__api = ${name};`,context);
  return {api:context.__api,calls,events,setReply:fn=>reply=fn};
}

(async()=>{
  for (const [file,name,action] of [
    ['web-app-admin/js/api.js','ApiClient',api=>api.registerVehicle({plateNumber:'TEST'})],
    ['web-app-student/js/api.js','StudentApi',api=>api.startPayment(1,'https://example.test')]
  ]) {
    const h=harness(file,name);
    h.setReply(async()=>{throw new TypeError('private transport details');});
    await assert.rejects(action(h.api),/Could not reach the server/);
    assert.equal(h.calls.length,1,'failed write is not automatically retried');

    h.setReply(async()=>({ok:false,status:500,text:async()=>'<html>private database path</html>'}));
    await assert.rejects(action(h.api),err=>!err.message.includes('private database path'));

    h.setReply(async()=>({ok:false,status:500,text:async()=>JSON.stringify({success:false,message:'private SQL details'})}));
    await assert.rejects(action(h.api),/temporarily unavailable/);

    h.setReply(async()=>({ok:true,status:200,text:async()=>JSON.stringify({unexpected:'shape'})}));
    await assert.rejects(action(h.api),/unexpected response/);
    h.setReply(async()=>({ok:true,status:200,text:async()=>JSON.stringify({success:false,message:'private failure'})}));
    await assert.rejects(action(h.api),/could not complete/);

    h.setReply(async()=>({ok:false,status:401,text:async()=>JSON.stringify({success:false,message:'Session expired'})}));
    await assert.rejects(action(h.api),err=>err.status===401);
    assert.equal(h.events.at(-1).type,name==='ApiClient'?'sp:auth-required':'sp:signed-out');
    console.log('PASS',name,'network, server, malformed-response, expired-session and no-write-retry cases');
  }
})().catch(err=>{console.error(err);process.exitCode=1;});
