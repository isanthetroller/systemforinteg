/**
 * SecurePark - Gate Monitor (Ingress / Egress verification)
 *
 * Flow: choose direction -> scan (camera / USB / paste) or type a plate -> verify.php
 * checks signature, validity, bans -> guard selects the driver behind the wheel ->
 * Approve (Entry Recorded / Exit Approved) or Deny (logged + incident).
 * Rejections decided by the server are logged automatically by verify.php.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const MODE_KEY = 'sp_gate_mode';
  const QR_LIB = 'https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js';
  const DENY_REASONS = [
    'Unauthorized / Unregistered Driver',
    'Plate & Vehicle Profile Mismatch',
    'Expired Campus Parking Sticker',
    'Invalid / Revoked QR Pass',
    'Security Officer Intervention',
    'Suspicious behavior',
    'Other'
  ];
  const DENY_LABELS = ['Driver is not allowed', 'Plate does not match the vehicle', 'Parking sticker has expired', 'QR pass is invalid or cancelled', 'Stopped by a security officer', 'Suspicious behavior', 'Other'];
  // After an anti-passback refusal the guard reports that the record looks wrong (the same list the phone offers)
  function reportReasons(result) {
    return [
      result === 'NOT_ON_CAMPUS' ? 'Vehicle is on campus (entry was not scanned)' : 'Vehicle already left (exit was not scanned)',
      'Pass used by another vehicle or driver', 'Plate & Vehicle Profile Mismatch', 'Unauthorized / Unregistered Driver', 'Suspicious behavior', 'Other'
    ];
  }
  const PASSBACK = ['ALREADY_INSIDE', 'NOT_ON_CAMPUS'];

  const gate = {
    mode: readMode(),
    policy: null,
    checkpoint: 'Gate 1',
    policyError: null,
    input: '',          // raw scanned / typed value of the current verification
    result: null,       // verify.php response data
    driverId: null,     // selected authorized driver id
    itemsChecked: false, // guard confirmed a visitor's declared items
    lookup: 'manual',    // how the guard identified the vehicle: qr (camera / scanner) or manual (typed)
    photos: {},          // optional photo fields of the current check (approve / deny / report), kept while the card redraws
    decisionRef: null, // stable across a manual retry when a write's reply is lost
    busy: false,
    cctv: null,
    scanner: null,      // Html5Qrcode instance
    cameraOn: false,
    cameras: [],         // available cameras, for Flip
    cameraIndex: 0
  };

  function readMode() {
    try { return sessionStorage.getItem(MODE_KEY) === 'Egress' ? 'Egress' : 'Ingress'; } catch (_) { return 'Ingress'; }
  }

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  function initials(name) {
    return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0].toUpperCase()).join('') || '?';
  }

  function photoHtml(src, name, size = 'w-14 h-14') {
    const clean = typeof src === 'string' ? src.trim() : '';
    const safe = /^(data:image\/|https?:\/\/|\/|[\w./-]+$)/i.test(clean) ? clean : '';
    const fallback = `<div class="${size} rounded-md bg-slate-200 text-slate-600 font-extrabold text-sm flex items-center justify-center flex-shrink-0">${esc(initials(name))}</div>`;
    if (!safe) return fallback;
    // A broken image collapses to the initials tile underneath it
    return `<div class="relative ${size} flex-shrink-0">${fallback.replace('flex-shrink-0', 'absolute inset-0')}<img src="${esc(safe)}" alt="Photo of ${esc(name)}" class="absolute inset-0 ${size} rounded-md object-cover border border-slate-200 bg-slate-100" onerror="this.remove()"></div>`;
  }

  /* ------------------------------------------------------------------------
     Direction toggle
     ------------------------------------------------------------------------ */
  function renderMode() {
    document.querySelectorAll('#gateModeToggle .gate-mode-btn').forEach(btn => {
      const active = btn.dataset.mode === gate.mode;
      btn.disabled = !gate.policy?.allowedDirections.includes(btn.dataset.mode);
      btn.classList.remove('hidden');
      btn.setAttribute('aria-checked', active ? 'true' : 'false');
      btn.className = 'gate-mode-btn' + (btn.classList.contains('hidden') ? ' hidden' : '');
    });
    if (gate.cctv) {
      gate.cctv.setLane(gate.mode === 'Ingress' ? 'ENTRY GATE - LANE 1' : 'EXIT GATE - LANE 2');
    }
    const btn = $('gateVerifyBtn');
    if (btn) {
      btn.textContent = gate.mode === 'Ingress' ? 'Check Entry' : 'Check Exit';
      if (gate.mode === 'Ingress') {
        btn.classList.remove('bg-ncst-navy', 'hover:bg-ncst-navyDark');
        btn.classList.add('bg-ncst-green', 'hover:bg-ncst-greenDark');
      } else {
        btn.classList.remove('bg-ncst-green', 'hover:bg-ncst-greenDark');
        btn.classList.add('bg-ncst-navy', 'hover:bg-ncst-navyDark');
      }
    }
    $('gateModeHint').textContent = gate.policy ? `${gate.policy.modeLabel} · ${gate.policy.checkpoint} · ${gate.policy.message}` : (gate.policyError || 'Loading gate permissions…');
    if (btn) btn.disabled = !gate.policy?.allowedDirections.includes(gate.mode);
  }

  let policyGeneration = 0;
  async function refreshPolicy() {
    const generation = ++policyGeneration;
    try {
      const policy = await ApiClient.getGatePolicy(gate.checkpoint);
      if (generation !== policyGeneration) return;
      gate.policy = policy;
      gate.policyError = null;
      const selector = $('gateCheckpoint');
      if (selector) {
        selector.classList.toggle('hidden', !policy.canSelectCheckpoint);
        selector.disabled = gate.busy;
      }
      if (!policy.allowedDirections.includes(gate.mode) && policy.allowedDirections.length) {
        gate.mode = policy.allowedDirections[0];
        if (!gate.busy) resetResult();
      }
    } catch (err) {
      if (generation !== policyGeneration) return;
      gate.policy = null;
      gate.policyError = 'Gate permissions unavailable. Reconnect before recording a passage.';
    }
    renderMode();
  }

  function setMode(mode) {
    if (gate.busy || mode === gate.mode || !gate.policy?.allowedDirections.includes(mode)) return;
    gate.mode = mode;
    try { sessionStorage.setItem(MODE_KEY, mode); } catch (_) {}
    renderMode();
    // A verification is direction-specific; start over
    if (gate.result) {
      resetResult();
      SP.showToast(`Switched to ${mode === 'Ingress' ? 'ENTRY' : 'EXIT'} mode. Scan again.`);
    } else renderIdle();
  }

  /* ------------------------------------------------------------------------
     Verification
     ------------------------------------------------------------------------ */
  async function verify(raw, lookup) {
    const value = (raw || '').trim();
    if (!value || gate.busy || !gate.policy?.allowedDirections.includes(gate.mode)) return;
    gate.busy = true;
    gate.input = value;
    gate.lookup = lookup || (value.startsWith('{') ? 'qr' : 'manual');
    gate.driverId = null;
    gate.itemsChecked = false;
    gate.decisionRef = null;
    gate.photos = {};
    renderLoading(value);
    pauseCamera();
    try {
      // The same two steps the phone uses: this call only checks (nothing is saved); "Record" confirms it once.
      // The server decides whether the text is a signed pass, legacy pass, pass code or plate, and refuses a lane that
      // contradicts where the vehicle is recorded (anti-passback).
      gate.result = await ApiClient.prepareMovement({
        qr_code: value, checkpoint: gate.policy.checkpoint, direction: gate.mode === 'Ingress' ? 'IN' : 'OUT', lookup_method: gate.lookup
      });
      autoSelectDriver();
      renderResult();
      if (window.SPFeedback) SPFeedback.play(!gate.result.accepted ? 'deny' : (gate.result.severity === 'ok' ? 'ok' : 'warn'));
    } catch (err) {
      gate.result = null;
      renderError(err.message || 'Verification failed. Check the connection and try again.');
    } finally {
      gate.busy = false;
    }
  }

  function autoSelectDriver() {
    const r = gate.result;
    if (!r || !r.vehicle) return;
    const drivers = r.vehicle.authorizedDrivers || [];
    if (drivers.length === 1) gate.driverId = Number(drivers[0].id);
  }

  function resetResult() {
    gate.result = null;
    gate.input = '';
    gate.driverId = null;
    gate.itemsChecked = false;
    gate.decisionRef = null;
    gate.photos = {};
    renderIdle();
    if ($('gateManualInput')) {
      $('gateManualInput').value = '';
      $('gateManualInput').focus();
    }
    resumeCamera();
  }

  /* ------------------------------------------------------------------------
     Result rendering
     ------------------------------------------------------------------------ */
  function renderIdle() {
    setCheckStatus('Ready to check', 'ready');
    const dir = gate.mode === 'Ingress' ? 'entry' : 'exit';
    $('gateResult').innerHTML = `
      <div class="h-full min-h-[320px] flex flex-col items-center justify-center text-center p-8 text-slate-400">
        <svg class="w-12 h-12 mb-3 text-slate-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/><line x1="7" y1="12" x2="17" y2="12"/>
        </svg>
        <p class="text-sm font-bold text-slate-500">Waiting for an ${dir} check</p>
        <p class="text-xs mt-1">Scan a pass or type a plate number above.</p>
      </div>`;
  }

  function renderLoading(value) {
    setCheckStatus('Checking…', 'checking');
    $('gateResult').innerHTML = `
      <div class="min-h-[320px] flex flex-col items-center justify-center p-8 text-slate-500" role="status" aria-live="polite">
        <div class="w-8 h-8 border-4 border-slate-200 border-t-ncst-navy rounded-full animate-spin mb-3"></div>
        <p class="text-xs font-semibold">Checking pass&hellip;</p>
        <p class="text-[10px] font-mono text-slate-400 mt-1 max-w-full truncate">${esc(value.slice(0, 60))}</p>
      </div>`;
  }

  function renderError(message) {
    setCheckStatus('Could not check', 'blocked');
    $('gateResult').innerHTML = `
      <div class="p-5 space-y-3">
        <div class="rounded-md border border-ncst-crimson/30 bg-ncst-crimsonLight px-4 py-3 text-sm font-semibold text-ncst-crimson" role="alert">${esc(message)}</div>
        <button type="button" data-act="reset" class="px-4 py-2 rounded-md border border-slate-300 bg-white hover:bg-slate-50 text-xs font-bold text-slate-700 cursor-pointer">Try Again</button>
      </div>`;
    $('gateResult').querySelector('[data-act="reset"]').addEventListener('click', resetResult);
  }

  function renderDecisionError(message) {
    const box = $('gateResult');
    let notice = box.querySelector('[data-decision-error]');
    if (!notice) {
      notice = document.createElement('p');
      notice.dataset.decisionError = '';
      notice.setAttribute('role', 'alert');
      notice.className = 'mx-5 my-3 rounded-md border border-ncst-crimson/30 bg-ncst-crimsonLight px-4 py-3 text-sm font-semibold text-ncst-crimson';
      box.prepend(notice);
    }
    notice.textContent = message;
  }

  const RESULT_LABELS = {
    VALID: 'Valid QR pass', LEGACY: 'Older pass', MANUAL: 'Plate number check', FORGED: 'Fake or changed pass',
    REVOKED: 'Cancelled pass', EXPIRED: 'Expired pass', EXPIRED_TEMP: 'Expired day pass', NOT_YET_VALID: 'Pass not active yet',
    BANNED: 'Violation hold', SUSPENDED: 'Registration on hold', NOT_FOUND: 'Not found',
    ALREADY_INSIDE: 'Already inside', NOT_ON_CAMPUS: 'Not on campus', UNPAID: 'Fee unpaid', RETIRED: 'Vehicle retired',
    GATE_DIRECTION_DENIED: 'Lane not allowed'
  };

  /* ------------------------------------------------------------------------
     Notices next to a result (parking nearly full, a released exit, the case holding the vehicle) and the
     "already inside" details
     ------------------------------------------------------------------------ */
  function clock(value) {
    const t = new Date(String(value || '').replace(' ', 'T'));
    return isNaN(t) ? '' : t.toLocaleTimeString('en-PH', { hour: 'numeric', minute: '2-digit' });
  }

  function noticeStrip(r) {
    const notes = [];
    if (r.exitRelease) {
      const until = clock(r.exitRelease.expiresAt);
      notes.push(['warning', `Exit released by ${r.exitRelease.releasedBy || 'an administrator'}${until ? ' until ' + until : ''}`,
        `Let it out once. It stays on hold and cannot come back in. Reason: ${r.exitRelease.reason || '-'}`]);
    }
    const occ = r.occupancy;
    if (occ && (occ.level === 'full' || occ.level === 'nearly_full') && occ.message) {
      notes.push([occ.level === 'full' ? 'danger' : 'warning', occ.message,
        occ.level === 'full' ? 'Entry is still your decision (emergency or VIP vehicles may need to be let in).' : '']);
    }
    if (r.case) {
      notes.push(['info', `Case: ${r.case.title || 'open case'} (${r.case.step || 'open'})${r.case.policeReferred ? ' · referred to the police' : ''}`,
        'The vehicle stays on hold until an administrator closes the case.', r.case.key]);
    }
    if (!notes.length) return '';
    const tint = { info: 'border-sky-300 bg-sky-50 text-sky-950', warning: 'border-amber-300 bg-amber-50 text-amber-950', danger: 'border-rose-300 bg-rose-50 text-rose-950' };
    return `<div class="px-5 pt-3 space-y-2" data-notices>${notes.map(([level, title, detail, key]) => `
      <div class="rounded-lg border ${tint[level]} px-3 py-2 text-xs"><div class="font-bold">${esc(title)}</div>
        ${detail ? `<div class="mt-0.5 opacity-90">${esc(detail)}</div>` : ''}
        ${key ? `<button type="button" data-open-case="${esc(key)}" class="mt-1 text-[11px] font-bold underline cursor-pointer">Open the case</button>` : ''}</div>`).join('')}</div>`;
  }

  /** Where a vehicle that is already inside is, and who to call. */
  function onCampusBlock(o) {
    if (!o) return '';
    const rows = [
      o.entryTime ? ['Came in', `${clock(o.entryTime)}${o.hoursInside != null ? ' (' + o.hoursInside + ' h ago)' : ''}${o.gatePoint ? ' at ' + o.gatePoint : ''}`] : null,
      o.enteredBy ? ['Driven in by', o.enteredBy] : null,
      o.admittedBy ? ['Admitted by', o.admittedBy] : null,
      o.ownerPhone ? ['Owner phone', { html: `<a class="font-bold text-ncst-navy underline" href="tel:${esc(o.ownerPhone)}">${esc(o.ownerPhone)}</a>` }] : null,
    ].filter(Boolean);
    return `<div class="mx-5 mt-3 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2.5 text-xs text-amber-950">
      <div class="font-extrabold uppercase tracking-wider text-[10px] mb-1">This vehicle is inside campus</div>
      <dl class="grid grid-cols-[auto,1fr] gap-x-3 gap-y-0.5">${rows.map(([k, v]) => `<dt class="opacity-75">${esc(k)}</dt><dd class="font-semibold">${v && v.html ? v.html : esc(v)}</dd>`).join('')}</dl></div>`;
  }

  /** A photo field that survives the card being redrawn (choosing a driver redraws it). */
  function photoSlot(box, name, label) {
    const slot = box.querySelector(`[data-photo-slot="${name}"]`);
    if (!slot || !window.SPPhoto) return;
    gate.photos[name] = gate.photos[name] || SPPhoto.field(label);
    slot.replaceWith(gate.photos[name].el);
  }
  const photoOf = (name) => (gate.photos[name] ? gate.photos[name].get() : null);

  function setCheckStatus(text, state) {
    const status = $('gateCheckStatus');
    if (!status) return;
    status.textContent = text;
    status.dataset.state = state;
  }

  function bannerClasses(severity) {
    if (severity === 'ok') return 'sp-gate-banner sp-gate-banner-ok';
    if (severity === 'warning') return 'sp-gate-banner sp-gate-banner-warning';
    return 'sp-gate-banner sp-gate-banner-blocked';
  }

  function renderResult() {
    const r = gate.result;
    const box = $('gateResult');
    setCheckStatus(r.accepted ? 'Review before saving' : 'Vehicle blocked', r.accepted ? 'review' : 'blocked');
    const dirLabel = r.gateType === 'Ingress' ? 'ENTRY' : 'EXIT';

    const warnings = (r.warnings || []).map(w => `
      <li class="flex gap-2 items-start"><span aria-hidden="true" class="mt-0.5 text-ncst-goldDark">&#9888;</span><span>${esc(w)}</span></li>`).join('');

    const passback = PASSBACK.includes(r.result);
    let subject = '';
    if (r.vehicle) subject = vehicleBlock(r.vehicle, r);
    else if (r.visitor) subject = visitorBlock(r.visitor);
    if (passback && r.onCampus) subject = onCampusBlock(r.onCampus) + subject;

    let actions = '';
    if (r.accepted) {
      const needsDriver = !!r.vehicle && !r.vehicle.isVip; // VIPs are waved through without a driver check
      const needsItems = !r.vehicle && r.visitor && (r.visitor.items || []).length > 0;
      const ready = (!needsDriver || gate.driverId) && (!needsItems || gate.itemsChecked);
      actions = `
        <div class="border-t border-slate-100 px-5 py-4 space-y-3">
          ${needsDriver && !gate.driverId ? '<p class="text-[11px] font-semibold text-ncst-navy">Select the driver currently behind the wheel to continue.</p>' : ''}
          ${needsItems && !gate.itemsChecked ? `<p class="text-[11px] font-semibold text-ncst-navy">Check the visitor's items ${r.gateType === 'Ingress' ? 'coming in' : 'going out'} and tick the box to continue.</p>` : ''}
          <div class="flex flex-wrap items-center gap-2">
            <button type="button" data-act="approve" ${ready ? '' : 'disabled'}
              class="px-5 py-2.5 rounded-md text-sm font-extrabold text-white shadow-xs cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed ${r.gateType === 'Ingress' ? 'bg-ncst-green hover:bg-ncst-greenDark' : 'bg-ncst-navy hover:bg-ncst-navyDark'}">
              ${r.gateType === 'Ingress' ? 'Record Entry' : 'Approve Exit'}
            </button>
            <button type="button" data-act="deny" class="px-4 py-2.5 rounded-md border border-ncst-crimson/30 bg-ncst-crimsonLight hover:bg-ncst-crimson/10 text-sm font-bold text-ncst-crimson cursor-pointer">
              Deny ${dirLabel === 'ENTRY' ? 'Entry' : 'Exit'}
            </button>
            ${r.vehicle && !r.vehicle.isVip ? '<button type="button" data-act="warn" class="px-3 py-2.5 rounded-md border border-ncst-crimson/30 bg-ncst-crimsonLight hover:bg-ncst-crimson/10 text-sm font-bold text-ncst-crimson cursor-pointer">Issue Violation</button>' : ''}
            <button type="button" data-act="reset" class="ml-auto px-3 py-2 rounded-md text-xs font-semibold text-slate-500 hover:text-slate-800 cursor-pointer">Cancel</button>
          </div>
          <div data-photo-slot="approve"></div>
          <div id="gateDenyPanel" class="hidden rounded-md border border-ncst-crimson/30 bg-ncst-crimsonLight/70 p-3 space-y-2">
            <label for="gateDenyReason" class="block text-[11px] font-bold text-slate-700">Why are you blocking this vehicle?</label>
            <select id="gateDenyReason" class="w-full px-2.5 py-2 rounded border border-slate-300 bg-white text-xs">
              ${DENY_REASONS.map((x, i) => `<option value="${esc(x)}">${esc(DENY_LABELS[i])}</option>`).join('')}
            </select>
            <label for="gateDenyNotes" class="block text-[11px] font-bold text-slate-700">Notes (optional)</label>
            <textarea id="gateDenyNotes" rows="2" class="w-full px-2.5 py-2 rounded border border-slate-300 bg-white text-xs" placeholder="What did you observe?"></textarea>
            <div data-photo-slot="deny"></div>
            <div class="flex justify-end gap-2">
              <button type="button" data-act="deny-cancel" class="px-3 py-1.5 rounded border border-slate-300 bg-white text-xs font-semibold text-slate-700 cursor-pointer">Back</button>
              <button type="button" data-act="deny-confirm" class="px-3 py-1.5 rounded bg-ncst-crimson hover:bg-ncst-crimsonDark text-white text-xs font-bold cursor-pointer">Deny &amp; Flag Vehicle</button>
            </div>
          </div>
        </div>`;
    } else {
      const logged = r.autoLogged
        ? `This attempt was logged automatically${r.incident ? ` and flagged as case <span class="font-mono font-bold">${esc(r.incident.caseNumber)}</span>` : ''}.`
        : (r.result === 'NOT_FOUND' ? 'Register the vehicle or issue a visitor day pass, then scan again.' : '');
      actions = `
        <div class="border-t border-slate-100 px-5 py-4 flex flex-wrap items-center gap-3">
          <p class="text-xs text-slate-600 flex-1 min-w-[200px]">${logged}</p>
          ${passback ? '<button type="button" data-act="report" class="px-3 py-2.5 rounded-md border border-amber-400 bg-amber-50 hover:bg-amber-100 text-sm font-bold text-amber-900 cursor-pointer">Report</button>' : ''}
          ${r.result === 'NOT_FOUND' && r.gateType === 'Ingress' ? '<button type="button" data-act="visitor" class="px-3 py-2.5 rounded-md border border-ncst-navy/20 bg-ncst-navy/5 hover:bg-ncst-navy/10 text-sm font-bold text-ncst-navy cursor-pointer">Issue Visitor Pass</button>' : ''}
          ${r.vehicle && !r.vehicle.isVip ? '<button type="button" data-act="warn" class="px-3 py-2.5 rounded-md border border-ncst-crimson/30 bg-ncst-crimsonLight hover:bg-ncst-crimson/10 text-sm font-bold text-ncst-crimson cursor-pointer">Issue Violation</button>' : ''}
          <button type="button" data-act="reset" class="px-5 py-2.5 rounded-md bg-slate-900 hover:bg-slate-800 text-white text-sm font-bold cursor-pointer">Scan Next</button>
        </div>
        ${passback ? `<div id="gateReportPanel" class="hidden border-t border-slate-100 mx-5 mb-4 rounded-md border border-amber-300 bg-amber-50/70 p-3 space-y-2">
          <label for="gateReportReason" class="block text-[11px] font-bold text-slate-700">What looks wrong with the record?</label>
          <select id="gateReportReason" class="w-full px-2.5 py-2 rounded border border-slate-300 bg-white text-xs">${reportReasons(r.result).map(x => `<option value="${esc(x)}">${esc(x)}</option>`).join('')}</select>
          <label for="gateReportNotes" class="block text-[11px] font-bold text-slate-700">Notes (optional)</label>
          <textarea id="gateReportNotes" rows="2" class="w-full px-2.5 py-2 rounded border border-slate-300 bg-white text-xs" placeholder="What did you see?"></textarea>
          <div data-photo-slot="report"></div>
          <p class="text-[11px] text-slate-600">An admin case is opened and the vehicle is held until it is reviewed. The owner is not told it was blocked.</p>
          <div class="flex justify-end gap-2">
            <button type="button" data-act="report-cancel" class="px-3 py-1.5 rounded border border-slate-300 bg-white text-xs font-semibold text-slate-700 cursor-pointer">Back</button>
            <button type="button" data-act="report-confirm" class="px-3 py-1.5 rounded bg-amber-600 hover:bg-amber-700 text-white text-xs font-bold cursor-pointer">Send report</button>
          </div></div>` : ''}`;
    }

    box.innerHTML = `
      <div class="${bannerClasses(r.severity)} rounded-t-lg px-5 py-4" role="status" aria-live="assertive">
        <div class="flex flex-wrap items-center gap-2 text-[10px] font-extrabold tracking-widest uppercase opacity-90">
          <span class="px-1.5 py-0.5 rounded bg-black/15">${dirLabel}</span>
          <span class="px-1.5 py-0.5 rounded bg-black/15">${esc(RESULT_LABELS[r.result] || r.result)}</span>
        </div>
        <div class="mt-1.5 text-xl font-extrabold tracking-tight">${esc(r.accepted ? (r.severity === 'ok' ? 'CLEAR TO ' + (r.gateType === 'Ingress' ? 'ENTER' : 'EXIT') : 'CHECK BEFORE ' + (r.gateType === 'Ingress' ? 'ENTRY' : 'EXIT')) : 'ACCESS DENIED')}</div>
        <div class="text-sm font-semibold mt-0.5">${esc(r.message)}${r.reason ? ' &mdash; ' + esc(r.reason) : ''}</div>
      </div>
      ${noticeStrip(r)}
      ${warnings ? `<ul class="px-5 py-3 space-y-1 text-xs text-amber-950 bg-ncst-goldLight border-b border-ncst-gold/30">${warnings}</ul>` : ''}
      ${subject}
      ${actions}`;
    photoSlot(box, 'approve', 'Add photo (optional)');
    photoSlot(box, 'deny', 'Add photo');
    photoSlot(box, 'report', 'Add photo');
    box.querySelectorAll('[data-open-case]').forEach(b => b.addEventListener('click', () => window.SPCases && SPCases.open(b.dataset.openCase)));

    box.querySelectorAll('[data-driver-id]').forEach(card => {
      card.addEventListener('click', () => {
        gate.driverId = Number(card.dataset.driverId);
        renderResult();
      });
    });
    box.querySelectorAll('[data-act="reset"]').forEach(b => b.addEventListener('click', resetResult));
    const itemsBox = box.querySelector('[data-act="items-check"]');
    if (itemsBox) itemsBox.addEventListener('change', () => { gate.itemsChecked = itemsBox.checked; renderResult(); });
    const visitorBtn = box.querySelector('[data-act="visitor"]');
    if (visitorBtn) visitorBtn.addEventListener('click', () => {
      // Prefill the plate only when the guard typed a plate (not a scanned QR payload)
      const typed = gate.input && !gate.input.startsWith('{') ? gate.input : '';
      if (window.SPVisitors) SPVisitors.openCreate({ plate: typed });
    });
    const warnBtn = box.querySelector('[data-act="warn"]');
    if (warnBtn) warnBtn.addEventListener('click', () => {
      if (!window.SPViolations) return;
      SPViolations.openFlagModal(r.vehicle, {
        context: `Gate ${r.gateType === 'Ingress' ? 'entry' : 'exit'} check (${RESULT_LABELS[r.result] || r.result})`,
        onDone: (res) => {
          if (res.onHold && r.accepted) {
            // The vehicle is now on hold: it can neither enter nor leave, so this passage can no longer be approved
            resetResult();
            SP.showToast(`${r.vehicle.plateNumber} is now on violation hold. Do not let it ${r.gateType === 'Ingress' ? 'enter' : 'leave'}.`);
            return;
          }
          r.vehicle.isBanned = res.vehicle.isBanned;
          renderResult();
        }
      });
    });
    const approveBtn = box.querySelector('[data-act="approve"]');
    if (approveBtn) approveBtn.addEventListener('click', approve);
    const denyBtn = box.querySelector('[data-act="deny"]');
    if (denyBtn) denyBtn.addEventListener('click', () => {
      $('gateDenyPanel').classList.remove('hidden');
      denyBtn.classList.add('hidden');
      $('gateDenyReason').focus();
    });
    const denyCancel = box.querySelector('[data-act="deny-cancel"]');
    if (denyCancel) denyCancel.addEventListener('click', () => {
      $('gateDenyPanel').classList.add('hidden');
      denyBtn.classList.remove('hidden');
    });
    const denyConfirm = box.querySelector('[data-act="deny-confirm"]');
    if (denyConfirm) denyConfirm.addEventListener('click', () => deny($('gateDenyReason').value, $('gateDenyNotes').value.trim()));
    const reportBtn = box.querySelector('[data-act="report"]');
    if (reportBtn) reportBtn.addEventListener('click', () => { $('gateReportPanel').classList.remove('hidden'); reportBtn.classList.add('hidden'); $('gateReportReason').focus(); });
    const reportCancel = box.querySelector('[data-act="report-cancel"]');
    if (reportCancel) reportCancel.addEventListener('click', () => { $('gateReportPanel').classList.add('hidden'); reportBtn.classList.remove('hidden'); });
    const reportConfirm = box.querySelector('[data-act="report-confirm"]');
    if (reportConfirm) reportConfirm.addEventListener('click', () => report($('gateReportReason').value, $('gateReportNotes').value.trim()));
  }

  function vehicleBlock(v, r) {
    const standing = v.isBanned
      ? '<span class="px-2 py-0.5 rounded bg-ncst-crimson text-white text-[10px] font-extrabold">VIOLATION HOLD</span>'
      : '';
    const drivers = v.authorizedDrivers || [];
    const ownerPhoto = v.ownerPhoto || v.ownerPhotoUrl;
    const vipBanner = v.isVip
      ? `<div class="sp-vip-gate-note"><span class="px-1.5 py-0.5 rounded bg-white/70 text-ncst-navy text-[10px] font-extrabold tracking-widest">VIP</span><span class="text-xs font-bold">VIP pass: no driver check required. Allow passage only when the pass check is approved. Entry and exit are recorded.</span></div>`
      : '';

    const driverCards = drivers.map(d => {
      const id = Number(d.id);
      const selected = gate.driverId === id;
      const isOwner = /self|owner/i.test(d.relationship || '');
      const photo = d.photoUrl || d.photo_url || (isOwner ? ownerPhoto : '');
      return `
        <button type="button" role="radio" aria-checked="${selected}" data-driver-id="${id}" ${r.accepted ? '' : 'disabled'}
          class="text-left flex items-center gap-3 p-2.5 rounded-lg border-2 transition-colors ${selected ? 'border-ncst-green bg-ncst-greenLight' : 'border-slate-200 bg-white hover:border-slate-400'} ${r.accepted ? 'cursor-pointer' : 'cursor-default opacity-80'}">
          ${photoHtml(photo, d.fullName)}
          <div class="min-w-0 flex-1">
            <div class="text-sm font-bold text-slate-900 truncate">${esc(d.fullName)}</div>
            <div class="text-[11px] text-slate-500 truncate">${esc(d.relationship || '')}</div>
            <div class="text-[10px] font-mono text-slate-400 truncate">Lic. ${esc(d.licenseNo || d.license_no || 'N/A')}</div>
          </div>
          ${selected ? '<span class="text-ncst-green text-lg font-bold" aria-hidden="true">&#10003;</span>' : ''}
        </button>`;
    }).join('');

    return `
      <div class="px-5 py-4 space-y-4">
        ${vipBanner}
        <div class="flex items-start gap-3">
          ${photoHtml(v.vehiclePhoto || v.vehiclePicture, v.plateNumber, 'w-20 h-14')}
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <span class="sp-plate text-base tracking-wider">${esc(v.plateNumber)}</span>
              ${standing}
              <span class="text-[10px] font-semibold text-slate-500">${esc(v.registrationStatus || '')} &middot; ${esc(v.status || '')}</span>
            </div>
            <div class="text-sm font-semibold text-slate-800 mt-1 truncate">${esc(v.makeModelColor || v.vehicleType || '')}</div>
            <div class="text-[11px] text-slate-500 truncate">Owner: <span class="font-semibold text-slate-700">${esc(v.ownerName)}</span> &middot; ${esc(v.ownerRole || '')} &middot; ${esc(v.ownerIdNumber || '')}</div>
            <div class="text-[10px] text-slate-400 font-mono">${v.passId ? 'Pass ' + esc(v.passId) + ' &middot; valid until ' + esc(v.passValidUntil || '—') : ''}</div>
          </div>
        </div>
        <div>
          <div class="text-[11px] font-extrabold uppercase tracking-wider text-slate-500 mb-2">Allowed drivers ${r.accepted ? '&mdash; select who is driving' : ''}</div>
          <div role="radiogroup" aria-label="Driver behind the wheel" class="grid grid-cols-1 sm:grid-cols-2 gap-2">${driverCards || '<p class="text-xs text-slate-400">No drivers on record.</p>'}</div>
        </div>
      </div>`;
  }

  function visitorBlock(v) {
    return `
      <div class="px-5 py-4">
        <div class="flex items-start gap-3 p-3 rounded-lg border-2 border-ncst-navy/20 bg-ncst-navy/5">
          ${photoHtml('', v.visitorName)}
          <div class="min-w-0 flex-1 text-xs space-y-0.5">
            <div class="flex flex-wrap items-center gap-2">
              <span class="sp-plate text-sm tracking-wider">${esc(v.plateNumber)}</span>
              <span class="px-1.5 py-0.5 rounded bg-ncst-navy text-white text-[10px] font-extrabold">VISITOR DAY PASS</span>
            </div>
            <div class="text-sm font-bold text-slate-900 mt-1">${esc(v.visitorName)}</div>
            <div class="text-slate-600">Visiting: <span class="font-semibold">${esc(v.personToVisit)}</span></div>
            <div class="text-slate-600">Purpose: ${esc(v.purposeOfVisit)}</div>
            <div class="text-slate-500">Contact: ${esc(v.contactNumber)} &middot; Valid only on <span class="font-bold">${esc(v.validDate)}</span></div>
          </div>
        </div>
        ${itemsCheckBlock(v)}
      </div>`;
  }

  function itemsCheckBlock(v) {
    const items = v.items || [];
    if (!items.length) return '';
    const r = gate.result;
    const direction = r.gateType === 'Ingress' ? 'coming in' : 'going out';
    return `
      <div class="mt-3 rounded-lg border-2 ${gate.itemsChecked ? 'border-ncst-green bg-ncst-greenLight' : 'border-ncst-gold bg-ncst-goldLight'} p-3">
        <div class="text-[11px] font-extrabold uppercase tracking-wider text-slate-700">Declared items (${items.length})</div>
        <ul class="mt-1.5 space-y-1 text-sm text-slate-900">
          ${items.map(i => `<li class="flex gap-2"><span class="font-mono font-extrabold w-12 text-right flex-shrink-0">${esc(i.quantity)}&times;</span><span><span class="font-semibold">${esc(i.name)}</span>${i.description ? ` <span class="text-slate-500 text-xs">(${esc(i.description)})</span>` : ''}</span></li>`).join('')}
        </ul>
        ${r.accepted ? `
        <label class="mt-2 flex items-center gap-2 text-xs font-bold text-slate-800 cursor-pointer">
          <input type="checkbox" data-act="items-check" class="w-4 h-4 accent-ncst-green" ${gate.itemsChecked ? 'checked' : ''}>
          I checked these items ${direction}
        </label>` : ''}
      </div>`;
  }

  /* ------------------------------------------------------------------------
     Decisions
     ------------------------------------------------------------------------ */
  function selectedDriver() {
    const r = gate.result;
    if (!r || !r.vehicle || !gate.driverId) return null;
    return (r.vehicle.authorizedDrivers || []).find(d => Number(d.id) === gate.driverId) || null;
  }

  function decisionRef() {
    if (!gate.decisionRef) gate.decisionRef = `web:${Date.now()}:${Math.random().toString(36).slice(2)}`;
    return gate.decisionRef;
  }

  /** Saves the passage the server cleared. The ticket from the check makes a second press (or a resend) harmless. */
  async function approve() {
    const r = gate.result;
    if (!r || gate.busy) return;
    if (!r.movement) { renderDecisionError('This check cannot be saved. Scan the pass again.'); return; }
    const plate = r.vehicle ? r.vehicle.plateNumber : r.visitor.plateNumber;
    const payload = { ticket: r.movement.ticket };
    if (r.vehicle && gate.driverId) payload.driver_id = gate.driverId;
    if (r.visitor && (r.visitor.items || []).length) payload.items_verified = gate.itemsChecked;

    gate.busy = true;
    try {
      const log = await ApiClient.confirmMovement(payload);
      ApiClient.flushNotices(); // the owner's "is this you?" e-mail goes out now, in its own request
      const exit = log.action === 'OUT';
      const photoProblem = await SPPhoto.send(exit ? 'exit' : 'entry', plate, photoOf('approve'), { gateLogId: log.id });
      SP.showToast(`${exit ? 'EXIT APPROVED' : 'ENTRY RECORDED'}: ${log.plateNumber || plate} — ${selectedDriver()?.fullName || (r.visitor && r.visitor.visitorName) || (r.vehicle && r.vehicle.ownerName) || 'verified driver'}.`);
      if (photoProblem) SP.showToast(`The passage is saved, but the photo was not sent: ${photoProblem}`, 'warning');
      if (window.SPFeedback) SPFeedback.play('ok');
      await afterDecision().catch(() => SP.showToast('The passage was recorded, but the latest gate list could not load. It will refresh when the connection recovers.', 'warning'));
    } catch (err) {
      renderDecisionError(`${err.message || 'Could not confirm the decision.'} Check gate records before trying again.`);
      if (window.SPFeedback) SPFeedback.play('deny');
    } finally {
      gate.busy = false;
    }
  }

  async function deny(reason, notes) {
    const r = gate.result;
    if (!r || gate.busy) return;
    const drv = selectedDriver();
    const plate = r.vehicle ? r.vehicle.plateNumber : r.visitor.plateNumber;
    const action = r.gateType === 'Ingress' ? 'Entry Denied' : 'Exit Denied';
    const detail = notes ? `${reason}: ${notes}` : reason;

    gate.busy = true;
    let denialRecorded = false;
    try {
      const log = await ApiClient.createLog({
        plate, action, gate_type: r.gateType, checkpoint: r.gatePolicy?.checkpoint || gate.policy.checkpoint,
        client_ref: `${decisionRef()}:log`,
        driverName: drv ? drv.fullName : (r.visitor ? r.visitor.visitorName : 'Unverified'),
        driverRelationship: drv ? drv.relationship : (r.visitor ? 'Visitor (Day Pass)' : 'Unverified'),
        notes: detail
      });
      denialRecorded = true;
      const incident = await ApiClient.createIncident({
        client_ref: `${decisionRef()}:case`,
        plateNumber: plate,
        reason,
        vehicleType: r.vehicle ? r.vehicle.vehicleType : 'Visitor Vehicle',
        ownerName: r.vehicle ? r.vehicle.ownerName : r.visitor.visitorName,
        ownerRole: r.vehicle ? r.vehicle.ownerRole : 'Visitor',
        driverName: drv ? drv.fullName : 'Unverified',
        driverRelationship: drv ? drv.relationship : 'Unverified',
        gatePoint: r.gatePolicy?.checkpoint || gate.policy.checkpoint,
        notes: `${action} at gate verification. ${notes}`.trim()
      });
      const photoProblem = await SPPhoto.send('incident', plate, photoOf('deny'), { incidentId: incident.id, gateLogId: log && log.id });
      SP.showToast(`${action.toUpperCase()}: ${plate} flagged (${incident.caseNumber}).`);
      if (photoProblem) SP.showToast(`The case is saved, but the photo was not sent: ${photoProblem}`, 'warning');
      if (window.SPFeedback) SPFeedback.play('deny');
      await afterDecision().catch(() => SP.showToast('Denial and case were saved, but the latest gate list could not load.', 'warning'));
    } catch (err) {
      if (denialRecorded) {
        renderDecisionError('The denial was recorded, but the security case could not be confirmed. Review gate records and cases before trying again.');
      } else {
        renderDecisionError(`${err.message || 'Could not confirm the denial.'} Check gate records before trying again.`);
      }
    } finally {
      gate.busy = false;
    }
  }

  /** After an anti-passback refusal: the record looks wrong. Opens an admin case; no passage is refused and the owner is not told. */
  async function report(reason, notes) {
    const r = gate.result;
    if (!r || gate.busy) return;
    const plate = r.vehicle ? r.vehicle.plateNumber : r.visitor.plateNumber;
    gate.busy = true;
    try {
      const incident = await ApiClient.createIncident({
        client_ref: `${decisionRef()}:report`,
        plateNumber: plate,
        reason,
        vehicleType: r.vehicle ? r.vehicle.vehicleType : 'Visitor Vehicle',
        ownerName: r.vehicle ? r.vehicle.ownerName : r.visitor.visitorName,
        ownerRole: r.vehicle ? r.vehicle.ownerRole : 'Visitor',
        driverName: 'Unverified',
        driverRelationship: 'Unverified',
        gatePoint: r.gatePolicy?.checkpoint || gate.policy.checkpoint,
        notes: `Record check after "${RESULT_LABELS[r.result] || r.result}" at the ${r.gateType === 'Ingress' ? 'entry' : 'exit'} lane. ${notes}`.trim(),
        report: true
      });
      const photoProblem = await SPPhoto.send('incident', plate, photoOf('report'), { incidentId: incident.id });
      SP.showToast(`Reported: ${plate} is held under case ${incident.caseNumber} until an admin reviews it.`);
      if (photoProblem) SP.showToast(`The report is saved, but the photo was not sent: ${photoProblem}`, 'warning');
      await afterDecision().catch(() => SP.showToast('The report was saved, but the latest gate list could not load.', 'warning'));
    } catch (err) {
      renderDecisionError(`${err.message || 'Could not send the report.'}`);
    } finally {
      gate.busy = false;
    }
  }

  async function afterDecision() {
    resetResult();
    if (window.SP && SP.reload) await SP.reload();
    document.dispatchEvent(new CustomEvent('sp:gate-passage'));
    renderRecent();
  }

  /* ------------------------------------------------------------------------
     Recent activity
     ------------------------------------------------------------------------ */
  function renderRecent() {
    const list = $('gateRecentList');
    if (!list || !window.SP) return;
    const logs = (SP.state.auditLogs || []).slice(0, 8);
    if (!logs.length) {
      list.innerHTML = '<li class="px-4 py-4 text-center text-slate-400">No gate activity yet.</li>';
      return;
    }
    list.innerHTML = logs.map(l => {
      const denied = /Denied/.test(l.action || '');
      const exit = /Exit/.test(l.action || '');
      const chip = denied ? 'bg-ncst-crimsonLight text-ncst-crimson border-ncst-crimson/30' : (exit ? 'bg-ncst-navy/10 text-ncst-navy border-ncst-navy/20' : 'bg-ncst-greenLight text-ncst-greenDark border-ncst-green/30');
      return `
        <li class="sp-gate-recent-row">
          <div><span class="sp-plate">${esc(l.plateNumber)}</span><span class="sp-gate-recent-action rounded border ${chip}">${denied ? (exit ? 'Exit blocked' : 'Entry blocked') : (exit ? 'Exit saved' : 'Entry saved')}</span></div>
          <p>${esc(l.driverName || 'Driver not recorded')}</p>
          <time>${esc(l.timestamp || '')}</time>
        </li>`;
    }).join('');
  }

  /* ------------------------------------------------------------------------
     Camera scanning (html5-qrcode, loaded on demand)
     ------------------------------------------------------------------------ */
  function loadQrLibrary() {
    if (window.Html5Qrcode) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = QR_LIB;
      s.onload = resolve;
      s.onerror = () => reject(new Error('Could not load the camera scanner library. Use the text box instead.'));
      document.head.appendChild(s);
    });
  }

  function cameraError(message) {
    const el = $('gateCameraError');
    el.textContent = message;
    el.classList.toggle('hidden', !message);
  }

  function cameraButtons(torchSupported) {
    const flip = $('gateFlipBtn'), torch = $('gateTorchBtn');
    if (flip) flip.classList.toggle('hidden', !(gate.cameraOn && gate.cameras.length > 1));
    if (torch) torch.classList.toggle('hidden', !(gate.cameraOn && torchSupported));
  }

  async function startCamera() {
    cameraError('');
    if (!window.isSecureContext) {
      cameraError('The camera needs a secure (HTTPS) connection. Enable SSL on the site, or use a USB scanner / the text box.');
      return;
    }
    try {
      await loadQrLibrary();
      $('gateCameraBox').classList.remove('hidden');
      gate.scanner = gate.scanner || new Html5Qrcode('gateCameraReader');
      await gate.scanner.start(
        gate.cameras[gate.cameraIndex] ? { deviceId: { exact: gate.cameras[gate.cameraIndex].id } } : { facingMode: 'environment' },
        { fps: 10, qrbox: { width: 220, height: 220 } },
        (text) => { if (!gate.result && !gate.busy) verify(text, 'qr'); },
        () => {}
      );
      gate.cameraOn = true;
      $('gateCameraBtn').textContent = 'Stop Scanning';
      if (!gate.cameras.length) { try { gate.cameras = await Html5Qrcode.getCameras(); } catch (_) { gate.cameras = []; } }
      let torchSupported = false;
      try { torchSupported = !!gate.scanner.getRunningTrackCameraCapabilities().torchFeature().isSupported(); } catch (_) {}
      cameraButtons(torchSupported);
    } catch (err) {
      $('gateCameraBox').classList.add('hidden');
      cameraError(err && err.message ? err.message : 'Camera unavailable. Check browser permissions.');
    }
  }

  async function stopCamera() {
    if (gate.scanner && gate.cameraOn) {
      try { await gate.scanner.stop(); } catch (_) {}
    }
    gate.cameraOn = false;
    cameraButtons(false);
    if ($('gateCameraBox')) $('gateCameraBox').classList.add('hidden');
    if ($('gateCameraBtn')) $('gateCameraBtn').textContent = 'Scan with Camera';
  }

  function pauseCamera() {
    if (gate.scanner && gate.cameraOn) { try { gate.scanner.pause(true); } catch (_) {} }
  }

  function resumeCamera() {
    if (gate.scanner && gate.cameraOn) { try { gate.scanner.resume(); } catch (_) {} }
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  document.addEventListener('sp:app-ready', () => {
    SP.registerView('gateView', $('navGateBtn'), () => {
      renderMode();
      renderRecent();
      if (!gate.result) renderIdle();
      setTimeout(() => $('gateManualInput') && $('gateManualInput').focus(), 50);
    });

    gate.cctv = window.SPCctv ? SPCctv.mount($('gateCctvMount'), { camera: 'CAM 01 (MAIN GATE)' }) : null;
    renderMode();
    renderIdle();

    document.querySelectorAll('#gateModeToggle .gate-mode-btn').forEach(btn => {
      btn.addEventListener('click', () => setMode(btn.dataset.mode));
    });

    const selector = document.createElement('select');
    selector.id = 'gateCheckpoint';
    selector.setAttribute('aria-label', 'Physical checkpoint');
    selector.className = 'hidden rounded border border-slate-300 text-xs p-2';
    selector.innerHTML = '<option>Gate 1</option><option>Gate 2</option>';
    $('gateModeHint').after(selector);
    selector.addEventListener('change', async () => {
      gate.checkpoint = selector.value;
      resetResult();
      await refreshPolicy();
    });
    if (window.SPAuth) SPAuth.whenAuthenticated(refreshPolicy);
    window.addEventListener('online', refreshPolicy);
    $('gateManualForm').addEventListener('submit', (e) => {
      e.preventDefault();
      verify($('gateManualInput').value);   // typed, or pasted by a USB / Bluetooth scanner: verify() tells them apart
    });
    $('gateCameraBtn').addEventListener('click', () => (gate.cameraOn ? stopCamera() : startCamera()));
    if ($('gateFlipBtn')) $('gateFlipBtn').addEventListener('click', async () => {
      if (gate.cameras.length < 2) return;
      gate.cameraIndex = (gate.cameraIndex + 1) % gate.cameras.length;
      await stopCamera();
      await startCamera();
    });
    if ($('gateTorchBtn')) $('gateTorchBtn').addEventListener('click', async () => {
      try {
        const torch = gate.scanner.getRunningTrackCameraCapabilities().torchFeature();
        await torch.apply(!torch.value());
        $('gateTorchBtn').setAttribute('aria-pressed', String(torch.value()));
      } catch (_) { cameraError('This camera has no flashlight.'); }
    });
    document.addEventListener('sp:data-loaded', renderRecent);

    // Turn the camera off whenever the Gate Monitor is not on screen
    new MutationObserver(() => {
      if (!$('gateView').classList.contains('active') && gate.cameraOn) stopCamera();
    }).observe($('gateView'), { attributes: true, attributeFilter: ['class'] });
  });
  window.SPGate = { stopCamera };
  window.SPLive?.subscribe(async changed => {
    if (!gate.policy || changed.some(k => ['settings','session','staff'].includes(k))) await refreshPolicy();
    if (!gate.result || gate.busy || !changed.some(k => ['vehicles','visitors','cases','movements','settings'].includes(k))) return;
    resetResult(); SP.showToast('Gate information changed. Scan or check the pass again before approval.', 'warning');
  });
})();
