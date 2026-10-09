/** Authenticated invalidation transport. Poll revisions; reconcile before acknowledging. */
(function () {
  const handlers = new Set();
  let revisions = null, timer, busy = false, failures = 0, generation = 0;
  const status = (state) => {
    document.body.dataset.syncState = state;
    let el = document.getElementById('liveSyncStatus');
    if (!el) { el = document.createElement('div'); el.id = 'liveSyncStatus'; el.setAttribute('role','status'); el.style.cssText='position:fixed;bottom:12px;right:16px;z-index:60;padding:8px 12px;border-radius:8px;background:#fff5e8;color:#854d0e;font-size:12px;box-shadow:0 2px 8px #0002'; document.body.append(el); }
    el.hidden = state === 'live';
    el.textContent = state === 'offline' ? 'Connection lost. Showing earlier information.' : state === 'changed' ? 'This record changed. Check the latest information before saving.' : 'Updating information…';
  };
  async function tick() {
    clearTimeout(timer);
    if (busy || document.hidden || !window.SPAuth?.isAuthenticated()) return;
    busy = true;
    const mine = generation;
    try {
      const next = await ApiClient.getUpdates();
      if (mine !== generation || !SPAuth.isAuthenticated()) return;
      const changed = Object.keys(next.revisions).filter(k => !revisions || revisions[k] !== next.revisions[k]);
      if (changed.length) {
        status('updating');
        SPAuth.updateUser(next.user);
        await ApiClient.fresh(async () => {
          if (changed.some(k => ['vehicles','movements','cases','visitors','payments','clock'].includes(k))) await SP.reload(true, true, true);
          await Promise.all([...handlers].map(fn => fn(changed)));
        });
        if (mine !== generation || !SPAuth.isAuthenticated()) return;
      }
      revisions = next.revisions; failures = 0; status('live');
    } catch (error) { failures++; status('offline'); }
    finally {
      busy = false;
      if (SPAuth.isAuthenticated() && !document.hidden) timer = setTimeout(tick, Math.min(60000, 5000 * 2 ** Math.min(failures, 4)));
    }
  }
  window.SPLive = {
    subscribe(fn) { handlers.add(fn); return () => handlers.delete(fn); },
    wake() { clearTimeout(timer); if (!busy) tick(); },
    start() { generation++; revisions = null; failures = 0; this.wake(); },
    changed() { status('changed'); },
  };
  document.addEventListener('sp:app-ready', () => SPAuth.whenAuthenticated(() => SPLive.start()));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) SPLive.wake(); else clearTimeout(timer); });
  window.addEventListener('online', () => SPLive.wake());
  window.addEventListener('sp:auth-required', () => { generation++; clearTimeout(timer); revisions = null; });
})();
