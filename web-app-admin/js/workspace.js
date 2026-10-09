/* Arrange the dashboard before app.js creates charts on DOMContentLoaded.
   Moving an active chart canvas can detach its event listeners during refresh. */
(() => {
  const dashboard = document.getElementById('dashboardView');
  const operations = dashboard.querySelector('.sp-dashboard-operations');
  const support = dashboard.querySelector('.sp-dashboard-support');
  const fleet = document.getElementById('fleetTypesChart').closest('.bg-white');
  const alerts = document.getElementById('attentionPanelContent').closest('.bg-white');
  const overnight = document.getElementById('overnightPanel');
  alerts.classList.add('sp-dashboard-alerts');
  operations.replaceChildren(overnight, fleet);
  support.remove();
  dashboard.append(dashboard.querySelector('.sp-kpis'), dashboard.querySelector('.sp-dashboard-analytics'), alerts, operations, dashboard.querySelector('.sp-dashboard-flow'));
})();

/* Presentation and keyboard behavior only; authorization remains in auth.js. */
document.addEventListener('DOMContentLoaded', () => {
  const sidebar = document.getElementById('appSidebar');
  const menu = document.getElementById('workspaceMenu');
  const backdrop = document.getElementById('workspaceBackdrop');
  const narrow = window.matchMedia('(max-width: 1023px)');
  const content = document.querySelector('.workspace-content');
  const collapse = () => document.getElementById('sidebarCollapseBtn')?.click();
  let backdropTimer;
  const syncSidebar = () => {
    const open = !sidebar.classList.contains('collapsed');
    menu.setAttribute('aria-expanded', String(open));
    menu.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    const overlayOpen = narrow.matches && open;
    clearTimeout(backdropTimer);
    if (overlayOpen) {
      backdrop.hidden = false;
      requestAnimationFrame(() => backdrop.classList.toggle('is-open', narrow.matches && !sidebar.classList.contains('collapsed')));
    } else {
      backdrop.classList.remove('is-open');
      backdropTimer = setTimeout(() => { backdrop.hidden = true; }, 320);
    }
    backdrop.inert = !overlayOpen;
    sidebar.inert = !open;
    content.inert = narrow.matches && open;
  };
  menu.addEventListener('click', () => {
    if (sidebar.classList.contains('collapsed')) document.getElementById('sidebarExpandBtn')?.click();
    else collapse();
    syncSidebar();
    if (!sidebar.classList.contains('collapsed')) {
      const selected = sidebar.querySelector('.nav-item[aria-current="page"]');
      selected?.scrollIntoView({block:'nearest'});
      if (narrow.matches) (selected || sidebar.querySelector('.nav-item'))?.focus();
    }
  });
  backdrop.addEventListener('click', () => { collapse(); menu.focus(); });
  new MutationObserver(syncSidebar).observe(sidebar, {attributes:true, attributeFilter:['class']});
  sidebar.querySelector('nav').addEventListener('click', event => {
    if (narrow.matches && event.target.closest('.nav-item')) { collapse(); menu.focus(); }
  });
  narrow.addEventListener('change', () => { if (narrow.matches) collapse(); syncSidebar(); });
  if (narrow.matches) collapse();
  syncSidebar();
  document.getElementById('workspaceDate').textContent = new Intl.DateTimeFormat('en-PH', {weekday:'short',month:'short',day:'numeric',timeZone:'Asia/Manila'}).format(new Date());
  document.querySelectorAll('.view-panel .overflow-x-auto:has(> table)').forEach(region => {
    region.tabIndex = 0;
    region.setAttribute('role', 'region');
    region.setAttribute('aria-label', `${region.closest('.view-panel')?.querySelector('h1')?.textContent || 'Campus'} records`);
  });
  let currentView = '';
  const updateView = () => {
    const active = document.querySelector('.view-panel.active');
    if (!active || active.id === currentView) return;
    // Only animate navigation changes; auth.js handles the first dashboard entrance.
    const previous = document.getElementById(currentView);
    previous?.classList.remove('sp-page-enter');
    if (previous) active.classList.add('sp-page-enter');
    currentView = active.id;
    document.getElementById('workspacePage').textContent = active.querySelector('h1')?.textContent || 'Campus operations';
    const destinations = {dashboardView:'navDashboardBtn',gateView:'navGateBtn',onCampusView:'navOnCampusBtn',vehiclesView:'navVehiclesBtn',visitorsView:'navVisitorsBtn',accountView:'navAccountBtn',flaggedView:'navFlaggedBtn',violationsView:'navViolationsBtn',auditView:'navAuditBtn',staffView:'navStaffBtn',cashierView:'navCashierBtn',centerView:'navCenterBtn',casesView:'navCasesBtn',flaggedView:'navCasesBtn',violationsView:'navCasesBtn'};
    sidebar.querySelectorAll('.nav-item').forEach(button => {
      if (button.id === destinations[currentView]) button.setAttribute('aria-current','page');
      else button.removeAttribute('aria-current');
    });
    const selected = document.getElementById(destinations[currentView]);
    if (!sidebar.classList.contains('collapsed')) selected?.scrollIntoView({block:'nearest'});
    content.scrollTop = 0;
  };
  document.querySelectorAll('.view-panel').forEach(panel => new MutationObserver(updateView).observe(panel,{attributes:true,attributeFilter:['class']}));
  updateView();
  // The existing close buttons retain responsibility for each dialog's workflow.
  let activeDialog = null;
  let previousFocus = null;
  const focusable = element => [...element.querySelectorAll('button,input,select,textarea,a[href],[tabindex="0"]')].filter(e => !e.disabled && !e.hidden && e.getClientRects().length);
  document.querySelectorAll('.sp-dialog, #drawerOverlay, #editModalOverlay, #zoomQrModalOverlay').forEach(dialog => {
    dialog.classList.add('sp-dialog');
    dialog.setAttribute('role','dialog');
    dialog.setAttribute('aria-modal','true');
    const title = dialog.querySelector('h2,h3');
    if (title) { title.id ||= `${dialog.id}Title`; dialog.setAttribute('aria-labelledby',title.id); }
    else dialog.setAttribute('aria-label', dialog.id === 'visitorCardModal' ? 'Visitor day pass' : 'Campus operations dialog');
    dialog.querySelectorAll('button').forEach(button => {
      if (!button.textContent.trim() && !button.getAttribute('aria-label') && /close/i.test(button.id)) button.setAttribute('aria-label', 'Close dialog');
    });
    dialog.tabIndex = -1;
    const observe = () => {
      const shown = !dialog.classList.contains('hidden') && !dialog.hidden;
      if (shown && activeDialog !== dialog) {
        previousFocus = document.activeElement;
        activeDialog = dialog;
        (focusable(dialog)[0] || dialog).focus();
      } else if (!shown && activeDialog === dialog) {
        activeDialog = null;
        if (previousFocus?.isConnected) previousFocus.focus();
      }
    };
    new MutationObserver(observe).observe(dialog,{attributes:true,attributeFilter:['class','hidden']});
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !activeDialog && narrow.matches && !sidebar.classList.contains('collapsed')) { collapse(); menu.focus(); }
    if (event.key === 'Tab' && !activeDialog && narrow.matches && !sidebar.classList.contains('collapsed')) {
      const controls = focusable(sidebar);
      const first = controls[0], last = controls[controls.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    if (event.key !== 'Tab' || !activeDialog) return;
    const items = focusable(activeDialog);
    if (!items.length) { event.preventDefault(); activeDialog.focus(); return; }
    const first = items[0], last = items[items.length-1];
    if (event.shiftKey && (document.activeElement === first || !activeDialog.contains(document.activeElement))) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && (document.activeElement === last || !activeDialog.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
  });
});
