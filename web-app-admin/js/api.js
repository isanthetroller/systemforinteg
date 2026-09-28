/**
 * SecurePark - Web Admin API Client
 * Seamlessly interfaces with InfinityFree PHP/MySQL backend
 * With automatic InfinityFree cookie challenge solver and offline local caching
 */

const ApiClient = (function() {
  // Base URL for API endpoints. Defaults to './api'
  let baseUrl = (window.SECUREPARK_API_URL || './api').replace(/\/+$/, '');

  function toNumbers(d) {
    const e = [];
    d.replace(/(..)/g, function(h) {
      e.push(parseInt(h, 16));
    });
    return e;
  }

  function toHex(bytes) {
    let s = '';
    for (let i = 0; i < bytes.length; i++) {
      let h = bytes[i].toString(16);
      if (h.length < 2) h = '0' + h;
      s += h;
    }
    return s;
  }

  function solveInfinityFreeChallenge(html) {
    if (typeof slowAES === 'undefined') return false;
    try {
      const matchA = html.match(/a=toNumbers\(["']([0-9a-fA-F]+)["']\)/);
      const matchB = html.match(/b=toNumbers\(["']([0-9a-fA-F]+)["']\)/);
      const matchC = html.match(/c=toNumbers\(["']([0-9a-fA-F]+)["']\)/);
      if (matchA && matchB && matchC) {
        const a = toNumbers(matchA[1]);
        const b = toNumbers(matchB[1]);
        const c = toNumbers(matchC[1]);
        const decrypted = slowAES.decrypt(c, 2, a, b);
        const cookieVal = toHex(decrypted);
        document.cookie = `__test=${cookieVal}; max-age=86400; path=/; SameSite=Lax`;
        console.info('[ApiClient] Solved InfinityFree __test security challenge cookie.');
        return true;
      }
    } catch (err) {
      console.warn('[ApiClient] Challenge solver exception:', err);
    }
    return false;
  }

  /* ------------------------------------------------------------------------
     Session token (bearer). Kept in sessionStorage so closing the browser
     on a shared gate PC ends the session.
     ------------------------------------------------------------------------ */
  const TOKEN_KEY = 'sp_staff_token';
  const CACHE_KEYS = ['sp_cache_stats', 'sp_cache_vehicles', 'sp_cache_logs', 'sp_cache_incidents'];

  function getToken() {
    try { return sessionStorage.getItem(TOKEN_KEY); } catch (_) { return null; }
  }
  function setToken(token) {
    try { sessionStorage.setItem(TOKEN_KEY, token); } catch (_) {}
  }
  function clearToken() {
    try { sessionStorage.removeItem(TOKEN_KEY); } catch (_) {}
  }
  function clearCache() {
    CACHE_KEYS.forEach(k => { try { localStorage.removeItem(k); } catch (_) {} });
  }

  // Errors caused by auth must never be masked by the offline cache
  function isAuthError(err) {
    return err && (err.status === 401 || err.status === 403);
  }

  async function request(endpoint, options = {}, retries = 1) {
    const url = `${baseUrl}/${endpoint.replace(/^\/+/, '')}`;
    const headers = {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      ...(options.headers || {})
    };

    const token = getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
      headers['X-Auth-Token'] = token; // fallback for hosts that strip Authorization
    }

    if (options.body && typeof options.body === 'object' && !(options.body instanceof FormData)) {
      headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(options.body);
    }

    let res, text;
    try {
      res = await fetch(url, { ...options, headers, credentials: 'include' });
      text = await res.text();
    } catch (err) {
      console.warn(`[ApiClient] Request to ${endpoint} failed:`, err.message);
      throw err;
    }

    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_) {
      // If InfinityFree testcookie challenge page is returned, auto-solve it
      if (text.includes('toNumbers') && retries > 0) {
        const solved = solveInfinityFreeChallenge(text);
        if (solved) {
          await new Promise(r => setTimeout(r, 150));
          return request(endpoint, options, retries - 1);
        }
      }
      if (text.includes('<!DOCTYPE') || text.includes('<html')) {
        throw new Error('API server returned HTML. Check InfinityFree DB connection or domain.');
      }
      throw new Error(`Unexpected API response from ${endpoint}`);
    }

    if (!res.ok) {
      const err = new Error(json.message || `HTTP ${res.status}`);
      err.status = res.status;
      err.code = json.data && json.data.code ? json.data.code : null;
      err.data = json.data || null;

      if (res.status === 401 && !endpoint.startsWith('auth.php?action=login')) {
        clearToken();
        window.dispatchEvent(new CustomEvent('sp:auth-required', { detail: { message: err.message } }));
      } else if (res.status === 403 && err.code === 'PASSWORD_CHANGE_REQUIRED') {
        window.dispatchEvent(new CustomEvent('sp:password-change-required'));
      }
      throw err;
    }
    return json;
  }

  return {
    getBaseUrl: () => baseUrl,
    setBaseUrl: (url) => { baseUrl = url.replace(/\/+$/, ''); },
    hasToken: () => !!getToken(),
    clearCache,

    // Authentication
    login: async (username, password) => {
      const res = await request('auth.php?action=login', { method: 'POST', body: { username, password } });
      setToken(res.data.token);
      return res.data.user;
    },

    logout: async () => {
      try { await request('auth.php?action=logout', { method: 'POST' }); } catch (_) {}
      clearToken();
      clearCache();
    },

    me: async () => {
      const res = await request('auth.php?action=me');
      return res.data.user;
    },

    changePassword: async (currentPassword, newPassword) => {
      const res = await request('auth.php?action=change_password', {
        method: 'POST',
        body: { current_password: currentPassword, new_password: newPassword }
      });
      return res.data;
    },

    // Staff Accounts (admin only)
    getUsers: async () => {
      const res = await request('users.php');
      return res.data;
    },

    createUser: async (payload) => {
      const res = await request('users.php', { method: 'POST', body: payload });
      return res.data;
    },

    updateUser: async (id, action, payload = {}) => {
      const res = await request('users.php', { method: 'PUT', body: { id, action, ...payload } });
      return res.data;
    },

    // Metrics & KPIs
    getStats: async () => {
      try {
        const res = await request('stats.php');
        try { localStorage.setItem('sp_cache_stats', JSON.stringify(res.data)); } catch (_) {}
        return res.data;
      } catch (err) {
        if (isAuthError(err)) throw err;
        try {
          const cached = localStorage.getItem('sp_cache_stats');
          if (cached) return JSON.parse(cached);
        } catch (_) {}
        throw err;
      }
    },

    // Vehicle Directory
    getVehicles: async (params = {}) => {
      const qs = new URLSearchParams(params).toString();
      try {
        const res = await request(`vehicles.php${qs ? '?' + qs : ''}`);
        if (res.data && !qs) {
          try { localStorage.setItem('sp_cache_vehicles', JSON.stringify(res.data)); } catch (_) {}
        }
        return res.data;
      } catch (err) {
        if (!qs && !isAuthError(err)) {
          try {
            const cached = localStorage.getItem('sp_cache_vehicles');
            if (cached) {
              console.info('[ApiClient] Using cached vehicle fleet data.');
              return JSON.parse(cached);
            }
          } catch (_) {}
        }
        throw err;
      }
    },

    getVehicleByPlate: async (plate) => {
      const res = await request(`vehicles.php?plate=${encodeURIComponent(plate)}`);
      return res.data;
    },

    registerVehicle: async (payload) => {
      const res = await request('vehicles.php', {
        method: 'POST',
        body: payload
      });
      return res.data;
    },

    toggleVehicleStatus: async (id) => {
      const res = await request('vehicles.php', {
        method: 'PUT',
        body: { id: id, action: 'toggle_status' }
      });
      return res.data;
    },

    updateVehicle: async (id, data) => {
      const res = await request('vehicles.php', {
        method: 'PUT',
        body: { id: id, ...data }
      });
      return res.data;
    },

    // Signed passes (admin): new pass id, all previous QR codes revoked
    reissuePass: async (vehicleId, validUntil = '') => {
      const res = await request('passes.php', {
        method: 'POST',
        body: { vehicle_id: vehicleId, action: 'reissue', valid_until: validUntil }
      });
      return res.data;
    },

    // Gate verification: { qrCode } or { plate }, gateType 'Ingress' | 'Egress'
    verifyPass: async ({ qrCode = '', plate = '' }, gateType = 'Ingress') => {
      const res = await request('verify.php', {
        method: 'POST',
        body: { qr_code: qrCode, plate: plate, gate_type: gateType }
      });
      return res.data;
    },

    // Violations & 3-strike policy
    getViolations: async (params = {}) => {
      const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== '' && v != null)).toString();
      const res = await request(`violations.php${qs ? '?' + qs : ''}`);
      return res.data;
    },

    // { vehicle_id | plate, type, severity, notes } -> { violation, strikes, banned, vehicle, ... }
    createViolation: async (payload) => {
      const res = await request('violations.php', { method: 'POST', body: payload });
      return { ...res.data, message: res.message };
    },

    // { violation_id, action: 'resolve' | 'dismiss', notes } or { vehicle_id, action: 'reset', notes }
    updateViolation: async (payload) => {
      const res = await request('violations.php', { method: 'PUT', body: payload });
      return { ...res.data, message: res.message };
    },

    // Overtime / overnight parking (server records at most one strike per vehicle per night)
    runOvernightCheck: async () => {
      const res = await request('overnight_check.php', { method: 'POST', body: {} });
      return { ...res.data, message: res.message };
    },

    flagOvernight: async (vehicleId) => {
      const res = await request('overnight_check.php', { method: 'POST', body: { vehicle_id: vehicleId } });
      return { ...res.data, message: res.message };
    },

    // Visitor day passes (valid only on the day issued; server sets the date)
    getVisitorPasses: async (date = '') => {
      const res = await request(`visitors.php${date ? '?date=' + encodeURIComponent(date) : ''}`);
      return res.data;
    },

    createVisitorPass: async (payload) => {
      const res = await request('visitors.php', { method: 'POST', body: payload });
      return { pass: res.data, message: res.message };
    },

    getVisitorPass: async (id) => {
      const res = await request(`visitors.php?id=${encodeURIComponent(id)}`);
      return res.data;
    },

    // Registered vehicles inside campus + visitors who entered and have not left
    getOnCampus: async () => {
      const res = await request('oncampus.php');
      return res.data;
    },

    revokeVisitorPass: async (id) => {
      const res = await request('visitors.php', { method: 'PUT', body: { id, action: 'revoke' } });
      return { pass: res.data, message: res.message };
    },

    // Student portal login for a vehicle owner (admin): creates it or resets the password
    issueStudentLogin: async (ownerIdNumber) => {
      const res = await request('students.php', { method: 'POST', body: { owner_id_number: ownerIdNumber, action: 'issue' } });
      return { ...res.data, message: res.message };
    },

    deleteVehicle: async (id) => {
      const res = await request(`vehicles.php?id=${id}`, {
        method: 'DELETE'
      });
      return res.data;
    },

    // Gate Audit Logs
    getLogs: async (params = {}) => {
      const qs = new URLSearchParams(params).toString();
      try {
        const res = await request(`logs.php${qs ? '?' + qs : ''}`);
        if (res.data && !qs) {
          try { localStorage.setItem('sp_cache_logs', JSON.stringify(res.data)); } catch (_) {}
        }
        return res.data;
      } catch (err) {
        if (!qs && !isAuthError(err)) {
          try {
            const cached = localStorage.getItem('sp_cache_logs');
            if (cached) return JSON.parse(cached);
          } catch (_) {}
        }
        throw err;
      }
    },

    createLog: async (logData) => {
      const res = await request('logs.php', {
        method: 'POST',
        body: logData
      });
      return res.data;
    },

    // Security Incidents
    getIncidents: async (status = '') => {
      const qs = status ? `?status=${encodeURIComponent(status)}` : '';
      try {
        const res = await request(`incidents.php${qs}`);
        if (res.data && !qs) {
          try { localStorage.setItem('sp_cache_incidents', JSON.stringify(res.data)); } catch (_) {}
        }
        return res.data;
      } catch (err) {
        if (!qs && !isAuthError(err)) {
          try {
            const cached = localStorage.getItem('sp_cache_incidents');
            if (cached) return JSON.parse(cached);
          } catch (_) {}
        }
        throw err;
      }
    },

    createIncident: async (incidentData) => {
      const res = await request('incidents.php', {
        method: 'POST',
        body: incidentData
      });
      return res.data;
    },

    resolveIncident: async (id, notes = '') => {
      const res = await request('incidents.php', {
        method: 'PUT',
        body: { id: id, notes: notes }
      });
      return res.data;
    },

    // System Settings & Pass Rules
    getSettings: async () => {
      const res = await request('settings.php');
      return res.data;
    },

    updateSettings: async (settings) => {
      const res = await request('settings.php', {
        method: 'POST',
        body: settings
      });
      return res.data;
    }
  };
})();

// Export globally
window.ApiClient = ApiClient;
