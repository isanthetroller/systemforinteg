/**
 * SecurePark Student Portal
 *
 * Screens: sign in -> (first sign-in) set password -> app with three tabs:
 *   My Pass   signed QR pass per vehicle, standing, authorized drivers, save as image
 *   Strikes   3-strike meter, warnings / violations history, recent gate activity
 *   Account   profile, change password, how the pass works
 *
 * Everything shown comes from /api/student.php, which only returns the signed-in owner's data.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const STRIKE_LIMIT = 3;
  const data = { me: null, vehicles: [], violations: [], activity: [], selected: 0 };

  /* ---------------- helpers ---------------- */
  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function initials(name) {
    return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0].toUpperCase()).join('') || '?';
  }

  function fmtDateTime(value) {
    if (!value) return '';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    return isNaN(d) ? value : d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  }

  function fmtDate(value) {
    if (!value) return '—';
    const d = new Date(`${value}T12:00:00+08:00`);
    return isNaN(d) ? value : d.toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', month: 'long', day: 'numeric', year: 'numeric' });
  }

  let toastTimer = null;
  function toast(message, type = null) {
    if (window.SPAlert && typeof SPAlert.toast === 'function') {
      return SPAlert.toast(message, type);
    }
    const el = $('toast');
    if (!el) return;
    el.textContent = message;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 3200);
  }

  function showError(id, message) {
    $(id).textContent = message || '';
    $(id).hidden = !message;
  }

  function showScreen(id) {
    ['screenLogin', 'screenPassword', 'screenApp'].forEach(s => { $(s).hidden = s !== id; });
  }

  function vehicleStanding(v) {
    if (v.isBanned) return { cls: 'bad', label: 'BANNED — ENTRY BLOCKED', blocked: true };
    if (v.registrationStatus === 'Suspended') return { cls: 'bad', label: 'REGISTRATION SUSPENDED', blocked: true };
    if (v.passExpired) return { cls: 'bad', label: 'PASS EXPIRED', blocked: true };
    if (v.warningCount > 0) return { cls: 'warn', label: `ACTIVE · STRIKE ${v.warningCount} OF ${STRIKE_LIMIT}`, blocked: false };
    return { cls: 'ok', label: 'ACTIVE PASS', blocked: false };
  }

  /* ---------------- auth flow ---------------- */
  async function boot() {
    if (!StudentApi.hasToken()) return showScreen('screenLogin');
    try {
      data.me = await StudentApi.me();
      if (data.me.student.mustChangePassword) return showScreen('screenPassword');
      await enterApp();
    } catch (err) {
      if (err.code === 'PASSWORD_CHANGE_REQUIRED') return showScreen('screenPassword');
      showScreen('screenLogin');
    }
  }

  async function onLogin(e) {
    e.preventDefault();
    const id = $('loginId').value.trim();
    const pw = $('loginPassword').value;
    if (!id || !pw) return showError('loginError', 'Enter your ID and password.');
    $('loginBtn').disabled = true;
    showError('loginError', '');
    try {
      const student = await StudentApi.login(id, pw);
      $('loginPassword').value = '';
      if (student.mustChangePassword) {
        showScreen('screenPassword');
        $('fpCurrent').focus();
      } else {
        await enterApp();
      }
    } catch (err) {
      showError('loginError', err.status === 401 ? 'Incorrect ID or password.' : err.message);
    } finally {
      $('loginBtn').disabled = false;
    }
  }

  async function changePassword(currentId, newId, confirmId, errorId, button) {
    const current = $(currentId).value;
    const next = $(newId).value;
    if (!current || !next) { showError(errorId, 'Please fill in all fields.'); return false; }
    if (next !== $(confirmId).value) { showError(errorId, 'New passwords do not match.'); return false; }
    button.disabled = true;
    showError(errorId, '');
    try {
      await StudentApi.changePassword(current, next);
      [currentId, newId, confirmId].forEach(id => { $(id).value = ''; });
      return true;
    } catch (err) {
      showError(errorId, err.message);
      return false;
    } finally {
      button.disabled = false;
    }
  }

  async function onFirstPassword(e) {
    e.preventDefault();
    if (await changePassword('fpCurrent', 'fpNew', 'fpConfirm', 'firstPasswordError', $('firstPasswordBtn'))) {
      await enterApp();
      if (window.SPAlert) {
        SPAlert.success({
          title: 'Welcome to SecurePark!',
          text: 'Your new password has been saved.',
          timer: 2500
        });
      } else {
        toast('Password saved. Welcome to SecurePark!', 'success');
      }
    }
  }

  async function onPassword(e) {
    e.preventDefault();
    $('passwordOk').hidden = true;
    if (await changePassword('pwCurrent', 'pwNew', 'pwConfirm', 'passwordError', $('passwordBtn'))) {
      $('passwordOk').textContent = 'Password updated. Other devices were signed out.';
      $('passwordOk').hidden = false;
      if (window.SPAlert) {
        SPAlert.success({
          title: 'Password Updated',
          text: 'Your password was updated successfully. All other devices were signed out.',
          timer: 2500
        });
      }
    }
  }

  async function logout() {
    if (window.SPAlert) {
      const confirmed = await SPAlert.confirm({
        title: 'Sign Out?',
        text: 'Are you sure you want to sign out of the Student Portal?',
        confirmText: 'Sign Out',
        cancelText: 'Stay Signed In',
        icon: 'question'
      });
      if (!confirmed) return;
    }
    await StudentApi.logout();
    data.me = null;
    data.vehicles = [];
    showScreen('screenLogin');
    $('loginId').focus();
  }

  /* ---------------- app ---------------- */
  async function enterApp() {
    showScreen('screenApp');
    $('tabPass').innerHTML = '<div class="card empty">Loading your pass&hellip;</div>';
    const [me, vehicles, violations, activity] = await Promise.all([
      StudentApi.me(), StudentApi.vehicles(), StudentApi.violations(), StudentApi.activity()
    ]);
    Object.assign(data, { me, vehicles, violations, activity });
    data.selected = Math.min(data.selected, Math.max(vehicles.length - 1, 0));
    $('topbarName').textContent = `${me.student.fullName} · ${me.student.ownerIdNumber}`;
    const strikes = me.summary.strikes + me.summary.banned;
    $('strikesBadge').textContent = me.summary.banned ? '!' : String(me.summary.strikes);
    $('strikesBadge').hidden = strikes === 0;
    renderPass();
    renderStrikes();
    renderAccount();
  }

  function selectTab(tabId) {
    document.querySelectorAll('.tab').forEach(t => { t.hidden = t.id !== tabId; });
    document.querySelectorAll('.tabbar-btn').forEach(b => {
      if (b.dataset.tab === tabId) b.setAttribute('aria-current', 'page');
      else b.removeAttribute('aria-current');
    });
    window.scrollTo(0, 0);
  }

  /* ---- My Pass ---- */
  function renderPass() {
    const tab = $('tabPass');
    if (!data.vehicles.length) {
      tab.innerHTML = '<div class="card empty"><strong>No registered vehicle</strong>Register your vehicle at the Campus Security Office to get a pass.</div>';
      return;
    }
    const v = data.vehicles[data.selected];
    const st = vehicleStanding(v);
    const chips = data.vehicles.length > 1
      ? `<div class="chips" role="group" aria-label="Choose vehicle">${data.vehicles.map((x, i) =>
          `<button type="button" class="chip" data-index="${i}" aria-pressed="${i === data.selected}">${esc(x.plateNumber)}</button>`).join('')}</div>`
      : '';
    const blockNotice = v.isBanned
      ? `<div class="notice bad">Your vehicle reached ${STRIKE_LIMIT} strikes or received a violation and is banned from entering campus. Go to the Campus Security Office to settle it. See the <strong>Strikes</strong> tab for details.</div>`
      : v.registrationStatus === 'Suspended'
        ? '<div class="notice bad">Your registration is suspended. Please visit the Campus Security Office.</div>'
        : v.passExpired
          ? '<div class="notice bad">This pass has expired. Renew your sticker at the Campus Security Office to get a new pass.</div>'
          : (v.warningCount > 0 ? `<div class="notice warn">You have ${v.warningCount} of ${STRIKE_LIMIT} strikes. At ${STRIKE_LIMIT} strikes your vehicle is banned.</div>` : '');

    tab.innerHTML = `
      ${chips}
      <article class="card pass" aria-label="Campus pass for ${esc(v.plateNumber)}">
        <div class="pass-banner ${st.cls}"><span>${esc(st.label)}</span><span>${(v.status || '').toLowerCase().includes('inside') ? 'ON CAMPUS' : 'OFF CAMPUS'}</span></div>
        <div class="pass-body">
          <span class="plate">${esc(v.plateNumber)}</span>
          <div class="pass-vehicle">${esc(v.makeModelColor || v.vehicleType || '')}</div>
          <button type="button" id="passQr" class="pass-qr ${st.blocked ? 'dim' : ''}" aria-label="Show QR full screen">
            ${st.blocked ? `<span class="pass-qr-stamp"><span>${v.isBanned ? 'BANNED' : v.passExpired ? 'EXPIRED' : 'SUSPENDED'}</span></span>` : ''}
          </button>
          <div class="pass-id">${esc(v.passId || '')}</div>
          <dl class="pass-meta">
            <div><dt>Valid until</dt><dd>${esc(fmtDate(v.passValidUntil))}</dd></div>
            <div><dt>Sticker year</dt><dd>${esc(v.stickerYear || '—')}</dd></div>
            <div><dt>Strikes</dt><dd>${v.isBanned ? 'Banned' : `${v.warningCount} of ${STRIKE_LIMIT}`}</dd></div>
            <div><dt>Campus status</dt><dd>${(v.status || '').toLowerCase().includes('inside') ? '<span class="status-on">On Campus</span>' : '<span class="status-off">Outside Campus</span>'}</dd></div>
          </dl>
        </div>
        <div class="pass-actions">
          <button type="button" class="btn btn-gold" data-action="zoom">Show at Gate</button>
          <button type="button" class="btn btn-outline" data-action="save">Save Image</button>
        </div>
      </article>
      ${blockNotice}
      <div class="card">
        <h2 class="card-title">Authorized drivers</h2>
        <ul class="drivers">
          ${(v.authorizedDrivers || []).map(d => `
            <li><span class="avatar">${esc(initials(d.fullName))}</span>
              <div><div class="name">${esc(d.fullName)}</div><div class="sub">${esc(d.relationship || '')}${d.licenseNo && d.licenseNo !== 'N/A' ? ' · Lic. ' + esc(d.licenseNo) : ''}</div></div></li>`).join('')}
        </ul>
        <p class="hint">Only these people may drive this vehicle through the gate. Changes are made at the Security Office.</p>
      </div>`;

    if (typeof QRCode !== 'undefined' && v.qrPayload) {
      new QRCode($('passQr'), { text: v.qrPayload, width: 216, height: 216, colorDark: '#0F172A', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    }
    tab.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { data.selected = Number(c.dataset.index); renderPass(); }));
    $('passQr').addEventListener('click', () => openZoom(v));
    tab.querySelector('[data-action="zoom"]').addEventListener('click', () => openZoom(v));
    tab.querySelector('[data-action="save"]').addEventListener('click', () => savePassImage(v));
  }

  function openZoom(v) {
    $('qrZoomPlate').textContent = v.plateNumber;
    $('qrZoomCode').innerHTML = '';
    new QRCode($('qrZoomCode'), { text: v.qrPayload, width: 420, height: 420, colorDark: '#000000', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    $('qrZoom').hidden = false;
  }

  function savePassImage(v) {
    const qrCanvas = $('passQr').querySelector('canvas');
    if (!qrCanvas) return toast('The QR code is still loading. Try again.');
    const W = 720, H = 1080;
    const c = document.createElement('canvas');
    c.width = W; c.height = H;
    const ctx = c.getContext('2d');
    const sans = '"Plus Jakarta Sans", system-ui, sans-serif';
    const mono = '"JetBrains Mono", ui-monospace, monospace';
    const st = vehicleStanding(v);

    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = '#1B3676'; ctx.fillRect(0, 0, W, 170);
    ctx.fillStyle = '#F5B800'; ctx.fillRect(0, 164, W, 6);
    ctx.textAlign = 'center';
    ctx.fillStyle = '#fff'; ctx.font = `800 30px ${sans}`; ctx.fillText('NCST SECUREPARK', W / 2, 72);
    ctx.fillStyle = '#C7D2FE'; ctx.font = `600 22px ${sans}`; ctx.fillText('Campus Vehicle Pass', W / 2, 112);
    ctx.fillStyle = st.cls === 'bad' ? '#D62828' : st.cls === 'warn' ? '#B45309' : '#16A34A';
    ctx.font = `800 22px ${sans}`; ctx.fillText(st.label, W / 2, 222);
    ctx.fillStyle = '#0F172A'; ctx.fillRect(W / 2 - 170, 244, 340, 70);
    ctx.fillStyle = '#F5B800'; ctx.font = `800 44px ${mono}`; ctx.fillText(v.plateNumber, W / 2, 294);
    ctx.fillStyle = '#334155'; ctx.font = `600 22px ${sans}`; ctx.fillText(v.makeModelColor || '', W / 2, 350);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(qrCanvas, (W - 480) / 2, 380, 480, 480);
    ctx.fillStyle = '#334155'; ctx.font = `700 24px ${mono}`; ctx.fillText(v.passId || '', W / 2, 900);
    ctx.font = `600 22px ${sans}`; ctx.fillText(`${v.ownerName} · Valid until ${fmtDate(v.passValidUntil)}`, W / 2, 940);
    ctx.fillStyle = '#64748B'; ctx.font = `500 18px ${sans}`;
    ctx.fillText('Show this QR at the gate on entry and exit. Only authorized drivers may use it.', W / 2, 1010);
    ctx.fillText('A reissued pass replaces this one.', W / 2, 1038);

    c.toBlob(blob => {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `SecurePark-${v.plateNumber.replace(/\s+/g, '')}.png`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    }, 'image/png');
  }

  /* ---- Strikes ---- */
  function meter(count, banned) {
    const n = Math.min(Number(count || 0), STRIKE_LIMIT);
    const pips = Array.from({ length: STRIKE_LIMIT }, (_, i) =>
      `<span class="pip ${i < n ? (banned || n >= STRIKE_LIMIT ? 'full' : 'on') : ''}"></span>`).join('');
    return `<span class="meter" role="img" aria-label="${banned ? 'Banned' : `${n} of ${STRIKE_LIMIT} strikes`}">${pips}<span class="meter-label">${banned ? 'Banned' : `${n} / ${STRIKE_LIMIT}`}</span></span>`;
  }

  function renderStrikes() {
    const standing = data.vehicles.map(v => `
      <div class="standing-row"><span class="plate" style="font-size:16px">${esc(v.plateNumber)}</span>${meter(v.warningCount, v.isBanned)}</div>`).join('');
    const history = data.violations.length
      ? `<ul class="history">${data.violations.map(r => `
          <li>
            <div class="row1"><span class="type">${esc(r.violationType)}</span><span class="date">${esc(fmtDateTime(r.createdAt))}</span></div>
            <div class="desc">${esc(r.plateNumber)}${r.description ? ' · ' + esc(r.description) : ''}</div>
            <span class="badge ${r.severity === 'Violation' ? 'violation' : 'warning'}">${esc(r.severity)}</span>
            <span class="badge ${esc(r.status.toLowerCase())}">${esc(r.status)}</span>
            ${r.resolutionNotes ? `<div class="desc" style="color:var(--muted)">${esc(r.resolutionNotes)}</div>` : ''}
          </li>`).join('')}</ul>`
      : '<p class="empty" style="padding:12px 0">No warnings or violations. Keep it up!</p>';
    const activity = data.activity.length
      ? `<ul class="activity">${data.activity.map(a => `
          <li><span><span class="act ${/Denied/.test(a.action) ? 'denied' : ''}">${esc(a.action)}</span> · ${esc(a.plateNumber)}</span><span style="color:var(--muted)">${esc(fmtDateTime(a.loggedAt))}</span></li>`).join('')}</ul>`
      : '<p class="empty" style="padding:12px 0">No gate activity yet.</p>';
    const anyBanned = data.vehicles.some(v => v.isBanned);

    $('tabStrikes').innerHTML = `
      ${anyBanned ? '<div class="notice bad">A vehicle is banned. Visit the Campus Security Office to resolve the violation; the ban and your strikes are cleared once it is resolved.</div>' : ''}
      <div class="card"><h2 class="card-title">Strike standing</h2>${standing || '<p class="hint">No vehicles.</p>'}
        <p class="hint">Warnings and overnight / after-curfew parking each add one strike. ${STRIKE_LIMIT} strikes = automatic ban.</p></div>
      <div class="card"><h2 class="card-title">Warnings &amp; violations</h2>${history}</div>
      <div class="card"><h2 class="card-title">Recent gate activity</h2>${activity}</div>`;
  }

  /* ---- Account ---- */
  function renderAccount() {
    const s = data.me.student;
    $('accountDetails').innerHTML = `
      <dt>Name</dt><dd>${esc(s.fullName)}</dd>
      <dt>ID number</dt><dd>${esc(s.ownerIdNumber)}</dd>
      <dt>Email</dt><dd>${esc(s.email || '—')}</dd>
      <dt>Vehicles</dt><dd>${data.me.summary.vehicles}</dd>`;
  }

  /* ---------------- wiring ---------------- */
  document.addEventListener('DOMContentLoaded', () => {
    $('loginForm').addEventListener('submit', onLogin);
    $('firstPasswordForm').addEventListener('submit', onFirstPassword);
    $('passwordForm').addEventListener('submit', onPassword);
    document.querySelectorAll('[data-action="logout"]').forEach(b => b.addEventListener('click', logout));
    document.querySelectorAll('.tabbar-btn').forEach(b => b.addEventListener('click', () => selectTab(b.dataset.tab)));
    $('qrZoom').addEventListener('click', () => { $('qrZoom').hidden = true; });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') $('qrZoom').hidden = true; });
    boot();
  });

  window.addEventListener('sp:signed-out', (e) => {
    showScreen('screenLogin');
    showError('loginError', e.detail && e.detail.message);
  });
  window.addEventListener('sp:password-change-required', () => showScreen('screenPassword'));
})();
