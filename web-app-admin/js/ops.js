/**
 * SecurePark - Operations helpers shared by the admin screens
 *
 *  - askReason / askClassLimit: api.js calls these when the server wants a written reason (audit trail) or a decision
 *    about the one-vehicle-per-class rule, then repeats the request with the answer.
 *  - the periodic maintenance tick (expiry notices, hold reminders, shift clean-up, photo retention)
 *  - the dashboard parking-capacity card
 *  - exit release for a vehicle on hold, and retiring a vehicle
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  async function ask(opts) {
    if (window.SPAlert && SPAlert.prompt) return SPAlert.prompt(opts);
    const typed = window.prompt([opts.title, opts.text].filter(Boolean).join('\n\n'));
    return typed === null ? null : typed.trim();
  }

  /** Returns { reason } or null when the administrator cancels. */
  async function askReason(message) {
    const reason = await ask({
      title: 'Reason required',
      text: (message || 'Explain why.').replace(/^A reason \(at least 5 characters\) is required for /, 'Write the reason for ').replace(/\.$/, '') + '. It is saved in the activity log with your name.',
      icon: 'question',
      placeholder: 'e.g. Verified with the Registrar',
      confirmText: 'Save with reason',
      requiredMessage: 'Write at least a few words.',
      maxLength: 250,
    });
    if (!reason) return null;
    if (reason.length < 5) { SP.showToast('The reason must be at least 5 characters.', 'warning'); return askReason(message); }
    return { reason };
  }

  /**
   * One vehicle per class per ID. Offer: replace the old vehicle (fee already paid carries over) or, as an exception,
   * allow an extra one with a written reason. Returns the fields to add to the request, or null to cancel.
   */
  async function askClassLimit(err, canReplace) {
    const d = err.data || {};
    if (typeof Swal === 'undefined') return null;
    const res = await Swal.fire({
      icon: 'warning',
      title: 'One vehicle per class',
      html: `<div style="text-align:left;font-size:13px;line-height:1.6">
          This ID already has <strong>${esc(d.plateNumber)}</strong> registered as a ${esc(d.classLabel)} vehicle.<br><br>
          ${canReplace ? `<strong>Replace it</strong> if the owner changed vehicles: the old one is retired (its history stays) and the fee already paid is credited to the new one.<br><br>` : ''}
          <strong>Allow an extra vehicle</strong> only as an exception. You will write a reason and it is logged.</div>`,
      showCancelButton: true,
      showConfirmButton: !!canReplace,
      showDenyButton: true,
      confirmButtonText: `Replace ${d.plateNumber || 'old vehicle'}`,
      denyButtonText: 'Allow an extra vehicle',
      cancelButtonText: 'Cancel',
      confirmButtonColor: '#253475',
      denyButtonColor: '#b45309',
      reverseButtons: true,
    });
    if (res.isConfirmed) {
      const r = await ask({ title: `Replace ${d.plateNumber}`, text: 'Why is the old vehicle being replaced?', placeholder: 'e.g. Sold the old car, bought a new one', confirmText: 'Replace vehicle', maxLength: 250 });
      return r ? { replacesVehicleId: d.vehicleId, replaceReason: r } : null;
    }
    if (res.isDenied) {
      const r = await ask({ title: 'Allow an extra vehicle', text: `Why does this owner need a second ${d.classLabel} vehicle?`, placeholder: 'e.g. Family vehicle shared with a sibling who also studies here', confirmText: 'Allow extra vehicle', icon: 'warning', maxLength: 250 });
      return r ? { overrideReason: r } : null;
    }
    return null;
  }

  /* ------------------------------------------------------------------------
     Maintenance tick: the host has no cron, so a signed-in browser triggers the nightly jobs
     ------------------------------------------------------------------------ */
  let lastTick = 0;
  async function tick() {
    if (document.hidden || !window.SPAuth || !SPAuth.isAuthenticated() || !window.ApiClient) return;
    if (Date.now() - lastTick < 5 * 60 * 1000) return;
    lastTick = Date.now();
    await ApiClient.runMaintenance();
  }

  /* ------------------------------------------------------------------------
     Parking capacity card (dashboard)
     ------------------------------------------------------------------------ */
  function renderOccupancy(o) {
    const card = $('occupancyCard');
    if (!card || !o) return;
    const unlimited = !o.capacity;
    $('occupancyInside').textContent = o.inside;
    $('occupancyOf').textContent = unlimited ? 'No capacity set' : `of ${o.capacity} spaces`;
    const bar = $('occupancyBar');
    const pct = unlimited ? 0 : Math.min(100, o.percent || 0);
    bar.style.width = pct + '%';
    const tone = o.level === 'full' ? 'bg-rose-600' : o.level === 'nearly_full' ? 'bg-amber-500' : 'bg-emerald-500';
    bar.className = 'h-2 rounded-full transition-all ' + tone;
    const note = $('occupancyNote');
    if (o.message) {
      note.textContent = o.message;
      note.className = 'mt-2 text-[11px] font-semibold ' + (o.level === 'full' ? 'text-rose-700' : 'text-amber-700');
    } else {
      note.textContent = unlimited ? 'Set the parking capacity in Admin Center → Settings.' : `${o.available} space${o.available === 1 ? '' : 's'} left`;
      note.className = 'mt-2 text-[11px] text-slate-500';
    }
    $('occupancyBarWrap').classList.toggle('hidden', unlimited);
  }

  async function refreshOccupancy() {
    if (!window.ApiClient || !window.SPAuth || !SPAuth.isAuthenticated()) return;
    try {
      const stats = await ApiClient.getStats();
      renderOccupancy(stats && stats.occupancy);
    } catch (_) { /* the card is a convenience */ }
  }

  /* ------------------------------------------------------------------------
     Exit release and retire (called from the vehicle drawer)
     ------------------------------------------------------------------------ */
  async function releaseExit(v) {
    const reason = await ask({
      title: `Release one exit for ${v.plateNumber}`,
      html: `<div style="text-align:left;font-size:13px;line-height:1.6">${esc(v.plateNumber)} has an unresolved violation. This lets it <strong>leave once</strong>, within the next 30 minutes. It stays on hold and cannot come back in until the violation is resolved.</div>`,
      label: 'Reason (saved in the activity log)',
      placeholder: 'e.g. Family emergency, driver must leave now',
      confirmText: 'Release one exit',
      icon: 'warning',
      maxLength: 250,
    });
    if (!reason) return false;
    try {
      const r = await ApiClient.releaseExit(v.id, reason);
      SP.showToast(r.message || 'Exit released.', 'success');
      return true;
    } catch (err) {
      SP.showToast(err.message, 'error');
      return false;
    }
  }

  async function retire(v) {
    if (!(window.SPAlert && await SPAlert.confirm({
      title: `Retire ${v.plateNumber}?`,
      text: 'The vehicle can no longer enter and its pass is cancelled. Its gate history, payments and violations are kept. Use this when the owner sold or no longer uses it.',
      confirmText: 'Retire vehicle', icon: 'warning', isDanger: true,
    }))) return false;
    try {
      await ApiClient.retireVehicle(v.id); // api.js asks for the reason
      SP.showToast(`${v.plateNumber} retired.`, 'success');
      if (SP.reload) SP.reload(true, true);
      return true;
    } catch (err) {
      if (err.status) SP.showToast(err.message, 'error');
      return false;
    }
  }

  window.SPOps = { askReason, askClassLimit, releaseExit, retire, tick, renderOccupancy, refreshOccupancy };

  document.addEventListener('sp:app-ready', () => {
    if (window.SPAuth) SPAuth.whenAuthenticated(() => { tick(); refreshOccupancy(); });
    setInterval(tick, 10 * 60 * 1000);
    setInterval(() => { if (!document.hidden) refreshOccupancy(); }, 60 * 1000);
    document.addEventListener('sp:gate-passage', refreshOccupancy);
  });
})();
