/**
 * SecurePark - Violations
 *
 *   SPViolations.openFlagModal(vehicle, { context, onDone })
 *
 * Guards and admins issue violations. A pending violation puts the vehicle on hold: it can neither enter
 * nor leave campus. Admins resolve (notes required) or dismiss it, which lifts the hold.
 * All rules are enforced by the server (lib/violations.php); this file is presentation.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const TYPES = [
    'Overnight / Unauthorized Overtime Parking',
    'Unauthorized Driver at Helm',
    'Expired Campus Registration Sticker',
    'Reckless / Prohibited Driving on Campus',
    'Parking in Fire Lane / Restricted Zone',
    'Refusal of Inspection / Gate Bypass',
    'Other'
  ];

  const view = { records: [], flagTarget: null, flagOptions: {}, resolveTarget: null, page: 1, pageSize: 10 };
  let recordsRequest = 0;
  let refreshInProgress = false;

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));
  const isAdmin = () => !!(window.SPAuth && SPAuth.hasRole('admin'));

  function formatDate(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }));
  }

  function holdBadge(onHold) {
    return onHold
      ? '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-extrabold bg-rose-50 text-rose-700 border border-rose-200"><span class="w-1.5 h-1.5 rounded-full bg-rose-600"></span>ON HOLD</span>'
      : '<span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold bg-slate-100 text-slate-600 border border-slate-200">Clear</span>';
  }

  function violationBadge() {
    return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-semibold bg-rose-50 text-rose-700 border border-rose-200"><span class="w-1.5 h-1.5 rounded-full bg-rose-600"></span>Violation</span>';
  }

  function statusBadge(st) {
    const cls = st === 'Pending' ? 'bg-amber-50 text-amber-800 border-amber-200'
      : st === 'Resolved' ? 'bg-emerald-50 text-emerald-700 border-emerald-200/80'
      : 'bg-slate-100 text-slate-700 border-slate-200';
    return `<span class="px-2 py-0.5 rounded border text-[11px] font-semibold ${cls}">${esc(st)}</span>`;
  }

  function showModal(id) { $(id).classList.remove('hidden'); $(id).classList.add('flex'); }
  function hideModal(id) { $(id).classList.add('hidden'); $(id).classList.remove('flex'); }
  function setError(id, msg) { $(id).textContent = msg || ''; $(id).classList.toggle('hidden', !msg); }

  /* ------------------------------------------------------------------------
     Issue-violation modal
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
        <span class="sp-plate tracking-wider">${esc(vehicle.plateNumber)}</span>
        <span class="font-semibold text-slate-700">${esc(vehicle.ownerName || '')}</span>
        ${holdBadge(vehicle.isBanned)}
      </div>
      ${options.context ? `<div class="mt-1 text-[10px] text-slate-400">${esc(options.context)}</div>` : ''}`;

    $('flagType').innerHTML = TYPES.map(t => `<option>${esc(t)}</option>`).join('');
    if (options.defaultType) $('flagType').value = options.defaultType;
    $('flagNotes').value = options.context ? options.context + '. ' : '';
    updateHoldHint();
    setError('flagError', '');
    showModal('flagModal');
    setTimeout(() => $('flagType').focus(), 50);
  }

  function updateHoldHint() {
    const v = view.flagTarget;
    if (!v) return;
    $('flagHoldHint').textContent = v.isBanned
      ? `${v.plateNumber} is already on hold. This adds another violation, and every violation must be resolved before it can enter or leave.`
      : `${v.plateNumber} will not be able to enter or leave campus until an administrator resolves this violation.`;
  }

  async function submitFlag(e) {
    e.preventDefault();
    const v = view.flagTarget;
    const type = $('flagType').value;
    const notes = $('flagNotes').value.trim();
    if (type === 'Other' && !notes) return setError('flagError', 'Describe the violation in the notes when choosing "Other".');

    $('flagSubmitBtn').disabled = true;
    try {
      const res = await ApiClient.createViolation({ vehicle_id: v.id, type, notes });
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
      local.isBanned = serverVehicle.isBanned;
      local.registrationStatus = serverVehicle.registrationStatus;
      local.registration_status = serverVehicle.registrationStatus;
      local.status = serverVehicle.status;
    }
  }

  /* ------------------------------------------------------------------------
     Resolve / dismiss modal (admin)
     ------------------------------------------------------------------------ */
  function openResolveModal(target) {
    view.resolveTarget = target;
    const titles = { resolve: 'Resolve Violation', dismiss: 'Dismiss Violation' };
    $('resolveModalTitle').textContent = titles[target.action];
    let summary = '';
    if (target.action === 'resolve') summary = `Resolving "${target.record.violationType}" on ${target.record.plateNumber} lets the vehicle enter and leave campus again (if no other violation is pending).`;
    if (target.action === 'dismiss') summary = `Dismiss this violation on ${target.record.plateNumber} as issued by mistake. The hold is lifted if nothing else is pending.`;
    $('resolveModalSummary').textContent = summary;
    $('resolveNotes').value = '';
    $('resolveSubmitBtn').textContent = titles[target.action];
    $('resolveSubmitBtn').className = 'px-4 py-2 rounded-md text-white text-xs font-bold cursor-pointer disabled:opacity-60 ' +
      (target.action === 'dismiss' ? 'bg-slate-700 hover:bg-slate-800' : 'bg-ncst-green hover:bg-ncst-greenDark');
    setError('resolveError', '');
    showModal('resolveModal');
    setTimeout(() => $('resolveNotes').focus(), 50);
  }

  async function submitResolve(e) {
    e.preventDefault();
    const t = view.resolveTarget;
    const notes = $('resolveNotes').value.trim();
    if (!notes) return setError('resolveError', 'Resolution notes are required (e.g. "Fine paid / clearance signed").');
    const body = { violation_id: t.record.id, action: t.action, notes };
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
  async function loadRecords({ silent = false } = {}) {
    const request = ++recordsRequest;
    const body = $('violTableBody');
    $('violRecordsRegion').setAttribute('aria-busy', 'true');
    if (!silent) body.innerHTML = `<tr><td colspan="${isAdmin() ? 5 : 4}" class="sp-violations-empty">Loading records&hellip;</td></tr>`;
    try {
      const records = await ApiClient.getViolations({ status: $('violStatusFilter').value });
      if (request !== recordsRequest) return;
      view.records = records;
      renderRecords();
    } catch (err) {
      if (request !== recordsRequest) return;
      body.innerHTML = `<tr><td colspan="${isAdmin() ? 5 : 4}" class="sp-violations-empty text-ncst-crimson" role="alert">${esc(err.message)}<br>Use Refresh to try again.</td></tr>`;
      $('violPaginationInfo').textContent = 'Records could not be loaded';
      $('violRecordsCount').textContent = 'Unavailable';
      $('violPrevBtn').disabled = $('violNextBtn').disabled = true;
    } finally {
      if (request === recordsRequest) $('violRecordsRegion').setAttribute('aria-busy', 'false');
    }
  }

  function renderRecords() {
    const q = ($('violSearch').value || '').trim().toLowerCase();
    const rows = view.records.filter(r => !q ||
      [r.plateNumber, r.ownerName, r.violationType, r.loggedBy, r.description, r.resolutionNotes].some(x => String(x || '').toLowerCase().includes(q)));
    const pages = Math.max(1, Math.ceil(rows.length / view.pageSize));
    view.page = Math.min(Math.max(1, view.page), pages);
    const start = (view.page - 1) * view.pageSize;
    $('violRecordsCount').textContent = `${rows.length} ${rows.length === 1 ? 'record' : 'records'}`;
    $('violPaginationInfo').textContent = rows.length ? `Showing ${start + 1}–${Math.min(start + view.pageSize, rows.length)} of ${rows.length} records` : '0 matching records';
    $('violPageIndicator').textContent = `Page ${view.page} of ${pages}`;
    $('violPrevBtn').disabled = view.page <= 1;
    $('violNextBtn').disabled = view.page >= pages;
    const body = $('violTableBody');
    const admin = isAdmin();
    if (!rows.length) {
      body.innerHTML = `<tr><td colspan="${admin ? 5 : 4}" class="sp-violations-empty"><strong>${q ? 'No records match your search' : 'No records in this status'}</strong><p>${q ? 'Try a different plate, owner, or issue.' : 'Choose another status to view the record history.'}</p></td></tr>`;
      return;
    }
    body.innerHTML = '';
    rows.slice(start, start + view.pageSize).forEach(r => {
      const tr = document.createElement('tr');
      const detail = r.description || r.resolutionNotes;
      tr.innerHTML = `
        <td><span class="sp-plate">${esc(r.plateNumber)}</span><small class="sp-cell-detail sp-violation-owner">${esc(r.ownerName || 'Owner not recorded')}</small></td>
        <td>${violationBadge()}<div class="sp-violation-issue">${esc(r.violationType)}</div>
          ${detail ? `<details class="sp-violation-details"><summary>View notes${r.resolutionNotes ? ' &amp; resolution' : ''}</summary>${r.description ? `<p>${esc(r.description)}</p>` : ''}${r.resolutionNotes ? `<p><strong>${esc(r.status)} by ${esc(r.resolvedBy || 'administrator')}</strong><br>${esc(r.resolutionNotes)}</p>` : ''}</details>` : ''}
        </td>
        <td><time>${formatDate(r.createdAt)}</time><small class="sp-cell-detail">${esc(r.loggedBy || 'Officer not recorded')}</small></td>
        <td>${statusBadge(r.status)}</td>
        <td class="admin-only"><div class="sp-violation-actions">
          ${admin && r.status === 'Pending' ? `<button type="button" data-act="resolve" class="sp-review-button" aria-label="Resolve violation for ${esc(r.plateNumber)}">Resolve</button>` : ''}
          ${admin && r.status === 'Pending' ? `<button type="button" data-act="dismiss" class="sp-violation-dismiss" aria-label="Dismiss record for ${esc(r.plateNumber)}">Dismiss</button>` : '<span class="sp-cell-detail">Completed</span>'}
        </div></td>`;
      tr.querySelector('[data-act="resolve"]')?.addEventListener('click', () => openResolveModal({ action:'resolve', record:r }));
      tr.querySelector('[data-act="dismiss"]')?.addEventListener('click', () => openResolveModal({ action:'dismiss', record:r }));
      body.appendChild(tr);
    });
  }

  function renderWatchList() {
    if (!window.SP) return;
    const held = SP.state.vehicles.filter(v => v.isBanned);

    $('violStatBanned').textContent = held.length;

    const list = $('violWatchList');
    if (!held.length) {
      list.innerHTML = '<div class="px-4 py-4 text-center text-xs text-slate-400">No vehicles are on hold.</div>';
      return;
    }
    list.innerHTML = '<div class="overflow-x-auto" role="region" aria-label="Vehicles on hold" tabindex="0"><table class="sp-watch-table w-full text-left"><thead><tr><th scope="col">Vehicle</th><th scope="col">Owner</th><th scope="col">Status</th><th scope="col">Actions</th></tr></thead><tbody></tbody></table></div>';
    const watchBody = list.querySelector('tbody');
    held.forEach(v => {
      const row = document.createElement('tr');
      row.innerHTML = `
        <td><span class="sp-plate">${esc(v.plateNumber)}</span></td>
        <td><span>${esc(v.ownerName || 'Not recorded')}</span>${v.ownerPhone ? `<small class="sp-cell-detail">${esc(v.ownerPhone)}</small>` : ''}</td>
        <td>${holdBadge(true)}</td>
        <td><div class="sp-watch-actions"><button type="button" data-act="flag" class="sp-review-button" aria-label="Add a violation for ${esc(v.plateNumber)}">Add violation</button></div></td>`;
      row.querySelector('[data-act="flag"]').addEventListener('click', () => openFlagModal(v));
      watchBody.appendChild(row);
    });
  }

  async function updatePendingCount() {
    try {
      const pending = await ApiClient.getViolations({ status: 'Pending' });
      const stat = $('violStatPending');
      if (stat) stat.textContent = pending.length;
      const badge = $('violationsSidebarCount');
      if (badge) {
        badge.textContent = pending.length;
        badge.dataset.empty = String(pending.length === 0);
        badge.title = pending.length ? `${pending.length} pending violation${pending.length === 1 ? '' : 's'}` : 'No pending violations';
        badge.className = "sp-sidebar-count";
      }
    } catch (_) { /* badge is optional */ }
  }

  async function refreshAfterChange() {
    if (refreshInProgress) return;
    refreshInProgress = true;
    try {
      if (window.SP && SP.reload) await SP.reload();
      if ($('violationsView').classList.contains('active')) {
        renderWatchList();
        await loadRecords({ silent: true });
      }
      await updatePendingCount();
    } finally {
      refreshInProgress = false;
    }
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
    $('resolveForm').addEventListener('submit', submitResolve);
    $('resolveCancelBtn').addEventListener('click', () => hideModal('resolveModal'));
    $('violStatusFilter').addEventListener('change', () => { view.page = 1; loadRecords(); });
    $('violSearch').addEventListener('input', () => { view.page = 1; renderRecords(); });
    $('violPrevBtn').addEventListener('click', () => { view.page--; renderRecords(); });
    $('violNextBtn').addEventListener('click', () => { view.page++; renderRecords(); });
    $('violationsRefreshBtn').addEventListener('click', refreshAfterChange);

    document.addEventListener('sp:data-loaded', () => {
      if (refreshInProgress) return;
      if ($('violationsView').classList.contains('active')) { renderWatchList(); loadRecords({ silent: true }); }
      updatePendingCount();
    });
  });

  window.SPViolations = { openFlagModal };
})();
