"""Full gate history filtering against real PHP and an isolated database."""
import argparse, itertools, json, shutil, sqlite3, time
from contextlib import closing
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urlencode
from movement_integration import Sandbox, call, ROOT

def seed(s):
    base=s.bases[0]
    code,r=call(base,'auth.php?action=login',{'username':'admin','password':'Password123!'})
    assert code==200,r
    token=r['data']['token']
    assert call(base,'auth.php?action=change_password',{'current_password':'Password123!','new_password':'GateRecords-2026!'},token)[0]==200
    actions=['Entry Recorded','Exit Approved','Entry Denied','Exit Denied']
    rows=[]
    for i in range(360):
        d=datetime(2026,1,1)+timedelta(days=i//24,hours=i%24,seconds=59 if i%2 else 0)
        action=actions[i%4]; status='Blocked / Alert' if 'Denied' in action else 'Inside Campus' if i%4==0 else 'Exited'
        rows.append(dict(plate=f'HIST{i:03d}',at=d.strftime('%Y-%m-%d %H:%M:%S'),action=action,status=status,
            gate='Gate 1 (Main Ingress)' if i%2==0 else 'Checkpoint 2 (Exit)',officer='Officer A' if i%3 else 'Officer B',
            synced='2026-10-11 09:00:00' if i%5==0 else None,notes='Literal 100%_note' if i==0 else 'Fixture'))
    rows += [dict(plate=f'EDGE{i}',at=d,action='Entry Recorded',status='Inside Campus',gate='Gate 1',officer='Officer A',synced=None,notes='Boundary')
        for i,d in enumerate(['2026-01-15 07:59:59','2026-01-15 08:00:00','2026-01-15 09:30:59','2026-01-15 09:31:00','2026-01-15 23:59:59','2026-01-16 00:00:00'])]
    rows.append(dict(plate='UNICODE',at='2026-01-15 10:00:00',action='Exit Approved',status='Exited',gate='Gate 2',officer='Jose Niño',synced=None,notes='こんにちは'))
    with closing(sqlite3.connect(s.db)) as db, db:
        for row in rows:
            cur=db.execute('INSERT INTO gate_logs(plate_number,vehicle_type,owner_name,driver_name,driver_relationship,gate_point,action,gate_type,status,guard_name,notes,logged_at,synced_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (row['plate'],'4-Wheel','Test Owner','Test Driver','Self',row['gate'],row['action'],'Egress' if 'Exit' in row['action'] else 'Ingress',row['status'],row['officer'],row['notes'],row['at'],row['synced']))
            row['id']=cur.lastrowid
    return token,rows

def run(s,token,rows,append=None):
    checks=0
    def req(params=None,authed=True):
        return call(s.bases[0],'logs.php?'+urlencode({'paginated':'1',**(params or {})}),token=token if authed else None,method='GET')
    def verify(condition,detail):
        nonlocal checks
        assert condition,detail
        checks+=1
    def model(p):
        result=[]
        mapping={'Entry':'Entry Recorded','ExitApproved':'Exit Approved','EntryDenied':'Entry Denied','ExitDenied':'Exit Denied'}
        for row in rows:
            day=row['at'][:10]; clock=row['at'][11:]
            if p.get('from') and day<p['from'] or p.get('to') and day>p['to']: continue
            lo=p.get('time_from',''); hi=p.get('time_to','')
            if lo and hi and lo>hi:
                if not(clock>=lo+':00' or clock<=hi+':59'):continue
            elif lo and clock<lo+':00' or hi and clock>hi+':59':continue
            if p.get('event') and row['action']!=mapping[p['event']]:continue
            if p.get('gate') and ('1' if '1' in row['gate'] else '2')!=p['gate'][-1]:continue
            if p.get('officer') and row['officer']!=p['officer']:continue
            if p.get('source')=='offline' and not row['synced'] or p.get('source')=='online' and row['synced']:continue
            result.append(row)
        return sorted(result,key=lambda r:(r['at'],r['id']),reverse=p.get('sort')!='oldest')
    c,r=req(); verify(c==200 and r['data']['total']==len(rows),'all history, not latest 100')
    snapshot=r['data']['snapshot']
    for datepair,clockpair,gate in itertools.product([('', ''),('2026-01-01','2026-01-01'),('2026-01-15','2026-01-15'),('','2026-01-07'),('2026-01-05','')],[('',''),('08:00','09:30'),('22:00','06:00'),('','08:00'),('22:00','')],['All','Gate 1','Gate 2']):
        p=dict(zip(['from','to'],datepair)); p.update(dict(zip(['time_from','time_to'],clockpair)))
        if gate!='All':p['gate']=gate
        p['limit']=200
        c,r=req(p); expected=model(p)
        verify(c==200 and r['data']['total']==len(expected) and [x['id'] for x in r['data']['rows']]==[x['id'] for x in expected[:200]],p)
    for event,source,sort in itertools.product(['Entry','ExitApproved','EntryDenied','ExitDenied'],['online','offline'],['newest','oldest']):
        p={'event':event,'source':source,'sort':sort,'officer':'Officer A','limit':200}
        c,r=req(p); expected=model(p)
        verify(c==200 and [x['id'] for x in r['data']['rows']]==[x['id'] for x in expected],p)
    for params in [{'status':'Inside'},{'status':'Exited'},{'status':'Blocked'},{'event':'SecurityHold'}]:
        c,r=req(params); key=params.get('status',params.get('event'))
        expected=sum(row['status']=={'Inside':'Inside Campus','Exited':'Exited'}.get(key,'Blocked / Alert') for row in rows)
        verify(c==200 and r['data']['total']==expected,params)
    for p in [{'q':'HIST000'},{'q':'100%_note'},{'q':'こんにちは'},{'officer':'Jose Niño'},{'q':"' OR 1=1 --"}]:
        c,r=req(p); expected=0 if 'OR 1' in p.get('q','') else 1
        verify(c==200 and r['data']['total']==expected,p)
    c,r=req({'page':2,'limit':200}); verify(len(r['data']['rows'])==167,'second page includes older records')
    c,r=req({'page':999999,'limit':200}); verify(r['data']['page']==2,'page clamped after history changes')
    c,r=req({'from':'2026-01-15','to':'2026-01-15','time_from':'08:00','time_to':'09:30','q':'EDGE'}); verify([x['plateNumber'] for x in r['data']['rows']]==['EDGE2','EDGE1'],'inclusive end minute and start boundary')
    c,r=req({'time_from':'08:00','time_to':'08:00'}); verify(all(x['loggedAt'][11:16]=='08:00' for x in r['data']['rows']),'same minute window')
    for p in [{'from':'2026-02-30'},{'to':'2026-01-01','from':'2026-01-02'},{'time_from':'24:00'},{'time_to':'8:00'},{'time_to':'12:60'},{'page':'-1'},{'limit':'0'},{'limit':'201'},{'sort':'id;DROP'},{'source':'bogus'},{'gate':'Gate 10'},{'q[]':'array'},{'officer[]':'array'},{'from[]':'array'},{'paginated[]':'1'},{'snapshot':'0'}]:
        c,r=req(p); verify(c==400 and r.get('success') is False,p)
    c,r=req(authed=False); verify(c==401,'staff session required')
    c,r=call(s.bases[0],'logs.php',token=token,method='GET'); verify(c==200 and isinstance(r['data'],list) and len(r['data'])==100,'legacy API shape preserved')
    def execute(sql):
        if append: return append(sql)
        with closing(sqlite3.connect(s.db)) as db, db: db.execute(sql)
    execute("INSERT INTO gate_logs(plate_number,driver_name,logged_at) VALUES ('NEWAFTERSNAPSHOT','Driver','2026-10-11 23:59:59')")
    c,r=req({'snapshot':snapshot,'limit':200}); verify(r['data']['total']==len(rows),'stable export snapshot excludes arrivals')
    c,r=req({'from':'2030-01-01','page':7}); verify(c==200 and r['data']['rows']==[] and r['data']['page']==1,'empty results have valid pagination')
    execute("ALTER TABLE gate_logs CHANGE COLUMN guard_name guard_name_unavailable VARCHAR(100) NOT NULL DEFAULT 'Gate Officer'" if append else 'ALTER TABLE gate_logs RENAME COLUMN guard_name TO guard_name_unavailable')
    try:
        c,r=req(); verify(c==503 and r.get('success') is False,'storage read failures return structured retryable JSON')
    finally:execute("ALTER TABLE gate_logs CHANGE COLUMN guard_name_unavailable guard_name VARCHAR(100) NOT NULL DEFAULT 'Gate Officer'" if append else 'ALTER TABLE gate_logs RENAME COLUMN guard_name_unavailable TO guard_name')
    c,r=req();verify(c==200 and r['data']['total']==len(rows)+1,'history read recovers after storage repair')
    print(f'PASS: {checks} real API filter checks',flush=True)
    return checks

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--serve',action='store_true'); args=parser.parse_args()
    with Sandbox() as s:
        token,rows=seed(s); run(s,token,rows)
        if args.serve:
            admin=s.root/'web-app-admin'
            for name in ['js','css','assets']:shutil.copytree(ROOT/'web-app-admin'/name,admin/name,dirs_exist_ok=True)
            shutil.copy(ROOT/'web-app-admin/index.html',admin/'index.html')
            print('BROWSER_URL '+s.bases[0].removesuffix('/api')+'/',flush=True)
            print('TEST_LOGIN admin / GateRecords-2026!',flush=True)
            try:
                while True:time.sleep(1)
            except KeyboardInterrupt:pass
