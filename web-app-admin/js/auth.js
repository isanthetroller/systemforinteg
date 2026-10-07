/**
 * SecurePark - Staff Session Controller
 *
 * Owns the login screen, the change-password modal, role classes on <body>
 * (role-admin / role-guard) and the sidebar profile. Other scripts use:
 *
 *   SPAuth.whenAuthenticated(fn)  run fn after every successful sign-in
 *   SPAuth.isAuthenticated()      true once signed in and past any forced password change
 *   SPAuth.hasRole('admin')       role check for UI decisions (server enforces too)
 *   SPAuth.label()                "Full Name (BADGE)" for display
 *   SPAuth.user()                 current profile object
 */
(function () {
  const session = {
    user: null,
    callbacks: [],
    forcedPasswordChange: false
  };

  const $ = (id) => document.getElementById(id);

  function roleLabel(role) {
    return role === 'admin' ? 'Administrator' : 'Gate Guard';
  }

  function initials(name) {
    return (name || '?')
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map(p => p[0].toUpperCase())
      .join('') || '?';
  }

  function label() {
    const u = session.user;
    if (!u) return '';
    return u.badgeNumber ? `${u.fullName} (${u.badgeNumber})` : u.fullName;
  }

  function hasRole(role) {
    return !!session.user && session.user.role === role;
  }

  function setError(el, message) {
    if (!el) return;
    el.textContent = message || '';
    el.classList.toggle('hidden', !message);
  }

  /* ------------------------------------------------------------------------
     Session state -> UI
     ------------------------------------------------------------------------ */
  function applyUser(user) {
    session.user = user;
    const body = document.body;
    body.classList.add('sp-authed');
    body.classList.toggle('role-admin', user.role === 'admin');
    body.classList.toggle('role-guard', user.role !== 'admin');

    const isGuard2 = user.username === 'guard2' ||
      (user.fullName && user.fullName.toLowerCase().includes('guard 2')) ||
      (user.gateAssigned && (user.gateAssigned.includes('2') || user.gateAssigned.toLowerCase().includes('exit')));
    body.classList.toggle('role-guard2', !!isGuard2);

    if ($('sidebarUserName')) $('sidebarUserName').textContent = user.fullName;
    if ($('sidebarUserInitials')) $('sidebarUserInitials').textContent = initials(user.fullName);
    if ($('sidebarUserRole')) {
      const gate = user.gateAssigned ? ` • ${user.gateAssigned.replace(/Ingress/g, 'Entry').replace(/Egress/g, 'Exit')}` : '';
      const customRole = isGuard2 ? 'Gate 2 Guard (Exit)' : roleLabel(user.role);
      $('sidebarUserRole').textContent = `${customRole}${gate}`;
    }
  }

  function finishSessionCheck() {
    const loading = $('authLoading');
    if (loading) loading.hidden = true;
    document.body.classList.remove('sp-auth-pending');
  }

  // One brief entrance per page load; data refreshes and navigation do not replay it.
  const entranceShown = { login: false, dashboard: false };
  function showEntrance(name, root, className) {
    if (entranceShown[name] || !root) return;
    entranceShown[name] = true;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    root.classList.add(className);
    setTimeout(() => root.classList.remove(className), 650);
  }

  function showLogin(message) {
    session.user = null;
    document.body.classList.remove('sp-authed', 'role-admin', 'role-guard', 'role-guard2');
    const overlay = $('loginOverlay');
    showEntrance('login', overlay, 'sp-login-enter');
    if (overlay) overlay.classList.remove('hidden');
    setError($('loginError'), message || '');
    const pw = $('loginPassword');
    if (pw) { pw.value = ''; pw.type = 'password'; }
    const toggle = $('loginPasswordToggle');
    if (toggle) { toggle.textContent = 'Show'; toggle.setAttribute('aria-label', 'Show password'); toggle.setAttribute('aria-pressed', 'false'); }
    $('loginCapsLock')?.classList.add('hidden');
    finishSessionCheck();
    const un = $('loginUsername');
    if (un) setTimeout(() => (un.value ? pw : un).focus(), 50);
  }

  function hideLogin() {
    const overlay = $('loginOverlay');
    if (overlay) overlay.classList.add('hidden');
  }

  function runCallbacks() {
    session.callbacks.forEach(fn => {
      try { fn(session.user); } catch (err) { console.error('[SPAuth] callback error', err); }
    });
  }

  function onAuthenticated(user) {
    applyUser(user);
    hideLogin();
    finishSessionCheck();
    if (user.mustChangePassword) {
      openPasswordModal(true);
      return; // data loads only after the temporary password is replaced
    }
    showEntrance('dashboard', $('appShell'), 'sp-dashboard-enter');
    runCallbacks();
  }

  /* ------------------------------------------------------------------------
     Change password modal
     ------------------------------------------------------------------------ */
  function openPasswordModal(forced) {
    session.forcedPasswordChange = !!forced;
    const modal = $('passwordModal');
    if (!modal) return;
    ['pwCurrent', 'pwNew', 'pwConfirm'].forEach(id => { if ($(id)) $(id).value = ''; });
    setError($('passwordError'), '');
    if ($('passwordCancelBtn')) $('passwordCancelBtn').classList.toggle('hidden', !!forced);
    if ($('passwordModalHint')) {
      $('passwordModalHint').textContent = forced
        ? 'You are using a temporary password. Set a new one to continue (8+ characters, letters and numbers).'
        : 'At least 8 characters with letters and numbers.';
    }
    modal.classList.remove('hidden');
    modal.classList.add('flex');
    setTimeout(() => $('pwCurrent') && $('pwCurrent').focus(), 50);
  }

  function closePasswordModal() {
    const modal = $('passwordModal');
    if (!modal) return;
    modal.classList.add('hidden');
    modal.classList.remove('flex');
  }

  async function submitPasswordChange(e) {
    e.preventDefault();
    const current = $('pwCurrent').value;
    const next = $('pwNew').value;
    const confirm = $('pwConfirm').value;
    if (!current || !next) return setError($('passwordError'), 'Please fill in all fields.');
    if (next !== confirm) return setError($('passwordError'), 'New passwords do not match.');

    const btn = $('passwordSubmitBtn');
    btn.disabled = true;
    try {
      await ApiClient.changePassword(current, next);
      closePasswordModal();
      if (session.user) session.user.mustChangePassword = false;
      if (window.SP) SP.showToast('Password updated successfully.');
      if (session.forcedPasswordChange) {
        session.forcedPasswordChange = false;
        showEntrance('dashboard', $('appShell'), 'sp-dashboard-enter');
        runCallbacks();
      }
    } catch (err) {
      setError($('passwordError'), err.message || 'Could not change password.');
    } finally {
      btn.disabled = false;
    }
  }

  /* ------------------------------------------------------------------------
     Login / logout
     ------------------------------------------------------------------------ */
  async function submitLogin(e) {
    e.preventDefault();
    const username = $('loginUsername').value.trim();
    const password = $('loginPassword').value;
    if (!username || !password) return setError($('loginError'), 'Enter your username and password.');

    const btn = $('loginSubmitBtn');
    btn.disabled = true;
    const originalHTML = btn.innerHTML;
    btn.innerHTML = `
      <svg class="w-4 h-4 animate-spin text-white inline-block" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
      </svg>
      <span>Signing in…</span>
    `;
    setError($('loginError'), '');
    try {
      const user = await ApiClient.login(username, password);
      onAuthenticated(user);
    } catch (err) {
      setError($('loginError'), err.message || 'Sign in failed. Check your connection.');
    } finally {
      btn.disabled = false;
      btn.innerHTML = originalHTML;
    }
  }

  async function logout() {
    if (window.SPAlert) {
      const confirmed = await SPAlert.confirm({
        title: 'Sign Out?',
        text: 'Are you sure you want to sign out of SecurePark?',
        confirmText: 'Sign Out',
        cancelText: 'Stay Signed In',
        icon: 'question'
      });
      if (!confirmed) return;
    }
    await ApiClient.logout();
    // A full reload guarantees no data from this session stays in memory
    window.location.reload();
  }

  /* ------------------------------------------------------------------------
     Boot
     ------------------------------------------------------------------------ */
  document.addEventListener('DOMContentLoaded', async () => {
    if ($('loginForm')) $('loginForm').addEventListener('submit', submitLogin);
    if ($('passwordForm')) $('passwordForm').addEventListener('submit', submitPasswordChange);
    if ($('passwordCancelBtn')) $('passwordCancelBtn').addEventListener('click', closePasswordModal);
    if ($('changePasswordBtn')) $('changePasswordBtn').addEventListener('click', () => openPasswordModal(false));
    if ($('logoutBtn')) $('logoutBtn').addEventListener('click', logout);
    if ($('topHeaderLogoutBtn')) $('topHeaderLogoutBtn').addEventListener('click', logout);

    if (!window.ApiClient || !ApiClient.hasToken()) {
      showLogin();
      return;
    }
    try {
      onAuthenticated(await ApiClient.me());
    } catch (err) {
      showLogin(err.status === 401 ? '' : (err.message || ''));
    }
  });

  // Any API call that comes back 401 sends the user back to the login screen
  window.addEventListener('sp:auth-required', (e) => {
    if (!session.user) return;
    showLogin((e.detail && e.detail.message) || 'Your session has expired. Please sign in again.');
  });

  window.addEventListener('sp:password-change-required', () => {
    if (!session.forcedPasswordChange) openPasswordModal(true);
  });

  window.SPAuth = {
    whenAuthenticated(fn) {
      session.callbacks.push(fn);
      if (session.user && !session.user.mustChangePassword) fn(session.user);
    },
    // Signed in and past any forced password change: the data pollers run only then
    isAuthenticated: () => !!session.user && !session.user.mustChangePassword,
    hasRole,
    label,
    user: () => session.user
  };
})();
