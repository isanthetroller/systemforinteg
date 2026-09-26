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
    'Security Officer Intervention'
  ];

  const gate = {
    mode: readMode(),
    input: '',          // raw scanned / typed value of the current verification
    result: null,       // verify.php response data
    driverId: null,     // selected authorized driver id
    itemsChecked: false, // guard confirmed a visitor's declared items
    busy: false,
    cctv: null,
    scanner: null,      // Html5Qrcode instance
    cameraOn: false
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
      btn.setAttribute('aria-checked', active ? 'true' : 'false');
      btn.className = 'gate-mode-btn px-4 py-2 rounded-md text-xs font-extrabold tracking-wide transition-colors cursor-pointer ' + (active
        ? (gate.mode === 'Ingress' ? 'bg-emerald-600 text-white shadow' : 'bg-ncst-navy text-white shadow')
        : 'text-slate-600 hover:text-slate-900');
    });
    if (gate.cctv) {
      gate.cctv.setLane(gate.mode === 'Ingress' ? 'INGRESS MONITOR - LANE 1' : 'EGRESS MONITOR - LANE 2');
    }
    const btn = $('gateVerifyBtn');
    if (btn) btn.textContent = gate.mode === 'Ingress' ? 'Verify Entry' : 'Verify Exit';
  }

  function setMode(mode) {
    if (mode === gate.mode) return;
    gate.mode = mode;
    try { sessionStorage.setItem(MODE_KEY, mode); } catch (_) {}
    renderMode();
    // A verification is direction-specific; start over
    if (gate.result) {
      resetResult();
      SP.showToast(`Switched to ${mode === 'Ingress' ? 'ENTRY' : 'EXIT'} mode. Scan again.`);
    }
  }

  /* ------------------------------------------------------------------------
     Verification
     ------------------------------------------------------------------------ */
  async function verify(raw) {
    const value = (raw || '').trim();
    if (!value || gate.busy) return;
    gate.busy = true;
    gate.input = value;
    gate.driverId = null;
    gate.itemsChecked = false;
    renderLoading(value);
    pauseCamera();
    try {
      // Server decides whether the text is a signed pass, legacy pass, pass code or plate
      gate.result = await ApiClient.verifyPass({ qrCode: value }, gate.mode);
      autoSelectDriver();
      renderResult();
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
    const dir = gate.mode === 'Ingress' ? 'entry' : 'exit';
    $('gateResult').innerHTML = `
      <div class="h-full min-h-[320px] flex flex-col items-center justify-center text-center p-8 text-slate-400">
        <svg class="w-12 h-12 mb-3 text-slate-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/><line x1="7" y1="12" x2="17" y2="12"/>
        </svg>
        <p class="text-sm font-bold text-slate-500">Ready for ${dir} verification</p>
        <p class="text-xs mt-1">Scan a pass or type a plate number.</p>
      </div>`;
  }

  function renderLoading(value) {
    $('gateResult').innerHTML = `
      <div class="min-h-[320px] flex flex-col items-center justify-center p-8 text-slate-500" role="status" aria-live="polite">
        <div class="w-8 h-8 border-4 border-slate-200 border-t-ncst-navy rounded-full animate-spin mb-3"></div>
        <p class="text-xs font-semibold">Verifying pass&hellip;</p>
        <p class="text-[10px] font-mono text-slate-400 mt-1 max-w-full truncate">${esc(value.slice(0, 60))}</p>
      </div>`;
  }

  function renderError(message) {
    $('gateResult').innerHTML = `
      <div class="p-5 space-y-3">
        <div class="rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-ncst-crimson" role="alert">${esc(message)}</div>
        <button type="button" data-act="reset" class="px-4 py-2 rounded-md border border-slate-300 bg-white hover:bg-slate-50 text-xs font-bold text-slate-700 cursor-pointer">Try Again</button>
      </div>`;
    $('gateResult').querySelector('[data-act="reset"]').addEventListener('click', resetResult);
  }

  const RESULT_LABELS = {
    VALID: 'Signed pass', LEGACY: 'Legacy pass', MANUAL: 'Manual lookup', FORGED: 'Forged / tampered',
    REVOKED: 'Revoked pass', EXPIRED: 'Expired pass', EXPIRED_TEMP: 'Expired day pass',
    BANNED: 'Banned vehicle', SUSPENDED: 'Suspended registration', NOT_FOUND: 'Not found'
  };

  function bannerClasses(severity) {
    if (severity === 'ok') return 'bg-emerald-600 text-white';
    if (severity === 'warning') return 'bg-amber-400 text-slate-900';
    return 'bg-ncst-crimson text-white';
  }

  function renderResult() {
    const r = gate.result;
    const box = $('gateResult');
    const dirLabel = r.gateType === 'Ingress' ? 'ENTRY' : 'EXIT';

    const warnings = (r.warnings || []).map(w => `
      <li class="flex gap-2 items-start"><span aria-hidden="true" class="mt-0.5 text-amber-600">&#9888;</span><span>${esc(w)}</span></li>`).join('');

    let subject = '';
    if (r.vehicle) subject = vehicleBlock(r.vehicle, r);
    else if (r.visitor) subject = visitorBlock(r.visitor);

    let actions = '';
    if (r.accepted) {
      const needsDriver = !!r.vehicle;
      const needsItems = !r.vehicle && r.visitor && (r.visitor.items || []).length > 0;
      const ready = (!needsDriver || gate.driverId) && (!needsItems || gate.itemsChecked);
      actions = `
        <div class="border-t border-slate-100 px-5 py-4 space-y-3">
          ${needsDriver && !gate.driverId ? '<p class="text-[11px] font-semibold text-ncst-navy">Select the driver currently behind the wheel to continue.</p>' : ''}
          ${needsItems && !gate.itemsChecked ? `<p class="text-[11px] font-semibold text-ncst-navy">Check the visitor's items ${r.gateType === 'Ingress' ? 'coming in' : 'going out'} and tick the box to continue.</p>` : ''}
          <div class="flex flex-wrap items-center gap-2">
            <button type="button" data-act="approve" ${ready ? '' : 'disabled'}
              class="px-5 py-2.5 rounded-md text-sm font-extrabold text-white shadow-xs cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed ${r.gateType === 'Ingress' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-ncst-navy hover:bg-ncst-navyDark'}">
              ${r.gateType === 'Ingress' ? 'Record Entry' : 'Approve Exit'}
            </button>
            <button type="button" data-act="deny" class="px-4 py-2.5 rounded-md border border-rose-300 bg-rose-50 hover:bg-rose-100 text-sm font-bold text-ncst-crimson cursor-pointer">
              Deny ${dirLabel === 'ENTRY' ? 'Entry' : 'Exit'}
            </button>
            ${r.vehicle ? '<button type="button" data-act="warn" class="px-3 py-2.5 rounded-md border border-amber-300 bg-amber-50 hover:bg-amber-100 text-sm font-bold text-amber-900 cursor-pointer">Issue Warning</button>' : ''}
            <button type="button" data-act="reset" class="ml-auto px-3 py-2 rounded-md text-xs font-semibold text-slate-500 hover:text-slate-800 cursor-pointer">Cancel</button>
          </div>
          <div id="gateDenyPanel" class="hidden rounded-md border border-rose-200 bg-rose-50/60 p-3 space-y-2">
            <label for="gateDenyReason" class="block text-[11px] font-bold text-slate-700">Reason for denial</label>
            <select id="gateDenyReason" class="w-full px-2.5 py-2 rounded border border-slate-300 bg-white text-xs">
              ${DENY_REASONS.map(x => `<option>${esc(x)}</option>`).join('')}
            </select>
            <label for="gateDenyNotes" class="block text-[11px] font-bold text-slate-700">Notes (optional)</label>
            <textarea id="gateDenyNotes" rows="2" class="w-full px-2.5 py-2 rounded border border-slate-300 bg-white text-xs" placeholder="What did you observe?"></textarea>
            <div class="flex justify-end gap-2">
              <button type="button" data-act="deny-cancel" class="px-3 py-1.5 rounded border border-slate-300 bg-white text-xs font-semibold text-slate-700 cursor-pointer">Back</button>
              <button type="button" data-act="deny-confirm" class="px-3 py-1.5 rounded bg-ncst-crimson hover:bg-red-700 text-white text-xs font-bold cursor-pointer">Deny &amp; Flag Vehicle</button>
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
          ${r.result === 'NOT_FOUND' && r.gateType === 'Ingress' ? '<button type="button" data-act="visitor" class="px-3 py-2.5 rounded-md border border-sky-300 bg-sky-50 hover:bg-sky-100 text-sm font-bold text-sky-800 cursor-pointer">Issue Visitor Pass</button>' : ''}
          ${r.vehicle ? '<button type="button" data-act="warn" class="px-3 py-2.5 rounded-md border border-amber-300 bg-amber-50 hover:bg-amber-100 text-sm font-bold text-amber-900 cursor-pointer">Issue Warning</button>' : ''}
          <button type="button" data-act="reset" class="px-5 py-2.5 rounded-md bg-slate-900 hover:bg-slate-800 text-white text-sm font-bold cursor-pointer">Scan Next</button>
        </div>`;
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
      ${warnings ? `<ul class="px-5 py-3 space-y-1 text-xs text-amber-900 bg-amber-50 border-b border-amber-200">${warnings}</ul>` : ''}
      ${subject}
      ${actions}`;

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
          if (res.banned && r.accepted && r.gateType === 'Ingress') {
            // The vehicle just got banned: this entry can no longer be approved
            resetResult();
            SP.showToast(`${r.vehicle.plateNumber} is now BANNED. Entry must be refused.`);
            return;
          }
          r.vehicle.warningCount = res.vehicle.warningCount;
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
  }

  function vehicleBlock(v, r) {
    const strikes = Number(v.warningCount || 0);
    const standing = v.isBanned
      ? '<span class="px-2 py-0.5 rounded bg-ncst-crimson text-white text-[10px] font-extrabold">BANNED</span>'
      : (strikes > 0 ? `<span class="px-2 py-0.5 rounded bg-amber-100 text-amber-900 border border-amber-300 text-[10px] font-extrabold">STRIKE ${strikes} OF 3</span>` : '');
    const drivers = v.authorizedDrivers || [];
    const ownerPhoto = v.ownerPhoto || v.ownerPhotoUrl;

    const driverCards = drivers.map(d => {
      const id = Number(d.id);
      const selected = gate.driverId === id;
      const isOwner = /self|owner/i.test(d.relationship || '');
      const photo = d.photoUrl || d.photo_url || (isOwner ? ownerPhoto : '');
      return `
        <button type="button" role="radio" aria-checked="${selected}" data-driver-id="${id}" ${r.accepted ? '' : 'disabled'}
          class="text-left flex items-center gap-3 p-2.5 rounded-lg border-2 transition-colors ${selected ? 'border-emerald-500 bg-emerald-50' : 'border-slate-200 bg-white hover:border-slate-400'} ${r.accepted ? 'cursor-pointer' : 'cursor-default opacity-80'}">
          ${photoHtml(photo, d.fullName)}
          <div class="min-w-0 flex-1">
            <div class="text-sm font-bold text-slate-900 truncate">${esc(d.fullName)}</div>
            <div class="text-[11px] text-slate-500 truncate">${esc(d.relationship || '')}</div>
            <div class="text-[10px] font-mono text-slate-400 truncate">Lic. ${esc(d.licenseNo || d.license_no || 'N/A')}</div>
          </div>
          ${selected ? '<span class="text-emerald-600 text-lg" aria-hidden="true">&#10003;</span>' : ''}
        </button>`;
    }).join('');

    return `
      <div class="px-5 py-4 space-y-4">
        <div class="flex items-start gap-3">
          ${photoHtml(v.vehiclePhoto || v.vehiclePicture, v.plateNumber, 'w-20 h-14')}
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <span class="px-2 py-0.5 rounded bg-slate-900 text-ncst-gold font-mono font-extrabold text-base tracking-wider">${esc(v.plateNumber)}</span>
              ${standing}
              <span class="text-[10px] font-semibold text-slate-500">${esc(v.registrationStatus || '')} &middot; ${esc(v.status || '')}</span>
            </div>
            <div class="text-sm font-semibold text-slate-800 mt-1 truncate">${esc(v.makeModelColor || v.vehicleType || '')}</div>
            <div class="text-[11px] text-slate-500 truncate">Owner: <span class="font-semibold text-slate-700">${esc(v.ownerName)}</span> &middot; ${esc(v.ownerRole || '')} &middot; ${esc(v.ownerIdNumber || '')}</div>
            <div class="text-[10px] text-slate-400 font-mono">${v.passId ? 'Pass ' + esc(v.passId) + ' &middot; valid until ' + esc(v.passValidUntil || '—') : ''}</div>
          </div>
        </div>
        <div>
          <div class="text-[11px] font-extrabold uppercase tracking-wider text-slate-500 mb-2">Authorized drivers ${r.accepted ? '&mdash; select who is driving' : ''}</div>
          <div role="radiogroup" aria-label="Driver behind the wheel" class="grid grid-cols-1 sm:grid-cols-2 gap-2">${driverCards || '<p class="text-xs text-slate-400">No drivers on record.</p>'}</div>
        </div>
      </div>`;
  }

  function visitorBlock(v) {
    return `
      <div class="px-5 py-4">
        <div class="flex items-start gap-3 p-3 rounded-lg border-2 border-sky-300 bg-sky-50">
          ${photoHtml('', v.visitorName)}
          <div class="min-w-0 flex-1 text-xs space-y-0.5">
            <div class="flex flex-wrap items-center gap-2">
              <span class="px-2 py-0.5 rounded bg-slate-900 text-ncst-gold font-mono font-extrabold text-sm tracking-wider">${esc(v.plateNumber)}</span>
              <span class="px-1.5 py-0.5 rounded bg-sky-600 text-white text-[10px] font-extrabold">VISITOR DAY PASS</span>
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
      <div class="mt-3 rounded-lg border-2 ${gate.itemsChecked ? 'border-emerald-400 bg-emerald-50' : 'border-amber-300 bg-amber-50'} p-3">
        <div class="text-[11px] font-extrabold uppercase tracking-wider text-slate-700">Declared items (${items.length})</div>
        <ul class="mt-1.5 space-y-1 text-sm text-slate-900">
          ${items.map(i => `<li class="flex gap-2"><span class="font-mono font-extrabold w-12 text-right flex-shrink-0">${esc(i.quantity)}&times;</span><span><span class="font-semibold">${esc(i.name)}</span>${i.description ? ` <span class="text-slate-500 text-xs">(${esc(i.description)})</span>` : ''}</span></li>`).join('')}
        </ul>
        ${r.accepted ? `
        <label class="mt-2 flex items-center gap-2 text-xs font-bold text-slate-800 cursor-pointer">
          <input type="checkbox" data-act="items-check" class="w-4 h-4 accent-emerald-600" ${gate.itemsChecked ? 'checked' : ''}>
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

  async function approve() {
    const r = gate.result;
    if (!r || gate.busy) return;
    const plate = r.vehicle ? r.vehicle.plateNumber : r.visitor.plateNumber;
    const action = r.gateType === 'Ingress' ? 'Entry Recorded' : 'Exit Approved';
    const payload = { plate, action, gate_type: r.gateType, qr_code: gate.input.startsWith('{') ? gate.input : undefined };
    if (r.vehicle) payload.driver_id = gate.driverId;
    else if (r.visitor) {
      payload.visitor_pass_id = r.visitor.id;
      if ((r.visitor.items || []).length) payload.items_verified = gate.itemsChecked;
    }
    if ((r.warnings || []).length) payload.notes = `Verified (${r.result}) with alerts: ${r.warnings.join(' | ')}`;
    else payload.notes = `Verified (${r.result})`;

    gate.busy = true;
    try {
      const log = await ApiClient.createLog(payload);
      SP.showToast(`${action.toUpperCase()}: ${log.plateNumber} — ${log.driverName}`);
      afterDecision();
    } catch (err) {
      renderError(err.message || 'Could not record the decision.');
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
    try {
      await ApiClient.createLog({
        plate, action, gate_type: r.gateType,
        driverName: drv ? drv.fullName : (r.visitor ? r.visitor.visitorName : 'Unverified'),
        driverRelationship: drv ? drv.relationship : (r.visitor ? 'Visitor (Day Pass)' : 'Unverified'),
        notes: detail
      });
      const incident = await ApiClient.createIncident({
        plateNumber: plate,
        reason,
        vehicleType: r.vehicle ? r.vehicle.vehicleType : 'Visitor Vehicle',
        ownerName: r.vehicle ? r.vehicle.ownerName : r.visitor.visitorName,
        ownerRole: r.vehicle ? r.vehicle.ownerRole : 'Visitor',
        driverName: drv ? drv.fullName : 'Unverified',
        driverRelationship: drv ? drv.relationship : 'Unverified',
        gatePoint: r.gateType === 'Ingress' ? 'Gate 1 (Main Ingress)' : 'Gate 2 (Main Egress)',
        notes: `${action} at gate verification. ${notes}`.trim()
      });
      SP.showToast(`${action.toUpperCase()}: ${plate} flagged (${incident.caseNumber}).`);
      afterDecision();
    } catch (err) {
      renderError(err.message || 'Could not record the denial.');
    } finally {
      gate.busy = false;
    }
  }

  async function afterDecision() {
    resetResult();
    if (window.SP && SP.reload) await SP.reload();
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
      const chip = denied ? 'bg-rose-50 text-ncst-crimson border-rose-200' : (exit ? 'bg-blue-50 text-ncst-navy border-blue-200' : 'bg-emerald-50 text-emerald-700 border-emerald-200');
      return `
        <li class="px-4 py-2 flex items-center gap-3">
          <span class="px-1.5 py-0.5 rounded border text-[10px] font-bold whitespace-nowrap ${chip}">${esc(l.action)}</span>
          <span class="font-mono font-bold text-slate-800">${esc(l.plateNumber)}</span>
          <span class="text-slate-500 truncate flex-1">${esc(l.driverName || '')}</span>
          <span class="text-[10px] text-slate-400 whitespace-nowrap">${esc(l.timestamp || '')}</span>
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
        { facingMode: 'environment' },
        { fps: 10, qrbox: { width: 220, height: 220 } },
        (text) => { if (!gate.result && !gate.busy) verify(text); },
        () => {}
      );
      gate.cameraOn = true;
      $('gateCameraBtn').textContent = 'Stop Camera';
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
    if ($('gateCameraBox')) $('gateCameraBox').classList.add('hidden');
    if ($('gateCameraBtn')) $('gateCameraBtn').textContent = 'Start Camera';
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
    $('gateManualForm').addEventListener('submit', (e) => {
      e.preventDefault();
      verify($('gateManualInput').value);
    });
    $('gateCameraBtn').addEventListener('click', () => (gate.cameraOn ? stopCamera() : startCamera()));
    document.addEventListener('sp:data-loaded', renderRecent);

    // Turn the camera off whenever the Gate Monitor is not on screen
    new MutationObserver(() => {
      if (!$('gateView').classList.contains('active') && gate.cameraOn) stopCamera();
    }).observe($('gateView'), { attributes: true, attributeFilter: ['class'] });
  });
})();
