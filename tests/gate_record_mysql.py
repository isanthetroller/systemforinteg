"""Repeat the gate-history filter model on a disposable MariaDB instance."""
import os, secrets, socket, subprocess, tempfile, time
from pathlib import Path
from gate_record_filters import seed, run
from movement_integration import Sandbox, ROOT, call

BIN=Path(r'C:\xampp\mysql\bin')

def main():
    with tempfile.TemporaryDirectory(prefix='securepark-gate-filter-mysql-') as temporary:
        directory=Path(temporary).resolve(); data=directory/'data'
        assert directory.name.startswith('securepark-gate-filter-mysql-') and data.parent==directory
        with socket.socket() as sock: sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
        password=secrets.token_hex(24); env={**os.environ,'MYSQL_PWD':password}
        result=subprocess.run([str(BIN/'mysql_install_db.exe'),f'--datadir={data}',f'--password={password}',f'--port={port}','--silent'],capture_output=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        assert result.returncode==0,'Isolated MySQL setup failed'
        def query(sql,database=True):
            cmd=[str(BIN/'mysql.exe'),'--no-defaults','--protocol=tcp','--host=127.0.0.1',f'--port={port}','--user=root','--batch','--skip-column-names','--default-character-set=utf8mb4']
            if database:cmd.append('gate_filter_test')
            r=subprocess.run(cmd,input=sql.encode(),capture_output=True,env=env,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
            if r.returncode:raise RuntimeError('Isolated SQL statement failed: '+r.stderr.decode(errors='replace'))
            return r.stdout.decode().strip()
        with (directory/'server.log').open('wb') as log:
            server=subprocess.Popen([str(BIN/'mysqld.exe'),'--no-defaults',f'--basedir={BIN.parent}',f'--datadir={data}',f'--port={port}','--bind-address=127.0.0.1','--skip-name-resolve','--innodb-buffer-pool-size=32M','--console'],stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                for _ in range(80):
                    try:query('SELECT 1;',False);break
                    except RuntimeError:time.sleep(.1)
                else:raise RuntimeError('Isolated MariaDB did not start')
                query('CREATE DATABASE gate_filter_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',False)
                query((ROOT/'backend/database/schema.sql').read_text(encoding='utf-8'))
                with Sandbox() as s:
                    _,rows=seed(s)
                    secret=s.root/'web-app-admin/config/secret.php'
                    text=secret.read_text().replace("define('SP_FORCE_SQLITE', true);",'')
                    text+=f"\ndefine('SP_DB_HOST','127.0.0.1;port={port}');\ndefine('SP_DB_NAME','gate_filter_test');\ndefine('SP_DB_USER','root');\ndefine('SP_DB_PASS','{password}');\n"
                    secret.write_text(text)
                    def quote(v):return 'NULL' if v is None else "'"+str(v).replace('\\','\\\\').replace("'","''")+"'"
                    for r in rows:
                        fields=[r['id'],r['plate'],'4-Wheel','Test Owner','Test Driver','Self',r['gate'],r['action'],'Egress' if 'Exit' in r['action'] else 'Ingress',r['status'],r['officer'],r['notes'],r['at'],r['synced']]
                        query('INSERT INTO gate_logs(id,plate_number,vehicle_type,owner_name,driver_name,driver_relationship,gate_point,action,gate_type,status,guard_name,notes,logged_at,synced_at) VALUES ('+','.join(map(quote,fields))+');')
                    c,r=call(s.bases[0],'auth.php?action=login',{'username':'admin','password':'Password123!'})
                    assert c==200,r
                    token=r['data']['token']
                    assert call(s.bases[0],'auth.php?action=change_password',{'current_password':'Password123!','new_password':'GateRecords-MySQL-2026!'},token)[0]==200
                    print('MariaDB '+query('SELECT VERSION();'),flush=True)
                    run(s,token,rows,query)
            finally:
                try:query('SHUTDOWN;',False)
                except Exception:server.terminate()
                server.wait(timeout=15)

if __name__=='__main__':main()
