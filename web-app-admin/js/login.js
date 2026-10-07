/* Login presentation only. Authentication stays in auth.js. */
document.addEventListener('DOMContentLoaded', () => {
  const password = document.getElementById('loginPassword');
  const toggle = document.getElementById('loginPasswordToggle');
  const caps = document.getElementById('loginCapsLock');
  if (!password || !toggle || !caps) return;
  toggle.addEventListener('click', () => {
    const show = password.type === 'password';
    password.type = show ? 'text' : 'password';
    toggle.textContent = show ? 'Hide' : 'Show';
    toggle.setAttribute('aria-label', show ? 'Hide password' : 'Show password');
    toggle.setAttribute('aria-pressed', String(show));
  });
  const checkCaps = event => caps.classList.toggle('hidden', !event.getModifierState('CapsLock'));
  password.addEventListener('keydown', checkCaps);
  password.addEventListener('keyup', checkCaps);
  password.addEventListener('blur', () => caps.classList.add('hidden'));
});
