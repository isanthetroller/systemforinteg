import 'package:flutter/material.dart';

import '../../../models/user_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../services/sync_queue_service.dart';
import '../../../theme/ncst_theme.dart';
import '../../auth/screens/login_screen.dart';
import '../../dashboard/widgets/audit_log_card.dart';
import '../../dashboard/widgets/dashboard_kpi_row.dart';
import '../../dashboard/widgets/quick_scan_banner.dart';
import '../../scanner/screens/qr_scanner_screen.dart';
import '../../visitor/screens/visitor_registration_screen.dart';
import '../widgets/handover_note_field.dart';
import '../widgets/shift_banner.dart';

class GuardShellScreen extends StatefulWidget {
  final GuardUser user;

  const GuardShellScreen({super.key, required this.user});

  @override
  State<GuardShellScreen> createState() => _GuardShellScreenState();
}

class _GuardShellScreenState extends State<GuardShellScreen> {
  late GuardUser _currentUser;
  int _selectedIndex = 0;
  bool _movementPending = false;

  // Shared Dashboard State
  late List<AuditLogEntry> _auditLogs;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final GateRepository _repository = const GateRepository();

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _auditLogs = List<AuditLogEntry>.from(_repository.getInitialAuditLogs());
    _fetchLiveLogs();
    ApiService.sessionError.addListener(_onSessionEnded);
    ApiService.currentSessionUser.addListener(_onSessionUpdated);
    SyncQueueService().lastSyncTimeNotifier.addListener(_onAutoSyncCompleted);
  }

  @override
  void dispose() {
    SyncQueueService().lastSyncTimeNotifier.removeListener(
      _onAutoSyncCompleted,
    );
    ApiService.sessionError.removeListener(_onSessionEnded);
    ApiService.currentSessionUser.removeListener(_onSessionUpdated);
    super.dispose();
  }

  void _onSessionEnded() {
    final message = ApiService.sessionError.value;
    if (!mounted || message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AuthService().userNotifier.value = null;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
  }

  void _onSessionUpdated() {
    final user = ApiService.currentSessionUser.value;
    if (!mounted || user == null) return;
    setState(() {
      _currentUser = GuardUser.fromJson(user);
    });
  }

  void _onAutoSyncCompleted() {
    if (mounted) {
      final cached = LocalCacheService.getCachedLogs();
      {
        setState(() {
          _auditLogs = cached;
        });
      }
    }
  }

  Future<void> _fetchLiveLogs() async {
    // Just signed in: load the server's logs now instead of showing sample data until the next 30-second refresh
    SyncQueueService().requestRefresh();
    await SyncQueueService().processQueue();
    final serverLogs = LocalCacheService.getCachedLogs();
    if (mounted) {
      setState(() {
        _auditLogs = serverLogs;
      });
    }
  }

  void _confirmLogout() {
    if (_movementPending) return;
    var handoverNote = '';
    final onDuty = ShiftBanner.onDuty.value;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out of Terminal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to end your security guard shift and sign out?',
            ),
            if (onDuty) ...[
              const SizedBox(height: 12),
              HandoverNoteField(
                key: const Key('signOutHandoverField'),
                lines: 3,
                label: 'Handover note for the next guard (optional)',
                onChanged: (v) => handoverNote = v,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final note = handoverNote.trim();
              Navigator.of(ctx).pop();
              if (onDuty) {
                await ApiService.endShift(note);
                ShiftBanner.onDuty.value = false;
              }
              await AuthService().logout();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: NcstColors.crimson,
              foregroundColor: NcstColors.white,
            ),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
  }

  int get _insideCount {
    final Map<String, AuditLogEntry> latestByPlate = {};
    for (final log in _auditLogs) {
      final key = log.plateNumber.toUpperCase().trim();
      if (!latestByPlate.containsKey(key)) {
        latestByPlate[key] = log;
      }
    }
    return latestByPlate.values.where((l) => l.isInside).length;
  }

  int get _blockedTodayCount => _auditLogs.where((l) => l.isBlocked).length;
  int get _totalEntriesToday => _auditLogs
      .where((l) => l.isInside || l.action.toLowerCase().contains('entry'))
      .length;

  List<AuditLogEntry> get _filteredLogs {
    return _auditLogs.where((log) {
      final matchesSearch =
          log.plateNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log.ownerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log.driverName.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (_selectedFilter == 'Inside') return log.isInside;
      if (_selectedFilter == 'Exited') return log.isExited;
      if (_selectedFilter == 'Blocked') return log.isBlocked;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isEntrance = _currentUser.isEntranceGuard;

    return PopScope(
      canPop: !_movementPending,
      child: Scaffold(
        backgroundColor: _selectedIndex == 1
            ? Colors.black
            : NcstColors.slate100,
        appBar: _buildAppBar(isEntrance),
        body: _buildBody(isEntrance),
        bottomNavigationBar: _buildBottomNav(isEntrance),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isEntrance) {
    return AppBar(
      backgroundColor: NcstColors.navy,
      foregroundColor: NcstColors.white,
      elevation: 0,
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: NcstColors.gold, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NCST SECUREPARK',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isEntrance ? NcstColors.green : NcstColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _currentUser.fullName,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        // The checkpoint comes from the authenticated account, not a local role switch.
        PopupMenuButton<String>(
          tooltip: 'Guard account',
          icon: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'IN / OUT',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
          onSelected: (val) {
            if (val == 'logout') _confirmLogout();
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: const [
                  Icon(
                    Icons.power_settings_new,
                    size: 18,
                    color: NcstColors.crimson,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Sign Out of Terminal',
                    style: TextStyle(color: NcstColors.crimson),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody(bool isEntrance) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardFeed(isEntrance);
      case 1:
        return QrScannerScreen(
          isEmbedded: true,
          automaticMovement: true,
          currentGuard: _currentUser,
          onMovementPendingChanged: (pending) {
            if (mounted) setState(() => _movementPending = pending);
          },
          repository: _repository,
          onDecision: (entry) {
            setState(() {
              _auditLogs.removeWhere((l) => l.id == entry.id);
              _auditLogs.insert(0, entry);
              _selectedIndex = 0;
            });
            _fetchLiveLogs();
          },
          onReturnToDashboard: () {
            setState(() => _selectedIndex = 0);
            _fetchLiveLogs();
          },
          onNavigateToVisitorRegistration: () =>
              setState(() => _selectedIndex = 2),
        );
      case 2:
        return VisitorRegistrationScreen(
          currentGuard: _currentUser,
          onReturnToDashboard: () {
            setState(() => _selectedIndex = 0);
            _fetchLiveLogs();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDashboardFeed(bool isEntrance) {
    return RefreshIndicator(
      onRefresh: _fetchLiveLogs,
      color: NcstColors.navy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Who is on duty at this gate, and the previous guard's handover note
            ShiftBanner(assignedGate: _currentUser.assignedGate),

            // KPI Counters
            DashboardKpiRow(
              insideCount: _insideCount,
              totalEntriesToday: _totalEntriesToday,
              blockedTodayCount: _blockedTodayCount,
            ),
            const SizedBox(height: 12),

            // Primary Call to Action Banner
            QuickScanBanner(
              onOpenScan: () {
                setState(() {
                  _selectedIndex = 1; // Open scanner
                });
              },
            ),
            const SizedBox(height: 14),

            // Audit Log Card (with integrated search, filter, and item rows)
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
    );
  }

  Widget _buildBottomNav(bool isEntrance) {
    return Container(
      decoration: const BoxDecoration(
        color: NcstColors.white,
        border: Border(top: BorderSide(color: NcstColors.slate200)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _movementPending
            ? null
            : (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
        backgroundColor: NcstColors.white,
        selectedItemColor: NcstColors.green,
        unselectedItemColor: NcstColors.slate500,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan IN / OUT',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_add_alt_1_outlined),
            activeIcon: Icon(Icons.person_add_alt_1),
            label: 'Visitor',
          ),
        ],
      ),
    );
  }
}
