// Presentation logic checks with a fake DOM; no browser, API, or database writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
class Element {
  constructor() { this.value=''; this.textContent=''; this.innerHTML=''; this.children=[]; this.disabled=false; this.events={}; this.attrs={}; this.classList={contains:()=>true}; }
  addEventListener(name, handler) { this.events[name]=handler; }
  setAttribute(name,value) { this.attrs[name]=value; }
  appendChild(child) { this.children.push(child); }
  querySelector() { return new Element(); }
}
const elements = new Map();
const get = id => { if(!elements.has(id)) elements.set(id,new Element()); return elements.get(id); };
const events = {};
let show, calls=0;
let records = Array.from({length:23}, (_,i)=>({id:i+1,plateNumber:`TEST-${i+1}`,ownerName:'Fixture',violationType:'Other',status:'Pending',description:'Fixture notes',createdAt:'2026-10-07 12:00:00'}));
const context = {
  document:{getElementById:get,createElement:()=>new Element(),querySelectorAll:()=>[],addEventListener:(name,fn)=>{events[name]=fn;}},
  console,
  SP:{state:{vehicles:[]},escapeHtml:s=>s,registerView:(id,button,fn)=>{show=fn;},reload:async()=>events['sp:data-loaded']()},
  SPAuth:{hasRole:()=>true},
  ApiClient:{getViolations:async({status}={})=>{calls++; return records.filter(r=>!status || r.status===status);}}
};
context.window=context;
vm.runInNewContext(fs.readFileSync('web-app-admin/js/violations.js','utf8'),context);
const settle = () => new Promise(resolve=>setImmediate(resolve));
(async()=>{
  events['sp:app-ready'](); show(); await settle();
  assert.equal(get('violPaginationInfo').textContent,'Showing 1–10 of 23 records');
  assert.equal(get('violNextBtn').disabled,false);
  get('violNextBtn').events.click();
  assert.equal(get('violPaginationInfo').textContent,'Showing 11–20 of 23 records');
  get('violNextBtn').events.click();
  assert.equal(get('violPaginationInfo').textContent,'Showing 21–23 of 23 records');
  assert.equal(get('violNextBtn').disabled,true);
  get('violPrevBtn').events.click();
  assert.equal(get('violPageIndicator').textContent,'Page 2 of 3');
  get('violSearch').value='TEST-23'; get('violSearch').events.input();
  assert.equal(get('violPaginationInfo').textContent,'Showing 1–1 of 1 records');
  assert.equal(get('violPrevBtn').disabled,true);
  get('violSearch').value=''; get('violSearch').events.input();
  get('violStatusFilter').value='Resolved'; get('violStatusFilter').events.change(); await settle();
  assert.equal(get('violPaginationInfo').textContent,'0 matching records');
  assert.match(get('violTableBody').innerHTML,/No records in this status/);
  get('violStatusFilter').value=''; get('violStatusFilter').events.change(); await settle();
  const before=calls;
  await get('violationsRefreshBtn').events.click();
  assert.equal(calls-before,2,'Manual refresh fetches records and badge once each');
  records=records.slice(0,2); events['sp:data-loaded'](); await settle();
  assert.equal(get('violPaginationInfo').textContent,'Showing 1–2 of 2 records','Background data refresh updates visible ledger');
  assert.equal(get('violRecordsRegion').attrs['aria-busy'],'false');
  console.log('PASS: pagination, page boundaries, search, empty state, status filtering, manual refresh, background sync, loading state');
})().catch(error=>{console.error(error);process.exitCode=1;});
