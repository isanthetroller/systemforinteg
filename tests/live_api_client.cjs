// Actual live.js plus real HTTP APIs, with a minimal simulated renderer. Not browser E2E.
const fs=require('node:fs'),vm=require('node:vm');
const elements=new Map();
const body={dataset:{},append(el){elements.set(el.id,el);}};
let reloads=0;
async function read(path){
  const response=await fetch(`${process.env.SP_TEST_BASE}/${path}`,{headers:{Authorization:`Bearer ${process.env.SP_TEST_TOKEN}`}});
  if(!response.ok)throw Error(`API status ${response.status}`);
  return (await response.json()).data;
}
const context={document:{hidden:false,body,getElementById:id=>elements.get(id),createElement:()=>({style:{},setAttribute(){}}),addEventListener(){}},
  setTimeout,clearTimeout,addEventListener(){},
  SPAuth:{isAuthenticated:()=>true,updateUser(){},whenAuthenticated(fn){fn();}},
  ApiClient:{getUpdates:()=>read('updates.php'),fresh:fn=>fn()},
  SP:{async reload(){
    const vehicles=await read('vehicles.php');
    body.vehicles=vehicles;
    reloads++;
    if(reloads===1)console.log('READY');
    const changed=vehicles.find(v=>v.plateNumber===process.env.SP_TEST_PLATE);
    if(changed){console.log(JSON.stringify({result:'PASS',reloads,plate:changed.plateNumber,owner:changed.ownerName}));setTimeout(()=>process.exit(0),50);}
  }}};
context.window=context;
vm.runInNewContext(fs.readFileSync('web-app-admin/js/live.js','utf8'),context);
context.SPLive.start();
setTimeout(()=>{console.error('FAIL automatic read did not reconcile within 20 seconds');process.exit(1);},20000);
