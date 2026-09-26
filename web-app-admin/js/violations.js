/**
 * SecurePark - Violations & Penalties (3-strike policy)
 *
 *   SPViolations.openFlagModal(vehicle, { context, onDone })
 *
 * Guards: issue warnings, view active records. Admins: also issue violations,
 * resolve (notes required), dismiss mistakes and reset strikes.
 * All rules are enforced by the server (lib/strikes.php); this file is presentation.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const STRIKE_LIMIT = 3;
  const TYPES = [
    'Overnight / Unauthorized Overtime Parking',
    'Unauthorized Driver at Helm',
    'Expired Campus Registration Sticker',
    'Reckless / Prohibited Driving on Campus',
    'Parking in Fire Lane / Restricted Zone',
    'Refusal of Inspection / Gate Bypass',
    'Other'
  ];

  const view = { records: [], flagTarget: null, flagOptions: {}, resolveTarget: null };

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));
  const isAdmin = () => !!(window.SPAuth && SPAuth.hasRole('admin'));

  function formatDate(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }));
  }

  function strikeMeter(count, banned) {
    const n = Math.min(Number(count || 0), STRIKE_LIMIT);
    const pips = Array.from({ length: STRIKE_LIMIT }, (_, i) =>
      `<span class="w-3 h-3 rounded-full border ${i < n ? (banned || n >= STRIKE_LIMIT ? 'bg-ncst-crimson border-ncst-crimson' : 'bg-amber-400 border-amber-500') : 'bg-white border-slate-300'}"></span>`
    ).join('');
    const label = banned ? 'BANNED' : `Strike ${n} of ${STRIKE_LIMIT}`;
    return `<span class="inline-flex items-center gap-1" title="${label}">${pips}<span class="ml-1 text-[10px] font-extrabold ${banned ? 'text-ncst-crimson' : 'text-slate-600'}">${label}</span></span>`;
  }

  function severityBadge(sev) {
    return sev === 'Violation'
      ? '<span class="px-1.5 py-0.5 rounded bg-ncst-crimson text-white text-[10px] font-bold">Violation</span>'
      : '<span class="px-1.5 py-0.5 rounded bg-amber-100 text-amber-900 border border-amber-300 text-[10px] font-bold">Warning</span>';
  }

  function statusBadge(st) {
    const cls = st === 'Pending' ? 'bg-rose-50 text-ncst-crimson border-rose-200'
      : st === 'Resolved' ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
      : 'bg-slate-100 text-slate-500 border-slate-200';
    return `<span class="px-1.5 py-0.5 rounded border text-[10px] font-bold ${cls}">${esc(st)}</span>`;
  }

  function showModal(id) { $(id).classList.remove('hidden'); $(id).classList.add('flex'); }
  function hideModal(id) { $(id).classList.add('hidden'); $(id).classList.remove('flex'); }
  function setError(id, msg) { $(id).textContent = msg || ''; $(id).classList.toggle('hidden', !msg); }

  /* ------------------------------------------------------------------------
     Flag modal (warning / violation)
     ------------------------------------------------------------------------ */
  function findVehicle(v) {
    if (!v || !window.SP) return v;
    return SP.state.vehicles.find(x => x.id === v.id) || v;
  }

  function openFlagModal(vehicle, options = {}) {
    vehicle = findVehicle(vehicle);
    if (!vehicle || !vehicle.id || typeof vehicle.id !== 'number') {
      SP.showToast('Violations can only be issued to registered vehicles saved on the server.');
      return;
    }
    view.flagTarget = vehicle;
    view.flagOptions = options;

    $('flagVehicleSummary').innerHTML = `
      <div class="flex flex-wrap items-center gap-2">
        <span class="px-2 py-0.5 rounded bg-slate-900 text-ncst-gold font-mono font-extrabold tracking-wider">${esc(vehicle.plateNumber)}</span>
        <span class="font-semibold text-slate-700">${esc(vehicle.ownerName || '')}</span>
        ${strikeMeter(vehicle.warningCount, vehicle.isBanned)}
      </div>
      ${options.context ? `<div class="mt-1 text-[10px] text-slate-400">${esc(options.context)}</div>` : ''}`;

    $('flagType').innerHTML = TYPES.map(t => `<option>${esc(t)}</option>`).join('');
    if (options.defaultType) $('flagType').value = options.defaultType;
    $('flagNotes').value = options.context ? options.context + '. ' : '';
    document.querySelector('input[name="flagSeverity"][value="Warning"]').checked = true;

    const admin = isAdmin();
    const violationRadio = document.querySelector('input[name="flagSeverity"][value="Violation"]');
    violationRadio.disabled = !admin;
    $('flagSeverityViolationLabel').classList.toggle('opacity-40', !admin);
    $('flagSeverityViolationLabel').classList.toggle('cursor-not-allowed', !admin);
    $('flagGuardNote').classList.toggle('hidden', admin);

    updateStrikeHint();
    setError('flagError', '');
    showModal('flagModal');
    setTimeout(() => $('flagType').focus(), 50);
  }

  function updateStrikeHint() {
    const v = view.flagTarget;
    if (!v) return;
    const severity = document.querySelector('input[name="flagSeverity"]:checked').value;
    const next = Number(v.warningCount || 0) + 1;
    let hint = '';
    if (severity === 'Violation') hint = `This bans ${v.plateNumber} immediately until an administrator resolves it.`;
    else if (!v.isBanned && next >= STRIKE_LIMIT) hint = `This will be strike ${next} of ${STRIKE_LIMIT}: ${v.plateNumber} will be BANNED automatically.`;
    $('flagStrikeHint').textContent = hint;
    $('flagStrikeHint').classList.toggle('hidden', !hint);
    $('flagSubmitBtn').textContent = severity === 'Violation' ? 'Issue Violation' : `Record Warning (Strike ${Math.min(next, STRIKE_LIMIT)})`;
  }

  async function submitFlag(e) {
    e.preventDefault();
    const v = view.flagTarget;
    const type = $('flagType').value;
    const notes = $('flagNotes').value.trim();
    const severity = document.querySelector('input[name="flagSeverity"]:checked').value;
    if (type === 'Other' && !notes) return setError('flagError', 'Describe the violation in the notes when choosing "Other".');

    $('flagSubmitBtn').disabled = true;
    try {
      const res = await ApiClient.createViolation({ vehicle_id: v.id, type, severity, notes });
      hideModal('flagModal');
      applyVehicleUpdate(res.vehicle);
      SP.showToast(res.message);
      if (typeof view.flagOptions.onDone === 'function') view.flagOptions.onDone(res);
      refreshAfterChange();
    } catch (err) {
      setError('flagError', err.message);
    } finally {
      $('flagSubmitBtn').disabled = false;
    }
  }

  function applyVehicleUpdate(serverVehicle) {
    if (!serverVehicle || !window.SP) return;
    const local = SP.state.vehicles.find(x => x.id === serverVehicle.id);
    if (local) {
      local.warningCount = serverVehicle.warningCount;
      local.isBanned = serverVehicle.isBanned;
      local.registrationStatus = serverVehicle.registrationStatus;
      local.registration_status = serverVehicle.registrationStatus;
      local.status = serverVehicle.status;
    }
  }

  /* ------------------------------------------------------------------------
     Resolve / dismiss / reset modal (admin)
     ------------------------------------------------------------------------ */
  function openResolveModal(target) {
    view.resolveTarget = target;
    const titles = { resolve: 'Resolve Violation', dismiss: 'Dismiss Record', reset: 'Reset Strikes & Lift Suspension' };
    $('resolveModalTitle').textContent = titles[target.action];
    let summary = '';
    if (target.action === 'resolve') summary = `Resolving "${target.record.violationType}" on ${target.record.plateNumber} lifts the ban, restores the registration and resets the strikes (if no other violation is pending).`;
    if (target.action === 'dismiss') summary = target.record.severity === 'Warning'
      ? `Dismiss this warning on ${target.record.plateNumber} as issued by mistake. Its strike is removed.`
      : `Dismiss this violation on ${target.record.plateNumber} as issued by mistake. The ban is lifted if nothing else is pending.`;
    if (target.action === 'reset') summary = `Clear every pending warning and violation for ${target.vehicle.plateNumber}, set strikes to 0 and restore the registration.`;
    $('resolveModalSummary').textContent = summary;
    $('resolveNotes').value = '';
    $('resolveSubmitBtn').textContent = titles[target.action];
    $('resolveSubmitBtn').className = 'px-4 py-2 rounded-md text-white text-xs font-bold cursor-pointer disabled:opacity-60 ' +
      (target.action === 'dismiss' ? 'bg-slate-700 hover:bg-slate-800' : 'bg-emerald-600 hover:bg-emerald-700');
    setError('resolveError', '');
    showModal('resolveModal');
    setTimeout(() => $('resolveNotes').focus(), 50);
  }

  async function submitResolve(e) {
    e.preventDefault();
    const t = view.resolveTarget;
    const notes = $('resolveNotes').value.trim();
    if (!notes) return setError('resolveError', 'Resolution notes are required (e.g. "Fine paid / clearance signed").');
    const body = t.action === 'reset'
      ? { vehicle_id: t.vehicle.id, action: 'reset', notes }
      : { violation_id: t.record.id, action: t.action, notes };
    $('resolveSubmitBtn').disabled = true;
    try {
      const res = await ApiClient.updateViolation(body);
      hideModal('resolveModal');
      applyVehicleUpdate(res.vehicle);
      SP.showToast(res.message);
      refreshAfterChange();
    } catch (err) {
      setError('resolveError', err.message);
    } finally {
      $('resolveSubmitBtn').disabled = false;
    }
  }

  /* ------------------------------------------------------------------------
     Violations & Penalties view
     ------------------------------------------------------------------------ */
  async function loadRecords() {
    const body = $('violTableBody');
    try {
      view.records = await ApiClient.getViolations({ status: $('violStatusFilter').value });
      renderRecords();
    } catch (err) {
      body.innerHTML = `<tr><td colspan="7" class="px-4 py-6 text-center text-ncst-crimson">${esc(err.message)}</td></tr>`;
    }
  }

  function renderRecords() {
    const q = ($('violSearch').value || '').trim().toLowerCase();
    const rows = view.records.filter(r => !q ||
      [r.plateNumber, r.ownerName, r.violationType, r.loggedBy].some(x => (x || '').toLowerCase().includes(q)));
    const body = $('violTableBody');
    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="7" class="px-4 py-6 text-center text-slate-400">No records.</td></tr>';
      return;
    }
    const admin = isAdmin();
    body.innerHTML = '';
    rows.forEach(r => {
      const tr = document.createElement('tr');
      tr.className = 'align-top hover:bg-slate-50/60';
      const resolution = r.status !== 'Pending' && r.resolutionNotes
        ? `<div class="mt-1 text-[10px] text-slate-500">${esc(r.status)} by ${esc(r.resolvedBy || '')}: ${esc(r.resolutionNotes)}</div>` : '';
      tr.innerHTML = `
        <td class="px-4 py-2.5 whitespace-nowrap text-slate-600">${formatDate(r.createdAt)}</td>
        <td class="px-4 py-2.5">
          <div class="font-mono font-bold text-slate-900 whitespace-nowrap">${esc(r.plateNumber)}</div>
          <div class="text-[10px] text-slate-500">${esc(r.ownerName || '')}</div>
        </td>
        <td class="px-4 py-2.5">
          <div class="font-semibold text-slate-800">${esc(r.violationType)}</div>
          ${r.description ? `<div class="text-[10px] text-slate-500 max-w-xs">${esc(r.description)}</div>` : ''}
          ${resolution}
        </td>
        <td class="px-4 py-2.5">${severityBadge(r.severity)}</td>
        <td class="px-4 py-2.5 text-slate-600">${esc(r.loggedBy)}</td>
        <td class="px-4 py-2.5">${statusBadge(r.status)}</td>
        <td class="px-4 py-2.5 admin-only">
          <div class="flex justify-end gap-1.5">
            ${admin && r.status === 'Pending' && r.severity === 'Violation' ? '<button type="button" data-act="resolve" class="px-2.5 py-1 rounded bg-emerald-600 hover:bg-emerald-700 text-white text-[11px] font-bold cursor-pointer">Resolve</button>' : ''}
            ${admin && r.status === 'Pending' ? '<button type="button" data-act="dismiss" class="px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-50 text-[11px] font-semibold text-slate-700 cursor-pointer">Dismiss</button>' : ''}
          </div>
        </td>`;
      const resolveBtn = tr.querySelector('[data-act="resolve"]');
      if (resolveBtn) resolveBtn.addEventListener('click', () => openResolveModal({ action: 'resolve', record: r }));
      const dismissBtn = tr.querySelector('[data-act="dismiss"]');
      if (dismissBtn) dismissBtn.addEventListener('click', () => openResolveModal({ action: 'dismiss', record: r }));
      body.appendChild(tr);
    });
  }

  function renderWatchList() {
    if (!window.SP) return;
    const watched = SP.state.vehicles
      .filter(v => v.isBanned || Number(v.warningCount || 0) > 0)
      .sort((a, b) => (b.isBanned - a.isBanned) || (Number(b.warningCount) - Number(a.warningCount)));

    $('violStatBanned').textContent = watched.filter(v => v.isBanned).length;
    $('violStatStrikes').textContent = watched.filter(v => !v.isBanned).length;

    const list = $('violWatchList');
    if (!watched.length) {
      list.innerHTML = '<div class="px-4 py-4 text-center text-xs text-slate-400">No vehicles with strikes or bans.</div>';
      return;
    }
    const admin = isAdmin();
    list.innerHTML = '';
    watched.forEach(v => {
      const row = document.createElement('div');
      row.className = 'px-4 py-2.5 flex flex-wrap items-center gap-3 text-xs';
      row.innerHTML = `
        <span class="font-mono font-bold text-slate-900 w-24">${esc(v.plateNumber)}</span>
        <span class="text-slate-600 flex-1 min-w-[120px] truncate">${esc(v.ownerName || '')}${v.ownerPhone ? ' &middot; ' + esc(v.ownerPhone) : ''}</span>
        ${strikeMeter(v.warningCount, v.isBanned)}
        <div class="flex gap-1.5">
          <button type="button" data-act="flag" class="px-2.5 py-1 rounded border border-rose-300 bg-white hover:bg-rose-50 text-[11px] font-semibold text-ncst-crimson cursor-pointer">Flag</button>
          ${admin ? '<button type="button" data-act="reset" class="px-2.5 py-1 rounded border border-emerald-300 bg-emerald-50 hover:bg-emerald-100 text-[11px] font-semibold text-emerald-800 cursor-pointer">Reset Strikes &amp; Lift Suspension</button>' : ''}
        </div>`;
      row.querySelector('[data-act="flag"]').addEventListener('click', () => openFlagModal(v));
      const resetBtn = row.querySelector('[data-act="reset"]');
      if (resetBtn) resetBtn.addEventListener('click', () => openResolveModal({ action: 'reset', vehicle: v }));
      list.appendChild(row);
    });
  }

  async function updatePendingCount() {
    try {
      const pending = await ApiClient.getViolations({ status: 'Pending' });
      $('violStatPending').textContent = pending.length;
      const badge = $('violationsSidebarCount');
      badge.textContent = pending.length;
      badge.classList.toggle('hidden', pending.length === 0);
    } catch (_) { /* badge is optional */ }
  }

  async function refreshAfterChange() {
    if (window.SP && SP.reload) await SP.reload();
    if ($('violationsView').classList.contains('active')) {
      renderWatchList();
      loadRecords();
    }
    updatePendingCount();
  }

  function showView() {
    renderWatchList();
    loadRecords();
    updatePendingCount();
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  document.addEventListener('sp:app-ready', () => {
    SP.registerView('violationsView', $('navViolationsBtn'), showView);

    $('flagForm').addEventListener('submit', submitFlag);
    $('flagCancelBtn').addEventListener('click', () => hideModal('flagModal'));
    document.querySelectorAll('input[name="flagSeverity"]').forEach(r => r.addEventListener('change', updateStrikeHint));
    $('resolveForm').addEventListener('submit', submitResolve);
    $('resolveCancelBtn').addEventListener('click', () => hideModal('resolveModal'));
    $('violStatusFilter').addEventListener('change', loadRecords);
    $('violSearch').addEventListener('input', renderRecords);
    $('violationsRefreshBtn').addEventListener('click', refreshAfterChange);

    document.addEventListener('sp:data-loaded', () => {
      if ($('violationsView').classList.contains('active')) renderWatchList();
      updatePendingCount();
    });
  });

  window.SPViolations = { openFlagModal };
})();
