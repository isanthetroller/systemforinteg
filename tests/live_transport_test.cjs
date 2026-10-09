// Executed transport unit tests with simulated DOM and controlled timers. Not browser E2E.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
let count = 0;
function harness() {
  const listeners = {}, timers = new Map(), elements = new Map();
  let id = 0, calls = 0, reloads = 0, authenticated = true;
  let response = {revisions: {vehicles:'v1', session:'u1'}, user:{id:1}};
  let error = false, hold = null;
  const document = {hidden:false, body:{dataset:{}, append(el){elements.set(el.id,el);}},
    getElementById(id){return elements.get(id);}, createElement(){return {style:{},setAttribute(){}};},
    addEventListener(name, fn){listeners[name]=fn;}};
  const auth = {isAuthenticated:()=>authenticated, updateUser(u){auth.user=u;}, whenAuthenticated(fn){fn();}};
  const context = {document, SPAuth:auth, SP:{async reload(){reloads++;}},
    ApiClient:{async getUpdates(){calls++; if(hold) await hold; if(error) throw Error('offline'); return response;}, async fresh(fn){return fn();}},
    setTimeout(fn, delay){const n=++id;timers.set(n,{fn,delay});return n;},clearTimeout(n){timers.delete(n);}};
  context.window=context; context.addEventListener=(name,fn)=>{listeners[name]=fn;};
  vm.runInNewContext(fs.readFileSync('web-app-admin/js/live.js','utf8'),context);
  return {context,document,auth,timers,listeners,setResponse:r=>{response=r;},setError:v=>{error=v;},
    setAuth:v=>{authenticated=v;},setHold:v=>{hold=v;},get calls(){return calls;},get reloads(){return reloads;}};
}
const settle = async()=>{for(let n=0;n<12;n++) await new Promise(resolve=>setImmediate(resolve));};
async function check(name, fn) {await fn(); count++; console.log('PASS',name);}
(async()=>{
  await check('initial authenticated snapshot reconciles core and session',async()=>{const h=harness();h.context.SPLive.start();await settle();assert.equal(h.reloads,1);assert.equal(h.auth.user.id,1);assert.equal(h.document.body.dataset.syncState,'live');});
  await check('unchanged snapshot avoids duplicate reload',async()=>{const h=harness();h.context.SPLive.start();await settle();h.context.SPLive.wake();await settle();assert.equal(h.reloads,1);});
  await check('other client revision automatically reconciles on timer',async()=>{const h=harness();h.context.SPLive.start();await settle();h.setResponse({revisions:{vehicles:'v2',session:'u1'},user:{id:1}});const timer=[...h.timers.values()][0];assert.equal(timer.delay,5000);timer.fn();await settle();assert.equal(h.reloads,2);});
  await check('failed subscriber is not acknowledged and retries same revision',async()=>{const h=harness();let attempts=0;h.context.SPLive.subscribe(async()=>{if(++attempts===1)throw Error('load failed');});h.context.SPLive.start();await settle();assert.equal(h.document.body.dataset.syncState,'offline');h.context.SPLive.wake();await settle();assert.equal(attempts,2);assert.equal(h.document.body.dataset.syncState,'live');});
  await check('network failure backs off then recovers',async()=>{const h=harness();h.setError(true);h.context.SPLive.start();await settle();assert.equal([...h.timers.values()][0].delay,10000);h.setError(false);h.context.SPLive.wake();await settle();assert.equal(h.document.body.dataset.syncState,'live');assert.equal([...h.timers.values()][0].delay,5000);});
  await check('hidden tab pauses requests and foreground resumes',async()=>{const h=harness();h.document.hidden=true;h.context.SPLive.start();await settle();assert.equal(h.calls,0);h.document.hidden=false;h.listeners.visibilitychange();await settle();assert.equal(h.calls,1);});
  await check('online notification triggers missed snapshot recovery',async()=>{const h=harness();h.context.SPLive.start();await settle();h.setResponse({revisions:{vehicles:'v3'},user:{id:1}});h.listeners.online();await settle();assert.equal(h.reloads,2);});
  await check('overlapping wakes remain single flight',async()=>{const h=harness();let release;h.setHold(new Promise(r=>release=r));h.context.SPLive.start();h.context.SPLive.wake();h.context.SPLive.wake();assert.equal(h.calls,1);release();await settle();});
  await check('logout discards in-flight response',async()=>{const h=harness();let release;h.setHold(new Promise(r=>release=r));h.context.SPLive.start();h.setAuth(false);h.listeners['sp:auth-required']();release();await settle();assert.equal(h.reloads,0);assert.equal(h.timers.size,0);});
  await check('rapid relogin eventually refreshes the new session',async()=>{const h=harness();let release;h.setHold(new Promise(r=>release=r));h.context.SPLive.start();h.listeners['sp:auth-required']();h.context.SPLive.start();release();await settle();h.setHold(null);[...h.timers.values()][0].fn();await settle();assert.equal(h.reloads,1);});
  await check('subscription disposal prevents stale view callback',async()=>{const h=harness();let used=0;const off=h.context.SPLive.subscribe(()=>{used++;});off();h.context.SPLive.start();await settle();assert.equal(used,0);});
  await check('unauthenticated start cannot request privileged revisions',async()=>{const h=harness();h.setAuth(false);h.context.SPLive.start();await settle();assert.equal(h.calls,0);});
  console.log(`${count} transport unit checks passed`);
})().catch(error=>{console.error(error);process.exitCode=1;});
