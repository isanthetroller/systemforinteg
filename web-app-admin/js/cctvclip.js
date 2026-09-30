/**
 * SecurePark - CCTV gate clips (simulation)
 *
 * Every gate passage (entry or exit) gets a 5 second clip from the gate camera. This is a SIMULATION:
 * no video is recorded. The school supplies the footage; until then the player shows a
 * "CLIP PLACEHOLDER" screen.
 *
 * Where to put the videos (web-app-admin/assets/, MP4/H.264, 5 seconds, muted, under ~2 MB each):
 *   cctv_clips/log-<gate log id>.mp4    the clip for that one passage (optional, looked up first)
 *   cctv_clip_placeholder.mp4           one shared clip shown for every passage that has no file of its own
 *
 * Usage:
 *   SPClip.button({ logId, plate, action, loggedAt, gatePoint })  -> HTML for a "5s clip" button
 *   SPClip.open({ ... })                                          -> opens the player modal
 *   SPClip.mount(hostElement, { ... })                            -> embeds the player (audit drawer)
 * Any element with a data-sp-clip attribute made by button() opens the player on click.
 */
(function () {
  const CLIP_SECONDS = 5;
  const SHARED_CLIP = 'assets/cctv_clip_placeholder.mp4';
  const esc = (v) => (window.SP && SP.escapeHtml ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  function isExit(d) {
    return /exit|egress/i.test(d.action || '') || /gate 2|egress/i.test(d.gatePoint || '');
  }

  function describe(d) {
    const exit = isExit(d);
    return {
      camera: exit ? 'CAM 02 (EXIT GATE)' : 'CAM 01 (MAIN GATE)',
      lane: exit ? 'EGRESS MONITOR - LANE 2' : 'INGRESS MONITOR - LANE 1',
      label: exit ? 'Exit' : 'Entry',
      timestamp: d.loggedAt ? `${String(d.loggedAt).slice(0, 19)} PST` : null,
      sources: (d.logId ? [`assets/cctv_clips/log-${encodeURIComponent(d.logId)}.mp4`] : []).concat(SHARED_CLIP)
    };
  }

  function mount(host, d) {
    if (!host || !window.SPCctv) return null;
    const info = describe(d);
    return SPCctv.mount(host, {
      camera: info.camera,
      lane: info.lane,
      clip: { sources: info.sources, seconds: CLIP_SECONDS, timestamp: info.timestamp }
    });
  }

  function button(d, text) {
    const info = describe(d);
    const label = text || `${info.label} clip`;
    return `<button type="button" data-sp-clip="${esc(encodeURIComponent(JSON.stringify(d)))}"
      class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded border border-slate-300 bg-white hover:bg-slate-100 text-[10px] font-bold text-slate-700 cursor-pointer align-middle"
      title="Play the ${CLIP_SECONDS} second CCTV clip of this ${info.label.toLowerCase()}">
      <svg class="w-3 h-3 text-ncst-crimson" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>
      ${esc(label)} &middot; ${CLIP_SECONDS}s</button>`;
  }

  let overlay = null;

  function close() {
    if (!overlay) return;
    overlay.remove();
    overlay = null;
    document.removeEventListener('keydown', onKey);
  }

  function onKey(e) {
    if (e.key === 'Escape') close();
  }

  function open(d) {
    close();
    const info = describe(d);
    overlay = document.createElement('div');
    overlay.className = 'fixed inset-0 z-[80] flex items-center justify-center p-4 bg-slate-900/70';
    overlay.innerHTML = `
      <div class="w-full max-w-xl bg-white rounded-lg shadow-xl border border-slate-200 overflow-hidden" role="dialog" aria-modal="true" aria-label="CCTV clip">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-slate-200">
          <div>
            <div class="text-sm font-bold text-slate-900">${esc(info.label)} clip &middot; <span class="font-mono">${esc(d.plate || '')}</span></div>
            <div class="text-[11px] text-slate-500">${esc(info.camera)} &middot; ${CLIP_SECONDS} second recording${d.loggedAt ? ' &middot; ' + esc(String(d.loggedAt).slice(0, 19)) : ''}</div>
          </div>
          <button type="button" data-clip-close class="px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-100 text-xs font-semibold text-slate-700 cursor-pointer">Close</button>
        </div>
        <div class="p-3 bg-slate-50"><div data-clip-host></div>
          <p class="mt-2 text-[10px] text-slate-500">Simulated CCTV clip. Footage is supplied by the school; a placeholder shows until the video file is added.</p>
        </div>
      </div>`;
    document.body.appendChild(overlay);
    overlay.addEventListener('click', (e) => { if (e.target === overlay || e.target.closest('[data-clip-close]')) close(); });
    document.addEventListener('keydown', onKey);
    mount(overlay.querySelector('[data-clip-host]'), d);
  }

  document.addEventListener('click', (e) => {
    const trigger = e.target.closest && e.target.closest('[data-sp-clip]');
    if (!trigger) return;
    e.preventDefault();
    e.stopPropagation();
    try {
      open(JSON.parse(decodeURIComponent(trigger.getAttribute('data-sp-clip'))));
    } catch (err) { /* malformed descriptor: ignore */ }
  }, true);

  window.SPClip = { open, mount, button, seconds: CLIP_SECONDS };
})();
