"""Password boundaries tested only on disposable staff accounts."""
import json
from adversarial_runtime import OUT, setup, raw_call
from movement_integration import Sandbox, call


def main():
    OUT.mkdir(parents=True,exist_ok=True);results=[]
    def check(name,ok,detail=None):
        results.append({'name':name,'passed':bool(ok),'detail':detail});print(('PASS ' if ok else 'FAIL ')+name,flush=True)
    with Sandbox() as s:
        admin,guards,vehicle=setup(s);base=s.bases[0]
        for i,password in enumerate([' Exact-Password-2026 ','Pässword-漢字-2026','A1'+'x'*70+'suffix-a','Valid1\x00password']):
            user=f'boundary{i}'
            code,data,body=raw_call(base,'users.php',json.dumps({'username':user,'full_name':'Password Boundary','role':'guard','password':password,'gate_assigned':'Gate 1'}).encode(),admin)
            check(f'password boundary {i} returns controlled response',isinstance(data,dict) and code<500,{'status':code,'json':isinstance(data,dict)})
            if code==201 and data:
                c,r=call(base,'auth.php?action=login',{'username':user,'password':password})
                check(f'accepted password boundary {i} authenticates exactly as supplied',c==200,c)
                if i==2:
                    c,r=call(base,'auth.php?action=login',{'username':user,'password':'A1'+'x'*70+'different-suffix'})
                    check('different passwords beyond bcrypt byte 72 are not equivalent',c==401,c)
    report={'total':len(results),'passed':sum(x['passed'] for x in results),'failed':sum(not x['passed'] for x in results),'results':results}
    (OUT/'credential-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return int(report['failed']>0)


if __name__=='__main__':raise SystemExit(main())
