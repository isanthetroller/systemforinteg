"""Real API -> revision poll -> independent transport clients -> simulated renderer.
No real browser or mobile frontend is driven; never claim full UI E2E.
"""
from movement_integration import Sandbox, call, ROOT
from concurrent.futures import ThreadPoolExecutor
import os
import subprocess
import sqlite3
from contextlib import closing

def main():
    with Sandbox() as sandbox:
        base,other=sandbox.bases
        admin=call(base,'auth.php?action=login',{'username':'admin','password':'Password123!'})[1]['data']['token']
        call(base,'auth.php?action=change_password',{'current_password':'Password123!','new_password':'Live-Transport-2026'},admin)
        code,body=call(base,'users.php',{'username':'transportguard','full_name':'Transport Guard','role':'guard','password':'Live-Guard-2026','gate_assigned':'Checkpoint 2'},admin)
        assert code==201
        guard=call(base,'auth.php?action=login',{'username':'transportguard','password':'Live-Guard-2026'})[1]['data']['token']
        call(base,'auth.php?action=change_password',{'current_password':'Live-Guard-2026','new_password':'Live-Guard-Changed-2026'},guard)
        processes=[]
        try:
            for token in [admin,guard]:
                env={**os.environ,'SP_TEST_BASE':other,'SP_TEST_TOKEN':token,'SP_TEST_PLATE':'AUTOLIVE99'}
                processes.append(subprocess.Popen(['node','tests/live_api_client.cjs'],cwd=ROOT,env=env,
                    stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
            with ThreadPoolExecutor(max_workers=2) as pool:
                ready=list(pool.map(lambda p:p.stdout.readline().strip(),processes))
            assert ready==['READY','READY'],ready
            code,body=call(base,'vehicles.php',{'plateNumber':'AUTOLIVE99','vehicleType':'4-Wheel',
                'makeModelColor':'Transport fixture','ownerName':'Transport Owner','ownerRole':'Student',
                'ownerIdNumber':'TRANSPORT-OWNER','stickerYear':'2026'},admin)
            assert code==201,(code,body.get('message'))
            with closing(sqlite3.connect(sandbox.db)) as db:
                assert db.execute("SELECT COUNT(*) FROM vehicles WHERE plate_number='AUTOLIVE99'").fetchone()[0]==1
            print('PASS real authenticated write committed one database record')
            for label,p in zip(['admin','guard'],processes):
                output,error=p.communicate(timeout=25)
                assert p.returncode==0,(label,error)
                assert 'Transport Owner' in output and 'AUTOLIVE99' in output,output
                print(f'PASS {label} transport automatically polled and reconciled real API data into simulated UI state')
            print('3 real-API/transport checks passed; no browser/device E2E claim.')
        finally:
            for p in processes:
                if p.poll() is None:p.kill()
                p.wait()
if __name__=='__main__':main()
