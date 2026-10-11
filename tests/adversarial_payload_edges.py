"""Image parsing, confirmation booleans, and production-style error response probes."""
import base64
from contextlib import closing
import json
import sqlite3
from adversarial_runtime import OUT,setup,raw_call,fingerprint
from movement_integration import Sandbox,call


def main():
    OUT.mkdir(parents=True,exist_ok=True);results=[]
    def check(name,ok,detail=None):
        results.append({'name':name,'passed':bool(ok),'detail':detail});print(('PASS ' if ok else 'FAIL ')+name,flush=True)
    with Sandbox() as s:
        admin,guards,v=setup(s);base=s.bases[0]
        visitor={'visitor_name':'Payload Visitor','contact_number':'09123456789','plate':'PAYLOADVIS','purpose':'Equipment','person_to_visit':'Security','items':[{'name':'Equipment','quantity':1}]}
        c,r=call(base,'visitors.php',visitor,guards[0]);assert c==201,r
        passed=r['data']
        c,r=call(base,'movements.php',{'action':'prepare','qr_code':passed['qrPayload']},guards[0]);assert c==200,r
        ticket=r['data']['movement']['ticket']
        memory=sqlite3.connect(':memory:')
        with closing(sqlite3.connect(s.db)) as db:db.backup(memory)
        for value in ['false','no','0',False,0,[],{}, {'verified':False},[False],None]:
            with closing(sqlite3.connect(s.db)) as db:memory.backup(db)
            before=fingerprint(s.db)
            c,r=call(base,'movements.php',{'action':'confirm','ticket':ticket,'items_verified':value},guards[0])
            check('item confirmation rejects '+repr(value),400<=c<500 and fingerprint(s.db)==before,{'status':c,'saved':c<300})
        memory.close()
        png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII='
        for i,(name,value,valid) in enumerate([
            ('valid_png','data:image/png;base64,'+png,True),
            ('header_only_png','data:image/png;base64,'+base64.b64encode(b'\x89PNG\r\n\x1a\n').decode(),False),
            ('header_only_jpeg','data:image/jpeg;base64,'+base64.b64encode(b'\xff\xd8\xff').decode(),False),
            ('invalid_base64','data:image/png;base64,NOT-BASE64!',False),
            ('html_data','data:text/html;base64,PHNjcmlwdD4=',False),
            ('remote_url','https://example.invalid/photo.png',False),
            ('oversize','data:image/png;base64,'+base64.b64encode(b'\x89PNG\r\n\x1a\n'+b'x'*600001).decode(),False),
            ('object',{'photo':'bad'},False),
        ]):
            c,r=call(base,'visitors.php',{**visitor,'plate':f'PHOTOEDGE{i}','vehiclePhoto':value},guards[0])
            check('visitor photo '+name+' has truthful validity',c==201 and r['data']['hasVehiclePhoto']==valid,{'status':c,'hasPhoto':r.get('data',{}).get('hasVehiclePhoto')})
        # Repeat representative type failures with error display disabled, as in production.
        secret=s.root/'web-app-admin/config/secret.php'
        secret.write_text(secret.read_text(encoding='utf-8').replace("define('SP_DEBUG', true)","define('SP_DEBUG', false)"),encoding='utf-8')
        for endpoint,method,body in [('auth.php?action=login','POST',{'username':[],'password':'Invalid-password'}),('vehicles.php?plate%5B%5D=x','GET',None),('users.php','POST',{'username':[],'full_name':'Input','role':'guard','password':'Input-2026'})]:
            c,data,raw=raw_call(base,endpoint,json.dumps(body).encode(),admin,method)
            check('production-style malformed request '+endpoint+' returns validation JSON',400<=c<500 and isinstance(data,dict),{'status':c,'json':isinstance(data,dict),'body':raw[:200]})
    report={'total':len(results),'passed':sum(x['passed'] for x in results),'failed':sum(not x['passed'] for x in results),'results':results}
    (OUT/'payload-edge-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return int(report['failed']>0)


if __name__=='__main__':raise SystemExit(main())
