/**
 * SecurePark - On Campus Now
 *
 * Professional Real-Time Physical Vehicle Custody Data Table with Side Details Drawer.
 *
 * Scannable, compact data table displaying active vehicles and visitors on campus.
 * Selecting any vehicle opens a dedicated right-side details drawer that preserves
 * full visibility of the data table while providing rich custody & security context.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const STRIKE_LIMIT = 3;
  const view = {
    data: null,
    filter: 'all',
    incidentTarget: null,
    selectedKey: null
  };

  const esc = (v) => (window.SP ? SP.escapeHtml(v == null ? '' : String(v)) : String(v == null ? '' : v));

  function fmtTime(value) {
    if (!value) return '—';
    const d = new Date(String(value).replace(' ', 'T') + '+08:00');
    if (isNaN(d)) return esc(value);
    const sameDay = d.toDateString() === new Date().toDateString();
    return esc(d.toLocaleString('en-PH', sameDay
      ? { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit' }
      : { timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }));
  }

  function duration(hours) {
    if (hours == null) return '—';
    if (hours < 1) return `${Math.max(1, Math.round(hours * 60))}m`;
    const h = Math.floor(hours);
    const m = Math.round((hours - h) * 60);
    return m ? `${h}h ${m}m` : `${h}h`;
  }

  // Arrival order: earliest entry first, no recorded entry last, ties keep server order
  function arrivalKey(x) {
    return x.entryTime ? new Date(String(x.entryTime).replace(' ', 'T') + '+08:00').getTime() : Infinity;
  }

  function tel(phone) {
    const digits = String(phone || '').replace(/[^\d+]/g, '');
    return digits
      ? `<a href="tel:${esc(digits)}" class="font-mono text-ncst-navy font-semibold hover:underline">${esc(phone)}</a>`
      : '<span class="text-slate-400">No contact on file</span>';
  }

  function clipButton(x, plate, action) {
    return window.SPClip
      ? SPClip.button({ logId: x.entryLogId, plate, action, loggedAt: x.entryTime, gatePoint: x.entryGate }, 'Entry clip')
      : '';
  }

  function itemsHtml(items) {
    if (!items || !items.length) {
      return `<div class="p-3 rounded-lg bg-slate-50/70 border border-slate-100 text-xs text-slate-500">
        <span class="font-semibold text-slate-600">Declared items:</span> None recorded
      </div>`;
    }
    return `<div class="p-3 rounded-lg bg-slate-50/70 border border-slate-100">
      <div class="text-[10px] font-extrabold uppercase tracking-wider text-slate-400 mb-1.5">Items brought into campus:</div>
      <div class="flex flex-wrap items-center gap-1.5">
        ${items.map(i => `<span class="inline-flex items-center gap-1 px-2.5 py-1 rounded-md bg-white border border-slate-200 text-slate-800 text-xs font-semibold shadow-2xs"><span class="font-mono text-ncst-navy font-bold">${esc(i.quantity)}&times;</span> ${esc(i.name)}${i.description ? `<span class="text-slate-400 font-normal">(${esc(i.description)})</span>` : ''}</span>`).join('')}
      </div>
    </div>`;
  }

  /* ---------------- Single Clear Status Pill ---------------- */
  function getStatusBadge(item, kind) {
    if (item.activeHold || item.exitDenied) {
      return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-extrabold bg-rose-100 text-rose-800 border border-rose-300" title="Active Security Hold / Exit Blocked">Blocked</span>';
    }
    if (kind === 'vehicle') {
      if (item.isBanned) return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-extrabold bg-rose-100 text-rose-800 border border-rose-300">Banned</span>';
      if (item.timeFlag === 'overnight') return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-bold bg-indigo-50 text-indigo-800 border border-indigo-200">Overnight</span>';
      if (item.timeFlag === 'overtime') return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-bold bg-amber-50 text-amber-800 border border-amber-300">Overtime</span>';
      if (item.isVip) return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-bold bg-amber-50 text-amber-800 border border-amber-200">VIP</span>';
      const n = Math.min(Number(item.warningCount || 0), STRIKE_LIMIT);
      if (n > 0) return `<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-bold bg-amber-50 text-amber-800 border border-amber-300">Strike ${n}/${STRIKE_LIMIT}</span>`;
      return '<span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-medium text-slate-600 bg-slate-100 border border-slate-200/80"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>Inside</span>';
    } else {
      if (item.revoked) return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-extrabold bg-rose-100 text-rose-800 border border-rose-300">Cancelled</span>';
      if (item.overstayed) return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-extrabold bg-rose-100 text-rose-800 border border-rose-300">Expired</span>';
      return '<span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-medium text-slate-600 bg-slate-100 border border-slate-200/80"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>Inside</span>';
    }
  }

  /* ---------------- data ---------------- */
  async function load() {
    try {
      view.data = await ApiClient.getOnCampus();
      updateBadge();
      if ($('onCampusView').classList.contains('active')) render();
    } catch (err) {
      if (err.status !== 401 && $('onCampusView').classList.contains('active')) {
        const tbody = $('ocTableBody');
        if (tbody) {
          tbody.innerHTML = `<tr><td colspan="8" class="px-4 py-8 text-center text-xs text-ncst-crimson font-medium">${esc(err.message)}</td></tr>`;
        }
      }
    }
  }

  function updateBadge() {
    const badge = $('onCampusSidebarCount');
    if (badge && view.data) badge.textContent = view.data.counts.total;
  }

  /* ---------------- render ---------------- */
  function render() {
    const d = view.data;
    if (!d) return;

    $('ocTotal').textContent = d.counts.total;
    $('ocRegistered').textContent = d.counts.registered;
    $('ocVisitors').textContent = d.counts.visitors;
    $('ocAttention').textContent = d.counts.flagged + d.vehicles.filter(v => (v.warningCount > 0 || v.isBanned) && !v.timeFlag).length;
    $('onCampusUpdated').textContent = `Updated ${fmtTime(d.now)}`;

    document.querySelectorAll('#ocFilter .oc-filter').forEach(b => {
      const on = b.dataset.filter === view.filter;
      b.setAttribute('aria-selected', on ? 'true' : 'false');
      b.className = 'oc-filter px-3 py-1.5 rounded-md cursor-pointer transition-all ' +
        (on ? 'bg-white text-ncst-navy font-bold shadow-xs' : 'text-slate-600 hover:text-slate-900 font-semibold');
    });

    const q = ($('ocSearch').value || '').trim().toLowerCase();
    const match = (...fields) => !q || fields.some(f => String(f || '').toLowerCase().includes(q));

    const vehicles = d.vehicles.filter(v =>
      (view.filter === 'all' || view.filter === 'registered' || (view.filter === 'attention' && (v.timeFlag || v.warningCount > 0 || v.isBanned || v.activeHold || v.exitDenied))) &&
      match(v.plateNumber, v.ownerName, v.enteredBy, v.makeModelColor, v.department));

    const visitors = d.visitors.filter(p =>
      (view.filter === 'all' || view.filter === 'visitors' || (view.filter === 'attention' && (p.overstayed || p.revoked || p.activeHold || p.exitDenied))) &&
      match(p.plateNumber, p.visitorName, p.personToVisit, p.purposeOfVisit));

    // Combined arrival order
    const arrival = [...d.vehicles.map(v => ({ kind: 'vehicle', item: v })), ...d.visitors.map(p => ({ kind: 'visitor', item: p }))]
      .map((entry, i) => ({ ...entry, i, t: arrivalKey(entry.item) }))
      .sort((a, b) => (a.t === b.t ? a.i - b.i : a.t - b.t));

    const rank = new Map(arrival.map((entry, n) => [entry.item, n + 1]));
    const shown = new Set([...vehicles, ...visitors]);
    const filteredEntries = arrival.filter(entry => shown.has(entry.item));

    const tbody = $('ocTableBody');
    const emptyState = $('ocEmptyState');
    const summary = $('ocTableSummary');

    if (!filteredEntries.length) {
      if (tbody) tbody.innerHTML = '';
      if (emptyState) {
        emptyState.classList.remove('hidden');
        $('ocEmptyTitle').textContent = d.counts.total ? 'No vehicles match this filter' : 'Campus is empty';
        $('ocEmptySubtitle').textContent = d.counts.total ? 'Try selecting another filter tab or clearing the search query.' : 'Vehicles appear here as soon as their entry is recorded at the gate.';
      }
      if (summary) summary.textContent = 'Showing 0 vehicles inside campus';
      closeDrawer();
      return;
    }

    if (emptyState) emptyState.classList.add('hidden');
    if (summary) summary.textContent = `Showing ${filteredEntries.length} of ${d.counts.total} vehicles inside campus`;

    // Check if previously selected entry is still visible in filtered entries
    let activeEntry = null;
    let activeRank = 0;
    if (view.selectedKey) {
      filteredEntries.forEach(entry => {
        const k = entry.kind === 'vehicle' ? `v_${entry.item.vehicleId}` : `p_${entry.item.passId}`;
        if (k === view.selectedKey) {
          activeEntry = entry;
          activeRank = rank.get(entry.item);
        }
      });
      if (!activeEntry) {
        closeDrawer();
      }
    }

    if (tbody) {
      tbody.innerHTML = '';
      filteredEntries.forEach(entry => {
        const n = rank.get(entry.item);
        const tr = buildRow(entry.item, entry.kind, n);
        tbody.appendChild(tr);
      });
    }

    if (activeEntry) {
      renderDrawer(activeEntry.item, activeEntry.kind, activeRank, view.selectedKey);
    }
  }

  /* ---------------- Table Row Builder ---------------- */
  function buildRow(item, kind, n) {
    const isVehicle = kind === 'vehicle';
    const key = isVehicle ? `v_${item.vehicleId}` : `p_${item.passId}`;
    const isSelected = view.selectedKey === key;

    // Accent line on row left border for security alerts
    let accentBorder = 'border-l-4 border-l-transparent hover:border-l-slate-300';
    if (isSelected) {
      accentBorder = 'border-l-4 border-l-ncst-navy bg-blue-50/70 ring-1 ring-ncst-navy/30';
    } else if (item.activeHold || item.exitDenied) {
      accentBorder = 'border-l-4 border-l-rose-600 bg-rose-50/25';
    } else if (isVehicle) {
      if (item.isBanned) accentBorder = 'border-l-4 border-l-rose-600 bg-rose-50/25';
      else if (item.timeFlag === 'overnight') accentBorder = 'border-l-4 border-l-ncst-navy bg-blue-50/20';
      else if (item.timeFlag === 'overtime' || item.warningCount > 0) accentBorder = 'border-l-4 border-l-amber-500 bg-amber-50/25';
    } else {
      if (item.revoked || item.overstayed) accentBorder = 'border-l-4 border-l-rose-600 bg-rose-50/25';
    }

    // Vehicle description (Primary: vehicleTitle, Secondary: vehicleSub)
    const vehicleTitle = isVehicle ? (item.makeModelColor || item.vehicleType || 'Vehicle') : (item.vehicleModel || 'Visitor Vehicle');
    const vehicleSub = isVehicle ? (item.vehicleType && item.makeModelColor ? item.vehicleType : (item.department || 'Registered')) : 'Visitor Day Pass';

    // Person description (Primary: personName, Secondary: personSub)
    const personName = isVehicle ? (item.ownerName || 'Unknown Owner') : (item.visitorName || 'Unknown Visitor');
    const personSub = isVehicle
      ? (item.ownerRole ? `${item.ownerRole}${item.department ? ' · ' + item.department : ''}` : (item.department || 'Owner'))
      : (item.personToVisit ? `Visiting ${item.personToVisit}` : (item.purposeOfVisit || 'Visitor'));

    // Duration warning check
    const hasDurationWarning = item.timeFlag === 'overtime' || item.timeFlag === 'overnight' || item.overstayed;

    /* --- Main Row --- */
    const tr = document.createElement('tr');
    tr.dataset.key = key;
    tr.className = `h-13 transition-colors ${accentBorder} hover:bg-slate-50/80 cursor-pointer`;
    tr.innerHTML = `
      <td class="py-2.5 px-3.5 align-middle">
        ${getStatusBadge(item, kind)}
      </td>
      <td class="py-2.5 px-3.5 align-middle">
        <div class="flex items-baseline gap-1.5">
          <span class="font-mono font-bold text-slate-900 text-sm tracking-wide">${esc(item.plateNumber)}</span>
          <span class="text-[10px] text-slate-400 font-mono font-normal" title="Arrival order #${n}">#${n}</span>
        </div>
      </td>
      <td class="py-2.5 px-3.5 align-middle">
        <div class="min-w-0 max-w-[170px]">
          <div class="font-bold text-slate-900 text-xs truncate" title="${esc(vehicleTitle)}">${esc(vehicleTitle)}</div>
          <div class="text-[11px] text-slate-500 font-normal truncate mt-0.5">${esc(vehicleSub)}</div>
        </div>
      </td>
      <td class="py-2.5 px-3.5 align-middle">
        <div class="min-w-0 max-w-[170px]">
          <div class="font-bold text-slate-900 text-xs truncate" title="${esc(personName)}">${esc(personName)}</div>
          <div class="text-[11px] text-slate-500 font-normal truncate mt-0.5">${esc(personSub)}</div>
        </div>
      </td>
      <td class="py-2.5 px-3.5 align-middle">
        <span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium ${isVehicle ? 'bg-slate-100 text-slate-700 border border-slate-200/80' : 'bg-blue-50 text-ncst-navy border border-blue-200/80'}">
          ${isVehicle ? 'Registered' : 'Visitor'}
        </span>
      </td>
      <td class="py-2.5 px-3.5 align-middle whitespace-nowrap">
        <div class="text-xs text-slate-700 font-medium">${fmtTime(item.entryTime)}</div>
        <div class="text-[10px] text-slate-400 font-mono mt-0.5">${esc(item.entryGate || 'Campus Gate')}</div>
      </td>
      <td class="py-2.5 px-3.5 align-middle whitespace-nowrap">
        ${hasDurationWarning ? `
          <span class="font-mono text-xs font-bold text-amber-800 bg-amber-50 px-1.5 py-0.5 rounded border border-amber-200">
            ${esc(duration(item.hoursInside))}
          </span>
        ` : `
          <span class="font-mono text-xs font-medium text-slate-700">
            ${esc(duration(item.hoursInside))}
          </span>
        `}
      </td>
      <td class="py-2.5 px-3.5 align-middle text-right">
        <div class="flex items-center justify-end gap-1.5 relative">
          <button type="button" data-act="toggle" aria-controls="ocDrawer" aria-expanded="${isSelected}" aria-label="Toggle details for ${esc(item.plateNumber)}" class="oc-view-btn px-2.5 py-1.5 rounded-lg border text-xs font-semibold shadow-2xs transition-colors flex items-center gap-1 cursor-pointer ${isSelected ? 'border-ncst-navy bg-ncst-navy text-white' : 'border-slate-200 bg-white hover:bg-slate-50 text-slate-700 hover:text-slate-900'}">
            <span class="oc-view-label">${isSelected ? 'Close ×' : 'View ▼'}</span>
          </button>
          
          <!-- Secondary Options Dropdown Menu -->
          <div class="relative oc-menu-container">
            <button type="button" data-act="menu" class="p-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-600 hover:text-slate-900 shadow-2xs transition-colors cursor-pointer" title="More options" aria-label="More actions">
              <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <circle cx="12" cy="12" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="12" cy="19" r="1"/>
              </svg>
            </button>
            <div class="oc-dropdown hidden absolute right-0 mt-1 w-44 rounded-lg bg-white border border-slate-200 shadow-lg py-1 z-30 text-xs font-medium text-left">
              ${isVehicle ? `
                <button type="button" data-menu="dossier" class="w-full text-left px-3 py-1.5 text-slate-700 hover:bg-slate-50 hover:text-ncst-navy transition-colors flex items-center gap-2 cursor-pointer">
                  <svg class="w-3.5 h-3.5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                  <span>View Details</span>
                </button>
                <button type="button" data-menu="flag" class="w-full text-left px-3 py-1.5 text-rose-700 hover:bg-rose-50 transition-colors flex items-center gap-2 cursor-pointer">
                  <svg class="w-3.5 h-3.5 text-rose-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg>
                  <span>Flag Warning</span>
                </button>
              ` : `
                <button type="button" data-menu="pass" class="w-full text-left px-3 py-1.5 text-slate-700 hover:bg-slate-50 hover:text-ncst-navy transition-colors flex items-center gap-2 cursor-pointer">
                  <svg class="w-3.5 h-3.5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                  <span>View Pass</span>
                </button>
                <button type="button" data-menu="report" class="w-full text-left px-3 py-1.5 text-rose-700 hover:bg-rose-50 transition-colors flex items-center gap-2 cursor-pointer">
                  <svg class="w-3.5 h-3.5 text-rose-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
                  <span>Report Incident</span>
                </button>
              `}
            </div>
          </div>
        </div>
      </td>
    `;

    /* --- Event Listeners & Interaction Wiring --- */
    function toggleSelection() {
      if (view.selectedKey === key) {
        closeDrawer();
      } else {
        openDrawer(item, kind, n, key);
      }
    }

    // Row click selects/deselects vehicle in drawer
    tr.addEventListener('click', (e) => {
      if (e.target.closest('button') || e.target.closest('a') || e.target.closest('.oc-dropdown')) return;
      toggleSelection();
    });

    // Toggle button in action column
    const toggleBtn = tr.querySelector('[data-act="toggle"]');
    if (toggleBtn) {
      toggleBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleSelection();
      });
    }

    // Dropdown menu toggle
    const menuBtn = tr.querySelector('[data-act="menu"]');
    const dropdown = tr.querySelector('.oc-dropdown');
    if (menuBtn && dropdown) {
      menuBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        document.querySelectorAll('.oc-dropdown').forEach(d => {
          if (d !== dropdown) d.classList.add('hidden');
        });
        dropdown.classList.toggle('hidden');
      });
    }

    // Wiring actions for Registered Vehicles
    if (isVehicle) {
      const openDossierAction = () => {
        if (!SP.openVehicle(item.vehicleId)) {
          SP.showToast('Vehicle details are still loading. Try again in a moment.');
        }
      };

      const flagAction = () => {
        if (!window.SPViolations) return;
        SPViolations.openFlagModal({
          id: item.vehicleId, plateNumber: item.plateNumber, ownerName: item.ownerName,
          warningCount: item.warningCount, isBanned: item.isBanned
        }, {
          context: `On campus since ${fmtTime(item.entryTime).replace(/&[^;]+;/g, '')}, driven in by ${item.enteredBy || 'unknown driver'}`,
          onDone: () => load()
        });
      };

      const menuDossier = tr.querySelector('[data-menu="dossier"]');
      if (menuDossier) {
        menuDossier.addEventListener('click', (e) => {
          e.stopPropagation();
          dropdown.classList.add('hidden');
          openDossierAction();
        });
      }

      const menuFlag = tr.querySelector('[data-menu="flag"]');
      if (menuFlag) {
        menuFlag.addEventListener('click', (e) => {
          e.stopPropagation();
          dropdown.classList.add('hidden');
          flagAction();
        });
      }
    } else {
      // Wiring actions for Visitors
      const openPassAction = async () => {
        try {
          const pass = await ApiClient.getVisitorPass(item.passId);
          if (window.SPVisitors) SPVisitors.openCard(pass);
        } catch (err) {
          SP.showToast(err.message);
        }
      };

      const reportAction = () => {
        openIncident(item);
      };

      const menuPass = tr.querySelector('[data-menu="pass"]');
      if (menuPass) {
        menuPass.addEventListener('click', (e) => {
          e.stopPropagation();
          dropdown.classList.add('hidden');
          openPassAction();
        });
      }

      const menuReport = tr.querySelector('[data-menu="report"]');
      if (menuReport) {
        menuReport.addEventListener('click', (e) => {
          e.stopPropagation();
          dropdown.classList.add('hidden');
          reportAction();
        });
      }
    }

    return tr;
  }

  /* ---------------- Right-Side Details Drawer Controller ---------------- */
  function openDrawer(item, kind, n, key) {
    view.selectedKey = key;
    renderDrawer(item, kind, n, key);

    const drawer = $('ocDrawer');
    if (drawer) drawer.classList.remove('hidden');

    const backdrop = $('ocDrawerBackdrop');
    if (backdrop) backdrop.classList.remove('hidden');

    // Update row highlights
    document.querySelectorAll('#ocTableBody tr').forEach(tr => {
      const match = tr.dataset.key === key;
      tr.classList.toggle('bg-blue-50/70', match);
      tr.classList.toggle('ring-1', match);
      tr.classList.toggle('ring-ncst-navy/30', match);
      tr.classList.toggle('border-l-ncst-navy', match);
      const label = tr.querySelector('.oc-view-label');
      if (label) label.textContent = match ? 'Close ×' : 'View ▼';
      const btn = tr.querySelector('.oc-view-btn');
      if (btn) btn.setAttribute('aria-expanded', String(match));
      if (btn) {
        btn.classList.toggle('bg-ncst-navy', match);
        btn.classList.toggle('text-white', match);
        btn.classList.toggle('border-ncst-navy', match);
      }
    });
  }

  function closeDrawer() {
    view.selectedKey = null;

    const drawer = $('ocDrawer');
    if (drawer) drawer.classList.add('hidden');

    const backdrop = $('ocDrawerBackdrop');
    if (backdrop) backdrop.classList.add('hidden');

    document.querySelectorAll('#ocTableBody tr').forEach(tr => {
      tr.classList.remove('bg-blue-50/70', 'ring-1', 'ring-ncst-navy/30');
      const label = tr.querySelector('.oc-view-label');
      if (label) label.textContent = 'View ▼';
      const btn = tr.querySelector('.oc-view-btn');
      if (btn) btn.setAttribute('aria-expanded', 'false');
      if (btn) {
        btn.classList.remove('bg-ncst-navy', 'text-white', 'border-ncst-navy');
      }
    });
  }

  function renderDrawer(item, kind, n, key) {
    const isVehicle = kind === 'vehicle';
    const drawerContent = $('ocDrawerContent');
    if (!drawerContent) return;

    const vehicleTitle = isVehicle ? (item.makeModelColor || item.vehicleType || 'Vehicle') : (item.vehicleModel || 'Visitor Vehicle');
    const vehicleSub = isVehicle ? (item.vehicleType && item.makeModelColor ? item.vehicleType : (item.department || 'Registered')) : 'Visitor Day Pass';

    drawerContent.innerHTML = `
      <!-- Drawer Header -->
      <div class="p-4 sm:p-5 border-b border-slate-100 bg-slate-50/70 flex items-start justify-between gap-3">
        <div>
          <div class="flex items-center gap-2">
            <span class="sp-plate text-sm tracking-wider shadow-2xs">${esc(item.plateNumber)}</span>
            <span class="text-xs font-mono text-slate-400">#${n}</span>
            ${getStatusBadge(item, kind)}
          </div>
          <div class="text-sm font-bold text-slate-900 mt-2">${esc(vehicleTitle)}</div>
          <div class="text-xs text-slate-500">${esc(vehicleSub)}</div>
        </div>
        <button type="button" id="ocDrawerCloseBtn" class="px-2 py-1 rounded-md text-slate-500 hover:text-slate-800 hover:bg-slate-200/60 text-xs font-semibold transition-colors cursor-pointer flex items-center gap-1" title="Close Details">
          <span>Close Details</span>
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </div>

      <!-- Drawer Body (Scrollable) -->
      <div class="p-4 sm:p-5 space-y-4 flex-1 overflow-y-auto">
        <!-- Active Security Alerts Banner (if any) -->
        ${item.activeHold ? `
          <div class="p-3 rounded-lg bg-rose-50 border border-rose-200 text-rose-900">
            <div class="text-[10px] font-extrabold uppercase tracking-wider text-rose-700 flex items-center gap-1.5">
              <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
              <span>Active Security Hold</span>
            </div>
            <div class="text-xs font-bold mt-1">Case #${esc(item.activeHold.caseNumber)}</div>
            <div class="text-[11px] text-rose-700 mt-0.5">${esc(item.activeHold.reason || 'Exit Denied by Security Staff')}</div>
          </div>
        ` : ''}

        <!-- Group 1: Owner & Driver -->
        <div class="p-3.5 rounded-lg bg-slate-50/70 border border-slate-100 space-y-3">
          <div class="text-[10px] font-extrabold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
            <svg class="w-3.5 h-3.5 text-ncst-navy" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
            <span>${isVehicle ? 'Owner & Driver' : 'Visitor & Host'}</span>
          </div>
          ${isVehicle ? `
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Registered Owner</div>
              <div class="text-xs font-bold text-slate-900 mt-0.5">${esc(item.ownerName)} <span class="text-[11px] font-normal text-slate-500">(${esc(item.ownerRole || 'Registered')})</span></div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Driver at Gate</div>
              <div class="text-xs font-semibold text-slate-800 mt-0.5">${esc(item.enteredBy || 'Same as owner')}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Contact Number</div>
              <div class="text-xs mt-0.5">${tel(item.ownerPhone)}</div>
            </div>
          ` : `
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Visitor Name</div>
              <div class="text-xs font-bold text-slate-900 mt-0.5">${esc(item.visitorName)}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Person To Visit</div>
              <div class="text-xs font-semibold text-slate-800 mt-0.5">${esc(item.personToVisit || 'Campus Administration')}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Contact Number</div>
              <div class="text-xs mt-0.5">${tel(item.contactNumber)}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Visiting Purpose</div>
              <div class="text-xs text-slate-700 mt-0.5">${esc(item.purposeOfVisit || 'Official Business')}</div>
            </div>
          `}
        </div>

        <!-- Group 2: Entry Details -->
        <div class="p-3.5 rounded-lg bg-slate-50/70 border border-slate-100 space-y-3">
          <div class="text-[10px] font-extrabold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
            <svg class="w-3.5 h-3.5 text-ncst-navy" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
            <span>Entry Details</span>
          </div>
          <div class="grid grid-cols-2 gap-2.5">
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Entry Time</div>
              <div class="text-xs font-semibold text-slate-900 mt-0.5">${fmtTime(item.entryTime)}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Duration Inside</div>
              <div class="text-xs font-mono font-bold text-slate-900 mt-0.5">${esc(duration(item.hoursInside))}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Entry Gate</div>
              <div class="text-xs font-medium text-slate-700 mt-0.5">${esc(item.entryGate || 'Gate 1 (Main)')}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Checked By</div>
              <div class="text-xs font-medium text-slate-700 mt-0.5">${esc(item.admittedBy || 'Security Staff')}</div>
            </div>
          </div>
          ${!isVehicle ? `
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Pass Code</div>
              <div class="text-xs font-mono font-bold text-ncst-navy mt-0.5">${esc(item.passCode)} <span class="text-[11px] font-normal text-slate-400">(Valid: ${esc(item.validDate)})</span></div>
            </div>
          ` : ''}
        </div>

        <!-- Group 3: Vehicle Checks -->
        <div class="p-3.5 rounded-lg bg-slate-50/70 border border-slate-100 space-y-3">
          <div class="text-[10px] font-extrabold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
            <svg class="w-3.5 h-3.5 text-ncst-navy" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            <span>${isVehicle ? 'Vehicle Checks' : 'Pass Status & Security'}</span>
          </div>
          ${isVehicle ? `
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Vehicle Status</div>
              <div class="text-xs font-bold mt-0.5">
                ${item.isBanned ? '<span class="text-rose-700">Banned from Campus</span>' : (item.warningCount > 0 ? `<span class="text-amber-700">Strike ${item.warningCount} of ${STRIKE_LIMIT}</span>` : '<span class="text-emerald-700">Clear (0 strikes)</span>')}
              </div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">VIP Status</div>
              <div class="text-xs font-semibold mt-0.5 ${item.isVip ? 'text-amber-700' : 'text-slate-600'}">${item.isVip ? 'VIP Authorized' : 'Standard'}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Parking Status</div>
              <div class="text-xs font-semibold mt-0.5 ${item.timeFlag ? 'text-amber-700' : 'text-emerald-700'}">${item.timeFlag ? (item.timeFlag === 'overnight' ? 'Overnight Flag' : 'Overtime Flag') : 'Within Allowed Hours'}</div>
            </div>
          ` : `
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Pass Dates</div>
              <div class="text-xs font-bold mt-0.5 ${item.overstayed ? 'text-rose-700' : 'text-emerald-700'}">${item.overstayed ? 'Expired (Overstayed)' : 'Valid for Today'}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase font-semibold text-slate-400 tracking-wider">Pass State</div>
              <div class="text-xs font-bold mt-0.5 ${item.revoked ? 'text-rose-700' : 'text-slate-700'}">${item.revoked ? 'Cancelled' : 'Active Pass'}</div>
            </div>
          `}
        </div>

        <!-- Declared Items (if visitor) -->
        ${!isVehicle ? itemsHtml(item.items) : ''}
      </div>

      <!-- Drawer Actions (Fixed Bottom) -->
      <div class="p-4 border-t border-slate-100 bg-slate-50/70 space-y-2">
        ${isVehicle ? `
          <button type="button" id="ocDrawerPrimaryBtn" class="w-full h-9 rounded-lg bg-ncst-navy hover:bg-ncst-navyDark active:bg-ncst-navyDark text-white text-xs font-bold shadow-2xs transition-colors flex items-center justify-center gap-1.5 cursor-pointer">
            <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
            <span>View Details</span>
          </button>
          <div class="flex items-center gap-2">
            <button type="button" id="ocDrawerSecondaryBtn" class="flex-1 h-8 rounded-lg border border-rose-200 bg-rose-50/80 hover:bg-rose-100 text-rose-800 text-xs font-semibold transition-colors flex items-center justify-center gap-1.5 cursor-pointer">
              <svg class="w-3.5 h-3.5 text-rose-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg>
              <span>Flag Warning</span>
            </button>
            ${clipButton(item, item.plateNumber, 'Entry Recorded')}
          </div>
        ` : `
          <button type="button" id="ocDrawerPrimaryBtn" class="w-full h-9 rounded-lg bg-ncst-navy hover:bg-ncst-navyDark active:bg-ncst-navyDark text-white text-xs font-bold shadow-2xs transition-colors flex items-center justify-center gap-1.5 cursor-pointer">
            <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
            <span>View Pass</span>
          </button>
          <div class="flex items-center gap-2">
            <button type="button" id="ocDrawerSecondaryBtn" class="flex-1 h-8 rounded-lg border border-rose-200 bg-rose-50/80 hover:bg-rose-100 text-rose-800 text-xs font-semibold transition-colors flex items-center justify-center gap-1.5 cursor-pointer">
              <svg class="w-3.5 h-3.5 text-rose-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
              <span>Report Incident</span>
            </button>
            ${clipButton(item, item.plateNumber, 'Entry Recorded')}
          </div>
        `}
      </div>
    `;

    // Bind Close Button
    const closeBtn = $('ocDrawerCloseBtn');
    if (closeBtn) closeBtn.addEventListener('click', closeDrawer);

    // Bind Primary & Secondary Buttons
    const primaryBtn = $('ocDrawerPrimaryBtn');
    if (primaryBtn) {
      primaryBtn.addEventListener('click', () => {
        if (isVehicle) {
          if (!SP.openVehicle(item.vehicleId)) {
            SP.showToast('Vehicle details are still loading. Try again in a moment.');
          }
        } else {
          ApiClient.getVisitorPass(item.passId).then(pass => {
            if (window.SPVisitors) SPVisitors.openCard(pass);
          }).catch(err => SP.showToast(err.message));
        }
      });
    }

    const secondaryBtn = $('ocDrawerSecondaryBtn');
    if (secondaryBtn) {
      secondaryBtn.addEventListener('click', () => {
        if (isVehicle) {
          if (!window.SPViolations) return;
          SPViolations.openFlagModal({
            id: item.vehicleId, plateNumber: item.plateNumber, ownerName: item.ownerName,
            warningCount: item.warningCount, isBanned: item.isBanned
          }, {
            context: `On campus since ${fmtTime(item.entryTime).replace(/&[^;]+;/g, '')}, driven in by ${item.enteredBy || 'unknown driver'}`,
            onDone: () => load()
          });
        } else {
          openIncident(item);
        }
      });
    }
  }

  /* ---------------- visitor incident modal ---------------- */
  function openIncident(p) {
    view.incidentTarget = p;
    $('visitorIncidentSummary').textContent = `${p.visitorName} · ${p.plateNumber} · visiting ${p.personToVisit}`;
    $('viReason').value = p.overstayed ? 'Overstayed day pass' : 'Parking in Fire Lane / Restricted Zone';
    $('viNotes').value = '';
    $('visitorIncidentError').classList.add('hidden');
    $('visitorIncidentModal').classList.remove('hidden');
    $('visitorIncidentModal').classList.add('flex');
    setTimeout(() => $('viReason').focus(), 50);
  }

  function closeIncident() {
    $('visitorIncidentModal').classList.add('hidden');
    $('visitorIncidentModal').classList.remove('flex');
  }

  async function submitIncident(e) {
    e.preventDefault();
    const p = view.incidentTarget;
    const reason = $('viReason').value;
    const notes = $('viNotes').value.trim();
    const err = $('visitorIncidentError');
    if (reason === 'Other' && !notes) {
      err.textContent = 'Describe what happened when choosing "Other".';
      err.classList.remove('hidden');
      return;
    }
    const itemsText = (p.items || []).map(i => `${i.quantity}x ${i.name}`).join(', ');
    $('visitorIncidentSubmitBtn').disabled = true;
    try {
      const res = await ApiClient.createIncident({
        plateNumber: p.plateNumber,
        reason,
        vehicleType: 'Visitor Vehicle',
        ownerName: p.visitorName,
        ownerRole: 'Visitor',
        driverName: p.visitorName,
        driverRelationship: 'Visitor (Day Pass)',
        gatePoint: 'Campus patrol (on campus)',
        notes: [`Day pass ${p.passCode}, visiting ${p.personToVisit}.`, itemsText ? `Declared items: ${itemsText}.` : '', notes].filter(Boolean).join(' ')
      });
      closeIncident();
      SP.showToast(`Security case ${res.caseNumber} opened for ${p.plateNumber}.`);
      if (SP.reload) SP.reload();
    } catch (e2) {
      err.textContent = e2.message;
      err.classList.remove('hidden');
    } finally {
      $('visitorIncidentSubmitBtn').disabled = false;
    }
  }

  /* ---------------- Wiring ---------------- */
  function showView() {
    if (view.data) render();
    load();
  }

  document.addEventListener('sp:app-ready', () => {
    SP.registerView('onCampusView', $('navOnCampusBtn'), showView);
    $('onCampusRefreshBtn').addEventListener('click', load);
    $('ocSearch').addEventListener('input', render);
    document.querySelectorAll('#ocFilter .oc-filter').forEach(b => b.addEventListener('click', () => {
      view.filter = b.dataset.filter;
      render();
    }));
    if ($('kpiInsideLink')) $('kpiInsideLink').addEventListener('click', () => SP.switchView('onCampusView'));
    $('visitorIncidentForm').addEventListener('submit', submitIncident);
    $('visitorIncidentCancelBtn').addEventListener('click', closeIncident);

    // Backdrop click on small screens closes drawer
    const backdrop = $('ocDrawerBackdrop');
    if (backdrop) {
      backdrop.addEventListener('click', closeDrawer);
    }

    // Escape closes drawer if open
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && view.selectedKey && !e.defaultPrevented && !document.querySelector('.sp-dialog:not(.hidden), #drawerOverlay:not(.hidden), #zoomQrModalOverlay:not(.hidden), #spClipOverlay')) {
        closeDrawer();
      }
    });

    // Global listener to close open action dropdown menus when clicking outside
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.oc-menu-container')) {
        document.querySelectorAll('.oc-dropdown').forEach(d => d.classList.add('hidden'));
      }
    });

    // Refresh on gate passages
    document.addEventListener('sp:data-loaded', () => {
      const shared = SP.state.onCampus;
      if (shared && shared.counts) {
        view.data = shared;
        updateBadge();
        if ($('onCampusView').classList.contains('active')) render();
      } else {
        load();
      }
    });

    SPAuth.whenAuthenticated(load);
  });
})();
