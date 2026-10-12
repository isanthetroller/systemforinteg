"""Guard shift tracking in the admin web: the timeline of shifts, what was done during each, and gate coverage."""
from contextlib import closing
from pathlib import Path
import datetime
import json
import sqlite3
import time
from movement_integration import Sandbox, call


def run():
    results = []

    def check(name, condition, detail=None):
        assert condition, (name, detail)
        results.append(name)
        print('PASS', name)

    with Sandbox() as s:
        base = s.bases[0]

        def req(path, body=None, token=None, method='POST'):
            return call(base, path, body, token, method)

        admin = req('auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})[1]['data']['token']
        req('auth.php?action=change_password', {'current_password': 'Password123!', 'new_password': 'Shifts-Admin-2026'}, admin)

        def guard(name, label):
            c, r = req('users.php', {'username': name, 'full_name': label, 'role': 'guard', 'password': 'Shifts-Guard-2026', 'gate_assigned': 'Gate 1'}, admin)
            assert c in (200, 201), r
            return req('auth.php?action=login', {'username': name, 'password': 'Shifts-Guard-2026'})[1]['data']['token']

        g1 = guard('guard.one', 'Gina One')
        g2 = guard('guard.two', 'Gabe Two')

        # admin-only
        check('the timeline is admin only -> 403', req('shifts.php?scope=timeline', token=g1, method='GET')[0] == 403)
        check('a shift detail is admin only -> 403', req('shifts.php?scope=shift&id=1', token=g1, method='GET')[0] == 403)

        # Gina works a shift: starts at Gate 1, scans an entry, issues a violation, ends with a note
        c, r = req('shifts.php', {'action': 'start', 'gate': 'Gate 1 (Main Ingress)'}, g1)
        check('guard goes on duty', c == 201, r)
        shift1 = r['data']['shift']['id']
        c, veh = req('vehicles.php', {'plateNumber': 'SHF 1001', 'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': 'Shift Owner',
                                      'ownerRole': 'Student', 'ownerIdNumber': 'SHF-1001', 'stickerYear': '2026'}, admin)
        veh = veh['data']
        c, lg = req('logs.php', {'plate': 'SHF 1001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driverName': 'Shift Owner'}, g1)
        check('guard records an entry', c == 201, lg)
        c, v = req('violations.php', {'vehicle_id': veh['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'x'}, g1)
        check('guard issues a violation', c == 201, v)

        # Gabe is on duty now at Gate 2 and has an old shift that was closed automatically
        c, r = req('shifts.php', {'action': 'start', 'gate': 'Gate 2 (Main Egress)'}, g2)
        check('a second guard goes on duty', c == 201, r)
        gabe_shift = r['data']['shift']['id']

        today = datetime.date.today().isoformat()
        c, tl = req(f'shifts.php?scope=timeline&from={today}&to={today}', token=admin, method='GET')
        check('the timeline answers 200', c == 200, tl)
        d = tl['data']
        mine = [x for x in d['shifts'] if x['id'] == shift1][0]
        check('Gina\'s shift counts her entry and violation', mine['counts']['entry'] == 1 and mine['counts']['violation'] == 1 and mine['actions'] >= 2, mine)
        check('an open shift has no end and is marked open', mine['endedAt'] is None and mine['endKind'] == 'open', mine)
        check('summary: two guards on duty, two shifts', d['summary']['onDuty'] == 2 and d['summary']['shifts'] == 2, d['summary'])
        cov = {x['gate']: x['guards'] for x in d['coverage']}
        check('gate coverage lists who is where', [g['guard'] for g in cov['Gate 1 (Main Ingress)']] == ['Gina One'] and [g['guard'] for g in cov['Gate 2 (Main Egress)']] == ['Gabe Two'], cov)
        check('a gate nobody covers is listed empty', cov['Patrol / Other'] == [], cov)

        # Gina ends her shift with a note
        c, r = req('shifts.php', {'action': 'end', 'notes': 'Fire lane keeps filling up.'}, g1)
        check('guard ends the shift', c == 200, r)
        c, tl = req(f'shifts.php?scope=timeline&from={today}&to={today}', token=admin, method='GET')
        mine = [x for x in tl['data']['shifts'] if x['id'] == shift1][0]
        check('an ended shift reports manual end, duration and note', mine['endKind'] == 'manual' and mine['endedAt'] and mine['handoverNotes'] == 'Fire lane keeps filling up.', mine)

        # Detail: what she did, in order
        c, det = req(f'shifts.php?scope=shift&id={shift1}', token=admin, method='GET')
        types = [a['type'] for a in det['data']['activity']]
        check('the shift detail lists entry then violation in time order', c == 200 and 'entry' in types and 'violation' in types, det)
        check('...and carries the end kind', det['data']['shift']['endKind'] == 'manual', det['data']['shift'])
        check('an unknown shift -> 404', req('shifts.php?scope=shift&id=99999', token=admin, method='GET')[0] == 404)

        # Activity outside any shift is flagged; auto-closed and long shifts are marked
        req('vehicles.php', {'plateNumber': 'SHF 2002', 'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': 'Other Owner',
                             'ownerRole': 'Student', 'ownerIdNumber': 'SHF-2002', 'stickerYear': '2026'}, admin)
        time.sleep(1.2)   # timestamps have one-second resolution
        c, lg = req('logs.php', {'plate': 'SHF 2002', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driverName': 'Other Owner'}, g1)   # Gina is off duty now
        check('Gina still scans after ending her shift (it is allowed, just flagged)', c == 201, lg)
        old = (datetime.datetime.now() - datetime.timedelta(days=1, hours=1)).strftime('%Y-%m-%d %H:%M:%S')
        old_end = (datetime.datetime.now() - datetime.timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S')
        with closing(sqlite3.connect(s.db)) as db, db:
            gabe_id = db.execute('SELECT user_id FROM guard_shifts WHERE id = ?', (gabe_shift,)).fetchone()[0]
            db.execute("INSERT INTO guard_shifts (user_id, guard_label, gate, started_at, ended_at, handover_notes) VALUES (?, 'Gabe Two', 'Patrol / Other', ?, ?, '(shift closed automatically after 16 hours)')",
                       (gabe_id, old, old_end))
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
        c, tl = req(f'shifts.php?scope=timeline&from={yesterday}&to={today}', token=admin, method='GET')
        d = tl['data']
        check('an automatically closed shift is marked', any(x['endKind'] == 'auto' for x in d['shifts']) and d['summary']['autoClosed'] == 1, d['summary'])
        check('a shift over 12 hours is flagged long', d['summary']['longShifts'] == 1 and any(x['long'] for x in d['shifts']), d['summary'])
        gina = [g for g in d['guards'] if g['guard'].startswith('Gina')][0]
        check('Gina\'s exit after she ended her shift is counted as off-shift', gina['offShiftActions'] >= 1 and d['summary']['offShiftActions'] >= 1, gina)
        check('every guard account is listed, even one with no shifts', {g['guard'] for g in d['guards']} >= {'Gina One', 'Gabe Two'}, d['guards'])
        check('a period over 62 days is refused -> 400', req('shifts.php?scope=timeline&from=2026-01-01&to=2026-12-31', token=admin, method='GET')[0] == 400)

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/guard-shifts-timeline-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
