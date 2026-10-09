"""Source-stable validation runner. Backend mutations occur only in disposable Sandbox.
Never invokes api_smoke --fresh against a working database. No browser/device claims.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time
from movement_integration import Sandbox
import api_smoke

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts'
PHP = os.environ.get('SP_TEST_PHP', r'C:\xampp\php\php.exe')
results = []

def command(name, args, log, cwd=ROOT):
    started = time.monotonic()
    with (OUT / log).open('w', encoding='utf-8') as stream:
        process = subprocess.run(args, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                 encoding='utf-8', errors='replace')
    result = {'name':name, 'result':'PASS' if process.returncode == 0 else 'FAIL',
              'exitCode':process.returncode, 'log':log, 'seconds':round(time.monotonic()-started,2)}
    results.append(result)
    print(name, result['result'], flush=True)

def main():
    OUT.mkdir(exist_ok=True)
    roots=['backend','web-app-admin','web-app-student','mobile-app/lib']
    manifest={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
              for root in roots for p in (ROOT/root).rglob('*')
              if p.is_file() and p.suffix in {'.php','.js','.css','.html','.dart','.sql'}
              and not any(part in p.parts for part in ('config','data','uploads','vendor','node_modules'))}
    (OUT/'validation-source-manifest.json').write_text(json.dumps(manifest,indent=2))
    command('movement PHP/SQLite integration', [sys.executable,'-X','utf8','tests/movement_integration.py'], 'baseline-movement.log')
    command('authenticated revision API integration', [sys.executable,'-X','utf8','tests/realtime_integration.py'], 'baseline-realtime-api.log')
    command('web transport simulated-DOM units', ['node','tests/live_transport_test.cjs'], 'baseline-live-transport.log')
    command('real API with two transport clients and simulated renderers', [sys.executable,'-X','utf8','tests/live_api_integration.py'], 'baseline-live-api-clients.log')
    command('legacy violations simulated-DOM presentation', ['node','tests/test_violations_ui.cjs'], 'baseline-violations-ui.log')
    # Redirect the existing broad suite entirely into a fresh copied test backend.
    with Sandbox() as sandbox:
        api_smoke.BASE = sandbox.bases[0]
        api_smoke.ROOT = str(sandbox.root)
        api_smoke.SQLITE_DB = str(sandbox.db)
        api_smoke.SCANNER = {'X-Api-Key':sandbox.scanner_key, 'User-Agent':'SecurePark-Tests'}
        original = sys.stdout
        code = 0
        with (OUT / 'baseline-backend-suite.log').open('w',encoding='utf-8') as stream:
            try:
                sys.stdout = stream
                try:
                    api_smoke.main()
                except SystemExit as error:
                    code = error.code or 0
            finally:
                sys.stdout = original
        results.append({'name':'broad real API/SQLite suite','result':'PASS' if code==0 else 'FAIL',
                        'exitCode':code,'log':'baseline-backend-suite.log',
                        'assertionsPassed':api_smoke.passed,'assertionsFailed':api_smoke.failed})
        print('broad real API/SQLite suite',results[-1]['result'],flush=True)
    checks = []
    for p in sorted((ROOT/'backend').rglob('*.php')):
        if 'config' not in p.parts:
            completed = subprocess.run([PHP,'-l',str(p)],capture_output=True,text=True)
            checks.append((str(p.relative_to(ROOT)),completed.returncode,completed.stdout.strip()+completed.stderr.strip()))
    for p in sorted((ROOT/'web-app-admin').rglob('*.php')):
        if 'config' not in p.parts:
            completed = subprocess.run([PHP,'-l',str(p)],capture_output=True,text=True)
            checks.append((str(p.relative_to(ROOT)),completed.returncode,completed.stdout.strip()+completed.stderr.strip()))
    (OUT/'baseline-php-lint.log').write_text('\n'.join(f'{name}: {output}' for name,code,output in checks),encoding='utf-8')
    results.append({'name':'PHP syntax excluding private config','result':'PASS' if all(code==0 for _,code,_ in checks) else 'FAIL','files':len(checks),'log':'baseline-php-lint.log'})
    scripts = sorted([p for directory in ['web-app-admin/js','web-app-student/js'] for p in (ROOT/directory).glob('*.js')])
    with (OUT/'baseline-js-syntax.log').open('w',encoding='utf-8') as stream:
        failures=[]
        for p in scripts:
            completed=subprocess.run(['node','--check',str(p)],capture_output=True,text=True)
            stream.write(f'{p.relative_to(ROOT)}: {"PASS" if completed.returncode==0 else "FAIL"}\n{completed.stderr}')
            if completed.returncode: failures.append(str(p))
    results.append({'name':'JavaScript syntax','result':'PASS' if not failures else 'FAIL','files':len(scripts),'log':'baseline-js-syntax.log'})
    mirror=[]
    for folder in ['api','lib','database']:
        for p in (ROOT/'backend'/folder).rglob('*'):
            if p.is_file() and p.suffix in ['.php','.sql']:
                target=ROOT/'web-app-admin'/p.relative_to(ROOT/'backend')
                if not target.exists() or p.read_bytes()!=target.read_bytes(): mirror.append(str(p.relative_to(ROOT)))
    results.append({'name':'canonical deployment mirror','result':'PASS' if not mirror else 'FAIL','differences':mirror})
    changed=[name for name,digest in manifest.items() if not (ROOT/name).exists() or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
    results.append({'name':'production source freeze','result':'PASS' if not changed else 'FAIL','files':len(manifest),'changed':changed})
    (OUT/'baseline-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(json.dumps(results,indent=2))
    return 1 if any(r['result']=='FAIL' for r in results) else 0

if __name__=='__main__':
    raise SystemExit(main())
