"""Execute the actual mobile Dart transport worker against disposable PHP/SQLite.
Not real-device E2E. Does not connect to the cloud or working database.
"""
import os
import shutil
import subprocess
from movement_integration import Sandbox, call, ROOT

def main():
    flutter=os.environ.get('SP_TEST_FLUTTER') or shutil.which('flutter') or r'C:\Users\ethan\flutter\bin\flutter.bat'
    with Sandbox() as sandbox:
        base,other=sandbox.bases
        admin=call(base,'auth.php?action=login',{'username':'admin','password':'Password123!'})[1]['data']['token']
        call(base,'auth.php?action=change_password',{'current_password':'Password123!','new_password':'Mobile-Admin-2026'},admin)
        code,response=call(base,'users.php',{'username':'phoneguard','full_name':'Mobile Fixture Guard','role':'guard','password':'Mobile-Guard-2026','gate_assigned':'Checkpoint 2'},admin)
        assert code==201
        uid=response['data']['user']['id']
        guard=call(base,'auth.php?action=login',{'username':'phoneguard','password':'Mobile-Guard-2026'})[1]['data']['token']
        call(base,'auth.php?action=change_password',{'current_password':'Mobile-Guard-2026','new_password':'Mobile-Changed-2026'},guard)
        env={**os.environ,'SP_TEST_BASE':other,'SP_TEST_TOKEN':guard,'SP_TEST_ADMIN':admin,'SP_TEST_UID':str(uid)}
        result=subprocess.run([flutter,'test','--no-pub','test/integration_checks/live_php_transport_test.dart','--reporter','expanded'],cwd=ROOT/'mobile-app',env=env)
        return result.returncode
if __name__=='__main__':raise SystemExit(main())
