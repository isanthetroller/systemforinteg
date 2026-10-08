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

    const originalBody = options.body; // request() turns the body into a string below; a retry needs the object
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
      // Say what came back (status and the first characters) so a server problem can be diagnosed from the message
      const peek = String(text || '').replace(/\s+/g, ' ').trim().slice(0, 120);
      throw new Error(`Unexpected API response from ${endpoint} (HTTP ${res.status}${peek ? ': ' + peek : ', empty reply'})`);
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

      // The server wants a written reason (audit trail) or a decision about the one-vehicle-per-class rule:
      // ask the administrator, then repeat the same request with the answer.
      if (!options._asked && window.SPOps && (err.code === 'REASON_REQUIRED' || err.code === 'OWNER_CLASS_LIMIT')) {
        const method = (options.method || 'GET').toUpperCase();
        const extra = err.code === 'REASON_REQUIRED'
          ? await window.SPOps.askReason(err.message)
          : await window.SPOps.askClassLimit(err, method === 'POST' && /^vehicles\.php/.test(endpoint));
        if (extra) {
          const next = { ...options, _asked: true };
          let nextEndpoint = endpoint;
          if (method === 'DELETE') {
            nextEndpoint += (endpoint.includes('?') ? '&' : '?') + new URLSearchParams(extra);
          } else {
            let body = originalBody;
            if (typeof body === 'string') { try { body = JSON.parse(body); } catch (_) { body = {}; } }
            next.body = { ...(body || {}), ...extra };
          }
          return request(nextEndpoint, next, retries);
        }
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

    // Cashier (admin only)
    getUnpaidVehicles: async () => {
      const res = await request('payments.php?view=unpaid');
      return res.data;
    },

    getPayments: async ({ q = '', status = '', method = '' } = {}) => {
      const params = new URLSearchParams();
      if (q) params.set('q', q);
      if (status) params.set('status', status);
      if (method) params.set('method', method);
      const res = await request('payments.php' + (params.toString() ? '?' + params : ''));
      return res.data;
    },

    receiveCashPayment: async (vehicleId, tendered) => {
      const res = await request('payments.php', { method: 'POST', body: { action: 'cash', vehicleId, tendered } });
      return res.data;
    },

    // Renewals (admin): cashier renewal list, cash / free / bulk renewal
    getRenewals: async () => (await request('renewals.php')).data,
    renewPass: async (vehicleId, action, tendered) => {
      const res = await request('renewals.php', { method: 'POST', body: { action, vehicleId, tendered } });
      return { ...res.data, message: res.message };
    },
    renewBulk: async (vehicleIds, cashCollected) => {
      const res = await request('renewals.php', { method: 'POST', body: { action: 'bulk', vehicleIds, cashCollected } });
      return { ...res.data, message: res.message };
    },

    // Retire a vehicle without replacing it (admin; the server asks for a reason)
    retireVehicle: async (id) => {
      const res = await request('vehicles.php', { method: 'PUT', body: { id, action: 'retire' } });
      return res.data;
    },

    // One-time exit for a vehicle on hold (admin; reason required)
    releaseExit: async (vehicleId, reason) => {
      const res = await request('releases.php', { method: 'POST', body: { vehicleId, reason } });
      return { ...res.data, message: res.message };
    },
    getReleases: async () => (await request('releases.php')).data,
    cancelRelease: async (id) => (await request(`releases.php?id=${id}`, { method: 'DELETE' })).data,

    // Cases: violations and security incidents as one process
    getCases: async (params = {}) => {
      const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== '' && v != null)).toString();
      return (await request(`cases.php${qs ? '?' + qs : ''}`)).data;
    },
    // Downloads the matching cases as a CSV file (admin)
    exportCases: async (params = {}) => {
      const qs = new URLSearchParams(Object.entries({ ...params, format: 'csv' }).filter(([, v]) => v !== '' && v != null)).toString();
      const token = getToken();
      const res = await fetch(`${baseUrl}/cases.php?${qs}`, { headers: token ? { 'Authorization': `Bearer ${token}`, 'X-Auth-Token': token } : {}, credentials: 'include' });
      if (!res.ok || !(res.headers.get('Content-Type') || '').includes('csv')) {
        let msg = `Could not export (HTTP ${res.status}).`;
        try { msg = (await res.json()).message || msg; } catch (_) {}
        throw new Error(msg);
      }
      return res.blob();
    },
    getCase: async (key) => (await request(`cases.php?key=${encodeURIComponent(key)}`)).data,
    caseAction: async (key, action, fields = {}) => {
      const res = await request('cases.php', { method: 'POST', body: { key, action, ...fields } });
      return { ...res.data, message: res.message };
    },

    // Admin Center: activity log, approvals, guard duty, settings
    getAuditLog: async (params = {}) => {
      const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== '' && v != null)).toString();
      return (await request(`audit.php${qs ? '?' + qs : ''}`)).data;
    },
    getApprovals: async (status = '') => (await request(`approvals.php${status ? '?status=' + encodeURIComponent(status) : ''}`)).data,
    decideApproval: async (id, decision, note = '') => {
      const res = await request('approvals.php', { method: 'POST', body: { id, decision, note } });
      return { ...res.data, message: res.message };
    },
    getSettings: async () => (await request('settings.php?scope=all')).data,
    saveSettings: async (values) => (await request('settings.php', { method: 'PUT', body: values })).data,
    getShifts: async () => (await request('shifts.php')).data,
    getShiftReport: async (from = '', to = '') => (await request(`shifts.php?scope=report${from ? '&from=' + from : ''}${to ? '&to=' + to : ''}`)).data,
    getEvidence: async (params) => (await request('evidence.php?' + new URLSearchParams(params))).data,
    getEvidencePhoto: async (id) => (await request(`evidence.php?id=${id}`)).data,
    // Sends one test e-mail through the server's SMTP account (admin). Resolves with the server's message, rejects with the reason.
    sendTestMail: async (to) => {
      const res = await request('mail_test.php', { method: 'POST', body: { to } });
      return { ...res.data, message: res.message };
    },
    runMaintenance: async () => { try { return (await request('maintenance.php', { method: 'POST', body: {} })).data; } catch (_) { return null; } },

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

    // Violations (a pending violation blocks the vehicle's entry and exit)
    getViolations: async (params = {}) => {
      const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== '' && v != null)).toString();
      const res = await request(`violations.php${qs ? '?' + qs : ''}`);
      return res.data;
    },

    // { vehicle_id | plate, type, notes } -> { violation, onHold, vehicle, ... }
    createViolation: async (payload) => {
      const res = await request('violations.php', { method: 'POST', body: payload });
      return { ...res.data, message: res.message };
    },

    // { violation_id, action: 'resolve' | 'dismiss', notes }
    updateViolation: async (payload) => {
      const res = await request('violations.php', { method: 'PUT', body: payload });
      return { ...res.data, message: res.message };
    },

    // Overtime / overnight parking list (nothing is recorded automatically)
    runOvernightCheck: async () => {
      const res = await request('overnight_check.php', { method: 'POST', body: {} });
      return { ...res.data, message: res.message };
    },

    flagOvernight: async (vehicleId) => {
      const res = await request('overnight_check.php', { method: 'POST', body: { vehicle_id: vehicleId } });
      return { ...res.data, message: res.message };
    },

    // Visitor day passes (supports date, upcoming, search, status, or params object)
    getVisitorPasses: async (dateOrParams = '', upcoming = false) => {
      let query = '';
      if (typeof dateOrParams === 'object' && dateOrParams !== null) {
        query = new URLSearchParams(dateOrParams).toString();
      } else if (upcoming) {
        query = 'upcoming=1';
      } else if (dateOrParams) {
        query = 'date=' + encodeURIComponent(dateOrParams);
      }
      const res = await request(`visitors.php${query ? '?' + query : ''}`);
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
    }
  };
})();

// Export globally
window.ApiClient = ApiClient;
