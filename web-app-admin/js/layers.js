/* Keep floating UI out of table clipping and animated page stacking contexts. */
document.addEventListener('DOMContentLoaded', () => {
  const selector = '.oc-dropdown, .overflow-menu-dropdown';
  const initialized = new WeakSet();
  const entries = new Set();
  const closeMenus = () => entries.forEach(entry => {
    if (!entry.menu.classList.contains('hidden')) entry.menu.classList.add('hidden');
  });
  let sequence = 0;
  function initialize(menu) {
    if (initialized.has(menu)) return;
    initialized.add(menu);
    const parent = menu.parentElement;
    const button = parent.querySelector('[data-act="menu"], .overflow-menu-btn');
    if (!button) return;
    const entry = {menu, button};
    entries.add(entry);
    menu.id ||= `rowActions${++sequence}`;
    menu.classList.add('sp-floating-menu');
    button.setAttribute('aria-controls', menu.id);
    button.setAttribute('aria-expanded', 'false');
    button.setAttribute('aria-label', 'More actions');
    const topLayer = typeof menu.showPopover === 'function';
    if (topLayer) menu.setAttribute('popover', 'manual');
    const sync = () => {
      const open = !menu.classList.contains('hidden');
      button.setAttribute('aria-expanded', String(open));
      if (!open) {
        if (topLayer && menu.matches(':popover-open')) menu.hidePopover();
        if (!topLayer && menu.parentElement !== parent && parent.isConnected) parent.append(menu);
        return;
      }
      entries.forEach(other => { if (other !== entry) other.menu.classList.add('hidden'); });
      if (topLayer && !menu.matches(':popover-open')) menu.showPopover();
      else if (!topLayer) document.body.append(menu);
      const anchor = button.getBoundingClientRect();
      const bounds = menu.getBoundingClientRect();
      const gap = 6, edge = 12;
      const below = window.innerHeight - anchor.bottom - edge;
      const above = anchor.top - edge;
      const useAbove = below < bounds.height && above > below;
      const available = Math.max(44, useAbove ? above - gap : below - gap);
      menu.style.maxHeight = `${available}px`;
      menu.style.left = `${Math.max(edge, Math.min(anchor.right - bounds.width, window.innerWidth - bounds.width - edge))}px`;
      menu.style.top = `${useAbove ? Math.max(edge, anchor.top - Math.min(bounds.height, available) - gap) : anchor.bottom + gap}px`;
    };
    new MutationObserver(sync).observe(menu, {attributes:true, attributeFilter:['class']});
    button.addEventListener('keydown', event => {
      if (event.key !== 'ArrowDown') return;
      event.preventDefault();
      menu.classList.remove('hidden');
      sync();
      menu.querySelector('button')?.focus();
    });
    menu.addEventListener('keydown', event => {
      const items = [...menu.querySelectorAll('button:not(:disabled)')];
      const index = items.indexOf(document.activeElement);
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        items[(index + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus();
      }
      if (event.key === 'Tab') menu.classList.add('hidden');
    });
  }
  const discover = () => {
    if (document.getElementById('spClipOverlay') || document.querySelector('.swal2-container')) closeMenus();
    entries.forEach(entry => {
      if (!entry.button.isConnected) {
        if (entry.menu.matches('[popover]:popover-open')) entry.menu.hidePopover();
        if (entry.menu.parentElement === document.body) entry.menu.remove();
        entries.delete(entry);
      }
    });
    document.querySelectorAll(selector).forEach(initialize);
  };
  new MutationObserver(discover).observe(document.body, {childList:true, subtree:true});
  discover();
  document.addEventListener('click', event => {
    if (!event.target.closest('.oc-menu-container, .overflow-menu-container, .sp-floating-menu')) closeMenus();
  });
  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    const open = [...entries].find(entry => !entry.menu.classList.contains('hidden'));
    if (open) { event.preventDefault(); closeMenus(); open.button.focus(); }
  }, true);
  document.addEventListener('scroll', event => {
    if (!(event.target instanceof Element && event.target.closest('.sp-floating-menu'))) closeMenus();
  }, true);
  window.addEventListener('resize', closeMenus);
  document.querySelectorAll('.view-panel').forEach(panel => {
    new MutationObserver(() => { if (!panel.classList.contains('active')) { closeMenus(); if (panel.id === 'onCampusView') document.getElementById('ocDrawerCloseBtn')?.click(); } })
      .observe(panel, {attributes:true, attributeFilter:['class']});
  });
  // The desktop details panel stays beside the table; the small-screen drawer lives at the body root.
  const drawer = document.getElementById('ocDrawer');
  const backdrop = document.getElementById('ocDrawerBackdrop');
  const home = document.createComment('On Campus details panel');
  drawer.before(home);
  const desktop = window.matchMedia('(min-width:1280px)');
  const placeDrawer = () => {
    if (desktop.matches) { home.after(drawer); drawer.removeAttribute('aria-modal'); drawer.setAttribute('role','region'); }
    else { document.body.append(drawer); drawer.setAttribute('role','dialog'); drawer.setAttribute('aria-modal','true'); }
    drawer.setAttribute('aria-label','Vehicle details');
  };
  document.body.append(backdrop);
  desktop.addEventListener('change', placeDrawer);
  placeDrawer();
  let drawerFocus = null;
  let drawerWasOpen = false;
  const drawerControls = () => [...drawer.querySelectorAll('button,a[href],input,[tabindex="0"]')]
    .filter(control => !control.disabled && control.getClientRects().length);
  const focusDrawer = () => {
    const open = !desktop.matches && !drawer.classList.contains('hidden');
    if (open && !drawerWasOpen) {
      drawerFocus = document.activeElement;
      (drawerControls()[0] || drawer).focus();
    } else if (!open && drawerWasOpen && drawerFocus?.isConnected) drawerFocus.focus();
    drawerWasOpen = open;
  };
  drawer.tabIndex = -1;
  new MutationObserver(focusDrawer).observe(drawer, {attributes:true,attributeFilter:['class']});
  desktop.addEventListener('change', focusDrawer);
  document.addEventListener('keydown', event => {
    if (event.key !== 'Tab' || !drawerWasOpen || document.querySelector('.sp-dialog:not(.hidden), #drawerOverlay:not(.hidden), #editModalOverlay:not(.hidden), #zoomQrModalOverlay:not(.hidden), #spClipOverlay')) return;
    const controls = drawerControls(), first = controls[0], last = controls[controls.length - 1];
    if (!first) { event.preventDefault(); drawer.focus(); return; }
    if (event.shiftKey && (document.activeElement === first || !drawer.contains(document.activeElement))) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && (document.activeElement === last || !drawer.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
  });
  document.querySelectorAll('.sp-dialog, #drawerOverlay, #editModalOverlay, #zoomQrModalOverlay').forEach(dialog => {
    if (dialog.parentElement !== document.body) document.body.append(dialog);
    new MutationObserver(() => { if (!dialog.classList.contains('hidden')) closeMenus(); })
      .observe(dialog, {attributes:true,attributeFilter:['class']});
  });
});
