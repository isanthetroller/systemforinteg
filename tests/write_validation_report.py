"""Archived baseline report generator, requiring original pre-correction logs/source.
For current validation use system_validation.py and mobile_php_integration.py.
Does not modify application source.
"""
from pathlib import Path
import csv
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts'
REPORT=ROOT/'docs/realtime-plan-and-system-validation-2026-10-09.md'
CSV=ROOT/'docs/system-validation-coverage-2026-10-09.csv'
rows=[]
groups=[]

def evidence(log,line=None):
    return (OUT/log).as_posix()+(f':{line}' if line else '')

for prefix,log,kind,application in [
    ('API','baseline-backend-suite.log','Real PHP/SQLite integration','Backend/database'),
    ('MOV','baseline-movement.log','Real concurrent PHP/SQLite integration','Backend/database'),
    ('REV','baseline-realtime-api.log','Real independent-client API integration','Backend/database'),
    ('TRN','baseline-live-transport.log','Actual JS with simulated DOM/API/timers','Web transport'),
    ('HTTP','baseline-live-api-clients.log','Real HTTP + actual JS + simulated renderer','Backend/web transport')]:
    group=kind; start=0; count=0
    for line_no,line in enumerate((OUT/log).read_text(encoding='utf-8').splitlines(),1):
        if line.startswith('== '):
            if count:groups.append((group,count,log,start))
            group=line[3:];start=line_no;count=0
        match=re.match(r'\s*PASS\s+(.+)',line)
        if match:
            number=sum(r['id'].startswith(prefix+'-') for r in rows)+1
            name=match.group(1)
            issue='RT001' if any(w in name.lower() for w in ['revoked','bearer','anonymous','unauthorized']) else ''
            rows.append(dict(id=f'{prefix}-{number:03}',application=application,feature=group,
                scenario=name,testType=kind,expected=name,actual='Executed assertion evaluated true',
                result='PASS',evidence=evidence(log,line_no),issue=issue))
            count+=1
    if prefix=='API' and count:groups.append((group,count,log,start))

flutter=(OUT/'baseline-flutter-tests.log').read_text(encoding='utf-8')
assert '+168 -1: Some tests failed.' in flutter
events=[]
for line_no,line in enumerate((OUT/'baseline-flutter-machine.jsonl').read_text(encoding='utf-8-sig').splitlines(),1):
    try: event=json.loads(line)
    except ValueError: continue
    if isinstance(event,dict):events.append((line_no,event))
starts={event['test']['id']:event['test'] for _,event in events if event.get('type')=='testStart'}
visible=[(n,e) for n,e in events if e.get('type')=='testDone' and not e.get('hidden')]
assert len(visible)==169 and sum(e.get('result')=='success' for _,e in visible)==168
for index,(line_no,event) in enumerate(visible,1):
    test=starts[event['testID']]
    name=test['name']
    failed=event.get('result')!='success'
    feature=test.get('url','').replace('\\','/').split('/')[-1] or 'Flutter test'
    issue='RT003, RT006, N014' if failed else ('RT001' if '401' in name else '')
    rows.append(dict(id=f'FLT-{index:03}',application='Mobile',feature=feature,scenario=name,
        testType='Executed Flutter unit/component with mocks',expected='Test assertions succeed',
        actual='Framework testDone: '+event.get('result','unknown'),result='FAIL' if failed else 'PASS',
        evidence=evidence('baseline-flutter-machine.jsonl',line_no),issue=issue))
rows.append(dict(id='FLT-ALL',application='Mobile',feature='Full Flutter suite',
    scenario='All existing tests plus new transport and open-card baseline',testType='Mocked unit/component tests',
    expected='All 169 tests pass',actual='168 passed; one new visitor live-card test failed, with stale text and a layout overflow',
    result='FAIL',evidence=evidence('baseline-flutter-tests.log'),issue='RT003, RT006, N014'))
rows.append(dict(id='FLT-CARD',application='Mobile',feature='Open visitor confirmation',
    scenario='Repository publishes changed/blocked pass while confirmation is already open',testType='Executed widget baseline',
    expected='Updated fixture visitor replaces original text',actual='Zero matching updated widgets; original pass remains rendered',
    result='FAIL',evidence=evidence('baseline-flutter-tests.log'),issue='RT003, RT006'))
rows.append(dict(id='FLT-LAYOUT',application='Mobile',feature='Visitor QR card layout',
    scenario='Render confirmation with current validity caption',testType='Executed widget rendering in same test case',
    expected='No RenderFlex overflow',actual='110-pixel right overflow at Row line 405 under 382-pixel constraint',
    result='FAIL',evidence=evidence('baseline-flutter-tests.log'),issue='N014'))

limitations=[
 ('E2E-WW','Web → Web','Two administrator browser sessions automatically update rendered views','BLOCKED','Browser access rejected by automatic approval/security review','RT005, N011'),
 ('E2E-WM','Web → Mobile','Web blocks/edits while real phone renders current account/vehicle','BLOCKED','No Android device/emulator; browser also unavailable','RT002, RT004, RT008, N011'),
 ('E2E-MW','Mobile → Web','Physical guard scan updates another real browser dashboard','BLOCKED','No Android device/emulator and browser access rejected','RT003, N001, N011'),
 ('E2E-MM','Mobile → Mobile','Two real phones synchronize movement/pass details','BLOCKED','No Android devices/emulators','RT003, RT006, N011'),
 ('E2E-GATES','Web/mobile guards','All four guard combinations through actual UI and cameras','BLOCKED','Real APIs pass separately; actual browser/device execution unavailable','N001, N011'),
 ('E2E-OWNER','Owner portal','Pass/activity/cases/payments/notices/profile update visually','BLOCKED','Browser access rejected','RT004, R007'),
 ('E2E-ADMIN','Admin portal','Dashboard/vehicles/campus/history/cases/visitors/payments/Admin Center/settings/approvals/evidence visual flow','BLOCKED','Browser access rejected','RT003, RT005, R001–R008'),
 ('E2E-CAMERA','Mobile scanner','Physical camera scanning, OCR and image upload on device','BLOCKED','No Android device/emulator; parser/widget tests are separate','N011'),
 ('E2E-LIFECYCLE','Mobile recovery','Airplane mode, background suspension and app-resume rendering','BLOCKED','No real mobile runtime','RT010'),
 ('DB-MYSQL','Deployment database','MySQL migrations, row locks, deadlocks and rollback parity','BLOCKED','No configured disposable MySQL test environment','N011'),
 ('NET-DB','Recovery','Whole database unavailable and subsequent live UI recovery','NOT TESTED','Injected transaction rollback passed; whole DB shutdown recovery not executed','RT007, RT010'),
 ('NET-SOAK','Reliability','Multi-hour sessions, very slow network and target-scale soak','NOT TESTED','Bounded request/timer tests only; no workload/SLO supplied','RT010, N007'),
 ('QUEUE-IDENTITY','Historical queue','Queued event from guard A replayed after login as B','NOT TESTED','Specific account-switch queue scenario not executed','N010'),
 ('SESSION-EXPIRY','Authentication','Wall-clock session lifetime expiration during open UI','NOT TESTED','Revocation/reset tested; natural lifetime expiration not separately executed','RT002, RT008'),
 ('MAIL-LIVE','External delivery','Actual mailbox delivery and real payment provider callback','NOT TESTED','Local SMTP and simulated payment contracts only','N011'),
 ('REV-COUNTERS','Synchronization scale','Transactionally persisted domain revision counters','NOT IMPLEMENTED','Current implementation hashes row content','N007'),
 ('CARD-SUBSCRIBE','Open mobile visitor card','Card subscribes by ID to repository changes','NOT IMPLEMENTED','Failed baseline proves existing snapshot remains static','RT003, RT006'),
 ('KPI-SERVER','Mobile metrics','Mobile dashboard uses full authoritative daily aggregate','NOT IMPLEMENTED','Current display derives data from bounded recent logs','N003'),
]
for identifier,feature,expected,result,actual,issue in limitations:
    rows.append(dict(id=identifier,application='Cross-platform',feature=feature,scenario=expected,
        testType='Required workflow/runtime validation',expected=expected,actual=actual,result=result,
        evidence='Report environment/limitations; not an executed PASS',issue=issue))

analysis=(OUT/'realtime-flutter-analysis.log').read_text(encoding='utf-8')
assert '20 issues found' in analysis
static=[('PHP','PHP syntax','PASS','110 PHP files; private config excluded','baseline-php-lint.log',''),
 ('JS','JavaScript syntax','PASS','33 files checked','baseline-js-syntax.log',''),
 ('ANALYZE','Flutter analyzer','FAIL','1 duplicate-import warning and 19 brace diagnostics; exit 1','realtime-flutter-analysis.log','N013'),
 ('BUILD','Android debug APK','PASS','assembleDebug built successfully; emulator API override on port 8001','baseline-apk-build.log','N011'),
 ('LEGACY','Legacy violations presentation units','PASS','Pagination/filter/search/empty/loading/manual/background checks passed','baseline-violations-ui.log','R006')]
assert 'Built' in (OUT/'baseline-apk-build.log').read_text(encoding='utf-8')
for identifier,feature,result,actual,log,issue in static:
    rows.append(dict(id=identifier,application='Static/build/client units',feature=feature,scenario=feature,
        testType='Static/build' if identifier!='LEGACY' else 'Simulated DOM presentation',expected='Check succeeds',actual=actual,
        result=result,evidence=evidence(log),issue=issue))
with CSV.open('w',newline='',encoding='utf-8-sig') as stream:
    writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)

summary='''### Executed frozen-source results

| Check | Actual result | Evidence |
|---|---|---|
'''
for name,result,log in [
 ('Broad real PHP/SQLite regression','PASS — 678 assertions, 0 failures','baseline-backend-suite.log'),
 ('Signed movement/concurrency integration','PASS — 85 assertions','baseline-movement.log'),
 ('Authenticated revision/session API integration','PASS — 19 assertions','baseline-realtime-api.log'),
 ('Web transport units with simulated DOM/timers','PASS — 12 checks','baseline-live-transport.log'),
 ('Real API with independent admin and guard transport clients','PASS — 3 checks; simulated renderers, not browser E2E','baseline-live-api-clients.log'),
 ('Flutter full suite including new stale-card baseline','FAIL — 168 passed, 1 test failed','baseline-flutter-tests.log'),
 ('Flutter analyzer','FAIL — 1 warning, 19 style diagnostics','realtime-flutter-analysis.log'),
 ('Android debug APK','PASS — build only','baseline-apk-build.log'),
 ('PHP / JavaScript syntax','PASS — 110 PHP / 33 JS files','baseline-results.json'),
 ('Mirror parity and source freeze','PASS — no mirror differences; 238 source hashes unchanged','baseline-results.json'),
 ('Legacy violations presentation','PASS — simulated DOM checks','baseline-violations-ui.log')]:
    summary+=f'| {name} | {result} | [{log}]({evidence(log)}) |\n'
summary+='''
The earlier transport/regression suite had 168 passing Flutter tests. Adding a targeted, non-skipped open-card baseline produced 168 passes and one failure. That failure is preserved: it demonstrates stale card text and a separate QR-caption layout overflow. No assertions were weakened to obtain a green baseline.

Real movement tests exercise G1→G1, G1→G2, G2→G1 and G2→G2, cancellation, duplicate confirmation, competing guards, lost-response retry, forced rollback, stale/expired/tampered tickets, changed holds/pass eligibility, one-time release, VIP driver exemption and visitor items. They check committed records and shared web/owner API reads. They do not execute real UI navigation or camera scans.

The real transport test starts two separate Node clients, executes actual `live.js`, commits a vehicle through an authenticated API, checks one database row, then waits for each five-second poll to read and publish the new record. Admin and guard clients both reconcile automatically. Its renderer is simulated; this proves the live API/transport connection, not full frontend rendering or mobile-to-mobile behavior.

The debug APK was rebuilt with `--dart-define=API_BASE_URL=http://10.0.2.2:8001/web-app-admin/api`. No install or phone runtime was performed. Default source configuration still points to the existing cloud host, whose backend was not deployed by this task. Select the updated local server when testing local clients; cloud and local databases are not automatically the same system.

### Major feature inventory — executed backend layer

'''
summary+='| Feature/workflow group | Actual API assertions | Result | Evidence |\n|---|---:|---|---|\n'
for group,count,log,start in groups:
    summary+=f'| {group} | {count} | PASS at API/database layer | [{log}:{start}]({evidence(log,start)}) |\n'
summary+='\nThis inventory includes accounts, lockout, signatures/legacy QR, vehicles/classes/drivers, gates, violations/overnight, visitors/items/photos, owner scope/notices, historical sync, cashier/online payment contracts, renewals, approvals/audit, settings/capacity/shifts/evidence and unified cases. Local SMTP/provider simulations do not prove live external delivery.\n'

matrix='''The complete assertion-level CSV records test identifiers, application, feature/scenario, expected/actual behavior, type, result, evidence line and related issue where applicable:

'''+f'[{CSV.name}]({CSV.as_posix()}) — {len(rows)} rows. These are coverage rows, not independent test-case counts. The single failed Flutter test has separate rows for its stale-content and layout symptoms.\n\n'
matrix+='| ID / application | Scenario | Type | Expected → actual | Result | Issue |\n|---|---|---|---|---|---|\n'
for r in rows:
    if r['id'].startswith(('FLT-ALL','FLT-CARD','FLT-LAYOUT','E2E','DB-','NET-','QUEUE-','SESSION-','MAIL-','REV-COUNTERS','CARD-','KPI-')) or r['id'] in ['PHP','JS','ANALYZE','BUILD','LEGACY']:
        matrix+=f"| {r['id']} / {r['application']} | {r['scenario']} | {r['testType']} | {r['expected']} → {r['actual']} | {r['result']} | {r['issue']} |\n"
matrix+='''
Core recovery coverage: executed Node units pass network failure/backoff, same-revision retry after subscriber failure, single-flight, hidden-tab wake, online wake, logout/in-flight discard and rapid relogin. Flutter units/widgets pass strict failed reads, empty log response, 401 without fallback, offline queue refusal/retry and uncertain movement payload retention. These are controlled simulations, not physical outage tests.

### Reproduction

Run from the repository root: `python -X utf8 tests/system_validation.py`. It uses disposable backend sandboxes and emits `artifacts/baseline-results.json`; it does not run Flutter or claim full-system PASS. Run Flutter separately from `mobile-app`: `flutter test --no-pub --reporter expanded`, `flutter analyze --no-pub`, and `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8001/web-app-admin/api`. The Flutter test/analyzer commands currently fail for the documented baseline findings. `python tests/write_validation_report.py` rebuilds this evidence table from completed logs; it is not a test executor.
'''

def replace_section(text,heading,next_heading,body):
    a=text.index(heading)+len(heading)
    b=text.index(next_heading,a)
    return text[:a]+'\n\n'+body+'\n\n'+text[b:]

text=REPORT.read_text(encoding='utf-8')
text=replace_section(text,'## E. End-to-end simulation results','## F. Real-time synchronization results',summary)
text=replace_section(text,'## H. Test coverage matrix','## I. Problems discovered during testing',matrix)
failure='''Initial Flutter runs exposed fixture assumptions about anonymous queue processing, missing revision endpoints in HTTP mocks and malformed visitor-create records. Test fixtures were updated before the freeze without removing assertions; the resulting 168-test regression suite passed.

The expanded frozen baseline contains two failed checks:

1. **Open visitor widget test (RT003/RT006, High):** the repository publishes a changed/blocked pass, but the already open confirmation still uses its constructor snapshot. Updated visitor text has zero matching widgets. Add a pass-ID subscription and update the full-screen QR/eligibility display; verify changed, used, blocked and unavailable passes in a mounted screen and on real phones. The same test reports **N014 (Medium)**: the validity/QR caption Row overflows 110 pixels. Wrap/flex its text and rerun a width/text-scale matrix. One failing test case exposes two symptoms.
2. **Analyzer (N013, Low):** one duplicate-import warning and 19 missing-brace diagnostics; exit code 1. Remove the duplicate import and wrap conditional bodies in the approved follow-up, then rerun analyzer, tests and build. The APK compiles, so these diagnostics are not reported as compiler errors.

No application changes were made to suppress either result after the freeze. Additional confirmed source-level workflow/data gaps are in section B/C; unexecuted scenarios remain NOT TESTED or BLOCKED. There is no blanket whole-system PASS.
'''
text=replace_section(text,'## I. Problems discovered during testing','## J. Prioritized implementation roadmap',failure)
manifest=json.loads((OUT/'phase1-source-manifest.json').read_text())
changed=[name for name,digest in manifest.items() if not (ROOT/name).exists() or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
assert not changed,changed
text+='\n### Final freeze verification\n\nAll 238 recorded application-source hashes still match after testing/build/report generation. Backend deployment mirrors match. No push, commit, deployment or live-database destructive test was performed in this task.\n' if '### Final freeze verification' not in text else ''
REPORT.write_text(text,encoding='utf-8')
print('Report updated; coverage rows:',len(rows),'; unchanged source files:',len(manifest))
