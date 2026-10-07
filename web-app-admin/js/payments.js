/**
 * SecurePark - Cashier (admin only)
 *
 * Registration-fee queue: vehicles waiting for payment, cash receiving with change and a printable
 * receipt, and the payment history (cash + online PayMongo). All rules live on the server
 * (lib/payments.php): paying is what activates a vehicle's QR pass.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));
  const peso = (n) => '₱' + Number(n || 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  let tab = 'awaiting';
  let unpaid = [];
  let history = [];
  let summary = null;
  let searchTimer = null;
  let loading = 0;

  function formatDate(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }));
  }

  function methodLabel(p) {
    if (p.method === 'Cash') return 'Cash';
    const via = p.providerMethod ? ` (${p.providerMethod === 'test' ? 'test' : p.providerMethod})` : '';
    return 'Online' + esc(via);
  }

  function statusBadge(p) {
    const dup = p.notes && /^DUPLICATE/.test(p.notes);
    if (dup) return '<span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-rose-50 text-rose-700 border border-rose-200" title="' + esc(p.notes) + '">Paid twice – refund</span>';
    if (p.status === 'Paid') return '<span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200/80">Paid</span>';
    if (p.status === 'Pending') return '<span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-200">Awaiting checkout</span>';
    return '<span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-slate-100 text-slate-600 border border-slate-200">' + esc(p.status) + '</span>';
  }

  /* ------------------------------------------------------------------------
     Loading + rendering
     ------------------------------------------------------------------------ */
  function setSidebarCount(n) {
    const badge = $('cashierSidebarCount');
    if (!badge) return;
    badge.textContent = n;
    badge.classList.toggle('hidden', !n);
  }

  async function refreshCount() {
    if (!window.SPAuth || !SPAuth.hasRole('admin')) return;
    try {
      const data = await ApiClient.getPayments({});
      summary = data.summary;
      setSidebarCount(summary.unpaidCount);
    } catch (_) { /* the sidebar badge is a convenience */ }
  }

  async function load() {
    const ticket = ++loading;
    const q = ($('cashierSearch').value || '').trim();
    try {
      const [queue, hist] = await Promise.all([
        ApiClient.getUnpaidVehicles(),
        ApiClient.getPayments({ q }),
      ]);
      if (ticket !== loading) return;
      // Something left the queue (e.g. an owner paid online): the vehicle directory must follow
      if (unpaid.length > queue.length && window.SP && SP.reload) SP.reload(true, true);
      unpaid = queue;
      history = hist.payments;
      summary = hist.summary;
      setSidebarCount(summary.unpaidCount);
      render();
    } catch (err) {
      const msg = esc(err.message);
      $('cashierAwaitingBody').innerHTML = `<tr><td colspan="7" class="px-4 py-6 text-center text-ncst-crimson">${msg}</td></tr>`;
    }
  }

  function renderSummary() {
    if (!summary) return;
    $('cashStatAwaiting').textContent = summary.unpaidCount;
    $('cashStatAwaitingAmt').textContent = peso(summary.unpaidTotal) + ' to collect';
    $('cashStatToday').textContent = peso(summary.collectedToday);
    $('cashStatCash').textContent = peso(summary.cashToday.total);
    $('cashStatCashN').textContent = summary.cashToday.count + ' payment' + (summary.cashToday.count === 1 ? '' : 's');
    $('cashStatOnline').textContent = peso(summary.onlineToday.total);
    $('cashStatOnlineN').textContent = summary.onlineToday.count + ' payment' + (summary.onlineToday.count === 1 ? '' : 's');
    const note = $('cashierGatewayNote');
    if (summary.onlineMock) {
      note.textContent = 'Online payments use the built-in TEST checkout on this server (no PayMongo key configured). No real money moves.';
      note.className = 'text-[11px] px-3 py-2 rounded-md bg-amber-50 text-amber-800 border border-amber-200';
    } else if (!summary.onlineAvailable) {
      note.textContent = 'Online payment is not set up yet (PayMongo keys missing). Owners can only pay at this cashier.';
      note.className = 'text-[11px] px-3 py-2 rounded-md bg-slate-100 text-slate-700 border border-slate-200';
    } else {
      note.className = 'hidden';
    }
    const dup = $('cashierDuplicateNote');
    if (summary.duplicates > 0) {
      dup.textContent = `${summary.duplicates} payment${summary.duplicates === 1 ? ' was' : 's were'} received for a vehicle that was already paid. Refund them in the PayMongo dashboard (marked "Paid twice" in History).`;
      dup.className = 'text-[11px] px-3 py-2 rounded-md bg-rose-50 text-rose-700 border border-rose-200';
    } else {
      dup.className = 'hidden';
    }
  }

  function render() {
    renderSummary();
    $('cashierTabAwaiting').setAttribute('aria-selected', String(tab === 'awaiting'));
    $('cashierTabHistory').setAttribute('aria-selected', String(tab === 'history'));
    $('cashierTabAwaiting').className = tabClass(tab === 'awaiting');
    $('cashierTabHistory').className = tabClass(tab === 'history');
    $('cashierAwaitingWrap').classList.toggle('hidden', tab !== 'awaiting');
    $('cashierHistoryWrap').classList.toggle('hidden', tab !== 'history');
    $('cashierTabAwaitingCount').textContent = unpaid.length;
    if (tab === 'awaiting') renderAwaiting(); else renderHistory();
  }

  function tabClass(active) {
    return 'px-3.5 py-2 text-xs font-bold border-b-2 cursor-pointer transition-colors ' +
      (active ? 'border-ncst-navy text-ncst-navy' : 'border-transparent text-slate-500 hover:text-slate-800');
  }

  function renderAwaiting() {
    const body = $('cashierAwaitingBody');
    const q = ($('cashierSearch').value || '').trim().toLowerCase();
    const qPlate = q.replace(/[^a-z0-9]/g, '');
    const rows = unpaid.filter(v => !q || v.plateNumber.toLowerCase().includes(q)
      || (qPlate && v.plateNumber.toLowerCase().replace(/[^a-z0-9]/g, '').includes(qPlate))
      || v.ownerName.toLowerCase().includes(q) || v.ownerIdNumber.toLowerCase().includes(q));
    if (!rows.length) {
      body.innerHTML = `<tr><td colspan="7" class="px-4 py-8 text-center text-slate-400">${unpaid.length ? 'No unpaid vehicle matches your search.' : 'Nothing is waiting for payment.'}</td></tr>`;
      return;
    }
    body.innerHTML = '';
    rows.forEach(v => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50/60';
      tr.innerHTML = `
        <td class="px-4 py-2.5 font-mono font-bold text-slate-900 whitespace-nowrap">${esc(v.plateNumber)}</td>
        <td class="px-4 py-2.5"><div class="font-semibold text-slate-800">${esc(v.ownerName)}</div><div class="text-[11px] text-slate-500">${esc(v.ownerIdNumber)} · ${esc(v.ownerRole)}</div></td>
        <td class="px-4 py-2.5">${esc(v.vehicleType)}</td>
        <td class="px-4 py-2.5 font-bold text-slate-900 whitespace-nowrap">${peso(v.feeAmount)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap">${formatDate(v.registeredAt)}</td>
        <td class="px-4 py-2.5">${v.onlineCheckoutOpen ? '<span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-200">Checkout open</span>' : '<span class="text-slate-400">—</span>'}</td>
        <td class="px-4 py-2.5 text-right"><button type="button" class="px-3 py-1.5 rounded-md bg-ncst-navy hover:bg-ncst-navyDark text-white text-xs font-semibold shadow-xs cursor-pointer">Receive cash</button></td>`;
      tr.querySelector('button').addEventListener('click', () => receiveCash(v));
      body.appendChild(tr);
    });
  }

  function renderHistory() {
    const body = $('cashierHistoryBody');
    if (!history.length) {
      body.innerHTML = '<tr><td colspan="8" class="px-4 py-8 text-center text-slate-400">No payments yet.</td></tr>';
      return;
    }
    body.innerHTML = '';
    history.forEach(p => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50/60';
      tr.innerHTML = `
        <td class="px-4 py-2.5 font-mono text-[11px] whitespace-nowrap">${esc(p.receiptNumber || '—')}</td>
        <td class="px-4 py-2.5 whitespace-nowrap">${formatDate(p.paidAt || p.createdAt)}</td>
        <td class="px-4 py-2.5 font-mono font-bold text-slate-900 whitespace-nowrap">${esc(p.plateNumber)}</td>
        <td class="px-4 py-2.5"><div class="font-semibold text-slate-800">${esc(p.ownerName)}</div><div class="text-[11px] text-slate-500">${esc(p.ownerIdNumber)}</div></td>
        <td class="px-4 py-2.5">${methodLabel(p)}${p.recordedBy ? `<div class="text-[11px] text-slate-500">${esc(p.recordedBy)}</div>` : ''}</td>
        <td class="px-4 py-2.5 font-bold text-slate-900 whitespace-nowrap">${peso(p.amount)}</td>
        <td class="px-4 py-2.5">${statusBadge(p)}</td>
        <td class="px-4 py-2.5 text-right">${p.status === 'Paid' ? '<button type="button" class="px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs cursor-pointer">Receipt</button>' : ''}</td>`;
      const btn = tr.querySelector('button');
      if (btn) btn.addEventListener('click', () => showReceipt(p));
      body.appendChild(tr);
    });
  }

  /* ------------------------------------------------------------------------
     Receive cash + receipt
     ------------------------------------------------------------------------ */
  async function receiveCash(v) {
    if (typeof Swal === 'undefined') { SP.showToast('Dialogs failed to load. Reload the page.'); return; }
    const result = await Swal.fire({
      title: 'Receive cash payment',
      html: `
        <div style="text-align:left;font-size:13px;line-height:1.6">
          <div><strong>${esc(v.plateNumber)}</strong> · ${esc(v.vehicleType)}</div>
          <div>${esc(v.ownerName)} (${esc(v.ownerIdNumber)})</div>
          <div style="margin:10px 0 2px;font-size:12px;color:#64748b">Registration fee</div>
          <div style="font-size:26px;font-weight:800;color:#0f172a">${peso(v.feeAmount)}</div>
        </div>`,
      input: 'number',
      inputLabel: 'Cash received (₱)',
      inputValue: v.feeAmount,
      inputAttributes: { min: String(v.feeAmount), step: '0.01' },
      showCancelButton: true,
      confirmButtonText: 'Confirm payment',
      confirmButtonColor: '#253475',
      focusConfirm: false,
      preConfirm: async (value) => {
        const tendered = Number(value);
        if (!isFinite(tendered) || tendered + 0.001 < v.feeAmount) {
          Swal.showValidationMessage(`The cash received must be at least ${peso(v.feeAmount)}.`);
          return false;
        }
        try {
          return await ApiClient.receiveCashPayment(v.vehicleId, tendered);
        } catch (err) {
          Swal.showValidationMessage(err.message);
          return false;
        }
      },
    });
    if (!result.isConfirmed || !result.value) return;
    document.dispatchEvent(new CustomEvent('sp:payment-recorded'));
    if (window.SP && SP.reload) SP.reload(true, true); // the directory shows each vehicle's payment state
    await load();
    await showReceipt(result.value.payment, true);
  }

  function receiptRows(p) {
    const rows = [
      ['Receipt no.', p.receiptNumber], ['Date', formatDate(p.paidAt)], ['Plate', p.plateNumber],
      ['Owner', `${p.ownerName} (${p.ownerIdNumber})`], ['Sticker year', p.stickerYear],
      ['Method', p.method === 'Cash' ? 'Cash' : 'Online (PayMongo)'], ['Amount', peso(p.amount)],
    ];
    if (p.method === 'Cash' && p.cashTendered != null) {
      rows.push(['Cash received', peso(p.cashTendered)], ['Change', peso(p.change)]);
    }
    if (p.recordedBy) rows.push(['Received by', p.recordedBy]);
    return rows;
  }

  async function showReceipt(p, justPaid) {
    if (typeof Swal === 'undefined') return;
    const rows = receiptRows(p).map(([k, v]) =>
      `<tr><td style="padding:3px 10px 3px 0;color:#64748b;white-space:nowrap">${esc(k)}</td><td style="padding:3px 0;font-weight:600;color:#0f172a;text-align:left">${esc(v)}</td></tr>`).join('');
    const result = await Swal.fire({
      icon: justPaid ? 'success' : undefined,
      title: justPaid ? 'Payment received' : 'Official receipt',
      html: `${justPaid ? '<p style="margin:0 0 10px;font-size:13px;color:#047857">The QR pass for this vehicle is now active.</p>' : ''}
        <table style="font-size:13px;margin:0 auto">${rows}</table>`,
      showDenyButton: true,
      denyButtonText: 'Print receipt',
      denyButtonColor: '#475569',
      confirmButtonText: 'Done',
      confirmButtonColor: '#253475',
    });
    if (result.isDenied) {
      printReceipt(p);
    }
  }

  function printReceipt(p) {
    const w = window.open('', '_blank', 'width=420,height=620');
    if (!w) { SP.showToast('Allow pop-ups to print the receipt.'); return; }
    const rows = receiptRows(p).map(([k, v]) => `<tr><td class="k">${esc(k)}</td><td class="v">${esc(v)}</td></tr>`).join('');
    w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(p.receiptNumber)}</title>
      <style>body{font-family:system-ui,sans-serif;margin:24px;color:#0f172a}h1{font-size:16px;margin:0}p{margin:2px 0 14px;font-size:12px;color:#475569}
      table{width:100%;border-collapse:collapse;font-size:13px}td{padding:5px 0;border-bottom:1px dashed #cbd5e1}.k{color:#64748b;width:38%}.v{font-weight:600;text-align:right}
      .foot{margin-top:18px;font-size:11px;color:#64748b;text-align:center}</style></head><body>
      <h1>NCST SecurePark</h1><p>Vehicle registration fee – official receipt</p>
      <table>${rows}</table><div class="foot">Keep this receipt. Your QR pass is available in the SecurePark student portal.</div>
      <script>window.onload=function(){window.print();}<\/script></body></html>`);
    w.document.close();
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  function setTab(next) {
    tab = next;
    render();
  }

  // Same rule as lib/payments.php registrationFee(); display only, the server decides the real fee
  function feeFor(type) {
    const t = String(type || '').toLowerCase();
    if (/motor|scooter|tricycle|\b[23]\s*-?\s*wheel/.test(t)) return 250;
    if (/bicycle|non-?\s?plated|unplated|\bbike\b/.test(t)) return 0;
    return 500;
  }

  function updateFeeHint() {
    const select = $('vehicleCategory'), hint = $('vehicleFeeHint');
    if (!select || !hint) return;
    const vip = $('passClassVip') && $('passClassVip').checked;
    const fee = vip ? 0 : feeFor(select.value);
    hint.textContent = fee ? `Registration fee: ${peso(fee)}. The QR pass is issued after it is paid (cashier or online).` : 'No registration fee. The QR pass is issued right away.';
  }

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('cashierView', $('navCashierBtn'), load);
    if ($('vehicleCategory')) { $('vehicleCategory').addEventListener('change', updateFeeHint); updateFeeHint(); }
    if ($('passClassVip')) $('passClassVip').addEventListener('change', updateFeeHint);
    $('cashierRefreshBtn').addEventListener('click', load);
    $('cashierTabAwaiting').addEventListener('click', () => setTab('awaiting'));
    $('cashierTabHistory').addEventListener('click', () => setTab('history'));
    $('cashierSearch').addEventListener('input', () => {
      if (tab === 'awaiting') { renderAwaiting(); return; }
      clearTimeout(searchTimer);
      searchTimer = setTimeout(load, 300);
    });
    if (window.SPAuth) {
      SPAuth.whenAuthenticated(refreshCount);
    }
    // A fresh registration adds to the queue; online payments arrive by themselves, so poll gently
    document.addEventListener('sp:vehicle-registered', refreshCount);
    setInterval(() => {
      if (document.hidden) return;
      if ($('cashierView').classList.contains('active')) load(); else refreshCount();
    }, 60000);
  });
})();
