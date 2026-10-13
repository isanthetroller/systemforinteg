/**
 * SecurePark - the guard's post inside the Gate Monitor (admin web)
 *
 * Everything the phone terminal offers a guard, in one tab, so a guard can work from any browser if the phone app is
 * not installed:
 *   - Duty:      go on duty at a gate, see the previous guard's handover note, end the shift with a note, and the
 *                "Start your shift" prompt at sign-in (never blocks scanning; a shift that cannot be recorded just
 *                shows the scans as "outside a shift" in the admin's Guard Shifts tab).
 *   - Numbers:   inside campus, entries and refusals today, vehicles held.
 *   - Scan IN / OUT: gate.js (camera, typed plate, drivers, items, Allow / Block / Report / Violation, photos).
 *   - Visitors:  today's / upcoming day passes, search, issue a new pass, open a pass's QR.
 *   - Cases:     what is holding vehicles; open one to log a contact attempt or add a note.
 *   - Activity:  every passage with search and filter.
 * The server enforces every rule; this file only shows and submits.
 */
(function () {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));
  const GATES = ['Gate 1 (Main Ingress)', 'Gate 2 (Main Egress)', 'Patrol / Other'];
  const TAB_KEY = 'sp_gate_tab';
  const isGuard = () => !!(window.SPAuth && SPAuth.user() && SPAuth.user().role !== 'admin');
  const gateLabel = (g) => String(g || '').replace(/Ingress/g, 'Entry').replace(/Egress/g, 'Exit');

  const duty = { mine: null, onDuty: [], handover: null, loaded: false, failed: false, noteHidden: false, busy: false };
  let tab = 'Scan';
  let askedAt = null;      // the account the "Start your shift" prompt was already shown to

  function clock(value) {
    const t = new Date(String(value || '').replace(' ', 'T'));
    return isNaN(t) ? '' : t.toLocaleTimeString('en-PH', { hour: 'numeric', minute: '2-digit' });
  }
  function since(value) {
    const t = new Date(String(value || '').replace(' ', 'T'));
    if (isNaN(t)) return '';
    const minutes = Math.max(0, Math.round((Date.now() - t.getTime()) / 60000));
    return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
  }
  const todayManila = () => new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);

  /* ------------------------------------------------------------------------
     Duty bar
     ------------------------------------------------------------------------ */
  async function loadDuty() {
    if (!isGuard()) { renderDuty(); return; }
    try {
      const res = await ApiClient.getShifts();
      duty.mine = res.mine || null;
      duty.onDuty = res.onDuty || [];
      if (res.handover && (!duty.handover || duty.handover.id !== res.handover.id)) duty.noteHidden = false;
      duty.handover = res.handover || null;
      duty.loaded = true;
      duty.failed = false;
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
      duty.failed = true;   // the bar stays out of the way: scanning never waits for it
    }
    renderDuty();
  }

  function gateOptions(selected) {
    return GATES.map(g => `<option value="${esc(g)}" ${g === selected ? 'selected' : ''}>${esc(gateLabel(g))}</option>`).join('');
  }
  function preferredGate() {
    const mine = SPAuth.user() && SPAuth.user().gateAssigned;
    return GATES.find(g => g === mine) || GATES.find(g => mine && g.startsWith(String(mine).slice(0, 6))) || GATES[0];
  }

  function renderDuty() {
    const bar = $('gateDutyBar');
    if (!bar) return;
    if (!isGuard() || duty.failed || !duty.loaded) { bar.innerHTML = ''; return; }
    const others = duty.onDuty.filter(s => !duty.mine || s.id !== duty.mine.id);
    const coverage = others.length
      ? `<span class="text-[11px] text-slate-500">Also on duty: ${others.map(s => `${esc(s.guard)} (${esc(gateLabel(s.gate))})`).join(', ')}</span>` : '';
    const note = duty.handover && !duty.noteHidden ? `
      <div class="sp-duty-note" role="note"><div><strong>Handover from ${esc(duty.handover.guard)}</strong> · ${esc(gateLabel(duty.handover.gate))} · ${esc(clock(duty.handover.endedAt))}</div>
        <p>${esc(duty.handover.handoverNotes)}</p><button type="button" data-duty="hide-note">Got it</button></div>` : '';
    bar.innerHTML = duty.mine ? `
      <div class="sp-duty sp-duty-on"><div class="min-w-0"><div class="sp-duty-title">On duty at ${esc(gateLabel(duty.mine.gate))}</div>
        <div class="text-[11px] text-slate-600">Since ${esc(clock(duty.mine.startedAt))} · ${esc(since(duty.mine.startedAt))}</div>${coverage}</div>
        <button type="button" data-duty="end" class="sp-gate-tool">End shift</button></div>${note}` : `
      <div class="sp-duty sp-duty-off"><div class="min-w-0"><div class="sp-duty-title">You are not on duty</div>
        <div class="text-[11px] text-slate-600">Go on duty so your time at the gate is recorded. You can still scan without it.</div>${coverage}</div>
        <div class="flex items-center gap-2 flex-wrap"><label class="sr-only" for="dutyGate">Gate</label>
          <select id="dutyGate" class="sp-duty-select">${gateOptions(preferredGate())}</select>
          <button type="button" data-duty="start" class="sp-gate-tool sp-gate-tool-primary">Go on duty</button></div></div>${note}`;
  }

  async function startDuty(gate) {
    if (duty.busy) return;
    duty.busy = true;
    try {
      const res = await ApiClient.startShift(gate);
      duty.mine = res.shift;
      duty.handover = res.handover || null;
      duty.noteHidden = false;
      duty.loaded = true;
      SP.showToast(`On duty at ${gateLabel(gate)}.`, 'success');
      await loadDuty();
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
      SP.showToast(`Could not go on duty: ${err.message}`, 'error');
    } finally { duty.busy = false; }
  }

  async function endDuty() {
    if (duty.busy || !window.Swal) return;
    const res = await Swal.fire({
      title: 'End your shift?',
      text: 'Leave a note for the next guard (optional).',
      input: 'textarea', inputAttributes: { maxlength: 2000, 'aria-label': 'Handover note' }, inputPlaceholder: 'Anything the next guard should know…',
      showCancelButton: true, confirmButtonText: 'End shift', cancelButtonText: 'Stay on duty', confirmButtonColor: '#253475'
    });
    if (!res.isConfirmed) return;
    duty.busy = true;
    try {
      await ApiClient.endShift((res.value || '').trim());
      duty.mine = null;
      SP.showToast('Shift ended. Thank you.', 'success');
      await loadDuty();
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
      SP.showToast(`Could not end the shift: ${err.message}`, 'error');
    } finally { duty.busy = false; }
  }

  /** Right after sign-in with no open shift: ask once, never trap the guard. */
  async function promptStart() {
    const user = SPAuth.user();
    if (!isGuard() || duty.mine || !duty.loaded || !window.Swal || askedAt === user.id) return;
    askedAt = user.id;
    const res = await Swal.fire({
      title: 'Start your shift',
      html: `<p style="margin-bottom:10px;font-size:14px">Choose the gate you are on duty at.</p><select id="dutyPromptGate" class="swal2-select" style="display:flex;margin:0 auto">${gateOptions(preferredGate())}</select>`,
      showCancelButton: true, confirmButtonText: 'Go on duty', cancelButtonText: 'Continue without recording', confirmButtonColor: '#253475',
      allowOutsideClick: false, preConfirm: () => document.getElementById('dutyPromptGate').value
    });
    if (res.isConfirmed) await startDuty(res.value);
  }

  /** Signing out while on duty: offer the handover note first (the same choice the phone gives). */
  async function onSignOut(event) {
    if (!isGuard() || !duty.mine || !window.Swal) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const res = await Swal.fire({
      title: 'End your shift before signing out?',
      text: 'Leave a note for the next guard (optional).',
      input: 'textarea', inputAttributes: { maxlength: 2000, 'aria-label': 'Handover note' }, inputPlaceholder: 'Anything the next guard should know…',
      showCancelButton: true, showDenyButton: true, confirmButtonText: 'End shift & sign out', denyButtonText: 'Sign out, keep shift open',
      cancelButtonText: 'Stay signed in', confirmButtonColor: '#253475'
    });
    if (res.isDismissed) return;
    if (res.isConfirmed) { try { await ApiClient.endShift((res.value || '').trim()); } catch (_) { /* the server closes a forgotten shift on its own */ } }
    await ApiClient.logout();
    window.location.reload();
  }

  /* ------------------------------------------------------------------------
     Today's numbers
     ------------------------------------------------------------------------ */
  async function refreshKpis() {
    const box = $('gateKpis');
    if (!box) return;
    let stats = SP.state.stats;
    try { stats = await ApiClient.getStats(); } catch (_) { /* keep the last numbers */ }
    if (!stats) { box.innerHTML = ''; return; }
    const card = (label, value, tone) => `<div class="sp-gate-kpi ${tone || ''}"><div>${esc(label)}</div><strong>${esc(value)}</strong></div>`;
    box.innerHTML = card('Inside campus', stats.inside ?? 0, 'ok') + card('Entries today', stats.todayEntries ?? 0)
      + card('Refused today', stats.todayDenied ?? 0, (stats.todayDenied || 0) ? 'bad' : '') + card('Vehicles on hold', stats.blocked ?? 0, (stats.blocked || 0) ? 'bad' : '');
  }

  /* ------------------------------------------------------------------------
     Sub-tabs
     ------------------------------------------------------------------------ */
  function selectTab(name) {
    tab = name;
    try { sessionStorage.setItem(TAB_KEY, name); } catch (_) {}
    document.querySelectorAll('#gateTabs [data-gate-tab]').forEach(b => b.setAttribute('aria-selected', String(b.dataset.gateTab === name)));
    ['Scan', 'Visitors', 'Cases', 'Activity'].forEach(n => $(`gatePane${n}`)?.classList.toggle('hidden', n !== name));
    if (name !== 'Scan' && window.SPGate) SPGate.stopCamera();
    if (name === 'Visitors') loadVisitors();
    if (name === 'Cases') loadCases();
    if (name === 'Activity') renderActivity();
  }

  /* ---- Visitors ---- */
  const vis = { range: 'today', q: '', list: [], error: '' };

  function passStatus(p) {
    if (p.status === 'Revoked' && p.isInside) return ['Revoked · still inside', 'bg-rose-50 text-rose-700 border-rose-200'];
    if (p.status === 'Revoked') return [p.exitTime ? 'Left' : 'Revoked', 'bg-slate-100 text-slate-600 border-slate-200'];
    if (p.status === 'Active' && p.isInside) return ['Inside', 'bg-emerald-50 text-emerald-700 border-emerald-200'];
    if (p.status === 'Active' && p.validDate > todayManila()) return ['Scheduled', 'bg-sky-50 text-sky-700 border-sky-200'];
    if (p.status === 'Active' && p.validDate < todayManila()) return ['Expired', 'bg-slate-100 text-slate-600 border-slate-200'];
    if (p.status === 'Active') return ['Expected', 'bg-amber-50 text-amber-800 border-amber-200'];
    return [p.status || '—', 'bg-slate-100 text-slate-600 border-slate-200'];
  }

  async function loadVisitors() {
    const pane = $('gatePaneVisitors');
    if (!pane.dataset.built) {
      pane.dataset.built = '1';
      pane.innerHTML = `
        <div class="sp-gate-card"><div class="sp-gate-pane-tools">
          <input id="gateVisSearch" type="search" placeholder="Search visitor, plate, pass code or host" class="sp-gate-search" aria-label="Search visitor passes">
          <div class="sp-gate-chips" role="group" aria-label="Which passes">
            <button type="button" data-vis="today" aria-pressed="true">Today</button><button type="button" data-vis="upcoming" aria-pressed="false">Scheduled</button>
          </div>
          <button type="button" id="gateVisNew" class="sp-gate-tool sp-gate-tool-primary">New day pass</button></div>
        <p class="sp-gate-pane-note">To check a visitor in or out, scan the pass or type the plate on the Scan tab: the items they declared are ticked there.</p>
        <div id="gateVisList"></div></div>`;
      $('gateVisSearch').addEventListener('input', (e) => { vis.q = e.target.value.trim(); clearTimeout(loadVisitors.t); loadVisitors.t = setTimeout(loadVisitors, 300); });
      pane.querySelectorAll('[data-vis]').forEach(b => b.addEventListener('click', () => {
        vis.range = b.dataset.vis;
        pane.querySelectorAll('[data-vis]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
        loadVisitors();
      }));
      $('gateVisNew').addEventListener('click', () => window.SPVisitors && SPVisitors.openCreate({}));
      pane.addEventListener('click', (e) => {
        const open = e.target.closest('[data-pass]');
        if (open && window.SPVisitors) SPVisitors.openCard(vis.list[Number(open.dataset.pass)]);
      });
    }
    try {
      vis.error = '';
      vis.list = vis.q ? await ApiClient.getVisitorPasses(vis.q)
        : vis.range === 'upcoming' ? await ApiClient.getVisitorPasses('', true) : await ApiClient.getVisitorPasses(todayManila());
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
      vis.error = err.message;
    }
    renderVisitors();
  }

  function renderVisitors() {
    const box = $('gateVisList');
    if (!box) return;
    if (vis.error) { box.innerHTML = `<p class="sp-gate-empty text-ncst-crimson">${esc(vis.error)}</p>`; return; }
    if (!vis.list.length) { box.innerHTML = `<p class="sp-gate-empty">${vis.q ? 'No pass matches your search.' : vis.range === 'upcoming' ? 'No scheduled passes.' : 'No visitor passes for today.'}</p>`; return; }
    box.innerHTML = `<ul class="sp-gate-rows">${vis.list.map((p, i) => {
      const [label, cls] = passStatus(p);
      return `<li><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="sp-plate">${esc(p.plateNumber)}</span><span class="px-1.5 py-0.5 rounded border text-[10px] font-bold ${cls}">${esc(label)}</span>
        <span class="text-[11px] font-mono text-slate-400">${esc(p.passCode || '')}</span></div>
        <div class="text-sm font-semibold text-slate-800 mt-1">${esc(p.visitorName)}</div>
        <div class="text-[11px] text-slate-500">Visiting ${esc(p.personToVisit || '—')} · ${esc(p.purposeOfVisit || '')} · valid ${esc(p.validDate)}${p.entryTime ? ' · in ' + esc(clock(p.entryTime)) : ''}${p.exitTime ? ' · out ' + esc(clock(p.exitTime)) : ''}</div></div>
        <button type="button" data-pass="${i}" class="sp-gate-tool">Open pass</button></li>`;
    }).join('')}</ul>`;
  }

  /* ---- Cases ---- */
  const cs = { status: 'active', q: '', data: null, error: '' };

  async function loadCases() {
    const pane = $('gatePaneCases');
    if (!pane.dataset.built) {
      pane.dataset.built = '1';
      pane.innerHTML = `
        <div class="sp-gate-card"><div class="sp-gate-pane-tools">
          <input id="gateCaseSearch" type="search" placeholder="Search case number, plate or owner" class="sp-gate-search" aria-label="Search cases">
          <div class="sp-gate-chips" role="group" aria-label="Case status">
            <button type="button" data-case="active" aria-pressed="true">Active</button><button type="button" data-case="open" aria-pressed="false">Open</button>
            <button type="button" data-case="awaiting" aria-pressed="false">Awaiting clearance</button><button type="button" data-case="closed" aria-pressed="false">Closed</button>
          </div></div>
        <p class="sp-gate-pane-note">Open a case to log that you tried to reach the owner, note that the owner is coming in, or add a note. An administrator closes it.</p>
        <div id="gateCaseList"></div></div>`;
      $('gateCaseSearch').addEventListener('input', (e) => { cs.q = e.target.value.trim(); clearTimeout(loadCases.t); loadCases.t = setTimeout(loadCases, 300); });
      pane.querySelectorAll('[data-case]').forEach(b => b.addEventListener('click', () => {
        cs.status = b.dataset.case;
        pane.querySelectorAll('[data-case]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
        loadCases();
      }));
      pane.addEventListener('click', (e) => {
        const open = e.target.closest('[data-case-key]');
        if (open && window.SPCases) SPCases.open(open.dataset.caseKey);
      });
    }
    try {
      cs.error = '';
      cs.data = await ApiClient.getCases({ status: cs.status, q: cs.q, limit: 100 });
    } catch (err) {
      if (window.ApiClient?.isFresh?.()) throw err;
      cs.error = err.message;
    }
    renderCases();
  }

  function renderCases() {
    const box = $('gateCaseList');
    if (!box) return;
    if (cs.error) { box.innerHTML = `<p class="sp-gate-empty text-ncst-crimson">${esc(cs.error)}</p>`; return; }
    const list = (cs.data && cs.data.cases) || [];
    if (!list.length) { box.innerHTML = `<p class="sp-gate-empty">${cs.q ? 'No case matches your search.' : 'No cases here.'}</p>`; return; }
    box.innerHTML = `<ul class="sp-gate-rows">${list.map(c => `
      <li><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="sp-plate">${esc(c.plateNumber)}</span>
        <span class="px-1.5 py-0.5 rounded border text-[10px] font-bold bg-slate-100 text-slate-700 border-slate-200">${esc(c.status)}</span>
        <span class="text-[11px] font-mono text-slate-400">${esc(c.reference || c.key)}</span></div>
        <div class="text-sm font-semibold text-slate-800 mt-1">${esc(c.title)}</div>
        <div class="text-[11px] text-slate-500">${esc(c.ownerName || 'Owner unknown')} · opened ${esc(String(c.openedAt || '').slice(0, 16))}${c.contactAttempts ? ` · ${c.contactAttempts} contact attempt${c.contactAttempts === 1 ? '' : 's'}` : ''}</div></div>
        <button type="button" data-case-key="${esc(c.key)}" class="sp-gate-tool">Open case</button></li>`).join('')}</ul>`;
  }

  async function refreshCasesCount() {
    try {
      const res = await ApiClient.getCases({ status: 'active', limit: 1 });
      const n = (res.summary && (res.summary.open + res.summary.awaiting)) || 0;
      const badge = $('gateCasesCount');
      if (badge) { badge.textContent = n; badge.classList.toggle('hidden', !n); }
    } catch (_) { /* the count is a convenience */ }
  }

  /* ---- Activity ---- */
  const act = { filter: 'All', q: '' };

  function renderActivity() {
    const pane = $('gatePaneActivity');
    if (!pane.dataset.built) {
      pane.dataset.built = '1';
      pane.innerHTML = `
        <div class="sp-gate-card"><div class="sp-gate-pane-tools">
          <input id="gateActSearch" type="search" placeholder="Search plate, owner or driver" class="sp-gate-search" aria-label="Search gate activity">
          <div class="sp-gate-chips" role="group" aria-label="Which passages">
            <button type="button" data-act="All" aria-pressed="true">All</button><button type="button" data-act="Entry" aria-pressed="false">Entries</button>
            <button type="button" data-act="Exit" aria-pressed="false">Exits</button><button type="button" data-act="Denied" aria-pressed="false">Refused</button>
          </div></div><div id="gateActList"></div></div>`;
      $('gateActSearch').addEventListener('input', (e) => { act.q = e.target.value.trim().toLowerCase(); renderActivity(); });
      pane.querySelectorAll('[data-act]').forEach(b => b.addEventListener('click', () => {
        act.filter = b.dataset.act;
        pane.querySelectorAll('[data-act]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
        renderActivity();
      }));
    }
    const box = $('gateActList');
    const logs = (SP.state.auditLogs || []).filter(l => {
      const a = l.action || '';
      if (act.filter === 'Entry' && a !== 'Entry Recorded') return false;
      if (act.filter === 'Exit' && a !== 'Exit Approved') return false;
      if (act.filter === 'Denied' && !/Denied/.test(a)) return false;
      return !act.q || [l.plateNumber, l.ownerName, l.driverName].some(x => String(x || '').toLowerCase().includes(act.q));
    }).slice(0, 100);
    if (!logs.length) { box.innerHTML = '<p class="sp-gate-empty">No gate activity matches.</p>'; return; }
    box.innerHTML = `<ul class="sp-gate-rows">${logs.map(l => {
      const denied = /Denied/.test(l.action || ''), exit = /Exit/.test(l.action || '');
      const chip = denied ? 'bg-rose-50 text-rose-700 border-rose-200' : exit ? 'bg-sky-50 text-sky-800 border-sky-200' : 'bg-emerald-50 text-emerald-700 border-emerald-200';
      return `<li><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="sp-plate">${esc(l.plateNumber)}</span>
        <span class="px-1.5 py-0.5 rounded border text-[10px] font-bold ${chip}">${esc(denied ? (exit ? 'Exit refused' : 'Entry refused') : (exit ? 'Exit' : 'Entry'))}</span></div>
        <div class="text-[11px] text-slate-500 mt-1">${esc(l.driverName || 'Driver not recorded')} · ${esc(gateLabel(l.gatePoint || l.gate || ''))}${l.guardName ? ' · ' + esc(l.guardName) : ''}</div></div>
        <time class="text-[11px] text-slate-500 whitespace-nowrap">${esc(l.timestamp || '')}</time></li>`;
    }).join('')}</ul>`;
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  document.addEventListener('sp:app-ready', () => {
    // gate.js owns the view's show hook (one per view), so watch for the Gate Monitor coming on screen instead
    const gateView = $('gateView');
    let wasActive = gateView.classList.contains('active');
    new MutationObserver(() => {
      const now = gateView.classList.contains('active');
      if (now && !wasActive) {
        refreshKpis();
        refreshCasesCount();
        if (isGuard()) loadDuty();
        if (tab !== 'Scan') selectTab(tab);
      }
      wasActive = now;
    }).observe(gateView, { attributes: true, attributeFilter: ['class'] });

    const bar = $('gateDutyBar');
    if (bar) bar.addEventListener('click', (e) => {
      const act = e.target.closest('[data-duty]');
      if (!act) return;
      if (act.dataset.duty === 'start') startDuty($('dutyGate').value);
      else if (act.dataset.duty === 'end') endDuty();
      else if (act.dataset.duty === 'hide-note') { duty.noteHidden = true; renderDuty(); }
    });
    ['logoutBtn', 'topHeaderLogoutBtn'].forEach(id => { const b = $(id); if (b) b.addEventListener('click', onSignOut, true); });

    document.querySelectorAll('#gateTabs [data-gate-tab]').forEach(b => b.addEventListener('click', () => selectTab(b.dataset.gateTab)));
    try { const saved = sessionStorage.getItem(TAB_KEY); if (saved && $(`gatePane${saved}`)) tab = saved; } catch (_) {}

    const sound = $('gateSoundBtn');
    const showSound = () => { if (sound && window.SPFeedback) { sound.textContent = `Scan sound: ${SPFeedback.isOn() ? 'on' : 'off'}`; sound.setAttribute('aria-pressed', String(SPFeedback.isOn())); } };
    if (sound) sound.addEventListener('click', () => { SPFeedback.setOn(!SPFeedback.isOn()); showSound(); if (SPFeedback.isOn()) SPFeedback.play('ok'); });
    showSound();

    if (window.SPAuth) SPAuth.whenAuthenticated(async () => {
      await loadDuty();
      refreshKpis();
      refreshCasesCount();
      if (isGuard()) setTimeout(promptStart, 600);
      if (tab !== 'Scan') selectTab(tab);
    });

    document.addEventListener('sp:gate-passage', () => { refreshKpis(); refreshCasesCount(); if (tab === 'Activity') renderActivity(); });
    document.addEventListener('sp:data-loaded', () => { if (tab === 'Activity') renderActivity(); });
    document.addEventListener('visibilitychange', () => { if (!document.hidden && isGuard() && SPAuth.isAuthenticated()) loadDuty(); });
    setInterval(() => {
      if (document.hidden || !window.SPAuth || !SPAuth.isAuthenticated() || !$('gateView').classList.contains('active')) return;
      refreshKpis();
      if (isGuard()) loadDuty();
      if (tab === 'Visitors') loadVisitors();
      if (tab === 'Cases') loadCases();
    }, 30000);
  });
  window.SPLive?.subscribe((changed) => {
    if (!$('gateView') || !$('gateView').classList.contains('active')) return;
    if (changed.some(k => ['movements', 'vehicles'].includes(k))) refreshKpis();
    if (tab === 'Visitors' && changed.includes('visitors')) loadVisitors();
    if (changed.includes('cases')) { refreshCasesCount(); if (tab === 'Cases') loadCases(); }
  });
})();
