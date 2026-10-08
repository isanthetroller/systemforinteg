/**
 * SecurePark Student Portal
 *
 * Screens: sign in -> (first sign-in) set password -> app with four tabs:
 *   My Pass   signed QR pass per vehicle, standing, authorized drivers, save as image
 *   Activity  gate audit log (entries, exits, refused passages) and flag history of the owner's vehicles
 *   Violations   violations on my vehicles: a pending one blocks entry and exit until the Security Office resolves it
 *   Account   profile, change password, how the pass works
 * Every entry, exit and refused passage has a 5 second gate clip (simulated: one shared clip, or
 * cctv_clips/log-<id>.mp4 when the school supplies one); a flag's clip is the refused passage that raised it.
 * A red banner on every tab appears while one of the owner's vehicles is held at the gate; the app
 * re-checks every 15 seconds while it is open.
 *
 * Everything shown comes from /api/student.php, which only returns the signed-in owner's data.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const data = { me: null, vehicles: [], violations: [], cases: [], activity: [], alerts: { active: [], recent: [] }, selected: 0, activityFilter: 'all' };
  const POLL_MS = 15000;
  const DEFAULT_TITLE = document.title;
  let pollTimer = null;

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

  function fmtTime(value) {
    if (!value) return '';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    return isNaN(d) ? value : d.toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit' });
  }

  function manilaDay(offsetDays = 0) {
    const d = new Date(Date.now() + offsetDays * 86400000);
    return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
  }

  function dayLabel(dayKey) {
    if (dayKey === manilaDay(0)) return 'Today';
    if (dayKey === manilaDay(-1)) return 'Yesterday';
    return fmtDate(dayKey);
  }

  function normPlate(p) { return String(p || '').toUpperCase().replace(/[^A-Z0-9]/g, ''); }

  /* ---- Gate clips ---- */
  const CLIP_BASE = String(window.SECUREPARK_ASSETS_URL || '../assets').replace(/\/+$/, '');

  function isExitPassage(d) {
    return /exit|egress/i.test(d.action || '') || /gate 2|egress/i.test(d.gatePoint || '');
  }

  function clipButton(d, label, extraClass) {
    const text = label || (isExitPassage(d) ? 'Exit clip' : 'Entry clip');
    return `<button type="button" class="clip-btn ${extraClass || ''}" data-clip="${esc(encodeURIComponent(JSON.stringify(d)))}">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>${esc(text)} · 5s</button>`;
  }

  function openClip(d) {
    const video = $('clipVideo');
    const exit = isExitPassage(d);
    $('clipTitle').textContent = `${exit ? 'Exit' : 'Entry'} clip · ${d.plate || ''}`;
    $('clipSub').textContent = [exit ? 'Exit gate camera' : 'Main gate camera', d.gatePoint, d.loggedAt ? fmtDateTime(d.loggedAt) : ''].filter(Boolean).join(' · ');
    $('clipMissing').hidden = true;
    video.pause();
    video.textContent = '';
    // The passage's own clip first (when the school has supplied one), then the shared clip
    const sources = (d.logId ? [`${CLIP_BASE}/cctv_clips/log-${encodeURIComponent(d.logId)}.mp4`] : []).concat(`${CLIP_BASE}/cctv_clip_placeholder.mp4`);
    sources.forEach((src, i) => {
      const el = document.createElement('source');
      el.src = src;
      el.type = 'video/mp4';
      if (i === sources.length - 1) el.addEventListener('error', () => { $('clipMissing').hidden = false; });
      video.appendChild(el);
    });
    $('clipModal').hidden = false;
    video.load();
    const started = video.play();
    if (started && started.catch) started.catch(() => { /* autoplay refused: the controls start it */ });
  }

  function closeClip() {
    const video = $('clipVideo');
    video.pause();
    video.textContent = '';
    video.load();
    $('clipModal').hidden = true;
  }

  function activeAlertsFor(v) {
    return data.alerts.active.filter(a => normPlate(a.plateNumber) === normPlate(v.plateNumber));
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
    if (activeAlertsFor(v).length) return { cls: 'bad', label: 'FLAGGED · HELD AT GATE', blocked: false, flagged: true };
    if (v.isBanned) return { cls: 'bad', label: 'VIOLATION HOLD — CANNOT ENTER OR LEAVE', blocked: true };
    if (v.registrationStatus === 'Suspended') return { cls: 'bad', label: 'REGISTRATION SUSPENDED', blocked: true };
    if (v.passExpired) return { cls: 'bad', label: 'PASS EXPIRED', blocked: true };
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
    stopPolling();
    await StudentApi.logout();
    data.me = null;
    data.vehicles = [];
    data.alerts = { active: [], recent: [] };
    document.title = DEFAULT_TITLE;
    $('alertBanner').hidden = true;
    showScreen('screenLogin');
    $('loginId').focus();
  }

  /* ---------------- app ---------------- */
  async function enterApp() {
    showScreen('screenApp');
    $('tabPass').innerHTML = '<div class="card empty">Loading your pass&hellip;</div>';
    const [me, vehicles, violations, activity, alerts, payments, notices, cases] = await Promise.all([
      StudentApi.me(), StudentApi.vehicles(), StudentApi.violations(), StudentApi.activity(), StudentApi.alerts(), StudentApi.payments(), StudentApi.notices(), StudentApi.cases()
    ]);
    Object.assign(data, { me, vehicles, violations, activity, alerts, payments, notices, cases });
    data.selected = Math.min(data.selected, Math.max(vehicles.length - 1, 0));
    $('topbarName').textContent = `${me.student.fullName} · ${me.student.ownerIdNumber}`;
    renderAll();
    startPolling();
    handlePaymentReturn();
  }

  function renderAll() {
    const open = data.me.summary.openViolations || 0;
    $('strikesBadge').textContent = String(open);
    $('strikesBadge').hidden = open === 0;
    $('strikesBadge').classList.add('is-blocked');
    renderAlerts();
    renderPass();
    renderActivity();
    renderStrikes();
    renderAccount();
  }

  /* ---- Live refresh: a flag raised at the gate must reach the owner while it is happening ---- */
  function startPolling() {
    stopPolling();
    pollTimer = setInterval(refresh, POLL_MS);
  }

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
  }

  async function refresh() {
    if (!data.me || document.hidden || $('screenApp').hidden) return;
    try {
      const [me, alerts, activity, notices] = await Promise.all([StudentApi.me(), StudentApi.alerts(), StudentApi.activity(), StudentApi.notices()]);
      const before = JSON.stringify([data.me.summary, data.alerts, data.activity.slice(0, 20), (data.notices || []).map(n => n.id)]);
      if (before === JSON.stringify([me.summary, alerts, activity.slice(0, 20), notices.map(n => n.id)])) return;

      const knownNotices = new Set((data.notices || []).map(n => n.id));
      const newNotice = notices.find(n => !knownNotices.has(n.id));

      const known = new Set(data.alerts.active.map(a => a.id));
      const raised = alerts.active.filter(a => !known.has(a.id));
      const standingChanged = JSON.stringify(me.summary) !== JSON.stringify(data.me.summary);
      Object.assign(data, { me, alerts, activity, notices });
      if (standingChanged || raised.length || alerts.active.length !== known.size || newNotice) {
        const [vehicles, violations, payments, cases] = await Promise.all([StudentApi.vehicles(), StudentApi.violations(), StudentApi.payments(), StudentApi.cases()]);
        Object.assign(data, { vehicles, violations, payments, cases });
      }
      renderAll();
      if (raised.length) notifyFlag(raised[0]);
      else if (newNotice) toast(`${newNotice.title} (${newNotice.plateNumber})`, 'error');
    } catch (_) { /* a missed check is retried on the next tick; sign-out is handled by the API client */ }
  }

  function notifyFlag(a) {
    toast(`Your vehicle ${a.plateNumber} was flagged at the gate.`, 'error');
    try { if (navigator.vibrate) navigator.vibrate([250, 120, 250, 120, 500]); } catch (_) {}
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
    const qrReady = Boolean(v.qrPayload);
    const chips = data.vehicles.length > 1
      ? `<div class="chips" role="group" aria-label="Choose vehicle">${data.vehicles.map((x, i) =>
          `<button type="button" class="chip" data-index="${i}" aria-pressed="${i === data.selected}">${esc(x.plateNumber)}</button>`).join('')}</div>`
      : '';
    if (v.paymentStatus === 'Unpaid') return renderPaymentDue(tab, v, chips);
    const flags = activeAlertsFor(v);
    const flagNotice = flags.length
      ? `<div class="notice bad">This vehicle is being <strong>held at the gate</strong> (${esc(flags[0].gatePoint)}). If you did not authorize this, contact the guard or the Campus Security Office right away. See the <strong>Activity</strong> tab.<div class="alert-clip">${clipButton({ logId: flags[0].logId, plate: flags[0].plateNumber, action: '', gatePoint: flags[0].gatePoint, loggedAt: flags[0].reportedAt }, 'Watch gate clip', 'danger')}</div></div>`
      : '';
    const blockNotice = v.isBanned
      ? `<div class="notice bad">Your vehicle has an unresolved <strong>violation</strong>. It cannot enter or leave campus until the Campus Security Office resolves it. Go to the Security Office to settle it. See the <strong>Violations</strong> tab for details.</div>`
      : v.registrationStatus === 'Suspended'
        ? '<div class="notice bad">Your registration is suspended. Please visit the Campus Security Office.</div>'
        : v.passExpired
          ? '<div class="notice bad">This pass has expired. Renew your sticker at the Campus Security Office to get a new pass.</div>'
          : '';

    tab.innerHTML = `
      ${chips}
      <article class="card pass" aria-label="Campus pass for ${esc(v.plateNumber)}">
        <div class="pass-banner ${st.cls}"><span>${esc(st.label)}</span><span>${(v.status || '').toLowerCase().includes('inside') ? 'ON CAMPUS' : 'OFF CAMPUS'}</span></div>
        <div class="pass-body">
          <div class="pass-kind">${v.isVip ? 'VIP vehicle pass' : 'Campus vehicle pass'}</div>
          <span class="plate">${esc(v.plateNumber)}</span>
          <div class="pass-vehicle">${esc(v.makeModelColor || v.vehicleType || '')}</div>
          <button type="button" id="passQr" class="pass-qr ${st.blocked ? 'dim' : ''}" aria-label="Show QR full screen" ${qrReady ? '' : 'disabled'}>
            ${qrReady ? '' : '<span class="pass-qr-empty">Pass unavailable<span>Please contact the Security Office.</span></span>'}
            ${st.blocked ? `<span class="pass-qr-stamp"><span>${v.isBanned ? 'ON HOLD' : v.passExpired ? 'EXPIRED' : 'SUSPENDED'}</span></span>` : ''}
          </button>
          <div class="pass-id">${esc(v.passId || '')}</div>
          <div class="pass-actions">
            <button type="button" class="btn btn-gold" data-action="zoom" ${qrReady ? '' : 'disabled'}>Show at Gate</button>
            <button type="button" class="btn btn-outline" data-action="save" ${qrReady ? '' : 'disabled'}>Save Image</button>
          </div>
          <dl class="pass-meta">
            <div><dt>Valid until</dt><dd>${esc(fmtDate(v.passValidUntil))}</dd></div>
            <div><dt>Sticker year</dt><dd>${esc(v.stickerYear || '—')}</dd></div>
            <div><dt>Registration fee</dt><dd>${v.paymentStatus === 'Waived' ? 'No fee' : v.feeAmount > 0 ? `Paid ${peso(v.feeAmount)}` : 'Paid'}</dd></div>
            <div><dt>Violations</dt><dd>${v.isBanned ? 'On hold (unresolved)' : v.isVip ? 'Not applied to VIP' : 'None pending'}</dd></div>
            <div><dt>Campus status</dt><dd>${(v.status || '').toLowerCase().includes('inside') ? '<span class="status-on">On Campus</span>' : '<span class="status-off">Outside Campus</span>'}</dd></div>
          </dl>
        </div>
      </article>
      <div class="pass-support">${flagNotice}${blockNotice}
      <div class="card gate-help"><h2 class="card-title">At the gate</h2><ol><li><span>1</span><div><strong>Open your pass</strong><p>Tap Show at Gate to make the QR code larger.</p></div></li><li><span>2</span><div><strong>Show it to the guard</strong><p>Keep your screen bright enough to scan.</p></div></li><li><span>3</span><div><strong>${v.isVip ? 'Wait for approval' : 'Confirm the driver'}</strong><p>${v.isVip ? 'The guard checks your pass before entry or exit.' : 'The guard checks the driver before entry or exit.'}</p></div></li></ol></div>
      <div class="card">
        <h2 class="card-title">Authorized drivers</h2>
        <ul class="drivers">
          ${(v.authorizedDrivers || []).map(d => `
            <li><span class="avatar">${esc(initials(d.fullName))}</span>
              <div><div class="name">${esc(d.fullName)}</div><div class="sub">${esc(d.relationship || '')}${d.licenseNo && d.licenseNo !== 'N/A' ? ' · License ' + esc(d.licenseNo) : ''}</div></div></li>`).join('')}
        </ul>
        ${(v.authorizedDrivers || []).length ? '' : '<p class="hint">No drivers are listed. Visit the Security Office to update this vehicle.</p>'}
        <p class="hint">${v.isVip ? 'VIP passes do not need a driver check. Vehicle changes are made at the Security Office.' : 'Only these people may drive this vehicle through the gate. Changes are made at the Security Office.'}</p>
      </div></div>`;

    if (typeof QRCode !== 'undefined' && v.qrPayload) {
      new QRCode($('passQr'), { text: v.qrPayload, width: 216, height: 216, colorDark: '#0F172A', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    }
    tab.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { data.selected = Number(c.dataset.index); renderPass(); }));
    $('passQr').addEventListener('click', () => openZoom(v));
    tab.querySelector('[data-action="zoom"]').addEventListener('click', () => openZoom(v));
    tab.querySelector('[data-action="save"]').addEventListener('click', () => savePassImage(v));
  }

  /* ---- Registration fee: no pass until it is paid ---- */
  const peso = (n) => '\u20b1' + Number(n || 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function renderPaymentDue(tab, v, chips) {
    tab.innerHTML = `
      ${chips}
      <article class="card pass pay-due" aria-label="Registration fee for ${esc(v.plateNumber)}">
        <div class="pass-banner warn"><span>PAYMENT REQUIRED</span><span>NO PASS YET</span></div>
        <div class="pass-body">
          <div class="pass-kind">Registration fee</div>
          <span class="plate">${esc(v.plateNumber)}</span>
          <div class="pass-vehicle">${esc(v.makeModelColor || v.vehicleType || '')}</div>
          <div class="pay-amount">${peso(v.feeAmount)}</div>
          <p class="pay-note">Your QR pass appears here as soon as the fee is paid. Until then this vehicle cannot enter campus.</p>
          <div class="pass-actions">
            <button type="button" class="btn btn-gold" data-action="pay">Pay ${peso(v.feeAmount)} online</button>
          </div>
          <p class="hint" id="payError" role="alert" hidden></p>
        </div>
      </article>
      <div class="pass-support">
        <div class="card gate-help"><h2 class="card-title">Two ways to pay</h2><ol>
          <li><span>1</span><div><strong>Online</strong><p>Pay with GCash, Maya or a card through PayMongo. Your pass is ready within moments of paying.</p></div></li>
          <li><span>2</span><div><strong>In person</strong><p>Go to the cashier at the Campus Security Office and give your plate number (${esc(v.plateNumber)}) or ID. Your pass appears here right after.</p></div></li>
        </ol></div>
      </div>`;
    tab.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { data.selected = Number(c.dataset.index); renderPass(); }));
    tab.querySelector('[data-action="pay"]').addEventListener('click', (e) => startPayment(v, e.currentTarget));
  }

  async function startPayment(v, button) {
    const err = $('payError');
    err.hidden = true;
    button.disabled = true;
    const label = button.textContent;
    button.textContent = 'Opening secure checkout\u2026';
    try {
      const r = await StudentApi.startPayment(v.id, location.origin + location.pathname);
      window.location.href = r.checkoutUrl;
    } catch (e) {
      err.textContent = e.message || 'Could not start the payment. Please try again.';
      err.hidden = false;
      button.disabled = false;
      button.textContent = label;
    }
  }

  /* Back from the PayMongo checkout (?payment=success|cancelled&p=<id>) */
  async function handlePaymentReturn() {
    const params = new URLSearchParams(location.search);
    const outcome = params.get('payment');
    if (!outcome) return;
    const id = params.get('p');
    history.replaceState(null, '', location.pathname);
    selectTab('tabPass');
    if (outcome !== 'success' || !id) {
      toast('Payment was cancelled. You can pay again anytime.');
      return;
    }
    toast('Confirming your payment\u2026');
    let payment = null;
    for (let i = 0; i < 8; i++) {
      try { payment = await StudentApi.paymentStatus(id); } catch (_) { break; }
      if (payment.status !== 'Pending') break;
      await new Promise(r => setTimeout(r, 1500));
    }
    try {
      const [me, vehicles, payments] = await Promise.all([StudentApi.me(), StudentApi.vehicles(), StudentApi.payments()]);
      Object.assign(data, { me, vehicles, payments });
      const paidIndex = payment ? vehicles.findIndex(x => x.id === payment.vehicleId) : -1;
      if (paidIndex >= 0) data.selected = paidIndex; // land on the vehicle that was just paid for
      renderAll();
    } catch (_) { /* the next poll refreshes */ }
    if (payment && payment.status === 'Paid') toast(`Payment received (${payment.receiptNumber}). Your pass is ready.`, 'success');
    else toast('We have not received the payment yet. If you paid, your pass will appear shortly.');
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

  /* ---- Flag banner (all tabs) ---- */
  function renderAlerts() {
    const active = data.alerts.active;
    const banner = $('alertBanner');
    const badge = $('activityBadge');
    badge.textContent = '!';
    badge.hidden = active.length === 0;
    document.title = active.length ? '⚠ Vehicle flagged · SecurePark' : DEFAULT_TITLE;
    if (!active.length) { banner.hidden = true; banner.innerHTML = ''; return; }

    banner.innerHTML = `
      <div class="alert-head"><span class="alert-dot" aria-hidden="true"></span>
        ${active.length > 1 ? `${active.length} VEHICLE FLAGS AT THE GATE` : 'YOUR VEHICLE WAS FLAGGED AT THE GATE'}</div>
      ${active.slice(0, 3).map(a => {
        const stranger = a.driverName && !/^(registered owner|unknown|unverified)$/i.test(a.driverName) && !/registered owner/i.test(a.driverRelationship || '');
        return `<div class="alert-item">
          <div class="alert-line"><span class="plate plate-sm">${esc(a.plateNumber)}</span>
            <span>${esc(a.gatePoint)} · ${esc(fmtDateTime(a.reportedAt))}</span></div>
          <div class="alert-reason">Reason: ${esc(a.reason)}</div>
          ${stranger ? `<div class="alert-driver">Person at the gate: <strong>${esc(a.driverName)}</strong>${a.driverRelationship && a.driverRelationship !== 'Unverified' ? ' · ' + esc(a.driverRelationship) : ''}</div>` : ''}
          <div class="alert-case">Case ${esc(a.caseNumber)}</div>
          <div class="alert-clip">${clipButton({ logId: a.logId, plate: a.plateNumber, action: '', gatePoint: a.gatePoint, loggedAt: a.reportedAt }, 'Watch gate clip', 'on-red')}</div>
        </div>`;
      }).join('')}
      <p class="alert-help">Security is holding this vehicle. <strong>If you did not give anyone permission to drive it, tell the guard or the Campus Security Office right away.</strong></p>
      <button type="button" class="btn btn-light btn-sm" data-action="open-activity">See what happened</button>`;
    banner.hidden = false;
  }

  /* ---- Activity (audit log) ---- */
  const ACTIVITY = {
    'Entry Recorded': { cls: 'in',     title: 'Entered campus' },
    'Exit Approved':  { cls: 'out',    title: 'Left campus' },
    'Entry Denied':   { cls: 'denied', title: 'Entry refused' },
    'Exit Denied':    { cls: 'denied', title: 'Exit stopped at the gate' },
  };
  const ACTIVITY_ICON = {
    in: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    out: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
    denied: '<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>',
  };

  function renderActivity() {
    const tab = $('tabActivity');
    if (!data.vehicles.length) {
      tab.innerHTML = '<div class="card empty"><strong>No registered vehicle</strong>Gate activity appears here once your vehicle is registered.</div>';
      return;
    }
    const plates = data.vehicles.map(v => v.plateNumber);
    if (data.activityFilter !== 'all' && !plates.includes(data.activityFilter)) data.activityFilter = 'all';
    const chips = plates.length > 1
      ? `<div class="chips" role="group" aria-label="Filter by vehicle">
          <button type="button" class="chip" data-filter="all" aria-pressed="${data.activityFilter === 'all'}">All</button>
          ${plates.map(p => `<button type="button" class="chip" data-filter="${esc(p)}" aria-pressed="${data.activityFilter === p}">${esc(p)}</button>`).join('')}
        </div>`
      : '';

    const flags = [...data.alerts.active, ...data.alerts.recent]
      .filter(a => data.activityFilter === 'all' || normPlate(a.plateNumber) === normPlate(data.activityFilter));
    const flagCard = flags.length
      ? `<div class="card"><h2 class="card-title">Flags on your vehicle</h2><ul class="history">${flags.map(a => `
          <li>
            <div class="row1"><span class="type">${esc(a.reason)}</span><span class="date">${esc(fmtDateTime(a.reportedAt))}</span></div>
            <div class="desc">${esc(a.plateNumber)} · ${esc(a.gatePoint)}</div>
            <span class="badge ${a.status === 'Held' ? 'held' : esc(a.status.toLowerCase())}">${a.status === 'Held' ? 'ACTIVE · HELD' : esc(a.status)}</span>
            <span class="badge dismissed">${esc(a.caseNumber)}</span>
            ${a.resolvedAt ? `<div class="desc" style="color:var(--muted)">Closed ${esc(fmtDateTime(a.resolvedAt))}</div>` : ''}
            <div class="tl-actions">${clipButton({ logId: a.logId, plate: a.plateNumber, action: '', gatePoint: a.gatePoint, loggedAt: a.reportedAt }, 'Watch gate clip', 'danger')}</div>
          </li>`).join('')}</ul></div>`
      : '';

    const rows = data.activity.filter(a => data.activityFilter === 'all' || normPlate(a.plateNumber) === normPlate(data.activityFilter));
    let log;
    if (!rows.length) {
      log = '<p class="empty" style="padding:12px 0">No gate activity yet.</p>';
    } else {
      const groups = [];
      rows.forEach(a => {
        const key = String(a.loggedAt || '').slice(0, 10);
        let g = groups[groups.length - 1];
        if (!g || g.key !== key) { g = { key, items: [] }; groups.push(g); }
        g.items.push(a);
      });
      log = groups.map(g => `
        <h3 class="day-label">${esc(dayLabel(g.key))}</h3>
        <ul class="timeline">${g.items.map(a => {
          const t = ACTIVITY[a.action] || { cls: 'in', title: a.action };
          const driver = a.driverName && !/^unverified$/i.test(a.driverName)
            ? `Driver: ${esc(a.driverName)}${a.driverRelationship && !/^unverified$/i.test(a.driverRelationship) ? ' · ' + esc(a.driverRelationship) : ''}`
            : '';
          return `<li class="tl ${t.cls}">
            <span class="tl-icon" aria-hidden="true"><svg viewBox="0 0 24 24">${ACTIVITY_ICON[t.cls]}</svg></span>
            <div class="tl-body">
              <div class="tl-row"><span class="tl-title">${esc(t.title)}</span><span class="tl-time">${esc(fmtTime(a.loggedAt))}</span></div>
              <div class="tl-sub">${esc(a.plateNumber)} · ${esc(a.gatePoint || '')}</div>
              ${driver ? `<div class="tl-sub">${driver}</div>` : ''}
              ${a.note ? `<div class="tl-note">${esc(a.note)}</div>` : ''}
              <div class="tl-actions">${clipButton({ logId: a.id, plate: a.plateNumber, action: a.action, gatePoint: a.gatePoint, loggedAt: a.loggedAt }, null, t.cls === 'denied' ? 'danger' : '')}</div>
            </div></li>`;
        }).join('')}</ul>`).join('');
    }

    tab.innerHTML = `${chips}${flagCard}
      <div class="card"><h2 class="card-title">Gate activity</h2>${log}
        <p class="hint">Every time your vehicle enters, leaves or is stopped at a gate, it is recorded here with the driver who was verified by the guard.</p></div>`;
    tab.querySelectorAll('[data-filter]').forEach(c => c.addEventListener('click', () => { data.activityFilter = c.dataset.filter; renderActivity(); }));
  }

  /* ---- Violations ---- */
  function renderStrikes() {
    const standing = data.vehicles.map(v => `
      <div class="standing-row"><span class="plate" style="font-size:16px">${esc(v.plateNumber)}</span>
        <span class="hold-label ${v.isBanned ? 'on' : ''}">${v.isBanned ? 'On hold — cannot enter or leave' : 'Clear'}</span></div>`).join('');
    const cases = data.cases || [];
    const history = cases.length
      ? cases.map(c => `
          <div class="case-card" style="border:1px solid var(--line,#e2e8f0);border-radius:12px;padding:14px;margin-bottom:12px">
            <div class="row1"><span class="type">${esc(c.title)}</span><span class="date">${esc(fmtDateTime(c.openedAt))}</span></div>
            <div class="desc">${esc(c.plateNumber)}</div>
            <span class="badge ${c.status === 'Closed' ? 'resolved' : 'violation'}">${esc(c.step)}</span>
            <div class="desc" style="margin-top:8px"><strong>What to do:</strong> ${esc(c.nextStep)}</div>
            <ol style="list-style:none;margin:10px 0 0;padding:0;border-left:2px solid #e2e8f0">${c.timeline.map(t => `
              <li style="padding:0 0 8px 12px;font-size:13px"><span style="color:var(--muted)">${esc(fmtDateTime(t.at))}</span><br>${esc(t.label)}</li>`).join('')}</ol>
          </div>`).join('')
      : '<p class="empty" style="padding:12px 0">No cases. Your vehicles are in good standing.</p>';
    const anyHeld = data.vehicles.some(v => v.isBanned);
    const notices = (data.notices || []).length
      ? `<ul class="history">${data.notices.map(n => `
          <li>
            <div class="row1"><span class="type">${esc(n.title)}</span><span class="date">${esc(fmtDateTime(n.createdAt))}</span></div>
            <div class="desc">${esc(n.plateNumber)} · ${esc(n.message).replace(/\n/g, '<br>')}</div>
            <span class="badge ${n.kind === 'Violation' ? 'violation' : 'warning'}">${esc({ Violation: 'Violation', Reminder: 'Reminder', Expiry: 'Pass expiry' }[n.kind] || 'Blocked at gate')}</span>
            ${n.emailed ? '<span class="badge resolved">Also emailed to you</span>' : ''}
          </li>`).join('')}</ul>`
      : '<p class="empty" style="padding:12px 0">No notices.</p>';

    $('tabStrikes').innerHTML = `
      ${anyHeld ? '<div class="notice bad">A vehicle has an unresolved violation and cannot enter or leave campus. Visit the Campus Security Office to resolve it; the vehicle is released as soon as it is resolved.</div>' : ''}
      <div class="card"><h2 class="card-title">Vehicle status</h2>${standing || '<p class="hint">No vehicles.</p>'}
        <p class="hint">A vehicle with a pending violation cannot enter or leave campus until the Security Office resolves it.</p></div>
      <div class="card"><h2 class="card-title">Notices</h2>${notices}
        <p class="hint">You get a notice here, and an email when we have your address, whenever a vehicle of yours is blocked at the gate or given a violation.</p></div>
      <div class="card"><h2 class="card-title">Your cases</h2>${history}</div>`;
  }

  /* ---- Account ---- */
  function renderAccount() {
    const s = data.me.student;
    $('accountDetails').innerHTML = `
      <dt>Name</dt><dd>${esc(s.fullName)}</dd>
      <dt>ID number</dt><dd>${esc(s.ownerIdNumber)}</dd>
      <dt>Email</dt><dd>${esc(s.email || '—')}</dd>
      <dt>Vehicles</dt><dd>${data.me.summary.vehicles}</dd>`;
    const paid = (data.payments || []).filter(p => p.status === 'Paid');
    $('receiptsCard').hidden = !paid.length;
    $('receiptList').innerHTML = paid.map(p => `
      <li><div><div class="name">${esc(p.plateNumber)} \u00b7 ${peso(p.amount)}</div>
        <div class="sub">${esc(p.receiptNumber)} \u00b7 ${p.method === 'Cash' ? 'Cash at cashier' : 'Online'} \u00b7 ${esc(fmtDateTime(p.paidAt))}</div></div></li>`).join('');
  }

  /* ---------------- wiring ---------------- */
  document.addEventListener('DOMContentLoaded', () => {
    $('loginForm').addEventListener('submit', onLogin);
    $('firstPasswordForm').addEventListener('submit', onFirstPassword);
    $('passwordForm').addEventListener('submit', onPassword);
    document.querySelectorAll('[data-action="logout"]').forEach(b => b.addEventListener('click', logout));
    document.querySelectorAll('.tabbar-btn').forEach(b => b.addEventListener('click', () => selectTab(b.dataset.tab)));
    $('alertBanner').addEventListener('click', (e) => {
      if (e.target.closest('[data-action="open-activity"]')) selectTab('tabActivity');
    });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
    document.addEventListener('click', (e) => {
      const trigger = e.target.closest && e.target.closest('[data-clip]');
      if (!trigger) return;
      try { openClip(JSON.parse(decodeURIComponent(trigger.getAttribute('data-clip')))); } catch (_) { /* malformed descriptor: ignore */ }
    });
    $('clipClose').addEventListener('click', closeClip);
    $('clipModal').addEventListener('click', (e) => { if (e.target === $('clipModal')) closeClip(); });
    $('qrZoom').addEventListener('click', () => { $('qrZoom').hidden = true; });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { $('qrZoom').hidden = true; if (!$('clipModal').hidden) closeClip(); } });
    boot();
  });

  window.addEventListener('sp:signed-out', (e) => {
    showScreen('screenLogin');
    showError('loginError', e.detail && e.detail.message);
  });
  window.addEventListener('sp:password-change-required', () => showScreen('screenPassword'));
})();
