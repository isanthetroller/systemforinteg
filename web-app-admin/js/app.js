// SecurePark - Campus Vehicle Custody Management System
// Admin Web Application Controller
// Standard, high-density operations logic for campus security personnel

document.addEventListener('DOMContentLoaded', () => {
  /* ==========================================================================
     Application State
     ========================================================================== */
  const state = {
    vehicles: [...INITIAL_DATA.vehicles],
    auditLogs: [...INITIAL_DATA.auditLogs],
    incidents: [...INITIAL_DATA.incidents],
    visitors: [],
    onCampus: null,
    gateFlowTab: 'inside',
    currentView: 'dashboardView',
    vehicleFilter: {
      search: '',
      role: 'All',
      category: 'All',
      location: 'All',
      status: 'All'
    },
    auditFilter: {
      search: '',
      status: 'All',
      page: 1,
      pageSize: 10
    },
    driverCounter: 1
  };

  /* ==========================================================================
     DOM Element Selections
     ========================================================================== */
  // Navigation
  const navBtns = {
    dashboard: document.getElementById('navDashboardBtn'),
    vehicles: document.getElementById('navVehiclesBtn'),
    account: document.getElementById('navAccountBtn'),
    audit: document.getElementById('navAuditBtn'),
    flagged: document.getElementById('navFlaggedBtn')
  };

  const views = {
    dashboardView: document.getElementById('dashboardView'),
    vehiclesView: document.getElementById('vehiclesView'),
    flaggedView: document.getElementById('flaggedView'),
    auditView: document.getElementById('auditView'),
    accountView: document.getElementById('accountView')
  };

  const flaggedSidebarCount = document.getElementById('flaggedSidebarCount');
  const incidentQueueBadge = document.getElementById('incidentQueueBadge');

  // Sidebar Controls
  const appSidebar = document.getElementById('appSidebar');
  const sidebarCollapseBtn = document.getElementById('sidebarCollapseBtn');
  const sidebarExpandBtn = document.getElementById('sidebarExpandBtn');

  // Dashboard shortcuts & KPIs
  const quickFlaggedBtn = document.getElementById('quickFlaggedBtn');
  const quickNewAccBtn = document.getElementById('quickNewAccBtn');
  const directoryNewAccBtn = document.getElementById('directoryNewAccBtn');
  const viewAllAuditBtn = document.getElementById('viewAllAuditBtn');

  const kpiInside = document.getElementById('kpiInside');
  const kpiBlocked = document.getElementById('kpiBlocked');
  const kpiTotalLogs = document.getElementById('kpiTotalLogs');
  const kpiRegistered = document.getElementById('kpiRegistered');
  const dashboardActivityBody = document.getElementById('dashboardActivityBody');

  // Gate Flow Operations Center
  const tabCurrentlyInsideBtn = document.getElementById('tabCurrentlyInsideBtn');
  const tabEntranceBtn = document.getElementById('tabEntranceBtn');
  const tabExitBtn = document.getElementById('tabExitBtn');
  const tabCountInside = document.getElementById('tabCountInside');
  const tabCountEntrance = document.getElementById('tabCountEntrance');
  const tabCountExit = document.getElementById('tabCountExit');
  const paneCurrentlyInside = document.getElementById('paneCurrentlyInside');
  const paneEntrance = document.getElementById('paneEntrance');
  const paneExit = document.getElementById('paneExit');
  const currentlyInsideTableBody = document.getElementById('currentlyInsideTableBody');
  const entranceTableBody = document.getElementById('entranceTableBody');
  const exitTableBody = document.getElementById('exitTableBody');
  const gateFlowSubtext = document.getElementById('gateFlowSubtext');
  const onCampusSidebarCount = document.getElementById('onCampusSidebarCount');

  // Dashboard Visualizations & Attention Panel
  const activityTrendHourlyBtn = document.getElementById('activityTrendHourlyBtn');
  const activityTrendGateBtn = document.getElementById('activityTrendGateBtn');
  const gateActivityChartCanvas = document.getElementById('gateActivityChart');
  const gateStatusChartCanvas = document.getElementById('gateStatusChart');
  const fleetTypesChartCanvas = document.getElementById('fleetTypesChart');
  const legendInsideCount = document.getElementById('legendInsideCount');
  const legendExitedCount = document.getElementById('legendExitedCount');
  const legendBlockedCount = document.getElementById('legendBlockedCount');
  const fleetTotalBadge = document.getElementById('fleetTotalBadge');
  const donutCenterTotal = document.getElementById('donutCenterTotal');
  const attentionCountBadge = document.getElementById('attentionCountBadge');
  const viewAllIncidentsLink = document.getElementById('viewAllIncidentsLink');
  const attentionPanelContent = document.getElementById('attentionPanelContent');

  const charts = {
    activityTrend: null,
    gateStatus: null,
    fleetTypes: null
  };
  let trendViewMode = 'hourly';

  // Vehicle Directory
  const vehicleSearchInput = document.getElementById('vehicleSearchInput');
  const vehicleRoleFilter = document.getElementById('vehicleRoleFilter');
  const vehicleCategoryFilter = document.getElementById('vehicleCategoryFilter');
  const vehicleLocationFilter = document.getElementById('vehicleLocationFilter');
  const vehicleStatusFilter = document.getElementById('vehicleStatusFilter');
  const vehiclesTableBody = document.getElementById('vehiclesTableBody');
  const directoryVehicleCountBadge = document.getElementById('directoryVehicleCountBadge');

  // Flagged & Blocked
  const incidentsTableBody = document.getElementById('incidentsTableBody');

  // Audit Logs
  const fullAuditSearchInput = document.getElementById('fullAuditSearchInput');
  const auditFilterPills = document.querySelectorAll('.audit-filter-pill');
  const fullAuditTableBody = document.getElementById('fullAuditTableBody');
  const auditPaginationInfo = document.getElementById('auditPaginationInfo');
  const auditPrevBtn = document.getElementById('auditPrevBtn');
  const auditNextBtn = document.getElementById('auditNextBtn');
  const exportCsvBtn = document.getElementById('exportCsvBtn');

  // Audit Summary Elements
  const auditSummaryTotal = document.getElementById('auditSummaryTotal');
  const auditSummaryInside = document.getElementById('auditSummaryInside');
  const auditSummaryExited = document.getElementById('auditSummaryExited');
  const auditSummaryBlocked = document.getElementById('auditSummaryBlocked');
  const auditPillCountAll = document.getElementById('auditPillCountAll');
  const auditPillCountInside = document.getElementById('auditPillCountInside');
  const auditPillCountExited = document.getElementById('auditPillCountExited');
  const auditPillCountBlocked = document.getElementById('auditPillCountBlocked');

  // Registration Form
  const vehicleForm = document.getElementById('vehicleRegistrationForm');
  const resetFormBtn = document.getElementById('resetFormBtn');
  const addDriverBtn = document.getElementById('addDriverBtn');
  const driversContainer = document.getElementById('driversContainer');
  const plateInput = document.getElementById('plateNumber');
  const plateValidationMsg = document.getElementById('plateValidationMsg');

  // Photo Attachment Controls
  const ownerPhotoInput = document.getElementById('ownerPhotoInput');
  const ownerPhotoBtn = document.getElementById('ownerPhotoBtn');
  const removeOwnerPhotoBtn = document.getElementById('removeOwnerPhotoBtn');
  const ownerPhotoPreview = document.getElementById('ownerPhotoPreview');
  const ownerPhotoPlaceholder = document.getElementById('ownerPhotoPlaceholder');
  const ownerPhotoFileName = document.getElementById('ownerPhotoFileName');

  const vehiclePhotoInput = document.getElementById('vehiclePhotoInput');
  const vehiclePhotoBtn = document.getElementById('vehiclePhotoBtn');
  const removeVehiclePhotoBtn = document.getElementById('removeVehiclePhotoBtn');
  const vehiclePhotoPreview = document.getElementById('vehiclePhotoPreview');
  const vehiclePhotoPlaceholder = document.getElementById('vehiclePhotoPlaceholder');
  const vehiclePhotoFileName = document.getElementById('vehiclePhotoFileName');

  let ownerPhotoDataUrl = null;
  let vehiclePhotoDataUrl = null;
  let vehiclePhotoMicroDataUrl = null;

  // Live QR Pass Technology Elements
  const qrCodeContainer = document.getElementById('qrCodeContainer');
  const qrStickerYearBadge = document.getElementById('qrStickerYearBadge');
  const qrPreviewPlate = document.getElementById('qrPreviewPlate');
  const qrPreviewVehicle = document.getElementById('qrPreviewVehicle');
  const qrPreviewRole = document.getElementById('qrPreviewRole');
  const qrPreviewId = document.getElementById('qrPreviewId');
  const qrOwnerThumb = document.getElementById('qrOwnerThumb');
  const qrOwnerPlaceholder = document.getElementById('qrOwnerPlaceholder');
  const qrVehicleThumb = document.getElementById('qrVehicleThumb');
  const qrVehiclePlaceholder = document.getElementById('qrVehiclePlaceholder');
  const qrPreviewOwnerName = document.getElementById('qrPreviewOwnerName');
  const qrPreviewDriverName = document.getElementById('qrPreviewDriverName');
  const qrDriversCountBadge = document.getElementById('qrDriversCountBadge');
  const qrPreviewDriversList = document.getElementById('qrPreviewDriversList');
  const downloadPassBadgeBtn = document.getElementById('downloadPassBadgeBtn');
  const downloadQrBtn = document.getElementById('downloadQrBtn');
  const printGatePassBtn = document.getElementById('printGatePassBtn');
  let qrCodeInstance = null;

  // Inspection Drawer
  const drawerOverlay = document.getElementById('drawerOverlay');
  const drawerTitle = document.getElementById('drawerTitle');
  const drawerSubtitle = document.getElementById('drawerSubtitle');
  const drawerContent = document.getElementById('drawerContent');
  const drawerFooter = document.getElementById('drawerFooter');
  const closeDrawerBtn = document.getElementById('closeDrawerBtn');
  const drawerCancelBtn = document.getElementById('drawerCancelBtn');

  // Edit Modal Elements (Full 3-Section Register Style)
  const editModalOverlay = document.getElementById('editModalOverlay');
  const closeEditModalBtn = document.getElementById('closeEditModalBtn');
  const cancelEditModalBtn = document.getElementById('cancelEditModalBtn');
  const editVehicleForm = document.getElementById('editVehicleForm');
  const editVehicleId = document.getElementById('editVehicleId');
  const editModalPlate = document.getElementById('editModalPlate');
  // Section 1: Owner
  const editOwnerRole = document.getElementById('editOwnerRole');
  const editOwnerIdNumber = document.getElementById('editOwnerIdNumber');
  const editOwnerFullName = document.getElementById('editOwnerFullName');
  const editDepartment = document.getElementById('editDepartment');
  const editOwnerPhone = document.getElementById('editOwnerPhone');
  const editOwnerEmail = document.getElementById('editOwnerEmail');
  const editOwnerPhotoInput = document.getElementById('editOwnerPhotoInput');
  const editOwnerPhotoBtn = document.getElementById('editOwnerPhotoBtn');
  const removeEditOwnerPhotoBtn = document.getElementById('removeEditOwnerPhotoBtn');
  const editOwnerPhotoPreview = document.getElementById('editOwnerPhotoPreview');
  const editOwnerPhotoPlaceholder = document.getElementById('editOwnerPhotoPlaceholder');
  const editOwnerPhotoFileName = document.getElementById('editOwnerPhotoFileName');
  let editOwnerPhotoDataUrl = null;
  // Section 2: Vehicle
  const editVehicleCategory = document.getElementById('editVehicleCategory');
  const editPlateNumber = document.getElementById('editPlateNumber');
  const editMakeModel = document.getElementById('editMakeModel');
  const editStickerYear = document.getElementById('editStickerYear');
  const editPassClassVip = document.getElementById('editPassClassVip');
  const editRegStatus = document.getElementById('editRegStatus');
  const editCampusStatus = document.getElementById('editCampusStatus');
  const editVehiclePhotoInput = document.getElementById('editVehiclePhotoInput');
  const editVehiclePhotoBtn = document.getElementById('editVehiclePhotoBtn');
  const removeEditVehiclePhotoBtn = document.getElementById('removeEditVehiclePhotoBtn');
  const editVehiclePhotoPreview = document.getElementById('editVehiclePhotoPreview');
  const editVehiclePhotoPlaceholder = document.getElementById('editVehiclePhotoPlaceholder');
  const editVehiclePhotoFileName = document.getElementById('editVehiclePhotoFileName');
  let editVehiclePhotoDataUrl = null;
  // Section 3: Drivers
  const editAddDriverBtn = document.getElementById('editAddDriverBtn');
  const editDriversContainer = document.getElementById('editDriversContainer');

  // Zoom QR Modal
  const zoomQrModalOverlay = document.getElementById('zoomQrModalOverlay');
  const closeZoomQrModalBtn = document.getElementById('closeZoomQrModalBtn');
  const zoomQrDoneBtn = document.getElementById('zoomQrDoneBtn');
  const zoomQrContainer = document.getElementById('zoomQrContainer');
  const zoomQrPlate = document.getElementById('zoomQrPlate');
  const zoomQrOwner = document.getElementById('zoomQrOwner');
  const zoomQrYear = document.getElementById('zoomQrYear');
  const zoomQrCategory = document.getElementById('zoomQrCategory');
  const zoomPreviewQrBtn = document.getElementById('zoomPreviewQrBtn');
  let currentZoomSize = 340;
  let currentZoomPayload = '';
  let lastPreviewPassInfo = null;

  // Toast Hub
  const toastHub = document.getElementById('toastHub');

  /* ==========================================================================
     1. Navigation System
     ========================================================================== */
  const navMap = {
    dashboardView: navBtns.dashboard,
    vehiclesView: navBtns.vehicles,
    accountView: navBtns.account,
    auditView: navBtns.audit,
    flaggedView: navBtns.flagged
  };

  // Feature modules (users.js, gate.js, ...) register extra views through window.SP.registerView
  const viewHooks = {};

  function switchView(targetViewId) {
    if (!views[targetViewId]) return;
    // Views hidden for the current role cannot be opened
    if (views[targetViewId].classList.contains('admin-only') && window.SPAuth && !SPAuth.hasRole('admin')) return;
    if (document.body.classList.contains('role-guard2') && (targetViewId === 'visitorsView' || targetViewId === 'accountView')) return;

    state.currentView = targetViewId;

    // Toggle panels
    Object.keys(views).forEach(key => {
      if (views[key]) {
        if (key === targetViewId) {
          views[key].classList.add('active');
        } else {
          views[key].classList.remove('active');
        }
      }
    });

    // Update navigation item styles for royal blue gradient sidebar
    const activeClass = "nav-item w-full flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-bold text-white bg-white/15 border-l-4 border-white shadow-xs transition-colors text-left cursor-pointer";
    const inactiveClass = "nav-item w-full flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-semibold text-slate-100 hover:text-white hover:bg-white/15 transition-colors text-left cursor-pointer";

    Object.keys(navMap).forEach(key => {
      const btn = navMap[key];
      if (!btn) return;
      const svg = btn.querySelector('svg');
      const roleClass = btn.classList.contains('admin-only') ? 'admin-only ' : '';

      if (key === targetViewId) {
        btn.className = roleClass + activeClass;
        if (svg) svg.className = "w-4 h-4 text-white flex-shrink-0";
      } else {
        btn.className = roleClass + inactiveClass;
        if (svg) svg.className = "w-4 h-4 text-slate-200 flex-shrink-0";
      }
    });

    // View-specific initialization
    if (viewHooks[targetViewId]) {
      viewHooks[targetViewId]();
    } else if (targetViewId === 'dashboardView') {
      renderDashboard();
    } else if (targetViewId === 'vehiclesView') {
      renderVehiclesTable();
    } else if (targetViewId === 'flaggedView') {
      renderIncidentsTable();
    } else if (targetViewId === 'auditView') {
      renderFullAuditTable();
    } else if (targetViewId === 'accountView') {
      generateQrPass(false);
    }
  }

  // Bind Navigation Listeners
  if (navBtns.dashboard) navBtns.dashboard.addEventListener('click', () => switchView('dashboardView'));
  if (navBtns.vehicles) navBtns.vehicles.addEventListener('click', () => switchView('vehiclesView'));
  if (navBtns.account) navBtns.account.addEventListener('click', () => switchView('accountView'));
  if (navBtns.audit) navBtns.audit.addEventListener('click', () => switchView('auditView'));
  if (navBtns.flagged) navBtns.flagged.addEventListener('click', () => switchView('flaggedView'));

  // Quick Action Buttons
  if (quickFlaggedBtn) quickFlaggedBtn.addEventListener('click', () => switchView('flaggedView'));
  if (quickNewAccBtn) quickNewAccBtn.addEventListener('click', () => switchView('accountView'));
  if (directoryNewAccBtn) directoryNewAccBtn.addEventListener('click', () => switchView('accountView'));
  if (viewAllAuditBtn) viewAllAuditBtn.addEventListener('click', () => switchView('auditView'));

  // Sidebar Hide / Toggle Controller
  function toggleSidebar(forceState = null) {
    if (!appSidebar) return;
    const isCurrentlyCollapsed = appSidebar.classList.contains('collapsed');
    const shouldCollapse = forceState !== null ? forceState : !isCurrentlyCollapsed;
    
    if (shouldCollapse) {
      appSidebar.classList.add('collapsed');
      if (sidebarExpandBtn) {
        sidebarExpandBtn.classList.remove('hidden');
        sidebarExpandBtn.classList.add('inline-flex');
      }
      try { localStorage.setItem('ncst_sidebar_collapsed', 'true'); } catch (e) {}
    } else {
      appSidebar.classList.remove('collapsed');
      if (sidebarExpandBtn) {
        sidebarExpandBtn.classList.add('hidden');
        sidebarExpandBtn.classList.remove('inline-flex');
      }
      try { localStorage.setItem('ncst_sidebar_collapsed', 'false'); } catch (e) {}
    }
  }

  if (sidebarCollapseBtn) {
    sidebarCollapseBtn.addEventListener('click', () => toggleSidebar(true));
  }
  if (sidebarExpandBtn) {
    sidebarExpandBtn.addEventListener('click', () => toggleSidebar(false));
  }

  // Restore saved collapsed state
  try {
    if (localStorage.getItem('ncst_sidebar_collapsed') === 'true') {
      toggleSidebar(true);
    }
  } catch(e) {}

  /* ==========================================================================
     2. Metrics & Status Updates
     ========================================================================== */
  function updateCounts() {
    let insideVehicles = 0;
    let insideVisitors = 0;
    let insideCount = 0;

    if (state.onCampus && state.onCampus.counts) {
      insideVehicles = state.onCampus.counts.registered || 0;
      insideVisitors = state.onCampus.counts.visitors || 0;
      insideCount = state.onCampus.counts.total || (insideVehicles + insideVisitors);
    } else {
      insideVehicles = state.vehicles.filter(v => (v.status || '').toLowerCase().includes('inside')).length;
      insideVisitors = (state.visitors || []).filter(v => {
        const s = (v.status || '').toLowerCase();
        return (s === 'active' || s.includes('inside')) && v.entryTime && !v.exitTime;
      }).length;
      insideCount = insideVehicles + insideVisitors;
    }

    const activeIncidents = state.incidents.filter(i => i.status === 'Held').length;
    const blockedCount = activeIncidents > 0 ? activeIncidents : state.vehicles.filter(v => v.status === 'Blocked / Alert').length;

    const entranceLogs = state.auditLogs.filter(l => l.action === 'Entry Recorded' || l.action === 'Entry Denied' || l.gateType === 'Entry' || l.gateType === 'Ingress' || (l.action && l.action.toLowerCase().includes('entry')));
    const exitLogs = state.auditLogs.filter(l => l.action === 'Exit Approved' || l.action === 'Exit Denied' || l.gateType === 'Exit' || l.gateType === 'Egress' || (l.action && l.action.toLowerCase().includes('exit')));

    if (kpiInside) kpiInside.textContent = insideCount;
    if (kpiBlocked) kpiBlocked.textContent = blockedCount;
    if (kpiTotalLogs) kpiTotalLogs.textContent = entranceLogs.length;
    if (kpiRegistered) kpiRegistered.textContent = state.vehicles.length;

    if (onCampusSidebarCount) onCampusSidebarCount.textContent = insideCount;
    if (tabCountInside) tabCountInside.textContent = insideCount;
    if (tabCountEntrance) tabCountEntrance.textContent = entranceLogs.length;
    if (tabCountExit) {
      tabCountExit.textContent = exitLogs.length;
      const hasBlockedExit = exitLogs.some(l => l.action === 'Exit Denied' || (l.notes && l.notes.toLowerCase().includes('exit denied')));
      if (hasBlockedExit) {
        tabCountExit.className = "px-1.5 py-0.2 rounded-full text-[10px] font-extrabold bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30";
      } else {
        tabCountExit.className = "px-1.5 py-0.2 rounded-full text-[10px] font-extrabold bg-slate-100 text-slate-700 border border-slate-200";
      }
    }

    if (flaggedSidebarCount) {
      flaggedSidebarCount.textContent = activeIncidents;
      if (activeIncidents > 0) {
        flaggedSidebarCount.className = "text-[10px] px-2 py-0.5 rounded-full font-bold bg-rose-500 text-white shadow-xs";
      } else {
        flaggedSidebarCount.className = "text-[10px] px-2 py-0.5 rounded-full font-bold bg-white/15 text-white border border-white/20 shadow-2xs";
      }
    }

    if (incidentQueueBadge) {
      incidentQueueBadge.textContent = `${activeIncidents} Active ${activeIncidents === 1 ? 'Case' : 'Cases'}`;
      if (activeIncidents > 0) {
        incidentQueueBadge.className = "text-xs px-2.5 py-0.5 rounded-full font-bold bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30";
      } else {
        incidentQueueBadge.className = "text-xs px-2.5 py-0.5 rounded-full font-bold bg-slate-100 text-slate-600 border border-slate-200";
      }
    }
  }

  /* ==========================================================================
     3. Dashboard Controller & Analytics
     ========================================================================== */
  // Configure Chart.js global typography and branding defaults if available
  if (typeof Chart !== 'undefined') {
    Chart.defaults.font.family = '"Plus Jakarta Sans", system-ui, sans-serif';
    Chart.defaults.font.size = 11;
    Chart.defaults.color = '#64748B';
    Chart.defaults.plugins.tooltip.backgroundColor = '#0F172A';
    Chart.defaults.plugins.tooltip.padding = 8;
    Chart.defaults.plugins.tooltip.cornerRadius = 6;
    Chart.defaults.plugins.tooltip.titleFont = { size: 11, weight: 'bold' };
    Chart.defaults.plugins.tooltip.bodyFont = { size: 11 };
  }

  // 3.1 Gate Activity Trend Chart (Hourly Today / By Gate)
  function renderActivityTrendChart(mode = trendViewMode) {
    if (typeof Chart === 'undefined' || !gateActivityChartCanvas) return;

    if (charts.activityTrend) {
      charts.activityTrend.destroy();
      charts.activityTrend = null;
    }

    if (mode === 'hourly') {
      const labels = ['6 AM', '7 AM', '8 AM', '9 AM', '10 AM', '11 AM', '12 PM', '1 PM', '2 PM', '3 PM', '4 PM', '5 PM'];
      const counts = new Array(labels.length).fill(0);

      state.auditLogs.forEach(log => {
        const timePart = (log.timestamp || '').replace(/Today,\s*/i, '').trim();
        const m = timePart.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i);
        if (m) {
          let h = parseInt(m[1], 10);
          const ampm = m[3].toUpperCase();
          if (ampm === 'PM' && h < 12) h += 12;
          if (ampm === 'AM' && h === 12) h = 0;
          const idx = h - 6;
          if (idx >= 0 && idx < counts.length) {
            counts[idx]++;
          }
        }
      });

      charts.activityTrend = new Chart(gateActivityChartCanvas, {
        type: 'bar',
        data: {
          labels,
          datasets: [{
            label: 'Passages',
            data: counts,
            backgroundColor: '#1A3B8B',
            borderRadius: 2,
            barThickness: 18
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                label: (ctx) => ` ${ctx.parsed.y} passage${ctx.parsed.y === 1 ? '' : 's'} recorded`
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { font: { size: 10 }, color: '#64748B' }
            },
            y: {
              beginAtZero: true,
              suggestedMax: 3,
              ticks: {
                stepSize: 1,
                font: { size: 10, family: 'JetBrains Mono' },
                color: '#64748B'
              },
              grid: { color: '#F1F5F9' }
            }
          }
        }
      });
    } else {
      // By Gate Mode
      const gateCounts = {
        'Gate 1 (Main Ingress)': 0,
        'Gate 2 (Main Egress)': 0,
        'Gate 3 (Motorcycle & Bike)': 0
      };

      state.auditLogs.forEach(log => {
        const pt = log.gatePoint || '';
        if (pt.includes('Gate 1')) gateCounts['Gate 1 (Main Ingress)']++;
        else if (pt.includes('Gate 2')) gateCounts['Gate 2 (Main Egress)']++;
        else if (pt.includes('Gate 3')) gateCounts['Gate 3 (Motorcycle & Bike)']++;
      });

      const labels = ['Gate 1 (Ingress)', 'Gate 2 (Egress)', 'Gate 3 (Moto/Bike)'];
      const data = [
        gateCounts['Gate 1 (Main Ingress)'],
        gateCounts['Gate 2 (Main Egress)'],
        gateCounts['Gate 3 (Motorcycle & Bike)']
      ];

      charts.activityTrend = new Chart(gateActivityChartCanvas, {
        type: 'bar',
        data: {
          labels,
          datasets: [{
            label: 'Passages Recorded',
            data,
            backgroundColor: '#1A3B8B',
            borderRadius: 4,
            barThickness: 36
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                label: (ctx) => ` ${ctx.parsed.y} recorded events`
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { font: { size: 10 }, color: '#64748B' }
            },
            y: {
              beginAtZero: true,
              suggestedMax: 4,
              ticks: {
                stepSize: 1,
                font: { size: 10, family: 'JetBrains Mono' },
                color: '#64748B'
              },
              grid: { color: '#F1F5F9' }
            }
          }
        }
      });
    }
  }

  // 3.2 Current Gate Status Donut Chart
  function renderGateStatusChart() {
    if (typeof Chart === 'undefined' || !gateStatusChartCanvas) return;

    if (charts.gateStatus) {
      charts.gateStatus.destroy();
      charts.gateStatus = null;
    }

    const insideCount = state.onCampus && state.onCampus.counts
      ? state.onCampus.counts.total
      : (state.vehicles.filter(v => v.status === 'Inside Campus').length +
         (state.visitors || []).filter(v => v.entryTime && !v.exitTime && (v.status === 'Active' || (v.status || '').toLowerCase().includes('inside'))).length);
    const exitedCount = state.vehicles.filter(v => v.status === 'Exited' || v.status === 'Outside').length;
    const activeIncidents = state.incidents.filter(i => i.status === 'Held').length;
    const blockedCount = activeIncidents > 0 ? activeIncidents : state.vehicles.filter(v => v.status === 'Blocked / Alert').length;

    if (legendInsideCount) legendInsideCount.textContent = insideCount;
    if (legendExitedCount) legendExitedCount.textContent = exitedCount;
    if (legendBlockedCount) legendBlockedCount.textContent = blockedCount;
    if (donutCenterTotal) donutCenterTotal.textContent = insideCount;

    charts.gateStatus = new Chart(gateStatusChartCanvas, {
      type: 'doughnut',
      data: {
        labels: ['Inside Campus', 'Exited', 'Blocked / Alert'],
        datasets: [{
          data: [insideCount, exitedCount, blockedCount],
          backgroundColor: ['#16A34A', '#94A3B8', '#D92128'],
          borderWidth: 2,
          borderColor: '#FFFFFF',
          hoverOffset: 4
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '70%',
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.label}: ${ctx.parsed} vehicles`
            }
          }
        }
      }
    });
  }

  // 3.3 Registered Fleet Types Composition Bar Chart
  function renderFleetTypesChart() {
    if (typeof Chart === 'undefined' || !fleetTypesChartCanvas) return;

    if (charts.fleetTypes) {
      charts.fleetTypes.destroy();
      charts.fleetTypes = null;
    }

    const count4W = state.vehicles.filter(v => v.vehicleType && v.vehicleType.toLowerCase().includes('4-wheel')).length;
    const countMoto = state.vehicles.filter(v => v.vehicleType && v.vehicleType.toLowerCase().includes('motorcycle')).length;
    const countBike = state.vehicles.filter(v => v.vehicleType && (v.vehicleType.toLowerCase().includes('bicycle') || v.vehicleType.toLowerCase().includes('bike') || v.vehicleType.toLowerCase().includes('non-plated'))).length;
    const countFleet = state.vehicles.filter(v => v.vehicleType && v.vehicleType.toLowerCase().includes('fleet')).length;

    if (fleetTotalBadge) fleetTotalBadge.textContent = state.vehicles.length;

    charts.fleetTypes = new Chart(fleetTypesChartCanvas, {
      type: 'bar',
      data: {
        labels: ['4-Wheel', 'Motorcycle', 'Bicycle', 'Fleet Shuttle'],
        datasets: [{
          label: 'Vehicles',
          data: [count4W, countMoto, countBike, countFleet],
          backgroundColor: ['#1A3B8B', '#2B4EA2', '#475569', '#0F265C'],
          borderRadius: 4,
          barThickness: 24
        }]
      },
      options: {
        indexAxis: 'y',
        responsive: true,
        maintainAspectRatio: false,
        layout: {
          padding: {
            left: 10,
            right: 14
          }
        },
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.parsed.x} registered vehicle${ctx.parsed.x === 1 ? '' : 's'}`
            }
          }
        },
        scales: {
          x: {
            beginAtZero: true,
            suggestedMax: 5,
            ticks: {
              stepSize: 1,
              font: { size: 10, family: 'JetBrains Mono' },
              color: '#64748B'
            },
            grid: { color: '#F1F5F9' }
          },
          y: {
            grid: { display: false },
            ticks: {
              font: { size: 10, weight: '500' },
              color: '#334155',
              padding: 6
            }
          }
        }
      }
    });
  }

  // 3.4 Requires Attention Security Panel
  function renderAttentionPanel() {
    if (!attentionPanelContent) return;
    attentionPanelContent.innerHTML = '';

    const activeIncidents = state.incidents.filter(i => i.status === 'Held');
    const heldPlates = new Set(activeIncidents.map(i => (i.plateNumber || '').replace(/[-\s]/g, '').toUpperCase()));

    // Also include any recent Exit Denied events that don't have an active incident case yet
    const unheldExitDeniedLogs = state.auditLogs.filter(l => {
      const isDenied = l.action === 'Exit Denied' || (l.action && l.action.toLowerCase().includes('exit') && l.action.toLowerCase().includes('denied'));
      if (!isDenied) return false;
      const norm = (l.plateNumber || '').replace(/[-\s]/g, '').toUpperCase();
      return norm && !heldPlates.has(norm);
    });

    const totalAttention = activeIncidents.length + unheldExitDeniedLogs.length;

    if (attentionCountBadge) {
      attentionCountBadge.textContent = `${totalAttention} Active`;
      if (totalAttention > 0) {
        attentionCountBadge.className = "text-[10px] px-1.5 py-0.5 rounded font-bold bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30";
      } else {
        attentionCountBadge.className = "text-[10px] px-1.5 py-0.5 rounded font-bold bg-slate-100 text-slate-600 border border-slate-200";
      }
    }

    if (totalAttention === 0) {
      attentionPanelContent.innerHTML = `
        <div class="h-full min-h-[110px] flex items-center justify-center p-3 rounded-lg border border-dashed border-slate-200 bg-slate-50/70 text-center">
          <div>
            <div class="w-6 h-6 rounded-full bg-ncst-greenLight text-ncst-greenDark mx-auto flex items-center justify-center font-bold text-xs mb-1.5">
              ✓
            </div>
            <div class="text-xs font-bold text-slate-800">All Campus Gates Normal</div>
            <div class="text-[11px] text-slate-500 mt-0.5">No active security holds or unauthorized vehicle stops.</div>
          </div>
        </div>
      `;
      return;
    }

    activeIncidents.forEach(inc => {
      const card = document.createElement('div');
      card.className = 'p-2.5 rounded-r-lg border-y border-r border-ncst-crimson/20 border-l-4 border-l-ncst-crimson bg-ncst-crimsonLight/40 hover:bg-ncst-crimsonLight/70 transition-colors';

      card.innerHTML = `
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="font-mono font-bold text-xs bg-white text-slate-900 px-1.5 py-0.5 rounded border border-slate-200 shadow-xs">${escapeHtml(inc.plateNumber)}</span>
            <span class="px-1.5 py-0.2 rounded text-[10px] font-bold bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30">HELD AT GATE</span>
          </div>
          <span class="text-[11px] font-mono text-slate-500">${escapeHtml(inc.timestamp.replace('Today, ', ''))}</span>
        </div>
        <div class="text-xs font-semibold text-ncst-crimson mt-1">${escapeHtml(inc.reason)}</div>
        <div class="grid grid-cols-2 gap-2 mt-1 text-[11px] text-slate-600">
          <div>Operator: <span class="font-medium text-slate-800">${escapeHtml(inc.driverName)}</span></div>
          <div>Owner: <span class="font-medium text-slate-800">${escapeHtml(inc.ownerName)}</span></div>
        </div>
        <div class="mt-2 flex items-center justify-between pt-1.5 border-t border-ncst-crimson/20">
          <span class="text-[10px] text-slate-500 font-mono">${escapeHtml(inc.caseNumber)} • ${escapeHtml(inc.gatePoint)}</span>
          <button type="button" class="investigate-card-btn text-xs font-bold text-ncst-navy hover:underline">
            Investigate Incident →
          </button>
        </div>
      `;

      card.querySelector('.investigate-card-btn').addEventListener('click', () => {
        openIncidentDrawer(inc);
      });

      attentionPanelContent.appendChild(card);
    });

    unheldExitDeniedLogs.forEach(log => {
      const card = document.createElement('div');
      card.className = 'p-2.5 rounded-r-lg border-y border-r border-ncst-crimson/20 border-l-4 border-l-ncst-crimson bg-ncst-crimsonLight/40 hover:bg-ncst-crimsonLight/70 transition-colors';

      card.innerHTML = `
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="font-mono font-bold text-xs bg-white text-slate-900 px-1.5 py-0.5 rounded border border-slate-200 shadow-xs">${escapeHtml(log.plateNumber)}</span>
            <span class="px-1.5 py-0.2 rounded text-[10px] font-bold bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30">EXIT BLOCKED</span>
          </div>
          <span class="text-[11px] font-mono text-slate-500">${escapeHtml(log.timestamp.replace('Today, ', ''))}</span>
        </div>
        <div class="text-xs font-semibold text-ncst-crimson mt-1">${escapeHtml(log.notes || 'Exit Denied at gate')}</div>
        <div class="grid grid-cols-2 gap-2 mt-1 text-[11px] text-slate-600">
          <div>Operator: <span class="font-medium text-slate-800">${escapeHtml(log.driverName)}</span></div>
          <div>Owner: <span class="font-medium text-slate-800">${escapeHtml(log.ownerName)}</span></div>
        </div>
        <div class="mt-2 flex items-center justify-between pt-1.5 border-t border-ncst-crimson/20">
          <span class="text-[10px] text-slate-500 font-mono">Held at ${escapeHtml(log.gatePoint)}</span>
          <button type="button" class="investigate-log-btn text-xs font-bold text-ncst-navy hover:underline">
            Inspect Gate Hold →
          </button>
        </div>
      `;

      card.querySelector('.investigate-log-btn').addEventListener('click', () => {
        openAuditDrawer(log);
      });

      attentionPanelContent.appendChild(card);
    });
  }

  // 3.5 Bind Dashboard Chart Toggles & Links
  if (activityTrendHourlyBtn) {
    activityTrendHourlyBtn.addEventListener('click', () => {
      trendViewMode = 'hourly';
      activityTrendHourlyBtn.className = "px-2.5 py-1 rounded text-xs font-semibold bg-white text-slate-900 shadow-xs transition-colors";
      activityTrendGateBtn.className = "px-2.5 py-1 rounded text-xs font-medium text-slate-600 hover:text-slate-900 transition-colors";
      renderActivityTrendChart('hourly');
    });
  }

  if (activityTrendGateBtn) {
    activityTrendGateBtn.addEventListener('click', () => {
      trendViewMode = 'gate';
      activityTrendGateBtn.className = "px-2.5 py-1 rounded text-xs font-semibold bg-white text-slate-900 shadow-xs transition-colors";
      activityTrendHourlyBtn.className = "px-2.5 py-1 rounded text-xs font-medium text-slate-600 hover:text-slate-900 transition-colors";
      renderActivityTrendChart('gate');
    });
  }

  if (viewAllIncidentsLink) {
    viewAllIncidentsLink.addEventListener('click', () => switchView('flaggedView'));
  }

  // 3.6 Dwell & Time Helpers for Gate Operations
  function formatDwell(hours) {
    if (hours == null || isNaN(hours)) return '—';
    if (hours < (1 / 60)) return '< 1 min';
    const totalMinutes = Math.round(hours * 60);
    const h = Math.floor(totalMinutes / 60);
    const m = totalMinutes % 60;
    if (h === 0) return `${m}m`;
    if (m === 0) return `${h}h`;
    return `${h}h ${m}m`;
  }

  function calcDurationBetween(startStr, endStr) {
    if (!startStr || !endStr) return '—';
    try {
      const s = new Date(String(startStr).replace(' ', 'T').replace(' • ', ' ') + '+08:00').getTime();
      const e = new Date(String(endStr).replace(' ', 'T').replace(' • ', ' ') + '+08:00').getTime();
      if (isNaN(s) || isNaN(e) || e < s) return '—';
      const hours = (e - s) / 3600000;
      return formatDwell(hours);
    } catch (_) {
      return '—';
    }
  }

  // 3.7 Gate Flow Operations Center Controller
  function initGateFlowTabs() {
    if (tabCurrentlyInsideBtn) {
      tabCurrentlyInsideBtn.addEventListener('click', () => switchGateFlowTab('inside'));
    }
    if (tabEntranceBtn) {
      tabEntranceBtn.addEventListener('click', () => switchGateFlowTab('entrance'));
    }
    if (tabExitBtn) {
      tabExitBtn.addEventListener('click', () => switchGateFlowTab('exit'));
    }
  }

  function switchGateFlowTab(tab) {
    state.gateFlowTab = tab;
    const tabs = [
      { id: 'inside', btn: tabCurrentlyInsideBtn, pane: paneCurrentlyInside, subtext: 'Real-time campus custody: Registered vehicles, visitors, and security-held vehicles currently inside campus' },
      { id: 'entrance', btn: tabEntranceBtn, pane: paneEntrance, subtext: 'Recent gate ingresses: Vehicles and visitors processed at entrance gates' },
      { id: 'exit', btn: tabExitBtn, pane: paneExit, subtext: 'Recent gate egresses: Departed vehicles, dwell durations, and blocked or flagged exit attempts' }
    ];

    tabs.forEach(t => {
      if (!t.btn || !t.pane) return;
      const isActive = t.id === tab;
      t.btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
      if (isActive) {
        t.pane.classList.remove('hidden');
        t.btn.className = 'gate-flow-tab px-3 py-1.5 rounded-md text-xs font-bold transition-all bg-white text-ncst-navy shadow-xs flex items-center gap-1.5';
        if (gateFlowSubtext) gateFlowSubtext.textContent = t.subtext;
      } else {
        t.pane.classList.add('hidden');
        t.btn.className = 'gate-flow-tab px-3 py-1.5 rounded-md text-xs font-semibold transition-all text-slate-600 hover:text-slate-900 flex items-center gap-1.5';
      }
    });
  }

  // Security Hold & Flagged Status Resolver
  function getActiveHoldInfo(plate) {
    if (!plate) return null;
    const norm = String(plate).replace(/[-\s]/g, '').toUpperCase();

    // 1. Check active security incidents (status === 'Held')
    const inc = (state.incidents || []).find(i => 
      i.status === 'Held' && 
      (i.plateNumber || '').replace(/[-\s]/g, '').toUpperCase() === norm
    );
    if (inc) {
      return {
        type: 'incident',
        badge: 'BLOCKED (HELD)',
        reason: inc.reason || 'Active Security Hold',
        caseNumber: inc.caseNumber,
        notes: inc.notes,
        id: inc.id,
        officer: inc.officer,
        reportedAt: inc.timestamp || inc.reportedAt
      };
    }

    // 2. Check recent Exit Denied in auditLogs
    const deniedExit = (state.auditLogs || []).find(l => 
      (l.plateNumber || '').replace(/[-\s]/g, '').toUpperCase() === norm &&
      (l.action === 'Exit Denied' || (l.action && l.action.toLowerCase().includes('exit') && l.action.toLowerCase().includes('denied')))
    );
    if (deniedExit) {
      return {
        type: 'exit_denied',
        badge: 'EXIT BLOCKED',
        reason: deniedExit.notes || 'Exit Denied at gate verification',
        gatePoint: deniedExit.gatePoint,
        id: deniedExit.id,
        guard: deniedExit.guardName
      };
    }

    // 3. Check vehicle record standing
    const veh = (state.vehicles || []).find(v => 
      (v.plateNumber || '').replace(/[-\s]/g, '').toUpperCase() === norm
    );
    if (veh) {
      if (veh.isBanned) {
        return {
          type: 'banned',
          badge: 'BANNED',
          reason: 'Vehicle banned from campus (3+ strikes)',
          id: veh.id
        };
      }
      if (veh.status === 'Blocked / Alert') {
        return {
          type: 'blocked',
          badge: 'BLOCKED',
          reason: 'Flagged on Security Watchlist',
          id: veh.id
        };
      }
      if (veh.registrationStatus === 'Suspended') {
        return {
          type: 'suspended',
          badge: 'SUSPENDED',
          reason: 'Registration Suspended',
          id: veh.id
        };
      }
    }

    return null;
  }

  // TABLE 1: CURRENTLY INSIDE / PERMITTED ON CAMPUS (Active Physical Custody)
  function renderCurrentlyInsideTable() {
    if (!currentlyInsideTableBody) return;
    currentlyInsideTableBody.innerHTML = '';

    // Collect registered vehicles currently inside
    let vehiclesInside = [];
    if (state.onCampus && Array.isArray(state.onCampus.vehicles)) {
      vehiclesInside = state.onCampus.vehicles;
    } else {
      vehiclesInside = state.vehicles
        .filter(v => (v.status || '').toLowerCase().includes('inside') || v.status === 'Blocked / Alert')
        .map(v => ({
          vehicleId: v.id,
          plateNumber: v.plateNumber,
          vehicleType: v.vehicleType,
          makeModelColor: v.makeModelColor,
          ownerName: v.ownerName,
          ownerRole: v.ownerRole,
          department: v.department,
          ownerPhone: v.ownerPhone,
          entryTime: v.entryTime,
          admittedBy: v.admittedBy || 'Officer',
          entryGate: v.entryGate || v.gatePoint || 'Gate 1',
          hoursInside: null,
          status: v.status
        }));
    }

    // Collect visitors currently inside (must have entryTime and no exitTime)
    let visitorsInside = [];
    if (state.onCampus && Array.isArray(state.onCampus.visitors)) {
      visitorsInside = state.onCampus.visitors;
    } else {
      visitorsInside = (state.visitors || [])
        .filter(v => v.entryTime && !v.exitTime && (v.status === 'Active' || (v.status || '').toLowerCase().includes('inside')))
        .map(v => ({
          passId: v.id,
          passCode: v.passCode || v.pass_code,
          plateNumber: v.plateNumber || v.plate,
          vehicleModel: v.vehicleModel || v.vehicle_model || 'Visitor Vehicle',
          visitorName: v.visitorName || v.visitor_name,
          contactNumber: v.contactNumber || v.contact_number,
          personToVisit: v.personToVisit || v.person_to_visit,
          purposeOfVisit: v.purposeOfVisit || v.purpose,
          entryTime: v.entryTime,
          hoursInside: null
        }));
    }

    // Arrival order, earliest entry first (same order as the On Campus page)
    const byArrival = (a, b) => {
      const ta = a.entryTime ? new Date(String(a.entryTime).replace(' ', 'T') + '+08:00').getTime() : Infinity;
      const tb = b.entryTime ? new Date(String(b.entryTime).replace(' ', 'T') + '+08:00').getTime() : Infinity;
      return ta === tb ? 0 : ta - tb;
    };
    vehiclesInside = [...vehiclesInside].sort(byArrival);
    visitorsInside = [...visitorsInside].sort(byArrival);

    const totalInside = vehiclesInside.length + visitorsInside.length;

    if (totalInside === 0) {
      currentlyInsideTableBody.innerHTML = `
        <tr>
          <td colspan="9" class="py-10 text-center text-slate-400 text-xs">
            <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-emerald-50 text-emerald-600 mb-2 font-bold">✓</div>
            <div class="font-semibold text-slate-700">No vehicles or visitors currently inside campus</div>
            <div class="text-[11px] text-slate-400 mt-0.5">All authorized entries have departed through exit gates.</div>
          </td>
        </tr>
      `;
      return;
    }

    // Render registered vehicles inside
    vehiclesInside.forEach(v => {
      const tr = document.createElement('tr');

      const hold = (v.activeHold && v.activeHold.caseNumber)
        ? {
            type: 'incident',
            badge: 'BLOCKED (HELD)',
            reason: v.activeHold.reason,
            caseNumber: v.activeHold.caseNumber,
            notes: v.activeHold.notes,
            id: v.activeHold.id
          }
        : getActiveHoldInfo(v.plateNumber);

      const isExitBlocked = Boolean(v.exitDenied || (hold && hold.type === 'exit_denied'));
      const isBlockedOrHeld = Boolean(hold || v.exitDenied || v.isBanned || v.status === 'Blocked / Alert');

      if (isBlockedOrHeld) {
        tr.className = 'hover:bg-rose-50/70 bg-rose-50/25 border-l-4 border-l-ncst-crimson transition-colors';
      } else {
        tr.className = 'hover:bg-slate-50/80 transition-colors';
      }

      const fullVeh = state.vehicles.find(x => x.plateNumber === v.plateNumber || x.id === v.vehicleId);
      const studentId = fullVeh ? (fullVeh.ownerIdNumber || fullVeh.owner_id_number || '') : '';
      const isStudent = (v.ownerRole || '').toLowerCase().includes('student');

      let statusBadge = `
        <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200/80">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
          INSIDE
        </span>
      `;

      if (isExitBlocked) {
        statusBadge = `
          <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200 shadow-2xs">
            <span class="w-1.5 h-1.5 rounded-full bg-rose-600 animate-ping"></span>
            EXIT BLOCKED (HELD)
          </span>
        `;
      } else if (isBlockedOrHeld) {
        const badgeText = hold ? hold.badge : 'BLOCKED (HELD)';
        statusBadge = `
          <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200 shadow-2xs">
            <span class="w-1.5 h-1.5 rounded-full bg-rose-600"></span>
            ${escapeHtml(badgeText)}
          </span>
        `;
      }

      const holdAlertSnippet = isBlockedOrHeld ? `
        <div class="text-[10px] font-bold text-rose-700 mt-0.5 flex items-center gap-1">
          <svg class="w-3 h-3 text-rose-600 shrink-0" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>
          <span class="truncate max-w-[170px]" title="${escapeHtml(isExitBlocked ? 'Exit attempt intercepted & blocked at gate' : (hold ? (hold.notes || hold.reason) : 'Security Hold'))}">
            ${escapeHtml(isExitBlocked ? 'Exit intercepted & blocked at gate' : (hold ? hold.reason : 'Security Hold'))}
          </span>
        </div>
      ` : '';

      let dwellBadge = `
        <span class="font-mono font-bold text-emerald-800 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200 text-xs">
          ${formatDwell(v.hoursInside)}
        </span>
      `;
      if (isBlockedOrHeld) {
        dwellBadge = `
          <span class="font-mono font-bold text-rose-700 bg-rose-50 px-1.5 py-0.5 rounded border border-rose-200 text-xs">
            ${formatDwell(v.hoursInside)} <span class="text-[10px] font-extrabold">(HELD)</span>
          </span>
        `;
      }

      let actionBtn = `
        <button type="button" class="inspect-inside-btn px-2.5 py-1 rounded-md border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs transition-colors">
          Inspect
        </button>
      `;
      if (isBlockedOrHeld) {
        actionBtn = `
          <button type="button" class="inspect-inside-btn px-2.5 py-1 rounded-md border border-rose-200 bg-rose-50 hover:bg-rose-100 text-rose-700 text-xs font-bold shadow-2xs transition-colors" title="Inspect Security Hold">
            ${hold && hold.caseNumber ? escapeHtml(hold.caseNumber) : 'Inspect Hold'}
          </button>
        `;
      }

      tr.innerHTML = `
        <td class="py-2.5 px-3.5">
          ${statusBadge}
        </td>
        <td class="py-2.5 px-3.5 font-mono font-extrabold text-slate-900">
          <div>${escapeHtml(v.plateNumber)}</div>
          ${holdAlertSnippet}
        </td>
        <td class="py-2.5 px-3.5">
          <div class="font-semibold text-slate-900">${escapeHtml(v.ownerName)}</div>
          <div class="text-[10px] text-slate-500">${escapeHtml(v.department || v.ownerPhone || '')}</div>
        </td>
        <td class="py-2.5 px-3.5">
          <span class="px-1.5 py-0.5 rounded text-[10px] font-bold ${isStudent ? 'bg-blue-50 text-blue-700 border border-blue-200' : 'bg-slate-100 text-slate-700 border border-slate-200'}">
            ${escapeHtml(v.ownerRole || 'Registered')}
          </span>
          ${studentId ? `<div class="font-mono text-[10px] text-slate-500 mt-0.5">${escapeHtml(studentId)}</div>` : ''}
        </td>
        <td class="py-2.5 px-3.5 text-slate-700">
          <div>${escapeHtml(v.vehicleType || 'Vehicle')}</div>
          <div class="text-[10px] text-slate-400 truncate max-w-[140px]">${escapeHtml(v.makeModelColor || '')}</div>
        </td>
        <td class="py-2.5 px-3.5 font-mono text-slate-600 text-xs">
          ${escapeHtml(v.entryTime ? String(v.entryTime).replace('Today, ', '') : '—')}
        </td>
        <td class="py-2.5 px-3.5">
          ${dwellBadge}
        </td>
        <td class="py-2.5 px-3.5 text-slate-600 text-[11px]">
          <div>${escapeHtml(v.entryGate || 'Main Ingress')}</div>
          <div class="text-slate-400">${escapeHtml(v.admittedBy || 'Officer')}</div>
        </td>
        <td class="py-2.5 px-3.5 text-right">
          ${actionBtn}
        </td>
      `;

      tr.querySelector('.inspect-inside-btn').addEventListener('click', () => {
        if (hold && hold.caseNumber) {
          const incObj = state.incidents.find(i => i.caseNumber === hold.caseNumber || i.id === hold.id);
          if (incObj) {
            openIncidentDrawer(incObj);
            return;
          }
        }
        if (fullVeh) openVehicleDrawer(fullVeh);
        else openVehicleDrawer(v);
      });

      currentlyInsideTableBody.appendChild(tr);
    });

    // Render visitors inside
    visitorsInside.forEach(vp => {
      const tr = document.createElement('tr');

      const hold = (vp.activeHold && vp.activeHold.caseNumber)
        ? {
            type: 'incident',
            badge: 'BLOCKED (HELD)',
            reason: vp.activeHold.reason,
            caseNumber: vp.activeHold.caseNumber,
            notes: vp.activeHold.notes,
            id: vp.activeHold.id
          }
        : getActiveHoldInfo(vp.plateNumber);

      const isExitBlocked = Boolean(vp.exitDenied || (hold && hold.type === 'exit_denied'));
      const isBlockedOrHeld = Boolean(hold || vp.exitDenied);

      if (isBlockedOrHeld) {
        tr.className = 'hover:bg-rose-50/70 bg-rose-50/25 border-l-4 border-l-ncst-crimson transition-colors';
      } else {
        tr.className = 'hover:bg-slate-50/80 transition-colors bg-blue-50/10';
      }

      let statusBadge = `
        <span class="px-2 py-0.5 rounded text-[11px] font-extrabold bg-ncst-greenLight text-ncst-greenDark border border-ncst-green/30">
          INSIDE
        </span>
      `;

      if (isExitBlocked) {
        statusBadge = `
          <span class="px-2 py-0.5 rounded text-[11px] font-extrabold bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30 inline-flex items-center gap-1 shadow-xs">
            <span class="w-1.5 h-1.5 rounded-full bg-ncst-crimson animate-ping"></span>
            EXIT BLOCKED (HELD)
          </span>
        `;
      } else if (isBlockedOrHeld) {
        const badgeText = hold ? hold.badge : 'BLOCKED (HELD)';
        statusBadge = `
          <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200 shadow-2xs">
            <span class="w-1.5 h-1.5 rounded-full bg-rose-600"></span>
            ${escapeHtml(badgeText)}
          </span>
        `;
      }

      const holdAlertSnippet = isBlockedOrHeld ? `
        <div class="text-[10px] font-bold text-rose-700 mt-0.5 flex items-center gap-1">
          <svg class="w-3 h-3 text-rose-600 shrink-0" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>
          <span class="truncate max-w-[170px]" title="${escapeHtml(isExitBlocked ? 'Exit attempt intercepted & blocked' : (hold ? (hold.notes || hold.reason) : 'Security Hold'))}">
            ${escapeHtml(isExitBlocked ? 'Exit intercepted & blocked' : (hold ? hold.reason : 'Security Hold'))}
          </span>
        </div>
      ` : '';

      let dwellBadge = `
        <span class="font-mono font-bold text-emerald-800 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200 text-xs">
          ${formatDwell(vp.hoursInside)}
        </span>
      `;
      if (isBlockedOrHeld) {
        dwellBadge = `
          <span class="font-mono font-bold text-rose-700 bg-rose-50 px-1.5 py-0.5 rounded border border-rose-200 text-xs">
            ${formatDwell(vp.hoursInside)} <span class="text-[10px] font-extrabold">(HELD)</span>
          </span>
        `;
      }

      let actionBtn = `
        <button type="button" class="inspect-inside-btn px-2.5 py-1 rounded-md border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs transition-colors">
          View Pass
        </button>
      `;
      if (isBlockedOrHeld) {
        actionBtn = `
          <button type="button" class="inspect-inside-btn px-2.5 py-1 rounded-md border border-rose-200 bg-rose-50 hover:bg-rose-100 text-rose-700 text-xs font-bold shadow-2xs transition-colors" title="Inspect Security Hold">
            ${hold && hold.caseNumber ? escapeHtml(hold.caseNumber) : 'Inspect Hold'}
          </button>
        `;
      }

      tr.innerHTML = `
        <td class="py-2.5 px-3.5">
          ${statusBadge}
        </td>
        <td class="py-2.5 px-3.5 font-mono font-extrabold text-slate-900">
          <div>${escapeHtml(vp.plateNumber)}</div>
          ${holdAlertSnippet}
        </td>
        <td class="py-2.5 px-3.5">
          <div class="font-semibold text-slate-900">${escapeHtml(vp.visitorName)}</div>
          <div class="text-[10px] text-slate-500 font-mono">${escapeHtml(vp.contactNumber || '')}</div>
        </td>
        <td class="py-2.5 px-3.5">
          <span class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-ncst-navy/10 text-ncst-navy border border-ncst-navy/20">
            Visitor Day Pass
          </span>
          <div class="font-mono text-[10px] text-slate-500 mt-0.5">${escapeHtml(vp.passCode || '')}</div>
        </td>
        <td class="py-2.5 px-3.5 text-slate-700">
          <div>${escapeHtml(vp.vehicleModel || 'Visitor Vehicle')}</div>
          <div class="text-[10px] text-slate-400">Visiting: ${escapeHtml(vp.personToVisit || 'Campus')}</div>
        </td>
        <td class="py-2.5 px-3.5 font-mono text-slate-600 text-xs">
          ${escapeHtml(vp.entryTime ? String(vp.entryTime).replace('Today, ', '') : '—')}
        </td>
        <td class="py-2.5 px-3.5">
          ${dwellBadge}
        </td>
        <td class="py-2.5 px-3.5 text-slate-600 text-[11px]">
          <div>Gate 1 (Visitor)</div>
          <div class="text-slate-400">Verified Pass</div>
        </td>
        <td class="py-2.5 px-3.5 text-right">
          ${actionBtn}
        </td>
      `;

      tr.querySelector('.inspect-inside-btn').addEventListener('click', () => {
        if (hold && hold.caseNumber) {
          const incObj = state.incidents.find(i => i.caseNumber === hold.caseNumber || i.id === hold.id);
          if (incObj) {
            openIncidentDrawer(incObj);
            return;
          }
        }
        switchView('visitorsView');
      });

      currentlyInsideTableBody.appendChild(tr);
    });
  }

  // TABLE 2: ENTRANCE / ENTRY TABLE (Recent Gate Ingresses)
  function renderEntranceTable() {
    if (!entranceTableBody) return;
    entranceTableBody.innerHTML = '';

    const entranceLogs = state.auditLogs
      .filter(l => l.action === 'Entry Recorded' || l.action === 'Entry Denied' || l.gateType === 'Entry' || l.gateType === 'Ingress' || (l.action && l.action.toLowerCase().includes('entry')))
      .slice(0, 15);

    if (entranceLogs.length === 0) {
      entranceTableBody.innerHTML = `
        <tr>
          <td colspan="9" class="py-10 text-center text-slate-400 text-xs">
            No entrance passages recorded today.
          </td>
        </tr>
      `;
      return;
    }

    entranceLogs.forEach(log => {
      const tr = document.createElement('tr');
      const isDenied = log.action === 'Entry Denied' || (log.action && log.action.toLowerCase().includes('entry') && log.action.toLowerCase().includes('denied'));

      if (isDenied) {
        tr.className = 'hover:bg-rose-50/60 bg-rose-50/20 border-l-4 border-l-ncst-crimson transition-colors';
      } else {
        tr.className = 'hover:bg-slate-50 transition-colors';
      }

      const fullVeh = state.vehicles.find(x => x.plateNumber === log.plateNumber);
      const studentId = fullVeh ? (fullVeh.ownerIdNumber || fullVeh.owner_id_number || '') : '';
      const passInfo = isDenied 
        ? `<span class="text-ncst-crimson font-semibold text-xs">${escapeHtml(log.notes ? log.notes.split('|')[0] : 'Entry Denied')}</span>`
        : (fullVeh ? `Pass ${fullVeh.stickerYear || '2026'}` : (log.notes ? escapeHtml(log.notes.split('|')[0]) : 'Standard Pass'));

      const statusBadge = isDenied ? `
        <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200 shadow-2xs">
          <span class="w-1.5 h-1.5 rounded-full bg-rose-600"></span>
          ENTRY DENIED
        </span>
      ` : `
        <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200/80">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
          INSIDE
        </span>
      `;

      tr.innerHTML = `
        <td class="py-2.5 px-3.5">
          ${statusBadge}
        </td>
        <td class="py-2.5 px-3.5 font-mono font-bold text-slate-900">
          ${escapeHtml(log.plateNumber)}
        </td>
        <td class="py-2.5 px-3.5">
          <div class="font-semibold text-slate-800">${escapeHtml(log.ownerName)}</div>
          ${studentId ? `<div class="text-[10px] text-slate-500 font-mono">ID: ${escapeHtml(studentId)}</div>` : ''}
        </td>
        <td class="py-2.5 px-3.5 text-slate-700">
          <div>${escapeHtml(log.driverName)}</div>
          <div class="text-slate-400 text-[10px]">(${escapeHtml(log.driverRelationship || 'Self')})</div>
        </td>
        <td class="py-2.5 px-3.5 text-slate-700">
          ${escapeHtml(log.vehicleType || 'Vehicle')}
        </td>
        <td class="py-2.5 px-3.5 text-slate-600 text-xs font-mono">
          ${passInfo}
        </td>
        <td class="py-2.5 px-3.5 font-mono text-slate-500 text-xs">
          ${escapeHtml(log.timestamp.replace('Today, ', ''))}${offlineChip(log)}
        </td>
        <td class="py-2.5 px-3.5 text-slate-600 text-[11px]">
          <div>${escapeHtml(log.gatePoint)}</div>
          <div class="text-slate-400">${escapeHtml(log.guardName || 'Officer')}</div>
        </td>
        <td class="py-2.5 px-3.5 text-right">
          <button type="button" class="inspect-entrance-btn px-2.5 py-1 rounded-md border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs transition-colors" data-id="${escapeHtml(log.id)}">
            Inspect
          </button>
        </td>
      `;

      tr.querySelector('.inspect-entrance-btn').addEventListener('click', () => {
        openAuditDrawer(log);
      });

      entranceTableBody.appendChild(tr);
    });
  }

  // TABLE 3: EXIT / OUT TABLE (Recent Gate Egresses with Duration Inside)
  function renderExitTable() {
    if (!exitTableBody) return;
    exitTableBody.innerHTML = '';

    const exitLogs = state.auditLogs
      .filter(l => l.action === 'Exit Approved' || l.action === 'Exit Denied' || l.gateType === 'Exit' || l.gateType === 'Egress' || (l.action && l.action.toLowerCase().includes('exit')))
      .slice(0, 15);

    if (exitLogs.length === 0) {
      exitTableBody.innerHTML = `
        <tr>
          <td colspan="9" class="py-10 text-center text-slate-400 text-xs">
            No exit gate passages recorded today.
          </td>
        </tr>
      `;
      return;
    }

    exitLogs.forEach(log => {
      const tr = document.createElement('tr');

      const isExitDenied = log.action === 'Exit Denied' || 
                           (log.action && log.action.toLowerCase().includes('exit') && log.action.toLowerCase().includes('denied')) || 
                           (log.notes && log.notes.toLowerCase().includes('exit denied'));
      const isFlagged = !isExitDenied && (log.notes && (log.notes.toLowerCase().includes('anti-passback') || log.notes.toLowerCase().includes('attention') || log.notes.toLowerCase().includes('warning') || log.notes.toLowerCase().includes('flagged')));

      if (isExitDenied) {
        tr.className = 'hover:bg-rose-50/60 bg-rose-50/25 border-l-4 border-l-rose-500 transition-colors';
      } else if (isFlagged) {
        tr.className = 'hover:bg-amber-50/40 bg-amber-50/10 transition-colors';
      } else {
        tr.className = 'hover:bg-slate-50 transition-colors';
      }

      // Find preceding entry log for this vehicle
      const priorEntry = state.auditLogs.find(l => 
        l.plateNumber === log.plateNumber && 
        (l.action === 'Entry Recorded' || l.gateType === 'Entry' || l.gateType === 'Ingress' || (l.action && l.action.toLowerCase().includes('entry'))) && 
        (Number(l.id) < Number(log.id) || (l.loggedAt && log.loggedAt && l.loggedAt <= log.loggedAt))
      );

      const entryTimeStr = priorEntry ? priorEntry.timestamp.replace('Today, ', '') : '—';
      const durationInside = priorEntry 
        ? calcDurationBetween(priorEntry.loggedAt || priorEntry.timestamp, log.loggedAt || log.timestamp) 
        : '—';

      let statusBadge = `
        <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-medium bg-slate-100 text-slate-700 border border-slate-200">
          <span class="w-1.5 h-1.5 rounded-full bg-slate-400"></span>
          OUTSIDE
        </span>
      `;
      let durationBadge = `
        <span class="font-mono font-bold text-slate-800 bg-slate-100 px-1.5 py-0.5 rounded border border-slate-200 text-xs">
          ${durationInside}
        </span>
      `;

      if (isExitDenied) {
        statusBadge = `
          <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200 shadow-2xs">
            <span class="w-1.5 h-1.5 rounded-full bg-rose-600 animate-ping"></span>
            EXIT BLOCKED
          </span>
        `;
        durationBadge = `
          <span class="font-mono font-bold text-rose-700 bg-rose-50 px-1.5 py-0.5 rounded border border-rose-200 text-xs inline-flex items-center gap-1">
            ${durationInside} <span class="text-[10px] font-extrabold">(HELD ON CAMPUS)</span>
          </span>
        `;
      } else if (isFlagged) {
        statusBadge = `
          <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-amber-50 text-amber-800 border border-amber-200">
            <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span>
            FLAGGED EXIT
          </span>
        `;
        durationBadge = `
          <span class="font-mono font-bold text-amber-900 bg-amber-50 px-1.5 py-0.5 rounded border border-amber-200 text-xs">
            ${durationInside}
          </span>
        `;
      }

      const noteSnippet = isExitDenied ? `
        <div class="text-[10px] font-semibold text-rose-700 mt-0.5 flex items-center gap-1 truncate max-w-[180px]" title="${escapeHtml(log.notes || 'Exit intercepted & blocked')}">
          ⚠️ ${escapeHtml(log.notes || 'Exit Intercepted & Blocked')}
        </div>
      ` : (isFlagged ? `
        <div class="text-[10px] font-medium text-amber-700 mt-0.5 truncate max-w-[180px]" title="${escapeHtml(log.notes || '')}">
          ${escapeHtml(log.notes || '')}
        </div>
      ` : '');

      let actionBtn = `
        <button type="button" class="inspect-exit-btn px-2.5 py-1 rounded-md border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs transition-colors" data-id="${escapeHtml(log.id)}">
          Inspect
        </button>
      `;

      if (isExitDenied) {
        actionBtn = `
          <button type="button" class="inspect-exit-btn px-2.5 py-1 rounded-md border border-rose-200 bg-rose-50 hover:bg-rose-100 text-rose-700 text-xs font-bold shadow-2xs transition-colors" data-id="${escapeHtml(log.id)}">
            Inspect Hold
          </button>
        `;
      }

      tr.innerHTML = `
        <td class="py-2.5 px-3.5">
          ${statusBadge}
        </td>
        <td class="py-2.5 px-3.5 font-mono font-bold text-slate-900">
          <div>${escapeHtml(log.plateNumber)}</div>
          ${noteSnippet}
        </td>
        <td class="py-2.5 px-3.5 text-slate-800">
          ${escapeHtml(log.ownerName)}
        </td>
        <td class="py-2.5 px-3.5 text-slate-700">
          ${escapeHtml(log.vehicleType || 'Vehicle')}
        </td>
        <td class="py-2.5 px-3.5 font-mono text-slate-500 text-xs">
          ${escapeHtml(entryTimeStr)}
        </td>
        <td class="py-2.5 px-3.5 font-mono text-slate-900 font-semibold text-xs">
          ${escapeHtml(log.timestamp.replace('Today, ', ''))}${offlineChip(log)}
        </td>
        <td class="py-2.5 px-3.5">
          ${durationBadge}
        </td>
        <td class="py-2.5 px-3.5 text-slate-600 text-[11px]">
          <div>${escapeHtml(log.gatePoint)}</div>
          <div class="text-slate-400">${escapeHtml(log.guardName || 'Officer')}</div>
        </td>
        <td class="py-2.5 px-3.5 text-right">
          ${actionBtn}
        </td>
      `;

      tr.querySelector('.inspect-exit-btn').addEventListener('click', () => {
        openAuditDrawer(log);
      });

      exitTableBody.appendChild(tr);
    });
  }

  // 3.8 Overall Dashboard Render
  function renderDashboard() {
    updateCounts();
    renderActivityTrendChart();
    renderGateStatusChart();
    renderFleetTypesChart();
    renderAttentionPanel();

    renderCurrentlyInsideTable();
    renderEntranceTable();
    renderExitTable();
  }

  /* ==========================================================================
     4. Vehicle Directory Controller
     ========================================================================== */
  function renderVehiclesTable() {
    if (!vehiclesTableBody) return;
    vehiclesTableBody.innerHTML = '';

    const filtered = state.vehicles.filter(v => {
      const q = state.vehicleFilter.search.toLowerCase().trim();
      const matchesSearch = !q ||
        (v.plateNumber && v.plateNumber.toLowerCase().includes(q)) ||
        (v.ownerName && v.ownerName.toLowerCase().includes(q)) ||
        (v.ownerIdNumber && v.ownerIdNumber.toLowerCase().includes(q)) ||
        (v.makeModelColor && v.makeModelColor.toLowerCase().includes(q)) ||
        (v.department && v.department.toLowerCase().includes(q)) ||
        (v.ownerEmail && v.ownerEmail.toLowerCase().includes(q)) ||
        (v.ownerPhone && v.ownerPhone.toLowerCase().includes(q)) ||
        formatPassId(v).toLowerCase().includes(q) ||
        (v.qrPassCode && v.qrPassCode.toLowerCase().includes(q)) ||
        (v.authorizedDrivers || []).some(d =>
          (d.fullName && d.fullName.toLowerCase().includes(q)) ||
          (d.licenseNo && d.licenseNo.toLowerCase().includes(q)) ||
          (d.relationship && d.relationship.toLowerCase().includes(q))
        );

      const matchesRole = state.vehicleFilter.role === 'All' || v.ownerRole === state.vehicleFilter.role;

      let matchesCategory = true;
      if (state.vehicleFilter.category !== 'All') {
        matchesCategory = (v.vehicleType || '').toLowerCase().includes(state.vehicleFilter.category.toLowerCase());
      }

      const matchesLocation = state.vehicleFilter.location === 'All'
        || (state.vehicleFilter.location === 'Inside'
          ? (v.status || '').toLowerCase().includes('inside')
          : (v.status || '').toLowerCase().includes('outside'));

      let matchesStatus = true;
      if (state.vehicleFilter.status === 'VIP') {
        matchesStatus = !!v.isVip;
      } else if (state.vehicleFilter.status === 'Banned') {
        matchesStatus = !!v.isBanned;
      } else if (state.vehicleFilter.status === 'Strikes') {
        matchesStatus = (Number(v.warningCount) || 0) > 0;
      } else if (state.vehicleFilter.status !== 'All') {
        matchesStatus = v.registrationStatus === state.vehicleFilter.status;
      }

      return matchesSearch && matchesRole && matchesCategory && matchesLocation && matchesStatus;
    });

    // Update Directory Header Count Badge
    if (directoryVehicleCountBadge) {
      const totalCount = state.vehicles.length;
      if (filtered.length === totalCount) {
        directoryVehicleCountBadge.textContent = `${totalCount} ${totalCount === 1 ? 'vehicle' : 'vehicles'}`;
      } else {
        directoryVehicleCountBadge.textContent = `${filtered.length} of ${totalCount} vehicles`;
      }
    }

    if (filtered.length === 0) {
      vehiclesTableBody.innerHTML = `
        <tr>
          <td colspan="7" class="py-16 text-center">
            <div class="w-12 h-12 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center mx-auto mb-3">
              <svg class="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                <circle cx="11" cy="11" r="8"></circle>
                <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
              </svg>
            </div>
            <div class="text-sm font-semibold text-slate-800">No vehicles match current filters</div>
            <div class="text-xs text-slate-500 mt-1 max-w-sm mx-auto">Try clearing search terms or resetting filters to display campus vehicle records.</div>
            <button type="button" id="emptyResetVehiclesBtn" class="mt-4 inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs hover:border-slate-300 transition-colors cursor-pointer">
              <svg class="w-3.5 h-3.5 text-slate-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"></path>
                <path d="M3 3v5h5"></path>
              </svg>
              <span>Clear All Filters</span>
            </button>
          </td>
        </tr>
      `;
      const emptyBtn = vehiclesTableBody.querySelector('#emptyResetVehiclesBtn');
      if (emptyBtn) {
        emptyBtn.addEventListener('click', () => {
          state.vehicleFilter.search = '';
          state.vehicleFilter.role = 'All';
          state.vehicleFilter.category = 'All';
          state.vehicleFilter.location = 'All';
          state.vehicleFilter.status = 'All';
          if (vehicleSearchInput) vehicleSearchInput.value = '';
          if (vehicleRoleFilter) vehicleRoleFilter.value = 'All';
          if (vehicleCategoryFilter) vehicleCategoryFilter.value = 'All';
          if (vehicleLocationFilter) vehicleLocationFilter.value = 'All';
          if (vehicleStatusFilter) vehicleStatusFilter.value = 'All';
          renderVehiclesTable();
        });
      }
      return;
    }

    filtered.forEach(vehicle => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50/80 transition-colors group';

      // Status indicator and badge - 100% matched to vehicle standing
      let statusDot = 'bg-emerald-500';
      let statusBadge = 'bg-emerald-50 text-emerald-700 border-emerald-200/80';
      let statusLabel = vehicle.registrationStatus || 'Active';

      if (vehicle.isBanned) {
        statusDot = 'bg-rose-500';
        statusBadge = 'bg-rose-50 text-rose-700 border-rose-200';
        statusLabel = 'Banned';
      } else if (vehicle.registrationStatus === 'Suspended') {
        statusDot = 'bg-amber-500';
        statusBadge = 'bg-amber-50 text-amber-800 border-amber-200';
        statusLabel = 'Suspended';
      } else if (vehicle.registrationStatus === 'Pending') {
        statusDot = 'bg-blue-500';
        statusBadge = 'bg-blue-50 text-blue-700 border-blue-200';
        statusLabel = 'Pending';
      } else {
        // Active
        statusDot = 'bg-emerald-500';
        statusBadge = 'bg-emerald-50 text-emerald-700 border-emerald-200/80';
        statusLabel = 'Active';
      }

      // Campus custody presence (secondary metadata)
      const vStatus = (vehicle.status || '').toLowerCase();
      const isInside = vStatus.includes('inside');
      const custodyLabel = isInside ? 'On campus' : 'Off campus';
      const custodyDot = isInside ? 'bg-emerald-500' : 'bg-slate-300';

      const driversCount = vehicle.authorizedDrivers ? vehicle.authorizedDrivers.length : 0;

      tr.innerHTML = `
        <td class="py-3 px-3.5 align-middle">
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full ${statusDot} ring-2 ring-white flex-shrink-0" title="${statusLabel}"></span>
            <span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border ${statusBadge}">
              ${escapeHtml(statusLabel)}
            </span>
          </div>
          <div class="text-[10px] text-slate-400 mt-1 flex items-center gap-1 font-medium pl-0.5" title="Gate custody: ${custodyLabel}">
            <span class="w-1.5 h-1.5 rounded-full ${custodyDot} flex-shrink-0"></span>
            <span>${custodyLabel}</span>
          </div>
        </td>
        <td class="py-3 px-3.5 align-middle">
          <div class="font-mono font-bold text-slate-900 text-xs flex items-center gap-1.5 flex-wrap">
            <span>${escapeHtml(vehicle.plateNumber)}</span>
            ${strikeChip(vehicle)}
          </div>
          <div class="inline-flex items-center gap-1.5 text-[11px] text-slate-500 font-mono mt-0.5">
            <span class="px-1.5 py-0.2 rounded bg-slate-100 border border-slate-200/80 text-slate-500 text-[10px] font-semibold">PASS</span>
            <span class="text-slate-600 truncate max-w-[150px]">${escapeHtml(formatPassId(vehicle))}</span>
          </div>
        </td>
        <td class="py-3 px-3.5 align-middle">
          <div class="text-slate-900 font-semibold text-xs leading-snug truncate" title="${escapeHtml(vehicle.makeModelColor)}">${escapeHtml(vehicle.makeModelColor)}</div>
          <div class="text-[11px] text-slate-500 mt-0.5 leading-tight truncate">
            <span>${escapeHtml(vehicle.vehicleType)}</span>
            <span class="text-slate-300 mx-1">&middot;</span>
            <span>Sticker ${escapeHtml(vehicle.stickerYear || '2026')}</span>
          </div>
        </td>
        <td class="py-3 px-3.5 align-middle">
          <div class="text-slate-900 font-semibold text-xs leading-snug truncate" title="${escapeHtml(vehicle.ownerName)}">${escapeHtml(vehicle.ownerName)}</div>
          <div class="text-[11px] text-slate-400 font-mono mt-0.5 truncate">${escapeHtml(vehicle.ownerIdNumber || 'N/A')}</div>
        </td>
        <td class="py-3 px-3.5 align-middle">
          <span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-slate-100 text-slate-700 border border-slate-200/60">
            ${escapeHtml(vehicle.ownerRole || 'General')}
          </span>
          <div class="text-[11px] text-slate-500 mt-0.5 truncate max-w-[190px]" title="${escapeHtml(vehicle.department || '')}">
            ${escapeHtml(vehicle.department || 'NCST Campus')}
          </div>
        </td>
        <td class="py-3 px-3.5 align-middle">
          <div class="inline-flex items-center gap-1.5 text-slate-700 text-xs font-medium">
            <svg class="w-3.5 h-3.5 text-slate-400 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path>
              <circle cx="9" cy="7" r="4"></circle>
              <path d="M22 21v-2a4 4 0 0 0-3-3.87"></path>
              <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
            </svg>
            <span>${driversCount} ${driversCount === 1 ? 'driver' : 'drivers'}</span>
          </div>
        </td>
        <td class="py-3 px-3.5 align-middle text-right pr-4">
          <div class="flex items-center justify-end gap-1.5">
            <!-- Inspect Primary Action -->
            <button type="button" class="inspect-btn px-2.5 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 hover:text-slate-900 text-xs font-semibold shadow-2xs hover:border-slate-300 transition-colors flex items-center gap-1 cursor-pointer" title="Inspect vehicle dossier">
              <svg class="w-3.5 h-3.5 text-slate-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"></path>
                <circle cx="12" cy="12" r="3"></circle>
              </svg>
              <span>Inspect</span>
            </button>

            <!-- Edit Secondary Action (Admin Only) -->
            <button type="button" class="edit-btn admin-only px-2.5 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 hover:text-slate-900 text-xs font-semibold shadow-2xs hover:border-slate-300 transition-colors flex items-center gap-1 cursor-pointer" title="Edit vehicle record">
              <svg class="w-3.5 h-3.5 text-slate-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
              </svg>
              <span>Edit</span>
            </button>

            <!-- Overflow Actions Menu Container -->
            <div class="relative inline-block text-left overflow-menu-container">
              <button type="button" class="overflow-menu-btn p-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-600 hover:text-slate-900 shadow-2xs hover:border-slate-300 transition-colors cursor-pointer flex items-center justify-center" title="More options" aria-haspopup="true" aria-expanded="false">
                <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <circle cx="12" cy="12" r="1.25"></circle>
                  <circle cx="19" cy="12" r="1.25"></circle>
                  <circle cx="5" cy="12" r="1.25"></circle>
                </svg>
              </button>

              <div class="overflow-menu-dropdown hidden absolute right-0 mt-1 w-44 rounded-lg bg-white border border-slate-200 shadow-lg py-1 z-30 divide-y divide-slate-100">
                <div class="py-1">
                  <button type="button" class="print-row-btn w-full px-3 py-1.5 text-slate-700 hover:bg-slate-50 hover:text-slate-900 flex items-center gap-2 text-left text-xs font-medium cursor-pointer transition-colors" title="Print Gate Pass Permit">
                    <svg class="w-3.5 h-3.5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <polyline points="6 9 6 2 18 2 18 9"></polyline>
                      <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"></path>
                      <rect x="6" y="14" width="12" height="8"></rect>
                    </svg>
                    <span>Print Pass</span>
                  </button>
                  <button type="button" class="zoom-qr-row-btn w-full px-3 py-1.5 text-slate-700 hover:bg-slate-50 hover:text-slate-900 flex items-center gap-2 text-left text-xs font-medium cursor-pointer transition-colors" title="Zoom QR Code for mobile scanning">
                    <svg class="w-3.5 h-3.5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <rect x="3" y="3" width="7" height="7"></rect>
                      <rect x="14" y="3" width="7" height="7"></rect>
                      <rect x="14" y="14" width="7" height="7"></rect>
                      <rect x="3" y="14" width="7" height="7"></rect>
                    </svg>
                    <span>View QR Pass</span>
                  </button>
                </div>
                <div class="py-1 admin-only">
                  <button type="button" class="toggle-status-btn w-full px-3 py-1.5 flex items-center gap-2 text-left text-xs font-medium cursor-pointer transition-colors ${vehicle.registrationStatus === 'Active' ? 'text-amber-700 hover:bg-amber-50' : 'text-emerald-700 hover:bg-emerald-50'}" title="Toggle registration status">
                    ${vehicle.registrationStatus === 'Active' ? `
                      <svg class="w-3.5 h-3.5 text-amber-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <circle cx="12" cy="12" r="10"></circle>
                        <line x1="12" y1="8" x2="12" y2="12"></line>
                        <line x1="12" y1="16" x2="12.01" y2="16"></line>
                      </svg>
                      <span>Suspend Pass</span>
                    ` : `
                      <svg class="w-3.5 h-3.5 text-emerald-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
                        <polyline points="22 4 12 14.01 9 11.01"></polyline>
                      </svg>
                      <span>Activate Pass</span>
                    `}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </td>
      `;

      // Event Listeners for Row Actions
      const menuBtn = tr.querySelector('.overflow-menu-btn');
      const dropdown = tr.querySelector('.overflow-menu-dropdown');

      if (menuBtn && dropdown) {
        menuBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          const isCurrentlyOpen = !dropdown.classList.contains('hidden');
          // Close all open dropdowns in the table first
          document.querySelectorAll('#vehiclesTableBody .overflow-menu-dropdown').forEach(d => {
            d.classList.add('hidden');
          });
          document.querySelectorAll('#vehiclesTableBody .overflow-menu-btn').forEach(b => {
            b.setAttribute('aria-expanded', 'false');
          });
          if (!isCurrentlyOpen) {
            dropdown.classList.remove('hidden');
            menuBtn.setAttribute('aria-expanded', 'true');
          }
        });
      }

      const printBtn = tr.querySelector('.print-row-btn');
      if (printBtn) {
        printBtn.addEventListener('click', () => {
          if (dropdown) dropdown.classList.add('hidden');
          if (menuBtn) menuBtn.setAttribute('aria-expanded', 'false');
          printVehiclePass(vehicle);
        });
      }

      const zoomQrBtn = tr.querySelector('.zoom-qr-row-btn');
      if (zoomQrBtn) {
        zoomQrBtn.addEventListener('click', () => {
          if (dropdown) dropdown.classList.add('hidden');
          if (menuBtn) menuBtn.setAttribute('aria-expanded', 'false');
          const qrData = passPayloadFor(vehicle);
          if (!qrData) return showToast(PASS_UNAVAILABLE_MSG);
          openZoomQrModal({
            payload: qrData,
            plate: vehicle.plateNumber,
            owner: vehicle.ownerName,
            year: vehicle.stickerYear || '2026',
            category: vehicle.vehicleType || 'Vehicle'
          });
        });
      }

      const inspectBtn = tr.querySelector('.inspect-btn');
      if (inspectBtn) {
        inspectBtn.addEventListener('click', () => openVehicleDrawer(vehicle));
      }

      const editBtn = tr.querySelector('.edit-btn');
      if (editBtn) {
        editBtn.addEventListener('click', () => openEditModal(vehicle));
      }

      const toggleStatusBtn = tr.querySelector('.toggle-status-btn');
      if (toggleStatusBtn) {
        toggleStatusBtn.addEventListener('click', () => {
          if (dropdown) dropdown.classList.add('hidden');
          if (menuBtn) menuBtn.setAttribute('aria-expanded', 'false');
          toggleVehicleRegistrationStatus(vehicle);
        });
      }

      vehiclesTableBody.appendChild(tr);
    });
  }

  async function toggleVehicleRegistrationStatus(vehicle) {
    if (vehicle.isBanned) {
      if (window.SPAlert) {
        SPAlert.warning({
          title: 'Vehicle Banned',
          text: `${vehicle.plateNumber} is banned by an active violation. Resolve it in Violations & Penalties to lift the suspension.`
        });
      } else {
        showToast(`${vehicle.plateNumber} is banned by a violation. Resolve it in Violations & Penalties to lift the suspension.`, 'warning');
      }
      return;
    }
    const nextStatus = vehicle.registrationStatus === 'Active' ? 'Suspended' : 'Active';
    const actionDesc = nextStatus === 'Active' ? 'activated' : 'suspended';

    const confirmed = window.SPAlert
      ? await SPAlert.confirm({
          title: `${nextStatus === 'Active' ? 'Activate' : 'Suspend'} Vehicle Pass?`,
          text: `Are you sure you want to change pass status of ${vehicle.plateNumber} to ${nextStatus}?`,
          confirmText: nextStatus === 'Active' ? 'Activate Pass' : 'Suspend Pass',
          icon: nextStatus === 'Active' ? 'question' : 'warning',
          isDanger: nextStatus === 'Suspended'
        })
      : confirm(`Are you sure you want to change pass status of ${vehicle.plateNumber} to ${nextStatus}?`);

    if (confirmed) {
      vehicle.registrationStatus = nextStatus;
      renderVehiclesTable();
      updateCounts();
      renderDashboard();
      showToast(`Pass for ${vehicle.plateNumber} is now ${actionDesc}.`, 'success');

      if (window.ApiClient && vehicle.id) {
        ApiClient.toggleVehicleStatus(vehicle.id).catch(err => {
          console.warn('[App] API status sync notice:', err.message);
        });
      }
    }
  }

  // Filter Listeners
  if (vehicleSearchInput) {
    vehicleSearchInput.addEventListener('input', (e) => {
      state.vehicleFilter.search = e.target.value;
      renderVehiclesTable();
    });
  }

  if (vehicleRoleFilter) {
    vehicleRoleFilter.addEventListener('change', (e) => {
      state.vehicleFilter.role = e.target.value;
      renderVehiclesTable();
    });
  }

  if (vehicleCategoryFilter) {
    vehicleCategoryFilter.addEventListener('change', (e) => {
      state.vehicleFilter.category = e.target.value;
      renderVehiclesTable();
    });
  }

  if (vehicleLocationFilter) {
    vehicleLocationFilter.addEventListener('change', (e) => {
      state.vehicleFilter.location = e.target.value;
      renderVehiclesTable();
    });
  }

  if (vehicleStatusFilter) {
    vehicleStatusFilter.addEventListener('change', (e) => {
      state.vehicleFilter.status = e.target.value;
      renderVehiclesTable();
    });
  }

  const resetVehicleFiltersBtn = document.getElementById('resetVehicleFiltersBtn');
  if (resetVehicleFiltersBtn) {
    resetVehicleFiltersBtn.addEventListener('click', () => {
      state.vehicleFilter.search = '';
      state.vehicleFilter.role = 'All';
      state.vehicleFilter.category = 'All';
      state.vehicleFilter.location = 'All';
      state.vehicleFilter.status = 'All';
      if (vehicleSearchInput) vehicleSearchInput.value = '';
      if (vehicleRoleFilter) vehicleRoleFilter.value = 'All';
      if (vehicleCategoryFilter) vehicleCategoryFilter.value = 'All';
      if (vehicleLocationFilter) vehicleLocationFilter.value = 'All';
      if (vehicleStatusFilter) vehicleStatusFilter.value = 'All';
      renderVehiclesTable();
      showToast('Filters cleared.');
    });
  }

  /* ==========================================================================
     5. Flagged & Blocked Incidents Controller
     ========================================================================== */
  function renderIncidentsTable() {
    if (!incidentsTableBody) return;
    incidentsTableBody.innerHTML = '';

    const incidents = state.incidents;

    if (incidents.length === 0) {
      incidentsTableBody.innerHTML = `
        <tr>
          <td colspan="8" class="py-12 text-center text-slate-400 text-xs">
            <div class="font-semibold text-ncst-green">No active security stops or flagged vehicles.</div>
            <div class="text-[11px] text-slate-400 mt-1">All campus gates operating under standard clearance.</div>
          </td>
        </tr>
      `;
      updateCounts();
      return;
    }

    incidents.forEach(inc => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50 transition-colors';

      const isHeld = inc.status === 'Held';
      const statusBadge = isHeld 
        ? 'bg-ncst-crimsonLight text-ncst-crimson border-ncst-crimson/30' 
        : 'bg-slate-100 text-slate-600 border-slate-200';

      tr.innerHTML = `
        <td class="py-2.5 px-4">
          <span class="px-2 py-0.5 rounded text-[11px] font-bold border ${statusBadge}">
            ${escapeHtml(inc.status)}
          </span>
        </td>
        <td class="py-2.5 px-4">
          <div class="font-mono font-bold text-slate-900">${escapeHtml(inc.plateNumber)}</div>
          <div class="text-[10px] text-slate-400 font-mono">${escapeHtml(inc.caseNumber)}</div>
        </td>
        <td class="py-2.5 px-4 text-slate-800">
          ${escapeHtml(inc.vehicleType)}
        </td>
        <td class="py-2.5 px-4">
          <div class="text-slate-900 font-medium">${escapeHtml(inc.driverName)}</div>
          <div class="text-[11px] text-slate-500">Owner: ${escapeHtml(inc.ownerName)}</div>
        </td>
        <td class="py-2.5 px-4">
          <span class="inline-block px-2 py-0.5 rounded text-[11px] font-medium bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30">
            ${escapeHtml(inc.reason)}
          </span>
        </td>
        <td class="py-2.5 px-4 text-slate-600 text-xs">
          <div>${escapeHtml(inc.gatePoint)}</div>
          <div class="text-[11px] text-slate-400">${escapeHtml(inc.officer)}</div>
        </td>
        <td class="py-2.5 px-4 font-mono text-slate-500 text-xs">
          ${escapeHtml(inc.timestamp.replace('Today, ', ''))}
        </td>
        <td class="py-2.5 px-4 text-right">
          <div class="flex items-center justify-end gap-1.5">
            <button type="button" class="investigate-btn px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-ncst-navy shadow-xs transition-colors">
              Investigate
            </button>
            ${isHeld ? `
              <button type="button" class="resolve-btn admin-only px-2.5 py-1 rounded text-xs font-semibold text-ncst-greenDark bg-ncst-greenLight border border-ncst-green/30 hover:bg-ncst-greenLight/80 shadow-xs transition-colors">
                Clear & Unblock
              </button>
            ` : ''}
          </div>
        </td>
      `;

      tr.querySelector('.investigate-btn').addEventListener('click', () => openIncidentDrawer(inc));
      const resolveBtn = tr.querySelector('.resolve-btn');
      if (resolveBtn) {
        resolveBtn.addEventListener('click', () => resolveIncident(inc));
      }

      incidentsTableBody.appendChild(tr);
    });

    updateCounts();
  }

  async function resolveIncident(inc) {
    const notes = await SPAlert.prompt({
      title: 'Clear & Unblock Vehicle?',
      html: `<div style="text-align:left"><div><strong>${escapeHtml(inc.plateNumber)}</strong> &middot; <span style="font-family:'JetBrains Mono',monospace">${escapeHtml(inc.caseNumber)}</span></div>
        <div>Reason: ${escapeHtml(inc.reason)}</div></div>
        <div style="margin-top:0.5rem">Releasing the hold lets this vehicle through the gate again. Your statement is saved in the audit trail.</div>`,
      label: 'Resolution statement',
      value: 'Identity and authorization confirmed with registered owner.',
      confirmText: 'Clear & Unblock',
      requiredMessage: 'A resolution statement is required.'
    });
    if (notes === null) return;

    // The server decides first: a ban tied to a pending violation can only be lifted in Violations & Penalties
    if (window.ApiClient && inc.id) {
      try {
        await ApiClient.resolveIncident(inc.id, notes);
      } catch (err) {
        if (err.code === 'VIOLATION_PENDING') {
          await SPAlert.warning({ title: 'Resolve the violation first', text: err.message, confirmText: 'Understood' });
        } else {
          await SPAlert.error({ title: 'Could not clear the hold', text: err.message || 'The server did not accept the resolution. Please try again.' });
        }
        return;
      }
    }

    const resolverLabel = (window.SPAuth && SPAuth.label()) || 'Security Administrator';
    inc.status = 'Resolved';
    inc.notes = (inc.notes || '') + ` [Resolved by ${resolverLabel}: ${notes}]`;
    closeDrawer();
    renderIncidentsTable();
    renderDashboard();
    // Vehicles, logs and cases exactly as the server now has them (no guessed local state)
    loadInitialDataFromApi(true, true);

    SPAlert.success({
      title: 'Vehicle Unblocked',
      text: `${inc.plateNumber} was cleared and the gate hold was released.`,
      timer: 2600
    });
  }

  /* ==========================================================================
     6. Audit Logs Controller (Search, Filter, Pagination, CSV Export)
     ========================================================================== */
  function getFilteredAuditLogs() {
    return state.auditLogs.filter(log => {
      const q = state.auditFilter.search.toLowerCase().trim();
      const matchesSearch = !q ||
        log.plateNumber.toLowerCase().includes(q) ||
        log.ownerName.toLowerCase().includes(q) ||
        log.driverName.toLowerCase().includes(q) ||
        log.gatePoint.toLowerCase().includes(q) ||
        (log.guardName && log.guardName.toLowerCase().includes(q));

      let matchesFilter = true;
      if (state.auditFilter.status === 'Inside') {
        matchesFilter = log.status === 'Inside Campus';
      } else if (state.auditFilter.status === 'Exited') {
        matchesFilter = log.status === 'Exited';
      } else if (state.auditFilter.status === 'Blocked') {
        matchesFilter = log.status === 'Blocked / Alert';
      }

      return matchesSearch && matchesFilter;
    });
  }

  function updateAuditSummaryStats() {
    const total = state.auditLogs.length;
    const insideCount = state.auditLogs.filter(l => l.status === 'Inside Campus').length;
    const exitedCount = state.auditLogs.filter(l => l.status === 'Exited').length;
    const blockedCount = state.auditLogs.filter(l => l.status === 'Blocked / Alert').length;

    if (auditSummaryTotal) auditSummaryTotal.textContent = total;
    if (auditSummaryInside) auditSummaryInside.textContent = insideCount;
    if (auditSummaryExited) auditSummaryExited.textContent = exitedCount;
    if (auditSummaryBlocked) auditSummaryBlocked.textContent = blockedCount;

    if (auditPillCountAll) auditPillCountAll.textContent = `(${total})`;
    if (auditPillCountInside) auditPillCountInside.textContent = `(${insideCount})`;
    if (auditPillCountExited) auditPillCountExited.textContent = `(${exitedCount})`;
    if (auditPillCountBlocked) auditPillCountBlocked.textContent = `(${blockedCount})`;
  }

  function renderFullAuditTable() {
    if (!fullAuditTableBody) return;
    updateAuditSummaryStats();
    fullAuditTableBody.innerHTML = '';

    const filtered = getFilteredAuditLogs();
    const total = filtered.length;
    const pageSize = state.auditFilter.pageSize;
    const totalPages = Math.ceil(total / pageSize) || 1;

    // Constrain page
    if (state.auditFilter.page > totalPages) state.auditFilter.page = totalPages;
    if (state.auditFilter.page < 1) state.auditFilter.page = 1;

    const startIdx = (state.auditFilter.page - 1) * pageSize;
    const pagedLogs = filtered.slice(startIdx, startIdx + pageSize);

    // Update Pagination UI
    if (auditPaginationInfo) {
      if (total === 0) {
        auditPaginationInfo.textContent = "Showing 0 of 0 entries";
      } else {
        const endIdx = Math.min(startIdx + pageSize, total);
        auditPaginationInfo.textContent = `Showing ${startIdx + 1} to ${endIdx} of ${total} entries`;
      }
    }

    if (auditPrevBtn) auditPrevBtn.disabled = state.auditFilter.page <= 1;
    if (auditNextBtn) auditNextBtn.disabled = state.auditFilter.page >= totalPages;

    if (pagedLogs.length === 0) {
      fullAuditTableBody.innerHTML = `
        <tr>
          <td colspan="9" class="py-12 text-center text-slate-500 text-xs bg-slate-50/50">
            <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-slate-200 text-slate-500 mb-2">
              <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <circle cx="11" cy="11" r="8"></circle>
                <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
              </svg>
            </div>
            <div class="font-semibold text-slate-700">No matching audit logs found</div>
            <div class="text-[11px] text-slate-400 mt-0.5">Try adjusting your search query or status filter.</div>
          </td>
        </tr>
      `;
      return;
    }

    pagedLogs.forEach(log => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50/80 transition-colors border-b border-slate-100 text-xs text-slate-800';

      let statusBadge = 'bg-emerald-50 text-emerald-700 border-emerald-200/80 font-semibold';
      let statusDot = 'bg-emerald-500';
      let statusText = 'Inside';

      if (log.status === 'Exited') {
        statusBadge = 'bg-slate-100 text-slate-700 border-slate-200 font-medium';
        statusDot = 'bg-slate-400';
        statusText = 'Exited';
      } else if (log.status === 'Blocked / Alert') {
        statusBadge = 'bg-rose-50 text-rose-700 border-rose-200 font-bold';
        statusDot = 'bg-rose-600';
        statusText = 'Hold / Blocked';
      }

      // Format event action styling
      let actionColor = 'text-slate-800 font-medium';
      const actLower = (log.action || '').toLowerCase();
      if (actLower.includes('entry') || actLower.includes('ingress') || actLower.includes('approved')) {
        actionColor = 'text-emerald-700 font-semibold';
      } else if (actLower.includes('exit') || actLower.includes('egress')) {
        actionColor = 'text-slate-700 font-medium';
      } else if (actLower.includes('flag') || actLower.includes('held') || actLower.includes('blocked') || actLower.includes('alert')) {
        actionColor = 'text-rose-700 font-bold';
      }

      tr.innerHTML = `
        <td class="py-2.5 px-4 whitespace-nowrap">
          <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] border ${statusBadge}">
            <span class="w-1.5 h-1.5 rounded-full ${statusDot}"></span>
            ${statusText}
          </span>
        </td>
        <td class="py-2.5 px-4 whitespace-nowrap">
          <span class="font-mono font-bold text-xs bg-slate-100 text-slate-900 px-2 py-0.5 rounded border border-slate-300 tracking-wide shadow-2xs">
            ${escapeHtml(log.plateNumber)}
          </span>
        </td>
        <td class="py-2.5 px-4 whitespace-nowrap">
          <div class="${actionColor}">
            ${escapeHtml(log.action || 'Movement Logged')}
          </div>
          <div class="text-[10px] text-slate-500 truncate max-w-[130px] font-normal">
            ${escapeHtml(log.vehicleType || '')}
          </div>
        </td>
        <td class="py-2.5 px-4">
          <div class="font-semibold text-slate-900 leading-snug">${escapeHtml(log.driverName)}</div>
          <div class="text-[11px] text-slate-500">(${escapeHtml(log.driverRelationship || 'Self')})</div>
        </td>
        <td class="py-2.5 px-4 text-slate-800 font-medium">
          ${escapeHtml(log.ownerName)}
        </td>
        <td class="py-2.5 px-4 text-slate-700 whitespace-nowrap">
          <span class="font-medium text-slate-800">${escapeHtml(log.gatePoint)}</span>
        </td>
        <td class="py-2.5 px-4 whitespace-nowrap">
          <span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] bg-slate-100 text-slate-800 font-mono border border-slate-200">
            ${escapeHtml(log.guardName || 'Gate Officer')}
          </span>
        </td>
        <td class="py-2.5 px-4 text-right font-mono font-medium text-slate-700 whitespace-nowrap">
          ${escapeHtml(log.timestamp.replace('Today, ', ''))}${offlineChip(log)}
          ${clipButtonFor(log)}
        </td>
        <td class="py-2.5 px-4 text-right whitespace-nowrap">
          <button type="button" class="audit-details-btn px-2.5 py-1 rounded-md border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs transition-colors cursor-pointer">
            Inspect
          </button>
        </td>
      `;

      tr.querySelector('.audit-details-btn').addEventListener('click', () => openAuditDrawer(log));

      fullAuditTableBody.appendChild(tr);
    });
  }

  // Audit Listeners
  if (fullAuditSearchInput) {
    fullAuditSearchInput.addEventListener('input', (e) => {
      state.auditFilter.search = e.target.value;
      state.auditFilter.page = 1;
      renderFullAuditTable();
    });
  }

  auditFilterPills.forEach(pill => {
    pill.addEventListener('click', () => {
      const activeClass = "audit-filter-pill px-3 py-1.5 rounded-md text-xs font-semibold bg-ncst-navy text-white shadow-xs transition-colors";
      const inactiveClass = "audit-filter-pill px-3 py-1.5 rounded-md text-xs font-semibold border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 hover:text-slate-900 transition-colors";

      auditFilterPills.forEach(p => {
        p.className = inactiveClass;
      });
      pill.className = activeClass;
      state.auditFilter.status = pill.getAttribute('data-filter') || 'All';
      state.auditFilter.page = 1;
      renderFullAuditTable();
    });
  });

  if (auditPrevBtn) {
    auditPrevBtn.addEventListener('click', () => {
      if (state.auditFilter.page > 1) {
        state.auditFilter.page--;
        renderFullAuditTable();
      }
    });
  }

  if (auditNextBtn) {
    auditNextBtn.addEventListener('click', () => {
      const totalPages = Math.ceil(getFilteredAuditLogs().length / state.auditFilter.pageSize) || 1;
      if (state.auditFilter.page < totalPages) {
        state.auditFilter.page++;
        renderFullAuditTable();
      }
    });
  }

  if (exportCsvBtn) {
    exportCsvBtn.addEventListener('click', () => {
      exportAuditCsv();
    });
  }

  function exportAuditCsv() {
    const logs = state.auditLogs;
    if (logs.length === 0) {
      showToast("No logs available to export.");
      return;
    }

    const headers = ["Log ID", "Timestamp", "Plate Number", "Vehicle Type", "Owner Name", "Driver Name", "Relationship", "Gate Point", "Action", "Status", "Officer", "Notes"];
    const rows = logs.map(l => [
      l.id,
      `"${l.timestamp}"`,
      `"${l.plateNumber}"`,
      `"${l.vehicleType || ''}"`,
      `"${l.ownerName || ''}"`,
      `"${l.driverName || ''}"`,
      `"${l.driverRelationship || ''}"`,
      `"${l.gatePoint || ''}"`,
      `"${l.action || ''}"`,
      `"${l.status || ''}"`,
      `"${l.guardName || ''}"`,
      `"${(l.notes || '').replace(/"/g, '""')}"`
    ]);

    const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `securepark_audit_logs_${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast("Audit logs exported to CSV.");
  }

  /* ==========================================================================
     7. Centered Inspection Modal & Print Controller
     ========================================================================== */
  function printVehiclePass(rawV) {
    if (!rawV) return;
    const v = normalizeVehicle(rawV);
    const container = document.getElementById('officialPrintQrContainer');
    if (!container) return;
    container.innerHTML = '';

    const qrData = passPayloadFor(v);
    if (!qrData) {
      showToast(PASS_UNAVAILABLE_MSG);
      return;
    }

    if (typeof QRCode !== 'undefined') {
      try {
        new QRCode(container, {
          text: qrData,
          width: 260,
          height: 260,
          colorDark: "#0F172A",
          colorLight: "#ffffff",
          correctLevel: QRCode.CorrectLevel.M
        });
      } catch (err) {
        console.warn('[PrintPass] QRCode generation notice:', err);
      }
    }

    // Delay slightly to ensure QR is fully rendered into the DOM before print dialog opens
    setTimeout(() => {
      window.print();
    }, 200);
  }
  window.printVehiclePass = printVehiclePass;

  function openDrawer(title, subtitle, contentHtml, footerHtml) {
    drawerTitle.textContent = title;
    drawerSubtitle.textContent = subtitle;
    drawerContent.innerHTML = contentHtml;
    drawerFooter.innerHTML = footerHtml || `
      <button id="drawerCancelBtnInner" class="px-3.5 py-1.5 rounded-md border border-slate-200 bg-white hover:bg-slate-100 text-xs font-medium text-slate-700 cursor-pointer">
        Close
      </button>
    `;

    const cancelBtn = drawerFooter.querySelector('#drawerCancelBtnInner') || drawerCancelBtn;
    if (cancelBtn) cancelBtn.addEventListener('click', closeDrawer);

    drawerOverlay.classList.remove('hidden');
    drawerOverlay.classList.add('flex');
  }

  function closeDrawer() {
    drawerOverlay.classList.add('hidden');
    drawerOverlay.classList.remove('flex');
  }

  if (closeDrawerBtn) closeDrawerBtn.addEventListener('click', closeDrawer);
  if (drawerCancelBtn) drawerCancelBtn.addEventListener('click', closeDrawer);
  if (drawerOverlay) {
    drawerOverlay.addEventListener('click', (e) => {
      if (e.target === drawerOverlay) closeDrawer();
    });
  }

  function resolveImgSrc(src) {
    if (!src) return '';
    const trimmed = String(src).trim();
    if (trimmed.startsWith('data:') || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    const base = window.ApiClient ? window.ApiClient.getBaseUrl().replace(/\/api\/?$/, '') : '';
    return trimmed.startsWith('/') ? `${base}${trimmed}` : `${base}/${trimmed}`;
  }

  function normalizeVehicle(v) {
    if (!v) return v;
    const plate = v.plateNumber || v.plate_number || '';
    const owner = v.ownerName || v.owner_name || '';
    const ownerPhoto = v.ownerPhoto || v.owner_photo || v.ownerPhotoUrl || null;
    const vehiclePhoto = v.vehiclePhoto || v.vehicle_photo || v.vehiclePicture || null;
    const makeModel = v.makeModelColor || v.make_model_color || 'Vehicle';
    const type = v.vehicleType || v.vehicle_type || '4-Wheel';
    const role = v.ownerRole || v.owner_role || 'Student';
    const idNum = v.ownerIdNumber || v.owner_id_number || '';
    const dept = v.department || '';
    const phone = v.ownerPhone || v.owner_phone || '';
    const email = v.ownerEmail || v.owner_email || '';
    const year = v.stickerYear || v.sticker_year || '2026';
    const regStat = v.registrationStatus || v.registration_status || 'Active';
    const status = v.status || 'Outside';
    const qrCode = v.qrPassCode || v.qr_pass_code || '';
    const entryTime = v.entryTime || v.last_entry_time || null;
    const gatePoint = v.gatePoint || v.last_gate_point || '—';

    const drivers = (v.authorizedDrivers || []).map((d, i) => ({
      id: d.id || `drv-${i}`,
      fullName: d.fullName || d.full_name || 'Driver',
      relationship: d.relationship || 'Self (Owner)',
      licenseNo: d.licenseNo || d.license_no || 'N/A',
      phone: d.phone || '',
      photoUrl: d.photoUrl || d.photo_url || null
    }));

    return {
      ...v,
      id: v.id,
      plateNumber: plate,
      plate_number: plate,
      ownerName: owner,
      owner_name: owner,
      ownerPhoto: ownerPhoto,
      owner_photo: ownerPhoto,
      ownerPhotoUrl: ownerPhoto,
      vehiclePhoto: vehiclePhoto,
      vehicle_photo: vehiclePhoto,
      vehiclePicture: vehiclePhoto,
      makeModelColor: makeModel,
      make_model_color: makeModel,
      vehicleType: type,
      vehicle_type: type,
      category: v.category || 'plated',
      ownerRole: role,
      owner_role: role,
      ownerIdNumber: idNum,
      owner_id_number: idNum,
      department: dept,
      ownerPhone: phone,
      owner_phone: phone,
      ownerEmail: email,
      owner_email: email,
      stickerYear: year,
      sticker_year: year,
      registrationStatus: regStat,
      registration_status: regStat,
      status: status,
      qrPassCode: qrCode,
      qr_pass_code: qrCode,
      qrPayload: v.qrPayload || null,
      passId: v.passId || null,
      passValidUntil: v.passValidUntil || null,
      passClass: v.passClass || (v.isVip ? 'VIP' : 'Standard'),
      isVip: !!(v.isVip || v.passClass === 'VIP'),
      vipGrantedBy: v.vipGrantedBy || null,
      vipGrantedAt: v.vipGrantedAt || null,
      warningCount: v.warningCount || 0,
      isBanned: !!v.isBanned,
      entryTime: entryTime,
      gatePoint: gatePoint,
      authorizedDrivers: drivers
    };
  }

  // Open Centered Modal for Vehicle Inspection
  function openVehicleDrawer(rawV) {
    const v = normalizeVehicle(rawV);
    const ownerPhotoSrc = resolveImgSrc(v.ownerPhoto);
    const vehiclePhotoSrc = resolveImgSrc(v.vehiclePhoto);

    const driversRows = (v.authorizedDrivers || []).map((d, i) => `
      <tr class="border-b border-slate-100 text-xs hover:bg-slate-50/60 transition-colors">
        <td class="py-2.5 px-3 text-slate-900 font-semibold flex items-center gap-1.5">
          <svg class="w-3.5 h-3.5 text-ncst-navy flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
            <circle cx="12" cy="7" r="4"></circle>
          </svg>
          <span>${escapeHtml(d.fullName)}</span>
        </td>
        <td class="py-2.5 px-3 text-slate-600 font-medium">${escapeHtml(d.relationship)}</td>
        <td class="py-2.5 px-3 font-mono text-slate-700 font-semibold">${escapeHtml(d.licenseNo)}</td>
        <td class="py-2.5 px-3 font-mono text-slate-500">${escapeHtml(d.phone || '—')}</td>
      </tr>
    `).join('');

    const html = `
      <div class="space-y-4">
        <!-- Vehicle Status Banner -->
        <div class="bg-white p-4 rounded-xl border border-slate-200 shadow-2xs flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
          <div>
            <div class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Registered Plate Number</div>
            <div class="text-2xl font-black font-mono text-ncst-navy tracking-wider leading-tight">${escapeHtml(v.plateNumber)}</div>
            <div class="text-xs text-slate-600 font-medium mt-0.5">${escapeHtml(v.makeModelColor)} (${escapeHtml(v.vehicleType)})</div>
          </div>
          <div class="flex sm:flex-col items-center sm:items-end gap-2">
            <span class="px-3 py-1 rounded text-xs font-extrabold border ${v.registrationStatus === 'Active' ? 'bg-ncst-greenLight text-ncst-greenDark border-ncst-green/30' : 'bg-ncst-crimsonLight text-ncst-crimson border-ncst-crimson/30'}">
              ${escapeHtml(v.registrationStatus || 'Active')}
            </span>
            <span class="px-2.5 py-0.5 rounded text-[11px] font-bold bg-ncst-goldLight text-amber-950 border border-ncst-gold/40 font-mono">
              Sticker ${escapeHtml(v.stickerYear || '2026')}
            </span>
            ${v.isVip ? `<span class="px-2.5 py-0.5 rounded text-[11px] font-extrabold bg-ncst-gold text-slate-900" title="${escapeHtml(v.vipGrantedBy ? 'Granted by ' + v.vipGrantedBy + (v.vipGrantedAt ? ' on ' + v.vipGrantedAt : '') : '')}">VIP PASS</span>` : ''}
          </div>
        </div>

        <!-- High-Visibility Scaled-Up QR Code Section -->
        <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-2xs flex flex-col items-center justify-center text-center">
          <div class="text-xs font-bold text-slate-900 uppercase tracking-wider mb-1 flex items-center gap-1.5">
            <svg class="w-4 h-4 text-ncst-navy" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="3" width="7" height="7"></rect>
              <rect x="14" y="3" width="7" height="7"></rect>
              <rect x="14" y="14" width="7" height="7"></rect>
              <rect x="3" y="14" width="7" height="7"></rect>
            </svg>
            <span>Official Gate Pass QR Code</span>
          </div>
          <p class="text-[11px] text-slate-500 mb-3.5">Encoded with verified driver roster for campus gate readers</p>
          
          <!-- Large 200px Centered QR Frame -->
          <div id="drawerQrClickable" class="p-3 bg-white rounded-xl border-2 border-ncst-navy/20 shadow-md flex items-center justify-center cursor-pointer group hover:border-ncst-navy transition-all relative" title="Click to zoom / enlarge QR code">
            <div id="drawerQrContainer" class="w-[200px] h-[200px] flex items-center justify-center overflow-hidden"></div>
            <div class="absolute inset-0 bg-ncst-navy/10 opacity-0 group-hover:opacity-100 flex items-center justify-center rounded-xl transition-opacity">
              <span class="bg-white text-ncst-navy font-bold text-xs px-2.5 py-1 rounded-md shadow-xs flex items-center gap-1.5">
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <circle cx="11" cy="11" r="8"></circle>
                  <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
                  <line x1="11" y1="8" x2="11" y2="14"></line>
                  <line x1="8" y1="11" x2="14" y2="11"></line>
                </svg>
                Enlarge
              </span>
            </div>
          </div>

          <button type="button" id="drawerZoomQrBtn" class="mt-3 inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-md bg-white hover:bg-ncst-navy hover:text-white text-slate-700 text-xs font-semibold border border-slate-300 transition-all shadow-2xs cursor-pointer">
            <svg class="w-3.5 h-3.5 text-ncst-navy group-hover:text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="11" cy="11" r="8"></circle>
              <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
              <line x1="11" y1="8" x2="11" y2="14"></line>
              <line x1="8" y1="11" x2="14" y2="11"></line>
            </svg>
            <span>Zoom / Enlarge QR Code</span>
          </button>
        </div>

        <!-- Scaled-Up Personnel & Asset Photos Section (2-Column Grid) -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          
          <!-- Owner Card with Scaled-Up 1x1 Photo -->
          <div class="bg-white p-4 rounded-xl border border-slate-200 shadow-2xs space-y-3">
            <div class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Registered Owner</div>
            <div class="flex items-center gap-3">
              <div class="w-20 h-20 rounded-lg border border-slate-300 bg-slate-50 flex items-center justify-center overflow-hidden flex-shrink-0 shadow-2xs">
                ${ownerPhotoSrc ? `<img src="${ownerPhotoSrc}" alt="Owner Photo" class="w-full h-full object-cover">` : `
                  <div class="w-full h-full flex flex-col items-center justify-center text-slate-400 bg-slate-100 font-bold text-sm">
                    ${escapeHtml((v.ownerName || 'NC').split(' ').map(n=>n[0]).slice(0,2).join(''))}
                  </div>
                `}
              </div>
              <div class="min-w-0 flex-1">
                <div class="text-xs font-extrabold text-slate-900 truncate">${escapeHtml(v.ownerName)}</div>
                <div class="text-[11px] text-slate-500 font-mono mt-0.5">${escapeHtml(v.ownerIdNumber || 'No ID')}</div>
                <span class="inline-block mt-1 px-2 py-0.5 rounded text-[10px] font-bold bg-ncst-navy/10 text-ncst-navy border border-ncst-navy/20">
                  ${escapeHtml(v.ownerRole || 'Student')}
                </span>
              </div>
            </div>
            <div class="text-xs border-t border-slate-100 pt-2 space-y-1">
              <div class="flex justify-between"><span class="text-slate-500">Dept/Course:</span> <span class="font-medium text-slate-800 truncate max-w-[150px]">${escapeHtml(v.department || '—')}</span></div>
              <div class="flex justify-between"><span class="text-slate-500">Phone:</span> <span class="font-mono text-slate-800">${escapeHtml(v.ownerPhone || '—')}</span></div>
              <div class="flex justify-between"><span class="text-slate-500">Email:</span> <span class="text-slate-800 truncate max-w-[150px]">${escapeHtml(v.ownerEmail || '—')}</span></div>
            </div>
          </div>

          <!-- Vehicle Specs Card with Scaled-Up Vehicle Photo -->
          <div class="bg-white p-4 rounded-xl border border-slate-200 shadow-2xs space-y-3">
            <div class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Vehicle Specifications</div>
            <div class="flex items-center gap-3">
              <div class="w-28 h-20 rounded-lg border border-slate-300 bg-slate-50 flex items-center justify-center overflow-hidden flex-shrink-0 shadow-2xs">
                ${vehiclePhotoSrc ? `<img src="${vehiclePhotoSrc}" alt="Vehicle Photo" class="w-full h-full object-cover">` : `
                  <div class="w-full h-full flex flex-col items-center justify-center text-slate-400 bg-slate-100 font-medium text-[10px] p-2 text-center">
                    <svg class="w-6 h-6 mx-auto text-slate-400 mb-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                      <path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.5 2.8C2.1 11.2 2 11.6 2 12v4c0 .6.4 1 1 1h2"></path>
                      <circle cx="7" cy="17" r="2"></circle>
                      <circle cx="17" cy="17" r="2"></circle>
                    </svg>
                    No Pic Attached
                  </div>
                `}
              </div>
              <div class="min-w-0 flex-1">
                <div class="text-xs font-extrabold text-slate-900 truncate">${escapeHtml(v.makeModelColor)}</div>
                <div class="text-[11px] text-slate-600 mt-0.5">${escapeHtml(v.vehicleType)}</div>
                <span class="inline-block mt-1 px-2 py-0.5 rounded text-[10px] font-bold ${v.status === 'Inside' ? 'bg-ncst-greenLight text-ncst-greenDark border border-ncst-green/30' : 'bg-slate-100 text-slate-600 border border-slate-200'}">
                  ${v.status === 'Inside' ? 'Inside Campus' : 'Outside Campus'}
                </span>
              </div>
            </div>
            <div class="text-xs border-t border-slate-100 pt-2 space-y-1">
              <div class="flex justify-between"><span class="text-slate-500">Sticker Year:</span> <span class="font-mono font-bold text-slate-800">${escapeHtml(v.stickerYear || '2026')}</span></div>
              <div class="flex justify-between"><span class="text-slate-500">Gate Passage:</span> <span class="text-slate-800">${escapeHtml(v.gatePoint || '—')}</span></div>
              <div class="flex justify-between"><span class="text-slate-500">Pass Time:</span> <span class="font-mono text-slate-800">${escapeHtml(v.entryTime || '—')}</span></div>
            </div>
          </div>

        </div>

        <!-- Authorized Drivers Roster Table -->
        <div class="bg-white p-4 rounded-xl border border-slate-200 shadow-2xs space-y-2.5">
          <div class="flex items-center justify-between">
            <div class="text-xs font-bold text-slate-900 uppercase tracking-wider">Authorized Drivers Roster</div>
            <span class="px-2 py-0.5 rounded text-[10px] font-bold bg-ncst-navy text-white">
              ${(v.authorizedDrivers || []).length} Registered
            </span>
          </div>
          <div class="border border-slate-200 rounded-lg overflow-hidden">
            <table class="w-full text-left">
              <thead class="bg-slate-50 text-slate-500 text-[11px]">
                <tr>
                  <th class="py-2 px-3">Driver Name</th>
                  <th class="py-2 px-3">Relationship</th>
                  <th class="py-2 px-3">License No.</th>
                  <th class="py-2 px-3">Phone</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 text-xs">
                ${driversRows || '<tr><td colspan="4" class="p-3 text-center text-slate-400">No authorized drivers recorded</td></tr>'}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;

    const footerHtml = `
      <div class="flex items-center gap-2">
        <button id="drawerPrintBtn" class="px-3.5 py-2 rounded-md bg-white border border-slate-300 hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs flex items-center gap-1.5 transition-colors cursor-pointer" title="Print Gate Pass Permit">
          <svg class="w-4 h-4 text-slate-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="6 9 6 2 18 2 18 9"></polyline>
            <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"></path>
            <rect x="6" y="14" width="12" height="8"></rect>
          </svg>
          <span>Print Pass</span>
        </button>
<button id="drawerFlagBtn" class="px-3.5 py-2 rounded-md bg-white border border-ncst-crimson/30 hover:bg-ncst-crimsonLight text-xs font-semibold text-ncst-crimson shadow-2xs transition-colors cursor-pointer" title="Record a warning (strike) or a violation for this vehicle">
          Flag Violation / Warning
        </button>
        <button id="drawerStudentLoginBtn" class="admin-only px-3.5 py-2 rounded-md bg-white border border-slate-300 hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-2xs transition-colors cursor-pointer" title="Create or reset the owner's student portal login">
          Student Login
        </button>
        <button id="drawerReissueBtn" class="admin-only px-3.5 py-2 rounded-md bg-white border border-ncst-gold/40 hover:bg-ncst-goldLight text-xs font-semibold text-amber-950 shadow-2xs transition-colors cursor-pointer" title="Issue a new signed pass; all previous QR codes for this vehicle stop working">
          Reissue Pass
        </button>
        <button id="drawerEditBtn" class="admin-only px-4 py-2 rounded-md bg-ncst-navy hover:bg-ncst-navyDark text-white text-xs font-bold shadow-xs flex items-center gap-1.5 transition-colors cursor-pointer">
          <svg class="w-3.5 h-3.5 text-ncst-gold" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
            <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
          </svg>
          <span>Edit Record</span>
        </button>
        <button id="drawerCancelBtnInner" class="px-3.5 py-2 rounded-md border border-slate-200 bg-white hover:bg-slate-100 text-xs font-medium text-slate-700 cursor-pointer">
          Close
        </button>
      </div>
    `;

    openDrawer(`Vehicle Dossier — ${v.plateNumber}`, v.plateNumber, html, footerHtml);

    // Render Scaled-Up 200px Drawer QR Code
    const drawerQrContainer = drawerContent.querySelector('#drawerQrContainer');
    if (drawerQrContainer && typeof QRCode !== 'undefined') {
      const qrData = passPayloadFor(v);
      if (!qrData) {
        drawerQrContainer.innerHTML = `<div class="w-[200px] h-[200px] flex items-center justify-center text-center text-[11px] text-slate-500 border border-dashed border-slate-300 rounded p-3">${PASS_UNAVAILABLE_MSG}</div>`;
      } else try {
        drawerQrContainer.innerHTML = '';
        new QRCode(drawerQrContainer, {
          text: qrData,
          width: 200,
          height: 200,
          colorDark: "#0F172A",
          colorLight: "#ffffff",
          correctLevel: QRCode.CorrectLevel.M
        });
      } catch (err) {
        console.warn('Drawer QRCode rendering notice:', err);
      }

      // Attach Zoom QR Handlers for Drawer
      const handleDrawerZoom = () => {
        if (typeof openZoomQrModal === 'function') {
          openZoomQrModal({
            payload: qrData,
            plate: v.plateNumber,
            owner: v.ownerName,
            year: v.stickerYear || '2026',
            category: v.vehicleType || 'Vehicle'
          });
        }
      };
      const drawerZoomBtn = drawerContent.querySelector('#drawerZoomQrBtn');
      const drawerQrClickable = drawerContent.querySelector('#drawerQrClickable');
      if (drawerZoomBtn) drawerZoomBtn.addEventListener('click', handleDrawerZoom);
      if (drawerQrClickable) drawerQrClickable.addEventListener('click', handleDrawerZoom);
    }

    // Attach Print & Edit Actions
    const printBtn = drawerFooter.querySelector('#drawerPrintBtn');
    if (printBtn) {
      printBtn.addEventListener('click', () => printVehiclePass(v));
    }
    const flagBtn = drawerFooter.querySelector('#drawerFlagBtn');
    if (flagBtn) flagBtn.addEventListener('click', () => window.SPViolations && SPViolations.openFlagModal(v));
    const studentLoginBtn = drawerFooter.querySelector('#drawerStudentLoginBtn');
    if (studentLoginBtn) studentLoginBtn.addEventListener('click', async () => {
      if (!v.ownerIdNumber) return showToast('This vehicle has no owner ID number.', 'warning');
      const confirmed = window.SPAlert
        ? await SPAlert.confirm({
            title: 'Issue Student Portal Login?',
            text: `Issue login credentials for owner ID ${v.ownerIdNumber}. If the student already has an account, their password will be reset and other sessions will be signed out.`,
            confirmText: 'Issue Login',
            icon: 'question'
          })
        : confirm(`Issue a student portal login for owner ID ${v.ownerIdNumber}?\n\nIf the owner already has one, the password is reset and they are signed out everywhere.`);
      if (!confirmed) return;
      try {
        const res = await ApiClient.issueStudentLogin(v.ownerIdNumber);
        if (window.SPAlert && typeof SPAlert.tempPassword === 'function') {
          await SPAlert.tempPassword({
            title: 'Student Portal Login Created',
            username: `Owner ID: ${res.ownerIdNumber}`,
            password: res.tempPassword,
            subtext: `Student credentials issued for ${v.ownerName || 'vehicle owner'} (${res.ownerIdNumber})`
          });
        } else if (window.SPTempPassword) {
          SPTempPassword(`Student portal login for owner ID ${res.ownerIdNumber}`, res.tempPassword);
        }
      } catch (err) {
        showToast(`Could not issue login: ${err.message}`, 'error');
      }
    });
    const reissueBtn = drawerFooter.querySelector('#drawerReissueBtn');
    if (reissueBtn) reissueBtn.addEventListener('click', () => reissueVehiclePass(v));
    const editBtn = drawerFooter.querySelector('#drawerEditBtn');
    if (editBtn) {
      editBtn.addEventListener('click', () => {
        closeDrawer();
        openEditModal(v);
      });
    }
  }

  // Open Drawer for Security Incident Dossier
  function openIncidentDrawer(inc) {
    const isHeld = inc.status === 'Held';

    const html = `
      <div class="space-y-5">
        <div class="p-4 rounded-lg border ${isHeld ? 'bg-ncst-crimsonLight border-ncst-crimson/30' : 'bg-slate-50 border-slate-200'}">
          <div class="flex items-center justify-between">
            <div class="text-xs font-bold ${isHeld ? 'text-ncst-crimson' : 'text-slate-600'} uppercase">Security Incident Report</div>
            <span class="px-2 py-0.5 rounded text-xs font-bold ${isHeld ? 'bg-ncst-crimson text-white' : 'bg-slate-200 text-slate-700'}">${escapeHtml(inc.status)}</span>
          </div>
          <div class="text-xl font-mono font-bold text-slate-900 mt-2">${escapeHtml(inc.plateNumber)}</div>
          <div class="text-xs font-semibold text-ncst-crimson mt-1 font-mono">${escapeHtml(inc.caseNumber)} • Stop Reason: ${escapeHtml(inc.reason)}</div>
        </div>

        <div>
          <h4 class="text-xs font-bold text-slate-900 uppercase tracking-wider mb-2">Incident Particulars</h4>
          <div class="grid grid-cols-2 gap-3 text-xs bg-white p-3 rounded border border-slate-200">
            <div>
              <span class="text-slate-400 block text-[11px]">Unregistered Driver</span>
              <span class="font-bold text-ncst-crimson">${escapeHtml(inc.driverName)}</span>
              <span class="text-[11px] text-slate-500 block">(${escapeHtml(inc.driverRelationship)})</span>
            </div>
            <div>
              <span class="text-slate-400 block text-[11px]">Registered Owner</span>
              <span class="font-medium text-slate-800">${escapeHtml(inc.ownerName)}</span>
              <span class="text-[11px] text-slate-500 block">${escapeHtml(inc.ownerRole)}</span>
            </div>
            <div>
              <span class="text-slate-400 block text-[11px]">Gate & Passage</span>
              <span class="font-medium text-slate-800">${escapeHtml(inc.gatePoint)}</span>
            </div>
            <div>
              <span class="text-slate-400 block text-[11px]">Reporting Officer</span>
              <span class="font-medium text-slate-800">${escapeHtml(inc.officer)}</span>
            </div>
            <div class="col-span-2">
              <span class="text-slate-400 block text-[11px]">Timestamp</span>
              <span class="font-medium font-mono text-slate-800">${escapeHtml(inc.timestamp)}</span>
            </div>
          </div>
        </div>

        ${window.SPClip ? `<div>
          <h4 class="text-xs font-bold text-slate-900 uppercase tracking-wider mb-2">Gate Camera &middot; ${SPClip.seconds} s clip at the ${/exit|egress|gate 2/i.test(inc.gatePoint || '') ? 'exit' : 'entrance'}</h4>
          <div id="incidentClipHost"></div>
          <p class="mt-1 text-[10px] text-slate-500">Simulated clip. Footage is supplied by the school; a placeholder shows until the video is added.</p>
        </div>` : ''}

        <div>
          <h4 class="text-xs font-bold text-slate-900 uppercase tracking-wider mb-2">Officer Incident Narrative</h4>
          <div class="bg-slate-50 p-3 rounded border border-slate-200 text-xs text-slate-800 leading-relaxed">
            ${escapeHtml(inc.notes)}
          </div>
        </div>
      </div>
    `;

    let footerHtml = '';
    if (isHeld) {
      footerHtml = `
        <button id="drawerResolveBtn" class="admin-only px-3 py-1.5 rounded-md bg-ncst-green hover:bg-ncst-greenDark text-white text-xs font-semibold">
          Clear & Unblock
        </button>
        <button id="drawerCancelBtnInner" class="px-3 py-1.5 rounded-md border border-slate-200 bg-white hover:bg-slate-100 text-xs font-medium text-slate-700">
          Close
        </button>
      `;
    } else {
      footerHtml = `
        <button id="drawerCancelBtnInner" class="px-3 py-1.5 rounded-md border border-slate-200 bg-white hover:bg-slate-100 text-xs font-medium text-slate-700">
          Close
        </button>
      `;
    }

    openDrawer(`Security Stop — ${inc.caseNumber}`, inc.plateNumber, html, footerHtml);
    if (window.SPClip) {
      SPClip.mount(document.getElementById('incidentClipHost'), { logId: inc.logId, plate: inc.plateNumber, action: '', loggedAt: inc.reportedAt, gatePoint: inc.gatePoint });
    }

    if (isHeld) {
      const resolveBtn = drawerFooter.querySelector('#drawerResolveBtn');
      if (resolveBtn) {
        resolveBtn.addEventListener('click', () => resolveIncident(inc));
      }
    }
  }

  // Open Drawer for Audit Event Inspection
  // 5 s CCTV clip button for an entry / exit row (simulation, see cctvclip.js). Denied attempts have no clip.
  function clipButtonFor(log) {
    if (!window.SPClip || !/entry|exit/i.test(log.action || '') || /denied/i.test(log.action || '')) return '';
    return `<div class="mt-1">${SPClip.button({ logId: log.id, plate: log.plateNumber, action: log.action, loggedAt: log.loggedAt, gatePoint: log.gatePoint })}</div>`;
  }

  function openAuditDrawer(log) {
    const showClip = Boolean(window.SPClip) && /entry|exit/i.test(log.action || '') && !/denied/i.test(log.action || '');
    const html = `
      <div class="space-y-4 text-xs">
        <div class="bg-slate-50 p-4 rounded-lg border border-slate-200 flex items-center justify-between">
          <div>
            <span class="text-[11px] text-slate-400 font-mono block">AUDIT LOG ID</span>
            <span class="text-base font-bold font-mono text-slate-900">${escapeHtml(log.id)}</span>
          </div>
          <span class="px-2 py-0.5 rounded text-xs font-bold ${log.status === 'Blocked / Alert' ? 'bg-ncst-crimsonLight text-ncst-crimson border border-ncst-crimson/30' : 'bg-ncst-greenLight text-ncst-greenDark border border-ncst-green/30'}">
            ${escapeHtml(log.status)}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-3 bg-white p-3 rounded border border-slate-200">
          <div>
            <span class="text-slate-400 block text-[11px]">Plate Number</span>
            <span class="font-bold font-mono text-slate-900">${escapeHtml(log.plateNumber)}</span>
          </div>
          <div>
            <span class="text-slate-400 block text-[11px]">Event Action</span>
            <span class="font-medium text-slate-800">${escapeHtml(log.action || 'Gate Passage')}</span>
          </div>
          <div>
            <span class="text-slate-400 block text-[11px]">Driver Verified</span>
            <span class="font-medium text-slate-800">${escapeHtml(log.driverName)}</span>
            <span class="text-[11px] text-slate-500 block">(${escapeHtml(log.driverRelationship || 'Self')})</span>
          </div>
          <div>
            <span class="text-slate-400 block text-[11px]">Registered Owner</span>
            <span class="font-medium text-slate-800">${escapeHtml(log.ownerName)}</span>
          </div>
          <div>
            <span class="text-slate-400 block text-[11px]">Gate Location</span>
            <span class="font-medium text-slate-800">${escapeHtml(log.gatePoint)}</span>
          </div>
          <div>
            <span class="text-slate-400 block text-[11px]">Gate Officer</span>
            <span class="font-medium text-slate-800">${escapeHtml(log.guardName || 'Officer on duty')}</span>
          </div>
          <div class="col-span-2">
            <span class="text-slate-400 block text-[11px]">Logged Timestamp</span>
            <span class="font-medium font-mono text-slate-800">${escapeHtml(log.timestamp)}</span>
            ${log.syncedAt && offlineChip(log) ? `<span class="block mt-1 text-[11px] text-ncst-navy font-semibold">Recorded offline at the gate &middot; reached the server ${escapeHtml(log.syncedAt)}</span>` : ''}
          </div>
        </div>

        ${showClip ? `<div>
          <span class="text-slate-500 block text-[11px] font-bold uppercase mb-1">CCTV Clip &middot; ${SPClip.seconds} s at the ${/exit/i.test(log.action || '') ? 'exit' : 'entrance'}</span>
          <div id="auditClipHost"></div>
          <p class="mt-1 text-[10px] text-slate-500">Simulated clip. Footage is supplied by the school; a placeholder shows until the video is added.</p>
        </div>` : ''}

        <div>
          <span class="text-slate-500 block text-[11px] font-bold uppercase mb-1">Passage Verification Notes</span>
          <div class="p-3 bg-slate-50 rounded border border-slate-200 text-slate-700 leading-relaxed">
            ${escapeHtml(log.notes || 'Routine gate check completed with verified custody credentials.')}
          </div>
        </div>
      </div>
    `;

    const auditVehicle = state.vehicles.find(x => (x.plateNumber || '').replace(/[^A-Z0-9]/gi, '').toUpperCase() === (log.plateNumber || '').replace(/[^A-Z0-9]/gi, '').toUpperCase());
    const auditFooter = auditVehicle ? `
      <div class="flex items-center justify-end gap-2 w-full">
        <button id="auditFlagBtn" class="px-3.5 py-2 rounded-md bg-white border border-ncst-crimson/30 hover:bg-ncst-crimsonLight text-xs font-semibold text-ncst-crimson shadow-2xs transition-colors cursor-pointer" title="Record a warning (strike) or a violation for this vehicle">
          Flag Violation / Warning
        </button>
        <button id="drawerCancelBtnInner" class="px-3.5 py-2 rounded-md border border-slate-200 bg-white hover:bg-slate-100 text-xs font-medium text-slate-700 cursor-pointer">
          Close
        </button>
      </div>` : '';
    openDrawer(`Gate Passage Audit — ${log.plateNumber}`, log.timestamp, html, auditFooter);
    if (showClip) SPClip.mount(document.getElementById('auditClipHost'), { logId: log.id, plate: log.plateNumber, action: log.action, loggedAt: log.loggedAt, gatePoint: log.gatePoint });
    const auditFlagBtn = document.getElementById('auditFlagBtn');
    if (auditFlagBtn) auditFlagBtn.addEventListener('click', () => window.SPViolations && SPViolations.openFlagModal(auditVehicle, { context: `Gate log: ${log.action} at ${log.gatePoint}, ${log.timestamp}` }));
  }

  /* ==========================================================================
     8. Edit Vehicle Modal Controller (Full 3-Section Register Style)
     ========================================================================== */
  function createEditDriverCard(index, driverData = {}) {
    const card = document.createElement('div');
    card.className = 'edit-driver-entry-card p-3.5 rounded-md border border-slate-200 bg-slate-50 space-y-3';
    card.setAttribute('data-index', index);

    const isFirst = index === 0;
    card.innerHTML = `
      <div class="flex items-center justify-between">
        <span class="edit-driver-num-label text-xs font-bold text-slate-700">Driver #${index + 1}</span>
        ${!isFirst ? `
          <button type="button" class="remove-edit-driver-btn text-[11px] text-ncst-crimson hover:text-ncst-crimsonDark font-semibold flex items-center gap-1 cursor-pointer">
            <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="3 6 5 6 21 6"></polyline>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            </svg>
            <span>Remove</span>
          </button>
        ` : ''}
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
        <div>
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Full Name <span class="text-ncst-crimson">*</span></label>
          <input type="text" class="edit-driver-name w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="Driver name" value="${escapeHtml(driverData.fullName || '')}" required>
        </div>
        <div>
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Relationship to Owner <span class="text-ncst-crimson">*</span></label>
          <select class="edit-driver-rel w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" required>
            <option value="Self (Owner)" ${driverData.relationship === 'Self (Owner)' ? 'selected' : ''}>Self (Owner)</option>
            <option value="Spouse" ${driverData.relationship === 'Spouse' ? 'selected' : ''}>Spouse</option>
            <option value="Parent" ${driverData.relationship === 'Parent' ? 'selected' : ''}>Parent</option>
            <option value="Child" ${driverData.relationship === 'Child' ? 'selected' : ''}>Child</option>
            <option value="Sibling" ${driverData.relationship === 'Sibling' ? 'selected' : ''}>Sibling</option>
            <option value="Designated Driver" ${driverData.relationship === 'Designated Driver' ? 'selected' : ''}>Designated Driver</option>
          </select>
        </div>
        <div>
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Driver's License No. <span class="text-ncst-crimson">*</span></label>
          <input type="text" class="edit-driver-license w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 font-mono focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="N01-22-849201" value="${escapeHtml(driverData.licenseNo || '')}" required>
        </div>
        <div>
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Phone</label>
          <input type="text" class="edit-driver-phone w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 font-mono focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="+63 9XX XXX XXXX" value="${escapeHtml(driverData.phone || '')}">
        </div>
      </div>
    `;

    const removeBtn = card.querySelector('.remove-edit-driver-btn');
    if (removeBtn) {
      removeBtn.addEventListener('click', () => {
        card.remove();
        renumberEditDrivers();
      });
    }

    return card;
  }

  function renumberEditDrivers() {
    if (!editDriversContainer) return;
    const cards = editDriversContainer.querySelectorAll('.edit-driver-entry-card');
    cards.forEach((card, idx) => {
      card.setAttribute('data-index', idx);
      const label = card.querySelector('.edit-driver-num-label');
      if (label) label.textContent = `Driver #${idx + 1}`;
    });
  }

  function openEditModal(v) {
    if (!editModalOverlay) return;
    v = normalizeVehicle(v);

    editVehicleId.value = v.id;
    editModalPlate.textContent = `Plate: ${v.plateNumber} • ${v.ownerName} • Sticker ${v.stickerYear || '2026'}`;
    
    // Section 1: Owner
    if (editOwnerRole) editOwnerRole.value = v.ownerRole || 'Student';
    if (editOwnerIdNumber) editOwnerIdNumber.value = v.ownerIdNumber || '';
    if (editOwnerFullName) editOwnerFullName.value = v.ownerName || '';
    if (editDepartment) editDepartment.value = v.department || '';
    if (editOwnerPhone) editOwnerPhone.value = v.ownerPhone || '';
    if (editOwnerEmail) editOwnerEmail.value = v.ownerEmail || '';

    // Section 1: Owner Photo
    editOwnerPhotoDataUrl = v.ownerPhoto || v.owner_photo || null;
    if (editOwnerPhotoDataUrl && editOwnerPhotoPreview) {
      editOwnerPhotoPreview.src = resolveImgSrc(editOwnerPhotoDataUrl);
      editOwnerPhotoPreview.classList.remove('hidden');
      if (editOwnerPhotoPlaceholder) editOwnerPhotoPlaceholder.classList.add('hidden');
      if (removeEditOwnerPhotoBtn) removeEditOwnerPhotoBtn.classList.remove('hidden');
      if (editOwnerPhotoFileName) editOwnerPhotoFileName.textContent = 'Existing owner photo';
    } else {
      if (editOwnerPhotoPreview) {
        editOwnerPhotoPreview.src = '';
        editOwnerPhotoPreview.classList.add('hidden');
      }
      if (editOwnerPhotoPlaceholder) editOwnerPhotoPlaceholder.classList.remove('hidden');
      if (removeEditOwnerPhotoBtn) removeEditOwnerPhotoBtn.classList.add('hidden');
      if (editOwnerPhotoFileName) editOwnerPhotoFileName.textContent = '';
    }
    if (editOwnerPhotoInput) editOwnerPhotoInput.value = '';

    // Section 2: Vehicle
    if (editVehicleCategory) {
      // Older / mobile-created vehicles store e.g. "4-Wheel (Sedan)": pick the closest category option
      const stored = String(v.vehicleType || '4-Wheel').toLowerCase();
      const options = [...editVehicleCategory.options];
      const match = options.find(o => o.value.toLowerCase() === stored)
        || options.find(o => stored.startsWith(o.value.toLowerCase()))
        || options[0];
      editVehicleCategory.value = match.value;
    }
    if (editPlateNumber) editPlateNumber.value = v.plateNumber || '';
    if (editMakeModel) editMakeModel.value = v.makeModelColor || '';
    if (editStickerYear) editStickerYear.value = v.stickerYear || '2026';
    if (editPassClassVip) editPassClassVip.checked = !!v.isVip;
    if (editRegStatus) editRegStatus.value = v.registrationStatus || 'Active';
    if (editCampusStatus) {
      // Inside / outside is set by the gate log, never by this form: show it, don't let it be edited or saved
      const st = String(v.status || 'Outside');
      editCampusStatus.value = (st.startsWith('Inside') || st === 'Blocked / Alert') ? 'Inside' : 'Outside';
      editCampusStatus.disabled = true;
      editCampusStatus.title = 'Set automatically by the gate log';
    }

    // Section 2: Vehicle Photo
    editVehiclePhotoDataUrl = v.vehiclePhoto || v.vehicle_photo || null;
    if (editVehiclePhotoDataUrl && editVehiclePhotoPreview) {
      editVehiclePhotoPreview.src = resolveImgSrc(editVehiclePhotoDataUrl);
      editVehiclePhotoPreview.classList.remove('hidden');
      if (editVehiclePhotoPlaceholder) editVehiclePhotoPlaceholder.classList.add('hidden');
      if (removeEditVehiclePhotoBtn) removeEditVehiclePhotoBtn.classList.remove('hidden');
      if (editVehiclePhotoFileName) editVehiclePhotoFileName.textContent = 'Existing vehicle photo';
    } else {
      if (editVehiclePhotoPreview) {
        editVehiclePhotoPreview.src = '';
        editVehiclePhotoPreview.classList.add('hidden');
      }
      if (editVehiclePhotoPlaceholder) editVehiclePhotoPlaceholder.classList.remove('hidden');
      if (removeEditVehiclePhotoBtn) removeEditVehiclePhotoBtn.classList.add('hidden');
      if (editVehiclePhotoFileName) editVehiclePhotoFileName.textContent = '';
    }
    if (editVehiclePhotoInput) editVehiclePhotoInput.value = '';

    // Section 3: Authorized Drivers Roster
    if (editDriversContainer) {
      editDriversContainer.innerHTML = '';
      if (Array.isArray(v.authorizedDrivers) && v.authorizedDrivers.length > 0) {
        v.authorizedDrivers.forEach((d, idx) => {
          editDriversContainer.appendChild(createEditDriverCard(idx, d));
        });
      } else {
        editDriversContainer.appendChild(createEditDriverCard(0, {
          fullName: v.ownerName,
          relationship: 'Self (Owner)',
          licenseNo: 'N/A',
          phone: v.ownerPhone || ''
        }));
      }
    }

    editModalOverlay.classList.remove('hidden');
    editModalOverlay.classList.add('flex');
  }

  function closeEditModal() {
    if (!editModalOverlay) return;
    editModalOverlay.classList.add('hidden');
    editModalOverlay.classList.remove('flex');
  }

  if (closeEditModalBtn) closeEditModalBtn.addEventListener('click', closeEditModal);
  if (cancelEditModalBtn) cancelEditModalBtn.addEventListener('click', closeEditModal);
  if (editModalOverlay) {
    editModalOverlay.addEventListener('click', (e) => {
      if (e.target === editModalOverlay) closeEditModal();
    });
  }

  // Edit Owner Photo Handlers
  if (editOwnerPhotoBtn && editOwnerPhotoInput) {
    editOwnerPhotoBtn.addEventListener('click', () => editOwnerPhotoInput.click());

    editOwnerPhotoInput.addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (file) {
        if (!file.type.startsWith('image/')) {
          showToast('Please select a valid image file (JPG, PNG).');
          return;
        }
        compressImage(file, 400, 0.72, (compressed) => {
          editOwnerPhotoDataUrl = compressed;
          if (editOwnerPhotoPreview) {
            editOwnerPhotoPreview.src = editOwnerPhotoDataUrl;
            editOwnerPhotoPreview.classList.remove('hidden');
          }
          if (editOwnerPhotoPlaceholder) editOwnerPhotoPlaceholder.classList.add('hidden');
          if (removeEditOwnerPhotoBtn) removeEditOwnerPhotoBtn.classList.remove('hidden');
          if (editOwnerPhotoFileName) editOwnerPhotoFileName.textContent = file.name;
        });
      }
    });
  }

  if (removeEditOwnerPhotoBtn) {
    removeEditOwnerPhotoBtn.addEventListener('click', () => {
      editOwnerPhotoDataUrl = null;
      if (editOwnerPhotoInput) editOwnerPhotoInput.value = '';
      if (editOwnerPhotoPreview) {
        editOwnerPhotoPreview.src = '';
        editOwnerPhotoPreview.classList.add('hidden');
      }
      if (editOwnerPhotoPlaceholder) editOwnerPhotoPlaceholder.classList.remove('hidden');
      removeEditOwnerPhotoBtn.classList.add('hidden');
      if (editOwnerPhotoFileName) editOwnerPhotoFileName.textContent = '';
    });
  }

  // Edit Vehicle Photo Handlers
  if (editVehiclePhotoBtn && editVehiclePhotoInput) {
    editVehiclePhotoBtn.addEventListener('click', () => editVehiclePhotoInput.click());

    editVehiclePhotoInput.addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (file) {
        if (!file.type.startsWith('image/')) {
          showToast('Please select a valid image file (JPG, PNG).');
          return;
        }
        compressImage(file, 400, 0.72, (compressed) => {
          editVehiclePhotoDataUrl = compressed;
          if (editVehiclePhotoPreview) {
            editVehiclePhotoPreview.src = editVehiclePhotoDataUrl;
            editVehiclePhotoPreview.classList.remove('hidden');
          }
          if (editVehiclePhotoPlaceholder) editVehiclePhotoPlaceholder.classList.add('hidden');
          if (removeEditVehiclePhotoBtn) removeEditVehiclePhotoBtn.classList.remove('hidden');
          if (editVehiclePhotoFileName) editVehiclePhotoFileName.textContent = file.name;
        });
      }
    });
  }

  if (removeEditVehiclePhotoBtn) {
    removeEditVehiclePhotoBtn.addEventListener('click', () => {
      editVehiclePhotoDataUrl = null;
      if (editVehiclePhotoInput) editVehiclePhotoInput.value = '';
      if (editVehiclePhotoPreview) {
        editVehiclePhotoPreview.src = '';
        editVehiclePhotoPreview.classList.add('hidden');
      }
      if (editVehiclePhotoPlaceholder) editVehiclePhotoPlaceholder.classList.remove('hidden');
      removeEditVehiclePhotoBtn.classList.add('hidden');
      if (editVehiclePhotoFileName) editVehiclePhotoFileName.textContent = '';
    });
  }

  // Dynamic Add Driver button in Edit Modal
  if (editAddDriverBtn && editDriversContainer) {
    editAddDriverBtn.addEventListener('click', () => {
      const count = editDriversContainer.querySelectorAll('.edit-driver-entry-card').length;
      editDriversContainer.appendChild(createEditDriverCard(count, {}));
    });
  }

  // Edit Vehicle Form Submission
  if (editVehicleForm) {
    editVehicleForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const targetId = editVehicleId.value;
      const v = state.vehicles.find(item => String(item.id) === String(targetId));
      if (!v) return;

      const ownerRole = editOwnerRole ? editOwnerRole.value : (v.ownerRole || 'Student');
      const ownerIdNumber = editOwnerIdNumber ? editOwnerIdNumber.value.trim() : (v.ownerIdNumber || '');
      const ownerFullName = editOwnerFullName ? editOwnerFullName.value.trim() : (v.ownerName || '');
      const department = editDepartment ? editDepartment.value.trim() : (v.department || '');
      const ownerPhone = editOwnerPhone ? editOwnerPhone.value.trim() : (v.ownerPhone || '');
      const ownerEmail = editOwnerEmail ? editOwnerEmail.value.trim() : (v.ownerEmail || '');

      const vehicleCategory = editVehicleCategory ? editVehicleCategory.value : (v.vehicleType || '4-Wheel');
      const plateNumber = editPlateNumber ? editPlateNumber.value.trim().toUpperCase() : (v.plateNumber || '');
      const makeModelColor = editMakeModel ? editMakeModel.value.trim() : (v.makeModelColor || '');
      const stickerYear = editStickerYear ? editStickerYear.value.trim() : (v.stickerYear || '2026');
      const registrationStatus = editRegStatus ? editRegStatus.value : (v.registrationStatus || 'Active');

      // Read Authorized Drivers
      const driverCards = editDriversContainer ? editDriversContainer.querySelectorAll('.edit-driver-entry-card') : [];
      const authorizedDrivers = [];

      driverCards.forEach((card, idx) => {
        const nameInput = card.querySelector('.edit-driver-name');
        const relInput = card.querySelector('.edit-driver-rel');
        const licenseInput = card.querySelector('.edit-driver-license');
        const phoneInput = card.querySelector('.edit-driver-phone');

        const name = nameInput ? nameInput.value.trim() : '';
        const rel = relInput ? relInput.value : 'Self (Owner)';
        const license = licenseInput ? licenseInput.value.trim() : '';
        const phone = phoneInput ? phoneInput.value.trim() : '';

        if (name) {
          authorizedDrivers.push({
            id: `drv-${Date.now()}-${idx}`,
            fullName: name,
            relationship: rel,
            licenseNo: license || 'N/A',
            phone: phone || ''
          });
        }
      });

      if (authorizedDrivers.length === 0) {
        authorizedDrivers.push({
          id: `drv-${Date.now()}-0`,
          fullName: ownerFullName,
          relationship: 'Self (Owner)',
          licenseNo: 'N/A',
          phone: ownerPhone || ''
        });
      }

      // Update in-memory vehicle record
      v.plateNumber = plateNumber;
      v.plate_number = plateNumber;
      v.ownerName = ownerFullName;
      v.owner_name = ownerFullName;
      v.ownerRole = ownerRole;
      v.owner_role = ownerRole;
      v.ownerIdNumber = ownerIdNumber;
      v.owner_id_number = ownerIdNumber;
      v.department = department;
      v.ownerPhone = ownerPhone;
      v.owner_phone = ownerPhone;
      v.ownerEmail = ownerEmail;
      v.owner_email = ownerEmail;
      v.vehicleType = vehicleCategory;
      v.vehicle_type = vehicleCategory;
      v.makeModelColor = makeModelColor;
      v.make_model_color = makeModelColor;
      v.stickerYear = stickerYear;
      v.sticker_year = stickerYear;
      if (editPassClassVip) {
        v.isVip = editPassClassVip.checked;
        v.passClass = v.isVip ? 'VIP' : 'Standard';
      }
      v.registrationStatus = registrationStatus;
      v.registration_status = registrationStatus;
      v.ownerPhoto = editOwnerPhotoDataUrl;
      v.owner_photo = editOwnerPhotoDataUrl;
      v.ownerPhotoUrl = editOwnerPhotoDataUrl;
      v.vehiclePhoto = editVehiclePhotoDataUrl;
      v.vehicle_photo = editVehiclePhotoDataUrl;
      v.authorizedDrivers = authorizedDrivers;

      closeEditModal();
      renderVehiclesTable();
      updateCounts();
      renderDashboard();
      showToast(`Record for ${v.plateNumber} successfully updated.`);

      // Sync with InfinityFree backend API
      if (window.ApiClient && v.id) {
        ApiClient.updateVehicle(v.id, {
          plateNumber: v.plateNumber,
          plate_number: v.plateNumber,
          vehicleType: v.vehicleType,
          category: v.vehicleType && v.vehicleType.toLowerCase().includes('motorcycle') ? 'motorcycle' : (v.vehicleType && v.vehicleType.toLowerCase().includes('bicycle') ? 'non-plated' : 'plated'),
          makeModelColor: v.makeModelColor,
          ownerName: v.ownerName,
          ownerRole: v.ownerRole,
          department: v.department,
          ownerIdNumber: v.ownerIdNumber,
          ownerPhone: v.ownerPhone,
          ownerEmail: v.ownerEmail,
          stickerYear: v.stickerYear,
          passClass: v.isVip ? 'VIP' : 'Standard',
          registrationStatus: v.registrationStatus,
          ownerPhoto: v.ownerPhoto,
          vehiclePhoto: v.vehiclePhoto,
          authorizedDrivers: v.authorizedDrivers
        }).then((saved) => {
          if (saved) applyServerPass(v, saved);
          renderVehiclesTable();
          console.log('[App] Vehicle updated on server:', v.plateNumber);
        }).catch(err => {
          console.warn('[App] Update API sync notice:', err.message);
          showToast(`Note: Updated locally, server sync: ${err.message}`);
        });
      }
    });
  }

  /* ==========================================================================
     8.1 Zoom / High-Resolution QR Modal Controller
     ========================================================================== */
  function renderZoomedQr(size) {
    if (!zoomQrContainer || !currentZoomPayload) return;
    zoomQrContainer.innerHTML = '';
    zoomQrContainer.style.width = `${size}px`;
    zoomQrContainer.style.height = `${size}px`;

    if (typeof QRCode !== 'undefined') {
      try {
        new QRCode(zoomQrContainer, {
          text: currentZoomPayload,
          width: size,
          height: size,
          colorDark: "#0F172A",
          colorLight: "#ffffff",
          correctLevel: QRCode.CorrectLevel.L
        });
      } catch (err) {
        console.warn('[ZoomQR] Render error:', err);
      }
    }
  }

  function openZoomQrModal(info = {}) {
    if (!zoomQrModalOverlay) return;
    const payload = info.payload || (lastPreviewPassInfo ? lastPreviewPassInfo.payload : '');
    if (!payload) {
      showToast('No QR code payload available to zoom.');
      return;
    }

    currentZoomPayload = payload;
    if (zoomQrPlate) zoomQrPlate.textContent = info.plate || (lastPreviewPassInfo ? lastPreviewPassInfo.plate : '—');
    if (zoomQrOwner) zoomQrOwner.textContent = info.owner || (lastPreviewPassInfo ? lastPreviewPassInfo.owner : '—');
    if (zoomQrYear) zoomQrYear.textContent = info.year || (lastPreviewPassInfo ? lastPreviewPassInfo.year : '2026');
    if (zoomQrCategory) zoomQrCategory.textContent = info.category || (lastPreviewPassInfo ? lastPreviewPassInfo.category : 'Vehicle');

    renderZoomedQr(currentZoomSize);

    zoomQrModalOverlay.classList.remove('hidden');
    zoomQrModalOverlay.classList.add('flex');
  }

  function closeZoomQrModal() {
    if (!zoomQrModalOverlay) return;
    zoomQrModalOverlay.classList.add('hidden');
    zoomQrModalOverlay.classList.remove('flex');
  }

  if (closeZoomQrModalBtn) closeZoomQrModalBtn.addEventListener('click', closeZoomQrModal);
  if (zoomQrDoneBtn) zoomQrDoneBtn.addEventListener('click', closeZoomQrModal);
  if (zoomQrModalOverlay) {
    zoomQrModalOverlay.addEventListener('click', (e) => {
      if (e.target === zoomQrModalOverlay) closeZoomQrModal();
    });
  }

  // Size toggle buttons in Zoom Modal
  document.querySelectorAll('.zoom-size-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const size = parseInt(btn.getAttribute('data-size'), 10) || 340;
      currentZoomSize = size;
      document.querySelectorAll('.zoom-size-btn').forEach(b => {
        b.classList.remove('active-size', 'bg-ncst-navy', 'text-white', 'border-ncst-navy');
        b.classList.add('bg-white', 'text-slate-700', 'border-slate-200');
      });
      btn.classList.add('active-size', 'bg-ncst-navy', 'text-white', 'border-ncst-navy');
      btn.classList.remove('bg-white', 'text-slate-700', 'border-slate-200');
      renderZoomedQr(size);
    });
  });

  // Zoom preview QR button and container click
  if (zoomPreviewQrBtn) {
    zoomPreviewQrBtn.addEventListener('click', () => openZoomQrModal());
  }
  if (qrCodeContainer) {
    qrCodeContainer.addEventListener('click', () => openZoomQrModal());
  }

  /* ==========================================================================
     9. Vehicle Registration Form Controller (Duplicate Checking & Dynamic Roster)
     ========================================================================== */
  // Real-time Duplicate Plate Detection
  if (plateInput) {
    plateInput.addEventListener('input', () => {
      const val = plateInput.value.trim().toUpperCase();
      const exists = state.vehicles.some(v => v.plateNumber === val);

      if (exists && val.length > 0) {
        plateValidationMsg.textContent = `Warning: Plate ${val} is already registered in the system!`;
        plateValidationMsg.classList.remove('hidden');
        plateInput.classList.add('border-ncst-crimson');
      } else {
        plateValidationMsg.classList.add('hidden');
        plateInput.classList.remove('border-ncst-crimson');
      }
    });
  }

  // Dynamic Driver Field Management
  if (addDriverBtn) {
    addDriverBtn.addEventListener('click', () => {
      state.driverCounter++;
      const count = state.driverCounter;

      const driverCard = document.createElement('div');
      driverCard.className = 'driver-entry-card p-3.5 rounded-md border border-slate-200 bg-slate-50 space-y-3';
      driverCard.setAttribute('data-index', count - 1);

      driverCard.innerHTML = `
        <div class="flex items-center justify-between">
          <span class="driver-num-label text-xs font-bold text-slate-700">Driver #${count}</span>
          <button type="button" class="remove-driver-btn text-xs font-medium text-ncst-crimson hover:text-ncst-crimsonDark hover:underline cursor-pointer">
            Remove
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Full Name <span class="text-ncst-crimson">*</span></label>
            <input type="text" class="driver-name w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="Driver name" required>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Relationship to Owner <span class="text-ncst-crimson">*</span></label>
            <select class="driver-rel w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" required>
              <option value="Spouse">Spouse</option>
              <option value="Parent">Parent</option>
              <option value="Child">Child</option>
              <option value="Sibling">Sibling</option>
              <option value="Designated Driver" selected>Designated Driver</option>
            </select>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Driver's License No. <span class="text-ncst-crimson">*</span></label>
            <input type="text" class="driver-license w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy font-mono" placeholder="N01-22-849201" required>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Phone</label>
            <input type="text" class="driver-phone w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy font-mono" placeholder="+63 9XX XXX XXXX">
          </div>
        </div>
      `;

      driverCard.querySelector('.remove-driver-btn').addEventListener('click', () => {
        driverCard.remove();
        renumberDrivers();
      });

      driversContainer.appendChild(driverCard);
      triggerQrUpdate(10);
    });
  }

  function renumberDrivers() {
    const cards = driversContainer.querySelectorAll('.driver-entry-card');
    state.driverCounter = cards.length;
    cards.forEach((card, idx) => {
      const label = card.querySelector('.driver-num-label');
      if (label) label.textContent = `Driver #${idx + 1}`;
    });
    triggerQrUpdate(10);
  }

  function resetDriverFields() {
    driversContainer.innerHTML = `
      <div class="driver-entry-card p-3.5 rounded-md border border-slate-200 bg-slate-50 space-y-3" data-index="0">
        <div class="flex items-center justify-between">
          <span class="driver-num-label text-xs font-bold text-slate-700">Driver #1</span>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Full Name <span class="text-ncst-crimson">*</span></label>
            <input type="text" class="driver-name w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="Driver name" required>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Relationship to Owner <span class="text-ncst-crimson">*</span></label>
            <select class="driver-rel w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" required>
              <option value="Self (Owner)" selected>Self (Owner)</option>
              <option value="Spouse">Spouse</option>
              <option value="Parent">Parent</option>
              <option value="Child">Child</option>
              <option value="Sibling">Sibling</option>
              <option value="Designated Driver">Designated Driver</option>
            </select>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Driver's License No. <span class="text-ncst-crimson">*</span></label>
            <input type="text" class="driver-license w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy font-mono" placeholder="N01-22-849201" required>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Phone</label>
            <input type="text" class="driver-phone w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy font-mono" placeholder="+63 9XX XXX XXXX">
          </div>
        </div>
      </div>
    `;
    state.driverCounter = 1;
    triggerQrUpdate(10);
  }

  // Client-side image compressor: scales images down to max 640px and quality 0.8 (~35KB-50KB)
  // Ensures reliable fast transmission over mobile networks and storage in SQLite/MySQL
  function compressImage(file, maxDimension = 400, quality = 0.72, callback) {
    if (!file) {
      callback(null);
      return;
    }
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        try {
          let w = img.width;
          let h = img.height;
          if (w > maxDimension || h > maxDimension) {
            if (w > h) {
              h = Math.round((h * maxDimension) / w);
              w = maxDimension;
            } else {
              w = Math.round((w * maxDimension) / h);
              h = maxDimension;
            }
          }
          const canvas = document.createElement('canvas');
          canvas.width = Math.max(w, 16);
          canvas.height = Math.max(h, 16);
          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
          const dataUrl = canvas.toDataURL('image/jpeg', quality);
          callback(dataUrl);
        } catch (err) {
          callback(e.target.result);
        }
      };
      img.onerror = () => callback(e.target.result);
      img.src = e.target.result;
    };
    reader.onerror = () => callback(null);
    reader.readAsDataURL(file);
  }

  // Photo Attachment Event Handlers
  if (ownerPhotoBtn && ownerPhotoInput) {
    ownerPhotoBtn.addEventListener('click', () => ownerPhotoInput.click());

    ownerPhotoInput.addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (file) {
        if (!file.type.startsWith('image/')) {
          showToast('Please select a valid image file (JPG, PNG).');
          return;
        }
        compressImage(file, 400, 0.72, (compressedDataUrl) => {
          ownerPhotoDataUrl = compressedDataUrl;
          if (ownerPhotoPreview) {
            ownerPhotoPreview.src = ownerPhotoDataUrl;
            ownerPhotoPreview.classList.remove('hidden');
          }
          if (ownerPhotoPlaceholder) ownerPhotoPlaceholder.classList.add('hidden');
          if (removeOwnerPhotoBtn) removeOwnerPhotoBtn.classList.remove('hidden');
          if (ownerPhotoFileName) ownerPhotoFileName.textContent = file.name;
          triggerQrUpdate(10);
        });
      }
    });
  }

  function resetOwnerPhoto() {
    ownerPhotoDataUrl = null;
    if (ownerPhotoInput) ownerPhotoInput.value = '';
    if (ownerPhotoPreview) {
      ownerPhotoPreview.src = '';
      ownerPhotoPreview.classList.add('hidden');
    }
    if (ownerPhotoPlaceholder) ownerPhotoPlaceholder.classList.remove('hidden');
    if (removeOwnerPhotoBtn) removeOwnerPhotoBtn.classList.add('hidden');
    if (ownerPhotoFileName) ownerPhotoFileName.textContent = '';
    triggerQrUpdate(10);
  }

  if (removeOwnerPhotoBtn) {
    removeOwnerPhotoBtn.addEventListener('click', resetOwnerPhoto);
  }

  function compressVehiclePhotoForQr(dataUrl, callback) {
    if (!dataUrl) {
      callback(null);
      return;
    }
    const img = new Image();
    img.onload = () => {
      try {
        const canvas = document.createElement('canvas');
        const maxDim = 32;
        let w = img.width;
        let h = img.height;
        if (w > h) {
          h = Math.round((h * maxDim) / w);
          w = maxDim;
        } else {
          w = Math.round((w * maxDim) / h);
          h = maxDim;
        }
        canvas.width = Math.max(w, 16);
        canvas.height = Math.max(h, 16);
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        const micro = canvas.toDataURL('image/jpeg', 0.3);
        callback(micro);
      } catch (err) {
        callback(null);
      }
    };
    img.onerror = () => callback(null);
    img.src = dataUrl;
  }

  // Vehicle Photo Attachment
  if (vehiclePhotoBtn && vehiclePhotoInput) {
    vehiclePhotoBtn.addEventListener('click', () => vehiclePhotoInput.click());

    vehiclePhotoInput.addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (file) {
        if (!file.type.startsWith('image/')) {
          showToast('Please select a valid image file (JPG, PNG).');
          return;
        }
        compressImage(file, 400, 0.72, (compressedDataUrl) => {
          vehiclePhotoDataUrl = compressedDataUrl;
          if (vehiclePhotoPreview) {
            vehiclePhotoPreview.src = vehiclePhotoDataUrl;
            vehiclePhotoPreview.classList.remove('hidden');
          }
          if (vehiclePhotoPlaceholder) vehiclePhotoPlaceholder.classList.add('hidden');
          if (removeVehiclePhotoBtn) removeVehiclePhotoBtn.classList.remove('hidden');
          if (vehiclePhotoFileName) vehiclePhotoFileName.textContent = file.name;
          
          compressVehiclePhotoForQr(vehiclePhotoDataUrl, (micro) => {
            vehiclePhotoMicroDataUrl = micro;
            triggerQrUpdate(10);
          });
        });
      }
    });
  }

  function resetVehiclePhoto() {
    vehiclePhotoDataUrl = null;
    vehiclePhotoMicroDataUrl = null;
    if (vehiclePhotoInput) vehiclePhotoInput.value = '';
    if (vehiclePhotoPreview) {
      vehiclePhotoPreview.src = '';
      vehiclePhotoPreview.classList.add('hidden');
    }
    if (vehiclePhotoPlaceholder) vehiclePhotoPlaceholder.classList.remove('hidden');
    if (removeVehiclePhotoBtn) removeVehiclePhotoBtn.classList.add('hidden');
    if (vehiclePhotoFileName) vehiclePhotoFileName.textContent = '';
    triggerQrUpdate(10);
  }

  if (removeVehiclePhotoBtn) {
    removeVehiclePhotoBtn.addEventListener('click', resetVehiclePhoto);
  }

  // Handle Form Submission
  if (vehicleForm) {
    vehicleForm.addEventListener('submit', (e) => {
      e.preventDefault();

      const plateNumber = plateInput.value.trim().toUpperCase();

      // Check duplicate plate
      if (state.vehicles.some(v => v.plateNumber === plateNumber)) {
        showToast(`Error: Plate ${plateNumber} is already registered!`);
        plateInput.focus();
        return;
      }

      const ownerFullName = document.getElementById('ownerFullName').value.trim();
      const ownerRole = document.getElementById('ownerRole').value;
      const department = document.getElementById('department').value.trim();
      const ownerIdNumber = document.getElementById('ownerIdNumber').value.trim();
      const ownerContact = document.getElementById('ownerContact').value.trim();
      const ownerEmail = document.getElementById('ownerEmail').value.trim();
      const vehicleCategory = document.getElementById('vehicleCategory').value;
      const makeModelColor = document.getElementById('makeModelColor').value.trim();
      const stickerYear = document.getElementById('stickerYear').value.trim() || '2026';
      const isVip = !!(document.getElementById('passClassVip') && document.getElementById('passClassVip').checked);

      // Read Authorized Drivers
      const driverCards = document.querySelectorAll('.driver-entry-card');
      const authorizedDrivers = [];

      driverCards.forEach((card, idx) => {
        const nameInput = card.querySelector('.driver-name');
        const relInput = card.querySelector('.driver-rel');
        const licenseInput = card.querySelector('.driver-license');
        const phoneInput = card.querySelector('.driver-phone');

        const name = nameInput ? nameInput.value.trim() : '';
        const rel = relInput ? relInput.value : 'Self (Owner)';
        const license = licenseInput ? licenseInput.value.trim() : '';
        const phone = phoneInput ? phoneInput.value.trim() : '';

        if (name) {
          authorizedDrivers.push({
            id: `drv-${Date.now()}-${idx}`,
            fullName: name,
            relationship: rel,
            licenseNo: license || 'N/A',
            phone: phone || ''
          });
        }
      });

      if (authorizedDrivers.length === 0) {
        authorizedDrivers.push({
          id: `drv-${Date.now()}-0`,
          fullName: ownerFullName,
          relationship: 'Self (Owner)',
          licenseNo: 'N/A',
          phone: ownerContact || ''
        });
      }

      const newVehicle = {
        id: `veh-${Date.now()}`,
        plateNumber,
        vehicleType: vehicleCategory,
        category: vehicleCategory.toLowerCase().includes('motorcycle') ? 'motorcycle' : (vehicleCategory.toLowerCase().includes('bicycle') ? 'non-plated' : 'plated'),
        makeModelColor,
        ownerName: ownerFullName,
        ownerRole,
        department,
        ownerIdNumber,
        ownerPhone: ownerContact,
        ownerEmail,
        qrPayload: null,
        status: 'Outside',
        registrationStatus: 'Active',
        entryTime: null,
        gatePoint: '—',
        stickerYear,
        passClass: isVip ? 'VIP' : 'Standard',
        isVip,
        ownerPhoto: ownerPhotoDataUrl,
        vehiclePhoto: vehiclePhotoDataUrl,
        authorizedDrivers
      };

      // Add to Registered Fleet (gate passages are only recorded when vehicle actually enters at a gate)
      state.vehicles.unshift(newVehicle);

      showToast(`Vehicle ${plateNumber} enrolled successfully.`);
      updateCounts();
      renderDashboard();
      renderFullAuditTable();

      // Synchronize with InfinityFree Backend API
      if (window.ApiClient) {
        ApiClient.registerVehicle({
          plateNumber,
          vehicleType: newVehicle.vehicleType,
          category: newVehicle.category,
          makeModelColor,
          ownerName: ownerFullName,
          ownerRole,
          department,
          ownerIdNumber,
          ownerPhone: ownerContact,
          ownerEmail,
          stickerYear,
          passClass: isVip ? 'VIP' : 'Standard',
          ownerPhoto: ownerPhotoDataUrl,
          vehiclePhoto: vehiclePhotoDataUrl,
          authorizedDrivers
        }).then(res => {
          if (res && res.id) newVehicle.id = res.id;
          if (res) applyServerPass(newVehicle, res);
          console.log('[App] Vehicle enrolled on backend:', res);
          showToast(`Signed pass issued for ${plateNumber}.`);
          switchView('vehiclesView');
          openVehicleDrawer(newVehicle);
          const acct = res && res.studentAccount;
          if (acct && acct.tempPassword && window.SPTempPassword) {
            SPTempPassword(`Student portal login for owner ID ${acct.ownerIdNumber} (new account)`, acct.tempPassword);
          }
        }).catch(err => {
          console.warn('[App] Local cache saved, API sync notice:', err.message);
          showToast(`Notice: Saved locally, server sync error: ${err.message}`);
        });
      }

      // Reset form
      vehicleForm.reset();
      resetDriverFields();
      resetOwnerPhoto();
      resetVehiclePhoto();
      plateValidationMsg.classList.add('hidden');
      plateInput.classList.remove('border-ncst-crimson');

    });
  }

  if (resetFormBtn) {
    resetFormBtn.addEventListener('click', () => {
      vehicleForm.reset();
      resetDriverFields();
      resetOwnerPhoto();
      resetVehiclePhoto();
      plateValidationMsg.classList.add('hidden');
      plateInput.classList.remove('border-ncst-crimson');
      generateQrPass(true);
      showToast('Registration form cleared.');
    });
  }

  /* ==========================================================================
     9.1 Live QR Gate Pass Technology Controller
     ========================================================================== */
  let qrDebounceTimer = null;
  function triggerQrUpdate(delay = 150) {
    if (qrDebounceTimer) clearTimeout(qrDebounceTimer);
    qrDebounceTimer = setTimeout(() => {
      generateQrPass(false);
    }, delay);
  }

  function generateQrPass(forceNewSalt = false) {
    if (!qrCodeContainer) return;

    if (forceNewSalt) {
      qrPassSalt = Math.random().toString(36).substring(2, 7).toUpperCase();
    }

    const plateVal = plateInput ? plateInput.value.trim().toUpperCase() : '';
    const plate = plateVal || 'NDK-4821';

    const ownerNameInput = document.getElementById('ownerFullName');
    const owner = (ownerNameInput && ownerNameInput.value.trim()) || 'Juan C. Dela Cruz';

    const roleInput = document.getElementById('ownerRole');
    const role = (roleInput && roleInput.value) || 'Student';

    const idInput = document.getElementById('ownerIdNumber');
    const idNum = (idInput && idInput.value.trim()) || 'NCST-2024-05182';

    const makeInput = document.getElementById('makeModelColor');
    const makeModel = (makeInput && makeInput.value.trim()) || 'White Toyota Vios';

    const catInput = document.getElementById('vehicleCategory');
    const category = (catInput && catInput.value) || '4-Wheel';

    const yearInput = document.getElementById('stickerYear');
    const year = (yearInput && yearInput.value.trim()) || '2026';

    const firstDriverInput = driversContainer ? driversContainer.querySelector('.driver-name') : null;
    const firstDriverRel = driversContainer ? driversContainer.querySelector('.driver-rel') : null;
    const driverName = (firstDriverInput && firstDriverInput.value.trim()) || owner;
    const driverRel = (firstDriverRel && firstDriverRel.value) || 'Self (Owner)';

    // Update Visual Pass Card
    if (qrPreviewPlate) qrPreviewPlate.textContent = plate;
    if (qrPreviewVehicle) qrPreviewVehicle.textContent = `${makeModel} (${category})`;
    if (qrPreviewRole) qrPreviewRole.textContent = role.toUpperCase();
    if (qrPreviewId) qrPreviewId.textContent = idNum;
    if (qrStickerYearBadge) qrStickerYearBadge.textContent = year;
    if (qrPreviewOwnerName) qrPreviewOwnerName.textContent = owner;
    if (qrPreviewDriverName) qrPreviewDriverName.textContent = `${driverName} (${driverRel})`;

    // Read all authorized drivers from the form
    const driverCards = driversContainer ? driversContainer.querySelectorAll('.driver-entry-card') : [];
    const authorizedDriversList = [];
    driverCards.forEach(card => {
      const nameInput = card.querySelector('.driver-name');
      const relInput = card.querySelector('.driver-rel');
      const licInput = card.querySelector('.driver-license');
      const dName = nameInput ? nameInput.value.trim() : '';
      if (dName) {
        authorizedDriversList.push({
          fullName: dName,
          relationship: relInput ? relInput.value : 'Self (Owner)',
          licenseNo: (licInput && licInput.value.trim()) || 'N/A'
        });
      }
    });

    if (authorizedDriversList.length === 0) {
      authorizedDriversList.push({
        fullName: owner,
        relationship: 'Self (Owner)',
        licenseNo: 'N/A'
      });
    }

    // Update Authorized Drivers Roster in Visual Pass Card
    if (qrDriversCountBadge) {
      qrDriversCountBadge.textContent = `${authorizedDriversList.length} ${authorizedDriversList.length === 1 ? 'Driver' : 'Drivers'}`;
    }
    if (qrPreviewDriversList) {
      qrPreviewDriversList.innerHTML = authorizedDriversList.map(d => `
        <div class="flex items-center justify-between text-xs bg-white p-1.5 rounded border border-slate-200">
          <div class="min-w-0 pr-2">
            <span class="font-bold text-slate-800 text-[11px] truncate block">${escapeHtml(d.fullName)}</span>
            <span class="text-[10px] text-slate-500">${escapeHtml(d.relationship)}</span>
          </div>
          <div class="text-right flex-shrink-0">
            <span class="font-mono text-[10px] bg-slate-100 text-slate-700 px-1.5 py-0.5 rounded border border-slate-200 font-semibold">${escapeHtml(d.licenseNo)}</span>
          </div>
        </div>
      `).join('');
    }

    // Valid structured JSON pass payload for real-time mobile gate scanner detection
    const passPayloadObj = {
      v: 1,
      plateNumber: plate,
      plate_number: plate,
      ownerFullName: owner,
      owner_name: owner,
      ownerRole: role,
      owner_role: role,
      ownerStudentId: idNum,
      owner_id_number: idNum,
      vehicleCategory: category,
      vehicle_type: category,
      makeModelColor: makeModel,
      make_model_color: makeModel,
      stickerYear: year,
      sticker_year: year,
      authorizedDrivers: authorizedDriversList,
      authorized_drivers: authorizedDriversList
    };
    let payloadString = JSON.stringify(passPayloadObj);

    // Update Photo Thumbnails in the Pass Card
    if (ownerPhotoDataUrl && qrOwnerThumb) {
      qrOwnerThumb.src = ownerPhotoDataUrl;
      qrOwnerThumb.classList.remove('hidden');
      if (qrOwnerPlaceholder) qrOwnerPlaceholder.classList.add('hidden');
    } else if (qrOwnerThumb) {
      qrOwnerThumb.src = '';
      qrOwnerThumb.classList.add('hidden');
      if (qrOwnerPlaceholder) qrOwnerPlaceholder.classList.remove('hidden');
    }

    if (vehiclePhotoDataUrl && qrVehicleThumb) {
      qrVehicleThumb.src = vehiclePhotoDataUrl;
      qrVehicleThumb.classList.remove('hidden');
      if (qrVehiclePlaceholder) qrVehiclePlaceholder.classList.add('hidden');
    } else if (qrVehicleThumb) {
      qrVehicleThumb.src = '';
      qrVehicleThumb.classList.add('hidden');
      if (qrVehiclePlaceholder) qrVehiclePlaceholder.classList.remove('hidden');
    }

    // Render QR Code using QRCode library
    if (typeof QRCode !== 'undefined') {
      try {
        if (!qrCodeInstance) {
          qrCodeContainer.innerHTML = '';
          qrCodeInstance = new QRCode(qrCodeContainer, {
            text: payloadString,
            width: 220,
            height: 220,
            colorDark: "#0F172A",
            colorLight: "#ffffff",
            correctLevel: QRCode.CorrectLevel.L
          });
        } else {
          qrCodeInstance.clear();
          qrCodeInstance.makeCode(payloadString);
        }
      } catch (err) {
        console.warn('QRCode generation fallback notice:', err);
      }
    }

    lastPreviewPassInfo = {
      payload: payloadString,
      plate,
      owner,
      year,
      category
    };
  }

  // Bind Real-Time QR Listeners on Vehicle Registration Form
  if (vehicleForm) {
    vehicleForm.addEventListener('input', () => triggerQrUpdate(120));
    vehicleForm.addEventListener('change', () => triggerQrUpdate(50));
  }

  // Composite Pass Badge Generator (Draws 1x1 Photo + QR Code onto official high-res badge)
  function generateCompositePassImage(plate, owner, idNum, role, category, makeModel, year, driverName, driverRel, photoUrl, vehPhotoUrl, qrSourceEl, authorizedDriversList, callback) {
    const canvas = document.createElement('canvas');
    const w = 620;
    const h = 840;
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');

    // Background card with shadow effect & border
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, w, h);

    // Outer security border
    ctx.strokeStyle = '#0F172A';
    ctx.lineWidth = 4;
    ctx.strokeRect(8, 8, w - 16, h - 16);

    // Inner security hairline border
    ctx.strokeStyle = '#CBD5E1';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(14, 14, w - 28, h - 28);

    // Header Ribbon (NCST Navy #1A3B8B)
    ctx.fillStyle = '#1A3B8B';
    ctx.fillRect(14, 14, w - 28, 86);

    // Gold accent stripe (#F5B800)
    ctx.fillStyle = '#F5B800';
    ctx.fillRect(14, 100, w - 28, 5);

    // Header Title (Centered)
    ctx.fillStyle = '#FFFFFF';
    ctx.font = 'bold 21px "Plus Jakarta Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('NATIONAL COLLEGE OF SCIENCE AND TECHNOLOGY', w / 2, 62);
    ctx.textAlign = 'left';

    // Plate Box (Philippine License Plate style)
    ctx.fillStyle = '#F8FAFC';
    ctx.fillRect(32, 134, w - 64, 86);
    ctx.strokeStyle = '#CBD5E1';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(32, 134, w - 64, 86);

    // Plate top band
    ctx.fillStyle = '#1A3B8B';
    ctx.fillRect(32, 134, w - 64, 18);
    ctx.fillStyle = '#FFFFFF';
    ctx.font = 'bold 10px "Plus Jakarta Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('PILIPINAS — CAMPUS REGISTERED', w / 2, 147);

    // Plate Number
    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 36px "JetBrains Mono", monospace';
    ctx.fillText(plate, w / 2, 188);

    // Vehicle Info below plate
    ctx.font = '600 12px "Plus Jakarta Sans", sans-serif';
    ctx.fillStyle = '#475569';
    ctx.fillText(`${makeModel} • ${category}`, w / 2, 208);
    ctx.textAlign = 'left';

    // Role Badge
    ctx.fillStyle = '#EFF6FF';
    ctx.fillRect(w - 150, 144, 104, 26);
    ctx.strokeStyle = '#BFDBFE';
    ctx.lineWidth = 1;
    ctx.strokeRect(w - 150, 144, 104, 26);
    ctx.fillStyle = '#1E40AF';
    ctx.font = 'bold 11px "Plus Jakarta Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(role.toUpperCase(), w - 98, 161);
    ctx.textAlign = 'left';

    // Middle Row: Left = 1x1 Photo Box; Right = Scannable QR Code
    const midY = 238;

    // Photo Box Container
    ctx.fillStyle = '#F8FAFC';
    ctx.fillRect(32, midY, 240, 290);
    ctx.strokeStyle = '#E2E8F0';
    ctx.lineWidth = 1;
    ctx.strokeRect(32, midY, 240, 290);

    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 11px "Plus Jakarta Sans", sans-serif';
    ctx.fillText('VERIFIED IDENTIFICATION', 48, midY + 24);

    function finishDraw(imgOwner, imgVehicle) {
      const photoX = 52;
      const photoY = midY + 36;
      const photoW = 140;
      const photoH = 140;

      if (imgOwner) {
        ctx.drawImage(imgOwner, photoX, photoY, photoW, photoH);
        ctx.strokeStyle = '#1E293B';
        ctx.lineWidth = 1.5;
        ctx.strokeRect(photoX, photoY, photoW, photoH);

        // Photo label badge
        ctx.fillStyle = 'rgba(15, 23, 42, 0.85)';
        ctx.fillRect(photoX, photoY + photoH - 22, photoW, 22);
        ctx.fillStyle = '#FFFFFF';
        ctx.font = 'bold 9px "Plus Jakarta Sans", sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('1x1 OWNER PHOTO', photoX + photoW / 2, photoY + photoH - 7);
        ctx.textAlign = 'left';
      } else {
        ctx.fillStyle = '#E2E8F0';
        ctx.fillRect(photoX, photoY, photoW, photoH);
        ctx.strokeStyle = '#CBD5E1';
        ctx.lineWidth = 1;
        ctx.strokeRect(photoX, photoY, photoW, photoH);
        ctx.fillStyle = '#64748B';
        ctx.font = 'bold 12px "Plus Jakarta Sans", sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('1x1 PHOTO', photoX + photoW / 2, photoY + 65);
        ctx.font = '9px "Plus Jakarta Sans", sans-serif';
        ctx.fillText('OFFICIAL ID', photoX + photoW / 2, photoY + 82);
        ctx.textAlign = 'left';
      }

      // Secondary box: Vehicle photo or owner record summary
      if (imgVehicle) {
        const vehY = photoY + photoH + 12;
        const vehW = 140;
        const vehH = 80;
        ctx.drawImage(imgVehicle, photoX, vehY, vehW, vehH);
        ctx.strokeStyle = '#1E293B';
        ctx.lineWidth = 1;
        ctx.strokeRect(photoX, vehY, vehW, vehH);

        ctx.fillStyle = 'rgba(15, 23, 42, 0.85)';
        ctx.fillRect(photoX, vehY + vehH - 18, vehW, 18);
        ctx.fillStyle = '#FFFFFF';
        ctx.font = 'bold 8px "Plus Jakarta Sans", sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('REGISTERED VEHICLE', photoX + vehW / 2, vehY + vehH - 5);
        ctx.textAlign = 'left';
      } else {
        const infoY = photoY + photoH + 20;
        ctx.fillStyle = '#64748B';
        ctx.font = '9px "Plus Jakarta Sans", sans-serif';
        ctx.fillText('OWNER ON FILE:', 52, infoY);
        ctx.fillStyle = '#0F172A';
        ctx.font = 'bold 11px "Plus Jakarta Sans", sans-serif';
        ctx.fillText(owner.slice(0, 22), 52, infoY + 16);
        ctx.font = '10px "JetBrains Mono", monospace';
        ctx.fillStyle = '#475569';
        ctx.fillText(idNum, 52, infoY + 34);
      }

      // QR Code Box (Clean Light Institutional Card)
      const qrBoxX = 292;
      const qrBoxW = w - qrBoxX - 32;
      ctx.fillStyle = '#F8FAFC';
      ctx.fillRect(qrBoxX, midY, qrBoxW, 290);
      ctx.strokeStyle = '#CBD5E1';
      ctx.lineWidth = 1;
      ctx.strokeRect(qrBoxX, midY, qrBoxW, 290);

      // QR Header
      ctx.fillStyle = '#0F172A';
      ctx.font = 'bold 11px "Plus Jakarta Sans", sans-serif';
      ctx.fillText('GATE ACCESS QR CODE', qrBoxX + 16, midY + 24);

      // QR Target Box (White)
      const qrCanvasW = 180;
      const qrCanvasH = 180;
      const qrX = qrBoxX + (qrBoxW - qrCanvasW) / 2;
      const qrY = midY + 44;

      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(qrX - 10, qrY - 10, qrCanvasW + 20, qrCanvasH + 20);
      ctx.strokeStyle = '#CBD5E1';
      ctx.lineWidth = 1.5;
      ctx.strokeRect(qrX - 10, qrY - 10, qrCanvasW + 20, qrCanvasH + 20);

      // Draw QR Canvas or Image
      if (qrSourceEl) {
        ctx.drawImage(qrSourceEl, qrX, qrY, qrCanvasW, qrCanvasH);
      }

      // Lower Particulars Grid
      const lowY = 548;
      ctx.fillStyle = '#F8FAFC';
      ctx.fillRect(32, lowY, w - 64, 155);
      ctx.strokeStyle = '#E2E8F0';
      ctx.lineWidth = 1;
      ctx.strokeRect(32, lowY, w - 64, 155);

      // Row 1
      ctx.fillStyle = '#64748B';
      ctx.font = '10px "Plus Jakarta Sans", sans-serif';
      ctx.fillText('REGISTERED OWNER:', 48, lowY + 24);
      ctx.fillText('INSTITUTIONAL ID:', 340, lowY + 24);

      ctx.fillStyle = '#0F172A';
      ctx.font = 'bold 13px "Plus Jakarta Sans", sans-serif';
      ctx.fillText(owner, 48, lowY + 44);
      ctx.font = 'bold 13px "JetBrains Mono", monospace';
      ctx.fillText(idNum, 340, lowY + 44);

      // Divider line
      ctx.strokeStyle = '#E2E8F0';
      ctx.beginPath();
      ctx.moveTo(48, lowY + 56);
      ctx.lineTo(w - 48, lowY + 56);
      ctx.stroke();

      // Row 2
      ctx.fillStyle = '#64748B';
      ctx.font = '10px "Plus Jakarta Sans", sans-serif';
      ctx.fillText('AUTHORIZED DRIVER(S) IN QR:', 48, lowY + 76);
      ctx.fillText('AFFILIATION & PERMIT:', 340, lowY + 76);

      ctx.fillStyle = '#0F172A';
      ctx.font = 'bold 12px "Plus Jakarta Sans", sans-serif';
      const drvCount = (authorizedDriversList && authorizedDriversList.length) || 1;
      const drvLabel = drvCount > 1 
        ? `${driverName} (${driverRel}) [+${drvCount - 1} more in QR]`
        : `${driverName} (${driverRel})`;
      ctx.fillText(drvLabel.slice(0, 36), 48, lowY + 94);
      ctx.fillText(`${role} • Validated Pass`, 340, lowY + 94);

      // Divider line
      ctx.beginPath();
      ctx.moveTo(48, lowY + 108);
      ctx.lineTo(w - 48, lowY + 108);
      ctx.stroke();

      // Row 3
      ctx.fillStyle = '#64748B';
      ctx.font = '10px "JetBrains Mono", monospace';
      ctx.fillText(`STATUS: ACTIVE / VERIFIED`, 48, lowY + 134);
      ctx.textAlign = 'right';
      ctx.fillText(`ISSUED: ${new Date().toISOString().slice(0, 10)}`, w - 48, lowY + 134);
      ctx.textAlign = 'left';

      // Footer Legal & Safety Notice
      const footY = 724;
      ctx.fillStyle = '#0F172A';
      ctx.font = 'bold 10px "Plus Jakarta Sans", sans-serif';
      ctx.fillText('NCST CAMPUS SECURITY & MOTOR VEHICLE ACCESS REGULATION', 32, footY);
      ctx.font = '9px "Plus Jakarta Sans", sans-serif';
      ctx.fillStyle = '#64748B';
      ctx.fillText('This permit must be displayed on vehicle windshield or presented to Gate Officers upon entry.', 32, footY + 16);
      ctx.fillText('Unauthorized duplication or custody transfer is subject to administrative sanction and vehicle impoundment.', 32, footY + 30);

      callback(canvas.toDataURL('image/png'));
    }

    // Preload photos if available
    let loadedOwnerImg = null;
    let loadedVehImg = null;
    let toLoad = 0;
    let loaded = 0;

    function checkDone() {
      loaded++;
      if (loaded >= toLoad) {
        finishDraw(loadedOwnerImg, loadedVehImg);
      }
    }

    if (photoUrl) {
      toLoad++;
      loadedOwnerImg = new Image();
      loadedOwnerImg.crossOrigin = 'anonymous';
      loadedOwnerImg.onload = checkDone;
      loadedOwnerImg.onerror = checkDone;
      loadedOwnerImg.src = photoUrl;
    }

    if (vehPhotoUrl) {
      toLoad++;
      loadedVehImg = new Image();
      loadedVehImg.crossOrigin = 'anonymous';
      loadedVehImg.onload = checkDone;
      loadedVehImg.onerror = checkDone;
      loadedVehImg.src = vehPhotoUrl;
    }

    if (toLoad === 0) {
      finishDraw(null, null);
    }
  }

  // QR Technology Action Button Handlers
  if (downloadPassBadgeBtn) {
    downloadPassBadgeBtn.addEventListener('click', () => {
      showToast('Register the vehicle first. The signed pass opens automatically after saving (Print Pass in the dossier).');
      return;
      // eslint-disable-next-line no-unreachable
      if (!qrCodeContainer) return;
      const qrEl = qrCodeContainer.querySelector('canvas') || qrCodeContainer.querySelector('img');
      if (!qrEl) {
        showToast('Generating security pass, please try again.');
        return;
      }

      const plate = (plateInput && plateInput.value.trim().toUpperCase()) || 'NDK-4821';
      const owner = (document.getElementById('ownerFullName') && document.getElementById('ownerFullName').value.trim()) || 'Juan C. Dela Cruz';
      const role = (document.getElementById('ownerRole') && document.getElementById('ownerRole').value) || 'Student';
      const idNum = (document.getElementById('ownerIdNumber') && document.getElementById('ownerIdNumber').value.trim()) || 'NCST-2024-05182';
      const makeModel = (document.getElementById('makeModelColor') && document.getElementById('makeModelColor').value.trim()) || 'White Toyota Vios';
      const category = (document.getElementById('vehicleCategory') && document.getElementById('vehicleCategory').value) || '4-Wheel';
      const year = (document.getElementById('stickerYear') && document.getElementById('stickerYear').value.trim()) || '2026';

      const firstDriverInput = driversContainer ? driversContainer.querySelector('.driver-name') : null;
      const firstDriverRel = driversContainer ? driversContainer.querySelector('.driver-rel') : null;
      const driverName = (firstDriverInput && firstDriverInput.value.trim()) || owner;
      const driverRel = (firstDriverRel && firstDriverRel.value) || 'Self (Owner)';

      const driverCards = driversContainer ? driversContainer.querySelectorAll('.driver-entry-card') : [];
      const currentDrivers = [];
      driverCards.forEach(card => {
        const n = card.querySelector('.driver-name') ? card.querySelector('.driver-name').value.trim() : '';
        const r = card.querySelector('.driver-rel') ? card.querySelector('.driver-rel').value : 'Self (Owner)';
        const l = card.querySelector('.driver-license') ? card.querySelector('.driver-license').value.trim() : '';
        if (n) currentDrivers.push({ fullName: n, relationship: r, licenseNo: l || 'N/A' });
      });
      if (currentDrivers.length === 0) {
        currentDrivers.push({ fullName: owner, relationship: 'Self (Owner)', licenseNo: 'N/A' });
      }

      showToast('Rendering official Gate Pass Badge with photo...');

      generateCompositePassImage(
        plate, owner, idNum, role, category, makeModel, year, driverName, driverRel,
        ownerPhotoDataUrl, vehiclePhotoDataUrl, qrEl, currentDrivers,
        (dataUrl) => {
          const a = document.createElement('a');
          a.href = dataUrl;
          a.download = `NCST_GATE_PASS_${plate}_WITH_PHOTO.png`;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
          showToast(`Downloaded Gate Pass Badge with 1x1 Photo for ${plate}`);
        }
      );
    });
  }

  if (downloadQrBtn) {
    downloadQrBtn.addEventListener('click', () => {
      if (!qrCodeContainer) return;
      const canvas = qrCodeContainer.querySelector('canvas');
      const img = qrCodeContainer.querySelector('img');
      let dataUrl = null;
      if (canvas) {
        dataUrl = canvas.toDataURL('image/png');
      } else if (img && img.src && img.src.startsWith('data:image')) {
        dataUrl = img.src;
      }

      if (!dataUrl) {
        showToast('Generating QR code image, please try again.');
        return;
      }

      const plate = (plateInput && plateInput.value.trim().toUpperCase()) || 'NCST-PASS';
      const a = document.createElement('a');
      a.href = dataUrl;
      a.download = `NCST_QR_CODE_${plate}.png`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      showToast(`Downloaded QR Code for ${plate}`);
    });
  }

  if (printGatePassBtn) {
    printGatePassBtn.addEventListener('click', () => {
      const currentPass = (state && state.lastSavedVehicle) ? state.lastSavedVehicle : {
        plateNumber: (plateInput && plateInput.value.trim().toUpperCase()) || (qrPreviewPlate ? qrPreviewPlate.textContent.trim() : 'NDK-4821'),
        ownerName: (ownerFullName && ownerFullName.value.trim()) || (qrPreviewOwnerName ? qrPreviewOwnerName.textContent.trim() : 'Juan C. Dela Cruz'),
        ownerIdNumber: (ownerIdNumber && ownerIdNumber.value.trim()) || (qrPreviewId ? qrPreviewId.textContent.trim() : 'NCST-2024-05182'),
        stickerYear: (stickerYear && stickerYear.value.trim()) || (qrStickerYearBadge ? qrStickerYearBadge.textContent.trim() : '2026'),
        vehicleType: (vehicleCategory && vehicleCategory.value) || '4-Wheel',
        makeModelColor: (makeModelColor && makeModelColor.value.trim()) || (qrPreviewVehicle ? qrPreviewVehicle.textContent.trim() : 'White Toyota Vios')
      };
      printVehiclePass(currentPass);
    });
  }

  /* ==========================================================================
     9.2 Signed Pass Helpers (payloads are signed by the server, never here)
     ========================================================================== */
  const PASS_UNAVAILABLE_MSG = 'Signed pass not available yet. Save the vehicle online, then reload.';

  // A gate log the mobile app recorded offline and sent later shows when it reached the server
  function offlineChip(log) {
    if (!log || !log.syncedAt || !log.loggedAt) return '';
    const happened = Date.parse(String(log.loggedAt).replace(' ', 'T') + '+08:00');
    const synced = Date.parse(String(log.syncedAt).replace(' ', 'T') + '+08:00');
    if (isNaN(happened) || isNaN(synced) || synced - happened < 120000) return '';
    const at = new Date(synced).toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit' });
    return `<div class="mt-0.5"><span class="inline-block px-1.5 py-0.5 rounded bg-ncst-navy/10 text-ncst-navy border border-ncst-navy/20 text-[9px] font-bold tracking-wide" title="Recorded offline at the gate; reached the server at ${escapeHtml(log.syncedAt)}">OFFLINE &middot; synced ${escapeHtml(at)}</span></div>`;
  }

  function strikeChip(v) {
    if (v.isVip) return '<span class="inline-flex items-center px-1.5 py-0.5 rounded bg-amber-50 text-amber-800 border border-amber-200/80 text-[10px] font-semibold tracking-wide">VIP</span>';
    if (v.isBanned) return '<span class="inline-flex items-center px-1.5 py-0.5 rounded bg-rose-50 text-rose-700 border border-rose-200 text-[10px] font-semibold tracking-wide">BANNED</span>';
    const n = Number(v.warningCount || 0);
    return n > 0 ? `<span class="inline-flex items-center px-1.5 py-0.5 rounded bg-amber-50 text-amber-800 border border-amber-200 text-[10px] font-semibold">STRIKE ${n}/3</span>` : '';
  }

  function passPayloadFor(v) {
    if (!v) return null;
    if (typeof v.qrPayload === 'string' && v.qrPayload.startsWith('{')) {
      return v.qrPayload;
    }
    const plate = v.plateNumber || v.plate_number || '';
    if (!plate) return null;
    return JSON.stringify({
      v: 1,
      plateNumber: plate,
      plate_number: plate,
      ownerFullName: v.ownerName || v.owner_name || 'Registered Owner',
      owner_name: v.ownerName || v.owner_name || 'Registered Owner',
      ownerRole: v.ownerRole || v.owner_role || 'Student',
      owner_role: v.ownerRole || v.owner_role || 'Student',
      ownerStudentId: v.ownerIdNumber || v.owner_id_number || 'N/A',
      owner_id_number: v.ownerIdNumber || v.owner_id_number || 'N/A',
      vehicleCategory: v.vehicleType || v.vehicle_type || '4-Wheel',
      vehicle_type: v.vehicleType || v.vehicle_type || '4-Wheel',
      makeModelColor: v.makeModelColor || v.make_model_color || 'Vehicle',
      make_model_color: v.makeModelColor || v.make_model_color || 'Vehicle',
      stickerYear: v.stickerYear || v.sticker_year || '2026',
      sticker_year: v.stickerYear || v.sticker_year || '2026',
      authorizedDrivers: (v.authorizedDrivers || []).map(d => ({
        fullName: d.fullName || d.full_name || '',
        relationship: d.relationship || 'Self (Owner)',
        licenseNo: d.licenseNo || d.license_no || 'N/A'
      }))
    });
  }

  function applyServerPass(target, serverVehicle) {
    target.qrPayload = serverVehicle.qrPayload || target.qrPayload || null;
    target.passId = serverVehicle.passId || target.passId || null;
    target.passValidUntil = serverVehicle.passValidUntil || target.passValidUntil || null;
    if (serverVehicle.plateNumber) target.plateNumber = serverVehicle.plateNumber;
    if (typeof serverVehicle.isVip === 'boolean') {
      target.isVip = serverVehicle.isVip;
      target.passClass = serverVehicle.isVip ? 'VIP' : 'Standard';
      target.vipGrantedBy = serverVehicle.vipGrantedBy || null;
      target.vipGrantedAt = serverVehicle.vipGrantedAt || null;
    }
  }

  async function reissueVehiclePass(v) {
    if (!v || !v.id) return;
    const confirmed = window.SPAlert
      ? await SPAlert.confirm({
          title: 'Issue New QR Pass?',
          text: `Issue a new pass for ${v.plateNumber}? Every previously printed QR code for this vehicle will stop working immediately.`,
          confirmText: 'Issue New Pass',
          icon: 'warning',
          isDanger: true
        })
      : confirm(`Issue a new pass for ${v.plateNumber}?\n\nEvery previously printed QR code for this vehicle will stop working immediately.`);
    if (!confirmed) return;
    try {
      const saved = await ApiClient.reissuePass(v.id);
      const target = state.vehicles.find(x => x.id === v.id) || v;
      applyServerPass(target, saved);
      showToast(`New pass issued for ${v.plateNumber}. Old QR codes are revoked.`, 'success');
      renderVehiclesTable();
      openVehicleDrawer(target);
    } catch (err) {
      showToast(`Reissue failed: ${err.message}`, 'error');
    }
  }

  /* ==========================================================================
     10. Utility Functions
     ========================================================================== */
  function showToast(message, type) {
    if (window.SPAlert && typeof SPAlert.toast === 'function') {
      return SPAlert.toast(message, type);
    }
    if (!toastHub) return;
    const toast = document.createElement('div');
    toast.className = `pointer-events-auto px-4 py-2.5 rounded-md shadow-lg text-xs font-semibold text-white bg-slate-900 border border-slate-700 transition-all duration-200 transform translate-y-2 opacity-0`;
    toast.textContent = message;

    toastHub.appendChild(toast);

    // Fade in
    requestAnimationFrame(() => {
      toast.classList.remove('translate-y-2', 'opacity-0');
    });

    // Fade out
    setTimeout(() => {
      toast.classList.add('opacity-0', 'translate-y-2');
      setTimeout(() => toast.remove(), 200);
    }, 2800);
  }

  function formatCurrentTime() {
    const d = new Date();
    let hours = d.getHours();
    const minutes = d.getMinutes().toString().padStart(2, '0');
    const ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    hours = hours ? hours : 12;
    return `${hours.toString().padStart(2, '0')}:${minutes} ${ampm}`;
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str).replace(/[&<>'"]/g, 
      tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)
    );
  }

  function formatPassId(vehicle) {
    if (!vehicle) return 'PASS-NCST';
    const raw = vehicle.qrPassCode || vehicle.qr_pass_code || '';
    if (raw && !raw.startsWith('{') && !raw.includes('"') && raw.length < 32) {
      return raw;
    }
    const plate = vehicle.plateNumber || vehicle.plate_number || '';
    const cleanPlate = plate.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    const year = vehicle.stickerYear || vehicle.sticker_year || '2026';
    return `NCST-PASS-${year}-${cleanPlate}`;
  }

  // Keyboard Ergonomics
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeDrawer();
      closeEditModal();
    }
  });

  /* ==========================================================================
     Initial Boot
     ========================================================================== */
  initGateFlowTabs();
  renderDashboard();
  renderVehiclesTable();
  renderIncidentsTable();
  renderFullAuditTable();
  generateQrPass(true);

  // Synchronize with InfinityFree MySQL Backend API
  // The vehicle registry is the heavy call (owner and vehicle photos), so background refreshes fetch it at
  // most once a minute; explicit reloads and gate passages ask for it right away.
  const VEHICLES_REFRESH_MS = 60 * 1000;
  let lastVehiclesLoad = 0;

  async function loadInitialDataFromApi(silent = false, forceVehicles = false) {
    if (!window.ApiClient) return;
    try {
      const needVehicles = !silent || forceVehicles || (Date.now() - lastVehiclesLoad) >= VEHICLES_REFRESH_MS;
      const [vehicles, logs, incidents, visitors, onCampus] = await Promise.all([
        needVehicles ? ApiClient.getVehicles().catch(() => null) : Promise.resolve(null),
        ApiClient.getLogs().catch(() => null),
        ApiClient.getIncidents().catch(() => null),
        ApiClient.getVisitorPasses().catch(() => null),
        ApiClient.getOnCampus().catch(() => null)
      ]);

      let hasUpdate = false;
      if (vehicles && Array.isArray(vehicles)) {
        state.vehicles = vehicles.map(v => normalizeVehicle(v));
        lastVehiclesLoad = Date.now();
        hasUpdate = true;
      }
      if (logs && Array.isArray(logs)) {
        state.auditLogs = logs;
        hasUpdate = true;
      }
      if (incidents && Array.isArray(incidents)) {
        state.incidents = incidents;
        hasUpdate = true;
      }
      if (visitors && Array.isArray(visitors)) {
        state.visitors = visitors;
        hasUpdate = true;
      }
      if (onCampus && onCampus.counts) {
        state.onCampus = onCampus;
        hasUpdate = true;
      }

      if (hasUpdate) {
        updateCounts();
        renderDashboard();
        renderVehiclesTable();
        renderIncidentsTable();
        renderFullAuditTable();
        if (!silent) console.log('[App] Synchronized state with backend.');
      }
    } catch (err) {
      console.warn('[App] Backend sync note:', err.message);
    }
    // Feature modules (gate monitor, violations, ...) refresh their panels on this
    document.dispatchEvent(new CustomEvent('sp:data-loaded'));
  }

  /* ==========================================================================
     Bridge for feature modules (auth.js, users.js, ...)
     ========================================================================== */
  window.SP = {
    state,
    switchView,
    showToast,
    escapeHtml,
    openDrawer,
    closeDrawer,
    alert: window.SPAlert,
    reload: loadInitialDataFromApi,
    openVehicle(id) {
      const v = state.vehicles.find(x => x.id === id);
      if (v) openVehicleDrawer(v);
      return !!v;
    },
    registerView(viewId, navBtn, onShow) {
      views[viewId] = document.getElementById(viewId);
      if (navBtn) {
        navMap[viewId] = navBtn;
        navBtn.addEventListener('click', () => switchView(viewId));
      }
      if (onShow) viewHooks[viewId] = onShow;
    }
  };
  document.dispatchEvent(new CustomEvent('sp:app-ready'));

  // Data is only loaded once a staff member is signed in
  if (window.SPAuth) {
    SPAuth.whenAuthenticated(() => {
      loadInitialDataFromApi();
      // Admins land on the dashboard, guards on the Gate Monitor
      switchView(SPAuth.hasRole('admin') ? 'dashboardView' : 'gateView');
    });
  } else {
    loadInitialDataFromApi();
  }

  // Background refresh: every 30 seconds, and never while the tab is hidden (free hosting has a daily request limit)
  setInterval(() => {
    if (document.hidden) return;
    if (!window.SPAuth || SPAuth.isAuthenticated()) {
      loadInitialDataFromApi(true);
    }
  }, 30000);

  // Instant refresh when user returns to window
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && (!window.SPAuth || SPAuth.isAuthenticated())) {
      loadInitialDataFromApi(true);
    }
  });

  // Instant refresh on gate passage events
  document.addEventListener('sp:gate-passage', () => {
    loadInitialDataFromApi(true, true);
  });

  // Global dismiss listener for Vehicle Directory row overflow menus
  document.addEventListener('click', (e) => {
    if (!e.target.closest('.overflow-menu-container')) {
      document.querySelectorAll('#vehiclesTableBody .overflow-menu-dropdown').forEach(d => {
        d.classList.add('hidden');
      });
      document.querySelectorAll('#vehiclesTableBody .overflow-menu-btn').forEach(b => {
        b.setAttribute('aria-expanded', 'false');
      });
    }
  });
});
