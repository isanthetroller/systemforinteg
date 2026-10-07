(() => {
  const headings = {
    tabPass: ['Your campus pass', 'Show your pass and check your vehicle details.'],
    tabActivity: ['Gate activity', 'See when your vehicles entered and left campus.'],
    tabStrikes: ['Warnings & violations', 'Check your warning count and find out what to do next.'],
    tabAccount: ['Your account', 'Manage your password and view your registered details.']
  };
  let currentTab = '';
  function updateHeading() {
    const tab = document.querySelector('.tab:not([hidden])');
    if (!tab || !headings[tab.id] || tab.id === currentTab) return;
    document.getElementById(currentTab)?.classList.remove('portal-page-enter');
    if (currentTab) tab.classList.add('portal-page-enter');
    currentTab = tab.id;
    const [title, description] = headings[tab.id];
    document.getElementById('portalTitle').textContent = title;
    document.getElementById('portalDescription').textContent = description;
  }
  document.querySelectorAll('.tab').forEach(tab => new MutationObserver(updateHeading).observe(tab, {attributes:true,attributeFilter:['hidden']}));
  updateHeading();
  const shownScreens = new Set();
  document.querySelectorAll('.screen').forEach(screen => {
    new MutationObserver(() => {
      if (screen.hidden || shownScreens.has(screen.id)) return;
      shownScreens.add(screen.id);
      screen.classList.add('portal-screen-enter');
      setTimeout(() => screen.classList.remove('portal-screen-enter'), 450);
    }).observe(screen, {attributes:true,attributeFilter:['hidden']});
  });
  const qr = document.getElementById('qrZoom');
  document.getElementById('qrZoomClose').addEventListener('click', () => { qr.hidden = true; });
  let currentDialog = null;
  let returnFocus = null;
  const items = dialog => [...dialog.querySelectorAll('button,a[href],input,[tabindex="0"]')].filter(element => !element.disabled && element.getClientRects().length);
  document.querySelectorAll('[role="dialog"]').forEach(dialog => {
    dialog.tabIndex = -1;
    new MutationObserver(() => {
      if (!dialog.hidden && currentDialog !== dialog) {
        returnFocus = document.activeElement;
        currentDialog = dialog;
        (items(dialog)[0] || dialog).focus();
      } else if (dialog.hidden && currentDialog === dialog) {
        currentDialog = null;
        if (returnFocus?.isConnected) returnFocus.focus();
      }
      document.body.classList.toggle('portal-modal-open', Boolean(currentDialog));
      document.documentElement.classList.toggle('portal-modal-open', Boolean(currentDialog));
    }).observe(dialog, {attributes:true,attributeFilter:['hidden']});
  });
  document.addEventListener('keydown', event => {
    if (event.key !== 'Tab' || !currentDialog) return;
    const controls = items(currentDialog);
    const first = controls[0], last = controls[controls.length - 1];
    if (!first) { event.preventDefault(); currentDialog.focus(); return; }
    if (event.shiftKey && (document.activeElement === first || !currentDialog.contains(document.activeElement))) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && (document.activeElement === last || !currentDialog.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
  });
})();
