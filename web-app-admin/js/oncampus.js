/**
 * SecurePark - On Campus Now
 *
 * One list of everything inside campus right now: registered vehicles (flag a warning /
 * violation) and visitors on day passes (report an incident, see declared items).
 * Refreshes every minute while the page is open; the sidebar badge shows the live count.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const REFRESH_MS = 60 * 1000;
  const STRIKE_LIMIT = 3;
  const view = { data: null, filter: 'all', timer: null, incidentTarget: null };

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  function fmtTime(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    const sameDay = d.toDateString() === new Date().toDateString();
    return esc(d.toLocaleString('en-PH', sameDay
      ? { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit' }
      : { timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }));
  }

  function duration(hours) {
    if (hours == null) return 'unknown';
    if (hours < 1) return `${Math.max(1, Math.round(hours * 60))} min`;
    const h = Math.floor(hours);
    const m = Math.round((hours - h) * 60);
    return m ? `${h} h ${m} min` : `${h} h`;
  }

  function tel(phone) {
    const digits = String(phone || '').replace(/[^\d+]/g, '');
    return digits ? `<a href="tel:${esc(digits)}" class="font-mono text-ncst-navy hover:underline">${esc(phone)}</a>` : '<span class="text-slate-400">no contact on file</span>';
  }

  function standing(v) {
    if (v.isBanned) return '<span class="px-1.5 py-0.5 rounded bg-ncst-crimson text-white text-[10px] font-extrabold">BANNED</span>';
    const n = Math.min(Number(v.warningCount || 0), STRIKE_LIMIT);
    if (!n) return '<span class="px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200 text-[10px] font-bold">No strikes</span>';
    return `<span class="px-1.5 py-0.5 rounded bg-amber-100 text-amber-900 border border-amber-300 text-[10px] font-extrabold">STRIKE ${n} OF ${STRIKE_LIMIT}</span>`;
  }

  function timeChip(flag) {
    if (flag === 'overnight') return '<span class="px-1.5 py-0.5 rounded bg-indigo-600 text-white text-[10px] font-extrabold">OVERNIGHT</span>';
    if (flag === 'overtime') return '<span class="px-1.5 py-0.5 rounded bg-amber-400 text-slate-900 text-[10px] font-extrabold">OVERTIME</span>';
    if (flag === 'overstayed') return '<span class="px-1.5 py-0.5 rounded bg-indigo-600 text-white text-[10px] font-extrabold">PASS EXPIRED</span>';
    return '';
  }

  function itemsHtml(items) {
    if (!items || !items.length) return '';
    return `<div class="mt-2 flex flex-wrap items-center gap-1.5">
      <span class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Items brought in:</span>
      ${items.map(i => `<span class="px-1.5 py-0.5 rounded bg-sky-50 border border-sky-200 text-sky-900 text-[11px] font-semibold">${esc(i.quantity)}&times; ${esc(i.name)}${i.description ? ` <span class="font-normal text-sky-700">(${esc(i.description)})</span>` : ''}</span>`).join('')}
    </div>`;
  }

  /* ---------------- data ---------------- */
  async function load() {
    try {
      view.data = await ApiClient.getOnCampus();
      updateBadge();
      if ($('onCampusView').classList.contains('active')) render();
    } catch (err) {
      if (err.status !== 401 && $('onCampusView').classList.contains('active')) {
        $('ocList').innerHTML = `<div class="px-4 py-6 text-center text-xs text-ncst-crimson">${esc(err.message)}</div>`;
      }
    }
  }

  function updateBadge() {
    const badge = $('onCampusSidebarCount');
    if (badge && view.data) badge.textContent = view.data.counts.total;
  }

  /* ---------------- render ---------------- */
  function render() {
    const d = view.data;
    if (!d) return;
    $('ocTotal').textContent = d.counts.total;
    $('ocRegistered').textContent = d.counts.registered;
    $('ocVisitors').textContent = d.counts.visitors;
    $('ocAttention').textContent = d.counts.flagged + d.vehicles.filter(v => (v.warningCount > 0 || v.isBanned) && !v.timeFlag).length;
    $('onCampusUpdated').textContent = `Updated ${fmtTime(d.now)}`;

    document.querySelectorAll('#ocFilter .oc-filter').forEach(b => {
      const on = b.dataset.filter === view.filter;
      b.setAttribute('aria-selected', on ? 'true' : 'false');
      b.className = 'oc-filter px-2.5 py-1 rounded cursor-pointer ' + (on ? 'bg-white text-ncst-navy shadow-xs' : 'text-slate-500 hover:text-slate-800');
    });

    const q = ($('ocSearch').value || '').trim().toLowerCase();
    const match = (...fields) => !q || fields.some(f => String(f || '').toLowerCase().includes(q));

    const vehicles = d.vehicles.filter(v =>
      (view.filter === 'all' || view.filter === 'registered' || (view.filter === 'attention' && (v.timeFlag || v.warningCount > 0 || v.isBanned))) &&
      match(v.plateNumber, v.ownerName, v.enteredBy, v.makeModelColor, v.department));
    const visitors = d.visitors.filter(p =>
      (view.filter === 'all' || view.filter === 'visitors' || (view.filter === 'attention' && p.overstayed)) &&
      match(p.plateNumber, p.visitorName, p.personToVisit, p.purposeOfVisit));

    const list = $('ocList');
    if (!vehicles.length && !visitors.length) {
      list.innerHTML = `<div class="px-4 py-8 text-center">
        <div class="text-sm font-bold text-slate-700">${d.counts.total ? 'No vehicles match this filter' : 'Campus is empty'}</div>
        <div class="text-xs text-slate-500 mt-1">${d.counts.total ? 'Try another filter or clear the search.' : 'Vehicles appear here as soon as their entry is recorded at the gate.'}</div></div>`;
      return;
    }

    list.innerHTML = '';
    vehicles.forEach(v => list.appendChild(vehicleRow(v)));
    visitors.forEach(p => list.appendChild(visitorRow(p)));
  }

  function vehicleRow(v) {
    const row = document.createElement('div');
    const accent = v.isBanned ? 'border-l-ncst-crimson' : v.timeFlag === 'overnight' ? 'border-l-indigo-600' : v.timeFlag === 'overtime' ? 'border-l-amber-400' : v.warningCount > 0 ? 'border-l-amber-300' : 'border-l-emerald-500';
    row.className = `px-4 py-3 border-l-4 ${accent} hover:bg-slate-50/60`;
    row.innerHTML = `
      <div class="flex flex-wrap items-center gap-2">
        <span class="px-2 py-0.5 rounded bg-slate-900 text-ncst-gold font-mono font-extrabold text-sm tracking-wider">${esc(v.plateNumber)}</span>
        <span class="text-xs font-semibold text-slate-700">${esc(v.makeModelColor || v.vehicleType || '')}</span>
        ${timeChip(v.timeFlag)} ${standing(v)}
        <span class="ml-auto text-[11px] font-bold text-slate-700">Inside ${esc(duration(v.hoursInside))}</span>
      </div>
      <div class="mt-1.5 grid grid-cols-1 md:grid-cols-3 gap-x-4 gap-y-0.5 text-[11px] text-slate-600">
        <div class="truncate">Owner: <span class="font-semibold text-slate-800">${esc(v.ownerName)}</span> <span class="text-slate-400">${esc(v.ownerRole || '')}</span></div>
        <div class="truncate">Driven in by: <span class="font-semibold text-slate-800">${esc(v.enteredBy || 'not recorded')}</span></div>
        <div class="truncate">Contact: ${tel(v.ownerPhone)}</div>
        <div class="truncate">Entered: <span class="font-semibold text-slate-800">${fmtTime(v.entryTime)}</span> ${v.entryGate ? '&middot; ' + esc(v.entryGate) : ''}</div>
        <div class="truncate md:col-span-2">Admitted by: <span class="text-slate-700">${esc(v.admittedBy || '—')}</span></div>
      </div>
      <div class="mt-2 flex flex-wrap gap-1.5">
        <button type="button" data-act="flag" class="px-2.5 py-1 rounded bg-ncst-crimson hover:bg-red-700 text-white text-[11px] font-bold cursor-pointer">Flag Violation / Warning</button>
        <button type="button" data-act="dossier" class="px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-50 text-[11px] font-semibold text-slate-700 cursor-pointer">Open Dossier</button>
      </div>`;
    row.querySelector('[data-act="flag"]').addEventListener('click', () => {
      if (!window.SPViolations) return;
      SPViolations.openFlagModal({
        id: v.vehicleId, plateNumber: v.plateNumber, ownerName: v.ownerName,
        warningCount: v.warningCount, isBanned: v.isBanned
      }, {
        context: `On campus since ${fmtTime(v.entryTime).replace(/&[^;]+;/g, '')}, driven in by ${v.enteredBy || 'unknown driver'}`,
        onDone: () => load()
      });
    });
    row.querySelector('[data-act="dossier"]').addEventListener('click', () => {
      if (!SP.openVehicle(v.vehicleId)) SP.showToast('Vehicle details are still loading. Try again in a moment.');
    });
    return row;
  }

  function visitorRow(p) {
    const row = document.createElement('div');
    row.className = `px-4 py-3 border-l-4 ${p.overstayed ? 'border-l-indigo-600 bg-indigo-50/30' : 'border-l-sky-400'} hover:bg-slate-50/60`;
    row.innerHTML = `
      <div class="flex flex-wrap items-center gap-2">
        <span class="px-2 py-0.5 rounded bg-slate-900 text-ncst-gold font-mono font-extrabold text-sm tracking-wider">${esc(p.plateNumber)}</span>
        <span class="px-1.5 py-0.5 rounded bg-sky-600 text-white text-[10px] font-extrabold">VISITOR</span>
        <span class="text-xs font-semibold text-slate-700">${esc(p.vehicleModel || '')}</span>
        ${p.overstayed ? timeChip('overstayed') : ''}
        <span class="ml-auto text-[11px] font-bold text-slate-700">Inside ${esc(duration(p.hoursInside))}</span>
      </div>
      <div class="mt-1.5 grid grid-cols-1 md:grid-cols-3 gap-x-4 gap-y-0.5 text-[11px] text-slate-600">
        <div class="truncate">Visitor: <span class="font-semibold text-slate-800">${esc(p.visitorName)}</span></div>
        <div class="truncate">Visiting: <span class="font-semibold text-slate-800">${esc(p.personToVisit)}</span></div>
        <div class="truncate">Contact: ${tel(p.contactNumber)}</div>
        <div class="truncate">Entered: <span class="font-semibold text-slate-800">${fmtTime(p.entryTime)}</span></div>
        <div class="truncate md:col-span-2">Purpose: ${esc(p.purposeOfVisit)} &middot; Pass <span class="font-mono">${esc(p.passCode)}</span> (valid ${esc(p.validDate)})</div>
      </div>
      ${itemsHtml(p.items)}
      <div class="mt-2 flex flex-wrap gap-1.5">
        <button type="button" data-act="report" class="px-2.5 py-1 rounded bg-ncst-crimson hover:bg-red-700 text-white text-[11px] font-bold cursor-pointer">Report Incident</button>
        <button type="button" data-act="pass" class="px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-50 text-[11px] font-semibold text-slate-700 cursor-pointer">View Pass</button>
      </div>`;
    row.querySelector('[data-act="report"]').addEventListener('click', () => openIncident(p));
    row.querySelector('[data-act="pass"]').addEventListener('click', async () => {
      try {
        const pass = await ApiClient.getVisitorPass(p.passId);
        if (window.SPVisitors) SPVisitors.openCard(pass);
      } catch (err) {
        SP.showToast(err.message);
      }
    });
    return row;
  }

  /* ---------------- visitor incident ---------------- */
  function openIncident(p) {
    view.incidentTarget = p;
    $('visitorIncidentSummary').textContent = `${p.visitorName} · ${p.plateNumber} · visiting ${p.personToVisit}`;
    $('viReason').value = p.overstayed ? 'Overstayed day pass' : 'Parking in Fire Lane / Restricted Zone';
    $('viNotes').value = '';
    $('visitorIncidentError').classList.add('hidden');
    $('visitorIncidentModal').classList.remove('hidden');
    $('visitorIncidentModal').classList.add('flex');
    setTimeout(() => $('viReason').focus(), 50);
  }

  function closeIncident() {
    $('visitorIncidentModal').classList.add('hidden');
    $('visitorIncidentModal').classList.remove('flex');
  }

  async function submitIncident(e) {
    e.preventDefault();
    const p = view.incidentTarget;
    const reason = $('viReason').value;
    const notes = $('viNotes').value.trim();
    const err = $('visitorIncidentError');
    if (reason === 'Other' && !notes) {
      err.textContent = 'Describe what happened when choosing "Other".';
      err.classList.remove('hidden');
      return;
    }
    const itemsText = (p.items || []).map(i => `${i.quantity}x ${i.name}`).join(', ');
    $('visitorIncidentSubmitBtn').disabled = true;
    try {
      const res = await ApiClient.createIncident({
        plateNumber: p.plateNumber,
        reason,
        vehicleType: 'Visitor Vehicle',
        ownerName: p.visitorName,
        ownerRole: 'Visitor',
        driverName: p.visitorName,
        driverRelationship: 'Visitor (Day Pass)',
        gatePoint: 'Campus patrol (on campus)',
        notes: [`Day pass ${p.passCode}, visiting ${p.personToVisit}.`, itemsText ? `Declared items: ${itemsText}.` : '', notes].filter(Boolean).join(' ')
      });
      closeIncident();
      SP.showToast(`Security case ${res.caseNumber} opened for ${p.plateNumber}.`);
      if (SP.reload) SP.reload();
    } catch (e2) {
      err.textContent = e2.message;
      err.classList.remove('hidden');
    } finally {
      $('visitorIncidentSubmitBtn').disabled = false;
    }
  }

  /* ---------------- wiring ---------------- */
  function showView() {
    if (view.data) render();
    load();
  }

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('onCampusView', $('navOnCampusBtn'), showView);
    $('onCampusRefreshBtn').addEventListener('click', load);
    $('ocSearch').addEventListener('input', render);
    document.querySelectorAll('#ocFilter .oc-filter').forEach(b => b.addEventListener('click', () => { view.filter = b.dataset.filter; render(); }));
    $('kpiInsideLink').addEventListener('click', () => SP.switchView('onCampusView'));
    $('visitorIncidentForm').addEventListener('submit', submitIncident);
    $('visitorIncidentCancelBtn').addEventListener('click', closeIncident);

    // Gate decisions change who is inside: refresh with the rest of the data
    document.addEventListener('sp:data-loaded', load);
    SPAuth.whenAuthenticated(() => {
      load();
      if (view.timer) clearInterval(view.timer);
      view.timer = setInterval(load, REFRESH_MS);
    });
  });
})();
