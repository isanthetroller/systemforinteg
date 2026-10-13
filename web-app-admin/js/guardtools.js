/**
 * SecurePark - small tools the guard's Gate Monitor shares (admin web)
 *
 *   SPPhoto     Take or choose a photo, shrink it, and send it as evidence with a gate record, violation or case
 *               (the same evidence.php the phone uses). A photo that cannot be sent never blocks the record it belongs to.
 *   SPFeedback  The scan sound and vibration: one tone for cleared, two for a warning, a low one for refused.
 */
(function () {
  'use strict';
  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  /* ------------------------------------------------------------------------ photos */
  const MAX_SIDE = 800;
  const QUALITY = 0.72;

  /** File -> JPEG data URL, longest side at most 800 px (a few hundred KB at most; the server accepts 600 KB). */
  function shrink(file) {
    return new Promise((resolve, reject) => {
      if (!file || !/^image\//.test(file.type)) return reject(new Error('Choose a photo (an image file).'));
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, MAX_SIDE / Math.max(img.width, img.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(img.width * scale));
        canvas.height = Math.max(1, Math.round(img.height * scale));
        canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
        URL.revokeObjectURL(url);
        resolve(canvas.toDataURL('image/jpeg', QUALITY));
      };
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('That photo could not be read.')); };
      img.src = url;
    });
  }

  /**
   * A small "Add photo" control. Returns { el, get(), reset() }: put `el` in a form, read the photo with get() (a data URL
   * or null) when the guard presses the form's own button.
   */
  function field(label = 'Add photo') {
    const el = document.createElement('div');
    el.className = 'sp-photo-field flex items-center gap-2 flex-wrap';
    el.innerHTML = `
      <input type="file" accept="image/*" capture="environment" class="hidden" data-input>
      <button type="button" data-pick class="px-2.5 py-1.5 rounded border border-slate-300 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 cursor-pointer">${esc(label)}</button>
      <img data-thumb alt="Photo to send" class="hidden w-12 h-12 rounded border border-slate-200 object-cover">
      <button type="button" data-remove class="hidden text-[11px] font-semibold text-rose-600 hover:underline cursor-pointer">Remove</button>
      <span data-msg class="text-[11px] text-slate-500"></span>`;
    const input = el.querySelector('[data-input]');
    const thumb = el.querySelector('[data-thumb]');
    const remove = el.querySelector('[data-remove]');
    const msg = el.querySelector('[data-msg]');
    let image = null;
    const set = (value, note = '') => {
      image = value;
      thumb.src = value || '';
      thumb.classList.toggle('hidden', !value);
      remove.classList.toggle('hidden', !value);
      msg.textContent = note;
    };
    el.querySelector('[data-pick]').addEventListener('click', () => input.click());
    remove.addEventListener('click', () => { input.value = ''; set(null); });
    input.addEventListener('change', async () => {
      const file = input.files && input.files[0];
      if (!file) return;
      try { set(await shrink(file), 'Photo ready'); } catch (err) { set(null, err.message); }
    });
    return { el, get: () => image, reset: () => { input.value = ''; set(null); } };
  }

  /**
   * Sends one photo with the record it belongs to. Never throws: resolves null on success (or when there is no photo),
   * otherwise with a short message for the guard.
   */
  async function send(kind, plate, image, ids = {}) {
    if (!image) return null;
    try {
      await ApiClient.uploadEvidence({ kind, plate, image, ...ids });
      return null;
    } catch (err) {
      return (err && err.message) || 'The photo could not be sent.';
    }
  }

  /* ------------------------------------------------------------------------ scan sound */
  const SOUND_KEY = 'sp_gate_sound';
  let audio = null;

  function isOn() {
    try { return localStorage.getItem(SOUND_KEY) !== 'off'; } catch (_) { return true; }
  }
  function setOn(on) {
    try { localStorage.setItem(SOUND_KEY, on ? 'on' : 'off'); } catch (_) {}
  }
  function tone(freq, start, length, volume = 0.18) {
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(volume, audio.currentTime + start);
    gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + start + length);
    osc.connect(gain);
    gain.connect(audio.destination);
    osc.start(audio.currentTime + start);
    osc.stop(audio.currentTime + start + length + 0.02);
  }
  /** kind: 'ok' (cleared / saved), 'warn' (check before allowing), 'deny' (refused). */
  function play(kind) {
    if (!isOn()) return;
    try {
      audio = audio || new (window.AudioContext || window.webkitAudioContext)();
      if (audio.state === 'suspended') audio.resume();
      if (kind === 'ok') tone(880, 0, 0.14);
      else if (kind === 'warn') { tone(660, 0, 0.12); tone(660, 0.2, 0.12); }
      else tone(220, 0, 0.45, 0.22);
      if (navigator.vibrate) navigator.vibrate(kind === 'ok' ? 60 : kind === 'warn' ? [80, 60, 80] : [200, 80, 200]);
    } catch (_) { /* no audio on this device: the screen colours still say it */ }
  }

  window.SPPhoto = { field, send, shrink };
  window.SPFeedback = { play, isOn, setOn };
})();
