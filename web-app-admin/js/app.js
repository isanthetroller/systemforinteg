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
    currentView: 'dashboardView',
    vehicleFilter: {
      search: '',
      role: 'All',
      category: 'All',
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
  const vehicleStatusFilter = document.getElementById('vehicleStatusFilter');
  const vehiclesTableBody = document.getElementById('vehiclesTableBody');

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

  function switchView(targetViewId) {
    if (!views[targetViewId]) return;

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

    // Update navigation item styles for white sidebar
    const activeClass = "nav-item w-full flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-bold text-ncst-navy bg-blue-50/80 border-l-4 border-ncst-navy shadow-2xs transition-colors text-left cursor-pointer";
    const inactiveClass = "nav-item w-full flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-semibold text-slate-600 hover:text-ncst-navy hover:bg-slate-50 transition-colors text-left cursor-pointer";

    Object.keys(navMap).forEach(key => {
      const btn = navMap[key];
      if (!btn) return;
      const svg = btn.querySelector('svg');

      if (key === targetViewId) {
        btn.className = activeClass;
        if (svg) svg.className = "w-4 h-4 text-ncst-navy flex-shrink-0";
      } else {
        btn.className = inactiveClass;
        if (svg) {
          if (key === 'flaggedView') {
            svg.className = "w-4 h-4 text-ncst-crimson flex-shrink-0";
          } else {
            svg.className = "w-4 h-4 text-slate-400 flex-shrink-0";
          }
        }
      }
    });

    // View-specific initialization
    if (targetViewId === 'dashboardView') {
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
    const insideCount = state.vehicles.filter(v => (v.status || '').toLowerCase().includes('inside')).length;
    const activeIncidents = state.incidents.filter(i => i.status === 'Held').length;
    const blockedCount = activeIncidents > 0 ? activeIncidents : state.vehicles.filter(v => v.status === 'Blocked / Alert').length;

    if (kpiInside) kpiInside.textContent = insideCount;
    if (kpiBlocked) kpiBlocked.textContent = blockedCount;
    if (kpiTotalLogs) kpiTotalLogs.textContent = state.auditLogs.length;
    if (kpiRegistered) kpiRegistered.textContent = state.vehicles.length;

    if (flaggedSidebarCount) {
      flaggedSidebarCount.textContent = activeIncidents;
      if (activeIncidents > 0) {
        flaggedSidebarCount.className = "text-[10px] px-1.5 py-0.2 rounded font-bold bg-rose-50 text-ncst-crimson border border-rose-200";
      } else {
        flaggedSidebarCount.className = "text-[10px] px-1.5 py-0.2 rounded font-bold bg-slate-100 text-slate-400 border border-slate-200";
      }
    }

    if (incidentQueueBadge) {
      incidentQueueBadge.textContent = `${activeIncidents} Active ${activeIncidents === 1 ? 'Case' : 'Cases'}`;
      if (activeIncidents > 0) {
        incidentQueueBadge.className = "text-xs px-2.5 py-0.5 rounded-full font-bold bg-rose-50 text-rose-700 border border-rose-200";
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

    const insideCount = state.vehicles.filter(v => v.status === 'Inside Campus').length;
    const exitedCount = state.vehicles.filter(v => v.status === 'Exited').length;
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

    if (attentionCountBadge) {
      attentionCountBadge.textContent = `${activeIncidents.length} Active`;
      if (activeIncidents.length > 0) {
        attentionCountBadge.className = "text-[10px] px-1.5 py-0.5 rounded font-bold bg-rose-50 text-rose-700 border border-rose-200";
      } else {
        attentionCountBadge.className = "text-[10px] px-1.5 py-0.5 rounded font-bold bg-slate-100 text-slate-600 border border-slate-200";
      }
    }

    if (activeIncidents.length === 0) {
      attentionPanelContent.innerHTML = `
        <div class="h-full min-h-[110px] flex items-center justify-center p-3 rounded-lg border border-dashed border-slate-200 bg-slate-50/70 text-center">
          <div>
            <div class="w-6 h-6 rounded-full bg-emerald-100 text-emerald-700 mx-auto flex items-center justify-center font-bold text-xs mb-1.5">
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
      card.className = 'p-2.5 rounded-r-lg border-y border-r border-rose-200 border-l-4 border-l-rose-600 bg-rose-50/40 hover:bg-rose-50/70 transition-colors';

      card.innerHTML = `
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="font-mono font-bold text-xs bg-white text-slate-900 px-1.5 py-0.5 rounded border border-slate-200 shadow-xs">${escapeHtml(inc.plateNumber)}</span>
            <span class="px-1.5 py-0.2 rounded text-[10px] font-bold bg-rose-100 text-rose-800 border border-rose-200">HELD AT GATE</span>
          </div>
          <span class="text-[11px] font-mono text-slate-500">${escapeHtml(inc.timestamp.replace('Today, ', ''))}</span>
        </div>
        <div class="text-xs font-semibold text-rose-900 mt-1">${escapeHtml(inc.reason)}</div>
        <div class="grid grid-cols-2 gap-2 mt-1 text-[11px] text-slate-600">
          <div>Operator: <span class="font-medium text-slate-800">${escapeHtml(inc.driverName)}</span></div>
          <div>Owner: <span class="font-medium text-slate-800">${escapeHtml(inc.ownerName)}</span></div>
        </div>
        <div class="mt-2 flex items-center justify-between pt-1.5 border-t border-rose-200/60">
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

  // 3.6 Overall Dashboard Render
  function renderDashboard() {
    updateCounts();
    renderActivityTrendChart();
    renderGateStatusChart();
    renderFleetTypesChart();
    renderAttentionPanel();

    if (!dashboardActivityBody) return;
    dashboardActivityBody.innerHTML = '';

    const recentLogs = state.auditLogs.slice(0, 6);

    if (recentLogs.length === 0) {
      dashboardActivityBody.innerHTML = `
        <tr>
          <td colspan="7" class="py-8 text-center text-slate-400 text-xs">
            No gate passage records logged today.
          </td>
        </tr>
      `;
      return;
    }

    recentLogs.forEach(log => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50 transition-colors';

      let statusBadge = 'bg-emerald-50 text-emerald-700 border border-emerald-200';
      let statusText = 'Inside';

      if (log.status === 'Exited') {
        statusBadge = 'bg-slate-100 text-slate-600 border border-slate-200';
        statusText = 'Exited';
      } else if (log.status === 'Blocked / Alert') {
        statusBadge = 'bg-rose-50 text-rose-700 border border-rose-200 font-bold';
        statusText = 'Flagged';
      }

      tr.innerHTML = `
        <td class="py-2.5 px-4">
          <span class="px-2 py-0.5 rounded text-[11px] font-medium ${statusBadge}">
            ${statusText}
          </span>
        </td>
        <td class="py-2.5 px-4 font-mono font-bold text-slate-900">
          ${escapeHtml(log.plateNumber)}
        </td>
        <td class="py-2.5 px-4 text-slate-700">
          ${escapeHtml(log.driverName)}
          <span class="text-slate-400 text-[11px]">(${escapeHtml(log.driverRelationship || 'Self')})</span>
        </td>
        <td class="py-2.5 px-4 text-slate-600">
          ${escapeHtml(log.ownerName)}
        </td>
        <td class="py-2.5 px-4 text-slate-600">
          ${escapeHtml(log.gatePoint)}
        </td>
        <td class="py-2.5 px-4 text-right font-mono text-slate-500">
          ${escapeHtml(log.timestamp.replace('Today, ', ''))}
        </td>
        <td class="py-2.5 px-4 text-right">
          <button type="button" class="inspect-log-btn px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-ncst-navy shadow-xs transition-colors" data-id="${escapeHtml(log.id)}">
            Inspect
          </button>
        </td>
      `;

      tr.querySelector('.inspect-log-btn').addEventListener('click', () => {
        openAuditDrawer(log);
      });

      dashboardActivityBody.appendChild(tr);
    });
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
        v.plateNumber.toLowerCase().includes(q) ||
        v.ownerName.toLowerCase().includes(q) ||
        v.ownerIdNumber.toLowerCase().includes(q) ||
        v.makeModelColor.toLowerCase().includes(q) ||
        formatPassId(v).toLowerCase().includes(q) ||
        (v.qrPassCode && v.qrPassCode.toLowerCase().includes(q));

      const matchesRole = state.vehicleFilter.role === 'All' || v.ownerRole === state.vehicleFilter.role;

      let matchesCategory = true;
      if (state.vehicleFilter.category !== 'All') {
        matchesCategory = v.vehicleType.toLowerCase().includes(state.vehicleFilter.category.toLowerCase());
      }

      const matchesStatus = state.vehicleFilter.status === 'All' || v.registrationStatus === state.vehicleFilter.status;

      return matchesSearch && matchesRole && matchesCategory && matchesStatus;
    });

    if (filtered.length === 0) {
      vehiclesTableBody.innerHTML = `
        <tr>
          <td colspan="7" class="py-12 text-center text-slate-400 text-xs">
            <div class="font-medium text-slate-600">No vehicles match current filters.</div>
            <div class="text-[11px] text-slate-400 mt-1">Try clearing search terms or selecting 'All Roles'.</div>
            <button type="button" id="emptyResetVehiclesBtn" class="mt-3 px-3 py-1.5 rounded-md border border-slate-300 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs transition-colors inline-block">
              Clear All Filters
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
          state.vehicleFilter.status = 'All';
          if (vehicleSearchInput) vehicleSearchInput.value = '';
          if (vehicleRoleFilter) vehicleRoleFilter.value = 'All';
          if (vehicleCategoryFilter) vehicleCategoryFilter.value = 'All';
          if (vehicleStatusFilter) vehicleStatusFilter.value = 'All';
          renderVehiclesTable();
        });
      }
      return;
    }

    filtered.forEach(vehicle => {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-slate-50 transition-colors';

      // Campus custody indicator
      let custodyDot = 'bg-slate-400';
      let custodyLabel = 'Outside';
      const vStatus = (vehicle.status || '').toLowerCase();
      if (vStatus.includes('inside')) {
        custodyDot = 'bg-emerald-500';
        custodyLabel = 'Inside';
      } else if (vStatus.includes('block') || vStatus.includes('alert') || vStatus.includes('hold')) {
        custodyDot = 'bg-rose-600';
        custodyLabel = 'Blocked';
      } else {
        custodyDot = 'bg-slate-400';
        custodyLabel = 'Outside';
      }

      // Registration pass status badge
      const regStatusBadge = vehicle.registrationStatus === 'Active'
        ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
        : 'bg-amber-50 text-amber-700 border-amber-200';

      const driversCount = vehicle.authorizedDrivers ? vehicle.authorizedDrivers.length : 0;

      tr.innerHTML = `
        <td class="py-2.5 px-4">
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full ${custodyDot}" title="${custodyLabel}"></span>
            <span class="px-2 py-0.5 rounded text-[11px] font-medium border ${regStatusBadge}">
              ${escapeHtml(vehicle.registrationStatus || 'Active')}
            </span>
          </div>
        </td>
        <td class="py-2.5 px-4">
          <div class="font-mono font-bold text-slate-900">${escapeHtml(vehicle.plateNumber)}</div>
          <div class="inline-flex items-center gap-1.5 text-[11px] text-slate-500 font-mono mt-0.5">
            <span class="px-1.5 py-0.2 rounded bg-slate-100 border border-slate-200 text-slate-600 text-[10px] font-semibold">PASS</span>
            <span>${escapeHtml(formatPassId(vehicle))}</span>
          </div>
        </td>
        <td class="py-2.5 px-4">
          <div class="text-slate-800 font-medium">${escapeHtml(vehicle.makeModelColor)}</div>
          <div class="text-[11px] text-slate-500">${escapeHtml(vehicle.vehicleType)} • Sticker ${escapeHtml(vehicle.stickerYear || '2026')}</div>
        </td>
        <td class="py-2.5 px-4">
          <div class="text-slate-800 font-medium">${escapeHtml(vehicle.ownerName)}</div>
          <div class="text-[11px] text-slate-400 font-mono">${escapeHtml(vehicle.ownerIdNumber)}</div>
        </td>
        <td class="py-2.5 px-4">
          <span class="inline-block px-2 py-0.5 rounded text-[11px] font-medium bg-slate-100 text-slate-700">
            ${escapeHtml(vehicle.ownerRole)}
          </span>
          <div class="text-[11px] text-slate-500 truncate max-w-[140px]" title="${escapeHtml(vehicle.department)}">
            ${escapeHtml(vehicle.department)}
          </div>
        </td>
        <td class="py-2.5 px-4">
          <span class="text-xs font-semibold text-slate-700">${driversCount}</span>
          <span class="text-[11px] text-slate-500">${driversCount === 1 ? 'driver' : 'drivers'}</span>
        </td>
        <td class="py-2.5 px-4 text-right">
          <div class="flex items-center justify-end gap-1.5">
            <button type="button" class="print-row-btn px-2 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs transition-colors flex items-center gap-1 cursor-pointer" title="Print Gate Pass Permit">
              <svg class="w-3.5 h-3.5 text-slate-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <polyline points="6 9 6 2 18 2 18 9"></polyline>
                <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"></path>
                <rect x="6" y="14" width="12" height="8"></rect>
              </svg>
              <span>Print</span>
            </button>
            <button type="button" class="zoom-qr-row-btn px-2 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs transition-colors flex items-center gap-1 cursor-pointer" title="Zoom QR Code for mobile scanning">
              <svg class="w-3.5 h-3.5 text-ncst-navy" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="3" y="3" width="7" height="7"></rect>
                <rect x="14" y="3" width="7" height="7"></rect>
                <rect x="14" y="14" width="7" height="7"></rect>
                <rect x="3" y="14" width="7" height="7"></rect>
              </svg>
              <span>QR</span>
            </button>
            <button type="button" class="inspect-btn px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-ncst-navy shadow-xs transition-colors cursor-pointer" title="Inspect vehicle dossier">
              Inspect
            </button>
            <button type="button" class="edit-btn px-2.5 py-1 rounded border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 shadow-xs transition-colors cursor-pointer" title="Edit vehicle record">
              Edit
            </button>
            <button type="button" class="toggle-status-btn px-2.5 py-1 rounded border text-xs font-semibold shadow-xs transition-colors cursor-pointer ${vehicle.registrationStatus === 'Active' ? 'border-amber-200 bg-amber-50/60 hover:bg-amber-100 text-amber-800' : 'border-emerald-200 bg-emerald-50/60 hover:bg-emerald-100 text-emerald-800'}" title="Toggle registration status">
              ${vehicle.registrationStatus === 'Active' ? 'Suspend' : 'Activate'}
            </button>
          </div>
        </td>
      `;

      // Event Listeners for Row Actions
      tr.querySelector('.print-row-btn').addEventListener('click', () => printVehiclePass(vehicle));
      tr.querySelector('.zoom-qr-row-btn').addEventListener('click', () => {
        const qrData = (vehicle.qrPassCode && vehicle.qrPassCode.startsWith('{')) ? vehicle.qrPassCode : JSON.stringify({
          ownerStudentId: vehicle.ownerIdNumber,
          ownerFullName: vehicle.ownerName,
          plateNumber: vehicle.plateNumber,
          stickerYear: vehicle.stickerYear || '2026',
          authorizedDrivers: (vehicle.authorizedDrivers && vehicle.authorizedDrivers.length > 0) ? vehicle.authorizedDrivers.map(d => ({
            fullName: d.fullName,
            relationship: d.relationship,
            licenseNo: d.licenseNo
          })) : [{
            fullName: vehicle.ownerName,
            relationship: 'Self (Owner)',
            licenseNo: 'N/A'
          }],
          vehicleCategory: vehicle.vehicleType,
          makeModelColor: vehicle.makeModelColor
        });
        openZoomQrModal({
          payload: qrData,
          plate: vehicle.plateNumber,
          owner: vehicle.ownerName,
          year: vehicle.stickerYear || '2026',
          category: vehicle.vehicleType || 'Vehicle'
        });
      });
      tr.querySelector('.inspect-btn').addEventListener('click', () => openVehicleDrawer(vehicle));
      tr.querySelector('.edit-btn').addEventListener('click', () => openEditModal(vehicle));
      tr.querySelector('.toggle-status-btn').addEventListener('click', () => toggleVehicleRegistrationStatus(vehicle));

      vehiclesTableBody.appendChild(tr);
    });
  }

  function toggleVehicleRegistrationStatus(vehicle) {
    const nextStatus = vehicle.registrationStatus === 'Active' ? 'Suspended' : 'Active';
    const actionDesc = nextStatus === 'Active' ? 'activated' : 'suspended';

    if (confirm(`Are you sure you want to change pass status of ${vehicle.plateNumber} to ${nextStatus}?`)) {
      vehicle.registrationStatus = nextStatus;
      renderVehiclesTable();
      updateCounts();
      renderDashboard();
      showToast(`Pass for ${vehicle.plateNumber} is now ${actionDesc}.`);

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
      state.vehicleFilter.status = 'All';
      if (vehicleSearchInput) vehicleSearchInput.value = '';
      if (vehicleRoleFilter) vehicleRoleFilter.value = 'All';
      if (vehicleCategoryFilter) vehicleCategoryFilter.value = 'All';
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
            <div class="font-medium text-emerald-600">No active security stops or flagged vehicles.</div>
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
        ? 'bg-rose-50 text-rose-700 border-rose-200' 
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
          <div class="text-rose-700 font-medium">${escapeHtml(inc.driverName)}</div>
          <div class="text-[11px] text-slate-500">Owner: ${escapeHtml(inc.ownerName)}</div>
        </td>
        <td class="py-2.5 px-4">
          <span class="inline-block px-2 py-0.5 rounded text-[11px] font-medium bg-rose-50 text-rose-700 border border-rose-200">
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
              <button type="button" class="resolve-btn px-2.5 py-1 rounded text-xs font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 hover:bg-emerald-100 shadow-xs transition-colors">
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

  function resolveIncident(inc) {
    const resolutionNotes = prompt(`Enter resolution statement for ${inc.plateNumber} (${inc.caseNumber}):`, "Identity and authorization confirmed with registered owner.");
    if (resolutionNotes === null) return;

    inc.status = 'Resolved';
    inc.notes += ` [Resolved by Admin: ${resolutionNotes}]`;

    // Unblock vehicle
    const vehicle = state.vehicles.find(v => v.plateNumber === inc.plateNumber);
    if (vehicle) {
      vehicle.status = 'Inside Campus';
      if (vehicle.registrationStatus === 'Suspended') {
        vehicle.registrationStatus = 'Active';
      }
    }

    // Add audit entry
    state.auditLogs.unshift({
      id: `log-${Date.now()}`,
      timestamp: `Today, ${formatCurrentTime()}`,
      plateNumber: inc.plateNumber,
      vehicleType: inc.vehicleType,
      ownerName: inc.ownerName,
      driverName: inc.driverName,
      driverRelationship: "Cleared by Security Admin",
      gatePoint: inc.gatePoint,
      action: "Security Stop Cleared",
      status: "Inside Campus",
      guardName: "Security Administrator",
      notes: `Incident ${inc.caseNumber} resolved: ${resolutionNotes}`
    });

    showToast(`Vehicle ${inc.plateNumber} unblocked and gate hold cleared.`);
    renderIncidentsTable();
    renderDashboard();
    renderVehiclesTable();
    renderFullAuditTable();
    closeDrawer();

    if (window.ApiClient && inc.id) {
      ApiClient.resolveIncident(inc.id).catch(err => {
        console.warn('[App] API incident resolution notice:', err.message);
      });
    }
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
      tr.className = 'odd:bg-white even:bg-slate-50/75 hover:bg-sky-50/40 transition-colors border-b border-slate-200 text-xs text-slate-800';

      let statusBadge = 'bg-emerald-100 text-emerald-900 border-emerald-300 font-semibold';
      let statusDot = 'bg-emerald-600';
      let statusText = 'Inside';

      if (log.status === 'Exited') {
        statusBadge = 'bg-slate-200 text-slate-800 border-slate-300 font-medium';
        statusDot = 'bg-slate-500';
        statusText = 'Exited';
      } else if (log.status === 'Blocked / Alert') {
        statusBadge = 'bg-rose-100 text-rose-900 border-rose-300 font-bold';
        statusDot = 'bg-rose-600';
        statusText = 'Hold / Blocked';
      }

      // Format event action styling
      let actionColor = 'text-slate-800 font-medium';
      const actLower = (log.action || '').toLowerCase();
      if (actLower.includes('entry') || actLower.includes('ingress') || actLower.includes('approved')) {
        actionColor = 'text-emerald-800 font-semibold';
      } else if (actLower.includes('exit') || actLower.includes('egress')) {
        actionColor = 'text-slate-700 font-medium';
      } else if (actLower.includes('flag') || actLower.includes('held') || actLower.includes('blocked') || actLower.includes('alert')) {
        actionColor = 'text-rose-800 font-bold';
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
          ${escapeHtml(log.timestamp.replace('Today, ', ''))}
        </td>
        <td class="py-2.5 px-4 text-right whitespace-nowrap">
          <button type="button" class="audit-details-btn px-2.5 py-1 rounded border border-slate-300 bg-white hover:bg-slate-100 hover:text-ncst-navy text-xs font-semibold text-slate-800 shadow-2xs transition-all cursor-pointer">
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

    const qrData = (v.qrPassCode && v.qrPassCode.startsWith('{')) ? v.qrPassCode : JSON.stringify({
      ownerStudentId: v.ownerIdNumber,
      ownerFullName: v.ownerName,
      plateNumber: v.plateNumber,
      stickerYear: v.stickerYear || '2026',
      authorizedDrivers: (v.authorizedDrivers && v.authorizedDrivers.length > 0) ? v.authorizedDrivers.map(d => ({
        fullName: d.fullName,
        relationship: d.relationship,
        licenseNo: d.licenseNo
      })) : [{
        fullName: v.ownerName,
        relationship: 'Self (Owner)',
        licenseNo: 'N/A'
      }],
      vehicleCategory: v.vehicleType,
      makeModelColor: v.makeModelColor
    });

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
            <span class="px-3 py-1 rounded text-xs font-extrabold border ${v.registrationStatus === 'Active' ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-rose-50 text-rose-700 border-rose-200'}">
              ${escapeHtml(v.registrationStatus || 'Active')}
            </span>
            <span class="px-2.5 py-0.5 rounded text-[11px] font-bold bg-amber-50 text-amber-900 border border-amber-300 font-mono">
              Sticker ${escapeHtml(v.stickerYear || '2026')}
            </span>
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
                <span class="inline-block mt-1 px-2 py-0.5 rounded text-[10px] font-bold bg-blue-50 text-ncst-navy border border-blue-200">
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
                <span class="inline-block mt-1 px-2 py-0.5 rounded text-[10px] font-bold ${v.status === 'Inside' ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' : 'bg-slate-100 text-slate-600 border border-slate-200'}">
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
        <button id="drawerEditBtn" class="px-4 py-2 rounded-md bg-ncst-navy hover:bg-ncst-navyDark text-white text-xs font-bold shadow-xs flex items-center gap-1.5 transition-colors cursor-pointer">
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
      const qrData = (v.qrPassCode && v.qrPassCode.startsWith('{')) ? v.qrPassCode : JSON.stringify({
        ownerStudentId: v.ownerIdNumber,
        ownerFullName: v.ownerName,
        plateNumber: v.plateNumber,
        stickerYear: v.stickerYear || '2026',
        authorizedDrivers: (v.authorizedDrivers && v.authorizedDrivers.length > 0) ? v.authorizedDrivers.map(d => ({
          fullName: d.fullName,
          relationship: d.relationship,
          licenseNo: d.licenseNo
        })) : [{
          fullName: v.ownerName,
          relationship: 'Self (Owner)',
          licenseNo: 'N/A'
        }],
        vehicleCategory: v.vehicleType,
        makeModelColor: v.makeModelColor
      });
      try {
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
        <div class="p-4 rounded-lg border ${isHeld ? 'bg-rose-50 border-rose-200' : 'bg-slate-50 border-slate-200'}">
          <div class="flex items-center justify-between">
            <div class="text-xs font-bold ${isHeld ? 'text-rose-700' : 'text-slate-600'} uppercase">Security Incident Report</div>
            <span class="px-2 py-0.5 rounded text-xs font-bold ${isHeld ? 'bg-rose-100 text-rose-800' : 'bg-slate-200 text-slate-700'}">${escapeHtml(inc.status)}</span>
          </div>
          <div class="text-xl font-mono font-bold text-slate-900 mt-2">${escapeHtml(inc.plateNumber)}</div>
          <div class="text-xs font-semibold text-rose-700 mt-1 font-mono">${escapeHtml(inc.caseNumber)} • Stop Reason: ${escapeHtml(inc.reason)}</div>
        </div>

        <div>
          <h4 class="text-xs font-bold text-slate-900 uppercase tracking-wider mb-2">Incident Particulars</h4>
          <div class="grid grid-cols-2 gap-3 text-xs bg-white p-3 rounded border border-slate-200">
            <div>
              <span class="text-slate-400 block text-[11px]">Unregistered Driver</span>
              <span class="font-bold text-rose-700">${escapeHtml(inc.driverName)}</span>
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
        <button id="drawerResolveBtn" class="px-3 py-1.5 rounded-md bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold">
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

    if (isHeld) {
      const resolveBtn = drawerFooter.querySelector('#drawerResolveBtn');
      if (resolveBtn) {
        resolveBtn.addEventListener('click', () => resolveIncident(inc));
      }
    }
  }

  // Open Drawer for Audit Event Inspection
  function openAuditDrawer(log) {
    const html = `
      <div class="space-y-4 text-xs">
        <div class="bg-slate-50 p-4 rounded-lg border border-slate-200 flex items-center justify-between">
          <div>
            <span class="text-[11px] text-slate-400 font-mono block">AUDIT LOG ID</span>
            <span class="text-base font-bold font-mono text-slate-900">${escapeHtml(log.id)}</span>
          </div>
          <span class="px-2 py-0.5 rounded text-xs font-bold ${log.status === 'Blocked / Alert' ? 'bg-rose-50 text-rose-700 border border-rose-200' : 'bg-emerald-50 text-emerald-700 border border-emerald-200'}">
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
          </div>
        </div>

        <div>
          <span class="text-slate-500 block text-[11px] font-bold uppercase mb-1">Passage Verification Notes</span>
          <div class="p-3 bg-slate-50 rounded border border-slate-200 text-slate-700 leading-relaxed">
            ${escapeHtml(log.notes || 'Routine gate check completed with verified custody credentials.')}
          </div>
        </div>
      </div>
    `;

    openDrawer(`Gate Passage Audit — ${log.plateNumber}`, log.timestamp, html);
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
          <button type="button" class="remove-edit-driver-btn text-[11px] text-rose-500 hover:text-rose-700 font-semibold flex items-center gap-1 cursor-pointer">
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
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Full Name <span class="text-rose-500">*</span></label>
          <input type="text" class="edit-driver-name w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="Driver name" value="${escapeHtml(driverData.fullName || '')}" required>
        </div>
        <div>
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Relationship to Owner <span class="text-rose-500">*</span></label>
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
          <label class="block text-[11px] font-medium text-slate-600 mb-1">Driver's License No. <span class="text-rose-500">*</span></label>
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
    if (editVehicleCategory) editVehicleCategory.value = v.vehicleType || '4-Wheel';
    if (editPlateNumber) editPlateNumber.value = v.plateNumber || '';
    if (editMakeModel) editMakeModel.value = v.makeModelColor || '';
    if (editStickerYear) editStickerYear.value = v.stickerYear || '2026';
    if (editRegStatus) editRegStatus.value = v.registrationStatus || 'Active';
    if (editCampusStatus) editCampusStatus.value = v.status || 'Outside';

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
        compressImage(file, 640, 0.8, (compressed) => {
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
        compressImage(file, 640, 0.8, (compressed) => {
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
      const v = state.vehicles.find(item => item.id === targetId);
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
      const campusStatus = editCampusStatus ? editCampusStatus.value : (v.status || 'Outside');

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

      const updatedQrPayload = JSON.stringify({
        ownerStudentId: ownerIdNumber,
        ownerFullName: ownerFullName,
        plateNumber: plateNumber,
        stickerYear: stickerYear,
        authorizedDrivers: authorizedDrivers.map(d => ({
          fullName: d.fullName,
          relationship: d.relationship,
          licenseNo: d.licenseNo
        })),
        vehicleCategory: vehicleCategory,
        makeModelColor: makeModelColor
      });

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
      v.registrationStatus = registrationStatus;
      v.registration_status = registrationStatus;
      v.status = campusStatus;
      v.ownerPhoto = editOwnerPhotoDataUrl;
      v.owner_photo = editOwnerPhotoDataUrl;
      v.ownerPhotoUrl = editOwnerPhotoDataUrl;
      v.vehiclePhoto = editVehiclePhotoDataUrl;
      v.vehicle_photo = editVehiclePhotoDataUrl;
      v.authorizedDrivers = authorizedDrivers;
      v.qrPassCode = updatedQrPayload;
      v.qr_pass_code = updatedQrPayload;

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
          registrationStatus: v.registrationStatus,
          status: v.status,
          ownerPhoto: v.ownerPhoto,
          vehiclePhoto: v.vehiclePhoto,
          qrPassCode: v.qrPassCode,
          authorizedDrivers: v.authorizedDrivers
        }).then(() => {
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
        plateInput.classList.add('border-rose-400');
      } else {
        plateValidationMsg.classList.add('hidden');
        plateInput.classList.remove('border-rose-400');
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
          <button type="button" class="remove-driver-btn text-xs font-medium text-rose-600 hover:underline">
            Remove
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Full Name <span class="text-rose-500">*</span></label>
            <input type="text" class="driver-name w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="Driver name" required>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Relationship to Owner <span class="text-rose-500">*</span></label>
            <select class="driver-rel w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" required>
              <option value="Spouse">Spouse</option>
              <option value="Parent">Parent</option>
              <option value="Child">Child</option>
              <option value="Sibling">Sibling</option>
              <option value="Designated Driver" selected>Designated Driver</option>
            </select>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Driver's License No. <span class="text-rose-500">*</span></label>
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
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Full Name <span class="text-rose-500">*</span></label>
            <input type="text" class="driver-name w-full px-2.5 py-1.5 rounded bg-white border border-slate-300 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-ncst-navy focus:border-ncst-navy" placeholder="Driver name" required>
          </div>

          <div>
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Relationship to Owner <span class="text-rose-500">*</span></label>
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
            <label class="block text-[11px] font-medium text-slate-600 mb-1">Driver's License No. <span class="text-rose-500">*</span></label>
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
  function compressImage(file, maxDimension = 640, quality = 0.8, callback) {
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
        compressImage(file, 640, 0.8, (compressedDataUrl) => {
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
        compressImage(file, 640, 0.8, (compressedDataUrl) => {
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

      const qrPayload = JSON.stringify({
        ownerStudentId: ownerIdNumber,
        ownerFullName: ownerFullName,
        plateNumber: plateNumber,
        stickerYear: stickerYear,
        authorizedDrivers: authorizedDrivers.map(d => ({
          fullName: d.fullName,
          relationship: d.relationship,
          licenseNo: d.licenseNo
        })),
        vehiclePicture: vehiclePhotoMicroDataUrl || (vehiclePhotoFileName ? vehiclePhotoFileName.textContent : null),
        vehicleCategory: vehicleCategory,
        makeModelColor: makeModelColor
      });

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
        qrPassCode: qrPayload,
        status: 'Outside',
        registrationStatus: 'Active',
        entryTime: null,
        gatePoint: '—',
        stickerYear,
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
          qrPassCode: qrPayload,
          stickerYear,
          ownerPhoto: ownerPhotoDataUrl,
          vehiclePhoto: vehiclePhotoDataUrl,
          authorizedDrivers
        }).then(res => {
          if (res && res.id) newVehicle.id = res.id;
          console.log('[App] Vehicle enrolled on backend:', res);
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
      plateInput.classList.remove('border-rose-400');

      // Prompt navigation
      setTimeout(() => {
        if (confirm(`Vehicle ${plateNumber} registered! Would you like to view it in the Vehicle Directory?`)) {
          switchView('vehiclesView');
        }
      }, 300);
    });
  }

  if (resetFormBtn) {
    resetFormBtn.addEventListener('click', () => {
      vehicleForm.reset();
      resetDriverFields();
      resetOwnerPhoto();
      resetVehiclePhoto();
      plateValidationMsg.classList.add('hidden');
      plateInput.classList.remove('border-rose-400');
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

    // Only necessary vehicle, driver, and pass information encoded into the QR code
    const payloadObj = {
      ownerStudentId: idNum,
      ownerFullName: owner,
      plateNumber: plate,
      stickerYear: year,
      authorizedDrivers: authorizedDriversList.map(d => ({
        fullName: d.fullName,
        relationship: d.relationship,
        licenseNo: d.licenseNo
      })),
      vehiclePicture: vehiclePhotoMicroDataUrl || (vehiclePhotoFileName && vehiclePhotoFileName.textContent ? vehiclePhotoFileName.textContent : null),
      vehicleCategory: category,
      makeModelColor: makeModel
    };

    let payloadString = JSON.stringify(payloadObj);

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
        if (payloadObj.vehiclePicture && payloadObj.vehiclePicture.startsWith('data:')) {
          payloadObj.vehiclePicture = vehiclePhotoFileName ? vehiclePhotoFileName.textContent : "vehicle_photo.jpg";
          payloadString = JSON.stringify(payloadObj);
          qrCodeInstance.clear();
          qrCodeInstance.makeCode(payloadString);
        }
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
     10. Utility Functions
     ========================================================================== */
  function showToast(message) {
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
  renderDashboard();
  renderVehiclesTable();
  renderIncidentsTable();
  renderFullAuditTable();
  generateQrPass(true);

  // Synchronize with InfinityFree MySQL Backend API
  async function loadInitialDataFromApi() {
    if (!window.ApiClient) return;
    try {
      const [vehicles, logs, incidents] = await Promise.all([
        ApiClient.getVehicles().catch(() => null),
        ApiClient.getLogs().catch(() => null),
        ApiClient.getIncidents().catch(() => null)
      ]);

      let hasUpdate = false;
      if (vehicles && Array.isArray(vehicles) && vehicles.length > 0) {
        state.vehicles = vehicles.map(v => normalizeVehicle(v));
        hasUpdate = true;
      }
      if (logs && Array.isArray(logs) && logs.length > 0) {
        state.auditLogs = logs;
        hasUpdate = true;
      }
      if (incidents && Array.isArray(incidents) && incidents.length > 0) {
        state.incidents = incidents;
        hasUpdate = true;
      }

      if (hasUpdate) {
        updateCounts();
        renderDashboard();
        renderVehiclesTable();
        renderIncidentsTable();
        renderFullAuditTable();
        console.log('[App] Synchronized state with InfinityFree backend.');
      }
    } catch (err) {
      console.warn('[App] Backend sync note:', err.message);
    }
  }

  loadInitialDataFromApi();
});
