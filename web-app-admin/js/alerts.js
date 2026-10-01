/**
 * SecurePark Web App - SweetAlert2 NCST Institutional Theme & Helper
 *
 * Provides polished, accessible, branded dialogs, confirmations, and toast
 * notifications that match NCST's academic design system.
 */
(function (global) {
  'use strict';

  // Inject NCST SweetAlert2 custom CSS rules
  const style = document.createElement('style');
  style.id = 'sp-sweetalert-styles';
  style.textContent = `
    .swal2-popup.sp-swal-popup {
      font-family: 'Plus Jakarta Sans', system-ui, sans-serif !important;
      border-radius: 14px !important;
      border: 1px solid #E2E8F0 !important;
      box-shadow: 0 20px 25px -5px rgba(15, 23, 42, 0.12), 0 8px 10px -6px rgba(15, 23, 42, 0.08) !important;
      padding: 1.5rem !important;
    }
    .swal2-popup.sp-swal-popup .swal2-title {
      font-size: 1.15rem !important;
      font-weight: 700 !important;
      color: #0F172A !important;
      margin-bottom: 0.5rem !important;
    }
    .swal2-popup.sp-swal-popup .swal2-html-container {
      font-size: 0.875rem !important;
      color: #475569 !important;
      line-height: 1.55 !important;
      margin-top: 0.25rem !important;
    }
    .swal2-popup.sp-swal-popup .swal2-actions {
      gap: 0.625rem !important;
      margin-top: 1.25rem !important;
    }
    .sp-swal-btn-navy {
      background-color: #1B3676 !important;
      color: #FFFFFF !important;
      font-weight: 700 !important;
      font-size: 0.8125rem !important;
      padding: 0.55rem 1.15rem !important;
      border-radius: 8px !important;
      border: 1px solid #112552 !important;
      box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08) !important;
      transition: background-color 0.15s ease !important;
    }
    .sp-swal-btn-navy:hover {
      background-color: #112552 !important;
    }
    .sp-swal-btn-crimson {
      background-color: #D62828 !important;
      color: #FFFFFF !important;
      font-weight: 700 !important;
      font-size: 0.8125rem !important;
      padding: 0.55rem 1.15rem !important;
      border-radius: 8px !important;
      border: 1px solid #B31B1B !important;
      box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08) !important;
      transition: background-color 0.15s ease !important;
    }
    .sp-swal-btn-crimson:hover {
      background-color: #B31B1B !important;
    }
    .sp-swal-btn-gold {
      background-color: #D49B00 !important;
      color: #FFFFFF !important;
      font-weight: 700 !important;
      font-size: 0.8125rem !important;
      padding: 0.55rem 1.15rem !important;
      border-radius: 8px !important;
      border: 1px solid #B48200 !important;
      box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08) !important;
      transition: background-color 0.15s ease !important;
    }
    .sp-swal-btn-gold:hover {
      background-color: #B48200 !important;
    }
    .sp-swal-btn-cancel {
      background-color: #F8FAFC !important;
      color: #475569 !important;
      font-weight: 600 !important;
      font-size: 0.8125rem !important;
      padding: 0.55rem 1.15rem !important;
      border-radius: 8px !important;
      border: 1px solid #CBD5E1 !important;
      transition: background-color 0.15s ease, color 0.15s ease !important;
    }
    .sp-swal-btn-cancel:hover {
      background-color: #F1F5F9 !important;
      color: #1E293B !important;
    }
    /* Written-statement popup (SPAlert.prompt) */
    .swal2-popup.sp-swal-popup .swal2-input-label {
      font-size: 0.75rem !important;
      font-weight: 700 !important;
      color: #334155 !important;
      justify-content: flex-start !important;
      margin: 0.9rem 0 0.35rem !important;
    }
    .swal2-popup.sp-swal-popup .swal2-textarea.sp-swal-input {
      font-family: inherit !important;
      font-size: 0.8125rem !important;
      color: #0F172A !important;
      border: 1px solid #CBD5E1 !important;
      border-radius: 8px !important;
      margin: 0 !important;
      min-height: 5.5rem !important;
      box-shadow: none !important;
    }
    .swal2-popup.sp-swal-popup .swal2-textarea.sp-swal-input:focus {
      border-color: #1B3676 !important;
      box-shadow: 0 0 0 2px rgba(27, 54, 118, 0.18) !important;
    }
    .swal2-popup.sp-swal-popup .swal2-validation-message {
      font-size: 0.75rem !important;
      font-weight: 600 !important;
      background: #FEF2F2 !important;
      color: #B31B1B !important;
    }
    /* Toast Styles */
    .swal2-popup.sp-swal-toast {
      font-family: 'Plus Jakarta Sans', system-ui, sans-serif !important;
      background: #0F172A !important;
      color: #F8FAFC !important;
      border: 1px solid #334155 !important;
      border-radius: 10px !important;
      box-shadow: 0 10px 15px -3px rgba(15, 23, 42, 0.25) !important;
      padding: 0.65rem 1rem !important;
    }
    .swal2-popup.sp-swal-toast .swal2-title {
      font-size: 0.8125rem !important;
      font-weight: 600 !important;
      color: #F8FAFC !important;
      margin: 0 !important;
    }
    .swal2-popup.sp-swal-toast.sp-toast-success {
      border-left: 4px solid #16A34A !important;
    }
    .swal2-popup.sp-swal-toast.sp-toast-error {
      border-left: 4px solid #D62828 !important;
    }
    .swal2-popup.sp-swal-toast.sp-toast-warning {
      border-left: 4px solid #F5B800 !important;
    }
    .swal2-popup.sp-swal-toast.sp-toast-info {
      border-left: 4px solid #264EA8 !important;
    }
  `;
  document.head.appendChild(style);

  // Fallback if SweetAlert2 is not loaded
  function hasSwal() {
    return typeof global.Swal === 'function';
  }

  // Toast instance cache
  let ToastMixin = null;
  function getToastMixin() {
    if (!hasSwal()) return null;
    if (!ToastMixin) {
      ToastMixin = global.Swal.mixin({
        toast: true,
        position: 'bottom-end',
        showConfirmButton: false,
        timer: 3000,
        timerProgressBar: true,
        customClass: {
          popup: 'sp-swal-toast'
        },
        didOpen: (toast) => {
          toast.addEventListener('mouseenter', global.Swal.stopTimer);
          toast.addEventListener('mouseleave', global.Swal.resumeTimer);
        }
      });
    }
    return ToastMixin;
  }

  const SPAlert = {
    /**
     * Show a branded confirmation dialog
     * @param {Object} opts
     * @param {string} opts.title
     * @param {string} [opts.text]
     * @param {string} [opts.html]
     * @param {'warning'|'question'|'error'|'info'} [opts.icon='warning']
     * @param {string} [opts.confirmText='Confirm']
     * @param {string} [opts.cancelText='Cancel']
     * @param {boolean} [opts.isDanger=false]
     * @param {boolean} [opts.isWarning=false]
     * @returns {Promise<boolean>} Resolves true if confirmed, false otherwise
     */
    async confirm({
      title,
      text = '',
      html = '',
      icon = 'warning',
      confirmText = 'Confirm',
      cancelText = 'Cancel',
      isDanger = false,
      isWarning = false
    }) {
      if (!hasSwal()) {
        const fullMsg = [title, text].filter(Boolean).join('\n\n');
        return global.confirm(fullMsg);
      }

      let btnClass = 'sp-swal-btn-navy';
      if (isDanger) btnClass = 'sp-swal-btn-crimson';
      else if (isWarning) btnClass = 'sp-swal-btn-gold';

      const res = await global.Swal.fire({
        title,
        text: html ? undefined : text,
        html: html || undefined,
        icon,
        showCancelButton: true,
        confirmButtonText: confirmText,
        cancelButtonText: cancelText,
        reverseButtons: true,
        focusCancel: isDanger,
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          confirmButton: btnClass,
          cancelButton: 'sp-swal-btn-cancel'
        }
      });

      return !!res.isConfirmed;
    },

    /**
     * Show a success modal
     */
    async success({ title, text = '', html = '', timer = 2200, showConfirmButton = false }) {
      if (!hasSwal()) {
        return SPAlert.toast(text || title, 'success');
      }
      return global.Swal.fire({
        icon: 'success',
        title,
        text: html ? undefined : text,
        html: html || undefined,
        timer,
        timerProgressBar: timer > 0,
        showConfirmButton,
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          confirmButton: 'sp-swal-btn-navy'
        }
      });
    },

    /**
     * Show an error modal
     */
    async error({ title, text = '', html = '', confirmText = 'Understood' }) {
      if (!hasSwal()) {
        const full = [title, text].filter(Boolean).join('\n\n');
        global.alert(full);
        return;
      }
      return global.Swal.fire({
        icon: 'error',
        title,
        text: html ? undefined : text,
        html: html || undefined,
        confirmButtonText: confirmText,
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          confirmButton: 'sp-swal-btn-crimson'
        }
      });
    },

    /**
     * Show a warning modal
     */
    async warning({ title, text = '', html = '', confirmText = 'OK' }) {
      if (!hasSwal()) {
        const full = [title, text].filter(Boolean).join('\n\n');
        global.alert(full);
        return;
      }
      return global.Swal.fire({
        icon: 'warning',
        title,
        text: html ? undefined : text,
        html: html || undefined,
        confirmButtonText: confirmText,
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          confirmButton: 'sp-swal-btn-gold'
        }
      });
    },

    /**
     * Show an informative modal
     */
    async info({ title, text = '', html = '', confirmText = 'Close' }) {
      if (!hasSwal()) {
        const full = [title, text].filter(Boolean).join('\n\n');
        global.alert(full);
        return;
      }
      return global.Swal.fire({
        icon: 'info',
        title,
        text: html ? undefined : text,
        html: html || undefined,
        confirmButtonText: confirmText,
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          confirmButton: 'sp-swal-btn-navy'
        }
      });
    },

    /**
     * Ask for a short written statement (for example the resolution note of a security case).
     * @returns {Promise<string|null>} the trimmed text, or null when the dialog was cancelled
     */
    async prompt({
      title,
      text = '',
      html = '',
      label = '',
      value = '',
      placeholder = '',
      icon = 'question',
      confirmText = 'Confirm',
      cancelText = 'Cancel',
      required = true,
      requiredMessage = 'Please enter a statement.',
      maxLength = 300
    }) {
      if (!hasSwal()) {
        const typed = global.prompt([title, text].filter(Boolean).join('\n\n'), value);
        return typed === null ? null : typed.trim();
      }
      const res = await global.Swal.fire({
        title,
        text: html ? undefined : text,
        html: html || undefined,
        icon,
        input: 'textarea',
        inputLabel: label || undefined,
        inputValue: value,
        inputPlaceholder: placeholder,
        inputAttributes: { maxlength: String(maxLength), 'aria-label': label || title },
        inputValidator: (v) => (required && !String(v || '').trim() ? requiredMessage : undefined),
        showCancelButton: true,
        confirmButtonText: confirmText,
        cancelButtonText: cancelText,
        reverseButtons: true,
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          input: 'sp-swal-input',
          confirmButton: 'sp-swal-btn-navy',
          cancelButton: 'sp-swal-btn-cancel'
        }
      });
      return res.isConfirmed ? String(res.value || '').trim() : null;
    },

    /**
     * Show a non-intrusive toast notification
     * Auto-detects type if message contains obvious keywords
     */
    toast(message, type = null) {
      if (!message) return;
      const str = String(message);

      // Auto-detect type if not provided
      if (!type) {
        const lower = str.toLowerCase();
        if (lower.includes('banned') || lower.includes('error') || lower.includes('failed') || lower.includes('rejected')) {
          type = 'error';
        } else if (lower.includes('warning') || lower.includes('strike') || lower.includes('suspended')) {
          type = 'warning';
        } else if (lower.includes('success') || lower.includes('updated') || lower.includes('issued') || lower.includes('cleared') || lower.includes('approved')) {
          type = 'success';
        } else {
          type = 'info';
        }
      }

      const toast = getToastMixin();
      if (!toast) {
        // Fallback to legacy DOM toast
        const legacyHub = document.getElementById('toastHub');
        if (legacyHub) {
          const div = document.createElement('div');
          div.className = 'pointer-events-auto px-4 py-2.5 rounded-md shadow-lg text-xs font-semibold text-white bg-slate-900 border border-slate-700 transition-all duration-200 transform translate-y-2 opacity-0';
          div.textContent = str;
          legacyHub.appendChild(div);
          requestAnimationFrame(() => div.classList.remove('translate-y-2', 'opacity-0'));
          setTimeout(() => {
            div.classList.add('opacity-0', 'translate-y-2');
            setTimeout(() => div.remove(), 200);
          }, 2800);
        }
        return;
      }

      toast.fire({
        icon: type,
        title: str,
        customClass: {
          popup: `sp-swal-toast sp-toast-${type}`
        }
      });
    },

    /**
     * Show a temporary password dialog with 1-click copy
     */
    async tempPassword({ title = 'Temporary Password Issued', username = '', password, subtext = '' }) {
      if (!password) return;
      const subtitle = subtext || (username ? `Account: ${username}` : 'Use this password for first sign-in.');

      const html = `
        <div style="text-align:center; padding: 0.25rem 0;">
          <p style="font-size: 0.8125rem; color: #64748B; margin-bottom: 0.75rem;">${subtitle}</p>
          <div style="display:flex; align-items:center; justify-content:center; gap: 0.5rem; background:#F1F5F9; border: 1.5px dashed #CBD5E1; border-radius: 8px; padding: 0.75rem 1rem; margin-bottom: 1rem;">
            <code id="spTempPassCode" style="font-family:'JetBrains Mono',monospace; font-size:1.25rem; font-weight:700; color:#1B3676; letter-spacing:0.05em;">${password}</code>
            <button type="button" id="spTempPassCopyBtn" style="border:none; background:#1B3676; color:#FFF; border-radius:6px; padding: 0.35rem 0.65rem; font-size:0.75rem; font-weight:700; cursor:pointer;">
              Copy
            </button>
          </div>
          <p style="font-size: 0.75rem; color: #D62828; font-weight:600; margin:0;">
            They must change this password upon their first sign-in. This code will not be shown again.
          </p>
        </div>
      `;

      if (!hasSwal()) {
        prompt(`${title}\n${subtitle}\n\nCopy this temporary password:`, password);
        return;
      }

      await global.Swal.fire({
        title,
        html,
        icon: 'info',
        confirmButtonText: 'Done',
        buttonsStyling: false,
        customClass: {
          popup: 'sp-swal-popup',
          confirmButton: 'sp-swal-btn-navy'
        },
        didOpen: () => {
          const copyBtn = document.getElementById('spTempPassCopyBtn');
          if (copyBtn) {
            copyBtn.addEventListener('click', async () => {
              try {
                await navigator.clipboard.writeText(password);
                copyBtn.textContent = 'Copied!';
                copyBtn.style.backgroundColor = '#16A34A';
                setTimeout(() => {
                  copyBtn.textContent = 'Copy';
                  copyBtn.style.backgroundColor = '#1B3676';
                }, 2000);
              } catch (_) {
                SPAlert.toast('Copy failed. Select the text manually.', 'error');
              }
            });
          }
        }
      });
    }
  };

  global.SPAlert = SPAlert;
})(typeof window !== 'undefined' ? window : this);
