/**
 * SecurePark Student Portal - API client
 * Bearer-token session (kept on this device), InfinityFree anti-bot challenge solver.
 */
const StudentApi = (function () {
  const baseUrl = String(window.SECUREPARK_API_URL || '../api').replace(/\/+$/, '');
  const TOKEN_KEY = 'sp_student_token';

  function getToken() { try { return localStorage.getItem(TOKEN_KEY); } catch (_) { return null; } }
  function setToken(t) { try { localStorage.setItem(TOKEN_KEY, t); } catch (_) {} }
  function clearToken() { try { localStorage.removeItem(TOKEN_KEY); } catch (_) {} }

  // InfinityFree serves an AES "testcookie" page to new visitors; solve it once and retry
  function toNumbers(d) { const e = []; d.replace(/(..)/g, h => { e.push(parseInt(h, 16)); }); return e; }
  function toHex(bytes) { return Array.from(bytes, b => (b < 16 ? '0' : '') + b.toString(16)).join(''); }
  function solveChallenge(html) {
    if (typeof slowAES === 'undefined') return false;
    const a = html.match(/a=toNumbers\(["']([0-9a-fA-F]+)["']\)/);
    const b = html.match(/b=toNumbers\(["']([0-9a-fA-F]+)["']\)/);
    const c = html.match(/c=toNumbers\(["']([0-9a-fA-F]+)["']\)/);
    if (!a || !b || !c) return false;
    try {
      const cookie = toHex(slowAES.decrypt(toNumbers(c[1]), 2, toNumbers(a[1]), toNumbers(b[1])));
      document.cookie = `__test=${cookie}; max-age=86400; path=/; SameSite=Lax`;
      return true;
    } catch (_) {
      return false;
    }
  }

  async function request(path, options = {}, retries = 1) {
    const headers = { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' };
    const token = getToken();
    if (token) {
      headers.Authorization = `Bearer ${token}`;
      headers['X-Auth-Token'] = token;
    }
    let body;
    if (options.body !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(options.body);
    }

    const res = await fetch(`${baseUrl}/${path}`, { method: options.method || 'GET', headers, body, credentials: 'include' });
    const text = await res.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch (_) {
      if (text.includes('toNumbers') && retries > 0 && solveChallenge(text)) {
        await new Promise(r => setTimeout(r, 150));
        return request(path, options, retries - 1);
      }
      throw new Error('The server is not responding correctly. Please try again later.');
    }

    if (!res.ok) {
      const err = new Error(json.message || `Request failed (${res.status})`);
      err.status = res.status;
      err.code = json.data && json.data.code ? json.data.code : null;
      if (res.status === 401 && !path.startsWith('auth.php?action=login')) {
        clearToken();
        window.dispatchEvent(new CustomEvent('sp:signed-out', { detail: { message: 'Your session has ended. Please sign in again.' } }));
      } else if (res.status === 403 && err.code === 'PASSWORD_CHANGE_REQUIRED') {
        window.dispatchEvent(new CustomEvent('sp:password-change-required'));
      }
      throw err;
    }
    return json;
  }

  return {
    hasToken: () => !!getToken(),

    async login(studentId, password) {
      const res = await request('auth.php?action=login&realm=student', { method: 'POST', body: { username: studentId, password } });
      setToken(res.data.token);
      return res.data.student;
    },

    async logout() {
      try { await request('auth.php?action=logout', { method: 'POST', body: {} }); } catch (_) {}
      clearToken();
    },

    async me() { return (await request('student.php?action=me')).data; },
    async vehicles() { return (await request('student.php?action=vehicles')).data; },
    async violations() { return (await request('student.php?action=violations')).data; },
    async activity() { return (await request('student.php?action=activity')).data; },

    async changePassword(current, next) {
      return request('auth.php?action=change_password', { method: 'POST', body: { current_password: current, new_password: next } });
    }
  };
})();
