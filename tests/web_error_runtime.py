"""Browser and real PHP/SQLite regression checks in a disposable sandbox."""
import shutil
import sys
import uuid

from playwright.sync_api import sync_playwright
from movement_integration import ROOT, Sandbox, call


def expect(condition, label):
    if not condition:
        raise AssertionError(label)
    print('PASS:', label, flush=True)


with Sandbox() as sandbox:
    target = sandbox.root / 'web-app-admin'
    for name in ('index.html', 'assets', 'css', 'js'):
        source = ROOT / 'web-app-admin' / name
        if source.is_dir():
            shutil.copytree(source, target / name, dirs_exist_ok=True)
        else:
            shutil.copy2(source, target / name)
    shutil.copytree(ROOT / 'web-app-student', sandbox.root / 'web-app-student')
    base = sandbox.bases[0]
    _, login = call(base, 'auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})
    token = login['data']['token']
    password = 'WebRuntime-Admin-2026'
    code, changed = call(base, 'auth.php?action=change_password',
                         {'current_password': 'Password123!', 'new_password': password}, token)
    expect(code == 200, 'isolated admin account prepared')

    plate = 'RTE-' + uuid.uuid4().hex[:6].upper()
    owner = 'RT-' + uuid.uuid4().hex[:8].upper()
    errors = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel='chrome', headless=True)
        page = browser.new_page(viewport={'width': 1366, 'height': 900})
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(base.replace('/api', '/') , wait_until='domcontentloaded')
        page.locator('#loginUsername').fill('admin')
        page.locator('#loginPassword').fill(password)
        page.locator('#loginSubmitBtn').click()
        page.locator('#loginOverlay').wait_for(state='hidden', timeout=15000)
        expect(page.evaluate('SPAuth.isAuthenticated()'), 'staff browser sign-in')

        page.evaluate("SP.switchView('accountView')")
        page.locator('#ownerFullName').fill('Runtime Owner')
        page.locator('#department').fill('Testing')
        page.locator('#ownerIdNumber').fill(owner)
        page.locator('#plateNumber').fill(plate)
        page.locator('#makeModelColor').fill('Blue test car')
        page.locator('.driver-name').first.fill('Runtime Owner')
        page.locator('.driver-license').first.fill('RUNTIME-1')

        def fail_post(route):
            if route.request.method == 'POST':
                route.abort('failed')
            else:
                route.continue_()

        page.route('**/vehicles.php', fail_post)
        page.locator('#submitVehicleBtn').click()
        page.wait_for_function("!document.getElementById('submitVehicleBtn').disabled")
        expect(page.locator('#plateNumber').input_value() == plate,
               'failed registration preserves form values')
        expect(not page.evaluate('(p) => SP.state.vehicles.some(v => v.plateNumber === p)', plate),
               'failed registration does not create a local row')
        page.unroute('**/vehicles.php', fail_post)

        post_count = [0]
        def count_post(route):
            if route.request.method == 'POST':
                post_count[0] += 1
            route.continue_()
        page.route('**/vehicles.php', count_post)
        page.evaluate("() => { const button = document.getElementById('submitVehicleBtn'); button.click(); button.click(); }")
        page.wait_for_function('(p) => SP.state.vehicles.some(v => v.plateNumber === p)', arg=plate)
        expect(post_count[0] == 1, 'rapid repeat click sends one registration request')
        page.unroute('**/vehicles.php', count_post)
        code, vehicles = call(base, 'vehicles.php', token=token, method='GET')
        expect(code == 200 and sum(v['plateNumber'] == plate for v in vehicles['data']) == 1,
               'confirmed registration created exactly one server record')
        if page.locator('#tempPasswordModal').is_visible():
            page.locator('#tempPasswordDoneBtn').click()

        page.evaluate("SP.switchView('vehiclesView')")
        page.evaluate("p => { const row = [...document.querySelectorAll('#vehiclesTableBody tr')].find(r => r.textContent.includes(p)); row.querySelector('.edit-btn').click(); }", plate)
        page.locator('#editModalOverlay').wait_for(state='visible', timeout=10000)
        page.locator('#editMakeModel').fill('Red edited car')

        def fail_put(route):
            if route.request.method == 'PUT':
                route.abort('failed')
            else:
                route.continue_()

        page.route('**/vehicles.php', fail_put)
        page.locator('#saveEditVehicleBtn').click()
        page.wait_for_function("!document.getElementById('saveEditVehicleBtn').disabled")
        expect(page.locator('#editMakeModel').input_value() == 'Red edited car',
               'failed edit retains entered value')
        expect(not page.locator('#editModalOverlay').evaluate('(el) => el.classList.contains("hidden")'),
               'failed edit keeps modal open')
        expect(page.evaluate('(p) => SP.state.vehicles.find(v => v.plateNumber === p).makeModelColor', plate) == 'Blue test car',
               'failed edit leaves displayed vehicle unchanged')
        page.unroute('**/vehicles.php', fail_put)
        page.locator('#saveEditVehicleBtn').click()
        page.wait_for_function('(p) => SP.state.vehicles.find(v => v.plateNumber === p).makeModelColor === "Red edited car"', arg=plate)
        expect(page.locator('#editModalOverlay').evaluate('(el) => el.classList.contains("hidden")'),
               'successful edit closes modal after server response')

        page.evaluate('SPAlert.confirm = async () => true')
        page.route('**/vehicles.php', fail_put)
        page.evaluate("p => { const row = [...document.querySelectorAll('#vehiclesTableBody tr')].find(r => r.textContent.includes(p)); row.querySelector('.toggle-status-btn').click(); }", plate)
        page.wait_for_function('(p) => !SP.state.vehicles.find(v => v.plateNumber === p)._statusPending', arg=plate)
        expect(page.evaluate('(p) => SP.state.vehicles.find(v => v.plateNumber === p).registrationStatus', plate) == 'Active',
               'failed pass status update leaves original standing')
        page.unroute('**/vehicles.php', fail_put)
        page.evaluate("p => { const row = [...document.querySelectorAll('#vehiclesTableBody tr')].find(r => r.textContent.includes(p)); row.querySelector('.toggle-status-btn').click(); }", plate)
        page.wait_for_function('(p) => SP.state.vehicles.find(v => v.plateNumber === p).registrationStatus === "Suspended"', arg=plate)
        expect(True, 'pass status changes only after confirmed server write')

        page.evaluate("p => { const row = [...document.querySelectorAll('#vehiclesTableBody tr')].find(r => r.textContent.includes(p)); row.querySelector('.toggle-status-btn').click(); }", plate)
        page.wait_for_function('(p) => SP.state.vehicles.find(v => v.plateNumber === p).registrationStatus === "Active"', arg=plate)
        vehicle_id = next(v['id'] for v in vehicles['data'] if v['plateNumber'] == plate)
        paid_code, _ = call(base, 'payments.php', {'action': 'cash', 'vehicleId': vehicle_id,
                                                 'tendered': 10000}, token)
        expect(paid_code == 201, 'gate fixture pass activated by cashier')
        page.evaluate('SP.reload(true, true)')
        page.evaluate('SP.closeDrawer()')
        page.evaluate("SP.switchView('gateView')")
        page.locator('#gateManualInput').fill(plate)
        page.locator('#gateVerifyBtn').click()
        page.locator('#gateResult [data-act="deny"]').wait_for(state='visible', timeout=10000)
        page.locator('#gateResult [data-act="deny"]').click()

        def fail_incident(route):
            if route.request.method == 'POST':
                route.abort('failed')
            else:
                route.continue_()

        page.route('**/incidents.php', fail_incident)
        page.locator('#gateResult [data-act="deny-confirm"]').click()
        page.locator('#gateResult [data-decision-error]').wait_for(state='visible', timeout=10000)
        expect(page.locator('#gateResult [data-act="deny-confirm"]').is_visible(),
               'partial gate denial preserves reviewed action for retry')
        page.unroute('**/incidents.php', fail_incident)
        page.locator('#gateResult [data-act="deny-confirm"]').click()
        page.wait_for_function("document.getElementById('gateManualInput').value === ''", timeout=10000)
        _, gate_logs = call(base, 'logs.php?plate=' + plate, token=token, method='GET')
        _, gate_cases = call(base, 'incidents.php', token=token, method='GET')
        expect(sum(row['action'] == 'Entry Denied' for row in gate_logs['data']) == 1 and
               sum(row['plateNumber'] == plate for row in gate_cases['data']) == 1,
               'gate retry creates one denial log and one security case')

        decision_ref = 'runtime:' + uuid.uuid4().hex
        denial = {'plate': plate, 'action': 'Entry Denied', 'gate_type': 'Ingress',
                  'driverName': 'Runtime Owner', 'notes': 'Runtime retry check',
                  'client_ref': decision_ref + ':log'}
        first_code, first_log = call(base, 'logs.php', denial, token)
        retry_code, retry_log = call(base, 'logs.php', denial, token)
        expect(first_code == 201 and retry_code == 200 and retry_log['data'].get('duplicate'),
               'denial log retry returns original write')
        case = {'plateNumber': plate, 'reason': 'Security Officer Intervention',
                'client_ref': decision_ref + ':case'}
        first_code, first_case = call(base, 'incidents.php', case, token)
        retry_code, retry_case = call(base, 'incidents.php', case, token)
        expect(first_code == 201 and retry_code == 200 and retry_case['data'].get('duplicate'),
               'security case retry returns original write')

        browser_token = page.evaluate("sessionStorage.getItem('sp_staff_token')")
        call(base, 'auth.php?action=logout', {}, browser_token)
        page.evaluate('ApiClient.me().catch(() => {})')
        page.locator('#loginOverlay').wait_for(state='visible', timeout=10000)
        expect('session has ended' in page.locator('#loginError').inner_text().lower(),
               'revoked staff session returns to sign-in with a clear message')
        expect(not errors, 'no uncaught browser exceptions in staff flows: ' + '; '.join(errors))

        _, issued = call(base, 'students.php', {'owner_id_number': owner, 'action': 'issue'}, token)
        temp_password = issued['data']['tempPassword']
        _, student_login = call(base, 'auth.php?action=login&realm=student',
                                {'username': owner, 'password': temp_password})
        student_token = student_login['data']['token']
        student_password = 'Runtime-Owner-2026'
        status, _ = call(base, 'auth.php?action=change_password',
                         {'current_password': temp_password, 'new_password': student_password}, student_token)
        expect(status == 200, 'isolated owner account prepared')

        owner_page = browser.new_page(viewport={'width': 390, 'height': 844})
        owner_errors = []
        owner_page.on('pageerror', lambda error: owner_errors.append(str(error)))

        def fail_vehicles(route):
            if 'action=vehicles' in route.request.url:
                route.fulfill(status=503, content_type='text/html', body='<html>private error</html>')
            else:
                route.continue_()

        owner_page.route('**/student.php?*', fail_vehicles)
        owner_page.goto(base.replace('/web-app-admin/api', '/web-app-student/'), wait_until='domcontentloaded')
        owner_page.locator('#loginId').fill(owner)
        owner_page.locator('#loginPassword').fill(student_password)
        owner_page.locator('#loginBtn').click()
        owner_page.get_by_role('button', name='Try again').wait_for(timeout=15000)
        expect(owner_page.locator('#screenApp').is_visible(), 'owner remains signed in after initial data failure')
        expect('private error' not in owner_page.locator('#tabPass').inner_text(),
               'owner load error does not expose server HTML')
        owner_page.unroute('**/student.php?*', fail_vehicles)
        owner_page.get_by_role('button', name='Try again').click()
        owner_page.wait_for_function("document.getElementById('tabPass').textContent.includes('" + plate + "')", timeout=15000)
        owner_browser_token = owner_page.evaluate("localStorage.getItem('sp_student_token')")
        call(base, 'auth.php?action=logout', {}, owner_browser_token)
        owner_page.evaluate('StudentApi.me().catch(() => {})')
        owner_page.locator('#screenLogin').wait_for(state='visible', timeout=10000)
        expect('session has ended' in owner_page.locator('#loginError').inner_text().lower(),
               'revoked owner session returns to sign-in on mobile viewport')
        expect(not owner_errors, 'no uncaught browser exceptions in mobile owner flow: ' + '; '.join(owner_errors))
        browser.close()

print('Browser runtime checks completed in disposable PHP/SQLite sandbox.', flush=True)
