"""Real Chrome, three signed-in sessions and isolated PHP/SQLite gate workflows."""
import shutil
from pathlib import Path
from playwright.sync_api import sync_playwright
from movement_integration import ROOT, Sandbox, call


def main():
    checks, errors = [], []
    def check(label, ok):
        assert ok, label
        checks.append(label)
        print('PASS:', label, flush=True)
    with Sandbox() as s:
        base = s.bases[0]
        for name in ('index.html', 'assets', 'css', 'js'):
            source, dest = ROOT / 'web-app-admin' / name, s.root / 'web-app-admin' / name
            if source.is_dir(): shutil.copytree(source, dest, dirs_exist_ok=True)
            else: shutil.copy2(source, dest)
        _, r = call(base, 'auth.php?action=login', {'username':'admin','password':'Password123!'})
        token = r['data']['token']
        password = 'Browser-Product-2026'
        assert call(base, 'auth.php?action=change_password', {'current_password':'Password123!','new_password':password}, token)[0] == 200
        for n in (1, 2):
            assert call(base, 'users.php', {'username':f'operator{n}','full_name':f'Operator {n}','role':'guard','password':password,'gate_assigned':f'Gate {n}'}, token)[0] == 201
        c, r = call(base, 'vehicles.php', {'plateNumber':'BROWSER100','vehicleType':'Bicycle','category':'non-plated','ownerName':'Browser Owner','ownerRole':'Student','ownerIdNumber':'BROWSEROWNER','stickerYear':'2026'}, token)
        assert c == 201, r
        vehicle = r['data']
        with sync_playwright() as pw:
            browser = pw.chromium.launch(channel='chrome', headless=True)
            def login(user):
                page = browser.new_page(viewport={'width':1366,'height':900})
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.goto(base.replace('/api','/'), wait_until='domcontentloaded')
                page.locator('#loginUsername').fill(user)
                page.locator('#loginPassword').fill(password)
                page.locator('#loginSubmitBtn').click()
                page.locator('#loginOverlay').wait_for(state='hidden', timeout=15000)
                return page
            admin, gate1, gate2 = login('admin'), login('operator1'), login('operator2')
            for page in (gate1, gate2):
                page.evaluate("SP.switchView('gateView')")
                page.wait_for_function("document.querySelector('#gateModeHint').textContent.includes('Normal operation')")
            check('normal Gate 1 exposes entry only', gate1.locator('[data-mode=Ingress]').is_enabled() and gate1.locator('[data-mode=Egress]').is_disabled())
            check('normal Gate 2 exposes exit only', gate2.locator('[data-mode=Egress]').is_enabled() and gate2.locator('[data-mode=Ingress]').is_disabled())
            def settings(mode):
                admin.evaluate("SP.switchView('centerView')")
                admin.locator('#centerTabSettings').click()
                admin.locator('#set_event_gate_mode').select_option(str(mode))
                admin.locator('#gateModeReason').fill('Browser verified campus event authorization')
                admin.locator('#set_exit_release_minutes').fill('7')
                with admin.expect_response(lambda r: 'settings.php' in r.url and r.request.method == 'PUT') as saved:
                    admin.locator('#settingsForm button[type=submit]').click()
                check(f'admin saves mode {mode}', saved.value.status == 200)
            settings(1)
            for page in (gate1, gate2):
                page.wait_for_function("document.querySelector('#gateModeHint').textContent.includes('Event operation')", timeout=20000)
                check('live event permissions enable both directions', page.locator('[data-mode=Ingress]').is_enabled() and page.locator('[data-mode=Egress]').is_enabled())
            def passage(page, direction):
                page.locator(f'[data-mode={direction}]').click()
                page.locator('#gateManualInput').fill('BROWSER100')
                page.locator('#gateVerifyBtn').click()
                page.locator('[data-act=approve]').wait_for(state='visible')
                with page.expect_response(lambda r: 'logs.php' in r.url and r.request.method == 'POST') as saved:
                    page.locator('[data-act=approve]').click()
                check(f'browser records {direction}', saved.value.status == 201)
                page.wait_for_function("!document.querySelector('[data-act=approve]')")
            passage(gate2, 'Ingress')
            passage(gate1, 'Egress')
            admin.evaluate("SP.switchView('fullAuditView')")
            admin.wait_for_function("document.getElementById('fullAuditTableBody').textContent.includes('BROWSER100')", timeout=15000)
            logs = call(base, 'logs.php?plate=BROWSER100', token=token, method='GET')[1]['data']
            check('physical checkpoint and operator preserved in both audits', len(logs)==2 and {x['gatePoint'] for x in logs} == {'Gate 1','Gate 2'} and all('Operator' in x['guardName'] for x in logs))
            settings(0)
            gate2.wait_for_function("document.querySelector('[data-mode=Ingress]').disabled", timeout=20000)
            check('open guard page returns to normal exit-only', gate2.locator('[data-mode=Egress]').is_enabled())
            gate1.wait_for_function("document.querySelector('#gateModeHint').textContent.includes('Normal operation')", timeout=20000)
            passage(gate1, 'Ingress')
            c, r = call(base, 'incidents.php', {'plateNumber':'BROWSER100','reason':'Security-only browser hold'}, token)
            assert c == 201, r
            key = 'I' + str(r['data']['id'])
            admin.evaluate('(key) => SPCases.open(key)', key)
            admin.locator('[data-act=release]').wait_for(state='visible', timeout=10000)
            check('security-only held vehicle has release control', True)
            admin.locator('[data-act=release]').click()
            admin.wait_for_function("document.body.textContent.includes('within 7 minutes')")
            check('release dialog uses configured seven minutes', True)
            admin.locator('.swal2-textarea').fill('Authorized browser emergency departure')
            admin.screenshot(path=str(ROOT/'artifacts/product-release-browser.png'), animations='disabled')
            with admin.expect_response(lambda r: 'releases.php' in r.url and r.request.method == 'POST') as released:
                admin.locator('.swal2-confirm').click()
            check('administrator grants one exit through browser', released.value.status == 201)
            admin.locator('[data-act=close]').click()
            admin.locator('#cx_notes').fill('Investigation completed; clearance verified')
            with admin.expect_response(lambda r: 'cases.php' in r.url and r.request.method == 'POST') as closed:
                admin.locator('.swal2-confirm').click()
            closed_data = closed.value.json()
            check('browser case closure preserves on-campus presence', closed.value.status == 200 and closed_data['data']['case']['vehicle']['standing']['isInside'])
            check('browser case closure discloses actual remaining restrictions', 'No remaining registration or case restrictions' in closed_data['message'])
            check('camera preview button makes no recorded-evidence claim', 'Camera demo' in admin.evaluate("SPClip.button({logId:1,action:'Entry Recorded'})") and '5s' not in admin.evaluate("SPClip.button({logId:1})"))
            check('no uncaught errors in three real Chrome sessions', not errors)
            browser.close()
    (ROOT/'artifacts/product-browser-results.txt').write_text('\n'.join(checks), encoding='utf-8')


if __name__ == '__main__': main()
