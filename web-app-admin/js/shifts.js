/**
 * SecurePark - Guard Shifts (admin only)
 *
 * Shows when each guard went on and off duty (the "Go on duty" / "End shift" button of the mobile app), how long they
 * worked, which gate they covered and what they did during the shift. Everything is calculated on the server
 * (api/shifts.php); this screen draws it:
 *   - gate coverage right now
 *   - search and filters (guard, gate, how the shift ended) that apply to everything below them
 *   - a timeline, by day (one row per day on a 24 hour axis) or by guard (one row per guard over the whole period)
 *   - hours by guard, what each guard handled (scans, refusals, manual lookups, violations, photos), and the list of
 *     shifts, each opening to a time-ordered log of what the guard did
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  const MANILA = '+08:00';
  const DAY = 86400000;
  const GATE_COLOR = { 'Gate 1 (Main Ingress)': '#253475', 'Gate 2 (Main Egress)': '#0f766e', 'Patrol / Other': '#b45309' };
  const OTHER_COLOR = '#64748b';
  const gateColor = (g) => GATE_COLOR[g] || OTHER_COLOR;
  const gateShort = (g) => (g ? String(g).replace(/\s*\(.*\)\s*$/, '').replace(/\s*\/.*$/, '') : 'No gate');

  const PRESETS = [{ id: 'today', label: 'Today' }, { id: 'yesterday', label: 'Yesterday' }, { id: 'week', label: 'This week' }, { id: 'lastweek', label: 'Last week' }, { id: '7', label: 'Last 7 days' }, { id: '30', label: 'Last 30 days' }];
  const PAGE = 25;
  const TYPES = {
    entry: { one: 'entry', many: 'entries', tone: 'bg-emerald-50 text-emerald-700 border-emerald-200', dot: '#059669' },
    exit: { one: 'exit', many: 'exits', tone: 'bg-sky-50 text-sky-700 border-sky-200', dot: '#0284c7' },
    denied: { one: 'denied', many: 'denied', tone: 'bg-rose-50 text-rose-700 border-rose-200', dot: '#e11d48' },
    violation: { one: 'violation', many: 'violations', tone: 'bg-orange-50 text-orange-700 border-orange-200', dot: '#ea580c' },
    incident: { one: 'held', many: 'held', tone: 'bg-red-50 text-red-700 border-red-200', dot: '#dc2626' },
    photo: { one: 'photo', many: 'photos', tone: 'bg-violet-50 text-violet-700 border-violet-200', dot: '#7c3aed' },
    visitor: { one: 'visitor pass', many: 'visitor passes', tone: 'bg-indigo-50 text-indigo-700 border-indigo-200', dot: '#4f46e5' },
  };
  const END_KIND = {
    open: { label: 'On duty', tone: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
    manual: { label: 'Ended by guard', tone: 'bg-slate-50 text-slate-700 border-slate-200' },
    auto: { label: 'Closed automatically', tone: 'bg-amber-50 text-amber-800 border-amber-300' },
    moved: { label: 'Moved to another gate', tone: 'bg-sky-50 text-sky-700 border-sky-200' },
  };
  const STATUS_FILTERS = [['', 'Any status'], ['open', 'On duty now'], ['manual', 'Ended by guard'], ['auto', 'Closed automatically'], ['moved', 'Moved to another gate'], ['long', 'Over 12 hours']];

  let range = { preset: 'today', from: '', to: '' };
  let data = null;
  let filter = { q: '', guard: '', gate: '', status: '' };
  let mode = 'auto';        // timeline: auto | day | guard
  let limit = PAGE;
  let ticket = 0;
  let timer = null;
  let nowMs = Date.now();

  /* ---------------------------------------------------------------- helpers */
  const ms = (value) => Date.parse(String(value).replace(' ', 'T') + MANILA);
  const dayKey = (offset = 0) => new Date(Date.now() + offset * DAY).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
  const manila = (t, opts) => new Date(t).toLocaleString('en-PH', { timeZone: 'Asia/Manila', ...opts });

  function fmt(value) {
    if (!value) return '—';
    const d = ms(value);
    return isNaN(d) ? esc(value) : esc(manila(d, { month: 'short', day: '2-digit', hour: 'numeric', minute: '2-digit' }));
  }
  function fmtTime(value) {
    const d = ms(value);
    return isNaN(d) ? '' : manila(d, { hour: 'numeric', minute: '2-digit' });
  }
  function fmtClock(value) {
    const d = ms(value);
    return isNaN(d) ? '' : manila(d, { hour: 'numeric', minute: '2-digit', second: '2-digit' });
  }
  function dur(minutes) {
    const m = Math.max(0, Math.round(minutes));
    const h = Math.floor(m / 60);
    return h ? `${h}h ${String(m % 60).padStart(2, '0')}m` : `${m}m`;
  }
  /** 'YYYY-MM-DD' plus n days (Manila calendar). */
  const addDays = (key, n) => new Date(Date.parse(`${key}T12:00:00${MANILA}`) + n * DAY).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
  const daysBetween = (a, b) => Math.round((Date.parse(`${b}T12:00:00${MANILA}`) - Date.parse(`${a}T12:00:00${MANILA}`)) / DAY);
  /** 0 = Monday ... 6 = Sunday */
  const weekdayIndex = (key) => (new Date(Date.parse(`${key}T12:00:00${MANILA}`)).getUTCDay() + 6) % 7;
  function presetRange(id) {
    if (id === 'today') return { from: dayKey(0), to: dayKey(0) };
    if (id === 'yesterday') return { from: dayKey(-1), to: dayKey(-1) };
    if (id === 'week') return { from: addDays(dayKey(0), -weekdayIndex(dayKey(0))), to: dayKey(0) };
    if (id === 'lastweek') { const monday = addDays(dayKey(0), -weekdayIndex(dayKey(0)) - 7); return { from: monday, to: addDays(monday, 6) }; }
    return { from: dayKey(id === '7' ? -6 : -29), to: dayKey(0) };
  }
  function rangeLabel() {
    const a = new Date(Date.parse(`${range.from}T12:00:00${MANILA}`)), b = new Date(Date.parse(`${range.to}T12:00:00${MANILA}`));
    const f = (d, withYear) => d.toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', weekday: 'short', month: 'short', day: 'numeric', ...(withYear ? { year: 'numeric' } : {}) });
    const n = daysBetween(range.from, range.to) + 1;
    return n === 1 ? f(a, true) : `${f(a)} – ${f(b, true)} · ${n} days`;
  }
  /** Hours of a shift that fall on one calendar day (dayStart = ms of 00:00 Manila). */
  const hoursOnDay = (sh, dayStart) => Math.max(0, (Math.min(sh.endedAt ? ms(sh.endedAt) : nowMs, dayStart + DAY, nowMs) - Math.max(ms(sh.startedAt), dayStart)) / 3600000);
  /** "Maria Santos (NCST-SEC-07)" -> { name, badge } */
  function person(label) {
    const m = String(label || '').match(/^(.*?)\s*\(([^)]+)\)\s*$/);
    return m ? { name: m[1], badge: m[2] } : { name: String(label || ''), badge: '' };
  }
  const who = (label) => { const p = person(label); return `<span class="font-semibold text-slate-800">${esc(p.name)}</span>${p.badge ? `<span class="block text-[10px] text-slate-400 font-medium leading-tight">${esc(p.badge)}</span>` : ''}`; };

  const btn = 'px-3 py-1.5 rounded-md text-xs font-semibold shadow-xs cursor-pointer';
  const navy = btn + ' bg-ncst-navy hover:bg-ncst-navyDark text-white';
  const ghost = btn + ' border border-slate-200 bg-white hover:bg-slate-50 text-slate-700';
  const inputCls = 'h-9 px-3 rounded-lg border border-slate-200 bg-slate-50/50 text-xs text-slate-800 focus:bg-white focus:outline-none focus:ring-2 focus:ring-ncst-navy/20';
  const th = (t, cls = '') => `<th scope="col" class="text-left font-bold px-4 py-3 ${cls}">${t}</th>`;
  const card = 'bg-white border border-slate-200 rounded-lg shadow-2xs overflow-hidden';

  function sectionHead(id, title, sub, right = '') {
    return `<div class="flex flex-wrap items-end justify-between gap-3 mb-3"><div><h2 id="${id}" class="text-sm font-bold text-slate-900">${title}</h2>${sub ? `<p class="text-[11px] text-slate-500 mt-0.5">${sub}</p>` : ''}</div>${right}</div>`;
  }

  /* ---------------------------------------------------------------- load */
  async function load() {
    const mine = ++ticket;
    const body = $('shiftsBody');
    if (!data) body.innerHTML = '<div class="px-4 py-10 text-center text-slate-400 text-xs">Loading…</div>';
    try {
      if (range.preset !== 'custom') Object.assign(range, presetRange(range.preset));
      const [res, report] = await Promise.all([ApiClient.getShiftTimeline(range.from, range.to), ApiClient.getShiftReport(range.from, range.to)]);
      if (mine !== ticket) return;
      data = res;
      data.report = report.guards;   // what each guard handled in the period (the old Admin Center "Guard duty" report)
      nowMs = ms(res.now);
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

  /* ---------------------------------------------------------------- filtering */
  const filtering = () => !!(filter.q || filter.guard || filter.gate || filter.status);

  function matches(s) {
    if (filter.guard && String(s.userId) !== filter.guard) return false;
    if (filter.gate && (s.gate || '') !== filter.gate) return false;
    if (filter.status === 'long' ? !s.long : (filter.status && s.endKind !== filter.status)) return false;
    const q = filter.q.trim().toLowerCase();
    return !q || [s.guard, s.gate, s.handoverNotes, END_KIND[s.endKind].label].some(v => String(v || '').toLowerCase().includes(q));
  }
  const visibleShifts = () => data.shifts.filter(matches);

  /** Hours of a shift that fall inside the chosen period. */
  function hoursInRange(s) {
    const a = Math.max(ms(s.startedAt), Date.parse(`${data.from}T00:00:00${MANILA}`));
    const b = Math.min(s.endedAt ? ms(s.endedAt) : nowMs, Date.parse(`${data.to}T23:59:59${MANILA}`) + 1000, nowMs);
    return Math.max(0, (b - a) / 3600000);
  }

  /* ---------------------------------------------------------------- top of the page */
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
      ${kpi('Hours on duty', s.hours, 'in this period')}
      ${kpi('Shifts', s.shifts, s.shifts ? `avg ${dur(s.hours * 60 / s.shifts)}` : 'none in this period')}
      ${kpi('Actions during shifts', s.actions, 'scans, violations, holds, photos')}
      ${kpi('Needs a look', attention, [s.autoClosed ? `${s.autoClosed} auto-closed` : '', s.longShifts ? `${s.longShifts} over ${data.longShiftHours} h` : '', s.offShiftActions ? `${s.offShiftActions} off-shift` : ''].filter(Boolean).join(' · ') || 'all clear', attention ? 'border-amber-300' : 'border-slate-200')}
    </div>`;
  }

  function renderCoverage() {
    const cards = data.coverage.map(c => {
      const covered = c.guards.length > 0;
      return `<div class="rounded-lg border ${covered ? 'border-emerald-200 bg-white' : 'border-dashed border-rose-300 bg-rose-50/40'} p-4 shadow-2xs">
        <div class="flex items-center gap-2"><span class="w-2.5 h-2.5 rounded-full flex-shrink-0" style="background:${gateColor(c.gate)}"></span>
          <span class="text-xs font-bold text-slate-800 truncate">${esc(c.gate)}</span>
          <span class="ml-auto px-2 py-0.5 rounded text-[10px] font-bold ${covered ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-700'}">${covered ? 'Covered' : 'No guard'}</span></div>
        ${covered ? c.guards.map(g => `<button type="button" data-shift="${g.shiftId}" class="mt-2.5 w-full text-left flex items-center justify-between gap-3 hover:bg-slate-50 rounded px-1.5 py-1 cursor-pointer">
            <span class="text-sm truncate">${who(g.guard)}</span>
            <span class="text-[11px] text-slate-500 whitespace-nowrap">since ${esc(fmtTime(g.startedAt))} · ${dur(g.minutes)}</span></button>`).join('')
          : '<div class="mt-2.5 text-[11px] text-slate-500">Nobody has gone on duty at this gate.</div>'}
      </div>`;
    }).join('');
    return `<section aria-labelledby="shCoverage">${sectionHead('shCoverage', 'Gate coverage right now', 'Who is on duty at each gate at this moment.')}<div class="grid grid-cols-1 md:grid-cols-3 gap-3">${cards}</div></section>`;
  }

  function renderFilterBar() {
    const gates = [...new Set([...Object.keys(GATE_COLOR), ...data.shifts.map(s => s.gate || '')])].filter(Boolean);
    return `<section aria-label="Search and filter shifts" class="${card} p-3.5">
      <div class="flex flex-wrap items-center gap-2">
        <label for="shSearch" class="sr-only">Search shifts</label>
        <div class="relative flex-1 min-w-[14rem]">
          <svg class="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>
          <input id="shSearch" type="search" value="${esc(filter.q)}" placeholder="Search guard, gate or handover note" autocomplete="off" class="${inputCls} w-full pl-9">
        </div>
        <label class="sr-only" for="shFilterGuard">Guard</label>
        <select id="shFilterGuard" class="${inputCls}"><option value="">All guards</option>${data.guards.map(g => `<option value="${g.userId}"${filter.guard === String(g.userId) ? ' selected' : ''}>${esc(person(g.guard).name)}</option>`).join('')}</select>
        <label class="sr-only" for="shFilterGate">Gate</label>
        <select id="shFilterGate" class="${inputCls}"><option value="">All gates</option>${gates.map(g => `<option${filter.gate === g ? ' selected' : ''}>${esc(g)}</option>`).join('')}</select>
        <label class="sr-only" for="shFilterStatus">Status</label>
        <select id="shFilterStatus" class="${inputCls}">${STATUS_FILTERS.map(([v, l]) => `<option value="${v}"${filter.status === v ? ' selected' : ''}>${l}</option>`).join('')}</select>
        <button type="button" id="shClear" class="${ghost}${filtering() ? '' : ' hidden'}">Clear filters</button>
      </div>
      <div id="shFilterNote" class="text-[11px] text-slate-500 mt-2"></div>
    </section>`;
  }

  /* ---------------------------------------------------------------- timeline */
  /** Puts overlapping bars in separate lanes so none is hidden. segs: [{a, b, ...}] */
  function pack(segs) {
    const lanes = [];
    segs.slice().sort((x, y) => x.a - y.a).forEach(seg => {
      let i = lanes.findIndex(end => end <= seg.a);
      if (i < 0) { i = lanes.length; lanes.push(0); }
      lanes[i] = seg.b;
      seg.lane = i;
    });
    return Math.max(1, lanes.length);
  }

  const LANE_H = 30;
  const LANE_GAP = 4;

  function barHtml(seg, start, span) {
    const s = seg.s;
    const left = (seg.a - start) / span * 100;
    const width = Math.max(0.4, (seg.b - seg.a) / span * 100);
    const cls = ['sh-bar', 'sh-seg', s.endKind === 'open' ? 'sh-open' : '', s.endKind === 'auto' ? 'sh-auto' : '', s.long ? 'sh-long' : ''].filter(Boolean).join(' ');
    const p = person(s.guard);
    const tip = `${p.name} · ${s.gate || 'No gate'}\n${fmtTime(s.startedAt)} – ${s.endedAt ? fmtTime(s.endedAt) : 'now'} (${dur(s.durationMinutes)})\n${END_KIND[s.endKind].label} · ${s.actions} action${s.actions === 1 ? '' : 's'}`;
    const radius = `border-radius:${seg.contFrom ? '0' : '6px'} ${seg.contTo ? '0' : '6px'} ${seg.contTo ? '0' : '6px'} ${seg.contFrom ? '0' : '6px'}`;
    const label = `${seg.contFrom ? '◂ ' : ''}${esc(p.name.split(' ')[0])} · ${esc(gateShort(s.gate))}${seg.contTo ? ' ▸' : ''}`;
    return `<button type="button" data-shift="${s.id}" class="${cls}" style="left:${left}%;width:${width}%;top:${seg.lane * (LANE_H + LANE_GAP) + 6}px;height:${LANE_H}px;background-color:${gateColor(s.gate)};${radius}" title="${esc(tip)}" aria-label="${esc(tip.replace(/\n/g, '. '))}"><span class="sh-seg-text">${label}</span></button>`;
  }

  const trackHeight = (lanes) => lanes * (LANE_H + LANE_GAP) + 8;

  function hourAxis(compact) {
    let t = '';
    const step = compact ? 6 : 3;
    for (let h = 0; h < 24; h += step) {
      const label = h === 0 ? '12 AM' : h === 12 ? '12 PM' : h < 12 ? `${h} AM` : `${h - 12} PM`;
      t += `<div class="absolute top-0 bottom-0" style="left:${h / 24 * 100}%"><span class="absolute top-1.5 left-1 text-[10px] text-slate-400 whitespace-nowrap">${label}</span></div>`;
    }
    return t;
  }

  /** One row per day on a 24 hour axis. */
  function timelineByDay(shifts) {
    const start = Date.parse(`${data.from}T00:00:00${MANILA}`);
    const days = Math.round((Date.parse(`${data.to}T23:59:59${MANILA}`) + 1000 - start) / DAY);
    const today = dayKey(0);
    let rows = '';
    for (let i = days - 1; i >= 0; i--) {
      const a = start + i * DAY, b = a + DAY;
      const segs = [];
      shifts.forEach(s => {
        const sa = ms(s.startedAt), sb = s.endedAt ? ms(s.endedAt) : nowMs;
        if (sb > a && sa < b) segs.push({ s, a: Math.max(sa, a), b: Math.min(sb, b), contFrom: sa < a, contTo: sb > b });
      });
      const lanes = pack(segs);
      const key = new Date(a).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
      const isToday = key === today;
      const weekend = weekdayIndex(key) >= 5;
      const dayHours = segs.reduce((n, seg) => n + (seg.b - seg.a) / 3600000, 0);
      const nowLine = isToday ? `<div class="absolute top-0 bottom-0 z-10 border-l-2 border-rose-500" style="left:${(nowMs - a) / DAY * 100}%" title="Now"></div>` : '';
      rows += `<div class="flex items-stretch border-t border-slate-100">
        <button type="button" data-day="${key}" title="Show only this day" class="w-28 sm:w-36 flex-shrink-0 px-3 py-3 text-left cursor-pointer hover:bg-slate-100 ${isToday ? 'bg-ncst-navy/5' : weekend ? 'bg-slate-50' : ''}">
          <div class="text-xs font-bold text-slate-800">${esc(manila(a, { weekday: 'short' }))}${isToday ? ' <span class="ml-1 px-1 rounded bg-rose-500 text-white text-[9px] font-bold align-middle">TODAY</span>' : ''}</div>
          <div class="text-[11px] text-slate-500">${esc(manila(a, { month: 'short', day: 'numeric' }))}</div>
          <div class="text-[10px] ${segs.length ? 'text-slate-600 font-semibold' : 'text-slate-300'}">${segs.length ? `${segs.length} shift${segs.length === 1 ? '' : 's'} · ${dur(dayHours * 60)}` : 'no shifts'}</div>
        </button>
        <div class="relative flex-1 sh-grid ${isToday ? 'bg-ncst-navy/5' : weekend ? 'bg-slate-50/70' : ''}" style="height:${trackHeight(lanes)}px">${nowLine}${segs.map(seg => barHtml(seg, a, DAY)).join('') || '<span class="absolute inset-0 flex items-center pl-3 text-[11px] text-slate-300">no shifts</span>'}</div></div>`;
    }
    // The hour axis stays in view while a long period scrolls
    return `<div class="${card}"><div class="max-h-[34rem] overflow-y-auto">
      <div class="sticky top-0 z-20 flex bg-white border-b border-slate-100"><div class="w-28 sm:w-36 flex-shrink-0"></div><div class="relative flex-1 h-7">${hourAxis(window.innerWidth < 900)}</div></div>${rows}</div></div>`;
  }

  /** One row per guard across the whole period. */
  function timelineByGuard(shifts) {
    const start = Date.parse(`${data.from}T00:00:00${MANILA}`);
    const end = Date.parse(`${data.to}T23:59:59${MANILA}`) + 1000;
    const span = end - start;
    const days = Math.round(span / DAY);
    let axis = '', bands = '';
    if (days === 1) {
      axis = hourAxis(window.innerWidth < 900);
      for (let h = 0; h < 24; h += 3) bands += `<div class="absolute top-0 bottom-0 border-l border-slate-100" style="left:${h / 24 * 100}%"></div>`;
    } else {
      const every = days <= 10 ? 1 : days <= 21 ? 2 : 7;
      for (let i = 0; i < days; i++) {
        const label = new Date(start + i * DAY).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric' });
        if (i % 2 === 1) bands += `<div class="absolute top-0 bottom-0 bg-slate-50" style="left:${i / days * 100}%;width:${100 / days}%"></div>`;
        const monday = weekdayIndex(addDays(data.from, i)) === 0;
        bands += `<div class="absolute top-0 bottom-0 border-l ${monday && days > 7 ? 'border-slate-400/70' : 'border-slate-200'}" style="left:${i / days * 100}%"></div>`;
        if (i % every === 0) axis += `<div class="absolute top-0 bottom-0" style="left:${i / days * 100}%"><span class="absolute top-1.5 left-1 text-[10px] text-slate-400 whitespace-nowrap">${esc(label)}</span></div>`;
      }
    }
    const nowLine = nowMs >= start && nowMs <= end
      ? `<div class="absolute top-0 bottom-0 z-10 border-l-2 border-rose-500" style="left:${(nowMs - start) / span * 100}%" title="Now"></div>` : '';
    const nowTag = nowMs >= start && nowMs <= end
      ? `<div class="absolute top-0 bottom-0 z-10" style="left:${(nowMs - start) / span * 100}%"><span class="absolute top-1.5 ${(nowMs - start) / span > 0.92 ? 'right-0.5' : 'left-0.5'} px-1 rounded bg-rose-500 text-white text-[9px] font-bold">NOW</span></div>` : '';

    const guards = data.guards.filter(g => !filtering() || shifts.some(s => s.userId === g.userId));
    const rows = guards.map(g => {
      const mine = shifts.filter(s => s.userId === g.userId);
      const segs = mine.map(s => ({ s, a: Math.max(ms(s.startedAt), start), b: Math.min(s.endedAt ? ms(s.endedAt) : nowMs, end), contFrom: ms(s.startedAt) < start, contTo: !!s.endedAt && ms(s.endedAt) > end }));
      const lanes = pack(segs);
      return `<div class="flex items-stretch border-t border-slate-100">
        <button type="button" data-guard="${g.userId}" title="Open this guard's profile" class="w-28 sm:w-44 flex-shrink-0 px-3 py-3 text-xs min-w-0 text-left cursor-pointer hover:bg-slate-50">${who(g.guard)}</button>
        <div class="relative flex-1" style="height:${trackHeight(lanes)}px">${bands}${nowLine}${segs.map(seg => barHtml(seg, start, span)).join('') || '<span class="absolute inset-0 flex items-center pl-3 text-[11px] text-slate-300">no shift</span>'}</div></div>`;
    }).join('');
    return `<div class="${card}">
      <div class="flex"><div class="w-28 sm:w-44 flex-shrink-0"></div><div class="relative flex-1 h-7">${axis}${nowTag}</div></div>
      ${rows || '<div class="px-4 py-8 text-center text-slate-400 text-xs border-t border-slate-100">No guards match.</div>'}</div>`;
  }

  function renderTimeline() {
    const shifts = visibleShifts();
    const days = Math.round((Date.parse(`${data.to}T23:59:59${MANILA}`) + 1000 - Date.parse(`${data.from}T00:00:00${MANILA}`)) / DAY);
    const active = mode === 'auto' ? (days > 1 ? 'day' : 'guard') : mode;
    const toggle = ['day', 'guard'].map(m => `<button type="button" data-mode="${m}" aria-pressed="${active === m}" class="px-3 py-1.5 text-xs font-bold ${active === m ? 'bg-ncst-navy text-white' : 'bg-white text-slate-600 hover:bg-slate-50'} cursor-pointer">${m === 'day' ? 'By day' : 'By guard'}</button>`).join('');
    const legend = Object.keys(GATE_COLOR).map(g => `<span class="inline-flex items-center gap-1.5"><span class="w-3 h-3 rounded-sm" style="background:${GATE_COLOR[g]}"></span>${esc(g)}</span>`).join('')
      + '<span class="inline-flex items-center gap-1.5"><span class="w-4 h-3 rounded-sm sh-auto" style="background-color:#94a3b8"></span>Closed automatically</span>'
      + `<span class="inline-flex items-center gap-1.5"><span class="w-4 h-3 rounded-sm sh-long" style="background-color:#94a3b8"></span>Over ${data.longShiftHours} h</span>`
      + '<span class="inline-flex items-center gap-1.5"><span class="w-4 h-3 rounded-sm sh-open" style="background-color:#94a3b8"></span>Still on duty</span>';
    return `<section aria-labelledby="shTimeline">
      ${sectionHead('shTimeline', 'Timeline', active === 'day' ? 'One row per day, midnight to midnight. A shift that crosses midnight continues on the next row.' : 'One row per guard across the whole period.',
        `<div class="inline-flex rounded-lg border border-slate-200 overflow-hidden shadow-2xs" role="group" aria-label="Timeline layout">${toggle}</div>`)}
      <div class="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-slate-500 mb-2">${legend}</div>
      ${active === 'day' ? timelineByDay(shifts) : timelineByGuard(shifts)}
      <p class="text-[11px] text-slate-500 mt-2">${shifts.length ? 'Click a bar to see what the guard did during that shift.' : 'No shifts match the search and filters.'}</p></section>`;
  }

  /* ---------------------------------------------------------------- hours and list */
  function renderGuards() {
    const shifts = visibleShifts();
    const rows = data.guards.map(g => {
      const mine = shifts.filter(s => s.userId === g.userId);
      return { g, shifts: mine.length, hours: mine.reduce((a, s) => a + hoursInRange(s), 0), actions: mine.reduce((a, s) => a + s.actions, 0) };
    }).filter(r => !filtering() || r.shifts > 0);
    const maxHours = Math.max(1, ...rows.map(r => r.hours));
    const body = rows.map(r => `<tr class="hover:bg-slate-50/70 cursor-pointer" data-guard="${r.g.userId}" title="Open this guard's profile">
        <td class="px-4 py-3 min-w-[10rem]">${who(r.g.guard)}</td>
        <td class="px-4 py-3">${r.shifts}</td>
        <td class="px-4 py-3 w-64"><div class="flex items-center gap-3"><div class="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden"><div class="h-full rounded-full bg-ncst-navy" style="width:${r.hours / maxHours * 100}%"></div></div><span class="w-16 text-right font-semibold text-slate-800">${dur(r.hours * 60)}</span></div></td>
        <td class="px-4 py-3">${r.shifts ? dur(r.hours * 60 / r.shifts) : '—'}</td>
        <td class="px-4 py-3">${r.actions}</td>
        <td class="px-4 py-3 ${r.g.offShiftActions ? 'text-amber-700 font-bold' : 'text-slate-400'}">${r.g.offShiftActions ? r.g.offShiftActions + ' scan' + (r.g.offShiftActions === 1 ? '' : 's') + ' not on duty' : '—'}</td></tr>`).join('');
    return `<section aria-labelledby="shGuards">${sectionHead('shGuards', 'Hours by guard', 'Time on duty inside the chosen period, for the shifts that match the filters above. Click a guard for their profile.')}
      <div class="${card}"><div class="overflow-x-auto"><table class="w-full text-xs">
        <thead class="bg-slate-100/90 text-slate-700 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider"><tr>${th('Guard')}${th('Shifts')}${th('Hours on duty')}${th('Average shift')}${th('Actions')}${th('<span title="Gate passages, violations or photos recorded while the guard had not gone on duty">Scans with no shift</span>')}</tr></thead>
        <tbody class="divide-y divide-slate-100">${body || '<tr><td colspan="6" class="px-4 py-8 text-center text-slate-400">No guards match.</td></tr>'}</tbody></table></div></div>
      ${data.summary.offShiftActions ? '<p class="text-[11px] text-amber-700 mt-2">Scans made while a guard was not on duty are not tied to any shift. Guards are asked to go on duty when they sign in; older app versions do not ask.</p>' : ''}</section>`;
  }

  /** What each guard handled in the period, with the rates worth a conversation (the former Admin Center "Guard duty" report). */
  function renderActivity() {
    const q = filter.q.trim().toLowerCase();
    const rows = data.report.filter(g => (!filter.guard || String(g.userId) === filter.guard) && (!q || String(g.guard).toLowerCase().includes(q)))
      .filter(g => !filtering() || g.shifts > 0 || g.entries + g.exits + g.denials > 0 || !q);
    const pct = (n) => n ? `${n}%` : '—';
    const body = rows.map(g => `<tr class="hover:bg-slate-50/70 cursor-pointer" data-guard="${g.userId}" title="Open this guard's profile">
        <td class="px-4 py-3 min-w-[10rem]">${who(g.guard)}</td>
        <td class="px-4 py-3">${g.entries}</td><td class="px-4 py-3">${g.exits}</td>
        <td class="px-4 py-3 ${g.denialRate >= 25 ? 'text-rose-600 font-bold' : ''}">${g.denials} <span class="text-slate-400 font-normal">(${pct(g.denialRate)})</span></td>
        <td class="px-4 py-3 ${g.manualRate >= 25 ? 'text-amber-700 font-bold' : ''}">${g.manualLookups} <span class="text-slate-400 font-normal">(${pct(g.manualRate)})</span></td>
        <td class="px-4 py-3">${g.violationsIssued}</td><td class="px-4 py-3">${g.photos}</td></tr>`).join('');
    return `<section aria-labelledby="shActivity">${sectionHead('shActivity', 'What each guard handled', "Everything recorded under the guard's name in the chosen period, whether or not a shift was open.")}
      <div class="${card}"><div class="overflow-x-auto"><table class="w-full text-xs">
        <thead class="bg-slate-100/90 text-slate-700 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider"><tr>${th('Guard')}${th('Entries')}${th('Exits')}${th('Denied')}${th('Manual lookups')}${th('Violations')}${th('Photos')}</tr></thead>
        <tbody class="divide-y divide-slate-100">${body || '<tr><td colspan="7" class="px-4 py-8 text-center text-slate-400">No guards match.</td></tr>'}</tbody></table></div></div>
      <p class="text-[11px] text-slate-500 mt-2">A high share of denied passages or manual plate lookups is worth a conversation: it can mean a trouble spot at the gate, or passes being waved through without a scan.</p></section>`;
  }

  function chips(counts) {
    const out = Object.keys(TYPES).filter(k => counts[k]).map(k => `<span class="px-1.5 py-0.5 rounded border text-[10px] font-semibold whitespace-nowrap ${TYPES[k].tone}">${counts[k]} ${counts[k] === 1 ? TYPES[k].one : TYPES[k].many}</span>`);
    return out.join(' ') || '<span class="text-slate-400">No activity</span>';
  }

  const sortedShifts = () => visibleShifts().slice().sort((a, b) => ms(b.startedAt) - ms(a.startedAt));

  function renderShiftTable() {
    const all = sortedShifts();
    const rows = all.slice(0, limit);
    const body = rows.map(s => `<tr class="hover:bg-slate-50/70 cursor-pointer" data-shift="${s.id}">
        <td class="px-4 py-3 min-w-[10rem]"><div class="flex items-stretch gap-3"><span class="w-1 rounded-full flex-shrink-0" style="background:${gateColor(s.gate)}"></span><div>${who(s.guard)}<span class="block text-[11px] text-slate-500">${esc(s.gate || '—')}</span></div></div></td>
        <td class="px-4 py-3 whitespace-nowrap"><div class="font-semibold text-slate-800">${fmt(s.startedAt)}</div><div class="text-[11px] text-slate-500">${s.endedAt ? 'to ' + fmt(s.endedAt) : '<span class="text-emerald-700 font-bold">still on duty</span>'}</div></td>
        <td class="px-4 py-3 whitespace-nowrap font-bold ${s.long ? 'text-rose-600' : 'text-slate-800'}">${dur(s.durationMinutes)}${s.long ? ' <span title="Longer than ' + data.longShiftHours + ' hours">⚠</span>' : ''}</td>
        <td class="px-4 py-3"><span class="px-2 py-0.5 rounded text-[11px] font-semibold border whitespace-nowrap ${END_KIND[s.endKind].tone}">${END_KIND[s.endKind].label}</span></td>
        <td class="px-4 py-3"><div class="flex flex-wrap gap-1 max-w-md">${chips(s.counts)}</div></td>
        <td class="px-4 py-3 text-right whitespace-nowrap"><span class="text-ncst-navy font-semibold">Details ›</span></td></tr>`).join('');
    return `<section aria-labelledby="shList">${sectionHead('shList', `Shifts <span class="font-normal text-slate-500">(${all.length}${filtering() ? ' of ' + data.shifts.length : ''})</span>`, 'Newest first. Click a row for the handover note and everything the guard did.')}
      <div class="${card}"><div class="overflow-x-auto"><table class="w-full text-xs">
        <thead class="bg-slate-100/90 text-slate-700 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider"><tr>${th('Guard and gate')}${th('Went on duty')}${th('Duration')}${th('How it ended')}${th('What they did')}${th('')}</tr></thead>
        <tbody class="divide-y divide-slate-100">${body || `<tr><td colspan="6" class="px-4 py-10 text-center text-slate-400">${data.shifts.length ? 'No shifts match the search and filters.' : 'No shifts in this period.'}</td></tr>`}</tbody></table></div>
        ${all.length > rows.length ? `<div class="flex items-center justify-between gap-3 px-4 py-3 border-t border-slate-100 text-[11px] text-slate-500"><span>Showing ${rows.length} of ${all.length}</span><button type="button" id="shMore" class="${ghost}">Show more</button></div>` : ''}
      </div></section>`;
  }

  /** Everything that follows the filters. */
  function renderResults() {
    const host = $('shResults');
    if (!host) return;
    host.innerHTML = renderTimeline() + renderGuards() + renderActivity() + renderShiftTable();
    const note = $('shFilterNote');
    if (note) note.textContent = filtering()
      ? `${visibleShifts().length} of ${data.shifts.length} shifts match. The cards above stay on the whole period.`
      : 'Search and filters apply to the timeline, hours and list below.';
    $('shClear')?.classList.toggle('hidden', !filtering());
  }

  function render() {
    const typing = document.activeElement && document.activeElement.id === 'shSearch'
      ? { start: document.activeElement.selectionStart, end: document.activeElement.selectionEnd } : null;
    const presets = PRESETS.map(p => `<button type="button" data-preset="${p.id}" class="px-3 py-1.5 rounded-md text-xs font-bold border ${range.preset === p.id ? 'bg-ncst-navy text-white border-ncst-navy' : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'} cursor-pointer">${p.label}</button>`).join('');
    const atToday = range.to >= dayKey(0);
    const stepBtn = 'w-9 h-9 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 font-bold cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed';
    const jump = [['shCoverage', 'Coverage'], ['shTimeline', 'Timeline'], ['shGuards', 'Hours'], ['shActivity', 'What guards handled'], ['shList', 'Shifts']]
      .map(([id, label]) => `<button type="button" data-jump="${id}" class="px-2.5 py-1 rounded-full border border-slate-200 bg-white hover:bg-slate-50 text-[11px] font-semibold text-slate-600 cursor-pointer">${label}</button>`).join('');
    $('shiftsBody').innerHTML = `
      <div class="${card} p-3.5 space-y-3">
        <div class="flex flex-wrap items-center gap-2">
          <button type="button" data-step="-1" class="${stepBtn}" aria-label="Earlier period" title="Earlier period">&#8249;</button>
          <div class="min-w-[13rem] text-center"><div class="text-sm font-bold text-slate-900" id="shRangeLabel">${esc(rangeLabel())}</div></div>
          <button type="button" data-step="1" class="${stepBtn}" aria-label="Later period" title="Later period" ${atToday ? 'disabled' : ''}>&#8250;</button>
          <div class="flex flex-wrap gap-1.5 ml-2" role="group" aria-label="Period">${presets}</div>
        </div>
        <div class="flex flex-wrap items-end gap-2">
          <label class="text-[11px] text-slate-500">From <input id="shFrom" type="date" value="${esc(range.from)}" class="${inputCls}"></label>
          <label class="text-[11px] text-slate-500">To <input id="shTo" type="date" value="${esc(range.to)}" class="${inputCls}"></label>
          <button type="button" id="shApply" class="${navy}">Show</button>
          <div class="ml-auto flex flex-wrap items-center gap-1.5" role="group" aria-label="Jump to a section"><span class="text-[11px] text-slate-400 mr-0.5">Jump to</span>${jump}</div>
        </div>
      </div>
      ${renderKpis()}
      ${renderCoverage()}
      ${renderFilterBar()}
      <div id="shResults" class="space-y-7"></div>`;
    renderResults();
    if (typing && $('shSearch')) { const el = $('shSearch'); el.focus(); try { el.setSelectionRange(typing.start, typing.end); } catch (_) {} }
  }

  /* ---------------------------------------------------------------- one shift */
  const factCell = (label, value) => `<div><dt class="text-[10px] font-bold uppercase tracking-wider text-slate-500">${label}</dt><dd class="font-semibold text-slate-900 mt-0.5">${value}</dd></div>`;

  /** The whole shift on one line: clock-on at the left, clock-off (or now) at the right, one tick per thing the guard did. */
  function shiftStrip(s, activity) {
    const a = ms(s.startedAt), b = s.endedAt ? ms(s.endedAt) : nowMs, span = Math.max(60000, b - a);
    const ticks = activity.map(e => {
      const pos = Math.min(100, Math.max(0, (ms(e.at) - a) / span * 100));
      return `<span class="absolute top-1 bottom-1 w-[3px] rounded-full" style="left:calc(${pos}% - 1px);background:${(TYPES[e.type] || {}).dot || '#64748b'}" title="${esc(fmtClock(e.at) + ' · ' + e.label)}"></span>`;
    }).join('');
    return `<div>
      <div class="relative h-9 rounded-md border border-slate-200 overflow-hidden" style="background:${gateColor(s.gate)}22" role="img" aria-label="Everything the guard did, from going on duty to going off duty">${ticks}</div>
      <div class="flex justify-between text-[10px] font-mono text-slate-500 mt-1"><span>${esc(fmtTime(s.startedAt))} on duty</span><span>${dur(span / 60000)}</span><span>${s.endedAt ? esc(fmtTime(s.endedAt)) + ' off duty' : 'now'}</span></div></div>`;
  }

  /** Clock-on, every action (with the quiet gaps between them), clock-off: the log covers the entire shift. */
  function shiftLog(s, activity, only) {
    const items = [{ at: s.startedAt, kind: 'start', label: `Went on duty at ${s.gate || 'no gate'}` }]
      .concat(activity.filter(e => !only || e.type === only))
      .concat([{ at: s.endedAt || null, kind: 'end', label: s.endedAt ? `Went off duty · ${END_KIND[s.endKind].label}` : 'Still on duty' }]);
    let html = '', prev = null;
    items.forEach(it => {
      const t = it.at ? ms(it.at) : nowMs;
      if (!only && prev !== null && t - prev >= 30 * 60000) html += `<li class="pl-4 relative text-[11px] text-slate-400 italic">${dur((t - prev) / 60000)} with nothing recorded</li>`;
      const edge = it.kind === 'start' || it.kind === 'end';
      const color = edge ? gateColor(s.gate) : (TYPES[it.type] || {}).dot || '#64748b';
      html += `<li class="pl-4 relative"><span class="absolute -left-[7px] top-1.5 w-3 h-3 ${edge ? 'rounded-sm' : 'rounded-full'} border-2 border-white" style="background:${color}"></span>
        <div class="text-[11px] text-slate-400 font-mono">${it.at ? esc(fmtClock(it.at)) : 'now'}</div>
        <div class="text-xs ${edge ? 'font-bold text-slate-900' : 'text-slate-800'}">${esc(it.label)}</div></li>`;
      prev = t;
    });
    return `<ol class="relative border-l-2 border-slate-200 ml-2 space-y-3">${html}</ol>`;
  }

  async function openShift(id) {
    let res;
    try { res = await ApiClient.getShiftDetail(id); } catch (err) { SP.showToast(err.message, 'error'); return; }
    const s = res.shift;
    const counts = {};
    res.activity.forEach(a => { counts[a.type] = (counts[a.type] || 0) + 1; });
    const list = sortedShifts();
    const at = list.findIndex(x => String(x.id) === String(s.id));
    const newer = at > 0 ? list[at - 1] : null, older = at >= 0 && at < list.length - 1 ? list[at + 1] : null;
    const kinds = Object.keys(TYPES).filter(k => counts[k]);
    const html = `<div class="space-y-4 text-xs">
        <dl class="grid grid-cols-2 gap-3">
          ${factCell('Gate', esc(s.gate || '—'))}${factCell('Duration', dur(s.durationMinutes))}
          ${factCell('Went on duty', fmt(s.startedAt))}${factCell('Went off duty', s.endedAt ? fmt(s.endedAt) : 'Still on duty')}
          ${factCell('Actions', res.activity.length ? res.activity.length + (res.truncated ? '+' : '') : 'None')}${factCell('Guard', `<button type="button" data-open-guard="${s.userId}" class="text-ncst-navy underline cursor-pointer">${esc(person(s.guard).name)}</button>`)}
        </dl>
        <div><span class="px-2 py-0.5 rounded text-[11px] font-semibold border ${END_KIND[s.endKind].tone}">${END_KIND[s.endKind].label}</span></div>
        ${s.endKind === 'auto' ? '<div class="px-3 py-2 rounded-md bg-amber-50 border border-amber-200 text-amber-900">The guard never ended this shift, so the system closed it automatically. The real duration may be shorter.</div>' : ''}
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5">The whole shift</div>${shiftStrip(s, res.activity)}</div>
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1">Handover note</div>
          <div class="px-3 py-2 rounded-md bg-slate-50 border border-slate-200 text-slate-800 whitespace-pre-wrap">${s.handoverNotes ? esc(s.handoverNotes) : '<span class="text-slate-400">No note left.</span>'}</div></div>
        <div><div class="flex flex-wrap items-center gap-1.5 mb-3"><span class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mr-1">What they did</span>
            ${kinds.length ? `<button type="button" data-log-type="" aria-pressed="true" class="sh-logchip">All ${res.activity.length}</button>` : ''}
            ${kinds.map(k => `<button type="button" data-log-type="${k}" aria-pressed="false" class="sh-logchip ${TYPES[k].tone}">${counts[k]} ${counts[k] === 1 ? TYPES[k].one : TYPES[k].many}</button>`).join('')}</div>
          <div id="shLog">${shiftLog(s, res.activity, '')}</div>
          ${res.truncated ? '<p class="text-[11px] text-slate-500 mt-2">Showing the first 500 actions.</p>' : ''}
          ${res.activity.length ? '' : '<p class="text-[11px] text-slate-500 mt-2">Nothing was recorded under this guard\'s name during the shift.</p>'}</div>
      </div>`;
    const nav = (target, label, dir) => `<button type="button" data-shift-go="${target ? target.id : ''}" class="sp-btn sp-btn-secondary" ${target ? '' : 'disabled'} title="${target ? esc(person(target.guard).name + ' · ' + fmt(target.startedAt)) : 'No ' + dir + ' shift in this list'}">${label}</button>`;
    SP.openDrawer(person(s.guard).name, `${s.gate || 'No gate'} · ${fmt(s.startedAt)}`, html,
      `<div class="sp-foot"><div class="sp-foot-left">${nav(newer, '&#8249; Newer shift', 'newer')}${nav(older, 'Older shift &#8250;', 'older')}</div>
        <div class="sp-foot-right"><button type="button" data-open-guard="${s.userId}" class="sp-btn sp-btn-primary">Guard profile</button></div></div>`);
    $('drawerContent').querySelectorAll('[data-log-type]').forEach(b => b.addEventListener('click', () => {
      $('drawerContent').querySelectorAll('[data-log-type]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
      $('shLog').innerHTML = shiftLog(s, res.activity, b.dataset.logType);
    }));
    drawerLinks();
  }

  /** Buttons inside the drawer that jump to another shift or to a guard's profile. */
  function drawerLinks() {
    ['drawerContent', 'drawerFooter'].forEach(id => $(id).querySelectorAll('[data-shift-go],[data-open-guard],[data-guard-go],[data-shift]').forEach(b => {
      b.addEventListener('click', () => {
        if (b.dataset.shiftGo) openShift(b.dataset.shiftGo);
        else if (b.dataset.shift) openShift(b.dataset.shift);
        else if (b.dataset.openGuard) openGuard(Number(b.dataset.openGuard));
        else if (b.dataset.guardGo) openGuard(Number(b.dataset.guardGo));
      });
    }));
  }

  /* ---------------------------------------------------------------- one guard */
  function openGuard(userId) {
    const g = data.guards.find(x => x.userId === userId);
    if (!g) return;
    const rep = (data.report || []).find(x => x.userId === userId) || {};
    const mine = data.shifts.filter(x => x.userId === userId).sort((x, y) => ms(y.startedAt) - ms(x.startedAt));
    const hours = mine.reduce((n, x) => n + hoursInRange(x), 0);
    const actions = mine.reduce((n, x) => n + x.actions, 0);
    const start = Date.parse(`${data.from}T00:00:00${MANILA}`);
    const days = Math.max(1, Math.round((Date.parse(`${data.to}T23:59:59${MANILA}`) + 1000 - start) / DAY));
    const today = dayKey(0);

    let rows = '';
    for (let i = days - 1; i >= 0; i--) {
      const a = start + i * DAY, key = new Date(a).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
      const todays = mine.filter(x => ms(x.startedAt) < a + DAY && (x.endedAt ? ms(x.endedAt) : nowMs) > a);
      const dayHours = todays.reduce((n, x) => n + hoursOnDay(x, a), 0);
      const weekend = weekdayIndex(key) >= 5;
      const bars = todays.map(x => {
        const sa = Math.max(ms(x.startedAt), a), sb = Math.min(x.endedAt ? ms(x.endedAt) : nowMs, a + DAY);
        const tip = `${fmtTime(x.startedAt)} – ${x.endedAt ? fmtTime(x.endedAt) : 'now'} · ${x.gate || 'No gate'} · ${dur(x.durationMinutes)}`;
        const wide = (sb - sa) / DAY > 0.16;   // wide enough to write the times inside the bar
        return `<button type="button" data-shift="${x.id}" title="${esc(tip)}" aria-label="${esc(tip)}" class="sh-bar sh-seg" style="left:${(sa - a) / DAY * 100}%;width:${Math.max(0.8, (sb - sa) / DAY * 100)}%;top:7px;height:26px;border-radius:6px;background:${gateColor(x.gate)}">${wide ? `<span class="sh-seg-text">${esc(manila(sa, { hour: 'numeric', minute: '2-digit' }))} – ${x.endedAt || sb < a + DAY ? esc(manila(sb, { hour: 'numeric', minute: '2-digit' })) : 'midnight'}</span>` : ''}</button>`;
      }).join('');
      rows += `<div class="flex items-stretch border-t border-slate-100 ${key === today ? 'bg-ncst-navy/5' : weekend ? 'bg-slate-50' : ''}">
        <div class="w-28 flex-shrink-0 px-3 py-2 text-xs leading-tight"><div class="font-bold text-slate-800">${esc(manila(a, { weekday: 'short' }))}${key === today ? ' <span class="ml-1 px-1 rounded bg-rose-500 text-white text-[9px] font-bold align-middle">TODAY</span>' : ''}</div><div class="text-[11px] text-slate-500">${esc(manila(a, { month: 'short', day: 'numeric' }))}</div></div>
        <div class="relative flex-1 sh-grid" style="height:40px">${bars || '<span class="absolute inset-0 flex items-center pl-3 text-[11px] text-slate-300">no shift</span>'}</div>
        <div class="w-20 flex-shrink-0 flex items-center justify-end pr-3 text-xs ${dayHours ? 'font-bold text-slate-800' : 'text-slate-300'}">${dayHours ? dur(dayHours * 60) : '—'}</div></div>`;
    }
    const tile = (label, value, sub, warn) => `<div class="rounded-lg border ${warn ? 'border-amber-300 bg-amber-50' : 'border-slate-200 bg-white'} px-3 py-2"><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500">${label}</div><div class="text-lg font-extrabold text-slate-900">${value}</div>${sub ? `<div class="text-[10px] text-slate-500">${sub}</div>` : ''}</div>`;
    const html = `<div class="space-y-4 text-xs">
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          ${tile('Shifts', mine.length, mine.length ? `avg ${dur(hours * 60 / mine.length)}` : 'none in this period')}
          ${tile('Hours on duty', Math.round(hours * 10) / 10, esc(rangeLabel()))}
          ${tile('Actions', actions, 'during shifts')}
          ${tile('Scans with no shift', g.offShiftActions || 0, g.offShiftActions ? 'made while not on duty' : 'always on duty when scanning', !!g.offShiftActions)}
        </div>
        ${g.offShiftActions ? `<p class="px-3 py-2 rounded-md bg-amber-50 border border-amber-200 text-amber-900"><strong>${g.offShiftActions} scan${g.offShiftActions === 1 ? '' : 's'} with no shift.</strong> This guard recorded gate passages, violations or photos at a time when they had not gone on duty, so those actions belong to no shift. Ask them to tap Go on duty when they sign in.</p>` : ''}
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5">Day by day</div>
          <div class="rounded-lg border border-slate-200 overflow-hidden"><div ${days > 8 ? 'style="max-height:26rem;overflow-y:auto"' : ''}>
            <div class="sticky top-0 z-10 flex bg-white border-b border-slate-200"><div class="w-28 flex-shrink-0"></div><div class="relative flex-1 h-8">${hourAxis(true)}</div><div class="w-20 flex-shrink-0 flex items-center justify-end pr-3 text-[10px] font-bold uppercase tracking-wider text-slate-400">Hours</div></div>${rows}</div></div>
          <div class="flex flex-wrap gap-x-3 gap-y-1 text-[10px] text-slate-500 mt-1.5">${Object.keys(GATE_COLOR).map(k => `<span class="inline-flex items-center gap-1"><span class="w-2.5 h-2.5 rounded-sm" style="background:${GATE_COLOR[k]}"></span>${esc(gateShort(k))}</span>`).join('')}<span>Click a bar to open the shift.</span></div></div>
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5">What they handled</div>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
            ${tile('Entries', rep.entries || 0)}${tile('Exits', rep.exits || 0)}
            ${tile('Denied', rep.denials || 0, rep.denialRate ? rep.denialRate + '% of passages' : '', rep.denialRate >= 25)}
            ${tile('Manual lookups', rep.manualLookups || 0, rep.manualRate ? rep.manualRate + '% of passages' : '', rep.manualRate >= 25)}
            ${tile('Violations', rep.violationsIssued || 0)}${tile('Photos', rep.photos || 0)}</div></div>
        <div><div class="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5">Shifts (${mine.length})</div>
          ${mine.length ? `<ul class="rounded-lg border border-slate-200 divide-y divide-slate-100 overflow-hidden">${mine.map(x => `<li><button type="button" data-shift="${x.id}" class="w-full flex items-center gap-3 px-3 py-2 text-left hover:bg-slate-50 cursor-pointer">
              <span class="w-1 self-stretch rounded-full" style="background:${gateColor(x.gate)}"></span>
              <span class="flex-1 min-w-0"><span class="block font-semibold text-slate-800">${fmt(x.startedAt)}${x.endedAt ? ' – ' + esc(fmtTime(x.endedAt)) : ' · still on duty'}</span><span class="block text-[11px] text-slate-500">${esc(x.gate || 'No gate')} · ${x.actions} action${x.actions === 1 ? '' : 's'}</span></span>
              <span class="font-bold ${x.long ? 'text-rose-600' : 'text-slate-700'}">${dur(x.durationMinutes)}</span>
              <span class="px-2 py-0.5 rounded text-[10px] font-semibold border whitespace-nowrap ${END_KIND[x.endKind].tone}">${END_KIND[x.endKind].label}</span></button></li>`).join('')}</ul>` : '<p class="text-slate-500">No shifts in this period.</p>'}</div>
      </div>`;
    const order = data.guards.map(x => x.userId), i = order.indexOf(userId);
    const prev = i > 0 ? data.guards[i - 1] : null, next = i >= 0 && i < order.length - 1 ? data.guards[i + 1] : null;
    const nav = (target, label) => `<button type="button" data-guard-go="${target ? target.userId : ''}" class="sp-btn sp-btn-secondary" ${target ? '' : 'disabled'} title="${target ? esc(person(target.guard).name) : ''}">${label}</button>`;
    SP.openDrawer(person(g.guard).name, `${g.assignedGate ? gateShort(g.assignedGate) + ' · ' : ''}${person(g.guard).badge || 'Guard'} · ${rangeLabel()}`, html,
      `<div class="sp-foot"><div class="sp-foot-left">${nav(prev, '&#8249; Previous guard')}${nav(next, 'Next guard &#8250;')}</div></div>`);
    drawerLinks();
  }

  /* ---------------------------------------------------------------- export */
  function exportCsv() {
    if (!data) return;
    const cell = (v) => `"${String(v == null ? '' : v).replace(/"/g, '""')}"`;
    const head = ['Guard', 'Gate', 'Started', 'Ended', 'Hours', 'How it ended', 'Entries', 'Exits', 'Denied', 'Violations', 'Held vehicles', 'Photos', 'Visitor passes', 'Handover note'];
    const lines = [head.map(cell).join(',')].concat(sortedShifts().map(s => [s.guard, s.gate, s.startedAt, s.endedAt || '', (s.durationMinutes / 60).toFixed(2), END_KIND[s.endKind].label,
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
      if (preset) { range.preset = preset.dataset.preset; limit = PAGE; load(); return; }
      const step = e.target.closest('[data-step]');
      if (step) {
        // Move the whole period earlier or later by its own length (a day, a week, a month...)
        const n = daysBetween(range.from, range.to) + 1, dir = Number(step.dataset.step);
        let from = addDays(range.from, dir * n), to = addDays(range.to, dir * n);
        if (to > dayKey(0)) { to = dayKey(0); from = addDays(to, -(n - 1)); }
        range = { preset: 'custom', from, to };
        limit = PAGE;
        load();
        return;
      }
      const jump = e.target.closest('[data-jump]');
      if (jump) { const target = $(jump.dataset.jump); if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' }); return; }
      const day = e.target.closest('[data-day]');
      if (day) { range = { preset: 'custom', from: day.dataset.day, to: day.dataset.day }; mode = 'auto'; limit = PAGE; load(); return; }
      if (e.target.closest('#shApply')) {
        const from = $('shFrom').value, to = $('shTo').value;
        if (!from || !to) { SP.showToast('Choose both dates.', 'warning'); return; }
        range = { preset: 'custom', from, to };
        limit = PAGE;
        load();
        return;
      }
      const m = e.target.closest('[data-mode]');
      if (m) { mode = m.dataset.mode; renderResults(); return; }
      if (e.target.closest('#shClear')) {
        filter = { q: '', guard: '', gate: '', status: '' };
        limit = PAGE;
        $('shSearch').value = ''; $('shFilterGuard').value = ''; $('shFilterGate').value = ''; $('shFilterStatus').value = '';
        renderResults();
        return;
      }
      if (e.target.closest('#shMore')) { limit += PAGE; renderResults(); return; }
      const shift = e.target.closest('[data-shift]');
      if (shift) { openShift(shift.dataset.shift); return; }
      const guard = e.target.closest('[data-guard]');
      if (guard) openGuard(Number(guard.dataset.guard));
    });
    view.addEventListener('input', (e) => {
      if (e.target.id === 'shSearch') { filter.q = e.target.value; limit = PAGE; renderResults(); }
    });
    view.addEventListener('change', (e) => {
      const key = { shFilterGuard: 'guard', shFilterGate: 'gate', shFilterStatus: 'status' }[e.target.id];
      if (key) { filter[key] = e.target.value; limit = PAGE; renderResults(); }
    });
    $('shiftsRefreshBtn').addEventListener('click', load);
    $('shiftsExportBtn').addEventListener('click', exportCsv);
    window.addEventListener('resize', () => { if (data && $('shiftsView').classList.contains('active')) renderResults(); });
  }

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('shiftsView', $('navShiftsBtn'), () => {
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
