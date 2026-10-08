import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/utils/scanner_controller_safe.dart';
import '../../../models/scanned_visitor_pass.dart';
import '../../../models/user_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../models/visitor_pass_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../repositories/visitor_repository.dart';
import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import '../dialogs/block_reason_dialog.dart';
import '../dialogs/manual_qr_dialog.dart';
import '../widgets/authorized_drivers_card.dart';
import '../widgets/bottom_decision_bar.dart';
import '../widgets/camera_viewfinder.dart';
import '../widgets/scan_rejection_view.dart';
import '../widgets/scan_notice_strip.dart';
import '../widgets/scanned_person_card.dart';
import '../widgets/scanned_visitor_card.dart';

enum ExitVerificationStatus {
  valid,       // Cleared for exit
  blocked,     // Security hold / Blacklisted
  expired,     // Exceeded permitted campus stay duration
  alreadyUsed, // Pass already checked out previously
  invalid,     // Unrecognized / Not found
}

class ExitScannerScreen extends StatefulWidget {
  final GuardUser currentGuard;
  final Function(AuditLogEntry)? onDecision;
  final VoidCallback? onReturnToDashboard;
  final bool isEmbedded;

  const ExitScannerScreen({
    super.key,
    required this.currentGuard,
    this.onDecision,
    this.onReturnToDashboard,
    this.isEmbedded = true,
  });

  @override
  State<ExitScannerScreen> createState() => _ExitScannerScreenState();
}

class _ExitScannerScreenState extends State<ExitScannerScreen> with WidgetsBindingObserver {
  MobileScannerController? _cameraController;
  bool _cameraHasError = false;
  bool _isTorchOn = false;

  // Active Verification State
  bool _isVerifying = false;
  bool _isSubmitting = false;
  DateTime? _lastScanTime;
  ExitVerificationStatus? _resultStatus;
  ScanRejectionDetails? _rejectionDetails;
  VehicleRecord? _verifiedVehicleRecord;
  String? _statusReason;
  // What the server told us about this scan (an exit released by an administrator, the case holding the vehicle...)
  List<ScanNotice> _scanNotices = const [];
  // A visitor day pass leaving campus: Guard 2 checks visitors out as well as registered vehicles
  ScannedVisitorPass? _exitVisitor;
  final Set<int> _exitCheckedItems = <int>{};
  String _selectedDriverName = '';
  String _selectedRelationship = '';
  String _currentPhotoUrl = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 150,
        facing: CameraFacing.back,
        formats: const [BarcodeFormat.qrCode],
        autoStart: true,
      );
    } catch (_) {
      _cameraHasError = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _cameraController?.stopSafely();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isVerifying && _resultStatus == null) {
        _cameraController?.startSafely();
      }
    }
  }

  void _resetScanner() {
    setState(() {
      _resultStatus = null;
      _rejectionDetails = null;
      _verifiedVehicleRecord = null;
      _statusReason = null;
      _scanNotices = const [];
      _exitVisitor = null;
      _exitCheckedItems.clear();
      _selectedDriverName = '';
      _selectedRelationship = '';
      _currentPhotoUrl = '';
      _isVerifying = false;
      _isSubmitting = false;
      _lastScanTime = null;
    });
    _cameraController?.startSafely();
  }

  @visibleForTesting
  void testVerifyPass(String raw) {
    _lastScanTime = null;
    _verifyPass(raw);
  }

  @visibleForTesting
  void testResetScanner() => _resetScanner();

  /// Evaluates scanned QR code against real-time database state for exit eligibility
  Future<void> _verifyPass(String raw) async {
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 1500) {
      return;
    }
    _lastScanTime = now;

    if (_isVerifying || _isSubmitting || _resultStatus != null || _rejectionDetails != null || _exitVisitor != null || _verifiedVehicleRecord != null) return;

    setState(() {
      _isVerifying = true;
      _rejectionDetails = null;
      _resultStatus = null;
      _statusReason = null;
    });

    _cameraController?.stopSafely();

    final clean = raw.trim();

    Map<String, dynamic>? decodedJson;
    if (clean.startsWith('{') && clean.endsWith('}')) {
      try {
        final dynamic d = jsonDecode(clean);
        if (d is Map<String, dynamic>) {
          decodedJson = d;
        } else if (d is Map) {
          decodedJson = Map<String, dynamic>.from(d);
        }
      } catch (_) {}
    }

    final isVisitorPayload = decodedJson != null && (
      decodedJson['type'] == 'NCST_VISITOR_PASS' ||
      decodedJson['type'] == 'visitor_temp' ||
      (decodedJson['pid']?.toString().startsWith('VP-') ?? false) ||
      (decodedJson['passId']?.toString().startsWith('VP-') ?? false) ||
      (decodedJson['pass_code']?.toString().startsWith('VP-') ?? false) ||
      decodedJson.containsKey('visitorName') ||
      decodedJson.containsKey('visitor_name')
    );
    final isVisitorCode = clean.startsWith('VP-') || isVisitorPayload;

    final extractedPlate = (decodedJson?['plateNumber'] ??
        decodedJson?['plate_number'] ??
        decodedJson?['plate'] ??
        '').toString().trim();
    final extractedPassCode = (decodedJson?['pid'] ??
        decodedJson?['passId'] ??
        decodedJson?['pass_code'] ??
        (clean.startsWith('VP-') ? clean : '')).toString().trim();

    // Query live API for fresh status - live database is source of truth
    final verifyPlate = extractedPlate.isNotEmpty ? extractedPlate : (isVisitorCode ? '' : clean);
    Map<String, dynamic>? verifyResult;
    try {
      verifyResult = await ApiService.verifyPassWithServer(
        qrCode: clean,
        plate: verifyPlate.isNotEmpty ? verifyPlate : null,
        gateType: 'Egress',
      );
    } catch (_) {
      // Handled below
    }

    // Check if network error occurred on remote check
    final isNetworkError = ApiService.lastVerifyError != null ||
        (verifyResult != null && (verifyResult['error_type'] == 'network_error' || verifyResult['status'] == 'offline'));
    if (isNetworkError) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _rejectionDetails = ScanRejectionDetails(
          type: ScanRejectionType.networkError,
          title: 'Connection / API Error',
          message: 'Unable to verify vehicle state in real-time with the database. Exit verification stopped for security.',
          reason: ApiService.lastVerifyError ?? 'Network connection failure',
        );
      });
      return;
    }

    // 1. Visitor Pass check: prioritize visitor pass identification so visitor registrations from Guard 1
    // are never mistakenly treated as generic registered vehicles
    final serverVisitor = (verifyResult != null && verifyResult['visitor'] is Map)
        ? (verifyResult['visitor'] as Map<String, dynamic>)
        : null;

    if (serverVisitor != null || isVisitorCode || (verifyResult != null && verifyResult['passType'] == 'visitor_temp')) {
      // 1a. Parse from server verifyResult
      ScannedVisitorPass? visitor = ScannedVisitorPass.fromVerify(verifyResult);

      // 1b. If verifyResult did not return the visitor pass details, query live /api/visitors.php?q=...
      if (visitor == null) {
        final query = extractedPassCode.isNotEmpty
            ? extractedPassCode
            : (extractedPlate.isNotEmpty ? extractedPlate : clean);
        final livePass = await ApiService.lookupVisitorPass(query);
        if (livePass != null) {
          final isBlocked = livePass.isBlocked ||
              (verifyResult != null && (verifyResult['result'] == 'REVOKED' || verifyResult['result'] == 'BANNED'));
          visitor = ScannedVisitorPass.fromVisitorPass(
            livePass,
            result: isBlocked ? 'REVOKED' : (verifyResult?['result']?.toString() ?? 'VALID'),
            accepted: verifyResult != null ? verifyResult['accepted'] == true : livePass.isActive,
            reason: (verifyResult?['reason'] ?? (isBlocked ? 'Blocked pass' : '')).toString(),
            warnings: (verifyResult?['warnings'] as List?)?.map((e) => e.toString()).toList() ?? const [],
            currentlyInside: verifyResult?['currentlyInside'] == true || livePass.status == VisitorPassStatus.active,
          );
        }
      }

      // 1c. If still not found, check local visitor repository
      if (visitor == null) {
        final localPass = await VisitorRepository().lookupPass(clean);
        if (localPass != null) {
          visitor = ScannedVisitorPass.fromVisitorPass(
            localPass,
            result: localPass.isBlocked ? 'REVOKED' : 'VALID',
            accepted: localPass.isActive,
            reason: localPass.isBlocked ? 'Blocked pass' : '',
            currentlyInside: localPass.status == VisitorPassStatus.active,
          );
        }
      }

      // 1d. Decoded payload fallback if created by Guard 1
      if (visitor == null && decodedJson != null && (decodedJson['visitorName'] != null || decodedJson['visitor_name'] != null)) {
        final vName = (decodedJson['visitorName'] ?? decodedJson['visitor_name'] ?? 'Visitor').toString();
        final vPlate = (decodedJson['plateNumber'] ?? decodedJson['plate_number'] ?? 'UNKNOWN').toString();
        final pId = (decodedJson['passId'] ?? decodedJson['pass_code'] ?? 'VP-LOCAL').toString();
        final vModel = (decodedJson['vehicleModel'] ?? decodedJson['vehicle_model'] ?? '').toString();
        visitor = ScannedVisitorPass(
          id: int.tryParse(pId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1,
          passCode: pId,
          visitorName: vName,
          plateNumber: vPlate,
          vehicleModel: vModel,
          validDate: DateTime.now().toIso8601String().substring(0, 10),
          status: 'Active',
          result: 'VALID',
          accepted: true,
          currentlyInside: true,
        );
      }

      if (visitor != null) {
        if (!mounted) return;

        // Strict Blocked Check
        if (visitor.isBlocked || (!visitor.accepted && visitor.reason.toLowerCase().contains('block'))) {
          setState(() {
            _isVerifying = false;
            _rejectionDetails = ScanRejectionDetails(
              type: ScanRejectionType.blocked,
              title: 'Visitor Pass Blocked',
              message: 'This vehicle cannot proceed because it is currently blocked. The vehicle owner must resolve the issue before the vehicle can exit.',
              plateNumber: visitor!.plateNumber,
              ownerName: visitor.visitorName,
              statusBadge: 'BLOCKED',
              reason: visitor.reason.isNotEmpty ? visitor.reason : 'Security Hold on visitor pass.',
            );
          });
          return;
        }

        // Strict Duplicate Exit / Already Used Check
        final alreadyExited = !visitor.accepted &&
            (visitor.reason.contains('already been used') ||
             visitor.reason.contains('already checked out') ||
             visitor.reason.contains('outside') ||
             visitor.status.toLowerCase().contains('used') ||
             visitor.status.toLowerCase().contains('exit'));

        if (alreadyExited) {
          setState(() {
            _isVerifying = false;
            _rejectionDetails = ScanRejectionDetails(
              type: ScanRejectionType.duplicateExit,
              title: 'Vehicle Not Inside Campus',
              message: 'This visitor pass has already completed exit or was not recorded as inside campus. Duplicate exit operations are rejected.',
              plateNumber: visitor!.plateNumber,
              ownerName: visitor.visitorName,
              statusBadge: 'ALREADY EXITED',
              reason: visitor.reason.isNotEmpty ? visitor.reason : 'Pass has already been checked out.',
            );
          });
          return;
        }

        setState(() {
          _isVerifying = false;
          _exitVisitor = visitor;
          _exitCheckedItems.clear();
          _verifiedVehicleRecord = null;
          _resultStatus = visitor!.accepted ? ExitVerificationStatus.valid : ExitVerificationStatus.blocked;
          _statusReason = visitor.reason.isNotEmpty ? visitor.reason : null;
        });
        return;
      }
    }

    // 2. Registered Vehicle lookup (strictly for genuine registered vehicles, NOT visitors)
    VehicleRecord? registeredVehicle;
    try {
      registeredVehicle = await ApiService.lookupVehicle(clean);
    } catch (_) {}

    if (registeredVehicle == null || (!registeredVehicle.isParsedFromQr && (registeredVehicle.ownerIdNumber == 'UNKNOWN' || registeredVehicle.ownerIdNumber.startsWith('VISITOR-')))) {
      final local = GateRepository().resolveVehicle(clean);
      if (local.isParsedFromQr && local.ownerIdNumber != 'UNKNOWN' && !local.ownerIdNumber.startsWith('VISITOR-') && !local.ownerRole.contains('Guest') && !local.ownerRole.contains('Visitor')) {
        registeredVehicle = local;
      } else {
        registeredVehicle = null;
      }
    }

    if (verifyResult != null && verifyResult['vehicle'] is Map<String, dynamic>) {
      final vMap = verifyResult['vehicle'] as Map<String, dynamic>;
      if (registeredVehicle != null) {
        registeredVehicle = registeredVehicle.copyWith(
          campusStatus: (vMap['status'] ?? registeredVehicle.campusStatus)?.toString(),
          registrationStatus: (vMap['registration_status'] ?? registeredVehicle.registrationStatus)?.toString(),
          isBanned: vMap['is_banned'] != null ? (vMap['is_banned'] == 1 || vMap['is_banned'] == true || vMap['is_banned'] == '1') : registeredVehicle.isBanned,
          isSyncedWithDb: true,
        );
      } else {
        registeredVehicle = VehicleRecord.fromQrJson(
          vMap,
          rawPayload: clean,
          isSyncedWithDb: true,
        );
      }
    }

    // Reconcile currentlyInside with server verify response
    if (verifyResult != null && verifyResult['currentlyInside'] != null && registeredVehicle != null) {
      final currentlyInside = verifyResult['currentlyInside'] == true;
      if (!currentlyInside && registeredVehicle.campusStatus == 'Inside Campus') {
        registeredVehicle = registeredVehicle.copyWith(campusStatus: 'Outside');
      } else if (currentlyInside && registeredVehicle.campusStatus != 'Inside Campus' && !registeredVehicle.isBlocked) {
        registeredVehicle = registeredVehicle.copyWith(campusStatus: 'Inside Campus');
      }
    }

    // If genuine registered vehicle found
    if (registeredVehicle != null && registeredVehicle.ownerIdNumber != 'UNKNOWN' && !registeredVehicle.ownerRole.contains('Guest') && !registeredVehicle.ownerRole.contains('Visitor')) {
      _scanNotices = ScanNotice.fromVerify(verifyResult);
      // An administrator released ONE exit for this vehicle on hold (the server accepted it and will use up the release
      // when the exit is recorded): show it as a normal exit, with the release spelled out for the guard.
      final released = verifyResult?['exitRelease'] is Map && verifyResult?['accepted'] == true;
      if (released) {
        registeredVehicle = registeredVehicle.copyWith(isBanned: false, registrationStatus: 'Active', campusStatus: 'Inside Campus');
      }
      _evaluateRegisteredVehicle(registeredVehicle, exitReleased: released);
      return;
    }

    // Invalid / Unrecognized QR State
    if (!mounted) return;
    setState(() {
      _isVerifying = false;
      _rejectionDetails = ScanRejectionDetails(
        type: ScanRejectionType.notFound,
        title: 'Invalid / Unrecognized QR Code',
        message: 'Pass code "$clean" is not a recognized vehicle or visitor pass in the campus registry.',
        statusBadge: 'NOT FOUND',
      );
    });
  }

  /// The server refused to record this exit, so it exists nowhere but on this phone's screen: tell the guard.
  void _showNotRecorded(String plate) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.crimson,
          duration: const Duration(seconds: 10),
          content: Text(
            'NOT RECORDED: the exit of $plate was refused by the server (${ApiService.lastWriteError ?? 'no reason given'}). '
            'Tell the security office.',
          ),
        ),
      );
    } catch (_) {}
  }

  void _evaluateRegisteredVehicle(VehicleRecord vehicle, {bool exitReleased = false}) {
    // 1. Strict BLOCKED Vehicle Check: Guard cannot override
    if (vehicle.isBlocked) {
      setState(() {
        _isVerifying = false;
        _verifiedVehicleRecord = null;
        _resultStatus = null;
        _rejectionDetails = ScanRejectionDetails(
          type: ScanRejectionType.blocked,
          title: 'Vehicle Blocked',
          message: 'This vehicle cannot proceed because it is currently blocked. The vehicle owner must resolve the issue before the vehicle can exit.',
          plateNumber: vehicle.plateNumber,
          ownerName: vehicle.ownerName,
          statusBadge: vehicle.campusStatus ?? 'BLOCKED',
          reason: vehicle.isBanned
              ? 'Vehicle is marked as BANNED in the system database.'
              : (vehicle.registrationStatus?.toLowerCase() == 'suspended'
                  ? 'Registration is SUSPENDED.'
                  : (vehicle.flagReason ?? 'Administrative hold on vehicle.')),
          notices: _scanNotices,
        );
      });
      return;
    }

    // 2. Strict Duplicate Exit Check: Vehicle must currently be inside campus
    if (!vehicle.isInsideCampus) {
      setState(() {
        _isVerifying = false;
        _verifiedVehicleRecord = null;
        _resultStatus = null;
        _rejectionDetails = ScanRejectionDetails(
          type: ScanRejectionType.duplicateExit,
          title: 'Vehicle Not Inside Campus',
          message: 'This vehicle is not currently inside campus (Status: ${vehicle.campusStatus ?? 'Outside'}). A duplicate exit scan cannot be processed.',
          plateNumber: vehicle.plateNumber,
          ownerName: vehicle.ownerName,
          statusBadge: vehicle.campusStatus ?? 'Outside',
          reason: 'Vehicle must enter through Guard 1 before another exit can be granted.',
        );
      });
      return;
    }

    // 3. Vehicle is eligible for exit
    setState(() {
      _isVerifying = false;
      _rejectionDetails = null;
      _verifiedVehicleRecord = vehicle;
      _exitVisitor = null;
      _resultStatus = ExitVerificationStatus.valid;
      _statusReason = exitReleased
          ? 'EXIT RELEASED by an administrator: let it leave once. It stays on hold.'
          : (vehicle.hasActiveFlag ? 'FLAGGED VEHICLE: ${vehicle.flagReason ?? "Security flag active"}' : null);

      if (vehicle.authorizedDrivers.isNotEmpty) {
        final first = vehicle.authorizedDrivers.first;
        _selectedDriverName = first.fullName;
        _selectedRelationship = first.relationship;
        final isOwner = first.fullName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
            first.relationship.toLowerCase().contains('self') ||
            first.relationship.toLowerCase().contains('owner');
        _currentPhotoUrl = (first.photoUrl != null && first.photoUrl!.isNotEmpty)
            ? first.photoUrl!
            : (isOwner ? (vehicle.ownerPhotoUrl ?? '') : '');
      } else {
        _selectedDriverName = vehicle.ownerName;
        _selectedRelationship = 'Registered Owner';
        _currentPhotoUrl = vehicle.ownerPhotoUrl ?? '';
      }
    });
  }

  bool get _exitItemsAllChecked {
    final pass = _exitVisitor;
    return pass == null || !pass.hasItems || _exitCheckedItems.length >= pass.items.length;
  }

  /// Records the exit of a visitor whose day pass exists on the server; the declared items are checked out.
  Future<void> _confirmVisitorExit() async {
    final pass = _exitVisitor;
    if (pass == null || !pass.canAdmit || !_exitItemsAllChecked) return;

    final recorded = await ApiService.postGateLog(
      plateNumber: pass.plateNumber,
      driverName: pass.visitorName,
      driverRelationship: 'Visitor (Day Pass)',
      gatePoint: widget.currentGuard.assignedGate,
      action: 'Exit Approved',
      status: 'Outside',
      guardName: widget.currentGuard.fullName,
      // The server adds the "Items checked out" line itself when items_verified is set
      notes: 'Visitor pass ${pass.passCode}',
      vehicleType: 'Visitor Vehicle',
      ownerName: pass.visitorName,
      visitorPassId: pass.id,
      itemsVerified: pass.hasItems,
    );
    if (!recorded) {
      _showNotRecorded(pass.plateNumber);
    } else {
      widget.onDecision?.call(
        AuditLogEntry(
          id: 'LOG-${DateTime.now().millisecondsSinceEpoch}',
          plateNumber: pass.plateNumber,
          vehicleType: 'Visitor Vehicle',
          ownerName: pass.visitorName,
          driverName: pass.visitorName,
          driverRelationship: 'Visitor (Day Pass)',
          timeIn: DateTime.now(),
          action: 'Exit Approved',
          status: GateStatus.exited,
        ),
      );
    }

    if (!mounted) return;
    if (recorded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Visitor exit confirmed: ${pass.plateNumber} (${pass.visitorName}).'),
          backgroundColor: NcstColors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    if (widget.onReturnToDashboard != null) {
      widget.onReturnToDashboard!();
    } else {
      _resetScanner();
    }
  }

  Future<void> _handleConfirmExit() async {
    if (_isSubmitting) return;

    if (_exitVisitor != null) {
      await _confirmVisitorExit();
      return;
    }
    final v = _verifiedVehicleRecord;
    if (v == null) return;

    // Strict validation check before confirming exit
    if (v.isBlocked || !v.isInsideCampus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text('ACTION DENIED: Vehicle is not eligible for exit.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    if (v.hasActiveFlag) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: NcstColors.crimson, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text('Flagged Vehicle Notice', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vehicle ${v.plateNumber} has an active security flag.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Reason: ${v.flagReason ?? "Security flag on file"}',
                style: const TextStyle(color: NcstColors.slate700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Do you wish to permit exit despite the active flag? Ensure security protocol has been followed.',
                style: TextStyle(fontSize: 13, color: NcstColors.slate600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('CANCEL', style: TextStyle(color: NcstColors.slate600, fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: NcstColors.goldDark,
                foregroundColor: NcstColors.white,
              ),
              child: const Text('PERMIT EXIT', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );

      if (shouldProceed != true) {
        setState(() => _isSubmitting = false);
        return;
      }
      if (!mounted) return;
    }

    final now = DateTime.now();
    final driver = _selectedDriverName.isNotEmpty ? _selectedDriverName : v.ownerName;
    final rel = _selectedRelationship.isNotEmpty ? _selectedRelationship : 'Registered Owner';

    final exitEntry = AuditLogEntry(
      id: 'LOG-${now.millisecondsSinceEpoch.toString().substring(7)}',
      plateNumber: v.plateNumber,
      vehicleType: v.vehicleType,
      ownerName: v.ownerName,
      driverName: driver,
      driverRelationship: rel,
      timeIn: now.subtract(const Duration(hours: 1)),
      action: 'Exit Approved',
      status: GateStatus.exited,
      blockReason: v.hasActiveFlag ? 'FLAGGED EXIT RECORDED: ${v.flagReason}' : null,
    );

    final recorded = await ApiService.postGateLog(
      plateNumber: v.plateNumber,
      driverName: driver,
      driverRelationship: rel,
      gatePoint: widget.currentGuard.assignedGate,
      action: 'Exit Approved',
      status: 'Outside',
      guardName: widget.currentGuard.fullName,
      notes: v.hasActiveFlag ? 'FLAGGED EXIT RECORDED: ${v.flagReason}' : 'Standard student/faculty exit',
      vehicleType: v.vehicleType,
      ownerName: v.ownerName,
      driverId: v.driverIdForName(driver),
    );
    if (!recorded) _showNotRecorded(v.plateNumber);

    widget.onDecision?.call(exitEntry);

    if (mounted) {
      setState(() => _isSubmitting = false);
      try {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('EXIT CLEARED: ${v.plateNumber} ($driver)'),
            backgroundColor: NcstColors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (_) {}
      if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else if (widget.onReturnToDashboard != null) {
        widget.onReturnToDashboard!();
      } else {
        _resetScanner();
      }
    }
  }

  void _showBlockDialog() {
    if (_verifiedVehicleRecord == null && _exitVisitor == null) return;
    BlockReasonDialog.show(
      context,
      _executeBlock,
      title: 'Block Vehicle Exit',
      subtitle: 'Select reason for exit hold / denial:',
    );
  }

  void _executeBlock(String reason) {
    final v = _verifiedVehicleRecord;
    final visitor = _exitVisitor;

    if (v != null) {
      final driver = _selectedDriverName.isNotEmpty ? _selectedDriverName : v.ownerName;
      final rel = _selectedRelationship.isNotEmpty ? _selectedRelationship : 'Registered Owner';

      final blockedEntry = AuditLogEntry(
        id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
        plateNumber: v.plateNumber,
        vehicleType: v.vehicleType,
        ownerName: v.ownerName,
        driverName: driver,
        driverRelationship: rel,
        timeIn: DateTime.now(),
        action: 'Exit Denied',
        status: GateStatus.blocked,
        blockReason: reason,
      );

      widget.onDecision?.call(blockedEntry);

      ApiService.postGateLog(
        plateNumber: v.plateNumber,
        driverName: driver,
        driverRelationship: rel,
        gatePoint: widget.currentGuard.assignedGate,
        action: 'Exit Denied',
        status: 'Blocked',
        notes: reason,
        guardName: widget.currentGuard.fullName,
        vehicleType: v.vehicleType,
        ownerName: v.ownerName,
        driverId: v.driverIdForName(driver),
      );
      ApiService.reportIncident(
        plateNumber: v.plateNumber,
        driverName: driver,
        reason: reason,
        gatePoint: widget.currentGuard.assignedGate,
        notes: 'Exit blocked at gate verification: $reason',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text(
            'EXIT BLOCKED: ${v.plateNumber} ($reason)',
            style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (visitor != null) {
      final blockedEntry = AuditLogEntry(
        id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
        plateNumber: visitor.plateNumber,
        vehicleType: 'Visitor Vehicle',
        ownerName: visitor.visitorName,
        driverName: visitor.visitorName,
        driverRelationship: 'Visitor (Day Pass)',
        timeIn: DateTime.now(),
        action: 'Exit Denied',
        status: GateStatus.blocked,
        blockReason: reason,
      );

      widget.onDecision?.call(blockedEntry);

      ApiService.postGateLog(
        plateNumber: visitor.plateNumber,
        driverName: visitor.visitorName,
        driverRelationship: 'Visitor (Day Pass)',
        gatePoint: widget.currentGuard.assignedGate,
        action: 'Exit Denied',
        status: 'Blocked',
        notes: reason,
        guardName: widget.currentGuard.fullName,
        vehicleType: 'Visitor Vehicle',
        ownerName: visitor.visitorName,
        visitorPassId: visitor.id,
      );
      ApiService.reportIncident(
        plateNumber: visitor.plateNumber,
        driverName: visitor.visitorName,
        reason: reason,
        gatePoint: widget.currentGuard.assignedGate,
        notes: 'Visitor exit blocked: $reason',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text(
            'VISITOR EXIT BLOCKED: ${visitor.plateNumber} ($reason)',
            style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (mounted) {
      if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else if (widget.onReturnToDashboard != null) {
        widget.onReturnToDashboard!();
      } else {
        _resetScanner();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_isVerifying) {
      content = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: NcstColors.navy),
            SizedBox(height: 14),
            Text(
              'Verifying Pass on Server...',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: NcstColors.slate700,
              ),
            ),
          ],
        ),
      );
    } else if (_rejectionDetails != null) {
      content = ScanRejectionView(
        details: _rejectionDetails!,
        onScanAnother: _resetScanner,
        buttonLabel: 'SCAN ANOTHER VEHICLE',
      );
    } else if (_resultStatus == null) {
      content = _buildViewfinderSection();
    } else {
      content = _buildScannedVerificationBody();
    }

    final appBar = AppBar(
      leading: (widget.isEmbedded && widget.onReturnToDashboard != null)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Dashboard',
              onPressed: widget.onReturnToDashboard,
            )
          : null,
      title: Text(_rejectionDetails != null
          ? 'Scan Rejected'
          : (_resultStatus == null ? 'Scan Driver QR Pass' : 'Scanned Verification')),
      backgroundColor: _rejectionDetails != null && _rejectionDetails!.type == ScanRejectionType.blocked
          ? NcstColors.crimson
          : NcstColors.navy,
      foregroundColor: NcstColors.white,
      actions: [
        if (_resultStatus == null && _rejectionDetails == null) ...[
          IconButton(
            tooltip: 'Enter QR Manually',
            icon: const Icon(Icons.keyboard_outlined, color: NcstColors.white),
            onPressed: () => ManualQrDialog.show(context, _verifyPass),
          ),
          IconButton(
            tooltip: 'Toggle Flashlight',
            icon: Icon(
              _isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: _isTorchOn ? NcstColors.gold : NcstColors.white,
            ),
            onPressed: () async {
              try {
                await _cameraController?.toggleTorch();
                setState(() => _isTorchOn = !_isTorchOn);
              } catch (_) {
                setState(() => _isTorchOn = !_isTorchOn);
              }
            },
          ),
        ] else
          TextButton.icon(
            onPressed: _resetScanner,
            icon: const Icon(Icons.qr_code_scanner, color: NcstColors.gold, size: 18),
            label: const Text(
              'Re-Scan QR',
              style: TextStyle(color: NcstColors.gold, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );

    if (widget.isEmbedded) {
      return Container(
        color: NcstColors.slate50,
        child: Column(
          children: [
            appBar,
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: NcstColors.slate50,
      appBar: appBar,
      body: SafeArea(
        child: content,
      ),
    );
  }

  Widget _buildViewfinderSection() {
    return CameraViewfinder(
      cameraController: _cameraController,
      cameraHasError: _cameraHasError,
      onQrDetected: _verifyPass,
      onManualQrPressed: () => ManualQrDialog.show(context, _verifyPass),
      onFlipCameraPressed: () async {
        try {
          await _cameraController?.switchCamera();
        } catch (_) {}
      },
    );
  }

  Widget _buildScannedVerificationBody() {
    if (_exitVisitor != null) {
      return _buildVisitorExitSection();
    }

    final vehicle = _verifiedVehicleRecord;
    if (vehicle == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline_rounded, color: NcstColors.crimson, size: 56),
              const SizedBox(height: 14),
              Text(
                _statusReason ?? 'Pass is invalid or unrecognized.',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: NcstColors.slate800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _resetScanner,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('SCAN ANOTHER PASS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NcstColors.navy,
                  foregroundColor: NcstColors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 880;

    return Column(
      children: [
        if (_scanNotices.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ScanNoticeStrip(notices: _scanNotices)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: ScannedPersonCard(
                              vehicle: vehicle,
                              driverName: _selectedDriverName,
                              relationship: _selectedRelationship,
                              photoUrl: _currentPhotoUrl,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 6,
                            child: AuthorizedDriversCard(
                              vehicle: vehicle,
                              selectedDriverName: _selectedDriverName,
                              onSelectOwner: () {
                                setState(() {
                                  _selectedDriverName = vehicle.ownerName;
                                  _selectedRelationship = 'Registered Owner';
                                  _currentPhotoUrl = vehicle.ownerPhotoUrl ?? '';
                                });
                              },
                              onSelectDriver: (driver) {
                                setState(() {
                                  _selectedDriverName = driver.fullName;
                                  _selectedRelationship = driver.relationship;
                                  final isOwner = driver.fullName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
                                      driver.relationship.toLowerCase().contains('self') ||
                                      driver.relationship.toLowerCase().contains('owner');
                                  _currentPhotoUrl = (driver.photoUrl != null && driver.photoUrl!.isNotEmpty)
                                      ? driver.photoUrl!
                                      : (isOwner ? (vehicle.ownerPhotoUrl ?? '') : '');
                                });
                              },
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          ScannedPersonCard(
                            vehicle: vehicle,
                            driverName: _selectedDriverName,
                            relationship: _selectedRelationship,
                            photoUrl: _currentPhotoUrl,
                          ),
                          const SizedBox(height: 16),
                          AuthorizedDriversCard(
                            vehicle: vehicle,
                            selectedDriverName: _selectedDriverName,
                            onSelectOwner: () {
                              setState(() {
                                _selectedDriverName = vehicle.ownerName;
                                _selectedRelationship = 'Registered Owner';
                                _currentPhotoUrl = vehicle.ownerPhotoUrl ?? '';
                              });
                            },
                            onSelectDriver: (driver) {
                              setState(() {
                                _selectedDriverName = driver.fullName;
                                _selectedRelationship = driver.relationship;
                                final isOwner = driver.fullName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
                                    driver.relationship.toLowerCase().contains('self') ||
                                    driver.relationship.toLowerCase().contains('owner');
                                _currentPhotoUrl = (driver.photoUrl != null && driver.photoUrl!.isNotEmpty)
                                    ? driver.photoUrl!
                                    : (isOwner ? (vehicle.ownerPhotoUrl ?? '') : '');
                              });
                            },
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        BottomDecisionBar(
          onBlock: _showBlockDialog,
          onCleared: _handleConfirmExit,
          isClearedEnabled: vehicle.isEligibleForExit && !_isSubmitting,
          clearedLabel: 'CLEARED (EXIT)',
          disabledLabel: vehicle.isBlocked
              ? 'VEHICLE BLOCKED'
              : (!vehicle.isInsideCampus ? 'NOT INSIDE CAMPUS' : null),
          clearedIcon: Icons.check_circle_rounded,
          clearedColor: NcstColors.green,
        ),
      ],
    );
  }

  Widget _buildVisitorExitSection() {
    final pass = _exitVisitor!;
    final canConfirm = pass.canAdmit && _exitItemsAllChecked;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ScannedVisitorCard(
                  pass: pass,
                  checkedItems: _exitCheckedItems,
                  isExit: true,
                  onToggleItem: (i) => setState(() {
                    if (!_exitCheckedItems.remove(i)) _exitCheckedItems.add(i);
                  }),
                ),
              ),
            ),
          ),
        ),
        BottomDecisionBar(
          onBlock: _showBlockDialog,
          onCleared: _confirmVisitorExit,
          isClearedEnabled: canConfirm,
          clearedLabel: 'CLEARED (VISITOR EXIT)',
          disabledLabel: !pass.canAdmit
              ? 'EXIT NOT ALLOWED'
              : 'TICK ITEMS (${_exitCheckedItems.length}/${pass.items.length})',
        ),
      ],
    );
  }
}
