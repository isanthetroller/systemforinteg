"""Real Dart mobile transport -> disposable PHP/SQLite -> live Chrome web audit."""
import os
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from playwright.sync_api import sync_playwright
from movement_integration import ROOT, Sandbox, call


def check(value, label):
    assert value, label
    print('PASS:', label, flush=True)


def await_phase(directory, name, process):
    marker = directory / f'{name}.ready'
    deadline = time.monotonic() + 45
    while not marker.exists() and time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(f'mobile process exited before {name}: {process.returncode}')
        time.sleep(.1)
    check(marker.exists(), f'mobile phase {name} reached')


def release(directory, name):
    (directory / f'{name}.release').write_text('continue', encoding='utf-8')


def main():
    flutter = os.environ.get('SP_TEST_FLUTTER') or shutil.which('flutter') or r'C:\Users\ethan\flutter\bin\flutter.bat'
    with Sandbox() as sandbox, tempfile.TemporaryDirectory(prefix='visitor-roundtrip-signals-') as signal_dir:
        target = sandbox.root / 'web-app-admin'
        for name in ('index.html', 'assets', 'css', 'js'):
            source = ROOT / 'web-app-admin' / name
            if source.is_dir():
                shutil.copytree(source, target / name, dirs_exist_ok=True)
            else:
                shutil.copy2(source, target / name)
        base = sandbox.bases[0]
        _, login = call(base, 'auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})
        admin = login['data']['token']
        password = 'Visitor-Admin-2026'
        check(call(base, 'auth.php?action=change_password', {'current_password': 'Password123!', 'new_password': password}, admin)[0] == 200, 'isolated admin prepared')
        check(call(base, 'settings.php', {'event_gate_mode': 1, 'reason': 'Roundtrip uses one guard for both directions'}, admin, method='PUT')[0] == 200, 'event operation authorized')
        user, guard_password = 'roundtripguard', 'Visitor-Guard-2026'
        check(call(base, 'users.php', {'username': user, 'full_name': 'Roundtrip Guard', 'role': 'guard', 'password': guard_password, 'gate_assigned': 'Checkpoint 1'}, admin)[0] == 201, 'web API creates mobile guard')
        plate = 'VRT' + uuid.uuid4().hex[:5].upper()
        visitor = 'Visitor Roundtrip ' + uuid.uuid4().hex[:4].upper()
        signals = Path(signal_dir)
        env = {**os.environ, 'SP_TEST_BASE': base, 'SP_TEST_USER': user,
               'SP_TEST_PASSWORD': guard_password, 'SP_TEST_PLATE': plate,
               'SP_TEST_VISITOR': visitor, 'SP_TEST_SIGNAL': signal_dir}
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel='chrome', headless=True)
            page = browser.new_page(viewport={'width': 1366, 'height': 900})
            errors = []
            page.on('pageerror', lambda err: errors.append(str(err)))
            page.goto(base.replace('/api', '/'), wait_until='domcontentloaded')
            page.locator('#loginUsername').fill('admin')
            page.locator('#loginPassword').fill(password)
            page.locator('#loginSubmitBtn').click()
            page.locator('#loginOverlay').wait_for(state='hidden', timeout=15000)
            page.evaluate("SP.switchView('visitorsView')")
            output = tempfile.TemporaryFile(mode='w+t', encoding='utf-8')
            process = subprocess.Popen([flutter, 'test', '--no-pub',
                                        'test/integration_checks/visitor_web_roundtrip_test.dart',
                                        '--reporter', 'expanded'], cwd=ROOT / 'mobile-app',
                                       env=env, stdout=output, stderr=subprocess.STDOUT)
            try:
                await_phase(signals, 'created', process)
                page.wait_for_function('(p) => document.getElementById("visitorsTableBody").textContent.includes(p)', arg=plate, timeout=15000)
                check(visitor in page.locator('#visitorsTableBody').inner_text(), 'mobile-issued visitor appears in live web visitor list')
                check('Supply box' in page.locator('#visitorsTableBody').inner_text(), 'declared visitor items appear on web')
                code, passes = call(base, 'visitors.php?all=1', token=admin, method='GET')
                check(code == 200 and sum(p['plateNumber'] == plate for p in passes['data']) == 1, 'duplicate mobile creation refused without duplicate web pass')
                page.evaluate("SP.switchView('auditView')")
                release(signals, 'created')

                await_phase(signals, 'entered', process)
                page.wait_for_function('(p) => document.getElementById("fullAuditTableBody").textContent.includes(p)', arg=plate, timeout=15000)
                check('Entry Recorded' in page.locator('#fullAuditTableBody').inner_text(), 'mobile entry appears in live web audit')
                code, logs = call(base, 'logs.php?plate=' + plate, token=admin, method='GET')
                check(code == 200 and len(logs['data']) == 1, 'unchecked items rejected without an audit log')
                page.evaluate("SP.switchView('visitorsView')")
                page.wait_for_function('(p) => { const t = document.getElementById("visitorsTableBody").textContent; return t.includes(p) && t.includes("Inside"); }', arg=plate, timeout=15000)
                check(True, 'visitor live web status changes to Inside')
                page.evaluate("SP.switchView('auditView')")
                release(signals, 'entered')

                await_phase(signals, 'exited', process)
                page.wait_for_function('(p) => { const t = document.getElementById("fullAuditTableBody").textContent; return t.includes(p) && t.includes("Exit Approved"); }', arg=plate, timeout=15000)
                code, logs = call(base, 'logs.php?plate=' + plate, token=admin, method='GET')
                check(code == 200 and len(logs['data']) == 2, 'mobile exit yields exactly two passage audits')
                page.evaluate("SP.switchView('visitorsView')")
                page.wait_for_function('(p) => { const t = document.getElementById("visitorsTableBody").textContent; return t.includes(p) && t.includes("Completed"); }', arg=plate, timeout=15000)
                check(True, 'mobile exit appears as closed visitor pass on live web')
                check(not errors, 'web browser has no uncaught errors: ' + '; '.join(errors))
                release(signals, 'exited')
                check(process.wait(timeout=30) == 0, 'real mobile Dart test finishes successfully')

                web_plate = 'WEB' + uuid.uuid4().hex[:5].upper()
                page.locator('#visitorsNewBtn').click()
                page.locator('#vpName').fill('Web Visitor')
                page.locator('#vpContact').fill('bad-contact')
                page.locator('#vpPlate').fill(web_plate)
                page.locator('#vpHost').fill('Science Office')
                page.locator('#vpPurpose').fill('Attend laboratory meeting')
                page.locator('#visitorSubmitBtn').click()
                page.locator('#visitorFormError').wait_for(state='visible', timeout=10000)
                check(page.locator('#vpPlate').input_value() == web_plate and page.locator('#visitorModal').is_visible(), 'invalid visitor contact keeps web form editable')
                page.locator('#vpContact').fill('09123456789')
                page.locator('#visitorSubmitBtn').click()
                page.locator('#visitorCardModal').wait_for(state='visible', timeout=10000)
                check(web_plate in page.locator('#visitorCard').inner_text(), 'web visitor form creates pass and displays card')
                page.locator('#visitorCardCloseBtn').click()
                page.wait_for_function('(p) => document.getElementById("visitorsTableBody").textContent.includes(p)', arg=web_plate, timeout=10000)
                page.locator('#visitorsNewBtn').click()
                page.locator('#vpName').fill('Duplicate Visitor')
                page.locator('#vpContact').fill('09123456789')
                page.locator('#vpPlate').fill(web_plate)
                page.locator('#vpHost').fill('Science Office')
                page.locator('#vpPurpose').fill('Duplicate attempt')
                page.locator('#visitorSubmitBtn').click()
                page.locator('#visitorFormError').wait_for(state='visible', timeout=10000)
                check('already exists' in page.locator('#visitorFormError').inner_text().lower(), 'duplicate web visitor pass shows server refusal')
                code, passes = call(base, 'visitors.php?all=1', token=admin, method='GET')
                check(code == 200 and sum(p['plateNumber'] == web_plate for p in passes['data']) == 1, 'duplicate web visitor attempt leaves one pass')
                check(not errors, 'web visitor form has no uncaught errors: ' + '; '.join(errors))
            finally:
                for phase in ('created', 'entered', 'exited'):
                    release(signals, phase)
                if process.poll() is None:
                    process.terminate()
                output.seek(0)
                print(output.read()[-8000:], flush=True)
                output.close()
                browser.close()


if __name__ == '__main__':
    main()
