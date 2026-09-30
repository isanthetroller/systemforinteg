/**
 * SecurePark - Single-Day Visitor Passes
 *
 *   SPVisitors.openCreate({ plate })   open the "New Day Pass" form (used by the Gate Monitor)
 *
 * A pass is valid all day on its date. Guards issue passes for today; an admin can pick a later day.
 * The server validates the date and signs the QR (type visitor_temp).
 * The card is screenshot-ready and can also be downloaded as a PNG / shared.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const state = { passes: [], current: null, upcoming: false };
  const MAX_ADVANCE_DAYS = 60;

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));
  const isAdmin = () => !!(window.SPAuth && SPAuth.hasRole('admin'));

  function manilaToday() {
    const p = {};
    new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit' })
      .formatToParts(new Date()).forEach(x => { p[x.type] = x.value; });
    return `${p.year}-${p.month}-${p.day}`;
  }

  function addDays(ymd, n) {
    const d = new Date(`${ymd}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
  }

  function longDate(ymd) {
    const d = new Date(`${ymd}T12:00:00+08:00`);
    return d.toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
  }

  function formatTime(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    return isNaN(d) ? esc(value) : esc(d.toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit' }));
  }

  function statusBadge(p) {
    let label = p.status, cls = 'bg-slate-100 text-slate-600 border-slate-200';
    if (p.status === 'Active' && p.isInside) { label = 'Inside'; cls = 'bg-ncst-greenLight text-ncst-greenDark border-ncst-green/30'; }
    else if (p.status === 'Active' && p.validDate > manilaToday()) { label = 'Upcoming'; cls = 'bg-ncst-goldLight text-amber-950 border-ncst-gold/40'; }
    else if (p.status === 'Revoked' && p.isInside) { label = 'Revoked (inside)'; cls = 'bg-ncst-crimson text-white border-ncst-crimson'; }
    else if (p.status === 'Active') { label = 'Active'; cls = 'bg-ncst-navy/10 text-ncst-navy border-ncst-navy/20'; }
    else if (p.status === 'Revoked') {
      // A pass is revoked automatically when the visitor exits (single use)
      if (p.exitTime) label = 'Revoked (checked out)';
      cls = 'bg-ncst-crimsonLight text-ncst-crimson border-ncst-crimson/30';
    }
    else if (p.status === 'Expired') cls = 'bg-ncst-goldLight text-amber-950 border-ncst-gold/40';
    return `<span class="px-1.5 py-0.5 rounded border text-[10px] font-bold ${cls}">${esc(label)}</span>`;
  }

  // A pass a guard issued on a phone without a connection: show when it reached the server
  function offlineChip(p) {
    if (!p.syncedAt || !p.createdAt) return '';
    const issued = Date.parse(String(p.createdAt).replace(' ', 'T') + '+08:00');
    const synced = Date.parse(String(p.syncedAt).replace(' ', 'T') + '+08:00');
    if (isNaN(issued) || isNaN(synced) || synced - issued < 120000) return '';
    return `<div class="mt-0.5"><span class="inline-block px-1.5 py-0.5 rounded bg-ncst-navy/10 text-ncst-navy border border-ncst-navy/20 text-[9px] font-bold tracking-wide" title="Issued offline at the gate; reached the server at ${esc(p.syncedAt)}">ISSUED OFFLINE &middot; synced ${formatTime(p.syncedAt)}</span></div>`;
  }

  function itemsInline(items, max = 3) {
    if (!items || !items.length) return '<span class="text-slate-400">—</span>';
    const shown = items.slice(0, max).map(i => `<span class="inline-block px-1.5 py-0.5 mr-1 mb-1 rounded bg-ncst-navy/5 border border-ncst-navy/20 text-ncst-navy text-[10px] font-semibold">${esc(i.quantity)}&times; ${esc(i.name)}</span>`).join('');
    return shown + (items.length > max ? `<span class="text-[10px] text-slate-500">+${items.length - max} more</span>` : '');
  }

  function addItemRow(item = {}) {
    const rows = $('vpItems');
    if (rows.children.length >= 20) return SP.showToast('A day pass can list at most 20 items.');
    const row = document.createElement('div');
    row.className = 'vp-item grid grid-cols-12 gap-1.5 items-center';
    const n = rows.children.length + 1;
    row.innerHTML = `
      <input type="text" maxlength="100" aria-label="Item ${n} name" placeholder="Item (e.g. Monobloc chairs)" class="vp-item-name col-span-5 px-2 py-1.5 rounded border border-slate-300 bg-white text-xs">
      <input type="number" min="1" max="9999" step="1" value="1" aria-label="Item ${n} quantity" class="vp-item-qty col-span-2 px-2 py-1.5 rounded border border-slate-300 bg-white text-xs text-right">
      <input type="text" maxlength="255" aria-label="Item ${n} note" placeholder="Note (optional)" class="vp-item-desc col-span-4 px-2 py-1.5 rounded border border-slate-300 bg-white text-xs">
      <button type="button" aria-label="Remove item ${n}" class="col-span-1 h-7 rounded text-slate-400 hover:text-ncst-crimson hover:bg-ncst-crimsonLight text-base leading-none cursor-pointer">&times;</button>`;
    row.querySelector('.vp-item-name').value = item.name || '';
    if (item.quantity) row.querySelector('.vp-item-qty').value = item.quantity;
    row.querySelector('.vp-item-desc').value = item.description || '';
    row.querySelector('button').addEventListener('click', () => row.remove());
    rows.appendChild(row);
    row.querySelector('.vp-item-name').focus();
  }

  function readItems() {
    return [...document.querySelectorAll('#vpItems .vp-item')].map(r => ({
      name: r.querySelector('.vp-item-name').value.trim(),
      quantity: Number(r.querySelector('.vp-item-qty').value || 0),
      description: r.querySelector('.vp-item-desc').value.trim()
    })).filter(i => i.name || i.description);
  }

  function showModal(id) { $(id).classList.remove('hidden'); $(id).classList.add('flex'); }
  function hideModal(id) { $(id).classList.add('hidden'); $(id).classList.remove('flex'); }

  /* ------------------------------------------------------------------------
     List
     ------------------------------------------------------------------------ */
  async function load() {
    const body = $('visitorsTableBody');
    if (!$('visitorsDate').value) $('visitorsDate').value = manilaToday();
    const upBtn = $('visitorsUpcomingBtn');
    upBtn.setAttribute('aria-pressed', String(state.upcoming));
    upBtn.className = `px-3 py-1.5 rounded-md border text-xs font-semibold cursor-pointer ${state.upcoming ? 'border-ncst-navy bg-ncst-navy text-white' : 'border-slate-300 bg-white hover:bg-slate-50 text-slate-700'}`;
    try {
      state.passes = state.upcoming
        ? await ApiClient.getVisitorPasses('', true)
        : await ApiClient.getVisitorPasses($('visitorsDate').value);
      render();
    } catch (err) {
      body.innerHTML = `<tr><td colspan="8" class="px-4 py-6 text-center text-ncst-crimson">${esc(err.message)}</td></tr>`;
    }
  }

  function render() {
    const body = $('visitorsTableBody');
    if (!state.passes.length) {
      body.innerHTML = `<tr><td colspan="8" class="px-4 py-6 text-center text-slate-400">${state.upcoming ? 'No upcoming passes are scheduled.' : 'No visitor passes for this day.'}</td></tr>`;
      return;
    }
    body.innerHTML = '';
    state.passes.forEach(p => {
      const tr = document.createElement('tr');
      tr.className = 'align-top hover:bg-slate-50/60';
      const canRevoke = isAdmin() && p.status === 'Active';
      tr.innerHTML = `
        <td class="px-4 py-2.5">
          <div class="font-mono font-bold text-slate-900 whitespace-nowrap">${esc(p.passCode)}</div>
          <div class="text-[10px] text-slate-400">Valid ${esc(p.validDate)}</div>
          ${offlineChip(p)}
        </td>
        <td class="px-4 py-2.5">
          <div class="font-semibold text-slate-800">${esc(p.visitorName)}</div>
          <div class="text-[10px] text-slate-500 font-mono">${esc(p.contactNumber)}</div>
        </td>
        <td class="px-4 py-2.5">
          <div class="font-mono font-bold text-slate-900 whitespace-nowrap">${esc(p.plateNumber)}</div>
          <div class="text-[10px] text-slate-500">${esc(p.vehicleModel || '')}</div>
        </td>
        <td class="px-4 py-2.5">
          <div class="font-semibold text-slate-800">${esc(p.personToVisit)}</div>
          <div class="text-[10px] text-slate-500">${esc(p.purposeOfVisit)}</div>
        </td>
        <td class="px-4 py-2.5 max-w-[220px]">${itemsInline(p.items)}</td>
        <td class="px-4 py-2.5">${statusBadge(p)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap text-slate-600">${formatTime(p.entryTime)} / ${formatTime(p.exitTime)}</td>
        <td class="px-4 py-2.5">
          <div class="flex justify-end gap-1.5">
            <button type="button" data-act="card" class="px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-50 text-[11px] font-semibold text-slate-700 cursor-pointer">View Pass</button>
            ${canRevoke ? '<button type="button" data-act="revoke" class="px-2.5 py-1 rounded border border-ncst-crimson/30 bg-ncst-crimsonLight hover:bg-ncst-crimson/10 text-[11px] font-semibold text-ncst-crimson cursor-pointer">Revoke</button>' : ''}
          </div>
        </td>`;
      tr.querySelector('[data-act="card"]').addEventListener('click', () => openCard(p));
      const revokeBtn = tr.querySelector('[data-act="revoke"]');
      if (revokeBtn) revokeBtn.addEventListener('click', () => revoke(p));
      body.appendChild(tr);
    });
  }

  async function revoke(p) {
    const confirmed = window.SPAlert
      ? await SPAlert.confirm({
          title: 'Revoke Day Pass?',
          text: p.isInside
            ? `${p.visitorName} (${p.plateNumber}) is on campus now. Revoking pass ${p.passCode} opens a security hold, but the visitor is still allowed to leave. Continue?`
            : `Revoke day pass ${p.passCode} for ${p.visitorName} (${p.plateNumber})? The QR code will be rejected immediately at the gate.`,
          confirmText: 'Revoke Pass',
          icon: 'warning',
          isDanger: true
        })
      : confirm(`Revoke day pass ${p.passCode} for ${p.visitorName} (${p.plateNumber})?\n\nThe QR will be rejected at the gate.`);
    if (!confirmed) return;
    try {
      const res = await ApiClient.revokeVisitorPass(p.id);
      SP.showToast(res.message, 'success');
      load();
    } catch (err) {
      SP.showToast(err.message, 'error');
    }
  }

  /* ------------------------------------------------------------------------
     Create
     ------------------------------------------------------------------------ */
  function openCreate(prefill = {}) {
    ['vpName', 'vpContact', 'vpPlate', 'vpModel', 'vpHost', 'vpPurpose'].forEach(id => { $(id).value = ''; });
    $('vpItems').innerHTML = '';
    if (prefill.plate) $('vpPlate').value = String(prefill.plate).toUpperCase();
    const today = manilaToday();
    const dateWrap = $('vpDateWrap');
    dateWrap.classList.toggle('hidden', !isAdmin());
    $('vpDate').min = today;
    $('vpDate').max = addDays(today, MAX_ADVANCE_DAYS);
    $('vpDate').value = prefill.date || today;
    $('visitorModalDate').textContent = isAdmin()
      ? 'Valid all day on the day you choose (default: today).'
      : `Valid all day today: ${longDate(today)}.`;
    $('visitorFormError').classList.add('hidden');
    showModal('visitorModal');
    setTimeout(() => $('vpName').focus(), 50);
  }

  async function submitCreate(e) {
    e.preventDefault();
    const payload = {
      visitor_name: $('vpName').value.trim(),
      contact_number: $('vpContact').value.trim(),
      plate: $('vpPlate').value.trim(),
      vehicle_model: $('vpModel').value.trim(),
      person_to_visit: $('vpHost').value.trim(),
      purpose: $('vpPurpose').value.trim(),
      items: readItems()
    };
    if (isAdmin() && $('vpDate').value) payload.valid_date = $('vpDate').value;
    const err = $('visitorFormError');
    $('visitorSubmitBtn').disabled = true;
    try {
      const res = await ApiClient.createVisitorPass(payload);
      hideModal('visitorModal');
      SP.showToast(res.message);
      openCard(res.pass);
      if ($('visitorsView').classList.contains('active')) load();
    } catch (e2) {
      err.textContent = e2.message;
      err.classList.remove('hidden');
    } finally {
      $('visitorSubmitBtn').disabled = false;
    }
  }

  /* ------------------------------------------------------------------------
     Pass card (HTML for screenshots, canvas for PNG download)
     ------------------------------------------------------------------------ */
  function openCard(p) {
    state.current = p;
    const expired = p.validDate < manilaToday() || p.status !== 'Active';
    const upcoming = p.status === 'Active' && p.validDate > manilaToday();
    $('visitorCard').innerHTML = `
      <div class="bg-ncst-navy px-5 pt-4 pb-3 text-white border-b-4 border-ncst-gold">
        <div class="flex items-center gap-3">
          <div class="w-11 h-11 rounded-full bg-ncst-gold text-ncst-navy font-extrabold text-xs flex items-center justify-center border-2 border-white/70 flex-shrink-0">NCST</div>
          <div class="min-w-0">
            <div class="text-[11px] font-bold leading-tight">National College of Science and Technology</div>
            <div class="text-[10px] text-white/80">SecurePark &middot; Campus Security Office</div>
          </div>
        </div>
        <div class="mt-3 text-center text-sm font-extrabold tracking-[0.18em]">VISITOR DAY PASS</div>
      </div>
      <div class="px-4 pt-3">
        <div class="rounded-lg ${expired ? 'bg-slate-200 text-slate-600' : 'bg-ncst-gold text-slate-900'} text-center py-2.5 px-2">
          <div class="text-[10px] font-bold tracking-widest">${upcoming ? 'ACTIVATES ON (VALID ALL DAY):' : 'VALID ALL DAY ON:'}</div>
          <div class="text-2xl font-extrabold font-mono leading-tight">${esc(p.validDate)}</div>
          <div class="text-[10px] font-semibold">${esc(longDate(p.validDate))}</div>
        </div>
      </div>
      <div class="relative flex justify-center py-4">
        <div id="visitorCardQr" class="w-[220px] h-[220px] p-2 bg-white border border-slate-200 rounded-lg"></div>
        ${p.status !== 'Active' ? `<div class="absolute inset-0 flex items-center justify-center"><span class="px-3 py-1 rounded bg-ncst-crimson text-white text-sm font-extrabold -rotate-12">${esc(p.status.toUpperCase())}</span></div>` : ''}
      </div>
      <div class="text-center font-mono text-xs font-bold text-slate-700 -mt-2">${esc(p.passCode)}</div>
      <dl class="px-5 py-3 grid grid-cols-3 gap-y-1.5 text-[11px]">
        <dt class="text-slate-500">Visitor</dt><dd class="col-span-2 font-bold text-slate-900">${esc(p.visitorName)}</dd>
        <dt class="text-slate-500">Plate</dt><dd class="col-span-2 font-mono font-extrabold text-slate-900">${esc(p.plateNumber)}${p.vehicleModel ? ` <span class="font-sans font-normal text-slate-500">&middot; ${esc(p.vehicleModel)}</span>` : ''}</dd>
        <dt class="text-slate-500">Visiting</dt><dd class="col-span-2 font-semibold text-slate-800">${esc(p.personToVisit)}</dd>
        <dt class="text-slate-500">Purpose</dt><dd class="col-span-2 text-slate-700">${esc(p.purposeOfVisit)}</dd>
      </dl>
      ${p.items && p.items.length ? `
      <div class="mx-5 mb-3 rounded-lg border border-ncst-navy/20 bg-ncst-navy/5 px-3 py-2">
        <div class="text-[10px] font-extrabold tracking-wider text-ncst-navy">ITEMS BROUGHT IN (${p.items.length})</div>
        <ul class="mt-1 space-y-0.5 text-[11px] text-slate-800">
          ${p.items.map(i => `<li class="flex gap-2"><span class="font-mono font-bold w-10 text-right flex-shrink-0">${esc(i.quantity)}&times;</span><span><span class="font-semibold">${esc(i.name)}</span>${i.description ? ` <span class="text-slate-500">(${esc(i.description)})</span>` : ''}</span></li>`).join('')}
        </ul>
        <div class="mt-1 text-[10px] text-slate-600">Checked by the guard on entry and exit.</div>
      </div>` : ''}
      <div class="bg-slate-50 border-t border-slate-200 px-5 py-2.5 text-[10px] text-slate-500 leading-snug">
        Present this QR at the gate on entry and exit. Valid all day on the date shown; not valid on any other date. Questions: NCST Campus Security Office.
      </div>`;

    const qrBox = $('visitorCardQr');
    if (typeof QRCode !== 'undefined') {
      new QRCode(qrBox, { text: p.qrPayload, width: 204, height: 204, colorDark: '#0F172A', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    }
    const canShare = !!(navigator.canShare && window.File && navigator.canShare({ files: [new File([''], 'x.png', { type: 'image/png' })] }));
    $('visitorCardShareBtn').classList.toggle('hidden', !canShare);
    showModal('visitorCardModal');
  }

  function wrapText(ctx, text, x, y, maxWidth, lineHeight, maxLines = 2) {
    const words = String(text || '').split(/\s+/);
    let line = '';
    let lines = 0;
    for (let i = 0; i < words.length; i++) {
      const test = line ? `${line} ${words[i]}` : words[i];
      if (ctx.measureText(test).width > maxWidth && line) {
        if (lines === maxLines - 1) { ctx.fillText(line + '…', x, y); return y + lineHeight; }
        ctx.fillText(line, x, y);
        line = words[i];
        y += lineHeight;
        lines++;
      } else {
        line = test;
      }
    }
    ctx.fillText(line, x, y);
    return y + lineHeight;
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  // 2x-resolution PNG of the card (720 x 1280), drawn directly on a canvas
  function renderCardPng() {
    const p = state.current;
    const qrCanvas = $('visitorCardQr').querySelector('canvas');
    const items = p.items || [];
    const itemsBlock = items.length ? 70 + items.length * 32 : 0;
    // Drawn on a tall canvas, then cropped to the real content height
    const W = 720, H = 1600 + itemsBlock;
    const c = document.createElement('canvas');
    c.width = W; c.height = H;
    const ctx = c.getContext('2d');
    const sans = '"Plus Jakarta Sans", system-ui, sans-serif';
    const mono = '"JetBrains Mono", ui-monospace, monospace';
    const expired = p.validDate < manilaToday() || p.status !== 'Active';

    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, W, H);
    // Header
    ctx.fillStyle = '#1B3676'; ctx.fillRect(0, 0, W, 230);
    ctx.fillStyle = '#F5B800'; ctx.fillRect(0, 222, W, 8);
    ctx.beginPath(); ctx.arc(90, 90, 46, 0, Math.PI * 2); ctx.fillStyle = '#F5B800'; ctx.fill();
    ctx.fillStyle = '#1B3676'; ctx.font = `800 24px ${sans}`; ctx.textAlign = 'center'; ctx.fillText('NCST', 90, 99);
    ctx.textAlign = 'left'; ctx.fillStyle = '#ffffff'; ctx.font = `700 24px ${sans}`;
    ctx.fillText('National College of Science', 160, 80);
    ctx.fillText('and Technology', 160, 110);
    ctx.fillStyle = '#E2E8F0'; ctx.font = `500 20px ${sans}`; ctx.fillText('SecurePark · Campus Security Office', 160, 142);
    ctx.fillStyle = '#ffffff'; ctx.font = `800 34px ${sans}`; ctx.textAlign = 'center'; ctx.fillText('V I S I T O R   D A Y   P A S S', W / 2, 200);

    // Validity banner
    roundRect(ctx, 40, 260, W - 80, 150, 18); ctx.fillStyle = expired ? '#E2E8F0' : '#F5B800'; ctx.fill();
    ctx.fillStyle = '#0F172A'; ctx.font = `700 22px ${sans}`; ctx.fillText('VALID ONLY ON:', W / 2, 300);
    ctx.font = `800 60px ${mono}`; ctx.fillText(p.validDate, W / 2, 362);
    ctx.font = `600 22px ${sans}`; ctx.fillText(longDate(p.validDate), W / 2, 395);

    // QR
    roundRect(ctx, (W - 460) / 2, 440, 460, 460, 16); ctx.fillStyle = '#ffffff'; ctx.fill();
    ctx.strokeStyle = '#CBD5E1'; ctx.lineWidth = 2; ctx.stroke();
    if (qrCanvas) { ctx.imageSmoothingEnabled = false; ctx.drawImage(qrCanvas, (W - 420) / 2, 460, 420, 420); }
    if (p.status !== 'Active') {
      ctx.save(); ctx.translate(W / 2, 670); ctx.rotate(-0.2);
      ctx.fillStyle = '#D62828'; ctx.fillRect(-160, -40, 320, 80);
      ctx.fillStyle = '#ffffff'; ctx.font = `800 44px ${sans}`; ctx.fillText(p.status.toUpperCase(), 0, 16); ctx.restore();
    }
    ctx.fillStyle = '#334155'; ctx.font = `700 26px ${mono}`; ctx.fillText(p.passCode, W / 2, 940);

    // Details
    ctx.textAlign = 'left';
    const rows = [['Visitor', p.visitorName], ['Plate', p.plateNumber + (p.vehicleModel ? ` · ${p.vehicleModel}` : '')], ['Visiting', p.personToVisit], ['Purpose', p.purposeOfVisit]];
    let y = 1000;
    rows.forEach(([label, value]) => {
      ctx.fillStyle = '#64748B'; ctx.font = `500 22px ${sans}`; ctx.fillText(label, 60, y);
      ctx.fillStyle = '#0F172A'; ctx.font = `700 24px ${label === 'Plate' ? mono : sans}`;
      y = wrapText(ctx, value, 210, y, W - 270, 30, 2) + 8;
    });

    // Items brought in
    let contentEnd = y;
    if (items.length) {
      const top = y + 6;
      contentEnd = top + itemsBlock - 16;
      roundRect(ctx, 40, top, W - 80, itemsBlock - 16, 14); ctx.fillStyle = '#F8FAFC'; ctx.fill();
      ctx.strokeStyle = '#CBD5E1'; ctx.lineWidth = 2; ctx.stroke();
      ctx.fillStyle = '#1B3676'; ctx.font = `800 20px ${sans}`; ctx.textAlign = 'left';
      ctx.fillText(`ITEMS BROUGHT IN (${items.length})`, 64, top + 36);
      items.forEach((it, idx) => {
        const iy = top + 72 + idx * 32;
        ctx.fillStyle = '#0F172A'; ctx.font = `800 22px ${mono}`; ctx.textAlign = 'right';
        ctx.fillText(`${it.quantity}×`, 150, iy);
        ctx.textAlign = 'left'; ctx.font = `600 22px ${sans}`;
        const label = it.description ? `${it.name} (${it.description})` : it.name;
        ctx.fillText(label.length > 44 ? label.slice(0, 43) + '…' : label, 166, iy);
      });
    }

    // Footer right below the content (at least the classic 1280 px card height)
    const finalH = Math.max(1280, contentEnd + 130);
    ctx.fillStyle = '#F1F5F9'; ctx.fillRect(0, finalH - 90, W, 90);
    ctx.fillStyle = '#64748B'; ctx.font = `500 19px ${sans}`; ctx.textAlign = 'center';
    ctx.fillText('Present this QR at the gate on entry and exit.', W / 2, finalH - 52);
    ctx.fillText('Not valid on any other date. NCST Campus Security Office.', W / 2, finalH - 24);

    const out = document.createElement('canvas');
    out.width = W; out.height = finalH;
    out.getContext('2d').drawImage(c, 0, 0, W, finalH, 0, 0, W, finalH);
    return out;
  }

  function cardBlob() {
    return new Promise(resolve => renderCardPng().toBlob(resolve, 'image/png'));
  }

  async function download() {
    const blob = await cardBlob();
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${state.current.passCode}.png`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }

  async function share() {
    try {
      const blob = await cardBlob();
      const file = new File([blob], `${state.current.passCode}.png`, { type: 'image/png' });
      await navigator.share({ files: [file], title: 'NCST Visitor Day Pass', text: `Valid only on ${state.current.validDate}` });
    } catch (err) {
      if (err && err.name !== 'AbortError') SP.showToast('Sharing failed. Use Download PNG instead.');
    }
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  document.addEventListener('sp:app-ready', () => {
    SP.registerView('visitorsView', $('navVisitorsBtn'), load);
    $('visitorsNewBtn').addEventListener('click', () => openCreate());
    $('visitorsDate').addEventListener('change', () => { state.upcoming = false; load(); });
    $('visitorsUpcomingBtn').addEventListener('click', () => { state.upcoming = !state.upcoming; load(); });
    $('visitorForm').addEventListener('submit', submitCreate);
    $('vpAddItemBtn').addEventListener('click', () => addItemRow());
    $('visitorCancelBtn').addEventListener('click', () => hideModal('visitorModal'));
    $('vpPlate').addEventListener('input', (e) => { e.target.value = e.target.value.toUpperCase(); });
    $('visitorCardCloseBtn').addEventListener('click', () => hideModal('visitorCardModal'));
    $('visitorCardDownloadBtn').addEventListener('click', download);
    $('visitorCardShareBtn').addEventListener('click', share);
  });

  window.SPVisitors = { openCreate, openCard };
})();
