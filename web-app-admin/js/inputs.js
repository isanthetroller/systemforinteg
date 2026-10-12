/**
 * SecurePark - input rules for the vehicle and visitor day pass forms (admin web)
 *
 * Philippine mobile numbers and driver's license numbers: typing is limited to the right characters and length, the
 * field explains a problem before the form is sent, and a valid value is tidied to the format that is stored
 * (+63 927 910 0511, N01-23-456789). Driver rows are added later by script, so the rules attach through event
 * delegation. The server enforces the same rules (lib/formats.php).
 */
(function (root) {
  'use strict';

  /** "09279100511", "+63 927 910 0511", "639279100511", "9279100511" -> "+63 927 910 0511"; null when invalid; "" when empty. */
  function normalizePhone(raw) {
    const s = String(raw == null ? '' : raw).trim();
    if (!s) return '';
    if (/[^0-9+()\-.\s]/.test(s)) return null;
    let d = s.replace(/\D/g, '');
    if (d.length === 11 && d.startsWith('09')) d = '63' + d.slice(1);
    else if (d.length === 10 && d[0] === '9') d = '63' + d;
    else if (!(d.length === 12 && d.startsWith('639'))) return null;
    return '+63 ' + d.slice(2, 5) + ' ' + d.slice(5, 8) + ' ' + d.slice(8);
  }

  /** "n0123456789" or "N01-23-456789" -> "N01-23-456789"; "" or N/A -> "" (no license); null when invalid. */
  function normalizeLicense(raw) {
    const s = String(raw == null ? '' : raw).trim();
    if (!s || /^n\/?a$/i.test(s)) return '';
    const m = s.toUpperCase().replace(/[\s-]/g, '').match(/^([A-Z]\d{2})(\d{2})(\d{6})$/);
    return m ? m[1] + '-' + m[2] + '-' + m[3] : null;
  }

  /** What the phone field shows while the user types: only digits (and a leading +), capped, grouped. */
  function formatPhoneLive(value) {
    const plus = String(value).trim().startsWith('+');
    let d = String(value).replace(/\D/g, '');
    const international = plus || d.startsWith('63');
    if (international) {
      d = d.slice(0, 12);
      return '+' + [d.slice(0, 2), d.slice(2, 5), d.slice(5, 8), d.slice(8, 12)].filter(Boolean).join(' ');
    }
    if (d.startsWith('0')) {
      d = d.slice(0, 11);
      return [d.slice(0, 4), d.slice(4, 7), d.slice(7, 11)].filter(Boolean).join(' ');
    }
    d = d.slice(0, 10);
    return [d.slice(0, 3), d.slice(3, 6), d.slice(6, 10)].filter(Boolean).join(' ');
  }

  /** What the license field shows while the user types: one letter first, then digits only, grouped as X99-99-999999. */
  function formatLicenseLive(value) {
    let out = '';
    for (const c of String(value).toUpperCase().replace(/[^A-Z0-9]/g, '')) {
      if (out.length === 0) { if (/[A-Z]/.test(c)) out += c; }
      else if (/\d/.test(c)) out += c;
      if (out.length === 11) break;
    }
    return [out.slice(0, 3), out.slice(3, 5), out.slice(5, 11)].filter(Boolean).join('-');
  }

  /** Institutional ID: letters, numbers and hyphens, 3 to 20 characters, in capitals; "" when empty; null when it does not fit. */
  function normalizeId(raw) {
    const s = String(raw == null ? '' : raw).trim().toUpperCase();
    if (!s) return '';
    return /^[A-Z0-9][A-Z0-9-]{2,19}$/.test(s) ? s : null;
  }

  /** What the ID field shows while the user types: capitals, only letters / numbers / hyphens, at most 20, no leading hyphen. */
  function formatIdLive(value) {
    return String(value).toUpperCase().replace(/[^A-Z0-9-]/g, '').replace(/^-+/, '').slice(0, 20);
  }

  const api = { normalizePhone, normalizeLicense, normalizeId, formatPhoneLive, formatLicenseLive, formatIdLive };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.SPInputs = api;
  if (typeof document === 'undefined') return;

  const PHONE = '#ownerContact, #editOwnerPhone, #vpContact, .driver-phone, .edit-driver-phone';
  const LICENSE = '.driver-license, .edit-driver-license';
  const OWNER_ID = '#ownerIdNumber, #editOwnerIdNumber';
  const PHONE_MSG = 'Enter a Philippine mobile number, like 0927 910 0511.';
  const ID_MSG = 'Use letters, numbers and hyphens only, 3 to 20 characters, like NCST-2024-05182.';
  const LICENSE_MSG = 'License no. looks like N01-23-456789: a letter, then 2, 2 and 6 digits. Leave it blank if there is none.';

  function hint(input) {
    let h = input.nextElementSibling;
    if (!h || !h.classList.contains('sp-field-error')) {
      h = document.createElement('p');
      h.className = 'sp-field-error';
      h.setAttribute('role', 'alert');
      input.insertAdjacentElement('afterend', h);
    }
    return h;
  }

  /** Marks the field valid or not. The message is shown once the user has left the field; the browser also blocks Save with it. */
  function show(input, message) {
    input.setCustomValidity(message || '');
    input.setAttribute('aria-invalid', message ? 'true' : 'false');
    hint(input).textContent = message && input.dataset.touched ? message : '';
  }

  const kind = (el) => (el.matches(PHONE) ? 'phone' : el.matches(LICENSE) ? 'license' : el.matches(OWNER_ID) ? 'id' : null);
  const message = (k) => (k === 'phone' ? PHONE_MSG : k === 'license' ? LICENSE_MSG : ID_MSG);
  const normalize = (k, v) => (k === 'phone' ? normalizePhone(v) : k === 'license' ? normalizeLicense(v) : normalizeId(v));
  const live = (k, v) => (k === 'phone' ? formatPhoneLive(v) : k === 'license' ? formatLicenseLive(v) : formatIdLive(v));
  const atEnd = (el) => el.selectionStart === el.value.length;

  document.addEventListener('focusin', (e) => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement)) return;
    const k = kind(el);
    if (k === 'phone') { el.inputMode = 'tel'; el.autocomplete = 'off'; }
    if (k === 'license') { el.autocomplete = 'off'; el.setAttribute('autocapitalize', 'characters'); }
  });

  document.addEventListener('input', (e) => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement)) return;
    const k = kind(el);
    if (!k) return;
    // Reformat while typing only when the caret is at the end, so fixing a digit in the middle is not disturbed
    if (atEnd(el)) el.value = live(k, el.value);
    show(el, normalize(k, el.value) !== null ? '' : message(k));
  });

  document.addEventListener('focusout', (e) => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement)) return;
    const k = kind(el);
    if (!k) return;
    el.dataset.touched = '1';
    const n = normalize(k, el.value);
    if (n === null) { show(el, message(k)); return; }
    if (n !== '' || k === 'license') el.value = n;   // tidy a valid value to the stored format
    show(el, '');
  });
})(typeof window !== 'undefined' ? window : globalThis);
