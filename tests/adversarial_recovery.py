"""Fault injection, concurrent saves and a seeded movement model on disposable PHP."""
import concurrent.futures
from contextlib import closing
import datetime
import http.server
import json
import random
import socket
import sqlite3
import threading
import urllib.request
import urllib.error
from adversarial_runtime import OUT, setup, fingerprint, raw_call
from movement_integration import Sandbox, call


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    def check(name, ok, detail=None):
        results.append({'name':name,'passed':bool(ok),'detail':detail})
        print(('PASS ' if ok else 'FAIL ')+name, flush=True)
    with Sandbox() as s:
        admin, guards, vehicle = setup(s)
        base = s.bases[0]
        driver = vehicle['authorizedDrivers'][0]['id']
        snapshot = sqlite3.connect(':memory:')
        with closing(sqlite3.connect(s.db)) as db: db.backup(snapshot)
        def restore():
            with closing(sqlite3.connect(s.db)) as db: snapshot.backup(db)
        def sql(statement, args=()):
            with closing(sqlite3.connect(s.db)) as db, db: return db.execute(statement,args).fetchall()
        def prepare(token=guards[0], worker=0):
            c,r=call(s.bases[worker],'movements.php',{'action':'prepare','qr_code':vehicle['qrPayload']},token)
            assert c == 200 and r['data']['accepted'], r
            return {'action':'confirm','ticket':r['data']['movement']['ticket'],'driver_id':driver}
        def race(path, bodies, tokens):
            barrier=threading.Barrier(len(bodies))
            def send(i):
                barrier.wait()
                return raw_call(s.bases[i%2],path,json.dumps(bodies[i]).encode(),tokens[i])[:2]
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(bodies)) as pool:
                return list(pool.map(send,range(len(bodies))))

        # Both the audit insert and subsequent custody update must be atomic.
        for table,event in [('gate_logs','INSERT'),('vehicles','UPDATE')]:
            restore(); body=prepare(); before=fingerprint(s.db)
            sql(f"CREATE TRIGGER failure BEFORE {event} ON {table} BEGIN SELECT RAISE(ABORT,'injected storage failure'); END")
            code,data,_=raw_call(base,'movements.php',json.dumps(body).encode(),guards[0])
            check(f'{table} failure returns controlled retry',code==503 and isinstance(data,dict),code)
            check(f'{table} failure rolls back movement and custody',fingerprint(s.db)==before)
            sql('DROP TRIGGER failure')
            c,r=call(base,'movements.php',body,guards[0])
            check(f'{table} same confirmation recovers after storage repair',c==201 and len(sql('SELECT id FROM gate_logs'))==1,r.get('message'))
        restore(); before=fingerprint(s.db)
        sql("CREATE TRIGGER failure BEFORE INSERT ON audit_log BEGIN SELECT RAISE(ABORT,'injected audit failure'); END")
        c,r=call(base,'settings.php',{'event_gate_mode':1,'reason':'Fault injected authorization'},admin,'PUT')
        check('mode authorization audit failure prevents policy change',c==503 and fingerprint(s.db)==before,c)

        visitor={'visitor_name':'Race Visitor','contact_number':'09123456789','plate':'RACEVIS', 'purpose':'Equipment','person_to_visit':'Security','items':[{'name':'Laptop','quantity':1}]}
        restore(); before=fingerprint(s.db)
        sql("CREATE TRIGGER failure BEFORE INSERT ON visitor_pass_items BEGIN SELECT RAISE(ABORT,'injected item failure'); END")
        c,r=call(base,'visitors.php',visitor,guards[0])
        check('visitor item failure leaves no partial pass',c==503 and fingerprint(s.db)==before,c)

        # A proxy drops the connection before forwarding or after the server commits.
        for after_commit in (False,True):
            restore(); body=prepare(); before=fingerprint(s.db)
            forwarded=threading.Event()
            class DropOnce(http.server.BaseHTTPRequestHandler):
                def do_POST(self):
                    payload=self.rfile.read(int(self.headers['Content-Length']))
                    if after_commit: raw_call(base,'movements.php',payload,guards[0])
                    forwarded.set()
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                def log_message(self,*args): pass
            proxy=http.server.ThreadingHTTPServer(('127.0.0.1',0),DropOnce)
            worker=threading.Thread(target=proxy.serve_forever,daemon=True);worker.start()
            try:
                try: raw_call(f'http://127.0.0.1:{proxy.server_port}','movements.php',json.dumps(body).encode(),guards[0])
                except (OSError, http.client.HTTPException): pass
                assert forwarded.wait(3)
                if not after_commit: check('connection drop before save leaves state unchanged',fingerprint(s.db)==before)
                c,r=call(base,'movements.php',body,guards[0])
                check('lost reply recovers original saved result' if after_commit else 'unsent request recovers once',
                    c==(200 if after_commit else 201) and r['data']['duplicate']==after_commit and len(sql('SELECT id FROM gate_logs'))==1)
            finally: proxy.shutdown();proxy.server_close();worker.join(3)

        for wave in range(5):
            restore(); body=prepare()
            replies=race('movements.php',[body]*8,[guards[0]]*8)
            check(f'concurrent same-ticket wave {wave}: one audit',len(sql('SELECT id FROM gate_logs'))==1)
            check(f'concurrent same-ticket wave {wave}: all recover one id',all(c in (200,201) and r and r.get('data',{}).get('id')==1 for c,r in replies),[c for c,r in replies])
            restore(); bodies=[prepare() for _ in range(8)]
            replies=race('movements.php',bodies,[guards[0]]*8)
            check(f'competing scans wave {wave}: one wins, others stale',sorted(c for c,r in replies)==[201]+[409]*7 and len(sql('SELECT id FROM gate_logs'))==1,[c for c,r in replies])

        # Exercise an adversarial schedule by slowing the gap after the uniqueness check.
        # Only the temporary server copy is instrumented; no branch/outcome is changed.
        restore()
        source=s.root/'web-app-admin/api/visitors.php'
        original=source.read_text(encoding='utf-8')
        marker="    $clientCode = trim((string)($data['passCode']"
        assert marker in original
        source.write_text(original.replace(marker,"    usleep(200000); // TEST-ONLY schedule point after duplicate check\n"+marker),encoding='utf-8')
        replies=race('visitors.php',[visitor,visitor],[guards[0],guards[1]])
        count=sql("SELECT COUNT(*) FROM visitor_passes WHERE plate_number='RACEVIS' AND status='Active'")[0][0]
        check('overlapping visitor issuance creates one active pass',count==1,{'activePasses':count,'responses':[c for c,r in replies],'schedule':'200ms pause after duplicate check in fixture copy'})
        source.write_text(original,encoding='utf-8')

        restore()
        c,r=call(base,'vehicles.php',{'plateNumber':'PAYRACE','vehicleType':'4-Wheel','ownerName':'Payment Owner','ownerRole':'Student','ownerIdNumber':'PAYOWNER','stickerYear':'2026'},admin)
        assert c==201,r
        paid_id=r['data']['id']
        source=s.root/'web-app-admin/api/payments.php';original=source.read_text(encoding='utf-8')
        marker="    $fee = (float)$vehicle['fee_amount'];"
        assert marker in original
        source.write_text(original.replace(marker,'    usleep(200000); // TEST-ONLY schedule point after unpaid check\n'+marker),encoding='utf-8')
        replies=race('payments.php',[{'action':'cash','vehicleId':paid_id}]*2,[admin]*2)
        paid=sql("SELECT status,notes FROM payments WHERE vehicle_id=?",(paid_id,))
        check('overlapping cash submissions record one payment',len(paid)==1,{'payments':paid,'responses':[c for c,r in replies],'schedule':'200ms pause after unpaid check in fixture copy'})
        source.write_text(original,encoding='utf-8')

        # Model-based sequence: successful transitions alternate; retries and denials never move it.
        restore(); rng=random.Random(20261011);inside=False;expected=0;event=False
        for step in range(120):
            if rng.random()<.25:
                event=not event
                assert call(base,'settings.php',{'event_gate_mode':int(event),'reason':'Seeded sequence transition'},admin,'PUT')[0]==200
            token=guards[rng.randrange(2)] if event else guards[1 if inside else 0]
            body=prepare(token)
            op=rng.choice(['valid','retry','wrong_driver','tampered_ticket','other_actor'])
            before=fingerprint(s.db)
            if op=='wrong_driver':
                c,r=call(base,'movements.php',{**body,'driver_id':999999},token)
                ok=400<=c<500 and fingerprint(s.db)==before
            elif op=='tampered_ticket':
                c,r=call(base,'movements.php',{**body,'ticket':body['ticket']+'bad'},token)
                ok=400<=c<500 and fingerprint(s.db)==before
            elif op=='other_actor':
                c,r=call(base,'movements.php',body,guards[1] if token==guards[0] else guards[0])
                ok=400<=c<500 and fingerprint(s.db)==before
            else:
                c,r=call(base,'movements.php',body,token)
                ok=c==201
                if ok: inside=not inside;expected+=1
                if op=='retry':
                    c2,r2=call(base,'movements.php',body,token)
                    ok=ok and c2==200 and r2['data']['id']==r['data']['id']
            check(f'seeded transition {step} ({op})',ok,{'status':c,'message':r.get('message')})
            state=sql('SELECT status FROM vehicles WHERE id=?',(vehicle['id'],))[0][0]
            check(f'seeded invariant {step}: custody equals successful audits',state==('Inside Campus' if inside else 'Outside') and len(sql('SELECT id FROM gate_logs'))==expected)
        snapshot.close()
        for i,log in enumerate(s.logs):
            log.seek(0);(OUT/f'recovery-server-{i}.log').write_bytes(log.read())
    report={'total':len(results),'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),'results':results}
    (OUT/'recovery-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print({k:v for k,v in report.items() if k!='results'},flush=True)
    return int(report['failed']>0)


if __name__=='__main__': raise SystemExit(main())
