/**
 * SecurePark - Admin Center (admin only)
 *
 * Activity log (who did what, to which record, and why), second-administrator approvals,
 * guard duty (who is on which gate + each guard's activity), and the system settings.
 * All rules are enforced by the server; this screen only shows and submits.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  const TABS = ['log', 'approvals', 'duty', 'settings'];
  let tab = 'log';
  let logPage = 1;
  let logFilter = { q: '', action: '', from: '', to: '' };
  let dutyRange = { from: '', to: '' };
  let ticket = 0;

  function fmt(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }));
  }

  const th = (t, right) => `<th scope="col" class="${right ? 'text-right' : 'text-left'} font-bold px-4 py-2.5">${t}</th>`;
  const table = (head, body) => `<div class="bg-white border border-slate-200 rounded-lg shadow-2xs overflow-hidden"><div class="overflow-x-auto"><table class="w-full text-xs">
      <thead class="bg-slate-100/90 text-slate-700 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider"><tr>${head}</tr></thead>
      <tbody class="divide-y divide-slate-100">${body}</tbody></table></div></div>`;
  const empty = (cols, text) => `<tr><td colspan="${cols}" class="px-4 py-8 text-center text-slate-400">${esc(text)}</td></tr>`;
  const input = 'h-9 px-3 rounded-lg border border-slate-200 bg-slate-50/50 text-xs text-slate-800 focus:bg-white focus:outline-none focus:ring-2 focus:ring-ncst-navy/20';
  const btn = 'px-3 py-1.5 rounded-md text-xs font-semibold shadow-xs cursor-pointer';
  const navy = btn + ' bg-ncst-navy hover:bg-ncst-navyDark text-white';
  const plain = btn + ' border border-slate-200 bg-white hover:bg-slate-50 text-slate-700';

  function paintTabs() {
    TABS.forEach(t => {
      const b = $('centerTab' + t.charAt(0).toUpperCase() + t.slice(1).replace('log', 'Log'));
      if (!b) return;
      const on = t === tab;
      b.setAttribute('aria-selected', String(on));
      b.className = 'px-3.5 py-2 text-xs font-bold border-b-2 whitespace-nowrap cursor-pointer ' + (on ? 'border-ncst-navy text-ncst-navy' : 'border-transparent text-slate-500 hover:text-slate-800');
    });
  }

  async function load() {
    paintTabs();
    const mine = ++ticket;
    const body = $('centerBody');
    body.innerHTML = '<div class="px-4 py-8 text-center text-slate-400 text-xs">Loading…</div>';
    try {
      const html = await ({ log: renderLog, approvals: renderApprovals, duty: renderDuty, settings: renderSettings }[tab])();
      if (mine !== ticket) return;
      body.innerHTML = html;
      wire();
      $('settingsForm')?.addEventListener('input', () => { $('settingsForm').dataset.dirty = 'true'; });
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
      if (mine === ticket) body.innerHTML = `<div class="px-4 py-6 text-center text-ncst-crimson text-xs">${esc(err.message)}</div>`;
    }
  }

  /* ---------------------------------------------------------------- Activity log */
  async function renderLog() {
    const data = await ApiClient.getAuditLog({ ...logFilter, page: logPage, limit: 25 });
    const pages = Math.max(1, Math.ceil(data.total / data.limit));
    const rows = data.rows.map(r => `<tr class="hover:bg-slate-50/60 align-top">
        <td class="px-4 py-2.5 whitespace-nowrap">${fmt(r.createdAt)}</td>
        <td class="px-4 py-2.5"><div class="font-semibold text-slate-800">${esc(r.actor)}</div><div class="text-[11px] text-slate-500">${esc(r.actorRole || '')}</div></td>
        <td class="px-4 py-2.5"><span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-slate-100 text-slate-700 border border-slate-200">${esc(r.action)}</span></td>
        <td class="px-4 py-2.5 font-mono font-bold text-slate-900 whitespace-nowrap">${esc(r.plateNumber || '')}</td>
        <td class="px-4 py-2.5 text-slate-700">${esc(r.detail || '')}${r.reason ? `<div class="mt-0.5 text-[11px] text-slate-600"><span class="font-semibold">Reason:</span> ${esc(r.reason)}</div>` : ''}</td></tr>`).join('');
    const options = ['<option value="">All actions</option>'].concat(data.actions.map(a => `<option value="${esc(a)}"${a === logFilter.action ? ' selected' : ''}>${esc(a)}</option>`)).join('');
    return `<div class="flex flex-wrap items-end gap-2">
        <input id="logQ" type="search" value="${esc(logFilter.q)}" placeholder="Search plate, person, detail or reason" aria-label="Search the activity log" class="${input} w-full sm:w-72">
        <select id="logAction" aria-label="Filter by action" class="${input}">${options}</select>
        <label class="text-[11px] text-slate-500">From <input id="logFrom" type="date" value="${esc(logFilter.from)}" class="${input}"></label>
        <label class="text-[11px] text-slate-500">To <input id="logTo" type="date" value="${esc(logFilter.to)}" class="${input}"></label>
        <button type="button" id="logApply" class="${navy}">Apply</button>
      </div>
      ${table(th('When') + th('Who') + th('Action') + th('Record') + th('What and why'), rows || empty(5, 'No activity matches.'))}
      <div class="flex items-center justify-between text-[11px] text-slate-500">
        <span>${data.total} entr${data.total === 1 ? 'y' : 'ies'} · page ${data.page} of ${pages}</span>
        <span class="flex gap-2"><button type="button" id="logPrev" class="${plain}"${data.page <= 1 ? ' disabled' : ''}>Previous</button><button type="button" id="logNext" class="${plain}"${data.page >= pages ? ' disabled' : ''}>Next</button></span>
      </div>`;
  }

  /* ---------------------------------------------------------------- Approvals */
  function setPendingBadge(n) {
    [$('centerApprovalsCount'), $('centerSidebarCount')].forEach(b => {
      if (!b) return;
      b.textContent = n;
      b.classList.toggle('hidden', !n);
    });
  }

  async function renderApprovals() {
    const data = await ApiClient.getApprovals();
    setPendingBadge(data.pending);
    const meId = data.me && data.me.id;
    const pending = data.requests.filter(r => r.status === 'Pending');
    const done = data.requests.filter(r => r.status !== 'Pending');
    const note = data.secondAdminAvailable
      ? 'Granting VIP and dismissing a violation need a second administrator. The person who asked cannot approve their own request.'
      : 'There is only one active administrator, so these actions are applied directly (and logged). Add a second administrator in Staff Accounts to turn approvals on.';
    const pendingRows = pending.map(r => `<tr class="hover:bg-slate-50/60 align-top">
        <td class="px-4 py-2.5 whitespace-nowrap">${fmt(r.createdAt)}</td>
        <td class="px-4 py-2.5 font-semibold text-slate-800">${esc(r.typeLabel)}</td>
        <td class="px-4 py-2.5 font-mono font-bold text-slate-900 whitespace-nowrap">${esc(r.plateNumber || '')}</td>
        <td class="px-4 py-2.5"><div>${esc(r.requestedBy)}</div><div class="text-[11px] text-slate-600">${esc(r.reason || '')}</div></td>
        <td class="px-4 py-2.5 text-right whitespace-nowrap">${r.requestedByUserId === meId
          ? '<span class="text-[11px] text-slate-500">Waiting for another administrator</span>'
          : `<button type="button" data-approve="${r.id}" class="${navy}">Approve</button> <button type="button" data-reject="${r.id}" class="${plain}">Reject</button>`}</td></tr>`).join('');
    const doneRows = done.slice(0, 50).map(r => `<tr class="align-top">
        <td class="px-4 py-2.5 whitespace-nowrap">${fmt(r.decidedAt || r.createdAt)}</td>
        <td class="px-4 py-2.5">${esc(r.typeLabel)}</td>
        <td class="px-4 py-2.5 font-mono font-bold text-slate-900 whitespace-nowrap">${esc(r.plateNumber || '')}</td>
        <td class="px-4 py-2.5">${esc(r.requestedBy)} <span class="text-slate-400">→</span> ${esc(r.decidedBy || '—')}${r.decisionNote ? `<div class="text-[11px] text-slate-600">${esc(r.decisionNote)}</div>` : ''}</td>
        <td class="px-4 py-2.5 text-right"><span class="px-2 py-0.5 rounded text-[11px] font-semibold ${r.status === 'Approved' ? 'bg-emerald-50 text-emerald-700 border border-emerald-200/80' : 'bg-rose-50 text-rose-700 border border-rose-200'}">${esc(r.status)}</span></td></tr>`).join('');
    return `<div class="text-[11px] px-3 py-2 rounded-md bg-slate-100 text-slate-700 border border-slate-200">${esc(note)}</div>
      <h2 class="text-sm font-bold text-slate-800">Waiting for a decision</h2>
      ${table(th('Asked') + th('Request') + th('Plate') + th('By and why') + th('', true), pendingRows || empty(5, 'Nothing is waiting.'))}
      <h2 class="text-sm font-bold text-slate-800 pt-2">Decided</h2>
      ${table(th('Decided') + th('Request') + th('Plate') + th('Asked by → decided by') + th('', true), doneRows || empty(5, 'No decisions yet.'))}`;
  }

  async function decide(id, approve) {
    let note = '';
    if (!approve) {
      note = await SPAlert.prompt({ title: 'Reject this request', text: 'Tell the requester why.', placeholder: 'e.g. Not enough proof', confirmText: 'Reject', icon: 'warning', maxLength: 250 });
      if (!note) return;
    } else if (!(await SPAlert.confirm({ title: 'Approve this request?', text: 'The action is carried out right away and logged under both names.', confirmText: 'Approve', icon: 'question' }))) return;
    try {
      const res = await ApiClient.decideApproval(id, approve ? 'approve' : 'reject', note);
      SP.showToast(res.message || 'Done.', 'success');
      if (SP.reload) SP.reload(true, true);
      load();
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err; SP.showToast(err.message, 'error'); }
  }

  /* ---------------------------------------------------------------- Guard duty */
  async function renderDuty() {
    const [now, report] = await Promise.all([ApiClient.getShifts(), ApiClient.getShiftReport(dutyRange.from, dutyRange.to)]);
    dutyRange = { from: report.from, to: report.to };
    const onRows = now.onDuty.map(s => `<tr><td class="px-4 py-2.5 font-semibold text-slate-800">${esc(s.guard)}</td><td class="px-4 py-2.5">${esc(s.gate || '—')}</td><td class="px-4 py-2.5 whitespace-nowrap">${fmt(s.startedAt)}</td></tr>`).join('');
    const pct = (n) => n ? `${n}%` : '—';
    const repRows = report.guards.map(g => `<tr class="hover:bg-slate-50/60">
        <td class="px-4 py-2.5 font-semibold text-slate-800">${esc(g.guard)}</td>
        <td class="px-4 py-2.5">${g.shifts} · ${g.hoursOnDuty} h</td>
        <td class="px-4 py-2.5">${g.entries}</td><td class="px-4 py-2.5">${g.exits}</td>
        <td class="px-4 py-2.5 ${g.denialRate >= 25 ? 'text-ncst-crimson font-bold' : ''}">${g.denials} <span class="text-slate-400">(${pct(g.denialRate)})</span></td>
        <td class="px-4 py-2.5 ${g.manualRate >= 25 ? 'text-amber-700 font-bold' : ''}">${g.manualLookups} <span class="text-slate-400">(${pct(g.manualRate)})</span></td>
        <td class="px-4 py-2.5">${g.violationsIssued}</td><td class="px-4 py-2.5">${g.photos}</td></tr>`).join('');
    return `<h2 class="text-sm font-bold text-slate-800">On duty now</h2>
      ${table(th('Guard') + th('Gate') + th('Since'), onRows || empty(3, 'Nobody has gone on duty.'))}
      <div class="flex flex-wrap items-end gap-2 pt-2">
        <h2 class="text-sm font-bold text-slate-800 mr-2">Guard activity</h2>
        <label class="text-[11px] text-slate-500">From <input id="dutyFrom" type="date" value="${esc(dutyRange.from)}" class="${input}"></label>
        <label class="text-[11px] text-slate-500">To <input id="dutyTo" type="date" value="${esc(dutyRange.to)}" class="${input}"></label>
        <button type="button" id="dutyApply" class="${navy}">Show</button>
      </div>
      ${table(th('Guard') + th('Shifts') + th('Entries') + th('Exits') + th('Denied') + th('Manual lookups') + th('Violations') + th('Photos'), repRows || empty(8, 'No guard accounts.'))}
      <p class="text-[11px] text-slate-500">A high share of denied passages or manual plate lookups is worth a conversation: it can mean a trouble spot at the gate, or passes being waved through without a scan.</p>`;
  }

  /* ---------------------------------------------------------------- Settings */
  const HELP = {
    parking_capacity: 'The gate and dashboard warn from 90% full. 0 means no limit.',
    renewal_window_days: 'Owners and the cashier can renew a pass this many days before it expires.',
    expiry_warning_days: 'Owners get an e-mail and a portal notice this many days before the pass expires.',
    hold_reminder_days: 'The owner is reminded this often while a violation stays unresolved.',
    exit_release_minutes: 'How long a one-time exit release stays usable.',
    notify_entry_exit: 'Each time a registered vehicle enters or leaves, its owner gets an "is this you?" e-mail with a one-tap way to report it. Owners without an e-mail address are skipped.',
    evidence_retention_days: 'Guard photos are deleted after this many days (the record stays).',
  };

  async function renderSettings() {
    const rows = await ApiClient.getSettings();
    return `<form id="settingsForm" class="bg-white border border-slate-200 rounded-lg shadow-2xs divide-y divide-slate-100">${rows.map(s => `
        <div class="flex flex-col sm:flex-row sm:items-center gap-2 px-4 py-3">
          <div class="flex-1 min-w-0"><label for="set_${esc(s.key)}" class="text-xs font-bold text-slate-800">${esc(s.label)}</label>
            <div class="text-[11px] text-slate-500">${esc(HELP[s.key] || '')} Default ${s.default}.</div></div>
          <input id="set_${esc(s.key)}" name="${esc(s.key)}" type="number" min="${s.min}" max="${s.max}" step="1" value="${s.value}" class="${input} w-28 text-right">
        </div>`).join('')}
        <div class="px-4 py-3 flex justify-end"><button type="submit" class="${navy}">Save settings</button></div></form>
      <div class="bg-white border border-slate-200 rounded-lg shadow-2xs px-4 py-3 flex flex-col sm:flex-row sm:items-center gap-2">
        <div class="flex-1 min-w-0"><div class="text-xs font-bold text-slate-800">E-mail to owners</div>
          <div class="text-[11px] text-slate-500">Violation and blocked notices, passage alerts and renewal reminders go out by e-mail. Send yourself a test to check that the server can reach the mail account.</div></div>
        <input id="mailTestTo" type="email" placeholder="you@example.com" aria-label="Send the test e-mail to" class="${input} w-full sm:w-60">
        <button type="button" id="mailTestBtn" class="${plain}">Send test e-mail</button>
      </div>`;
  }

  async function saveSettings(form) {
    const values = {};
    new FormData(form).forEach((v, k) => { values[k] = v; });
    try {
      await ApiClient.saveSettings(values);
      SP.showToast('Settings saved.', 'success');
      if (window.SPOps) SPOps.refreshOccupancy();
      load();
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err; SP.showToast(err.message, 'error'); }
  }

  /* ---------------------------------------------------------------- Wiring */
  function wire() {
    const apply = () => {
      logFilter = { q: $('logQ').value.trim(), action: $('logAction').value, from: $('logFrom').value, to: $('logTo').value };
      logPage = 1;
      load();
    };
    if ($('logApply')) {
      $('logApply').addEventListener('click', apply);
      $('logQ').addEventListener('keydown', (e) => { if (e.key === 'Enter') apply(); });
      $('logAction').addEventListener('change', apply);
      $('logPrev').addEventListener('click', () => { logPage = Math.max(1, logPage - 1); load(); });
      $('logNext').addEventListener('click', () => { logPage += 1; load(); });
    }
    document.querySelectorAll('[data-approve]').forEach(b => b.addEventListener('click', () => decide(Number(b.dataset.approve), true)));
    document.querySelectorAll('[data-reject]').forEach(b => b.addEventListener('click', () => decide(Number(b.dataset.reject), false)));
    if ($('dutyApply')) $('dutyApply').addEventListener('click', () => { dutyRange = { from: $('dutyFrom').value, to: $('dutyTo').value }; load(); });
    if ($('settingsForm')) $('settingsForm').addEventListener('submit', (e) => { e.preventDefault(); saveSettings(e.target); });
    if ($('mailTestBtn')) $('mailTestBtn').addEventListener('click', async () => {
      const to = $('mailTestTo').value.trim();
      if (!to) { SP.showToast('Type the address to send the test to.', 'warning'); return; }
      const btn = $('mailTestBtn');
      btn.disabled = true;
      btn.textContent = 'Sending…';
      try {
        const res = await ApiClient.sendTestMail(to);
        SP.showToast(res.message, 'success');
      } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
        if (window.Swal) Swal.fire({ icon: 'error', title: 'The test e-mail did not go out', text: err.message, confirmButtonColor: '#253475' });
        else SP.showToast(err.message, 'error');
      } finally {
        btn.disabled = false;
        btn.textContent = 'Send test e-mail';
      }
    });
  }

  async function refreshPending() {
    if (!window.SPAuth || !SPAuth.hasRole('admin') || !SPAuth.isAuthenticated()) return;
    try {
      const data = await ApiClient.getApprovals('Pending');
      const meId = data.me && data.me.id;
      setPendingBadge(data.requests.filter(r => r.requestedByUserId !== meId).length);
    } catch (_) { /* the badge is a convenience */ }
  }

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('centerView', $('navCenterBtn'), load);
    $('centerRefreshBtn').addEventListener('click', load);
    TABS.forEach(t => {
      const b = document.querySelector(`#centerView [data-tab="${t}"]`);
      if (b) b.addEventListener('click', () => { tab = t; load(); });
    });
    if (window.SPAuth) SPAuth.whenAuthenticated(refreshPending);
    setInterval(() => { if (!document.hidden) refreshPending(); }, 60000);
  });
  window.SPLive?.subscribe(async changed => {
    if (!window.SPAuth?.hasRole('admin')) return;
    if (changed.includes('approvals')) await refreshPending();
    if (!$('centerView').classList.contains('active')) return;
    const domain = {log:'activity', approvals:'approvals', duty:'shifts', settings:'settings'}[tab];
    if (!changed.includes(domain) && !(tab === 'duty' && changed.includes('movements'))) return;
    if (tab === 'settings' && $('settingsForm')?.dataset.dirty === 'true') { SP.showToast('Settings changed elsewhere. Reload before saving.', 'warning'); return; }
    await load();
  });
})();
