/**
 * SecurePark - Guard Shifts (admin only)
 *
 * Shows when each guard went on and off duty (the "Go on duty" / "End shift" button of the mobile app), how long they
 * worked, which gate they covered and what they did during the shift. Everything is calculated on the server
 * (api/shifts.php); this screen draws it:
 *   - gate coverage right now
 *   - a timeline of every shift, one row per guard
 *   - a per-guard summary (hours, actions, activity outside a shift)
 *   - the list of shifts, each opening to a time-ordered log of what the guard did
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  const MANILA = '+08:00';
  const DAY = 86400000;
  const GATE_COLOR = { 'Gate 1 (Main Ingress)': '#253475', 'Gate 2 (Main Egress)': '#0f766e', 'Patrol / Other': '#b45309' };
  const OTHER_COLOR = '#64748b';
  const gateColor = (g) => GATE_COLOR[g] || OTHER_COLOR;

  const PRESETS = [{ id: 'today', label: 'Today' }, { id: 'yesterday', label: 'Yesterday' }, { id: '7', label: 'Last 7 days' }, { id: '30', label: 'Last 30 days' }];
  const TYPES = {
    entry: { label: 'Entries', one: 'entry', many: 'entries', tone: 'bg-emerald-50 text-emerald-700 border-emerald-200', dot: '#059669' },
    exit: { label: 'Exits', one: 'exit', many: 'exits', tone: 'bg-sky-50 text-sky-700 border-sky-200', dot: '#0284c7' },
    denied: { label: 'Denied', one: 'denied', many: 'denied', tone: 'bg-rose-50 text-rose-700 border-rose-200', dot: '#e11d48' },
    violation: { label: 'Violations', one: 'violation', many: 'violations', tone: 'bg-orange-50 text-orange-700 border-orange-200', dot: '#ea580c' },
    incident: { label: 'Held', one: 'held', many: 'held', tone: 'bg-red-50 text-red-700 border-red-200', dot: '#dc2626' },
    photo: { label: 'Photos', one: 'photo', many: 'photos', tone: 'bg-violet-50 text-violet-700 border-violet-200', dot: '#7c3aed' },
    visitor: { label: 'Visitor passes', one: 'visitor pass', many: 'visitor passes', tone: 'bg-indigo-50 text-indigo-700 border-indigo-200', dot: '#4f46e5' },
  };
  const END_KIND = {
    open: { label: 'On duty', tone: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
    manual: { label: 'Ended by guard', tone: 'bg-slate-50 text-slate-700 border-slate-200' },
    auto: { label: 'Closed automatically', tone: 'bg-amber-50 text-amber-800 border-amber-300' },
    moved: { label: 'Moved to another gate', tone: 'bg-sky-50 text-sky-700 border-sky-200' },
  };

  let range = { preset: 'today', from: '', to: '' };
  let data = null;
  let filter = { guard: '', gate: '' };
  let ticket = 0;
  let timer = null;

  /* ---------------------------------------------------------------- helpers */
  const ms = (value) => Date.parse(String(value).replace(' ', 'T') + MANILA);
  const dayKey = (offset = 0) => new Date(Date.now() + offset * DAY).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });

  function fmt(value) {
    if (!value) return '—';
    const d = new Date(ms(value));
    return isNaN(d) ? esc(value) : esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', hour: 'numeric', minute: '2-digit' }));
  }
  function fmtTime(value) {
    const d = new Date(ms(value));
    return isNaN(d) ? '' : d.toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit' });
  }
  function fmtClock(value) {
    const d = new Date(ms(value));
    return isNaN(d) ? '' : d.toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit', second: '2-digit' });
  }
  function dur(minutes) {
    const m = Math.max(0, Math.round(minutes));
    const h = Math.floor(m / 60);
    return h ? `${h}h ${String(m % 60).padStart(2, '0')}m` : `${m}m`;
  }
  function presetRange(id) {
    if (id === 'today') return { from: dayKey(0), to: dayKey(0) };
    if (id === 'yesterday') return { from: dayKey(-1), to: dayKey(-1) };
    return { from: dayKey(id === '7' ? -6 : -29), to: dayKey(0) };
  }

  const btn = 'px-3 py-1.5 rounded-md text-xs font-semibold shadow-xs cursor-pointer';
  const navy = btn + ' bg-ncst-navy hover:bg-ncst-navyDark text-white';
  const plain = btn + ' border border-slate-200 bg-white hover:bg-slate-50 text-slate-700';
  const inputCls = 'h-9 px-3 rounded-lg border border-slate-200 bg-slate-50/50 text-xs text-slate-800 focus:bg-white focus:outline-none focus:ring-2 focus:ring-ncst-navy/20';
  const th = (t, cls = '') => `<th scope="col" class="text-left font-bold px-4 py-2.5 ${cls}">${t}</th>`;

  /* ---------------------------------------------------------------- load */
  async function load() {
    const mine = ++ticket;
    const body = $('shiftsBody');
    if (!data) body.innerHTML = '<div class="px-4 py-10 text-center text-slate-400 text-xs">Loading…</div>';
    try {
      if (range.preset !== 'custom') Object.assign(range, presetRange(range.preset));
      const res = await ApiClient.getShiftTimeline(range.from, range.to);
      if (mine !== ticket) return;
      data = res;
      range.from = res.from; range.to = res.to;
      render();
      const n = res.coverage.reduce((a, g) => a + g.guards.length, 0);
      const badge = $('shiftsSidebarCount');
      if (badge) { badge.textContent = n; badge.dataset.empty = String(!n); badge.classList.toggle('hidden', !n); }
    } catch (err) {
      if (mine !== ticket) return;
      body.innerHTML = `<div class="px-4 py-10 text-center text-rose-600 text-xs">${esc(err.message || 'The shifts could not be loaded.')}</div>`;
    }
  }

  /* ---------------------------------------------------------------- pieces */
  function kpi(label, value, sub, tone) {
    return `<div class="bg-white border ${tone || 'border-slate-200'} rounded-lg p-4 shadow-2xs">
      <div class="text-[10px] font-bold uppercase tracking-wider text-slate-500">${label}</div>
      <div class="text-2xl font-extrabold text-slate-900 mt-1">${value}</div>
      <div class="text-[11px] text-slate-500 mt-0.5">${sub}</div></div>`;
  }

  function renderKpis() {
    const s = data.summary;
    const attention = s.autoClosed + s.longShifts + (s.offShiftActions > 0 ? 1 : 0);
    return `<div class="grid grid-cols-2 lg:grid-cols-5 gap-3">
      ${kpi('On duty now', s.onDuty, s.onDuty === 1 ? 'guard at a gate' : 'guards at gates', s.onDuty ? 'border-emerald-200' : 'border-slate-200')}
      ${kpi('Hours on duty', s.hours, `in this period`)}
      ${kpi('Shifts', s.shifts, s.shifts ? `avg ${dur(s.hours * 60 / s.shifts)}` : 'none in this period')}
      ${kpi('Actions during shifts', s.actions, 'scans, violations, holds, photos')}
      ${kpi('Needs a look', attention, [s.autoClosed ? `${s.autoClosed} auto-closed` : '', s.longShifts ? `${s.longShifts} over ${data.longShiftHours} h` : '', s.offShiftActions ? `${s.offShiftActions} off-shift` : ''].filter(Boolean).join(' · ') || 'all clear', attention ? 'border-amber-300' : 'border-slate-200')}
    </div>`;
  }

  function renderCoverage() {
    const cards = data.coverage.map(c => {
      const covered = c.guards.length > 0;
      return `<div class="rounded-lg border ${covered ? 'border-emerald-200 bg-white' : 'border-dashed border-rose-300 bg-rose-50/40'} p-3.5 shadow-2xs">
        <div class="flex items-center gap-2"><span class="w-2.5 h-2.5 rounded-full flex-shrink-0" style="background:${gateColor(c.gate)}"></span>
          <span class="text-xs font-bold text-slate-800 truncate">${esc(c.gate)}</span>
          <span class="ml-auto px-2 py-0.5 rounded text-[10px] font-bold ${covered ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-700'}">${covered ? 'Covered' : 'No guard'}</span></div>
        ${covered ? c.guards.map(g => `<button type="button" data-shift="${g.shiftId}" class="mt-2 w-full text-left flex items-center justify-between gap-3 hover:bg-slate-50 rounded px-1.5 py-1 cursor-pointer">
            <span class="text-sm font-semibold text-slate-900 truncate">${esc(g.guard)}</span>
            <span class="text-[11px] text-slate-500 whitespace-nowrap">since ${esc(fmtTime(g.startedAt))} · ${dur(g.minutes)}</span></button>`).join('')
          : '<div class="mt-2 text-[11px] text-slate-500">Nobody has gone on duty at this gate.</div>'}
      </div>`;
    }).join('');
    return `<section aria-labelledby="shCoverage"><h2 id="shCoverage" class="text-sm font-bold text-slate-800 mb-2">Gate coverage right now</h2><div class="grid grid-cols-1 md:grid-cols-3 gap-3">${cards}</div></section>`;
  }

  /** One row per guard on a shared time axis. Bars are placed by percentage, so the chart scales with the screen. */
  function renderTimeline() {
    const start = Date.parse(`${data.from}T00:00:00${MANILA}`);
    const end = Date.parse(`${data.to}T23:59:59${MANILA}`) + 1000;
    const span = end - start;
    const pct = (t) => Math.min(100, Math.max(0, (t - start) / span * 100));
    const days = Math.round(span / DAY);

    let ticks = '';
    if (days === 1) {
      for (let h = 0; h < 24; h += 3) ticks += `<div class="absolute top-0 bottom-0 border-l border-slate-200" style="left:${h / 24 * 100}%"><span class="absolute -top-0.5 left-1 text-[10px] text-slate-400 whitespace-nowrap">${h === 0 ? '12 AM' : h === 12 ? '12 PM' : h < 12 ? h + ' AM' : (h - 12) + ' PM'}</span></div>`;
    } else {
      const every = days <= 10 ? 1 : days <= 21 ? 2 : 7;
      for (let i = 0; i < days; i += every) {
        const label = new Date(start + i * DAY).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric' });
        ticks += `<div class="absolute top-0 bottom-0 border-l border-slate-200" style="left:${i / days * 100}%"><span class="absolute -top-0.5 left-1 text-[10px] text-slate-400 whitespace-nowrap">${esc(label)}</span></div>`;
      }
      if (days > 1) for (let i = 1; i < days; i++) if (i % (days <= 10 ? 1 : days <= 21 ? 2 : 7) !== 0) ticks += `<div class="absolute top-6 bottom-0 border-l border-slate-100" style="left:${i / days * 100}%"></div>`;
    }

    const nowMs = ms(data.now);
    const nowLine = nowMs >= start && nowMs <= end
      ? `<div class="absolute top-0 bottom-0 z-10 border-l-2 border-rose-500" style="left:${pct(nowMs)}%" title="Now"><span class="absolute -top-0.5 ${pct(nowMs) > 92 ? 'right-1' : 'left-1'} px-1 rounded bg-rose-500 text-white text-[9px] font-bold">NOW</span></div>` : '';

    const rows = data.guards.map(g => {
      const mine = data.shifts.filter(s => s.userId === g.userId);
      const bars = mine.map(s => {
        const a = ms(s.startedAt);
        const b = s.endedAt ? ms(s.endedAt) : nowMs;
        const left = pct(a), right = pct(b);
        const width = Math.max(0.6, right - left);
        const cls = ['sh-bar', s.endKind === 'open' ? 'sh-open' : '', s.endKind === 'auto' ? 'sh-auto' : '', s.long ? 'sh-long' : ''].filter(Boolean).join(' ');
        const tip = `${s.guard} · ${s.gate || 'No gate'}\n${fmtTime(s.startedAt)} – ${s.endedAt ? fmtTime(s.endedAt) : 'now'} (${dur(s.durationMinutes)})\n${END_KIND[s.endKind].label} · ${s.actions} action${s.actions === 1 ? '' : 's'}`;
        return `<button type="button" data-shift="${s.id}" class="${cls}" style="left:${left}%;width:${width}%;background:${gateColor(s.gate)}" title="${esc(tip)}" aria-label="${esc(tip.replace(/\n/g, '. '))}"></button>`;
      }).join('');
      return `<div class="flex items-stretch border-t border-slate-100">
        <div class="w-36 sm:w-44 flex-shrink-0 px-3 py-2.5 text-xs font-semibold text-slate-800 truncate" title="${esc(g.guard)}">${esc(g.guard)}</div>
        <div class="relative flex-1 min-h-[2.75rem]">${bars || '<span class="absolute inset-0 flex items-center pl-2 text-[11px] text-slate-300">no shift</span>'}</div></div>`;
    }).join('');

    const legend = Object.keys(GATE_COLOR).map(g => `<span class="inline-flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-sm" style="background:${GATE_COLOR[g]}"></span>${esc(g)}</span>`).join('')
      + '<span class="inline-flex items-center gap-1.5"><span class="w-4 h-2.5 rounded-sm sh-auto" style="background:#94a3b8"></span>Closed automatically</span>'
      + '<span class="inline-flex items-center gap-1.5"><span class="w-4 h-2.5 rounded-sm sh-long" style="background:#94a3b8"></span>Over ' + data.longShiftHours + ' h</span>'
      + '<span class="inline-flex items-center gap-1.5"><span class="w-4 h-2.5 rounded-sm sh-open" style="background:#94a3b8"></span>Still on duty</span>';

    return `<section aria-labelledby="shTimeline"><div class="flex flex-wrap items-end justify-between gap-2 mb-2">
        <h2 id="shTimeline" class="text-sm font-bold text-slate-800">Timeline</h2>
        <div class="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-slate-500">${legend}</div></div>
      <div class="bg-white border border-slate-200 rounded-lg shadow-2xs overflow-hidden">
        <div class="flex"><div class="w-36 sm:w-44 flex-shrink-0"></div><div class="relative flex-1 h-6">${ticks}${nowLine}</div></div>
        ${rows || '<div class="px-4 py-8 text-center text-slate-400 text-xs border-t border-slate-100">No guard accounts yet.</div>'}
      </div><p class="text-[11px] text-slate-500 mt-1.5">Click a bar to see what the guard did during that shift.</p></section>`;
  }

  function renderGuards() {
    const maxHours = Math.max(1, ...data.guards.map(g => g.hours));
    const rows = data.guards.map(g => `<tr class="hover:bg-slate-50/60">
        <td class="px-4 py-2.5 font-semibold text-slate-800">${esc(g.guard)}</td>
        <td class="px-4 py-2.5">${g.shifts}</td>
        <td class="px-4 py-2.5 w-56"><div class="flex items-center gap-2"><div class="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden"><div class="h-full rounded-full bg-ncst-navy" style="width:${g.hours / maxHours * 100}%"></div></div><span class="w-14 text-right font-semibold text-slate-800">${g.hours} h</span></div></td>
        <td class="px-4 py-2.5">${data.shifts.filter(s => s.userId === g.userId).reduce((a, s) => a + s.actions, 0)}</td>
        <td class="px-4 py-2.5 ${g.offShiftActions ? 'text-amber-700 font-bold' : 'text-slate-400'}">${g.offShiftActions ? g.offShiftActions + ' scan' + (g.offShiftActions === 1 ? '' : 's') + ' with no shift' : '—'}</td></tr>`).join('');
    return `<section aria-labelledby="shGuards"><h2 id="shGuards" class="text-sm font-bold text-slate-800 mb-2">Hours by guard</h2>
      <div class="bg-white border border-slate-200 rounded-lg shadow-2xs overflow-hidden"><div class="overflow-x-auto"><table class="w-full text-xs">
        <thead class="bg-slate-100/90 text-slate-700 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider"><tr>${th('Guard')}${th('Shifts')}${th('Hours on duty')}${th('Actions')}${th('Outside a shift')}</tr></thead>
        <tbody class="divide-y divide-slate-100">${rows || '<tr><td colspan="5" class="px-4 py-8 text-center text-slate-400">No guard accounts.</td></tr>'}</tbody></table></div></div>
      ${data.summary.offShiftActions ? '<p class="text-[11px] text-amber-700 mt-1.5">Scans made while a guard was not on duty are not tied to any shift. Ask the guard to press Go on duty when they start, so their work is on record.</p>' : ''}</section>`;
  }

  function chips(counts) {
    const out = Object.keys(TYPES).filter(k => counts[k]).map(k => `<span class="px-1.5 py-0.5 rounded border text-[10px] font-semibold ${TYPES[k].tone}">${counts[k]} ${counts[k] === 1 ? TYPES[k].one : TYPES[k].many}</span>`);
    return out.join(' ') || '<span class="text-slate-400">No activity</span>';
  }

  function shiftRows() {
    return data.shifts.filter(s => (!filter.guard || String(s.userId) === filter.guard) && (!filter.gate || (s.gate || '') === filter.gate))
      .slice().sort((a, b) => ms(b.startedAt) - ms(a.startedAt));
  }

  function renderShiftTable() {
    const rows = shiftRows();
    const gates = [...new Set(data.shifts.map(s => s.gate || ''))].filter(Boolean);
    const body = rows.map(s => `<tr class="hover:bg-slate-50/60 cursor-pointer" data-shift="${s.id}">
        <td class="px-4 py-2.5 font-semibold text-slate-800 min-w-[9rem]">${esc(s.guard)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap"><span class="inline-flex items-center gap-1.5"><span class="w-2 h-2 rounded-full" style="background:${gateColor(s.gate)}"></span>${esc(s.gate || '—')}</span></td>
        <td class="px-4 py-2.5 whitespace-nowrap">${fmt(s.startedAt)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap">${s.endedAt ? fmt(s.endedAt) : '<span class="text-emerald-700 font-bold">On duty</span>'}</td>
        <td class="px-4 py-2.5 whitespace-nowrap font-semibold ${s.long ? 'text-rose-600' : 'text-slate-800'}">${dur(s.durationMinutes)}${s.long ? ' <span title="Longer than ' + data.longShiftHours + ' hours">⚠</span>' : ''}</td>
        <td class="px-4 py-2.5"><span class="px-2 py-0.5 rounded text-[11px] font-semibold border ${END_KIND[s.endKind].tone}">${END_KIND[s.endKind].label}</span></td>
        <td class="px-4 py-2.5"><div class="flex flex-wrap gap-1">${chips(s.counts)}</div></td>
        <td class="px-4 py-2.5 text-right"><span class="text-ncst-navy font-semibold">Details ›</span></td></tr>`).join('');
    return `<section aria-labelledby="shList"><div class="flex flex-wrap items-end justify-between gap-2 mb-2">
        <h2 id="shList" class="text-sm font-bold text-slate-800">Shifts <span class="font-normal text-slate-500">(${rows.length})</span></h2>
        <div class="flex flex-wrap gap-2">
          <label class="sr-only" for="shFilterGuard">Guard</label>
          <select id="shFilterGuard" class="${inputCls}"><option value="">All guards</option>${data.guards.map(g => `<option value="${g.userId}"${filter.guard === String(g.userId) ? ' selected' : ''}>${esc(g.guard)}</option>`).join('')}</select>
          <label class="sr-only" for="shFilterGate">Gate</label>
          <select id="shFilterGate" class="${inputCls}"><option value="">All gates</option>${gates.map(g => `<option${filter.gate === g ? ' selected' : ''}>${esc(g)}</option>`).join('')}</select>
        </div></div>
      <div class="bg-white border border-slate-200 rounded-lg shadow-2xs overflow-hidden"><div class="overflow-x-auto"><table class="w-full text-xs">
        <thead class="bg-slate-100/90 text-slate-700 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider"><tr>${th('Guard')}${th('Gate')}${th('Started')}${th('Ended')}${th('Duration')}${th('How it ended')}${th('What they did')}${th('')}</tr></thead>
        <tbody class="divide-y divide-slate-100">${body || '<tr><td colspan="8" class="px-4 py-8 text-center text-slate-400">No shifts in this period.</td></tr>'}</tbody></table></div></div></section>`;
  }

  function render() {
    const presets = PRESETS.map(p => `<button type="button" data-preset="${p.id}" class="px-3 py-1.5 rounded-md text-xs font-bold border ${range.preset === p.id ? 'bg-ncst-navy text-white border-ncst-navy' : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'} cursor-pointer">${p.label}</button>`).join('');
    $('shiftsBody').innerHTML = `
      <div class="flex flex-wrap items-end gap-2">
        <div class="flex flex-wrap gap-1.5" role="group" aria-label="Period">${presets}</div>
        <label class="text-[11px] text-slate-500 ml-1">From <input id="shFrom" type="date" value="${esc(range.from)}" class="${inputCls}"></label>
        <label class="text-[11px] text-slate-500">To <input id="shTo" type="date" value="${esc(range.to)}" class="${inputCls}"></label>
        <button type="button" id="shApply" class="${navy}">Show</button>
      </div>
      ${renderKpis()}
      ${renderCoverage()}
      ${renderTimeline()}
      ${renderGuards()}
      ${renderShiftTable()}`;
  }

  /* ---------------------------------------------------------------- one shift */
  async function openShift(id) {
    let res;
    try { res = await ApiClient.getShiftDetail(id); } catch (err) { SP.showToast(err.message, 'error'); return; }
    const s = res.shift;
    const counts = {};
    res.activity.forEach(a => { counts[a.type] = (counts[a.type] || 0) + 1; });
    const log = res.activity.length
      ? `<ol class="relative border-l-2 border-slate-200 ml-2 space-y-3">${res.activity.map(a => `<li class="pl-4 relative">
          <span class="absolute -left-[7px] top-1.5 w-3 h-3 rounded-full border-2 border-white" style="background:${(TYPES[a.type] || {}).dot || '#64748b'}"></span>
          <div class="text-[11px] text-slate-400 font-mono">${esc(fmtClock(a.at))}</div>
          <div class="text-xs text-slate-800">${esc(a.label)}</div></li>`).join('')}</ol>${res.truncated ? '<p class="text-[11px] text-slate-500 mt-2">Showing the first 500 actions.</p>' : ''}`
      : '<p class="text-xs text-slate-500">Nothing was recorded under this guard\'s name during the shift.</p>';
    const html = `<div class="space-y-4 text-xs">
        <dl class="grid grid-cols-2 gap-3">
          <div><dt class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Gate</dt><dd class="font-semibold text-slate-900 mt-0.5">${esc(s.gate || '—')}</dd></div>
          <div><dt class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Duration</dt><dd class="font-semibold text-slate-900 mt-0.5">${dur(s.durationMinutes)}</dd></div>
          <div><dt class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Went on duty</dt><dd class="font-semibold text-slate-900 mt-0.5">${fmt(s.startedAt)}</dd></div>
          <div><dt class="text-[10px] font-bold uppercase tracking-wider text-slate-500">Went off duty</dt><dd class="font-semibold text-slate-900 mt-0.5">${s.endedAt ? fmt(s.endedAt) : 'Still on duty'}</dd></div>
        </dl>
        <div><span class="px-2 py-0.5 rounded text-[11px] font-semibold border ${END_KIND[s.endKind].tone}">${END_KIND[s.endKind].label}</span></div>
        ${s.endKind === 'auto' ? '<div class="px-3 py-2 rounded-md bg-amber-50 border border-amber-200 text-amber-900">The guard never ended this shift, so the system closed it automatically. The real duration may be shorter.</div>' : ''}
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1">Handover note</div>
          <div class="px-3 py-2 rounded-md bg-slate-50 border border-slate-200 text-slate-800 whitespace-pre-wrap">${s.handoverNotes ? esc(s.handoverNotes) : '<span class="text-slate-400">No note left.</span>'}</div></div>
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5">What they did</div><div class="flex flex-wrap gap-1 mb-3">${chips(counts)}</div>${log}</div>
      </div>`;
    SP.openDrawer(`${s.guard}`, `${s.gate || 'No gate'} · ${fmt(s.startedAt)}`, html, '');
  }

  /* ---------------------------------------------------------------- export */
  function exportCsv() {
    if (!data) return;
    const cell = (v) => `"${String(v == null ? '' : v).replace(/"/g, '""')}"`;
    const head = ['Guard', 'Gate', 'Started', 'Ended', 'Hours', 'How it ended', 'Entries', 'Exits', 'Denied', 'Violations', 'Held vehicles', 'Photos', 'Visitor passes', 'Handover note'];
    const lines = [head.map(cell).join(',')].concat(shiftRows().map(s => [s.guard, s.gate, s.startedAt, s.endedAt || '', (s.durationMinutes / 60).toFixed(2), END_KIND[s.endKind].label,
      s.counts.entry, s.counts.exit, s.counts.denied, s.counts.violation, s.counts.incident, s.counts.photo, s.counts.visitor, s.handoverNotes || ''].map(cell).join(',')));
    const url = URL.createObjectURL(new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url; a.download = `guard-shifts-${data.from}-to-${data.to}.csv`;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  /* ---------------------------------------------------------------- wiring */
  function wire() {
    const view = $('shiftsView');
    view.addEventListener('click', (e) => {
      const preset = e.target.closest('[data-preset]');
      if (preset) { range.preset = preset.dataset.preset; load(); return; }
      if (e.target.closest('#shApply')) {
        const from = $('shFrom').value, to = $('shTo').value;
        if (!from || !to) { SP.showToast('Choose both dates.', 'warning'); return; }
        range = { preset: 'custom', from, to };
        load();
        return;
      }
      const shift = e.target.closest('[data-shift]');
      if (shift) openShift(shift.dataset.shift);
    });
    view.addEventListener('change', (e) => {
      if (e.target.id === 'shFilterGuard') { filter.guard = e.target.value; render(); }
      if (e.target.id === 'shFilterGate') { filter.gate = e.target.value; render(); }
    });
    $('shiftsRefreshBtn').addEventListener('click', load);
    $('shiftsExportBtn').addEventListener('click', exportCsv);
  }

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('shiftsView', $('navShiftsBtn'), () => {
      range.preset = range.preset === 'custom' ? 'custom' : range.preset;
      load();
      clearInterval(timer);
      // Durations of shifts still running tick forward
      timer = setInterval(() => { if (!document.hidden && $('shiftsView').classList.contains('active')) load(); }, 60000);
    });
    wire();
    if (window.SPAuth) SPAuth.whenAuthenticated(() => { if (SPAuth.hasRole('admin')) load().catch(() => {}); });
  });
  window.SPLive?.subscribe(async changed => {
    if (!window.SPAuth?.hasRole('admin')) return;
    if (!changed.includes('shifts') && !(changed.includes('movements') && $('shiftsView').classList.contains('active'))) return;
    await load();
  });
})();
