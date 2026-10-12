"""Lane-aware anti-passback: the phone says IN or OUT, the server refuses a lane that contradicts the vehicle's state.

Regression for: rescanning a vehicle at the entrance turned the scan into an exit at 'Gate 2'.
"""
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
            'current_password': 'Password123!', 'new_password': 'Lane-Admin-2026'})[0] == 200)

        def guard(username, gate):
            c, r = req('users.php', {'username': username, 'full_name': username, 'role': 'guard',
                                     'password': 'Lane-Guard-2026', 'gate_assigned': gate})
            assert c == 201, r
            return call(base, 'auth.php?action=login', {'username': username, 'password': 'Lane-Guard-2026'})[1]['data']['token']
        g1, g2, flex = guard('lane1', 'Gate 1 (Main Ingress)'), guard('lane2', 'Gate 2 (Main Egress)'), guard('laneall', 'All Gates')

        def vehicle(plate):
            c, r = req('vehicles.php', {'plateNumber': plate, 'vehicleType': 'Bicycle', 'category': 'non-plated',
                'ownerName': 'Lane Owner', 'ownerRole': 'Student', 'ownerIdNumber': 'OWNER-' + plate, 'stickerYear': '2026'})
            assert c == 201, r
            return r['data']
        def prepare(v, token, lane=None):
            body = {'action': 'prepare', 'qr_code': v['qrPayload']}
            if lane: body['direction'] = lane
            c, r = req('movements.php', body, token)
            assert c == 200, r
            return r['data']
        def confirm(p, v, token):
            return req('movements.php', {'action': 'confirm', 'ticket': p['movement']['ticket'],
                                         'driver_id': v['authorizedDrivers'][0]['id']}, token)

        # --- Gate 1 account, entry lane -------------------------------------------------------------------------
        v = vehicle('LNE100')
        p = prepare(v, g1, 'IN'); check('entry lane: outside vehicle is cleared', p['accepted'] and p['movement']['suggestedAction'] == 'IN', p)
        check('entry lane: entry saved', confirm(p, v, g1)[0] == 201)
        p = prepare(v, g1, 'IN')
        check('rescan on the entry lane is ALREADY_INSIDE, not an exit', p['result'] == 'ALREADY_INSIDE' and not p['accepted'] and p['movement'] is None, p)
        check('passback message tells the guard what to do', 'Report' in p['reason'], p)
        check('passback keeps the entry gate (never Gate 2)', p['gatePolicy']['checkpoint'] == 'Gate 1', p['gatePolicy'])
        check('rescan changed nothing: still inside', prepare(v, g1, 'IN')['currentlyInside'] is True)
        check('old phone without a lane keeps the state-derived toggle', prepare(v, g1)['result'] in ('GATE_DIRECTION_DENIED', 'VALID'))

        # --- Gate 2 account, exit lane --------------------------------------------------------------------------
        p = prepare(v, g2, 'OUT'); check('exit lane: inside vehicle is cleared', p['accepted'] and p['movement']['suggestedAction'] == 'OUT', p)
        check('exit lane: exit saved', confirm(p, v, g2)[0] == 201)
        p = prepare(v, g2, 'OUT')
        check('rescan on the exit lane is NOT_ON_CAMPUS, not an entry', p['result'] == 'NOT_ON_CAMPUS' and not p['accepted'] and p['movement'] is None, p)

        # --- All Gates account (lane decides the gate) ----------------------------------------------------------
        v2 = vehicle('LNE200')
        p = prepare(v2, flex, 'IN'); check('All Gates guard: entry cleared at Gate 1', p['accepted'] and p['movement']['checkpoint'] == 'Gate 1', p)
        check('All Gates guard: entry saved', confirm(p, v2, flex)[0] == 201)
        p = prepare(v2, flex, 'IN')
        check('All Gates guard: rescan stays on Gate 1 as ALREADY_INSIDE (the reported bug)',
              p['result'] == 'ALREADY_INSIDE' and p['gatePolicy']['checkpoint'] == 'Gate 1', p)
        p = prepare(v2, flex, 'OUT'); check('All Gates guard: exit lane cleared at Gate 2', p['accepted'] and p['movement']['checkpoint'] == 'Gate 2', p)
        check('All Gates guard: exit saved', confirm(p, v2, flex)[0] == 201)

        # --- Event mode: either lane at either gate, passback still applies ------------------------------------
        c, r = req('settings.php', {'event_gate_mode': 1, 'reason': 'Lane test event mode'}, method='PUT'); assert c == 200, r
        v3 = vehicle('LNE300')
        p = prepare(v3, g1, 'IN'); check('event mode: Gate 1 guard enters', p['accepted'], p)
        check('event mode: entry saved', confirm(p, v3, g1)[0] == 201)
        check('event mode: second entry on the entry lane is still refused', prepare(v3, g1, 'IN')['result'] == 'ALREADY_INSIDE')
        p = prepare(v3, g1, 'OUT'); check('event mode: Gate 1 guard may use the exit lane', p['accepted'] and p['movement']['suggestedAction'] == 'OUT', p)
        check('event mode: exit saved', confirm(p, v3, g1)[0] == 201)
        check('event mode: exit lane on an outside vehicle is refused', prepare(v3, g1, 'OUT')['result'] == 'NOT_ON_CAMPUS')
        c, r = req('settings.php', {'event_gate_mode': 0, 'reason': 'Lane test event mode off'}, method='PUT'); assert c == 200, r

        # --- Security results outrank passback -----------------------------------------------------------------
        v4 = vehicle('LNE400')
        p = prepare(v4, g1, 'IN'); assert confirm(p, v4, g1)[0] == 201
        c, viol = req('violations.php', {'vehicle_id': v4['id'], 'type': 'Other', 'notes': 'Lane test hold'}); assert c == 201, viol
        p = prepare(v4, g1, 'IN')
        check('held vehicle on the wrong lane shows the hold, not passback', p['result'] == 'BANNED' and not p['accepted'], p['result'])

        # --- Report a record discrepancy -----------------------------------------------------------------------
        c, r = req('movements.php', {'action': 'report_discrepancy', 'plate': 'LNE100', 'direction': 'IN', 'recorded': 'INSIDE', 'note': 'Left by the side gate'}, g1)
        check('guard can report a record discrepancy', c == 201 and r['data']['reported'], r)
        # Report opens a real case (same as Block) without telling the owner their vehicle was blocked
        with closing(sqlite3.connect(s.db)) as db:
            notices_before = db.execute('SELECT COUNT(*) FROM owner_notices').fetchone()[0]
        c, r = req('incidents.php', {'plateNumber': 'LNE200', 'driverName': 'Lane Owner', 'reason': 'Record check: Vehicle already left',
                                     'gatePoint': 'Gate 1 (Main Ingress)', 'notes': 'Left by the side gate', 'report': True}, g1)
        check('report opens a case', c == 201 and r['data']['caseNumber'] and r['data']['status'] == 'Held', r)
        check('report message says the vehicle is held for review', 'held until an admin reviews' in r['message'], r)
        with closing(sqlite3.connect(s.db)) as db:
            notices_after = db.execute('SELECT COUNT(*) FROM owner_notices').fetchone()[0]
        check('a report does not send the owner a blocked notice', notices_after == notices_before, (notices_before, notices_after))
        c, log2 = req('audit.php?action=record.discrepancy', method='GET')
        check('the case report is in the admin activity log', c == 200 and 'LNE200' in json.dumps(log2), log2)
        c, cases = req('cases.php?status=open', method='GET')
        check('the case shows up in the admin Cases list', c == 200 and 'LNE200' in json.dumps(cases), cases)
        c, plain = req('incidents.php', {'plateNumber': 'LNE200', 'driverName': 'Lane Owner', 'reason': 'Unauthorized / Unregistered Driver',
                                         'gatePoint': 'Gate 1 (Main Ingress)'}, g1)
        with closing(sqlite3.connect(s.db)) as db:
            notices_block = db.execute('SELECT COUNT(*) FROM owner_notices').fetchone()[0]
        check('a normal block still notifies the owner', c == 201 and notices_block > notices_after, (notices_after, notices_block))
        check('report needs a plate', req('movements.php', {'action': 'report_discrepancy', 'direction': 'IN'}, g1)[0] == 400)
        c, log = req('audit.php?action=record.discrepancy', method='GET')
        check('admin sees the report in the activity log', c == 200 and any('LNE100' in json.dumps(row) for row in log['data'].get('rows', log['data'].get('entries', log['data'])) ) , log)
        check('the audit-only report endpoint never holds the vehicle', prepare(v, g1, 'IN')['result'] in ('ALREADY_INSIDE', 'NOT_ON_CAMPUS', 'VALID'))
        check('a report case holds the vehicle until an admin reviews it', prepare(v2, g1, 'IN')['result'] == 'BANNED')

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/anti-passback-lane-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
