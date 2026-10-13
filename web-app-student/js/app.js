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
  const data = { me: null, vehicles: [], violations: [], cases: [], activity: [], alerts: { active: [], recent: [] }, selected: 0, activityFilter: 'all',
    af: { q: '', event: 'all', period: 'all', limit: 25 },                        // Activity filters
    cf: { q: '', status: 'all', type: 'all', plate: 'all', photos: false },        // Cases filters
    openCases: new Set(), seenCases: new Set() };                                  // which case rows are expanded
  const POLL_MS = 5000;
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
      if (StudentApi.hasToken() && err.status !== 401) {
        showScreen('screenApp');
        showInitialLoadError(err);
        return;
      }
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
    if (paymentCheckTimer) clearTimeout(paymentCheckTimer);
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
  function showInitialLoadError(err) {
    selectTab('tabPass');
    const tab = $('tabPass');
    tab.replaceChildren();
    const card = document.createElement('div');
    card.className = 'card empty';
    card.setAttribute('role', 'alert');
    const message = document.createElement('p');
    message.textContent = `Your information could not load. ${err.message || 'Please try again.'}`;
    const retry = document.createElement('button');
    retry.type = 'button';
    retry.className = 'btn btn-primary';
    retry.textContent = 'Try again';
    retry.addEventListener('click', () => enterApp());
    card.append(message, retry);
    tab.append(card);
  }

  async function enterApp() {
    showScreen('screenApp');
    selectTab('tabPass');
    $('tabPass').innerHTML = '<div class="card empty">Loading your pass&hellip;</div>';
    try {
      const [me, vehicles, violations, activity, alerts, payments, notices, cases] = await Promise.all([
        StudentApi.me(), StudentApi.vehicles(), StudentApi.violations(), StudentApi.activity(), StudentApi.alerts(), StudentApi.payments(), StudentApi.notices(), StudentApi.cases()
      ]);
      Object.assign(data, { me, vehicles, violations, activity, alerts, payments, notices, cases });
      data.selected = Math.min(data.selected, Math.max(vehicles.length - 1, 0));
      paintWho(me);
      renderAll(); startPolling(); handlePaymentReturn();
      return true;
    } catch (err) {
      if (err.status === 401 || !StudentApi.hasToken()) return false;
      showInitialLoadError(err);
      return false;
    }
  }

  /** The name in the top bar (phones) and in the sidebar account card (desktop), plus today's date. */
  function paintWho(me) {
    const s = me.student;
    $('topbarName').textContent = `${s.fullName} · ${s.ownerIdNumber}`;
    $('sidebarInitials').textContent = initials(s.fullName);
    $('sidebarName').textContent = s.fullName;
    $('sidebarId').textContent = `Owner ID · ${s.ownerIdNumber}`;
    $('topbarDate').textContent = new Date().toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', weekday: 'short', month: 'short', day: 'numeric' });
  }

  function renderAll() {
    // The tab badge counts every open case (violations and security cases), the same list the Cases tab shows
    const open = (data.cases || []).filter(c => c.status !== 'Closed').length;
    $('strikesBadge').textContent = String(open);
    $('strikesBadge').hidden = open === 0;
    $('strikesBadge').classList.add('is-blocked');
    // A refresh redraws the tabs: keep the cursor in a search box the owner is typing in
    const typing = document.activeElement && document.activeElement.matches && document.activeElement.matches('input.tb-input')
      ? { id: document.activeElement.id, start: document.activeElement.selectionStart, end: document.activeElement.selectionEnd } : null;
    renderAlerts();
    renderPass();
    renderActivity();
    renderStrikes();
    renderAccount();
    if (typing && $(typing.id)) { const el = $(typing.id); el.focus(); try { el.setSelectionRange(typing.start, typing.end); } catch (_) {} }
  }

  /* ---- Live refresh: a flag raised at the gate must reach the owner while it is happening ---- */
  function startPolling() {
    stopPolling();
    pollTimer = setInterval(refresh, POLL_MS);
  }

  window.addEventListener('online', () => refresh());

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
  }

  function syncStatus(state) {
    document.body.dataset.syncState = state;
    let banner = $('ownerSyncStatus');
    if (!banner) {
      banner = document.createElement('div'); banner.id = 'ownerSyncStatus';
      banner.setAttribute('role', 'status');
      banner.style.cssText = 'position:fixed;bottom:16px;left:50%;transform:translateX(-50%);z-index:60;padding:10px 16px;border-radius:8px;background:#fff5e8;color:#854d0e;font-size:13px;box-shadow:0 2px 8px #0002';
      document.body.append(banner);
    }
    banner.hidden = state === 'live';
    banner.textContent = 'Live updates are unavailable. Showing earlier information. Trying again…';
  }
  let refreshBusy = false, revisions = null;
  async function refresh() {
    if (!data.me || document.hidden || $('screenApp').hidden || refreshBusy) return;
    refreshBusy = true;
    try {
      const update = await StudentApi.updates();
      if (revisions && JSON.stringify(update.revisions) === JSON.stringify(revisions)) { syncStatus('live'); return; }
      const passChanged = !revisions || ['vehicles', 'cases', 'session'].some(k => update.revisions[k] !== revisions[k]);
      const [me, vehicles, violations, activity, alerts, payments, notices, cases] = await Promise.all([
        StudentApi.me(), StudentApi.vehicles(), StudentApi.violations(), StudentApi.activity(), StudentApi.alerts(), StudentApi.payments(), StudentApi.notices(), StudentApi.cases()
      ]);
      if ($('screenApp').hidden || !StudentApi.hasToken()) return;
      const known = new Set(data.alerts.active.map(a => a.id));
      const raised = alerts.active.filter(a => !known.has(a.id));
      Object.assign(data, {me, vehicles, violations, activity, alerts, payments, notices, cases});
      data.selected = Math.min(data.selected, Math.max(vehicles.length - 1, 0));
      paintWho(me);
      if (passChanged && !$('qrZoom').hidden) $('qrZoom').hidden = true;
      renderAll(); revisions = update.revisions;
      syncStatus('live');
      if (raised.length) notifyFlag(raised[0]);
    } catch (_) { syncStatus('offline'); }
    finally { refreshBusy = false; }
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
    $('screenApp').dataset.activeTab = tabId;
    window.scrollTo(0, 0);
  }

  /* ---- Shared pieces ---- */
  const ICON_WARN = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/></svg>';
  const ICON_TICK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7"/></svg>';

  /** A strip that tells the owner what is wrong and where to go. tone: 'bad' | 'warn'. */
  function attentionStrip(tone, title, text, action) {
    return `<div class="attention ${tone}" role="${tone === 'bad' ? 'alert' : 'status'}">
      <span class="attention-icon">${ICON_WARN}</span>
      <div class="attention-text"><strong>${esc(title)}</strong>${esc(text)}</div>
      ${action ? `<button type="button" class="btn btn-outline btn-sm" data-goto="${esc(action.tab)}">${esc(action.label)}</button>` : ''}
    </div>`;
  }

  function openCasesFor(v) {
    return (data.cases || []).filter(c => c.status !== 'Closed' && normPlate(c.plateNumber) === normPlate(v.plateNumber));
  }

  /** Renewal card: shown when the pass is inside the renewal window or already expired. */
  function renewalCard(v) {
    const r = v.renewal;
    if (!r || !r.due || r.blocker === 'This vehicle was retired.') return '';
    const when = r.expired
      ? `Your pass expired on ${fmtDate(v.passValidUntil)}.`
      : `Your pass expires on ${fmtDate(v.passValidUntil)} (${r.daysLeft} day${r.daysLeft === 1 ? '' : 's'} left).`;
    const tone = r.expired ? 'bad' : 'warn';
    const action = !r.eligible
      ? `<p class="hint">${esc(r.blocker || 'Renewal is not available right now.')}</p>`
      : r.fee > 0
        ? `<button type="button" class="btn btn-gold" data-action="renew">Renew for ${peso(r.fee)} online</button>
           <p class="hint">Or pay ${peso(r.fee)} at the cashier in the Campus Security Office. Your new pass appears here right after.</p>`
        : '<p class="hint"><strong>Renewal is free for this vehicle.</strong> Ask the Campus Security Office to renew it; your new pass appears here right after.</p>';
    return `<div class="card renew-card ${tone}">
      <h2 class="card-title">${r.expired ? 'Renew your pass' : 'Renew your pass soon'}</h2>
      <p class="card-sub">${esc(when)} ${r.expired ? 'Until it is renewed this vehicle cannot enter campus.' : 'Renew before then so your QR keeps working at the gate.'}</p>
      <dl class="renew-facts"><div><dt>New pass valid until</dt><dd>${esc(fmtDate(r.newValidUntil))}</dd></div><div><dt>Fee</dt><dd>${r.fee > 0 ? peso(r.fee) : 'No fee'}</dd></div></dl>
      ${action}
      <p class="hint" id="renewError" role="alert" hidden></p>
    </div>`;
  }

  /* ---- My Pass: detail cards ---- */
  const imgOk = (src) => /^(data:image\/|https?:\/\/)/i.test(String(src || ''));
  /** rows = [label, value] (null / '' hides the row); a value may be { html } for markup that is already escaped. */
  function infoList(rows) {
    const shown = rows.filter(r => r[1] !== null && r[1] !== undefined && r[1] !== '');
    return shown.length ? `<dl class="info-list">${shown.map(([k, val]) => `<div><dt>${esc(k)}</dt><dd>${val && val.html !== undefined ? val.html : esc(val)}</dd></div>`).join('')}</dl>` : '';
  }
  function validityText(v) {
    if (!v.passValidUntil) return null;
    const days = Math.round((new Date(`${v.passValidUntil}T12:00:00+08:00`) - new Date(`${manilaDay(0)}T12:00:00+08:00`)) / 86400000);
    const plural = (n) => `${n} day${n === 1 ? '' : 's'}`;
    const note = days < 0 ? `expired ${plural(-days)} ago` : days === 0 ? 'expires today' : `${plural(days)} left`;
    return `${fmtDate(v.passValidUntil)} (${note})`;
  }
  /** Pass, vehicle and owner in ONE compact card (two columns of facts) so the details are in view without scrolling far. */
  function detailsCard(v, st) {
    const vip = v.isVip || v.ownerRole === 'VIP';
    const fee = v.paymentStatus === 'Waived' ? 'No fee'
      : v.feeAmount > 0 ? `Paid ${peso(v.feeAmount)}${v.paidAt ? ' on ' + fmtDate(String(v.paidAt).slice(0, 10)) : ''}` : 'Paid';
    const mono = (t) => ({ html: `<span class="mono">${esc(t)}</span>` });
    const lastGate = v.lastEntryTime ? `${fmtDateTime(v.lastEntryTime)}${v.lastGatePoint && v.lastGatePoint !== '—' ? ' · ' + v.lastGatePoint : ''}` : null;
    return `<div class="card details-card">
      <section class="info-sec"><h3>Pass</h3>${infoList([
        ['Pass ID', v.passId ? mono(v.passId) : null],
        ['Valid until', validityText(v)],
        ['Registration fee', fee],
        ['Pass type', v.isVip ? 'VIP pass' : null],
        ['Registration', v.registrationStatus && v.registrationStatus !== 'Active' ? v.registrationStatus : null],   // the banner already says Active
      ])}</section>
      <section class="info-sec"><h3>Vehicle</h3>
        <div class="info-head">${imgOk(v.vehiclePhoto) ? `<img class="info-thumb" src="${esc(v.vehiclePhoto)}" alt="Photo of ${esc(v.plateNumber)}">` : ''}
          <div class="min-w-0"><div class="name">${esc(v.makeModelColor || v.vehicleType || v.plateNumber)}</div><div class="sub">${esc([v.vehicleType, v.stickerYear ? 'Sticker ' + v.stickerYear : ''].filter(Boolean).join(' · '))}</div></div></div>
        ${infoList([
          ['Registered on', v.registeredAt ? fmtDate(String(v.registeredAt).slice(0, 10)) : null],
          ['Last at the gate', lastGate],
        ])}</section>
      <section class="info-sec"><h3>Registered owner</h3>
        <div class="info-head">${imgOk(v.ownerPhoto) ? `<img class="info-thumb info-thumb-sq" src="${esc(v.ownerPhoto)}" alt="Photo of ${esc(v.ownerName)}">` : `<span class="owner-avatar">${esc(initials(v.ownerName))}</span>`}
          <div class="min-w-0"><div class="name">${esc(v.ownerName)}</div><div class="sub">${esc(vip ? 'VIP' : v.ownerRole || '')}</div></div></div>
        ${infoList([
          ['ID number', v.ownerIdNumber ? mono(v.ownerIdNumber) : null],
          ['Department / course', vip ? null : v.department],
          ['Contact phone', v.ownerPhone],
          ['Email', v.ownerEmail],
        ])}</section>
      <p class="hint">To change any of these details, visit the Campus Security Office.</p>
    </div>`;
  }
  function recentActivityCard(v) {
    const rows = (data.activity || []).filter(a => normPlate(a.plateNumber) === normPlate(v.plateNumber))
      .sort((a, b) => String(b.loggedAt).localeCompare(String(a.loggedAt))).slice(0, 4);
    if (!rows.length) return `<div class="card"><h2 class="card-title">Recent gate activity</h2><p class="hint">No gate activity yet. Entries and exits appear here as they happen.</p></div>`;
    return `<div class="card"><h2 class="card-title">Recent gate activity</h2>
      <ul class="act-mini">${rows.map(a => {
        const meta = ACTIVITY[a.action] || { cls: 'in', title: a.action };
        return `<li class="${meta.cls}"><svg viewBox="0 0 24 24" aria-hidden="true">${ACTIVITY_ICON[meta.cls]}</svg>
          <div><div class="name">${esc(meta.title)}</div><div class="sub">${esc(fmtDateTime(a.loggedAt))}${a.gatePoint ? ' · ' + esc(a.gatePoint) : ''}</div></div></li>`;
      }).join('')}</ul>
      <button type="button" class="btn btn-outline btn-sm" data-goto="tabActivity">See all activity</button></div>`;
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
    const cases = openCasesFor(v);
    const toCases = { tab: 'tabStrikes', label: cases.length > 1 ? 'View cases' : 'View case' };
    let attention = '';
    if (flags.length || v.isBanned || cases.length) {
      attention = attentionStrip('bad', 'This vehicle is on hold',
        `It cannot enter or leave campus until the Security Office closes ${cases.length > 1 ? `the ${cases.length} open cases` : 'the case'}. ${flags.length ? 'If you did not authorize what happened at the gate, tell the guard right away.' : ''}`.trim(), toCases);
    } else if (v.registrationStatus === 'Suspended') {
      attention = attentionStrip('bad', 'Registration suspended', 'Please visit the Campus Security Office.');
    } else if (v.passExpired) {
      attention = attentionStrip('warn', 'This pass has expired', v.renewal && v.renewal.eligible ? 'Renew it below, or at the Campus Security Office, to get a new QR pass.' : 'Renew your sticker at the Campus Security Office to get a new pass.');
    }

    tab.innerHTML = `
      ${chips}${attention}
      <div class="cols"><div class="col">
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
            <div><dt>Campus status</dt><dd>${(v.status || '').toLowerCase().includes('inside') ? '<span class="status-on">On Campus</span>' : '<span class="status-off">Outside Campus</span>'}</dd></div>
            <div><dt>Violations</dt><dd>${v.isBanned ? 'On hold (unresolved)' : v.isVip ? 'Not applied to VIP' : 'None pending'}</dd></div>
          </dl>
        </div>
      </article>
      </div><div class="col">
      ${renewalCard(v)}
      ${detailsCard(v, st)}
      ${recentActivityCard(v)}
      <div class="card">
        <h2 class="card-title">Authorized drivers</h2>
        <p class="card-sub">The only people the guard will let drive this vehicle through.</p>
        <ul class="drivers">
          ${(v.authorizedDrivers || []).map(d => `
            <li><span class="avatar">${esc(initials(d.fullName))}</span>
              <div><div class="name">${esc(d.fullName)}</div><div class="sub">${esc(d.relationship || '')}${d.licenseNo && d.licenseNo !== 'N/A' ? ' · License ' + esc(d.licenseNo) : ''}</div></div></li>`).join('')}
        </ul>
        ${(v.authorizedDrivers || []).length ? '' : '<p class="hint">No drivers are listed. Visit the Security Office to update this vehicle.</p>'}
        <p class="hint">${v.isVip ? 'VIP passes do not need a driver check. Vehicle changes are made at the Security Office.' : 'Only these people may drive this vehicle through the gate. Changes are made at the Security Office.'}</p>
      </div></div></div>`;

    if (typeof QRCode !== 'undefined' && v.qrPayload) {
      new QRCode($('passQr'), { text: v.qrPayload, width: 216, height: 216, colorDark: '#0F172A', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    }
    tab.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { data.selected = Number(c.dataset.index); renderPass(); }));
    $('passQr').addEventListener('click', () => openZoom(v));
    tab.querySelector('[data-action="zoom"]').addEventListener('click', () => openZoom(v));
    const renewBtn = tab.querySelector('[data-action="renew"]');
    if (renewBtn) renewBtn.addEventListener('click', (e) => startPayment(v, e.currentTarget, 'renewal'));
    tab.querySelector('[data-action="save"]').addEventListener('click', () => savePassImage(v));
  }

  /* ---- Registration fee: no pass until it is paid ---- */
  const peso = (n) => '\u20b1' + Number(n || 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function renderPaymentDue(tab, v, chips) {
    tab.innerHTML = `
      ${chips}
      <div class="cols"><div class="col">
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
      </div><div class="col">
        <div class="card gate-help"><h2 class="card-title">Two ways to pay</h2><ol>
          <li><span>1</span><div><strong>Online</strong><p>Pay with GCash, Maya or a card through PayMongo. Your pass is ready within moments of paying.</p></div></li>
          <li><span>2</span><div><strong>In person</strong><p>Go to the cashier at the Campus Security Office and give your plate number (${esc(v.plateNumber)}) or ID. Your pass appears here right after.</p></div></li>
        </ol></div>
      </div></div>`;
    tab.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => { data.selected = Number(c.dataset.index); renderPass(); }));
    tab.querySelector('[data-action="pay"]').addEventListener('click', (e) => startPayment(v, e.currentTarget));
  }

  async function startPayment(v, button, purpose) {
    const err = $(purpose === 'renewal' ? 'renewError' : 'payError');
    err.hidden = true;
    button.disabled = true;
    const label = button.textContent;
    button.textContent = 'Opening secure checkout\u2026';
    try {
      const r = await StudentApi.startPayment(v.id, location.origin + location.pathname, purpose);
      window.location.href = r.checkoutUrl;
    } catch (e) {
      err.textContent = e.message || 'Could not start the payment. Please try again.';
      err.hidden = false;
      button.disabled = false;
      button.textContent = label;
    }
  }

  /* Back from the PayMongo checkout (?payment=success|cancelled&p=<id>) */
  let paymentCheckTimer = null;
  let paymentPendingShown = false;
  async function handlePaymentReturn() {
    const params = new URLSearchParams(location.search);
    const outcome = params.get('payment');
    if (!outcome) return;
    const id = params.get('p');
    selectTab('tabPass');
    if (outcome !== 'success' || !id) {
      history.replaceState(null, '', location.pathname);
      paymentPendingShown = false;
      toast('Payment was cancelled. You can pay again anytime.');
      return;
    }
    if (!paymentCheckTimer) toast('Confirming your payment\u2026');
    paymentCheckTimer = null;
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
    } catch (_) { syncStatus('offline'); }
    if (payment && payment.status === 'Paid' && payment.purpose === 'Renewal') {
      history.replaceState(null, '', location.pathname);
      paymentPendingShown = false;
      const renewed = (data.vehicles || []).find(x => x.id === payment.vehicleId);
      toast(`Renewal paid (${payment.receiptNumber}). Your new pass is valid until ${fmtDate(renewed && renewed.passValidUntil)}.`, 'success');
    } else if (payment && payment.status === 'Paid') {
      history.replaceState(null, '', location.pathname);
      paymentPendingShown = false;
      toast(`Payment received (${payment.receiptNumber}). Your pass is ready.`, 'success');
    } else if (payment && payment.status === 'Cancelled') {
      history.replaceState(null, '', location.pathname);
      paymentPendingShown = false;
      toast('This checkout was cancelled. You can start a new payment when ready.');
    } else {
      if (!paymentPendingShown) toast('Payment confirmation is still pending. We will check again automatically.');
      paymentPendingShown = true;
      paymentCheckTimer = setTimeout(() => {
        if (StudentApi.hasToken()) handlePaymentReturn();
      }, 15000);
    }
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

  /* ---- Flag banner (all tabs): one line, details are in Cases and Activity ---- */
  function renderAlerts() {
    const active = data.alerts.active;
    const banner = $('alertBanner');
    const badge = $('activityBadge');
    badge.textContent = '!';
    badge.hidden = active.length === 0;
    document.title = active.length ? '⚠ Vehicle flagged · SecurePark' : DEFAULT_TITLE;
    if (!active.length) { banner.hidden = true; banner.innerHTML = ''; return; }
    const plates = [...new Set(active.map(a => a.plateNumber))];
    banner.innerHTML = attentionStrip('bad',
      plates.length === 1 ? `Security is holding ${plates[0]}` : `Security is holding ${plates.length} of your vehicles`,
      'It was stopped at a gate. If you did not give anyone permission to drive it, tell the guard or the Security Office right away.',
      { tab: 'tabStrikes', label: 'See what to do' });
    banner.hidden = false;
  }

  /* ---- Evidence photos: details arrive with each case / passage / flag, the pictures are fetched one at a time ---- */
  const EVIDENCE_KIND = { entry: 'Taken at entry', exit: 'Taken at exit', violation: 'Taken for the violation', incident: 'Taken when the vehicle was stopped' };
  const ICON_CAMERA = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg>';
  const evPhotos = new Map();   // id -> Promise of the photo (shared by every place that shows it)
  const evDone = new Map();     // id -> the photo once it has arrived
  let evActive = 0;
  const evQueue = [];

  function evidenceLabel(p) { return EVIDENCE_KIND[p.kind] || 'Photo from the gate'; }

  function evidenceGallery(list, label) {
    if (!list || !list.length) return '';
    return `<ul class="ev-grid" aria-label="${esc(label || 'Evidence photos')}">${list.map(p => `
      <li><button type="button" class="ev-thumb" data-ev="${p.id}" data-ev-label="${esc(evidenceLabel(p))}" data-ev-at="${esc(p.takenAt || '')}" aria-label="${esc(evidenceLabel(p))}. Tap to enlarge.">
        <span class="ev-load">Loading&hellip;</span></button>
        <span class="ev-cap">${esc(evidenceLabel(p))}<time>${esc(fmtDateTime(p.takenAt))}</time></span></li>`).join('')}</ul>`;
  }

  function evidenceBadge(list) {
    return list && list.length ? `<span class="ev-count" title="${list.length} photo${list.length === 1 ? '' : 's'} from the gate">${ICON_CAMERA}${list.length}</span>` : '<span class="dt-none">—</span>';
  }

  function paintThumb(btn, photo) {
    if (!btn.isConnected) return;
    if (!photo || photo.purged || !photo.image) {
      btn.classList.add('is-gone'); btn.disabled = true;
      btn.innerHTML = `<span class="ev-load">${photo && photo.purged ? 'Photo removed after the retention period' : 'Photo unavailable'}</span>`;
      return;
    }
    btn.innerHTML = '';
    const img = document.createElement('img');
    img.alt = btn.dataset.evLabel || 'Evidence photo';
    img.src = photo.image;
    btn.appendChild(img);
  }

  function fetchEvidence(id) {
    if (!evPhotos.has(id)) {
      evPhotos.set(id, StudentApi.evidence(id).then(p => { evDone.set(id, p); return p; }).catch(err => { evPhotos.delete(id); throw err; }));
    }
    return evPhotos.get(id);
  }

  function pumpEvidence() {
    while (evActive < 3 && evQueue.length) {
      const btn = evQueue.shift();
      if (!btn.isConnected) continue;
      evActive++;
      fetchEvidence(Number(btn.dataset.ev)).then(p => paintThumb(btn, p), () => paintThumb(btn, null)).finally(() => { evActive--; pumpEvidence(); });
    }
  }

  /** Fills every photo placeholder under root: from memory at once when it was seen before, otherwise three at a time. */
  function loadEvidenceThumbs(root) {
    root.querySelectorAll('.ev-thumb:not([data-state])').forEach(btn => {
      btn.dataset.state = '1';
      const done = evDone.get(Number(btn.dataset.ev));
      if (done) paintThumb(btn, done); else evQueue.push(btn);
    });
    pumpEvidence();
  }

  function openEvidence(btn) {
    const photo = evDone.get(Number(btn.dataset.ev));
    if (!photo || !photo.image) return;
    $('evImage').src = photo.image;
    $('evTitle').textContent = btn.dataset.evLabel || 'Evidence photo';
    $('evSub').textContent = btn.dataset.evAt ? fmtDateTime(btn.dataset.evAt) : '';
    $('evModal').hidden = false;
  }
  function closeEvidence() { $('evModal').hidden = true; $('evImage').removeAttribute('src'); }

  /* ---- Shared filter controls ---- */
  function chipRow(label, name, options, current) {
    return `<div class="chips" role="group" aria-label="${esc(label)}">${options.map(o =>
      `<button type="button" class="chip" data-${name}="${esc(o.value)}" aria-pressed="${current === o.value}">${esc(o.label)}${o.count != null ? ` <span class="chip-n">${o.count}</span>` : ''}</button>`).join('')}</div>`;
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
  const PERIODS = [{ value: 'all', label: 'All time' }, { value: 'today', label: 'Today' }, { value: '7', label: 'Last 7 days' }, { value: '30', label: 'Last 30 days' }];
  const ACTIVITY_PAGE = 25;

  const activityClass = (a) => (ACTIVITY[a.action] || { cls: 'in' }).cls;

  function inPeriod(at, period) {
    if (period === 'all') return true;
    const day = String(at || '').slice(0, 10);
    if (period === 'today') return day === manilaDay(0);
    return day >= manilaDay(period === '7' ? -6 : -29);
  }

  function matchesText(q, parts) {
    const needle = q.trim().toLowerCase();
    return !needle || parts.some(p => String(p || '').toLowerCase().includes(needle));
  }

  function plateOk(plate) { return data.activityFilter === 'all' || normPlate(plate) === normPlate(data.activityFilter); }

  function activityBase() {
    const f = data.af;
    return data.activity.filter(a => plateOk(a.plateNumber) && inPeriod(a.loggedAt, f.period)
      && matchesText(f.q, [a.plateNumber, a.gatePoint, a.driverName, a.note, (ACTIVITY[a.action] || {}).title]));
  }

  function renderActivity() {
    const tab = $('tabActivity');
    if (!data.vehicles.length) {
      tab.innerHTML = '<div class="card empty"><strong>No registered vehicle</strong>Gate activity appears here once your vehicle is registered.</div>';
      return;
    }
    const plates = data.vehicles.map(v => v.plateNumber);
    if (data.activityFilter !== 'all' && !plates.includes(data.activityFilter)) data.activityFilter = 'all';
    const f = data.af;
    const base = activityBase();
    const n = (cls) => base.filter(a => activityClass(a) === cls).length;
    const vehicleChips = plates.length > 1
      ? chipRow('Filter by vehicle', 'filter', [{ value: 'all', label: 'All vehicles' }, ...plates.map(p => ({ value: p, label: p }))], data.activityFilter) : '';
    const filtered = !!(f.q || f.event !== 'all' || f.period !== 'all' || data.activityFilter !== 'all');

    tab.innerHTML = `<div class="tab-wide col">
      <div class="card toolbar">
        <div class="tb-row">
          <label class="tb-search"><span class="sr-only">Search activity</span>
            <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>
            <input id="actSearch" type="search" class="tb-input" placeholder="Search gate, driver or note" value="${esc(f.q)}" autocomplete="off"></label>
          <label class="tb-select"><span class="sr-only">Period</span>
            <select id="actPeriod" class="tb-input">${PERIODS.map(p => `<option value="${p.value}"${f.period === p.value ? ' selected' : ''}>${p.label}</option>`).join('')}</select></label>
          ${filtered ? '<button type="button" class="tb-clear" id="actClear">Clear filters</button>' : ''}
        </div>
        ${vehicleChips}
        ${chipRow('Filter by event', 'event', [
          { value: 'all', label: 'All', count: base.length }, { value: 'in', label: 'Entries', count: n('in') },
          { value: 'out', label: 'Exits', count: n('out') }, { value: 'denied', label: 'Refused', count: n('denied') }], f.event)}
      </div>
      <div id="actResults" class="col"></div></div>`;

    $('actSearch').addEventListener('input', (e) => { data.af.q = e.target.value; data.af.limit = ACTIVITY_PAGE; renderActivityResults(); });
    $('actPeriod').addEventListener('change', (e) => { data.af.period = e.target.value; data.af.limit = ACTIVITY_PAGE; renderActivity(); });
    $('actClear')?.addEventListener('click', () => { data.af = { q: '', event: 'all', period: 'all', limit: ACTIVITY_PAGE }; data.activityFilter = 'all'; renderActivity(); });
    tab.querySelectorAll('[data-filter]').forEach(c => c.addEventListener('click', () => { data.activityFilter = c.dataset.filter; data.af.limit = ACTIVITY_PAGE; renderActivity(); }));
    tab.querySelectorAll('[data-event]').forEach(c => c.addEventListener('click', () => { data.af.event = c.dataset.event; data.af.limit = ACTIVITY_PAGE; renderActivity(); }));
    renderActivityResults();
  }

  function renderActivityResults() {
    const host = $('actResults');
    if (!host) return;
    const f = data.af;
    const rows = activityBase().filter(a => f.event === 'all' || activityClass(a) === f.event);

    const flags = [...data.alerts.active, ...data.alerts.recent].filter(a => plateOk(a.plateNumber) && inPeriod(a.reportedAt, f.period)
      && matchesText(f.q, [a.plateNumber, a.gatePoint, a.reason, a.caseNumber, a.driverName]));
    const flagTable = flags.length ? `<div class="card table-card">
        <h2 class="card-title">Stopped at the gate</h2><p class="card-sub">Times a guard held your vehicle. The case itself, and what to do, is on the Cases tab.</p>
        <div class="dt-wrap"><table class="dt"><thead><tr><th>Reported</th><th>Reason</th><th>Vehicle</th><th>Gate</th><th>Status</th><th>Evidence</th></tr></thead><tbody>
        ${flags.map(a => `<tr>
          <td data-label="Reported"><div class="dt-strong">${esc(fmtDateTime(a.reportedAt))}</div>${a.resolvedAt ? `<div class="dt-sub">Closed ${esc(fmtDateTime(a.resolvedAt))}</div>` : ''}</td>
          <td data-label="Reason"><div class="dt-strong">${esc(a.reason)}</div><div class="dt-sub">${esc(a.caseNumber)}</div></td>
          <td data-label="Vehicle"><span class="plate">${esc(a.plateNumber)}</span></td>
          <td data-label="Gate">${esc(a.gatePoint || '')}</td>
          <td data-label="Status"><span class="status-pill ${a.status === 'Held' ? 'bad' : 'ok'}">${a.status === 'Held' ? 'Held' : esc(a.status)}</span></td>
          <td data-label="Evidence">${evidenceGallery(a.evidence, 'Evidence photos for ' + a.caseNumber)}
            <div class="tl-actions">${clipButton({ logId: a.logId, plate: a.plateNumber, action: '', gatePoint: a.gatePoint, loggedAt: a.reportedAt }, 'Watch gate clip', 'danger')}</div></td>
        </tr>`).join('')}</tbody></table></div></div>` : '';

    let log;
    if (!rows.length) {
      log = `<div class="dt-empty"><strong>${data.activity.length ? 'No activity matches these filters' : 'No gate activity yet'}</strong>
        ${data.activity.length ? '<button type="button" class="tb-clear" data-clear="activity">Clear filters</button>' : 'Entries and exits appear here as they happen.'}</div>`;
    } else {
      const shown = rows.slice(0, f.limit);
      let body = '', day = null;
      shown.forEach(a => {
        const key = String(a.loggedAt || '').slice(0, 10);
        if (key !== day) { day = key; body += `<tr class="dt-day"><th colspan="6" scope="colgroup">${esc(dayLabel(key))}</th></tr>`; }
        const t = ACTIVITY[a.action] || { cls: 'in', title: a.action };
        const hasDriver = a.driverName && !/^unverified$/i.test(a.driverName);
        const rel = a.driverRelationship && !/^unverified$/i.test(a.driverRelationship) ? a.driverRelationship : '';
        body += `<tr class="act-${t.cls}">
          <td data-label="Time"><span class="dt-strong">${esc(fmtTime(a.loggedAt))}</span></td>
          <td data-label="Event"><span class="ev-pill ${t.cls}"><svg viewBox="0 0 24 24" aria-hidden="true">${ACTIVITY_ICON[t.cls]}</svg>${esc(t.title)}</span></td>
          <td data-label="Vehicle"><span class="plate">${esc(a.plateNumber)}</span></td>
          <td data-label="Gate">${esc(a.gatePoint || '—')}</td>
          <td data-label="Driver">${hasDriver ? `<div class="dt-strong">${esc(a.driverName)}</div>${rel ? `<div class="dt-sub">${esc(rel)}</div>` : ''}` : '<span class="dt-none">—</span>'}</td>
          <td data-label="Details">${a.note ? `<div class="tl-note">${esc(a.note)}</div>` : ''}${evidenceGallery(a.evidence, 'Photos from this passage')}
            <div class="tl-actions">${clipButton({ logId: a.id, plate: a.plateNumber, action: a.action, gatePoint: a.gatePoint, loggedAt: a.loggedAt }, null, t.cls === 'denied' ? 'danger' : '')}</div></td>
        </tr>`;
      });
      log = `<div class="dt-wrap"><table class="dt"><thead><tr><th>Time</th><th>Event</th><th>Vehicle</th><th>Gate</th><th>Driver</th><th>Details</th></tr></thead><tbody>${body}</tbody></table></div>
        <div class="dt-foot"><span>Showing ${shown.length} of ${rows.length}</span>${rows.length > shown.length ? '<button type="button" class="btn btn-outline btn-sm" data-more="activity">Show more</button>' : ''}</div>`;
    }

    host.innerHTML = `${flagTable}<div class="card table-card"><h2 class="card-title">Entries and exits</h2><p class="card-sub">Newest first, with the driver the guard verified.</p>${log}</div>`;
    host.querySelector('[data-more="activity"]')?.addEventListener('click', () => { data.af.limit += ACTIVITY_PAGE; renderActivityResults(); });
    host.querySelector('[data-clear="activity"]')?.addEventListener('click', () => { data.af = { q: '', event: 'all', period: 'all', limit: ACTIVITY_PAGE }; data.activityFilter = 'all'; renderActivity(); });
    loadEvidenceThumbs(host);
  }

  /* ---- Cases ---- */
  const CASE_STEPS = ['Reported', 'Owner contacted', 'Awaiting clearance', 'Closed'];
  const CASE_TYPES = [{ value: 'all', label: 'All types' }, { value: 'Violation', label: 'Violation' }, { value: 'Security', label: 'Security' }, { value: 'Overnight', label: 'Overnight parking' }];

  function caseStage(c) {
    if (c.status === 'Closed') return 4;
    if (c.status === 'Awaiting clearance') return 3;
    return (c.policeReferred || c.contactAttempts > 0) ? 2 : 1;
  }

  const casePill = (c) => c.status === 'Closed' ? ['ok', 'Closed'] : c.status === 'Awaiting clearance' ? ['warn', 'Awaiting clearance'] : ['bad', 'Open'];

  function caseDetail(c) {
    const closed = c.status === 'Closed';
    const stage = caseStage(c);
    const steps = CASE_STEPS.map((label, i) => {
      const n = i + 1;
      const cls = n < stage || (n === stage && closed) ? 'done' : n === stage ? 'current' : '';
      return `<li class="${cls}${n === 4 ? ' final' : ''}"${n === stage ? ' aria-current="step"' : ''}>${esc(label)}</li>`;
    }).join('');
    const ev = c.evidence || [];
    return `<div class="case-detail">
      <div class="case-detail-main">
        <ol class="steps" aria-label="Case progress">${steps}</ol>
        ${c.policeReferred && !closed ? '<span class="flag-police">Referred to the police</span>' : ''}
        ${closed
          ? `<p class="case-outcome"><strong>Outcome:</strong> ${esc(c.outcome || 'Closed')}. Your vehicle can enter and leave campus again unless another case is open.</p>`
          : `<div class="next-step"><strong>What to do</strong><p>${esc(c.nextStep)}</p></div>`}
        <h4 class="mini-title">What happened</h4>
        <ol class="case-timeline">${c.timeline.map(t => `<li>${esc(t.label)}<time>${esc(fmtDateTime(t.at))}</time></li>`).join('')}</ol>
      </div>
      <div class="case-detail-side">
        <h4 class="mini-title">Evidence${ev.length ? ` (${ev.length})` : ''}</h4>
        ${ev.length
          ? `${evidenceGallery(ev, 'Evidence photos for ' + c.title)}<p class="hint">Photos the guard took at the gate. Tap one to enlarge it.</p>`
          : '<p class="hint">No photos were attached to this case.</p>'}
      </div>
    </div>`;
  }

  function caseMatches(c) {
    const f = data.cf;
    if (f.status === 'open' && c.status !== 'Open') return false;
    if (f.status === 'awaiting' && c.status !== 'Awaiting clearance') return false;
    if (f.status === 'closed' && c.status !== 'Closed') return false;
    if (f.type !== 'all' && c.type !== f.type) return false;
    if (f.plate !== 'all' && normPlate(c.plateNumber) !== normPlate(f.plate)) return false;
    if (f.photos && !(c.evidence || []).length) return false;
    return matchesText(f.q, [c.title, c.plateNumber, c.reference, c.type, c.outcome]);
  }

  function renderCaseResults() {
    const host = $('caseResults');
    if (!host) return;
    const rows = (data.cases || []).filter(caseMatches);
    if (!rows.length) {
      host.innerHTML = `<div class="dt-empty">${(data.cases || []).length
        ? '<strong>No cases match these filters</strong><button type="button" class="tb-clear" data-clear="cases">Clear filters</button>'
        : `<div class="tick">${ICON_TICK}</div><strong>No cases</strong>Your vehicles are in good standing and can enter and leave campus normally.`}</div>`;
    } else {
      host.innerHTML = `<div class="dt-wrap"><table class="dt dt-cases"><thead><tr><th>Case</th><th>Vehicle</th><th>Opened</th><th>Status</th><th>Evidence</th><th><span class="sr-only">Details</span></th></tr></thead><tbody>
        ${rows.map(c => {
          const open = data.openCases.has(c.key);
          const pill = casePill(c);
          return `<tr class="dt-row case-row${open ? ' is-open' : ''}${c.status === 'Closed' ? '' : ' is-active'}" data-case="${esc(c.key)}">
            <td data-label="Case"><button type="button" class="dt-toggle" aria-expanded="${open}"><span class="dt-strong">${esc(c.title)}</span></button>
              <div class="dt-sub">${esc(c.reference || '')}${c.reference ? ' · ' : ''}${esc(c.type)}</div></td>
            <td data-label="Vehicle"><span class="plate">${esc(c.plateNumber)}</span></td>
            <td data-label="Opened"><div class="dt-strong">${esc(fmtDateTime(c.openedAt))}</div>${c.status === 'Closed' ? `<div class="dt-sub">Closed ${esc(fmtDateTime(c.closedAt))}</div>` : ''}</td>
            <td data-label="Status"><span class="status-pill ${pill[0]}">${esc(pill[1])}</span></td>
            <td data-label="Evidence">${evidenceBadge(c.evidence)}</td>
            <td class="dt-chev" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg></td>
          </tr>${open ? `<tr class="dt-detail"><td colspan="6">${caseDetail(c)}</td></tr>` : ''}`;
        }).join('')}</tbody></table></div>
        <div class="dt-foot"><span>Showing ${rows.length} of ${data.cases.length}</span></div>`;
    }
    host.querySelectorAll('[data-case]').forEach(tr => tr.addEventListener('click', (e) => {
      if (e.target.closest('.ev-thumb, a')) return;
      const key = tr.dataset.case;
      if (data.openCases.has(key)) data.openCases.delete(key); else data.openCases.add(key);
      renderCaseResults();
    }));
    host.querySelector('[data-clear="cases"]')?.addEventListener('click', () => { data.cf = { q: '', status: 'all', type: 'all', plate: 'all', photos: false }; renderStrikes(); });
    loadEvidenceThumbs(host);
  }

  function noticeItem(n) {
    const label = { Violation: 'Violation', Reminder: 'Reminder', Expiry: 'Pass expiry' }[n.kind] || 'Blocked at gate';
    return `<li class="notice-item">
      <h3>${esc(n.title)}</h3><time>${esc(fmtDateTime(n.createdAt))} · ${esc(n.plateNumber)}</time>
      <p>${esc(n.message).replace(/\n/g, '<br>')}</p>
      <div class="notice-tags"><span class="badge ${n.kind === 'Violation' ? 'violation' : 'warning'}">${esc(label)}</span>${n.emailed ? '<span class="badge resolved">Also e-mailed to you</span>' : ''}</div>
    </li>`;
  }

  function renderStrikes() {
    const cases = data.cases || [];
    const open = cases.filter(c => c.status !== 'Closed');
    const notices = data.notices || [];
    // Open cases start expanded, so their evidence is the first thing the owner sees; closed ones start folded
    cases.forEach(c => { if (!data.seenCases.has(c.key)) { data.seenCases.add(c.key); if (c.status !== 'Closed') data.openCases.add(c.key); } });

    const standing = data.vehicles.length ? data.vehicles.map(v => {
      const n = openCasesFor(v).length;
      const held = v.isBanned || n > 0 || activeAlertsFor(v).length > 0;
      return `<div class="standing-row"><span class="plate" style="font-size:16px">${esc(v.plateNumber)}</span>
        <span class="status-pill ${held ? 'bad' : 'ok'}">${held ? (n ? `On hold · ${n} open case${n === 1 ? '' : 's'}` : 'On hold') : 'Clear to enter and leave'}</span></div>`;
    }).join('') : '<p class="hint">No vehicles registered.</p>';

    const shown = notices.slice(0, 4);
    const older = notices.slice(4);
    const noticesHtml = notices.length
      ? `<ul class="notice-list">${shown.map(noticeItem).join('')}</ul>${older.length ? `<details class="fold" style="padding:12px 0 0"><summary>Older notices (${older.length})</summary><ul class="notice-list" style="margin-top:8px">${older.map(noticeItem).join('')}</ul></details>` : ''}`
      : '<p class="hint">No notices yet.</p>';

    const f = data.cf;
    const count = (fn) => cases.filter(fn).length;
    const platesInCases = [...new Set([...data.vehicles.map(v => v.plateNumber), ...cases.map(c => c.plateNumber)])];
    const filtered = !!(f.q || f.status !== 'all' || f.type !== 'all' || f.plate !== 'all' || f.photos);
    const withPhotos = count(c => (c.evidence || []).length);

    $('tabStrikes').innerHTML = `
      <div class="col cases-page">
          <section aria-labelledby="openCasesTitle">
            <h2 id="openCasesTitle" class="section-title">Cases <span class="count ${open.length ? 'bad' : ''}">${open.length} open</span></h2>
            <div class="card toolbar">
              <div class="tb-row">
                <label class="tb-search"><span class="sr-only">Search cases</span>
                  <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>
                  <input id="caseSearch" type="search" class="tb-input" placeholder="Search by case, plate or reference" value="${esc(f.q)}" autocomplete="off"></label>
                <label class="tb-select"><span class="sr-only">Type</span>
                  <select id="caseType" class="tb-input">${CASE_TYPES.map(t => `<option value="${t.value}"${f.type === t.value ? ' selected' : ''}>${t.label}</option>`).join('')}</select></label>
                ${platesInCases.length > 1 ? `<label class="tb-select"><span class="sr-only">Vehicle</span>
                  <select id="casePlate" class="tb-input"><option value="all">All vehicles</option>${platesInCases.map(p => `<option value="${esc(p)}"${f.plate === p ? ' selected' : ''}>${esc(p)}</option>`).join('')}</select></label>` : ''}
              </div>
              <div class="tb-row tb-row-chips">
                ${chipRow('Filter by status', 'cstatus', [
                  { value: 'all', label: 'All', count: cases.length }, { value: 'open', label: 'Open', count: count(c => c.status === 'Open') },
                  { value: 'awaiting', label: 'Awaiting clearance', count: count(c => c.status === 'Awaiting clearance') }, { value: 'closed', label: 'Closed', count: count(c => c.status === 'Closed') }], f.status)}
                <button type="button" class="chip" id="casePhotos" aria-pressed="${f.photos}">${ICON_CAMERA}With photos <span class="chip-n">${withPhotos}</span></button>
                ${filtered ? '<button type="button" class="tb-clear" id="caseClear">Clear filters</button>' : ''}
              </div>
            </div>
            <div class="card table-card"><div id="caseResults"></div></div>
          </section>
          <div class="cases-aside">
            <section class="card"><h2 class="card-title">Your vehicles</h2><p class="card-sub">A vehicle with an open case cannot enter or leave campus.</p><div class="standing-list">${standing}</div></section>
            <section class="card"><h2 class="card-title">Notices</h2><p class="card-sub">We post here, and e-mail you when we have your address.</p>${noticesHtml}</section>
          </div>
      </div>`;

    $('caseSearch').addEventListener('input', (e) => { data.cf.q = e.target.value; renderCaseResults(); });
    $('caseType').addEventListener('change', (e) => { data.cf.type = e.target.value; renderStrikes(); });
    $('casePlate')?.addEventListener('change', (e) => { data.cf.plate = e.target.value; renderStrikes(); });
    $('casePhotos').addEventListener('click', () => { data.cf.photos = !data.cf.photos; renderStrikes(); });
    $('caseClear')?.addEventListener('click', () => { data.cf = { q: '', status: 'all', type: 'all', plate: 'all', photos: false }; renderStrikes(); });
    $('tabStrikes').querySelectorAll('[data-cstatus]').forEach(c => c.addEventListener('click', () => { data.cf.status = c.dataset.cstatus; renderStrikes(); }));
    renderCaseResults();
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
      <li><div><div class="name">${esc(p.plateNumber)} \u00b7 ${peso(p.amount)}${p.purpose === 'Renewal' ? ' \u00b7 Pass renewal' : ''}</div>
        <div class="sub">${esc(p.receiptNumber)} \u00b7 ${p.method === 'Cash' ? 'Cash at cashier' : 'Online'} \u00b7 ${esc(fmtDateTime(p.paidAt))}</div></div></li>`).join('');
  }

  /* ---------------- wiring ---------------- */
  document.addEventListener('DOMContentLoaded', () => {
    $('loginForm').addEventListener('submit', onLogin);
    $('firstPasswordForm').addEventListener('submit', onFirstPassword);
    $('passwordForm').addEventListener('submit', onPassword);
    document.querySelectorAll('[data-action="logout"]').forEach(b => b.addEventListener('click', logout));
    document.querySelectorAll('.tabbar-btn').forEach(b => b.addEventListener('click', () => selectTab(b.dataset.tab)));
    document.addEventListener('click', (e) => {
      const go = e.target.closest && e.target.closest('[data-goto]');
      if (go) selectTab(go.dataset.goto);
    });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
    document.addEventListener('click', (e) => {
      const trigger = e.target.closest && e.target.closest('[data-clip]');
      if (!trigger) return;
      try { openClip(JSON.parse(decodeURIComponent(trigger.getAttribute('data-clip')))); } catch (_) { /* malformed descriptor: ignore */ }
    });
    document.addEventListener('click', (e) => {
      const thumb = e.target.closest && e.target.closest('.ev-thumb');
      if (thumb) openEvidence(thumb);
    });
    $('evClose').addEventListener('click', closeEvidence);
    $('evModal').addEventListener('click', (e) => { if (e.target === $('evModal')) closeEvidence(); });
    $('clipClose').addEventListener('click', closeClip);
    $('clipModal').addEventListener('click', (e) => { if (e.target === $('clipModal')) closeClip(); });
    $('qrZoom').addEventListener('click', () => { $('qrZoom').hidden = true; });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { $('qrZoom').hidden = true; if (!$('clipModal').hidden) closeClip(); if (!$('evModal').hidden) closeEvidence(); } });
    boot();
  });

  window.addEventListener('sp:signed-out', (e) => {
    showScreen('screenLogin');
    showError('loginError', e.detail && e.detail.message);
  });
  window.addEventListener('sp:password-change-required', () => showScreen('screenPassword'));
})();
