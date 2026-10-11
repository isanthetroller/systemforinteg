"""Isolated local MariaDB/InnoDB instance. Never connects to the installed data directory.

Creates a new datadir under a TemporaryDirectory, a random loopback port and fixture
credentials. No Windows service is installed. All SQL runs against this new instance.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import threading
import time
from adversarial_runtime import OUT, setup, raw_call
from movement_integration import Sandbox, ROOT, call

BIN=Path(r'C:\xampp\mysql\bin')


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    results=[]
    def check(name,ok,detail=None):
        results.append({'name':name,'passed':bool(ok),'detail':detail})
        print(('PASS ' if ok else 'FAIL ')+name,flush=True)
    with tempfile.TemporaryDirectory(prefix='securepark-adversarial-mariadb-') as root:
        directory=Path(root).resolve()
        data=directory/'data'
        assert directory.name.startswith('securepark-adversarial-mariadb-') and data.parent==directory
        with socket.socket() as sock: sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        password=secrets.token_hex(24)
        bootstrap=subprocess.run([str(BIN/'mysql_install_db.exe'),f'--datadir={data}',f'--password={password}',f'--port={port}','--silent'],capture_output=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        (OUT/'mariadb-bootstrap.log').write_bytes(bootstrap.stdout+bootstrap.stderr)
        if bootstrap.returncode: raise RuntimeError('Isolated MariaDB bootstrap failed; see log')
        env={**os.environ,'MYSQL_PWD':password}
        def query(sql,database=True):
            command=[str(BIN/'mysql.exe'),'--no-defaults','--protocol=tcp','--host=127.0.0.1',f'--port={port}','--user=root','--batch','--skip-column-names','--default-character-set=utf8mb4']
            if database: command.append('adversarial')
            r=subprocess.run(command,input=sql.encode(),capture_output=True,env=env,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
            if r.returncode: raise RuntimeError(r.stderr.decode(errors='replace'))
            return r.stdout.decode('utf-8',errors='replace').strip()
        with (OUT/'mariadb-server.log').open('wb') as log:
            server=subprocess.Popen([str(BIN/'mysqld.exe'),'--no-defaults',f'--basedir={BIN.parent}',f'--datadir={data}',f'--port={port}','--bind-address=127.0.0.1','--skip-name-resolve','--innodb-buffer-pool-size=32M','--console'],stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                for attempt in range(80):
                    if server.poll() is not None: raise RuntimeError('Isolated MariaDB exited; see server log')
                    try: version=query('SELECT VERSION();',False);break
                    except (RuntimeError,subprocess.TimeoutExpired): time.sleep(.1)
                else: raise RuntimeError('Isolated MariaDB did not start')
                check('dedicated loopback MariaDB instance started',True,version)
                query('CREATE DATABASE adversarial CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',False)
                query((ROOT/'backend/database/schema.sql').read_text(encoding='utf-8'))
                query((ROOT/'backend/database/migrations/012_gate_operation.sql').read_text(encoding='utf-8'))
                query((ROOT/'backend/database/migrations/012_gate_operation.sql').read_text(encoding='utf-8'))
                check('fresh schema and repeated migration 012 import',query("SELECT COUNT(*) FROM system_settings WHERE setting_key='event_gate_mode'")=='1')
                with Sandbox() as s:
                    secret=s.root/'web-app-admin/config/secret.php'
                    value=secret.read_text(encoding='utf-8').replace("define('SP_FORCE_SQLITE', true)","define('SP_FORCE_SQLITE', false)")
                    value+=f"\ndefine('SP_DB_HOST','127.0.0.1;port={port}');\ndefine('SP_DB_NAME','adversarial');\ndefine('SP_DB_USER','root');\ndefine('SP_DB_PASS','{password}');\n"
                    secret.write_text(value,encoding='utf-8')
                    admin,guards,vehicle=setup(s)
                    base=s.bases[0]
                    check('PHP actually uses isolated MySQL database',query("SELECT COUNT(*) FROM vehicles WHERE plate_number='ADV100'")=='1')
                    driver=vehicle['authorizedDrivers'][0]['id']
                    def prepare(token=guards[0]):
                        c,r=call(base,'movements.php',{'action':'prepare','qr_code':vehicle['qrPayload']},token)
                        assert c==200 and r['data']['accepted'],r
                        return {'action':'confirm','ticket':r['data']['movement']['ticket'],'driver_id':driver}
                    def race(endpoint,bodies,tokens):
                        barrier=threading.Barrier(len(bodies))
                        def one(i):
                            barrier.wait();return raw_call(s.bases[i%2],endpoint,json.dumps(bodies[i]).encode(),tokens[i])[:2]
                        with concurrent.futures.ThreadPoolExecutor(max_workers=len(bodies)) as pool: return list(pool.map(one,range(len(bodies))))
                    body=prepare()
                    replies=race('movements.php',[body]*8,[guards[0]]*8)
                    check('MySQL concurrent identical confirmation commits once',query("SELECT COUNT(*) FROM gate_logs WHERE plate_number='ADV100'")=='1' and sorted(c for c,r in replies)==[200]*7+[201],[c for c,r in replies])
                    body=prepare(guards[1])
                    query("CREATE TRIGGER fail_gate BEFORE INSERT ON gate_logs FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected storage failure';")
                    c,r=call(base,'movements.php',body,guards[1])
                    check('MySQL audit failure preserves inside custody',c==503 and query("SELECT status FROM vehicles WHERE plate_number='ADV100'")=='Inside Campus',c)
                    query('DROP TRIGGER fail_gate;')
                    check('MySQL original ticket recovers after repair',call(base,'movements.php',body,guards[1])[0]==201)
                    assert call(base,'settings.php',{'event_gate_mode':1,'reason':'Isolated engine event'},admin,'PUT')[0]==200
                    assert call(base,'movements.php',prepare(guards[1]),guards[1])[0]==201
                    stale=prepare(guards[0])
                    assert call(base,'settings.php',{'event_gate_mode':0,'reason':'Isolated engine normal'},admin,'PUT')[0]==200
                    check('MySQL mode reversal rejects pending wrong-gate exit',call(base,'movements.php',stale,guards[0])[0]==403)
                    # Instrument only the copied fixture to force overlapping precondition checks.
                    for endpoint,marker,payload,table in [
                        ('visitors.php',"    $clientCode = trim((string)($data['passCode']",{'visitor_name':'Concurrent Visitor','contact_number':'09123456789','plate':'SQLRACE','purpose':'Testing','person_to_visit':'Security'},'visitor_passes'),
                        ('payments.php',"    $fee = (float)$vehicle['fee_amount'];",None,'payments')]:
                        if payload is None:
                            c,r=call(base,'vehicles.php',{'plateNumber':'SQLPAY','vehicleType':'4-Wheel','ownerName':'SQL Owner','ownerRole':'Student','ownerIdNumber':'SQLPAYOWNER','stickerYear':'2026'},admin)
                            assert c==201,r
                            payload={'action':'cash','vehicleId':r['data']['id']}
                        source=s.root/'web-app-admin/api'/endpoint
                        original=source.read_text(encoding='utf-8');assert marker in original
                        source.write_text(original.replace(marker,'    usleep(200000); // TEST ONLY: competing precondition window\n'+marker),encoding='utf-8')
                        replies=race(endpoint,[payload]*2,[admin]*2)
                        count=int(query('SELECT COUNT(*) FROM '+table))
                        check('MySQL overlapping '+endpoint+' creates one record',count==1,{'rows':count,'responses':[c for c,r in replies],'schedule':'200ms pause after precondition in fixture only'})
                        source.write_text(original,encoding='utf-8')
                    # SQL strictness must turn too-long text into validation, not a broken response.
                    c,d,raw=raw_call(base,'users.php',json.dumps({'username':'longuser','full_name':'N'*1000,'role':'guard','password':'Long-Password-2026','gate_assigned':'Gate 1'}).encode(),admin)
                    check('MySQL overlong staff name yields controlled validation',400<=c<500 and isinstance(d,dict),{'status':c,'body':raw[:240]})
                    for i,logfile in enumerate(s.logs):
                        logfile.seek(0);(OUT/f'mysql-php-{i}.log').write_bytes(logfile.read())
            finally:
                try: query('SHUTDOWN;',False)
                except Exception: server.terminate()
                server.wait(timeout=15)
    report={'total':len(results),'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),'results':results}
    (OUT/'mysql-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print({k:v for k,v in report.items() if k!='results'},flush=True)
    return int(report['failed']>0)


if __name__=='__main__':raise SystemExit(main())
