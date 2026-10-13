"""
Generates the Guard Shifts showcase seed for phpMyAdmin (MySQL 5.7+ / MariaDB 10.3+):

    python tests/make_guard_shifts_seed.py

Writes
    backend/database/seed_guard_shifts.sql           5 demo guards, ~2 weeks of shifts up to now, and the gate passages
                                                     each guard handled (so the Guard Shifts tab has numbers to show)
    backend/database/remove_guard_shifts_seed.sql    takes all of it out again

Times are written relative to the moment the script is imported (Asia/Manila), so "today" is always today.
Nothing else is touched: no vehicles, violations, settings, or real guard accounts. The demo guards have no usable
password (they cannot sign in). The gate passages use the plates of your first registered vehicles.
Run sync_backend.py afterwards so the web-app-admin mirror matches.
"""
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'backend', 'database')
rnd = random.Random(20261013)

G1, G2, PT = 'Gate 1 (Main Ingress)', 'Gate 2 (Main Egress)', 'Patrol / Other'
DAYS = 14   # today plus the 13 days before it

GUARDS = {  # key -> (username, full name, badge, usual gate)
    'A': ('seed.guard.a', 'Ramon Dela Peña', 'NCST-SEC-D1', G1),
    'B': ('seed.guard.b', 'Maria Santos', 'NCST-SEC-D2', G1),
    'C': ('seed.guard.c', 'Eduardo Villanueva', 'NCST-SEC-D3', G2),
    'D': ('seed.guard.d', 'Liza Mendoza', 'NCST-SEC-D4', G2),
    'E': ('seed.guard.e', 'Carlo Reyes', 'NCST-SEC-D5', PT),
}
LABEL = {k: f'{v[1]} ({v[2]})' for k, v in GUARDS.items()}

NOTES_G1_DAY = [
    'All quiet. Two vehicles with expired stickers were sent to the Cashier.',
    'Heavy traffic from 7:30 to 8:30. Visitor pass holders were checked at the booth.',
    'No incidents. Barrier arm on the left lane is slow, reported to maintenance.',
    'One driver was not on the authorized list and was turned away. Owner was informed.',
]
NOTES_G1_EVE = [
    'Quiet shift. Reminder: delivery truck expected at the main gate tomorrow morning.',
    'Handled the campus event parking. Everything was logged.',
    'No incidents. Late arrivals for the evening classes were all registered vehicles.',
    'One visitor day pass was checked at the booth. Gate lights are working.',
]
NOTES_G2_DAY = [
    'Exit lane clear. Two vehicles left with a Security Hold released by the admin.',
    'No issues. Handover: gate light near the booth is flickering.',
    'One exit refused (vehicle on hold). Owner was sent to the Security Office.',
]
NOTES_G2_EVE = [
    'Rush at 5 PM. No incidents at the exit.',
    'All vehicles that entered today have left except the usual overnight faculty cars.',
    'Exit lane clear after the 6 PM rush. Two manual lookups when QR codes would not scan.',
]
NOTES_PT = [
    'Patrol of the parking areas done. No illegally parked vehicles.',
    'Checked the back lot twice. Nothing to report.',
    'One vehicle parked in the fire lane, owner moved it after a warning.',
]
DENY_ENTRY = ['Pass has expired', 'Driver is not on the authorized list', 'Vehicle is on a violation hold', 'Pass was replaced; old QR code scanned']
DENY_EXIT = ['Vehicle is on a Security Hold', 'Driver does not match the authorized list']


def sq(v):
    if v is None:
        return 'NULL'
    return "'" + str(v).replace('\\', '\\\\').replace("'", "''") + "'"


def at_day(d, minute):
    """Midnight of d days ago + minute (can run past midnight)."""
    return f'DATE_ADD(DATE_SUB(CURDATE(), INTERVAL {d} DAY), INTERVAL {minute} MINUTE)'


def at_now(minutes_ago):
    return f'DATE_SUB(NOW(), INTERVAL {minutes_ago} MINUTE)'


shifts = []   # dicts: guard, gate, start(sql), dur (minutes) or None while open, elapsed (minutes so far for open), note, kind


def add(guard, gate, start, dur, note=None, open_for=None, busy=1.0):
    shifts.append(dict(guard=guard, gate=gate, start=start, dur=dur, note=note, open_for=open_for, busy=busy))


def pick(pool):
    return rnd.choice(pool)


for d in range(DAYS - 1, 0, -1):          # 13 .. 1 days ago (complete days)
    even = d % 2 == 0
    g1_day, g1_eve = ('A', 'B') if even else ('B', 'A')
    g2_day, g2_eve = ('C', 'D') if even else ('D', 'C')
    quiet = d % 7 in (0, 6)                # fewer passages on the weekend-ish days
    busy = 0.55 if quiet else 1.0
    day0, eve0 = 360, 840                  # 06:00 and 14:00
    if d == 8:                             # the day after the forgotten shift: A is not on the morning gate
        g1_day, g1_eve = 'B', 'A'
    # Gate 1
    if d == 9:                             # a guard forgets to end the evening shift: the maintenance job closes it after 16 h
        add(g1_eve, G1, at_day(d, eve0), 16 * 60, '(shift closed automatically after 16 hours)', busy=busy)
    else:
        add(g1_eve, G1, at_day(d, eve0), 8 * 60, pick(NOTES_G1_EVE), busy=busy)
    add(g1_day, G1, at_day(d, day0), 8 * 60, pick(NOTES_G1_DAY) if d != 11 else None, busy=busy)
    # Gate 2
    if d == 5:                             # a long shift (13 h): flagged as long on the timeline
        add(g2_eve, G2, at_day(d, eve0), 13 * 60, 'Stayed on after the evening event ended. Exit lane closed at 03:00.', busy=busy)
    else:
        add(g2_eve, G2, at_day(d, eve0), 8 * 60, pick(NOTES_G2_EVE), busy=busy)
    if d == 3:                             # moved from the exit gate to patrol mid-shift
        add(g2_day, G2, at_day(d, day0), 270, '(moved to another gate)', busy=busy)
        add(g2_day, PT, at_day(d, day0 + 270), 210, pick(NOTES_PT), busy=busy)
    else:
        add(g2_day, G2, at_day(d, day0), 8 * 60, pick(NOTES_G2_DAY), busy=busy)
    # Patrol (guard E, most days)
    if d % 3 != 0 and d != 8:
        add('E', PT, at_day(d, 480), 4 * 60, pick(NOTES_PT), busy=busy)

# Today: two guards on duty right now, one earlier shift already handed over
add('E', G1, at_now(9 * 60), 5 * 60, 'Morning peak handled. Two visitor passes were issued at the booth.')
add('B', G1, at_now(180), None, open_for=180)
add('D', G2, at_now(150), None, open_for=150)


def events_for(s):
    """List of (minute offset from the shift start, action, gate_type, gate_point, note, method)."""
    dur = s['dur'] if s['dur'] is not None else s['open_for']
    if s['kind'] == 'auto':
        dur = 6 * 60                       # the guard was only really working for the first hours
    span = max(10, dur - 12)
    gate = s['gate']
    if gate == PT:
        n = rnd.randint(1, 3)
    elif s['dur'] is None:
        n = max(3, int(span / 60 * rnd.uniform(1.5, 2.5)))
    else:
        n = max(4, int(rnd.randint(9, 18) * s['busy']))
    out = []
    for _ in range(n):
        m = rnd.randint(6, span)
        if gate == G2:
            roll = rnd.random()
            if roll < 0.06:
                out.append((m, 'Exit Denied', 'Egress', gate, pick(DENY_EXIT), 'qr'))
            else:
                out.append((m, 'Exit Approved', 'Egress', gate, None, 'manual' if rnd.random() < 0.12 else 'qr'))
        else:
            roll = rnd.random()
            if roll < 0.07:
                out.append((m, 'Entry Denied', 'Ingress', G1, pick(DENY_ENTRY), 'qr'))
            else:
                out.append((m, 'Entry Recorded', 'Ingress', G1, None, 'manual' if rnd.random() < 0.15 else 'qr'))
    return sorted(out)


for s in shifts:
    s['kind'] = 'auto' if (s['note'] or '').startswith('(shift closed automatically') else 'normal'

HEADER = """-- ==============================================================================
-- SecurePark: Guard Shifts showcase data
-- Target database: MySQL 5.7+ / MariaDB 10.3+ (phpMyAdmin > Import, or the SQL tab)
-- Timezone: Asia/Manila (UTC+8). Every time below is relative to the moment you import it,
-- so the last two weeks always end today and two guards are shown on duty right now.
--
-- WHAT IT ADDS
--   * 5 demo guard accounts (seed.guard.a ... seed.guard.e). They have NO usable password, so nobody can sign in
--     with them; they exist only so the Guard Shifts tab has people to show.
--   * {n_shifts} guard shifts over the last {days} days: Gate 1 and Gate 2 day / evening shifts, patrol, handover notes,
--     one shift the maintenance job closed automatically, one 13-hour shift, one guard moved to another gate,
--     and today's shifts (two guards on duty now).
--   * {n_events} gate passages (entries, exits, refusals) logged by those guards during their shifts, so each shift
--     shows what it handled. They use the plates of your first registered vehicles (sample plates if you have none).
--
-- WHAT IT DOES NOT TOUCH: vehicles, violations, incidents, visitor passes, settings, real staff accounts.
-- Safe to import again: it first removes its own earlier rows (usernames seed.guard.*, client_ref seed-shift-*).
-- To take everything out, import remove_guard_shifts_seed.sql.
--
-- NOTE: the seeded passages do not change a vehicle's Inside / Outside status.
-- ==============================================================================

SET NAMES utf8mb4;
SET time_zone = '+08:00';

START TRANSACTION;

-- 1. Remove an earlier import of this seed
DELETE FROM `gate_logs` WHERE `client_ref` LIKE 'seed-shift-%';
DELETE FROM `guard_shifts` WHERE `user_id` IN (SELECT `id` FROM (SELECT `id` FROM `system_users` WHERE `username` LIKE 'seed.guard.%') u);
DELETE FROM `system_users` WHERE `username` LIKE 'seed.guard.%';

-- 2. Demo guards (password hash is not a valid hash on purpose: these accounts cannot sign in)
INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`, `created_at`) VALUES
{users};
"""

lines = []
users = []
for k, (u, name, badge, gate) in GUARDS.items():
    users.append(f"({sq(u)}, '!seed-account-no-login', {sq(name)}, 'guard', {sq(badge)}, {sq(gate)}, 'Active', 1, DATE_SUB(NOW(), INTERVAL 20 DAY))")
var = ''.join(f"SET @g{k} = (SELECT `id` FROM `system_users` WHERE `username` = {sq(v[0])});\n" for k, v in GUARDS.items())

# 3. shifts
sh_rows = []
for s in shifts:
    end = 'NULL' if s['dur'] is None else f"DATE_ADD({s['start']}, INTERVAL {s['dur']} MINUTE)"
    sh_rows.append(f"(@g{s['guard']}, {sq(LABEL[s['guard']])}, {sq(s['gate'])}, {s['start']}, {end}, {sq(s['note'])})")

# 4. gate passages
ev_rows = []
n = 0
for i, s in enumerate(shifts):
    for k, (m, action, gtype, gate, note, method) in enumerate(events_for(s)):
        status = 'Inside Campus' if action == 'Entry Recorded' else ('Exited' if action == 'Exit Approved' else 'Outside' if action == 'Entry Denied' else 'Inside Campus')
        p = rnd.randint(0, 11)
        ev_rows.append("(@p%d, @t%d, @o%d, @o%d, 'Self (Owner)', %s, %s, %s, %s, %s, @g%s, %s, DATE_ADD(%s, INTERVAL %d MINUTE), %s, %s)" % (
            p, p, p, p, sq(gate), sq(action), sq(gtype), sq(status), sq(LABEL[s['guard']]), s['guard'], sq(note),
            s['start'], m, sq(f'seed-shift-{i + 1}-{k + 1}'), sq(method)))
        n += 1

# Plates for the passages: the first 12 registered vehicles, sample plates fill any gaps (user variables only:
# shared hosts such as InfinityFree do not grant CREATE TEMPORARY TABLES)
PLATES = "\n-- 5. Plates for the passages: your first 12 registered vehicles (sample plates fill any gaps)\n"
for k in range(12):
    PLATES += ("SET @p%d = COALESCE((SELECT `plate_number` FROM `vehicles` ORDER BY `id` LIMIT 1 OFFSET %d), 'SHF %d');\n"
               "SET @t%d = COALESCE((SELECT `vehicle_type` FROM `vehicles` ORDER BY `id` LIMIT 1 OFFSET %d), '%s');\n"
               "SET @o%d = COALESCE((SELECT `owner_name` FROM `vehicles` ORDER BY `id` LIMIT 1 OFFSET %d), 'Sample Owner');\n"
               % (k, k, 1000 + k, k, k, '2-Wheel' if k in (4, 6, 9) else '4-Wheel', k, k))

body = HEADER.format(n_shifts=len(shifts), days=DAYS, n_events=n, users=',\n'.join(users)) + '\n' + var
body += "\n-- 4. Shifts: ended ones carry a handover note; the two with no end time are on duty now\n"
body += "INSERT INTO `guard_shifts` (`user_id`, `guard_label`, `gate`, `started_at`, `ended_at`, `handover_notes`) VALUES\n" + ',\n'.join(sh_rows) + ';\n'
body += PLATES
body += """
-- 6. Passages logged by the guards during their shifts
INSERT INTO `gate_logs` (`plate_number`, `vehicle_type`, `owner_name`, `driver_name`, `driver_relationship`, `gate_point`, `action`, `gate_type`, `status`,
                         `guard_name`, `logged_by_user_id`, `notes`, `logged_at`, `client_ref`, `lookup_method`) VALUES
""" + ',\n'.join(ev_rows) + """;

COMMIT;

-- Check: shifts and passages added
SELECT (SELECT COUNT(*) FROM `guard_shifts` WHERE `user_id` IN (SELECT `id` FROM `system_users` WHERE `username` LIKE 'seed.guard.%')) AS shifts_added,
       (SELECT COUNT(*) FROM `gate_logs` WHERE `client_ref` LIKE 'seed-shift-%') AS passages_added;
"""
with open(os.path.join(OUT, 'seed_guard_shifts.sql'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(body)

REMOVE = """-- ==============================================================================
-- SecurePark: remove the Guard Shifts showcase data added by seed_guard_shifts.sql
-- Deletes only: the seed.guard.* demo accounts, their shifts, and the gate passages with client_ref seed-shift-*.
-- ==============================================================================
START TRANSACTION;
DELETE FROM `gate_logs` WHERE `client_ref` LIKE 'seed-shift-%';
DELETE FROM `guard_shifts` WHERE `user_id` IN (SELECT `id` FROM (SELECT `id` FROM `system_users` WHERE `username` LIKE 'seed.guard.%') u);
DELETE FROM `system_users` WHERE `username` LIKE 'seed.guard.%';
COMMIT;
"""
with open(os.path.join(OUT, 'remove_guard_shifts_seed.sql'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(REMOVE)
print(f'{len(shifts)} shifts, {n} passages -> backend/database/seed_guard_shifts.sql')
