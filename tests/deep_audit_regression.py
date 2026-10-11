"""Targeted architectural regressions against disposable real PHP backends."""
from movement_integration import Sandbox, call
import sqlite3
from contextlib import closing


def pending_password_cannot_use_scanner_endpoints():
    with Sandbox() as s:
        base = s.bases[0]
        _, result = call(base, 'auth.php?action=login',
                         {'username': 'admin', 'password': 'Password123!'})
        token = result['data']['token']
        # First-install admin is authenticated, but still owes a password change.
        assert result['data']['user']['mustChangePassword']
        status, result = call(base, 'vehicles.php?plate=AUDIT1', token=token, method='GET')
        assert status == 403 and result.get('data', {}).get('code') == 'PASSWORD_CHANGE_REQUIRED', (status, result)
        assert call(base, 'auth.php?action=change_password', {
            'current_password': 'Password123!', 'new_password': 'Audit-Admin-2026',
        }, token)[0] == 200
        status, _ = call(base, 'vehicles.php?plate=AUDIT1', token=token, method='GET')
        assert status == 404, status


def configured_mysql_failure_cannot_open_sqlite():
    with Sandbox() as s:
        config = s.root / 'web-app-admin/config/secret.php'
        secret = config.read_text(encoding='utf-8')
        secret = secret.replace("define('SP_FORCE_SQLITE', true)", "define('SP_FORCE_SQLITE', false)")
        secret = secret.replace("define('SP_DEBUG', true)", "define('SP_DEBUG', false)")
        secret += "\ndefine('SP_DB_HOST', '127.0.0.1;port=1');\ndefine('SP_DB_NAME', 'audit_unavailable');\ndefine('SP_DB_USER', 'audit');\n"
        config.write_text(secret, encoding='utf-8')
        status, result = call(s.bases[0], 'status.php', method='GET')
        assert status == 503, (status, result)
        assert 'mysql_error' not in result and 'sqlite_error' not in result


def visitor_items_failure_rolls_back_pass():
    with Sandbox() as s:
        base = s.bases[0]
        _, result = call(base, 'auth.php?action=login',
                         {'username': 'admin', 'password': 'Password123!'})
        token = result['data']['token']
        assert call(base, 'auth.php?action=change_password', {
            'current_password': 'Password123!', 'new_password': 'Audit-Admin-2026',
        }, token)[0] == 200
        with closing(sqlite3.connect(s.db)) as db, db:
            db.execute("CREATE TRIGGER audit_fail_items BEFORE INSERT ON visitor_pass_items BEGIN SELECT RAISE(ABORT, 'simulated item storage failure'); END")
        status, result = None, None
        try:
            status, result = call(base, 'visitors.php', {
                'visitor_name': 'Audit Visitor', 'contact_number': '09123456789',
                'plate': 'AUDITITEMS', 'purpose': 'Inspection', 'person_to_visit': 'Security',
                'items': [{'name': 'Equipment', 'quantity': 2}],
            }, token)
        except ValueError:
            pass  # The old endpoint also emitted a non-JSON fatal database error.
        with closing(sqlite3.connect(s.db)) as db, db:
            count = db.execute("SELECT COUNT(*) FROM visitor_passes WHERE plate_number='AUDITITEMS'").fetchone()[0]
        assert count == 0, f'Failed item save left {count} usable pass(es) without their declared items'
        assert status == 503 and result['success'] is False, (status, result)


if __name__ == '__main__':
    failures = []
    for check in (pending_password_cannot_use_scanner_endpoints, configured_mysql_failure_cannot_open_sqlite, visitor_items_failure_rolls_back_pass):
        try:
            check()
            print('PASS', check.__name__)
        except AssertionError as error:
            failures.append(check.__name__)
            print('FAIL', check.__name__, error)
    raise SystemExit(bool(failures))
