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

  async function request(endpoint, options = {}, retries = 1) {
    const url = `${baseUrl}/${endpoint.replace(/^\/+/, '')}`;
    const headers = {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      ...(options.headers || {})
    };

    if (options.body && typeof options.body === 'object' && !(options.body instanceof FormData)) {
      headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(options.body);
    }

    try {
      const res = await fetch(url, { ...options, headers, credentials: 'include' });
      const text = await res.text();
      
      // Attempt JSON parse
      try {
        const json = JSON.parse(text);
        if (!res.ok) {
          throw new Error(json.message || `HTTP ${res.status}`);
        }
        return json;
      } catch (e) {
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
        throw e;
      }
    } catch (err) {
      console.warn(`[ApiClient] Request to ${endpoint} failed:`, err.message);
      throw err;
    }
  }

  return {
    getBaseUrl: () => baseUrl,
    setBaseUrl: (url) => { baseUrl = url.replace(/\/+$/, ''); },

    // Metrics & KPIs
    getStats: async () => {
      try {
        const res = await request('stats.php');
        try { localStorage.setItem('sp_cache_stats', JSON.stringify(res.data)); } catch (_) {}
        return res.data;
      } catch (err) {
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
        if (!qs) {
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
        if (!qs) {
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
        if (!qs) {
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

    resolveIncident: async (id) => {
      const res = await request('incidents.php', {
        method: 'PUT',
        body: { id: id }
      });
      return res.data;
    }
  };
})();

// Export globally
window.ApiClient = ApiClient;
