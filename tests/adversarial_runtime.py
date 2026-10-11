"""Reproducible input/permission probes. Disposable PHP + SQLite only.

This is bounded adversarial testing, not exhaustive proof. Findings are retained,
including failed invariants; the process exits nonzero when any check fails.
"""
from contextlib import closing
import collections
import hashlib
import json
from pathlib import Path
import random
import sqlite3
import time
import urllib.request
import urllib.error
from movement_integration import Sandbox, call, ROOT

SEED = 20261011
OUT = ROOT / 'artifacts' / 'adversarial'
TABLES = ('vehicles', 'visitor_passes', 'visitor_pass_items', 'gate_logs',
          'security_incidents', 'vehicle_violations', 'payments', 'system_users',
          'system_settings', 'exit_releases')


def fingerprint(path):
    with closing(sqlite3.connect(path)) as db:
        return {t: hashlib.sha256(repr(db.execute(f'SELECT * FROM {t} ORDER BY rowid').fetchall()).encode()).hexdigest() for t in TABLES}


def raw_call(base, path, body=b'', token=None, method='POST'):
    headers = {'Content-Type': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(base+'/'+path, data=body if method != 'GET' else None, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=12)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        try: data = json.loads(raw)
        except (ValueError, UnicodeError): data = None
        return response.status, data, raw.decode('utf-8', errors='replace')[:1200]


def setup(s):
    base = s.bases[0]
    admin = call(base, 'auth.php?action=login', {'username':'admin','password':'Password123!'})[1]['data']['token']
    assert call(base, 'auth.php?action=change_password', {'current_password':'Password123!','new_password':'Adversarial-Admin-2026'}, admin)[0] == 200
    guards = []
    for n in (1, 2):
        assert call(base,'users.php',{'username':f'probe{n}','full_name':f'Probe {n}','password':'Adversarial-Guard-2026','role':'guard','gate_assigned':f'Gate {n}'},admin)[0] == 201
        guards.append(call(base,'auth.php?action=login',{'username':f'probe{n}','password':'Adversarial-Guard-2026'})[1]['data']['token'])
    c, r = call(base,'vehicles.php',{'plateNumber':'ADV100','vehicleType':'Bicycle','category':'non-plated','ownerName':'Fixture Owner','ownerRole':'Student','ownerIdNumber':'ADVOWNER','stickerYear':'2026'},admin)
    assert c == 201, r
    return admin, guards, r['data']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    started = time.monotonic()
    with Sandbox() as s:
        admin, guards, vehicle = setup(s)
        memory = sqlite3.connect(':memory:')
        with closing(sqlite3.connect(s.db)) as db: db.backup(memory)
        baseline = fingerprint(s.db)
        def restore():
            with closing(sqlite3.connect(s.db)) as db: memory.backup(db)
        def probe(group, name, endpoint, body=None, method='POST', token=admin,
                  reject=True, immutable=True, raw=None, expected_name=None):
            restore()
            code, data, preview = raw_call(s.bases[0], endpoint,
                raw if raw is not None else json.dumps(body).encode(), token, method)
            faults = []
            if not isinstance(data, dict) or not isinstance(data.get('success'), bool): faults.append('non_json_or_invalid_contract')
            if code >= 500: faults.append('unexpected_server_error')
            preview_refused = isinstance(data,dict) and isinstance(data.get('data'),dict) and data['data'].get('accepted') is False
            if reject and not (400 <= code < 500 or (code == 200 and preview_refused)): faults.append('invalid_input_accepted' if code < 400 else 'invalid_input_crashed')
            changed = [t for t,v in fingerprint(s.db).items() if v != baseline[t]]
            if immutable and changed: faults.append('unexpected_data_mutation')
            if expected_name is not None:
                if code != 201 or not data or data.get('data',{}).get('visitorName') != expected_name: faults.append('text_roundtrip_mismatch')
            result = {'group':group,'name':name,'endpoint':endpoint,'method':method,'status':code,'passed':not faults,'faults':faults}
            if faults: result.update(response=preview, changedTables=changed)
            results.append(result)
            if len(results) % 100 == 0: print(f'{len(results)} probes; {sum(not r["passed"] for r in results)} failures', flush=True)

        # Malformed syntax, unsupported root types, broken encoding, excessive nesting.
        writes = [('auth.php?action=login','POST'),('auth.php?action=change_password','POST'),
            ('users.php','POST'),('users.php','PUT'),('vehicles.php','POST'),('vehicles.php','PUT'),
            ('visitors.php','POST'),('visitors.php','PUT'),('visitors.php?action=exit','POST'),
            ('incidents.php','POST'),('incidents.php','PUT'),('violations.php','POST'),
            ('violations.php','PUT'),('logs.php','POST'),('movements.php','POST'),
            ('settings.php','PUT'),('cases.php','POST'),('payments.php','POST'),
            ('passes.php','POST'),('renewals.php','POST'),('releases.php','POST'),
            ('shifts.php','POST'),('approvals.php','POST'),('sync.php','POST')]
        malformed = [b'{', b'{"x":', b'null', b'true', b'42', b'"string"', b'[1,2]',
                     b'{"x":NaN}', b'{"x":"\xff"}', b'{"x":1}garbage', b'['*520+b']'*520]
        for endpoint, method in writes:
            for i, raw in enumerate(malformed):
                probe('malformed_json',f'body_{i}',endpoint,method=method,raw=raw)

        visitor = {'visitor_name':'Input Visitor','contact_number':'09123456789','plate':'INPUT100',
                   'purpose':'Testing','person_to_visit':'Security'}
        staff = {'username':'inputguard','full_name':'Input Guard','role':'guard','password':'Input-Guard-2026','gate_assigned':'Gate 1'}
        registration = {'plateNumber':'INPUT200','vehicleType':'Bicycle','category':'non-plated',
            'ownerName':'Input Owner','ownerRole':'Student','ownerIdNumber':'INPUTOWNER','stickerYear':'2026'}
        schemas = [
            ('visitors.php','POST',visitor,list(visitor)+['valid_date','vehicleModel','passCode']),
            ('users.php','POST',staff,list(staff)),
            ('vehicles.php','POST',registration,list(registration)),
            ('auth.php?action=login','POST',{'username':'nobody','password':'Invalid-Password'},['username','password']),
            ('incidents.php','POST',{'plateNumber':'INPUT300','reason':'Input check'},['plateNumber','reason','notes']),
            ('movements.php','POST',{'action':'prepare','qr_code':vehicle['qrPayload']},['action','qr_code']),
            ('logs.php','POST',{'plate':'ADV100','action':'Entry Recorded','driver_id':vehicle['authorizedDrivers'][0]['id']},['plate','action','driver_id','notes','checkpoint']),
            ('settings.php','PUT',{'event_gate_mode':1,'reason':'Fixture event'},['event_gate_mode','reason']),
            ('cases.php','POST',{'key':'I9999','action':'close','outcome':'Clearance signed','notes':'Fixture clearance'},['key','action','notes']),
        ]
        for endpoint, method, valid, fields in schemas:
            for field in fields:
                for tag, value in [('array',[]),('object',{'unexpected':'value'}),('nested',[{'nested':[1]}])]:
                    probe('wrong_field_shape',field+':'+tag,endpoint,{**valid,field:value},method)
        # Parameter array injection must never crash a list/search endpoint.
        queries = {'vehicles.php':['plate','qr','q'], 'visitors.php':['id','status','plate'],
            'logs.php':['plate','action','limit'], 'incidents.php':['status'], 'cases.php':['key','q','status','page'],
            'audit.php':['q','action','page'], 'oncampus.php':['q'], 'payments.php':['vehicleId'],
            'students.php':['q'], 'violations.php':['vehicle_id','status'], 'gate_policy.php':['checkpoint']}
        for endpoint, fields in queries.items():
            for field in fields:
                probe('query_shape',field+':array',endpoint+'?'+field+'%5B%5D=x',method='GET',reject=False)
                probe('query_shape',field+':object',endpoint+'?'+field+'%5Bx%5D=y',method='GET',reject=False)
        # Protected writes must reject unauthenticated and guard callers before mutation.
        for endpoint, method in [('users.php','POST'),('vehicles.php','POST'),('settings.php','PUT'),
                ('releases.php','POST'),('payments.php','POST'),('approvals.php','POST')]:
            for role, token in [('anonymous',None),('invalid_token','bad-token'),('guard',guards[0])]:
                probe('authorization',role,endpoint,{'event_gate_mode':1,'reason':'Unauthorized change'},method,token)
        # Numerical and item boundaries, including loose boolean coercion.
        for value in [-1,2,0.1,'1.5','1e0','NaN',None,[],{},'9'*100]:
            probe('setting_boundary',repr(value),'settings.php',{'event_gate_mode':value,'reason':'Boundary probe'},'PUT')
        for value in [-1,0,0.5,10000,'1.5','NaN',[],{}]:
            probe('item_quantity',repr(value),'visitors.php',{**visitor,'items':[{'name':'Equipment','quantity':value}]})
        for value in ['2026-02-30','0000-00-00','not-a-date','2026-13-01','9999-12-31','2026-10-11T00:00:00Z']:
            probe('date_boundary',value,'visitors.php',{**visitor,'valid_date':value})
        for value in ['', ' ', '\t\n', '\x00', '+', '123', 'abc@example.com']:
            probe('contact_boundary',repr(value),'visitors.php',{**visitor,'contact_number':value})
        # Correct acceptance matters as much as rejection: Unicode and hostile-looking text stay literal.
        for name in ['O\'Brien','José Niño','李明','أحمد','Visitor 🚗','<img src=x onerror=alert(1)>',"Robert'); DROP TABLE vehicles;--",'N'*150]:
            probe('text_roundtrip',name,'visitors.php',{**visitor,'visitor_name':name},reject=False,immutable=False,expected_name=name)
        rng = random.Random(SEED)
        alphabet = 'abCD0123 <>\'"\\/%;😀é漢\t\n'
        for n in range(150):
            name = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1,149))).strip()
            if not name: name = 'Visitor'
            probe('seeded_text_roundtrip',str(n),'visitors.php',{**visitor,'visitor_name':name},reject=False,immutable=False,expected_name=name)
        # Valid seed values are kept separate so they do not inflate malformed-input failures.
        memory.close()
        for i, log in enumerate(s.logs):
            log.seek(0)
            (OUT/f'input-server-{i}.log').write_bytes(log.read())
    summary = {'seed':SEED,'total':len(results),'passed':sum(r['passed'] for r in results),
        'failed':sum(not r['passed'] for r in results),'seconds':round(time.monotonic()-started,2),
        'byGroup':dict(collections.Counter(r['group'] for r in results)), 'results':results}
    (OUT/'input-results.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k!='results'},indent=2),flush=True)
    return int(summary['failed'] > 0)


if __name__ == '__main__': raise SystemExit(main())
