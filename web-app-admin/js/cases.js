/**
 * SecurePark - Cases
 *
 * Violations and security incidents in one list, handled with the same steps:
 *   Reported -> owner contacted (attempts are logged) -> [referred to police] -> awaiting clearance -> closed with an outcome.
 * Guards and administrators log steps; only administrators refer to the police or close a case.
 * All rules live on the server (lib/cases.php).
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));
  const isAdmin = () => window.SPAuth && SPAuth.hasRole('admin');

  const METHODS = ['Phone call', 'Text message', 'In person', 'E-mail', 'Other'];
  const RESULTS = ['Reached owner', 'No answer', 'Left message', 'Wrong or unreachable number'];
  const OUTCOMES = ['Clearance signed', 'Referred to police / vehicle removed', 'Dismissed'];

  let filter = { status: 'active', type: '', q: '', outcome: '', from: '', to: '', page: 1, limit: 25 };
  let data = { summary: { open: 0, awaiting: 0, closed: 0, policeReferred: 0, total: 0 }, cases: [], total: 0, page: 1, limit: 25 };
  let searchTimer = null;
  let ticket = 0;

  function fmt(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }));
  }

  const TYPE_TONE = {
    Violation: 'bg-rose-50 text-rose-700 border-rose-200',
    Security: 'bg-slate-100 text-slate-700 border-slate-300',
    Overnight: 'bg-indigo-50 text-indigo-700 border-indigo-200',
  };
  const typeBadge = (t) => `<span class="px-2 py-0.5 rounded text-[11px] font-semibold border ${TYPE_TONE[t] || TYPE_TONE.Security}">${esc(t)}</span>`;

  function stepBadge(c) {
    const tone = c.status === 'Closed' ? 'bg-emerald-50 text-emerald-700 border-emerald-200/80'
      : c.status === 'Awaiting clearance' ? 'bg-amber-50 text-amber-800 border-amber-200'
      : c.policeReferred ? 'bg-rose-50 text-rose-700 border-rose-200' : 'bg-sky-50 text-sky-800 border-sky-200';
    return `<span class="px-2 py-0.5 rounded text-[11px] font-semibold border ${tone}">${esc(c.step)}</span>`
      + (c.policeReferred && c.status !== 'Closed' && c.step !== 'Referred to police' ? ' <span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-rose-600 text-white">POLICE</span>' : '');
  }

  const btn = 'px-3 py-1.5 rounded-md text-xs font-semibold shadow-xs cursor-pointer';
  const navy = btn + ' bg-ncst-navy hover:bg-ncst-navyDark text-white';
  const plain = btn + ' border border-slate-200 bg-white hover:bg-slate-50 text-slate-700';
  const danger = btn + ' border border-rose-200 bg-white hover:bg-rose-50 text-rose-700';

  /* ------------------------------------------------------------------------
     List
     ------------------------------------------------------------------------ */
  function setSidebarCount(n) {
    const b = $('casesSidebarCount');
    if (!b) return;
    b.textContent = n;
    b.dataset.empty = String(!n);
  }

  async function load() {
    const mine = ++ticket;
    try {
      const res = await ApiClient.getCases(filter);
      if (mine !== ticket) return;
      data = res;
      setSidebarCount(res.summary.open + res.summary.awaiting);
      render();
    } catch (err) {
      $('casesBody').innerHTML = `<tr><td colspan="7" class="px-4 py-6 text-center text-ncst-crimson">${esc(err.message)}</td></tr>`;
    }
  }

  function renderSummary() {
    const s = data.summary;
    $('casesStatOpen').textContent = s.open;
    $('casesStatAwaiting').textContent = s.awaiting;
    $('casesStatPolice').textContent = s.policeReferred;
    $('casesStatClosed').textContent = s.closed;
  }

  function render() {
    renderSummary();
    document.querySelectorAll('#casesView [data-status]').forEach(b => {
      const on = b.dataset.status === filter.status;
      b.className = 'px-3.5 py-2 text-xs font-bold border-b-2 whitespace-nowrap cursor-pointer ' + (on ? 'border-ncst-navy text-ncst-navy' : 'border-transparent text-slate-500 hover:text-slate-800');
    });
    const body = $('casesBody');
    if (!data.cases.length) {
      body.innerHTML = '<tr><td colspan="7" class="px-4 py-10 text-center text-slate-400">No cases match.</td></tr>';
      renderPaging();
      return;
    }
    body.innerHTML = '';
    data.cases.forEach(c => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50/60 cursor-pointer';
      tr.innerHTML = `
        <td class="px-4 py-2.5 font-mono font-bold text-slate-900 whitespace-nowrap">${esc(c.plateNumber)}</td>
        <td class="px-4 py-2.5"><div class="font-semibold text-slate-800">${esc(c.ownerName || 'Unknown')}</div><div class="text-[11px] text-slate-500">${esc(c.ownerIdNumber || '')}</div></td>
        <td class="px-4 py-2.5">${typeBadge(c.type)}</td>
        <td class="px-4 py-2.5 text-slate-700">${esc(c.title)}${c.contactAttempts ? `<div class="text-[11px] text-slate-500">${c.contactAttempts} contact attempt${c.contactAttempts === 1 ? '' : 's'}${c.lastContactResult ? ' · last: ' + esc(c.lastContactResult) : ''}</div>` : ''}</td>
        <td class="px-4 py-2.5">${stepBadge(c)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap">${fmt(c.openedAt)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap">${c.closedAt ? fmt(c.closedAt) + (c.closedBy ? `<div class="text-[11px] text-slate-500">${esc(c.closedBy)}</div>` : '') : '<span class="text-slate-400">—</span>'}</td>`;
      tr.addEventListener('click', () => openCase(c.key));
      body.appendChild(tr);
    });
    renderPaging();
  }

  function renderPaging() {
    const pages = Math.max(1, Math.ceil((data.total || 0) / data.limit));
    $('casesPageInfo').textContent = `${data.total} case${data.total === 1 ? '' : 's'} · page ${data.page} of ${pages}`;
    $('casesPrev').disabled = data.page <= 1;
    $('casesNext').disabled = data.page >= pages;
  }

  /* ------------------------------------------------------------------------
     Case drawer
     ------------------------------------------------------------------------ */
  const ICON = { reported: '●', contact: '☎', awaiting: '⏳', police: '⚑', note: '✎', closed: '✔' };

  function timelineHtml(c) {
    return `<ol class="space-y-3">${c.timeline.map(t => `
      <li class="flex gap-3">
        <div class="w-6 h-6 rounded-full bg-slate-100 text-slate-600 text-[11px] flex items-center justify-center flex-shrink-0 mt-0.5" aria-hidden="true">${ICON[t.type] || '●'}</div>
        <div class="min-w-0">
          <div class="text-xs font-bold text-slate-900">${esc(t.label)}</div>
          ${t.detail ? `<div class="text-xs text-slate-700 break-words">${esc(t.detail)}</div>` : ''}
          <div class="text-[11px] text-slate-500">${fmt(t.at)}${t.by ? ' · ' + esc(t.by) : ''}</div>
        </div>
      </li>`).join('')}</ol>`;
  }

  async function openCase(key) {
    let c;
    try { c = await ApiClient.getCase(key); } catch (err) { SP.showToast(err.message, 'error'); return; }
    showCase(c);
  }

  function showCase(c) {
    const closed = c.status === 'Closed';
    const phone = c.ownerPhone ? `<a class="text-ncst-navy font-semibold" href="tel:${esc(c.ownerPhone)}">${esc(c.ownerPhone)}</a>` : '<span class="text-slate-400">no number on file</span>';
    const evidence = (c.evidence || []).length
      ? `<div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5">Photos</div><div class="flex flex-wrap gap-2">${c.evidence.map(e => e.purged
          ? '<span class="text-[11px] text-slate-400">photo deleted (retention)</span>'
          : `<button type="button" data-photo="${e.id}" class="${plain}">View photo${e.plateMatches === false ? ' · plate does not match' : ''}</button>`).join('')}</div></div>` : '';
    const html = `<div class="space-y-4">
        <div class="bg-white p-4 rounded-xl border border-slate-200 shadow-2xs space-y-2">
          <div class="flex flex-wrap items-center gap-2">${typeBadge(c.type)} ${stepBadge(c)}${c.approvalPending ? ' <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-200">Dismissal waiting for a second administrator</span>' : ''}</div>
          <div class="text-sm font-bold text-slate-900">${esc(c.title)}</div>
          ${c.description ? `<div class="text-xs text-slate-600">${esc(c.description)}</div>` : ''}
          <div class="grid grid-cols-2 gap-2 text-xs pt-1">
            <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Owner</div><div class="font-semibold text-slate-800">${esc(c.ownerName || 'Unknown')}</div><div class="text-slate-500">${esc(c.ownerIdNumber || '')}</div></div>
            <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Contact</div><div>${phone}</div></div>
          </div>
          ${c.caseNumber ? `<div class="text-[11px] text-slate-500">Case no. ${esc(c.caseNumber)}</div>` : ''}
          ${closed ? `<div class="text-[11px] text-slate-600 pt-1">Closed by ${esc(c.closedBy || '—')} · ${fmt(c.closedAt)}</div>` : ''}
        </div>
        ${evidence}
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2">Timeline</div>${timelineHtml(c)}</div>
      </div>`;

    const buttons = [];
    if (!closed) {
      buttons.push(`<button type="button" data-act="contact" class="${navy}">Log contact attempt</button>`);
      if (c.status !== 'Awaiting clearance') buttons.push(`<button type="button" data-act="awaiting" class="${plain}">Owner is coming in</button>`);
      buttons.push(`<button type="button" data-act="note" class="${plain}">Add note</button>`);
      if (isAdmin()) {
        if (!c.policeReferred) buttons.push(`<button type="button" data-act="police" class="${danger}">Refer to police</button>`);
        if (c.vehicle && c.vehicle.isBanned && c.vehicle.status === 'Inside Campus') buttons.push(`<button type="button" data-act="release" class="${plain}">Release one exit</button>`);
        buttons.push(`<button type="button" data-act="close" class="${navy}">Close case</button>`);
      }
    }
    if (c.incidentId && window.SP && SP.openIncident) buttons.push(`<button type="button" data-act="investigate" class="${plain}">Investigation file</button>`);
    buttons.push('<button id="drawerCancelBtnInner" type="button" class="px-3.5 py-2 rounded-md border border-slate-200 bg-white hover:bg-slate-100 text-xs font-medium text-slate-700 cursor-pointer">Close</button>');

    SP.openDrawer(`Case — ${c.plateNumber}`, c.key, html, `<div class="flex flex-wrap items-center gap-2">${buttons.join('')}</div>`);
    const footer = $('drawerFooter');
    footer.querySelectorAll('[data-act]').forEach(b => b.addEventListener('click', () => act(c, b.dataset.act)));
    $('drawerContent').querySelectorAll('[data-photo]').forEach(b => b.addEventListener('click', () => showPhoto(Number(b.dataset.photo))));
  }

  async function showPhoto(id) {
    try {
      const p = await ApiClient.getEvidencePhoto(id);
      if (typeof Swal === 'undefined' || !p.image) return;
      Swal.fire({ imageUrl: p.image, imageAlt: 'Evidence photo', title: p.plateRead ? `Plate read: ${p.plateRead}${p.plateMatches === false ? ' (does not match)' : ''}` : 'Evidence photo', confirmButtonText: 'Close', confirmButtonColor: '#253475' });
    } catch (err) { SP.showToast(err.message, 'error'); }
  }

  /* ------------------------------------------------------------------------
     Actions
     ------------------------------------------------------------------------ */
  const options = (list) => list.map(o => `<option>${esc(o)}</option>`).join('');
  const field = 'width:100%;margin-top:4px;padding:8px;border:1px solid #cbd5e1;border-radius:8px;font-size:13px';

  async function submit(c, action, body, working) {
    try {
      const res = await ApiClient.caseAction(c.key, action, body);
      SP.showToast(res.message, res.approvalPending ? 'warning' : 'success');
      if (SP.reload) SP.reload(true, true);
      load();
      if (res.case) showCase(res.case); else openCase(c.key);
      return true;
    } catch (err) {
      return err.message;
    }
  }

  async function act(c, name) {
    if (name === 'investigate') { SP.openIncident(c.incidentId); return; }
    if (name === 'release') { if (window.SPOps && await SPOps.releaseExit({ id: c.vehicle.id, plateNumber: c.plateNumber })) openCase(c.key); return; }
    if (typeof Swal === 'undefined') { SP.showToast('Dialogs failed to load. Reload the page.'); return; }
    let cfg;
    if (name === 'contact') {
      cfg = {
        title: 'Log contact attempt', confirm: 'Save attempt',
        html: `<div style="text-align:left;font-size:13px"><label>How did you try?<select id="cx_method" style="${field}">${options(METHODS)}</select></label>
          <label style="display:block;margin-top:10px">Result<select id="cx_result" style="${field}">${options(RESULTS)}</select></label>
          <label style="display:block;margin-top:10px">Note (optional)<textarea id="cx_note" rows="2" maxlength="500" style="${field}"></textarea></label></div>`,
        read: () => ({ method: $('cx_method').value, result: $('cx_result').value, note: $('cx_note').value.trim() }),
      };
    } else if (name === 'awaiting') {
      cfg = {
        title: 'Owner is coming in', confirm: 'Mark as waiting',
        html: `<div style="text-align:left;font-size:13px">The owner agreed to come to the Security Office to sign the clearance.
          <label style="display:block;margin-top:10px">Note (optional)<textarea id="cx_note" rows="2" maxlength="500" style="${field}" placeholder="e.g. Coming tomorrow morning"></textarea></label></div>`,
        read: () => ({ note: $('cx_note').value.trim() }),
      };
    } else if (name === 'note') {
      cfg = {
        title: 'Add note', confirm: 'Add note',
        html: `<div style="text-align:left;font-size:13px"><label>Note (staff only, the owner does not see it)<textarea id="cx_note" rows="3" maxlength="900" style="${field}"></textarea></label></div>`,
        read: () => ({ note: $('cx_note').value.trim() }),
        check: (v) => (v.note ? '' : 'Write the note.'),
      };
    } else if (name === 'police') {
      cfg = {
        title: 'Refer to the police', confirm: 'Refer case',
        html: `<div style="text-align:left;font-size:13px">Use this when the owner cannot be reached. The vehicle stays on hold and the owner is told.
          <label style="display:block;margin-top:10px">Reason<textarea id="cx_reason" rows="2" maxlength="250" style="${field}" placeholder="e.g. Owner unreachable after repeated attempts"></textarea></label>
          <label style="display:block;margin-top:10px">Police report / blotter reference (optional)<input id="cx_ref" maxlength="100" style="${field}"></label></div>`,
        read: () => ({ reason: $('cx_reason').value.trim(), reference: $('cx_ref').value.trim() }),
        check: (v) => (v.reason.length >= 5 ? '' : 'Write the reason (at least 5 characters).'),
      };
    } else if (name === 'close') {
      cfg = {
        title: 'Close case', confirm: 'Close case',
        html: `<div style="text-align:left;font-size:13px">Closing lifts the hold on ${esc(c.plateNumber)} if nothing else is open.
          <label style="display:block;margin-top:10px">Outcome<select id="cx_outcome" style="${field}">${options(OUTCOMES)}</select></label>
          <div style="font-size:11px;color:#64748b;margin-top:4px">“Dismissed” is for a case raised by mistake and needs a second administrator when there is one.</div>
          <label style="display:block;margin-top:10px">Notes (required)<textarea id="cx_notes" rows="3" maxlength="250" style="${field}" placeholder="e.g. Owner signed the clearance form"></textarea></label></div>`,
        read: () => ({ outcome: $('cx_outcome').value, notes: $('cx_notes').value.trim() }),
        check: (v) => (v.notes.length >= 5 ? '' : 'Write the notes (at least 5 characters).'),
      };
    } else return;

    const res = await Swal.fire({
      title: cfg.title, html: cfg.html, showCancelButton: true, confirmButtonText: cfg.confirm, confirmButtonColor: '#253475', focusConfirm: false,
      preConfirm: async () => {
        const body = cfg.read();
        const problem = cfg.check ? cfg.check(body) : '';
        if (problem) { Swal.showValidationMessage(problem); return false; }
        const outcome = await submit(c, name, body);
        if (outcome !== true) { Swal.showValidationMessage(outcome); return false; }
        return true;
      },
    });
    if (!res.isConfirmed) return;
  }

  /* ------------------------------------------------------------------------
     Issue a violation from this screen
     ------------------------------------------------------------------------ */
  async function issueViolation() {
    if (typeof Swal === 'undefined' || !window.SPViolations) return;
    const r = await Swal.fire({ title: 'Issue a violation', input: 'text', inputLabel: 'Plate number of the registered vehicle', inputPlaceholder: 'e.g. ABC 1234', showCancelButton: true, confirmButtonText: 'Continue', confirmButtonColor: '#253475' });
    if (!r.isConfirmed || !r.value) return;
    const wanted = String(r.value).toUpperCase().replace(/[^A-Z0-9]/g, '');
    const v = (SP.state.vehicles || []).find(x => String(x.plateNumber || '').toUpperCase().replace(/[^A-Z0-9]/g, '') === wanted && !x.isRetired);
    if (!v) { SP.showToast('No registered vehicle has that plate. Flag unregistered vehicles from the gate.', 'warning'); return; }
    SPViolations.openFlagModal(v, { onDone: () => load() });
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  window.SPCases = { open: openCase };

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('casesView', $('navCasesBtn'), load);
    $('casesRefreshBtn').addEventListener('click', load);
    $('casesNewBtn').addEventListener('click', issueViolation);
    document.querySelectorAll('#casesView [data-status]').forEach(b => b.addEventListener('click', () => { filter.status = b.dataset.status; filter.page = 1; load(); }));
    $('casesOutcome').addEventListener('change', (e) => { filter.outcome = e.target.value; filter.page = 1; load(); });
    $('casesFrom').addEventListener('change', (e) => { filter.from = e.target.value; filter.page = 1; load(); });
    $('casesTo').addEventListener('change', (e) => { filter.to = e.target.value; filter.page = 1; load(); });
    $('casesPrev').addEventListener('click', () => { filter.page = Math.max(1, filter.page - 1); load(); });
    $('casesNext').addEventListener('click', () => { filter.page += 1; load(); });
    $('casesClearBtn').addEventListener('click', () => {
      filter = { status: filter.status, type: '', q: '', outcome: '', from: '', to: '', page: 1, limit: 25 };
      $('casesOutcome').value = ''; $('casesFrom').value = ''; $('casesTo').value = ''; $('casesType').value = ''; $('casesSearch').value = '';
      load();
    });
    $('casesExportBtn').addEventListener('click', async () => {
      try {
        const blob = await ApiClient.exportCases({ ...filter, page: '', limit: '' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `securepark-cases-${new Date().toISOString().slice(0, 10)}.csv`;
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      } catch (err) { SP.showToast(err.message, 'error'); }
    });
    $('casesType').addEventListener('change', (e) => { filter.type = e.target.value; filter.page = 1; load(); });
    $('casesSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => { filter.q = e.target.value.trim(); filter.page = 1; load(); }, 300);
    });
    if (window.SPAuth) SPAuth.whenAuthenticated(load);
    document.addEventListener('sp:gate-passage', () => { if ($('casesView').classList.contains('active')) load(); });
    setInterval(() => { if (!document.hidden && window.SPAuth && SPAuth.isAuthenticated()) load(); }, 60000);
  });
})();
