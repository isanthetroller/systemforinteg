/**
 * SecurePark - Overtime & Overnight Parking attention panel
 *
 * InfinityFree has no cron, so this panel runs the server check (POST overnight_check.php)
 * when a staff member signs in and every 10 minutes while the portal is open. The server
 * records at most one overnight strike per vehicle per night, so repeated runs are safe.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const INTERVAL_MS = 10 * 60 * 1000;
  const STRIKE_LIMIT = 3;
  let timer = null;
  let running = false;
  let report = null;

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  function formatTime(value) {
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }));
  }

  function telHref(phone) {
    const digits = String(phone || '').replace(/[^\d+]/g, '');
    return digits ? `tel:${digits}` : '';
  }

  function strikeLabel(item) {
    if (item.isBanned) return '<span class="px-1.5 py-0.5 rounded bg-ncst-crimson text-white text-[10px] font-extrabold">BANNED</span>';
    const n = Math.min(Number(item.warningCount || 0), STRIKE_LIMIT);
    const cls = n === 0 ? 'bg-slate-100 text-slate-600 border-slate-200' : 'bg-ncst-goldLight text-amber-950 border-ncst-gold/40';
    return `<span class="px-1.5 py-0.5 rounded border text-[10px] font-extrabold ${cls}">Strike ${n} of ${STRIKE_LIMIT}</span>`;
  }

  function render() {
    const list = $('overnightList');
    if (!list || !report) return;
    const items = report.items || [];
    const badge = $('overnightCountBadge');
    badge.textContent = items.length;
    badge.className = 'text-[10px] px-1.5 py-0.5 rounded font-bold border ' + (items.length
      ? 'bg-ncst-navy/10 text-ncst-navy border-ncst-navy/20' : 'bg-slate-100 text-slate-600 border-slate-200');
    $('overnightMeta').textContent = `Curfew ${report.curfew} · overtime after ${report.overtimeHours} h · checked ${formatTime(report.now).replace(/^.*?, /, '')}`;

    if (!items.length) {
      list.innerHTML = `
        <div class="px-4 py-5 text-center">
          <div class="text-xs font-bold text-slate-700">No overtime or overnight vehicles</div>
          <div class="text-[11px] text-slate-500 mt-0.5">Every vehicle inside campus is within the allowed time.</div>
        </div>`;
      return;
    }

    list.innerHTML = '';
    items.forEach(item => {
      const overnight = item.category === 'overnight';
      const row = document.createElement('div');
      row.className = `px-4 py-3 border-l-4 ${overnight ? 'border-l-ncst-navy bg-ncst-navy/5' : 'border-l-ncst-gold bg-ncst-goldLight/40'}`;
      const tel = telHref(item.ownerPhone);
      row.innerHTML = `
        <div class="flex flex-wrap items-center gap-2">
          <span class="px-2 py-0.5 rounded bg-slate-900 text-ncst-gold font-mono font-extrabold text-xs tracking-wider">${esc(item.plateNumber)}</span>
          <span class="px-1.5 py-0.5 rounded text-[10px] font-extrabold ${overnight ? 'bg-ncst-navy text-white' : 'bg-ncst-gold text-slate-900'}">${overnight ? 'OVERNIGHT' : 'OVERTIME'}</span>
          ${strikeLabel(item)}
          <span class="ml-auto text-[11px] font-bold ${overnight ? 'text-ncst-navy' : 'text-amber-950'}">${esc(item.elapsedHours)} h inside</span>
        </div>
        <div class="mt-1.5 grid grid-cols-1 sm:grid-cols-3 gap-x-4 gap-y-0.5 text-[11px] text-slate-600">
          <div class="truncate">Owner: <span class="font-semibold text-slate-800">${esc(item.ownerName)}</span></div>
          <div class="truncate">Contact: <span class="font-mono font-semibold text-slate-800">${esc(item.ownerPhone || 'none on file')}</span></div>
          <div class="truncate">Entered: <span class="font-semibold text-slate-800">${formatTime(item.entryTime)}</span></div>
        </div>
        <div class="mt-2 flex flex-wrap items-center gap-1.5">
          ${item.ownerPhone ? '<button type="button" data-act="copy" class="px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-50 text-[11px] font-semibold text-slate-700 cursor-pointer">Copy Number</button>' : ''}
          ${tel ? `<a href="${esc(tel)}" class="px-2.5 py-1 rounded border border-ncst-green/30 bg-ncst-greenLight hover:bg-ncst-greenLight/80 text-[11px] font-semibold text-ncst-greenDark">Call Owner</a>` : ''}
          ${item.flaggedThisNight
            ? `<span class="ml-auto text-[11px] font-semibold text-slate-500">Strike recorded ${formatTime(item.flaggedAt)}</span>`
            : '<button type="button" data-act="flag" class="ml-auto px-2.5 py-1 rounded bg-ncst-crimson hover:bg-ncst-crimsonDark text-white text-[11px] font-bold cursor-pointer disabled:opacity-50">Flag Overnight Strike</button>'}
        </div>`;

      const copyBtn = row.querySelector('[data-act="copy"]');
      if (copyBtn) copyBtn.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(item.ownerPhone);
          SP.showToast(`Copied ${item.ownerPhone}`);
        } catch (_) {
          SP.showToast('Copy failed. Select the number and copy it manually.');
        }
      });
      const flagBtn = row.querySelector('[data-act="flag"]');
      if (flagBtn) flagBtn.addEventListener('click', () => flag(item, flagBtn));
      list.appendChild(row);
    });
  }

  async function flag(item, btn) {
    const next = Number(item.warningCount || 0) + 1;
    const willBan = !item.isBanned && next >= STRIKE_LIMIT;
    const confirmed = window.SPAlert
      ? await SPAlert.confirm({
          title: 'Record Overnight Strike?',
          text: `Record an overnight / overtime strike for ${item.plateNumber}?` +
                (willBan ? ` WARNING: This is strike ${next} of ${STRIKE_LIMIT} — ${item.plateNumber} will be automatically BANNED from campus.` : ` (Strike ${next} of ${STRIKE_LIMIT})`),
          confirmText: willBan ? 'Issue Strike & Ban' : 'Record Strike',
          icon: willBan ? 'error' : 'warning',
          isDanger: willBan,
          isWarning: !willBan
        })
      : confirm(`Record an overnight / overtime strike for ${item.plateNumber}?${!item.isBanned && next >= STRIKE_LIMIT ? `\n\nThis is strike ${next} of ${STRIKE_LIMIT}: the vehicle will be BANNED.` : ''}`);
    if (!confirmed) return;
    btn.disabled = true;
    try {
      const res = await ApiClient.flagOvernight(item.vehicleId);
      report = res.report;
      render();
      SP.showToast(res.message, willBan ? 'error' : 'warning');
      if (SP.reload) SP.reload();
    } catch (err) {
      SP.showToast(err.message, 'error');
      btn.disabled = false;
    }
  }

  async function run(showToast = false) {
    if (running) return;
    running = true;
    const btn = $('overnightRunBtn');
    if (btn) btn.disabled = true;
    try {
      const res = await ApiClient.runOvernightCheck();
      report = res;
      render();
      if (res.flagged && res.flagged.length) {
        const banned = res.flagged.filter(f => f.banned).map(f => f.plateNumber);
        SP.showToast(`${res.flagged.length} overnight strike(s) recorded.` + (banned.length ? ` BANNED: ${banned.join(', ')}.` : ''));
        if (SP.reload) SP.reload();
      } else if (showToast) {
        SP.showToast('Overnight check complete. No new strikes.');
      }
    } catch (err) {
      if (err.status !== 401 && $('overnightList')) {
        $('overnightList').innerHTML = `<div class="px-4 py-4 text-center text-xs text-ncst-crimson">${esc(err.message)}</div>`;
      }
    } finally {
      running = false;
      if (btn) btn.disabled = false;
    }
  }

  document.addEventListener('sp:app-ready', () => {
    $('overnightRunBtn').addEventListener('click', () => run(true));
    SPAuth.whenAuthenticated(() => {
      run();
      if (timer) clearInterval(timer);
      timer = setInterval(() => run(), INTERVAL_MS);
    });
  });
})();
