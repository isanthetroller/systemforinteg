/**
 * SecurePark - CCTV Simulation Widget
 *
 *   SPCctv.mount(element, { camera: 'CAM 01 (MAIN GATE)', lane: 'INGRESS MONITOR - LANE 1' })
 *   -> returns { setLane(text) }
 *
 * Plays assets/cctv_simulation.mp4 on a loop (autoplay, muted, inline). If the file is
 * missing or cannot play, an animated "NO SIGNAL" static screen is shown instead.
 * The clock always shows Philippine Standard Time (Asia/Manila).
 *
 * Recorded-clip mode (used for the 5 s entry / exit clips, see cctvclip.js):
 *   SPCctv.mount(el, { camera, lane, clip: { sources: [url, fallbackUrl], seconds: 5, timestamp: '2026-09-30 08:00:00 PST' } })
 * shows "REC" instead of "LIVE", a frozen event timestamp, and loops the first `seconds` of the first
 * source that exists. With no file at all the NO SIGNAL screen reads "Clip placeholder".
 */
(function () {
  const VIDEO_SRC = 'assets/cctv_simulation.mp4';

  const STYLE = `
    .sp-cctv { position: relative; overflow: hidden; border-radius: 0.5rem; background: #05070d; aspect-ratio: 16 / 9;
               border: 1px solid #1e293b; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.04), 0 1px 2px rgba(15,23,42,0.2); }
    .sp-cctv video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; filter: saturate(0.55) contrast(1.1); }
    .sp-cctv-scan { position: absolute; inset: 0; pointer-events: none;
                    background: repeating-linear-gradient(to bottom, rgba(0,0,0,0) 0 2px, rgba(0,0,0,0.22) 2px 3px);
                    mix-blend-mode: multiply; }
    .sp-cctv-vignette { position: absolute; inset: 0; pointer-events: none;
                        background: radial-gradient(ellipse at center, rgba(0,0,0,0) 55%, rgba(0,0,0,0.55) 100%); }
    .sp-cctv-hud { position: absolute; font-family: "JetBrains Mono", ui-monospace, monospace; font-weight: 700;
                   color: #f8fafc; text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.8); font-size: 11px; letter-spacing: 0.04em;
                   background: rgba(2, 6, 23, 0.55); padding: 3px 7px; border-radius: 3px; line-height: 1.3; }
    .sp-cctv-nosignal { position: absolute; inset: 0; display: none; align-items: center; justify-content: center; flex-direction: column; gap: 6px;
                        background-color: #0b0f19; color: #e2e8f0; font-family: "JetBrains Mono", monospace; }
    .sp-cctv-nosignal::before { content: ""; position: absolute; inset: -50%; opacity: 0.35;
      background-image:
        repeating-radial-gradient(circle at 17% 32%, rgba(255,255,255,0.9) 0 1px, transparent 1px 3px),
        repeating-radial-gradient(circle at 71% 64%, rgba(255,255,255,0.7) 0 1px, transparent 1px 4px),
        repeating-radial-gradient(circle at 43% 81%, rgba(148,163,184,0.8) 0 1px, transparent 1px 2px);
      animation: sp-cctv-static 0.35s steps(4) infinite; }
    .sp-cctv-nosignal span { position: relative; }
    .sp-cctv.no-signal .sp-cctv-nosignal { display: flex; }
    .sp-cctv.no-signal video { display: none; }
    @keyframes sp-cctv-static {
      0% { transform: translate(0, 0); } 25% { transform: translate(-6%, 4%); }
      50% { transform: translate(5%, -3%); } 75% { transform: translate(-3%, -5%); } 100% { transform: translate(0, 0); }
    }
    @container (max-width: 340px) { .sp-cctv-brand { display: none; } }
    .sp-cctv { container-type: inline-size; }
    @media (prefers-reduced-motion: reduce) { .sp-cctv-nosignal::before { animation: none; } }
  `;

  function injectStyle() {
    if (document.getElementById('sp-cctv-style')) return;
    const el = document.createElement('style');
    el.id = 'sp-cctv-style';
    el.textContent = STYLE;
    document.head.appendChild(el);
  }

  // YYYY-MM-DD HH:mm:ss in Asia/Manila regardless of the viewer's device timezone
  function manilaTimestamp(date = new Date()) {
    const parts = {};
    new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'
    }).formatToParts(date).forEach(p => { parts[p.type] = p.value; });
    return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second} PST`;
  }

  const clocks = new Set();
  setInterval(() => {
    const text = manilaTimestamp();
    clocks.forEach(el => {
      if (!document.body.contains(el)) { clocks.delete(el); return; }
      el.textContent = text;
    });
  }, 1000);

  function mount(host, options = {}) {
    if (!host) return null;
    injectStyle();
    const camera = options.camera || 'CAM 01 (MAIN GATE)';
    const lane = options.lane || 'INGRESS MONITOR - LANE 1';
    const clip = options.clip || null;
    const sources = clip ? clip.sources.slice() : [VIDEO_SRC];
    const clipSeconds = clip ? (clip.seconds || 5) : 0;
    const badge = clip ? 'REC' : 'LIVE';

    host.innerHTML = `
      <div class="sp-cctv" role="img" aria-label="Simulated ${clip ? 'recorded CCTV clip' : 'live CCTV feed'}, ${camera}">
        <video muted autoplay ${clip ? '' : 'loop'} playsinline preload="auto" aria-hidden="true">
          <source src="${sources[0]}" type="video/mp4">
        </video>
        <div class="sp-cctv-nosignal">
          <span style="font-size:18px;font-weight:800;letter-spacing:0.3em;">${clip ? 'CLIP PLACEHOLDER' : 'NO SIGNAL'}</span>
          <span style="font-size:10px;color:#94a3b8;">${clip ? `${clipSeconds} s recording &middot; awaiting ${sources[sources.length - 1]}` : `Awaiting feed: ${VIDEO_SRC}`}</span>
        </div>
        <div class="sp-cctv-scan"></div>
        <div class="sp-cctv-vignette"></div>
        <div style="position:absolute;top:8px;left:8px;right:8px;display:flex;flex-direction:column;align-items:flex-start;gap:4px;">
          <div class="sp-cctv-hud" style="position:static;display:flex;align-items:center;max-width:100%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
            <span class="inline-block w-2.5 h-2.5 rounded-full bg-ncst-crimson ${clip ? '' : 'animate-pulse '}mr-2 flex-shrink-0"></span> ${badge} - ${camera}
          </div>
          <div class="sp-cctv-hud sp-cctv-clock" style="position:static;white-space:nowrap;">${manilaTimestamp()}</div>
        </div>
        <div style="position:absolute;bottom:8px;left:8px;right:8px;display:flex;justify-content:space-between;gap:6px;">
          <div class="sp-cctv-hud sp-cctv-lane" style="position:static;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${lane}</div>
          <div class="sp-cctv-hud sp-cctv-brand" style="position:static;opacity:0.8;white-space:nowrap;">NCST SECUREPARK</div>
        </div>
      </div>`;

    const root = host.querySelector('.sp-cctv');
    const video = root.querySelector('video');
    const source = video.querySelector('source');
    const noSignal = () => root.classList.add('no-signal');

    // Missing file -> <source> error; unsupported / blocked playback -> play() rejection.
    // A clip tries its fallback sources (e.g. the shared placeholder video) before giving up.
    let sourceIndex = 0;
    const onSourceFailed = () => {
      if (sourceIndex < sources.length - 1) {
        sourceIndex += 1;
        source.src = sources[sourceIndex];
        video.load();
        const retry = video.play();
        if (retry && typeof retry.catch === 'function') retry.catch(() => {});
      } else {
        noSignal();
      }
    };
    source.addEventListener('error', onSourceFailed);
    video.addEventListener('error', onSourceFailed);
    video.addEventListener('playing', () => root.classList.remove('no-signal'));
    // A fallback source that loads clears the "no signal" screen and starts playing
    video.addEventListener('canplay', () => {
      root.classList.remove('no-signal');
      if (video.paused) { const p = video.play(); if (p && typeof p.catch === 'function') p.catch(() => {}); }
    });
    const attempt = video.play();
    if (attempt && typeof attempt.catch === 'function') {
      // For a clip, a rejected play() only means the first source is still being replaced by a fallback
      attempt.catch(() => { if (!clip && video.readyState < 2) noSignal(); });
    }

    if (clip) {
      // A recorded clip is exactly `seconds` long: loop that window and show the event's own time
      video.addEventListener('timeupdate', () => {
        if (video.currentTime >= clipSeconds) video.currentTime = 0;
      });
      if (clip.timestamp) root.querySelector('.sp-cctv-clock').textContent = clip.timestamp;
    } else {
      clocks.add(root.querySelector('.sp-cctv-clock'));
    }
    const laneEl = root.querySelector('.sp-cctv-lane');
    return {
      setLane(text) { laneEl.textContent = text; }
    };
  }

  window.SPCctv = { mount, manilaTimestamp };

  document.addEventListener('DOMContentLoaded', () => {
    mount(document.getElementById('dashboardCctvMount'), { camera: 'CAM 01 (MAIN GATE)', lane: 'INGRESS MONITOR - LANE 1' });
  });
})();
