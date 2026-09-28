import 'package:flutter/material.dart';
import '../../../models/vehicle_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import '../../scanner/screens/qr_scanner_screen.dart';
import '../widgets/audit_log_card.dart';
import '../widgets/bottom_scan_bar.dart';
import '../widgets/dashboard_app_bar.dart';
import '../widgets/dashboard_kpi_row.dart';
import '../widgets/quick_scan_banner.dart';

class DashboardScreen extends StatefulWidget {
  final GateRepository repository;

  const DashboardScreen({
    super.key,
    this.repository = const GateRepository(),
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late List<AuditLogEntry> _auditLogs;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  int _selectedPageIndex = 0; // 0 = Dashboard & Entry Logs, 1 = 2nd Page (Camera Scanner)
  VehicleRecord? _pendingScanVehicle;

  @override
  void initState() {
    super.initState();
    _auditLogs = List<AuditLogEntry>.from(widget.repository.getInitialAuditLogs());
    _fetchLiveLogs();
  }

  Future<void> _fetchLiveLogs() async {
    final serverLogs = await ApiService.fetchLogs();
    if (mounted && serverLogs.isNotEmpty) {
      setState(() {
        _auditLogs = serverLogs;
      });
    }
  }

  int get _insideCount => _auditLogs.where((l) => l.isInside).length;
  int get _blockedTodayCount =>
      _auditLogs.where((l) => l.status == GateStatus.blocked).length;
  int get _totalEntriesToday => _auditLogs.length;

  List<AuditLogEntry> get _filteredLogs {
    return _auditLogs.where((log) {
      final matchesSearch =
          log.plateNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log.ownerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log.driverName.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (_selectedFilter == 'Inside') return log.isInside;
      if (_selectedFilter == 'Blocked') return log.status == GateStatus.blocked;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _selectedPageIndex == 1 ? Colors.black : NcstColors.slate100,
      body: _selectedPageIndex == 0
          ? _buildDashboardView()
          : QrScannerScreen(
              isEmbedded: true,
              repository: widget.repository,
              initialVehicle: _pendingScanVehicle,
              onDecision: (newEntry) {
                setState(() {
                  _pendingScanVehicle = null;
                  _auditLogs.insert(0, newEntry);
                  _selectedPageIndex = 0;
                });
                _fetchLiveLogs();
              },
              onReturnToDashboard: () {
                setState(() {
                  _pendingScanVehicle = null;
                  _selectedPageIndex = 0;
                });
                _fetchLiveLogs();
              },
            ),
      bottomNavigationBar: BottomScanBar(
        selectedIndex: _selectedPageIndex,
        onTabSelected: (index) {
          setState(() {
            _selectedPageIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildDashboardView() {
    return Column(
      children: [
        const DashboardAppBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchLiveLogs,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. KPI Metric Badges
                    DashboardKpiRow(
                      insideCount: _insideCount,
                      totalEntriesToday: _totalEntriesToday,
                      blockedTodayCount: _blockedTodayCount,
                    ),
                    const SizedBox(height: 16),

                    // 2. Quick Camera Scan Banner
                    QuickScanBanner(
                      onOpenScan: () {
                        setState(() {
                          _pendingScanVehicle = null;
                          _selectedPageIndex = 1;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // 3. Audit Log Section
                      AuditLogCard(
                        logs: _filteredLogs,
                        selectedFilter: _selectedFilter,
                        onFilterChanged: (filter) {
                          setState(() {
                            _selectedFilter = filter;
                          });
                        },
                        searchQuery: _searchQuery,
                        onSearchChanged: (query) {
                          setState(() {
                            _searchQuery = query;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
