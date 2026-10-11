"""Custody, visitor audit and gate-policy regressions in disposable real PHP fixtures."""
from contextlib import closing
from pathlib import Path
import json
import sqlite3
from movement_integration import Sandbox, call


def run():
    results = []
    def check(name, condition, detail=None):
        assert condition, (name, detail)
        results.append(name)
        print('PASS', name)

    with Sandbox() as s:
        base = s.bases[0]
        _, login = call(base, 'auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})
        admin = login['data']['token']
        def req(path, body=None, token=admin, method='POST'):
            return call(base, path, body, token, method)
        check('admin changes temporary password', req('auth.php?action=change_password', {
            'current_password': 'Password123!', 'new_password': 'Product-Audit-2026'})[0] == 200)
        guards = []
        for n in (1, 2):
            c, response = req('users.php', {'username': f'operator{n}', 'full_name': f'Operator {n}', 'role': 'guard',
                'password': 'Product-Guard-2026', 'gate_assigned': f'Gate {n}'})
            check(f'create Gate {n} guard independent of username', c == 201, response)
            _, response = call(base, 'auth.php?action=login', {'username': f'operator{n}', 'password': 'Product-Guard-2026'})
            guards.append(response['data']['token'])
        def create_vehicle(plate):
            c, r = req('vehicles.php', {'plateNumber': plate, 'vehicleType': 'Bicycle', 'category': 'non-plated',
                'ownerName': 'Product Owner', 'ownerRole': 'Student', 'ownerIdNumber': 'OWNER-'+plate, 'stickerYear': '2026'})
            assert c == 201, r
            return r['data']
        def prepare(v, token):
            c, r = req('movements.php', {'action': 'prepare', 'qr_code': v['qrPayload']}, token)
            assert c == 200, r
            return r['data']
        def confirm(p, v, token):
            return req('movements.php', {'action': 'confirm', 'ticket': p['movement']['ticket'],
                'driver_id': v['authorizedDrivers'][0]['id']}, token)
        def mode(value):
            c, r = req('settings.php', {'event_gate_mode': value, 'reason': 'Scheduled campus event operation'}, method='PUT')
            assert c == 200, r
        v = create_vehicle('PRD100')
        check('normal Gate 2 refuses entry', prepare(v, guards[1])['result'] == 'GATE_DIRECTION_DENIED')
        p = prepare(v, guards[0]); check('normal Gate 1 permits entry', p['accepted'])
        check('entry recorded', confirm(p, v, guards[0])[0] == 201)
        check('normal Gate 1 refuses exit', prepare(v, guards[0])['result'] == 'GATE_DIRECTION_DENIED')
        check('guard cannot authorize event mode', req('settings.php', {'event_gate_mode': 1, 'reason': 'No authority'}, guards[0], 'PUT')[0] == 403)
        check('mode change requires reason', req('settings.php', {'event_gate_mode': 1}, method='PUT')[0] == 400)
        mode(1)
        event_exit = prepare(v, guards[0]); check('event Gate 1 permits exit', event_exit['accepted'])
        mode(0)
        check('mode reversal invalidates uncommitted exit', confirm(event_exit, v, guards[0])[0] == 403)
        p = prepare(v, guards[1]); check('normal Gate 2 exit', confirm(p, v, guards[1])[0] == 201)
        mode(1)
        check('saved confirmation retry remains idempotent after mode change', confirm(p, v, guards[1])[1]['data']['duplicate'])
        for entry, leave in ((1, 1), (0, 0), (1, 0), (0, 1)):
            p = prepare(v, guards[entry]); check(f'event entry at Gate {entry+1}', confirm(p, v, guards[entry])[0] == 201)
            p = prepare(v, guards[leave]); check(f'event exit at Gate {leave+1}', confirm(p, v, guards[leave])[0] == 201)
        mode(0)
        p = prepare(v, guards[0]); assert confirm(p, v, guards[0])[0] == 201
        c, incident = req('incidents.php', {'plateNumber': 'PRD100', 'reason': 'Independent investigation', 'notes': 'Separate case'})
        assert c == 201, incident
        c, violation = req('violations.php', {'vehicle_id': v['id'], 'type': 'Other', 'notes': 'Fixture violation'})
        assert c == 201, violation
        c, closed = req('cases.php', {'key': 'V'+str(violation['data']['violation']['id']), 'action': 'close',
            'outcome': 'Clearance signed', 'notes': 'Close only this violation'})
        assert c == 200, closed
        with closing(sqlite3.connect(s.db)) as db:
            state = db.execute('SELECT status FROM vehicles WHERE id=?', (v['id'],)).fetchone()[0]
        check('case closure preserves physical presence', state == 'Inside Campus', state)
        check('remaining hold is disclosed', 'Unresolved security hold' in closed['message'], closed)
        check('security-only hold offers one-time release', closed['data']['case']['vehicle']['standing']['releaseEligible'])
        check('remaining hold prevents normal exit', not prepare(v, guards[1])['accepted'])
        with closing(sqlite3.connect(s.db)) as db, db:
            db.execute("UPDATE vehicles SET status='Blocked / Alert' WHERE id=?", (v['id'],))
        c, closed = req('cases.php', {'key': 'I'+str(incident['data']['id']), 'action': 'close',
            'outcome': 'Clearance signed', 'notes': 'Investigation finished'})
        check('legacy blocked status restores recorded inside presence', closed['data']['case']['vehicle']['standing']['isInside'])
        check('last case closure restores eligible exit', prepare(v, guards[1])['accepted'])

        def visitor(plate):
            c, r = req('visitors.php', {'visitor_name': 'Audit Visitor', 'contact_number': '09123456789',
                'plate': plate, 'purpose': 'Equipment delivery', 'person_to_visit': 'Security',
                'items': [{'name': 'Equipment', 'quantity': 2}]}, guards[0])
            assert c == 201, r
            return r['data']
        p = visitor('PRDV100')
        payload = {'passId': p['passCode'], 'plateNumber': p['plateNumber'], 'items_verified': True}
        check('visitor cannot checkout before entry', req('visitors.php?action=exit', payload, guards[1])[0] == 409)
        preview = prepare(p, guards[0])
        c, r = req('movements.php', {'action': 'confirm', 'ticket': preview['movement']['ticket'], 'items_verified': True}, guards[0])
        assert c == 201, r
        check('legacy checkout requires item confirmation', req('visitors.php?action=exit', {**payload, 'items_verified': False}, guards[1])[0] == 400)
        check('legacy checkout enforces normal direction', req('visitors.php?action=exit', payload, guards[0])[0] == 403)
        c, saved = req('visitors.php?action=exit', payload, guards[1]); check('legacy checkout saved', c == 200, saved)
        c, repeated = req('visitors.php?action=exit', payload, guards[1]); check('legacy checkout retry returns original', c == 200 and repeated['data']['duplicate'] and saved['data']['id'] == repeated['data']['id'], repeated)
        with closing(sqlite3.connect(s.db)) as db:
            rows = db.execute("SELECT action,gate_point,logged_by_user_id FROM gate_logs WHERE plate_number='PRDV100' ORDER BY id").fetchall()
        check('visitor entry and exit each have one named gate audit', len(rows) == 2 and rows[1][0] == 'Exit Approved' and rows[1][1] == 'Gate 2' and rows[1][2] is not None, rows)
        p = visitor('PRDV200'); preview = prepare(p, guards[0])
        assert req('movements.php', {'action': 'confirm', 'ticket': preview['movement']['ticket'], 'items_verified': True}, guards[0])[0] == 201
        assert req('visitors.php', {'id': p['id'], 'action': 'revoke', 'notes': 'Investigation required'}, method='PUT')[0] == 200
        check('legacy checkout cannot bypass revoked visitor hold', req('visitors.php?action=exit', {'passId': p['passCode'], 'items_verified': True}, guards[1])[0] == 403)
        check('scanner key cannot use named online checkout', call(base, 'visitors.php?action=exit', {'passId': p['passCode']}, extra_headers={'X-Api-Key': s.scanner_key})[0] == 401)
        with closing(sqlite3.connect(s.db)) as db:
            mode_audits = db.execute("SELECT COUNT(*) FROM audit_log WHERE action='gate.mode_change' AND reason IS NOT NULL").fetchone()[0]
        check('mode authorizations are audited', mode_audits >= 4)
        # Historical departures are audit events, not retroactive permission grants.
        import datetime
        now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
        event = {'client_ref': 'historical-visitor-exit-001', 'type': 'visitor_exit',
            'occurred_at': now.isoformat(), 'payload': {'passId': p['passCode'], 'plateNumber': p['plateNumber'], 'gatePoint': 'Gate 2'}}
        c, synced = req('sync.php', {'events': [event]}, guards[1])
        result = synced['data']['results'][0]
        check('historical held checkout saved with review flags', c == 200 and result['status'] == 'accepted' and 'SECURITY_HOLD_AT_SYNC' in result['flags'] and 'ITEMS_NOT_VERIFIED' in result['flags'], synced)
        c, again = req('sync.php', {'events': [{**event, 'client_ref':'historical-visitor-exit-002'}]}, guards[1])
        check('historical visitor checkout repeated under another reference deduplicates', again['data']['results'][0]['status'] == 'duplicate', again)
        with closing(sqlite3.connect(s.db)) as db, db:
            count = db.execute("SELECT COUNT(*) FROM gate_logs WHERE plate_number='PRDV200' AND action='Exit Approved'").fetchone()[0]
            check('historical checkout has one exit audit', count == 1)
            stamp = now.strftime('%Y-%m-%d 12:00:00')
            yesterday = (now-datetime.timedelta(days=1)).strftime('%Y-%m-%d 12:00:00')
            for action, timestamp, amount in [('Entry Recorded',stamp,123),('Entry Denied',stamp,17),('Exit Denied',stamp,5),('Entry Recorded',yesterday,19),('Entry Denied',yesterday,11)]:
                db.executemany("INSERT INTO gate_logs (driver_name,plate_number,action,gate_type,gate_point,status,guard_name,logged_at) VALUES ('Fixture','COUNTTEST',?,'Ingress','Gate 1','Outside','Fixture',?)", [(action,timestamp)]*amount)
            expected = db.execute("SELECT COUNT(*) FROM gate_logs WHERE action='Entry Recorded' AND substr(logged_at,1,10)=?",(now.strftime('%Y-%m-%d'),)).fetchone()[0]
            denied = db.execute("SELECT COUNT(*) FROM gate_logs WHERE action IN ('Entry Denied','Exit Denied') AND substr(logged_at,1,10)=?",(now.strftime('%Y-%m-%d'),)).fetchone()[0]
        c, stats = req('stats.php', method='GET')
        check('daily entries count exceeds recent-log window and excludes yesterday', c == 200 and stats['data']['todayEntries'] == expected and expected > 100, stats)
        check('daily denials include both directions without previous-day records', stats['data']['todayDenied'] == denied, stats)

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/product-integrity-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
