import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/utils/scanner_controller_safe.dart';
import '../../../data/mock_data.dart';
import '../../../models/scanned_visitor_pass.dart';
import '../../../models/user_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../models/visitor_pass_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../repositories/visitor_repository.dart';
import '../../../services/api_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../theme/ncst_theme.dart';
import '../../visitor/screens/visitor_registration_screen.dart';
import '../dialogs/block_reason_dialog.dart';
import '../dialogs/issue_violation_dialog.dart';
import '../dialogs/manual_qr_dialog.dart';
import '../widgets/authorized_drivers_card.dart';
import '../widgets/bottom_decision_bar.dart';
import '../widgets/camera_viewfinder.dart';
import '../widgets/scan_rejection_view.dart';
import '../widgets/scanned_person_card.dart';
import '../widgets/scanned_visitor_card.dart';

class QrScannerScreen extends StatefulWidget {
  final Function(AuditLogEntry) onDecision;
  final VoidCallback? onReturnToDashboard;
  final VoidCallback? onNavigateToVisitorRegistration;
  final bool isEmbedded;
  final GateRepository repository;
  final VehicleRecord? initialVehicle;

  const QrScannerScreen({
    super.key,
    required this.onDecision,
    this.onReturnToDashboard,
    this.onNavigateToVisitorRegistration,
    this.isEmbedded = false,
    this.repository = const GateRepository(),
    this.initialVehicle,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> with WidgetsBindingObserver {
  MobileScannerController? _cameraController;
  bool _cameraHasError = false;
  bool _isTorchOn = false;

  bool _isValidating = false;
  bool _isSubmitting = false;
  bool _isPatrolInspection = false;
  DateTime? _lastScanTime;
  ScanRejectionDetails? _rejectionDetails;

  VehicleRecord? _scannedVehicle;
  // Set when the scanned plate / pass code belongs to a visitor day pass that already exists on the server
  ScannedVisitorPass? _visitorPass;
  final Set<int> _checkedVisitorItems = <int>{};
  late String _selectedDriverName;
  late String _selectedRelationship;
  late String _currentPhotoUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialVehicle != null) {
      final v = widget.initialVehicle!;
      _scannedVehicle = v;
      if (v.authorizedDrivers.isNotEmpty) {
        final first = v.authorizedDrivers.first;
        _selectedDriverName = first.fullName;
        _selectedRelationship = first.relationship;
        final isOwner = first.fullName.trim().toLowerCase() == v.ownerName.trim().toLowerCase() ||
            first.relationship.toLowerCase().contains('self') ||
            first.relationship.toLowerCase().contains('owner');
        _currentPhotoUrl = (first.photoUrl != null && first.photoUrl!.isNotEmpty)
            ? first.photoUrl!
            : (isOwner ? (v.ownerPhotoUrl ?? '') : (v.ownerPhotoUrl ?? ''));
      } else {
        _selectedDriverName = v.ownerName;
        _selectedRelationship = 'Registered Owner';
        _currentPhotoUrl = v.ownerPhotoUrl ?? '';
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncVehicleWithDb(v);
      });
    }
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
      if (_scannedVehicle == null) {
        _cameraController?.startSafely();
      }
    }
  }

  void _onQrDetected(VehicleRecord vehicle) {
    // Cut camera native buffer and memory usage immediately upon successful scan
    _cameraController?.stopSafely();
    setState(() {
      _scannedVehicle = vehicle;
      _visitorPass = null;
      _checkedVisitorItems.clear();
      if (vehicle.authorizedDrivers.isNotEmpty) {
        final first = vehicle.authorizedDrivers.first;
        _selectedDriverName = first.fullName;
        _selectedRelationship = first.relationship;
        final isOwner = first.fullName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
            first.relationship.toLowerCase().contains('self') ||
            first.relationship.toLowerCase().contains('owner');
        _currentPhotoUrl = (first.photoUrl != null && first.photoUrl!.isNotEmpty)
            ? first.photoUrl!
            : (isOwner ? (vehicle.ownerPhotoUrl ?? '') : (vehicle.ownerPhotoUrl ?? ''));
      } else {
        _selectedDriverName = vehicle.ownerName;
        _selectedRelationship = 'Registered Owner';
        _currentPhotoUrl = vehicle.ownerPhotoUrl ?? '';
      }
    });
  }

  void _resetScanner() {
    setState(() {
      _scannedVehicle = null;
      _visitorPass = null;
      _checkedVisitorItems.clear();
      _rejectionDetails = null;
      _isValidating = false;
      _isSubmitting = false;
      _isPatrolInspection = false;
      _lastScanTime = null;
    });
    _cameraController?.startSafely();
  }

  @visibleForTesting
  void testProcessRawQrCode(String raw) {
    _lastScanTime = null;
    _processRawQrCode(raw);
  }

  void _processRawQrCode(String raw) async {
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 1500) {
      return;
    }
    _lastScanTime = now;

    if (_isValidating || _isSubmitting || _scannedVehicle != null || _visitorPass != null || _rejectionDetails != null) return;
    final clean = raw.trim();
    if (clean.isEmpty) return;

    _cameraController?.stopSafely();
    setState(() {
      _isValidating = true;
      _rejectionDetails = null;
      _isPatrolInspection = false;
    });

    await _syncVehicleWithDb(null, clean);
  }

  Future<void> _syncVehicleWithDb(VehicleRecord? initialVeh, [String? raw]) async {
    final queryCode = (raw != null && raw.trim().isNotEmpty)
        ? raw.trim()
        : (initialVeh?.qrPassCode.isNotEmpty == true
            ? initialVeh!.qrPassCode
            : (initialVeh?.plateNumber ?? ''));

    if (queryCode.isEmpty) {
      if (mounted) setState(() => _isValidating = false);
      return;
    }

    Map<String, dynamic>? decodedJson;
    if (queryCode.startsWith('{') && queryCode.endsWith('}')) {
      try {
        final dynamic d = jsonDecode(queryCode);
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
    final isVisitorCode = queryCode.startsWith('VP-') || isVisitorPayload;

    final extractedPlate = (decodedJson?['plateNumber'] ??
        decodedJson?['plate_number'] ??
        decodedJson?['plate'] ??
        '').toString().trim();
    final extractedPassCode = (decodedJson?['pid'] ??
        decodedJson?['passId'] ??
        decodedJson?['pass_code'] ??
        (queryCode.startsWith('VP-') ? queryCode : '')).toString().trim();

    try {
      final verifyPlate = extractedPlate.isNotEmpty
          ? extractedPlate
          : (isVisitorCode ? '' : (initialVeh?.plateNumber ?? queryCode));

      final verifyFuture = ApiService.verifyPassWithServer(
        qrCode: queryCode,
        plate: verifyPlate.isNotEmpty ? verifyPlate : null,
        gateType: 'Ingress',
      );
      final verifyResult = await verifyFuture;

      // Check network / API failure
      final isNetworkError = ApiService.lastVerifyError != null ||
          (verifyResult != null && (verifyResult['error_type'] == 'network_error' || verifyResult['status'] == 'offline'));
      if (isNetworkError) {
        if (!mounted) return;
        setState(() {
          _isValidating = false;
          _scannedVehicle = null;
          _rejectionDetails = ScanRejectionDetails(
            type: ScanRejectionType.networkError,
            title: 'Connection / API Error',
            message: 'Unable to verify vehicle state in real-time with the database. Entry verification stopped for security.',
            reason: ApiService.lastVerifyError ?? 'Network connection failure',
          );
        });
        return;
      }

      final serverVisitor = (verifyResult != null && verifyResult['visitor'] is Map)
          ? (verifyResult['visitor'] as Map<String, dynamic>)
          : null;

      // 1. Visitor Pass check: prioritize visitor pass identification so visitor registrations from Guard 1
      // are never mistakenly treated as generic registered vehicles
      if (serverVisitor != null || isVisitorCode || (verifyResult != null && verifyResult['passType'] == 'visitor_temp')) {
        ScannedVisitorPass? visitor = ScannedVisitorPass.fromVerify(verifyResult);

        if (visitor == null) {
          final query = extractedPassCode.isNotEmpty
              ? extractedPassCode
              : (extractedPlate.isNotEmpty ? extractedPlate : queryCode);
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

        if (visitor == null) {
          final localPass = await VisitorRepository().lookupPass(queryCode);
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

        if (visitor == null && MockData.isTestEnvironment && decodedJson != null && (decodedJson['visitorName'] != null || decodedJson['visitor_name'] != null)) {
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
            currentlyInside: false,
          );
        }

        if (visitor != null) {
          if (!mounted) return;

          // Strict Blocked Check
          if (visitor.isBlocked || (!visitor.accepted && visitor.reason.toLowerCase().contains('block'))) {
            setState(() {
              _isValidating = false;
              _scannedVehicle = null;
              _rejectionDetails = ScanRejectionDetails(
                type: ScanRejectionType.blocked,
                title: 'Visitor Pass Blocked',
                message: 'This vehicle cannot proceed because it is currently blocked. The vehicle owner must resolve the issue before entry can be granted.',
                plateNumber: visitor!.plateNumber,
                ownerName: visitor.visitorName,
                statusBadge: 'BLOCKED',
                reason: visitor.reason.isNotEmpty ? visitor.reason : 'Security Hold on visitor pass.',
              );
            });
            return;
          }

          // Strict Duplicate Entry Attempt Check (Anti-passback: already recorded inside)
          if (visitor.currentlyInside || (!visitor.accepted && (visitor.reason.contains('already inside') || visitor.reason.contains('already entered')))) {
            setState(() {
              _isValidating = false;
              _scannedVehicle = null;
              _rejectionDetails = ScanRejectionDetails(
                type: ScanRejectionType.duplicateEntry,
                title: 'Duplicate Entry Attempt',
                message: 'This visitor pass is already recorded as inside campus. The same QR code cannot be used for entry while already inside.',
                plateNumber: visitor!.plateNumber,
                ownerName: visitor.visitorName,
                statusBadge: 'INSIDE CAMPUS',
                reason: visitor.reason.isNotEmpty ? visitor.reason : 'Anti-passback: Vehicle must exit before entering again.',
                visitor: visitor,
              );
            });
            return;
          }

          // The server did not accept this visitor pass (not yet valid, expired, already used...): no approval from here
          if (!visitor.accepted) {
            final refusal = visitor.reason.isNotEmpty ? visitor.reason : 'The server did not accept this visitor pass (${visitor.result}).';
            setState(() {
              _isValidating = false;
              _scannedVehicle = null;
              _rejectionDetails = ScanRejectionDetails(
                type: ScanRejectionType.blocked,
                title: 'Visitor Pass Not Accepted',
                message: refusal,
                plateNumber: visitor!.plateNumber,
                ownerName: visitor.visitorName,
                statusBadge: visitor.result.isEmpty ? 'REFUSED' : visitor.result,
                reason: refusal,
              );
            });
            return;
          }

          setState(() {
            _isValidating = false;
            _rejectionDetails = null;
          });
          _applyVisitorPass(visitor);
          return;
        }
      }

      // 2. Registered Vehicle lookup (strictly for genuine registered vehicles, NOT visitors)
      VehicleRecord? remoteVehicle;
      try {
        remoteVehicle = await ApiService.lookupVehicle(queryCode);
      } catch (_) {}

      if (remoteVehicle == null && initialVeh != null && initialVeh.plateNumber.isNotEmpty) {
        remoteVehicle = await ApiService.lookupVehicleByPlate(initialVeh.plateNumber);
      }

      if (remoteVehicle == null && verifyResult != null) {
        final serverVeh = verifyResult['vehicle'] ?? verifyResult['data']?['vehicle'];
        if (serverVeh is Map<String, dynamic>) {
          try {
            remoteVehicle = VehicleRecord.fromQrJson(
              serverVeh,
              rawPayload: queryCode,
              isSyncedWithDb: true,
            );
          } catch (e) {
            debugPrint('[QrScannerScreen] Parse vehicle from verifyResult: $e');
          }
        }
      }

      if (remoteVehicle == null || (!remoteVehicle.isParsedFromQr && (remoteVehicle.ownerIdNumber == 'UNKNOWN' || remoteVehicle.ownerIdNumber.startsWith('VISITOR-')))) {
        if (initialVeh != null && (initialVeh.isParsedFromQr || (initialVeh.ownerIdNumber != 'UNKNOWN' && !initialVeh.ownerIdNumber.startsWith('VISITOR-')))) {
          remoteVehicle = initialVeh;
        } else {
          final local = widget.repository.resolveVehicle(queryCode);
          if (local.isParsedFromQr && local.ownerIdNumber != 'UNKNOWN' && !local.ownerIdNumber.startsWith('VISITOR-') && !local.ownerRole.contains('Guest') && !local.ownerRole.contains('Visitor')) {
            remoteVehicle = local;
          } else {
            remoteVehicle = null;
          }
        }
      }

      final vData = (verifyResult != null && verifyResult['data'] is Map<String, dynamic>)
          ? (verifyResult['data'] as Map<String, dynamic>)
          : verifyResult;

      // Check if completely unrecognized QR
      if (remoteVehicle == null) {
        setState(() {
          _isValidating = false;
          _scannedVehicle = null;
          _rejectionDetails = ScanRejectionDetails(
            type: ScanRejectionType.notFound,
            title: 'Invalid / Unrecognized QR Code',
            message: 'Pass code "$queryCode" is not a recognized vehicle or visitor pass in the campus registry.',
            statusBadge: 'NOT FOUND',
          );
        });
        return;
      }

      // Enrich vehicle status with live database values
      if (vData != null && vData['vehicle'] is Map<String, dynamic>) {
        final vMap = vData['vehicle'] as Map<String, dynamic>;
        remoteVehicle = remoteVehicle.copyWith(
          campusStatus: (vMap['status'] ?? remoteVehicle.campusStatus)?.toString(),
          registrationStatus: (vMap['registration_status'] ?? remoteVehicle.registrationStatus)?.toString(),
          isBanned: vMap['is_banned'] != null ? (vMap['is_banned'] == 1 || vMap['is_banned'] == true || vMap['is_banned'] == '1') : remoteVehicle.isBanned,
          isSyncedWithDb: true,
        );
      }

      final isServerBanned = vData != null &&
          (vData['result'] == 'BANNED' ||
           vData['result'] == 'SUSPENDED' ||
           vData['result'] == 'FORGED' ||
           vData['result'] == 'REVOKED' ||
           (vData['accepted'] == false && (vData['message']?.toString().toUpperCase().contains('BAN') == true)));

      if (isServerBanned) {
        remoteVehicle = remoteVehicle.copyWith(isBanned: true);
      }

      // Reconcile currentlyInside
      if (vData != null && vData['currentlyInside'] != null) {
        final currentlyInside = vData['currentlyInside'] == true;
        if (currentlyInside && remoteVehicle.campusStatus != 'Inside Campus') {
          remoteVehicle = remoteVehicle.copyWith(campusStatus: 'Inside Campus', isAntiPassback: true);
        } else if (!currentlyInside && remoteVehicle.campusStatus == 'Inside Campus') {
          remoteVehicle = remoteVehicle.copyWith(campusStatus: 'Outside', isAntiPassback: false);
        }
      }

      // 1. Strict BLOCKED Vehicle Check: Guard cannot override
      if (remoteVehicle.isBlocked) {
        setState(() {
          _isValidating = false;
          _scannedVehicle = null;
          _rejectionDetails = ScanRejectionDetails(
            type: ScanRejectionType.blocked,
            title: 'Vehicle Blocked',
            message: 'This vehicle cannot proceed because it is currently blocked. The vehicle owner must resolve the issue before the vehicle can enter.',
            plateNumber: remoteVehicle!.plateNumber,
            ownerName: remoteVehicle.ownerName,
            statusBadge: remoteVehicle.campusStatus ?? 'BLOCKED',
            reason: remoteVehicle.isBanned
                ? 'Vehicle is marked as BANNED in the system database.'
                : (remoteVehicle.registrationStatus?.toLowerCase() == 'suspended'
                    ? 'Registration is SUSPENDED.'
                    : (remoteVehicle.flagReason ?? 'Administrative hold on vehicle.')),
          );
        });
        return;
      }

      // 1b. Obey the server's decision. Anything it did not accept (registration fee unpaid, pass expired, not
      // registered...) stops here: the guard cannot approve it from this screen. (A vehicle already inside is the
      // anti-passback case handled just below.)
      if (vData != null && vData['accepted'] == false && !isServerBanned && vData['currentlyInside'] != true) {
        final serverResult = (vData['result'] ?? '').toString();
        final serverReason = (vData['reason'] ?? vData['message'] ?? 'The server did not accept this pass.').toString();
        setState(() {
          _isValidating = false;
          _scannedVehicle = null;
          _rejectionDetails = ScanRejectionDetails(
            type: serverResult == 'NOT_FOUND' ? ScanRejectionType.notFound : ScanRejectionType.blocked,
            title: _serverRefusalTitle(serverResult),
            message: serverReason,
            plateNumber: remoteVehicle!.plateNumber,
            ownerName: remoteVehicle.ownerName,
            statusBadge: serverResult.isEmpty ? 'REFUSED' : serverResult,
            reason: serverReason,
          );
        });
        return;
      }

      // 2. Strict Duplicate Entry Check (Anti-passback): Vehicle is already inside campus
      if (remoteVehicle.isInsideCampus) {
        setState(() {
          _isValidating = false;
          _scannedVehicle = null;
          _rejectionDetails = ScanRejectionDetails(
            type: ScanRejectionType.duplicateEntry,
            title: 'Duplicate Entry Attempt',
            message: 'This vehicle is already recorded as inside campus. The same QR code cannot be used for entry while already inside.',
            plateNumber: remoteVehicle!.plateNumber,
            ownerName: remoteVehicle.ownerName,
            statusBadge: remoteVehicle.campusStatus ?? 'Inside Campus',
            reason: 'Anti-passback protection: Vehicle must exit through Guard 2 before another entry can be recorded.',
            vehicle: _withOnCampusDetails(remoteVehicle, vData),
          );
        });
        return;
      }

      // 3. Vehicle is eligible for entry
      final enriched = remoteVehicle;
      MockData.upsertVehicle(enriched);
      LocalCacheService.upsertVehicle(enriched);

      setState(() {
        _isValidating = false;
        _rejectionDetails = null;
      });
      _onQrDetected(enriched);
    } catch (e) {
      debugPrint('[QrScannerScreen] Validation error: $e');
      if (mounted) {
        setState(() {
          _isValidating = false;
          _rejectionDetails = ScanRejectionDetails(
            type: ScanRejectionType.networkError,
            title: 'Validation Error',
            message: 'An error occurred while validating the QR pass. Please try scanning again.',
            reason: e.toString(),
          );
        });
      }
    }
  }

  /// Adds the server's "where is it and who to call" block (verify.php `onCampus`) to a vehicle that is already inside.
  VehicleRecord _withOnCampusDetails(VehicleRecord vehicle, Map<String, dynamic>? data) {
    final oc = data?['onCampus'];
    if (oc is! Map) return vehicle;
    String? text(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty || t == 'null' ? null : t;
    }
    final entry = text(oc['entryTime']);
    return vehicle.copyWith(
      ownerPhone: text(oc['ownerPhone']),
      onCampusSince: entry != null ? DateTime.tryParse(entry.replaceFirst(' ', 'T')) : null,
      hoursInside: double.tryParse((oc['hoursInside'] ?? '').toString()),
      entryGate: text(oc['gatePoint']),
      enteredBy: text(oc['enteredBy']),
      admittedBy: text(oc['admittedBy']),
    );
  }

  /// "Issue violation" from the already-inside screen: the vehicle is put on hold and the owner is notified.
  void _showIssueViolationDialog() {
    final vehicle = _rejectionDetails?.vehicle;
    if (vehicle == null) return;
    IssueViolationDialog.show(
      context,
      plateNumber: vehicle.plateNumber,
      onSubmit: (type, notes) async {
        final messenger = ScaffoldMessenger.of(context);
        final error = await ApiService.issueViolation(plateNumber: vehicle.plateNumber, type: type, notes: notes);
        if (!mounted) return;
        if (error != null) {
          messenger.showSnackBar(SnackBar(
            backgroundColor: NcstColors.crimson,
            duration: const Duration(seconds: 6),
            content: Text('NOT RECORDED: $error', style: const TextStyle(fontWeight: FontWeight.w700)),
          ));
          return;
        }
        widget.onDecision(AuditLogEntry(
          id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          plateNumber: vehicle.plateNumber,
          vehicleType: vehicle.vehicleType,
          ownerName: vehicle.ownerName,
          driverName: vehicle.enteredBy ?? vehicle.ownerName,
          timeIn: DateTime.now(),
          status: GateStatus.blocked,
          blockReason: 'Violation: $type',
        ));
        final held = vehicle.copyWith(isBanned: true);
        MockData.upsertVehicle(held);
        LocalCacheService.upsertVehicle(held);
        messenger.showSnackBar(SnackBar(
          backgroundColor: NcstColors.green,
          duration: const Duration(seconds: 4),
          content: Text('Violation recorded. ${vehicle.plateNumber} is on hold and the owner was notified.',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ));
        _resetScanner();
      },
    );
  }

  String _serverRefusalTitle(String result) {
    switch (result) {
      case 'UNPAID':
        return 'Registration Fee Unpaid';
      case 'EXPIRED':
        return 'Pass Expired';
      case 'NOT_FOUND':
        return 'Not Registered';
      default:
        return 'Entry Not Allowed';
    }
  }

  void _showManualQrInputDialog() {
    ManualQrDialog.show(context, _processRawQrCode);
  }

  /// Shows an existing visitor day pass the server recognised, in place of the locally guessed "unregistered" record.
  void _applyVisitorPass(ScannedVisitorPass pass) {
    setState(() {
      _visitorPass = pass;
      _checkedVisitorItems.clear();
      _selectedDriverName = pass.visitorName;
      _selectedRelationship = 'Visitor (Day Pass)';
      _currentPhotoUrl = '';
      _scannedVehicle = (_scannedVehicle ?? VehicleRecord(
        plateNumber: pass.plateNumber,
        vehicleType: 'Visitor Vehicle',
        makeModelColor: pass.vehicleModel.isNotEmpty ? pass.vehicleModel : 'Visitor Vehicle',
        ownerName: pass.visitorName,
        ownerRole: 'Visitor (Day Pass)',
        ownerIdNumber: pass.passCode,
        category: CampusUserCategory.visitor,
        qrPassCode: pass.passCode,
        authorizedDrivers: [
          AuthorizedDriver(
            id: 'drv-visitor',
            fullName: pass.visitorName,
            relationship: 'Visitor (Day Pass)',
            licenseNo: 'N/A',
          ),
        ],
      )).copyWith(
        plateNumber: pass.plateNumber,
        makeModelColor: pass.vehicleModel.isNotEmpty ? pass.vehicleModel : null,
        ownerName: pass.visitorName,
        ownerRole: 'Visitor (Day Pass)',
        ownerIdNumber: pass.passCode,
        category: CampusUserCategory.visitor,
        isAntiPassback: pass.currentlyInside,
      );
    });
  }

  void _toggleVisitorItem(int index) {
    setState(() {
      if (!_checkedVisitorItems.remove(index)) _checkedVisitorItems.add(index);
    });
  }

  bool get _visitorItemsAllChecked {
    final pass = _visitorPass;
    return pass == null || !pass.hasItems || _checkedVisitorItems.length >= pass.items.length;
  }

  /// Records the entry of a visitor whose day pass already exists on the server.
  void _admitVisitor() {
    final pass = _visitorPass;
    if (pass == null) return;
    final messenger = ScaffoldMessenger.of(context);

    if (!pass.canAdmit) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.crimson,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'ENTRY NOT ALLOWED: ${pass.reason.isNotEmpty ? pass.reason : pass.verdictTitle}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
        ),
      );
      return;
    }
    if (!_visitorItemsAllChecked) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.goldDark,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Check every declared item first (${_checkedVisitorItems.length}/${pass.items.length} ticked).',
            style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
        ),
      );
      return;
    }

    widget.onDecision(
      AuditLogEntry(
        id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
        plateNumber: pass.plateNumber,
        vehicleType: 'Visitor Vehicle',
        ownerName: pass.visitorName,
        driverName: pass.visitorName,
        driverRelationship: 'Visitor (Day Pass)',
        timeIn: DateTime.now(),
        status: GateStatus.inside,
      ),
    );

    ApiService.postGateLog(
      plateNumber: pass.plateNumber,
      driverName: pass.visitorName,
      driverRelationship: 'Visitor (Day Pass)',
      gatePoint: 'Gate 1 (Main Ingress)',
      action: 'Entry Recorded',
      status: 'Inside Campus',
      // The server adds the "Items checked in" line itself when items_verified is set
      notes: 'Visitor pass ${pass.passCode}',
      vehicleType: 'Visitor Vehicle',
      ownerName: pass.visitorName,
      visitorPassId: pass.id,
      itemsVerified: pass.hasItems,
    ).then((recorded) {
      if (recorded) return;
      _showEntryNotRecorded(messenger, pass.plateNumber);
    });

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          'ENTRY CLEARED: ${pass.plateNumber} (${pass.visitorName}, visitor pass ${pass.passCode})',
          style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
        ),
      ),
    );

    if (mounted) {
      if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else if (widget.onReturnToDashboard != null) {
        widget.onReturnToDashboard!();
      }
    }
  }

  /// The server refused an entry the guard just cleared: it exists nowhere but on this phone's screen.
  void _showEntryNotRecorded(ScaffoldMessengerState messenger, String plate) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.crimson,
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'NOT RECORDED: $plate was refused by the server (${ApiService.lastWriteError ?? 'no reason given'}). '
          'Do not admit this vehicle; contact the security office.',
          style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
        ),
      ),
    );
  }

  void _handleCleared() async {
    if (_isSubmitting || _scannedVehicle == null) return;
    if (_visitorPass != null) {
      _admitVisitor();
      return;
    }
    final vehicle = _scannedVehicle!;

    // 1. Guard against Banned / Suspended / Denied vehicles
    if (vehicle.isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text(
            'ENTRY DENIED: This vehicle is currently blocked. Clearance cannot be granted.',
            style: TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 2. Guard against Duplicate Entry / Already inside
    if (vehicle.isInsideCampus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text(
            'ENTRY DENIED: Vehicle is already inside campus. Duplicate entry rejected.',
            style: TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // 2. Unregistered pass -> route to visitor registration
    if (vehicle.isUnregistered) {
      if (widget.onNavigateToVisitorRegistration != null) {
        widget.onNavigateToVisitorRegistration!();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VisitorRegistrationScreen(
              currentGuard: GuardUser(
                id: 'guard-current',
                username: 'guard',
                fullName: 'Gate Guard',
                badgeNumber: 'G-101',
                role: GuardRole.entrance,
                assignedGate: 'Gate 1 (Main Ingress)',
                loginTime: DateTime.now(),
              ),
              onReturnToDashboard: widget.onReturnToDashboard,
            ),
          ),
        );
      }
      return;
    }

    // 3. Flagged vehicle alert / confirmation dialog
    if (vehicle.hasActiveFlag) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: NcstColors.goldDark, size: 28),
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
                'Vehicle ${vehicle.plateNumber} has an active security flag.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Reason: ${vehicle.flagReason ?? "Security flag on file"}',
                style: const TextStyle(color: NcstColors.slate700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Do you wish to permit entry despite the active flag? Ensure security protocol has been followed.',
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
              child: const Text('PERMIT ENTRY', style: TextStyle(fontWeight: FontWeight.w800)),
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

    final newEntry = AuditLogEntry(
      id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      plateNumber: _scannedVehicle!.plateNumber,
      vehicleType: _scannedVehicle!.vehicleType,
      ownerName: _scannedVehicle!.ownerName,
      driverName: _selectedDriverName,
      driverRelationship: _selectedRelationship,
      timeIn: DateTime.now(),
      status: GateStatus.inside,
    );

    final messenger = ScaffoldMessenger.of(context);
    final entryDesc = 'ENTRY CLEARED: ${_scannedVehicle!.plateNumber} ($_selectedDriverName)';

    widget.onDecision(newEntry);

    // Asynchronously synchronize with InfinityFree MySQL Backend API. If the server REFUSES the entry (banned,
    // unregistered...) it is not recorded anywhere: say so loudly, the guard must not treat it as cleared.
    final plateForLog = _scannedVehicle!.plateNumber;
    ApiService.postGateLog(
      plateNumber: plateForLog,
      driverName: _selectedDriverName,
      driverRelationship: _selectedRelationship,
      gatePoint: 'Gate 1 (Main Ingress)',
      action: 'Entry Recorded',
      status: 'Inside Campus',
      vehicleType: _scannedVehicle!.vehicleType,
      ownerName: _scannedVehicle!.ownerName,
      driverId: _scannedVehicle!.driverIdForName(_selectedDriverName),
    ).then((recorded) {
      if (recorded) return;
      _showEntryNotRecorded(messenger, plateForLog);
    });

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.green,
        content: Text(
          entryDesc,
          style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else if (widget.onReturnToDashboard != null) {
        widget.onReturnToDashboard!();
      }
    }
  }

  void _startPatrolInspection() {
    final vehicle = _rejectionDetails?.vehicle;
    final visitor = _rejectionDetails?.visitor;
    setState(() {
      _isPatrolInspection = true;
      _rejectionDetails = null;
      if (visitor != null) {
        _visitorPass = visitor;
        _scannedVehicle = null;
      } else if (vehicle != null) {
        _scannedVehicle = vehicle;
        _visitorPass = null;
        if (vehicle.authorizedDrivers.isNotEmpty) {
          final first = vehicle.authorizedDrivers.first;
          _selectedDriverName = first.fullName;
          _selectedRelationship = first.relationship;
          final isOwner = first.fullName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
              first.relationship.toLowerCase().contains('self') ||
              first.relationship.toLowerCase().contains('owner');
          _currentPhotoUrl = (first.photoUrl != null && first.photoUrl!.isNotEmpty)
              ? first.photoUrl!
              : (isOwner ? (vehicle.ownerPhotoUrl ?? '') : (vehicle.ownerPhotoUrl ?? ''));
        } else {
          _selectedDriverName = vehicle.ownerName;
          _selectedRelationship = 'Registered Owner';
          _currentPhotoUrl = vehicle.ownerPhotoUrl ?? '';
        }
      }
    });
  }

  void _showBlockDialog() {
    if (_scannedVehicle == null && _visitorPass == null) return;
    BlockReasonDialog.show(
      context,
      _executeBlock,
      title: _isPatrolInspection ? 'Report In-Campus Incident' : 'Block Vehicle Entry',
      subtitle: _isPatrolInspection ? 'Select reason for security hold / incident:' : 'Select reason for entry denial:',
    );
  }

  void _executeBlock(String reason) {
    if (_scannedVehicle == null && _visitorPass == null) return;

    final plate = _scannedVehicle?.plateNumber ?? _visitorPass!.plateNumber;
    final driver = _scannedVehicle != null ? _selectedDriverName : _visitorPass!.visitorName;
    final rel = _scannedVehicle != null ? _selectedRelationship : 'Visitor (Day Pass)';
    final owner = _scannedVehicle?.ownerName ?? _visitorPass!.visitorName;
    final type = _scannedVehicle?.vehicleType ?? _visitorPass!.vehicleModel;

    final blockedEntry = AuditLogEntry(
      id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      plateNumber: plate,
      vehicleType: type,
      ownerName: owner,
      driverName: driver,
      driverRelationship: rel,
      timeIn: DateTime.now(),
      status: GateStatus.blocked,
      blockReason: reason,
    );

    widget.onDecision(blockedEntry);

    if (_isPatrolInspection) {
      // In-campus patrol inspection hold: do NOT post an Entry Denied gate log,
      // because an in-campus inspection is NOT a gate transit attempt.
      ApiService.reportIncident(
        plateNumber: plate,
        driverName: driver,
        reason: reason,
        gatePoint: 'Gate 1 (Patrol / In-Campus Inspection)',
        notes: 'In-campus inspection hold: $reason',
      );
      if (_scannedVehicle != null) {
        final updated = _scannedVehicle!.copyWith(campusStatus: 'Blocked / Alert');
        MockData.upsertVehicle(updated);
        LocalCacheService.upsertVehicle(updated);
      }
    } else {
      // Gate transit block: post Entry Denied gate log and incident report
      ApiService.postGateLog(
        plateNumber: plate,
        driverName: driver,
        driverRelationship: rel,
        gatePoint: 'Gate 1 (Main Ingress)',
        action: 'Entry Denied',
        status: 'Blocked',
        notes: reason,
        vehicleType: type,
        ownerName: owner,
        driverId: _scannedVehicle?.driverIdForName(driver),
        visitorPassId: _visitorPass?.id,
      );
      ApiService.reportIncident(
        plateNumber: plate,
        driverName: driver,
        reason: reason,
        gatePoint: 'Gate 1 (Main Ingress)',
        notes: 'Entry blocked at gate verification: $reason',
      );
    }

    if (!widget.isEmbedded && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    } else if (widget.onReturnToDashboard != null) {
      widget.onReturnToDashboard!();
    } else {
      _resetScanner();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.crimson,
        content: Text(
          _isPatrolInspection
              ? 'HOLD ISSUED: $plate ($reason)'
              : 'ENTRY BLOCKED: $plate ($reason)',
          style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_isValidating) {
      content = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: NcstColors.navy),
            SizedBox(height: 14),
            Text(
              'Verifying Vehicle State with Database...',
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
      final alreadyInside = _rejectionDetails!.type == ScanRejectionType.duplicateEntry && _rejectionDetails!.vehicle != null;
      content = ScanRejectionView(
        details: _rejectionDetails!,
        onScanAnother: _resetScanner,
        buttonLabel: 'SCAN ANOTHER VEHICLE',
        onInspect: (_rejectionDetails!.vehicle != null || _rejectionDetails!.visitor != null)
            ? _startPatrolInspection
            : null,
        inspectButtonLabel: 'INSPECT ON-CAMPUS VEHICLE / REPORT INCIDENT',
        onIssueViolation: alreadyInside ? _showIssueViolationDialog : null,
      );
    } else if (_scannedVehicle == null && _visitorPass == null) {
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
          : (_isPatrolInspection
              ? 'On-Campus Vehicle Inspection'
              : (_scannedVehicle == null && _visitorPass == null ? 'Scan Driver QR Pass' : 'Scanned Verification'))),
      backgroundColor: _rejectionDetails != null && _rejectionDetails!.type == ScanRejectionType.blocked
          ? NcstColors.crimson
          : NcstColors.navy,
      foregroundColor: NcstColors.white,
      actions: [
        if (_scannedVehicle == null && _rejectionDetails == null) ...[
          IconButton(
            tooltip: 'Enter QR Manually',
            icon: const Icon(Icons.keyboard_outlined, color: NcstColors.white),
            onPressed: _showManualQrInputDialog,
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
      onQrDetected: _processRawQrCode,
      onManualQrPressed: _showManualQrInputDialog,
      onFlipCameraPressed: () async {
        try {
          await _cameraController?.switchCamera();
        } catch (_) {}
      },
    );
  }

  Widget _buildInspectionNoticeHeader(String plate, String person) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: NcstColors.navy,
        border: Border(
          bottom: BorderSide(color: NcstColors.gold, width: 2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: NcstColors.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PATROL INSPECTION MODE (ON-CAMPUS VEHICLE)',
                  style: TextStyle(
                    color: NcstColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$plate ($person) is currently inside campus. Inspecting details will NOT record an entry or exit gate log.',
                  style: const TextStyle(
                    color: NcstColors.slate300,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionDecisionBar(String plate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: NcstColors.white,
        border: Border(top: BorderSide(color: NcstColors.slate200)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: OutlinedButton.icon(
                onPressed: _resetScanner,
                icon: const Icon(Icons.check_circle_outline_rounded, color: NcstColors.slate700, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'FINISH INSPECTION',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: NcstColors.slate800,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  side: const BorderSide(color: NcstColors.slate300, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: ElevatedButton.icon(
                onPressed: _showBlockDialog,
                icon: const Icon(Icons.report_problem_rounded, color: NcstColors.white, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'REPORT INCIDENT / HOLD',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: NcstColors.white,
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NcstColors.crimson,
                  foregroundColor: NcstColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitorBody(ScannedVisitorPass pass) {
    final allChecked = _visitorItemsAllChecked;
    return Column(
      children: [
        if (_isPatrolInspection)
          _buildInspectionNoticeHeader(pass.plateNumber, pass.visitorName),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ScannedVisitorCard(
                  pass: pass,
                  checkedItems: _checkedVisitorItems,
                  onToggleItem: _toggleVisitorItem,
                ),
              ),
            ),
          ),
        ),
        if (_isPatrolInspection)
          _buildInspectionDecisionBar(pass.plateNumber)
        else
          BottomDecisionBar(
            onBlock: _showBlockDialog,
            onCleared: _handleCleared,
            isClearedEnabled: pass.canAdmit && allChecked,
            clearedLabel: 'CLEARED (VISITOR)',
            disabledLabel: !pass.canAdmit
                ? 'ENTRY NOT ALLOWED'
                : 'TICK ITEMS (${_checkedVisitorItems.length}/${pass.items.length})',
          ),
      ],
    );
  }

  Widget _buildScannedVerificationBody() {
    if (_visitorPass != null) return _buildVisitorBody(_visitorPass!);
    final vehicle = _scannedVehicle!;
    final isDesktop = MediaQuery.of(context).size.width >= 880;

    return Column(
      children: [
        if (_isPatrolInspection)
          _buildInspectionNoticeHeader(vehicle.plateNumber, vehicle.ownerName),
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
        if (_isPatrolInspection)
          _buildInspectionDecisionBar(vehicle.plateNumber)
        else
          BottomDecisionBar(
            onBlock: _showBlockDialog,
            onCleared: _handleCleared,
            isClearedEnabled: (vehicle.isEligibleForEntry || vehicle.isUnregistered) && !_isSubmitting,
            clearedLabel: vehicle.isBlocked
                ? 'ACCESS DENIED (BLOCKED)'
                : (vehicle.isInsideCampus
                    ? 'ALREADY INSIDE'
                    : (vehicle.isUnregistered
                        ? 'REGISTER VISITOR'
                        : 'CLEARED (TO GO)')),
            disabledLabel: vehicle.isBlocked
                ? 'VEHICLE BLOCKED'
                : (vehicle.isInsideCampus ? 'ALREADY INSIDE CAMPUS' : null),
            clearedIcon: vehicle.isUnregistered
                ? Icons.how_to_reg_rounded
                : Icons.check_rounded,
            clearedColor: vehicle.isUnregistered
                ? NcstColors.goldDark
                : NcstColors.green,
          ),
      ],
    );
  }
}
