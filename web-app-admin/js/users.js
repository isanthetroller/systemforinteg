/**
 * SecurePark - Staff Accounts (admin only)
 *
 * Lists admins and guards, creates accounts with a one-time temporary password,
 * edits details, resets passwords and activates / deactivates accounts.
 * Accounts are never deleted so audit logs keep pointing at real people.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  let staff = [];

  function esc(str) {
    return window.SP ? SP.escapeHtml(str == null ? '' : String(str)) : String(str == null ? '' : str);
  }

  function formatDateTime(value) {
    if (!value) return '<span class="text-slate-400">Never</span>';
    const d = new Date(value.replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    return esc(d.toLocaleString('en-PH', {
      timeZone: 'Asia/Manila', month: 'short', day: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit'
    }));
  }

  function roleBadge(role) {
    return role === 'admin'
      ? '<span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-ncst-navy/10 text-ncst-navy border border-ncst-navy/20">Administrator</span>'
      : '<span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-slate-100 text-slate-700 border border-slate-200">Gate Guard</span>';
  }

  function statusBadge(u) {
    if (u.status !== 'Active') {
      return '<span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-slate-100 text-slate-500 border border-slate-200">Inactive</span>';
    }
    if (u.mustChangePassword) {
      return '<span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-ncst-goldLight text-amber-950 border border-ncst-gold/40">Pending first sign-in</span>';
    }
    return '<span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-ncst-greenLight text-ncst-greenDark border border-ncst-green/30">Active</span>';
  }

  /* ------------------------------------------------------------------------
     Table
     ------------------------------------------------------------------------ */
  function render() {
    const body = $('staffTableBody');
    if (!body) return;
    if (!staff.length) {
      body.innerHTML = '<tr><td colspan="8" class="px-4 py-6 text-center text-slate-400">No staff accounts yet.</td></tr>';
      return;
    }
    const me = window.SPAuth && SPAuth.user();
    body.innerHTML = '';
    staff.forEach(u => {
      const isSelf = me && me.id === u.id;
      const tr = document.createElement('tr');
      tr.className = u.status === 'Active' ? 'hover:bg-slate-50/60' : 'bg-slate-50/40 text-slate-400';
      tr.innerHTML = `
        <td class="px-4 py-2.5 font-semibold text-slate-800">${esc(u.fullName)}${isSelf ? ' <span class="text-[10px] font-bold text-ncst-navy">(you)</span>' : ''}</td>
        <td class="px-4 py-2.5 font-mono text-[11px]">${esc(u.username)}</td>
        <td class="px-4 py-2.5">${roleBadge(u.role)}</td>
        <td class="px-4 py-2.5 font-mono text-[11px]">${esc(u.badgeNumber || '—')}</td>
        <td class="px-4 py-2.5">${esc(u.gateAssigned || '—')}</td>
        <td class="px-4 py-2.5">${statusBadge(u)}</td>
        <td class="px-4 py-2.5 whitespace-nowrap">${formatDateTime(u.lastLogin)}</td>
        <td class="px-4 py-2.5">
          <div class="flex items-center justify-end gap-1.5">
            <button type="button" data-act="edit" class="px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs cursor-pointer">Edit</button>
            <button type="button" data-act="reset" class="px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs cursor-pointer">Reset Password</button>
            ${isSelf ? '' : (u.status === 'Active'
              ? '<button type="button" data-act="deactivate" class="px-2.5 py-1 rounded border border-ncst-crimson/30 bg-ncst-crimsonLight/60 hover:bg-ncst-crimsonLight text-xs font-semibold text-ncst-crimson shadow-xs cursor-pointer">Deactivate</button>'
              : '<button type="button" data-act="activate" class="px-2.5 py-1 rounded border border-ncst-green/30 bg-ncst-greenLight/60 hover:bg-ncst-greenLight text-xs font-semibold text-ncst-greenDark shadow-xs cursor-pointer">Activate</button>')}
          </div>
        </td>`;
      tr.querySelector('[data-act="edit"]').addEventListener('click', () => openModal(u));
      tr.querySelector('[data-act="reset"]').addEventListener('click', () => resetPassword(u));
      const toggle = tr.querySelector('[data-act="deactivate"], [data-act="activate"]');
      if (toggle) toggle.addEventListener('click', () => setStatus(u, u.status === 'Active' ? 'Inactive' : 'Active'));
      body.appendChild(tr);
    });
  }

  async function load() {
    const body = $('staffTableBody');
    try {
      staff = await ApiClient.getUsers();
      render();
    } catch (err) {
      if (body) body.innerHTML = `<tr><td colspan="8" class="px-4 py-6 text-center text-ncst-crimson">${esc(err.message)}</td></tr>`;
    }
  }

  /* ------------------------------------------------------------------------
     Create / edit modal
     ------------------------------------------------------------------------ */
  function openModal(user) {
    const editing = !!user;
    $('staffFormId').value = editing ? user.id : '';
    $('staffFullName').value = editing ? user.fullName : '';
    $('staffUsername').value = editing ? user.username : '';
    $('staffUsername').disabled = editing;
    $('staffRole').value = editing ? user.role : 'guard';
    $('staffBadge').value = editing ? (user.badgeNumber || '') : '';
    $('staffGate').value = editing ? (user.gateAssigned || 'Gate 1 (Main Ingress)') : 'Gate 1 (Main Ingress)';
    $('staffModalTitle').textContent = editing ? `Edit ${user.username}` : 'New Staff Account';
    $('staffModalHint').textContent = editing
      ? 'Username cannot be changed. Use Reset Password to issue a new temporary password.'
      : 'A temporary password is generated and shown once.';
    $('staffSubmitBtn').textContent = editing ? 'Save Changes' : 'Create Account';
    $('staffFormError').classList.add('hidden');
    $('staffModal').classList.remove('hidden');
    $('staffModal').classList.add('flex');
    setTimeout(() => $('staffFullName').focus(), 50);
  }

  function closeModal() {
    $('staffModal').classList.add('hidden');
    $('staffModal').classList.remove('flex');
  }

  async function submitForm(e) {
    e.preventDefault();
    const id = $('staffFormId').value;
    const payload = {
      full_name: $('staffFullName').value.trim(),
      role: $('staffRole').value,
      badge_number: $('staffBadge').value.trim(),
      gate_assigned: $('staffGate').value
    };
    const errEl = $('staffFormError');
    const btn = $('staffSubmitBtn');
    btn.disabled = true;
    try {
      if (id) {
        await ApiClient.updateUser(Number(id), 'update', payload);
        closeModal();
        SP.showToast('Staff account updated.', 'success');
      } else {
        payload.username = $('staffUsername').value.trim();
        const res = await ApiClient.createUser(payload);
        closeModal();
        if (window.SPAlert && typeof SPAlert.tempPassword === 'function') {
          await SPAlert.tempPassword({
            title: 'Staff Account Created',
            username: res.user.username,
            password: res.tempPassword,
            subtext: `Temporary password for ${res.user.fullName} (${res.user.username})`
          });
        } else {
          showTempPassword(res.user.username, res.tempPassword);
        }
      }
      load();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    } finally {
      btn.disabled = false;
    }
  }

  /* ------------------------------------------------------------------------
     Row actions
     ------------------------------------------------------------------------ */
  async function resetPassword(u) {
    const confirmed = window.SPAlert
      ? await SPAlert.confirm({
          title: 'Reset Password?',
          text: `Reset the password for ${u.fullName} (${u.username})? They will be signed out everywhere and must set a new password at next sign-in.`,
          confirmText: 'Reset Password',
          icon: 'warning',
          isDanger: true
        })
      : confirm(`Reset the password for ${u.fullName} (${u.username})?\n\nThey will be signed out everywhere and must set a new password at next sign-in.`);
    if (!confirmed) return;
    try {
      const res = await ApiClient.updateUser(u.id, 'reset_password');
      if (window.SPAlert && typeof SPAlert.tempPassword === 'function') {
        await SPAlert.tempPassword({
          title: 'Password Reset',
          username: u.username,
          password: res.tempPassword,
          subtext: `Temporary password for ${u.fullName} (${u.username})`
        });
      } else {
        showTempPassword(u.username, res.tempPassword);
      }
      load();
    } catch (err) {
      SP.showToast(err.message, 'error');
    }
  }

  async function setStatus(u, status) {
    const verb = status === 'Active' ? 'Reactivate' : 'Deactivate';
    const confirmed = window.SPAlert
      ? await SPAlert.confirm({
          title: `${verb} Account?`,
          text: `Are you sure you want to ${verb.toLowerCase()} the account of ${u.fullName} (${u.username})?`,
          confirmText: `${verb} Account`,
          icon: status === 'Active' ? 'question' : 'warning',
          isDanger: status !== 'Active'
        })
      : confirm(`${verb} the account of ${u.fullName} (${u.username})?`);
    if (!confirmed) return;
    try {
      await ApiClient.updateUser(u.id, 'set_status', { status });
      SP.showToast(`${u.username} is now ${status}.`, 'success');
      load();
    } catch (err) {
      SP.showToast(err.message, 'error');
    }
  }

  function showTempPassword(username, password, label) {
    $('tempPasswordFor').textContent = label || `For account: ${username}`;
    $('tempPasswordValue').textContent = password;
    $('tempPasswordModal').classList.remove('hidden');
    $('tempPasswordModal').classList.add('flex');
  }

  function closeTempPassword() {
    $('tempPasswordValue').textContent = '';
    $('tempPasswordModal').classList.add('hidden');
    $('tempPasswordModal').classList.remove('flex');
  }

  /* ------------------------------------------------------------------------
     Wiring
     ------------------------------------------------------------------------ */
  // Shared with other modules (e.g. student portal logins issued from the vehicle dossier)
  window.SPTempPassword = (label, password) => showTempPassword('', password, label);

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('staffView', $('navStaffBtn'), load);

    $('staffCreateBtn').addEventListener('click', () => openModal(null));
    $('staffCancelBtn').addEventListener('click', closeModal);
    $('staffForm').addEventListener('submit', submitForm);
    $('tempPasswordDoneBtn').addEventListener('click', closeTempPassword);
    $('tempPasswordCopyBtn').addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText($('tempPasswordValue').textContent);
        SP.showToast('Temporary password copied.');
      } catch (_) {
        SP.showToast('Copy failed. Select the password and copy it manually.');
      }
    });
  });
})();
