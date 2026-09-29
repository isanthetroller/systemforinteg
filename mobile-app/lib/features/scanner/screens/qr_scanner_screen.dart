import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../data/mock_data.dart';
import '../../../models/user_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../services/api_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../theme/ncst_theme.dart';
import '../../visitor/screens/visitor_registration_screen.dart';
import '../dialogs/block_reason_dialog.dart';
import '../dialogs/manual_qr_dialog.dart';
import '../widgets/authorized_drivers_card.dart';
import '../widgets/bottom_decision_bar.dart';
import '../widgets/camera_viewfinder.dart';
import '../widgets/scanned_person_card.dart';

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

  VehicleRecord? _scannedVehicle;
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
      try {
        _cameraController?.stop();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      if (_scannedVehicle == null) {
        try {
          _cameraController?.start();
        } catch (_) {}
      }
    }
  }

  void _onQrDetected(VehicleRecord vehicle) {
    // Cut camera native buffer and memory usage immediately upon successful scan
    try {
      _cameraController?.stop();
    } catch (_) {}
    setState(() {
      _scannedVehicle = vehicle;
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
    });
    try {
      _cameraController?.start();
    } catch (_) {}
  }

  void _processRawQrCode(String raw) async {
    if (_scannedVehicle != null) return;
    var vehicle = widget.repository.resolveVehicle(raw);
    _onQrDetected(vehicle);

    // Fetch the updated information from the database
    // Even if an old QR code was scanned, the app connects to the database to fetch
    // the newest vehicle/owner/driver information and displays it while preserving the sticker year
    await _syncVehicleWithDb(vehicle, raw);
  }

  Future<void> _syncVehicleWithDb(VehicleRecord vehicle, [String? raw]) async {
    try {
      final verifyFuture = ApiService.verifyPassWithServer(
        qrCode: raw,
        plate: vehicle.plateNumber,
        gateType: 'Ingress',
      );
      final lookupPlateFuture = ApiService.lookupVehicleByPlate(vehicle.plateNumber);
      final lookupRawFuture = (raw != null && raw.isNotEmpty) ? ApiService.lookupVehicle(raw) : Future<VehicleRecord?>.value(null);

      final verifyResult = await verifyFuture;
      VehicleRecord? remoteVehicle = (await lookupPlateFuture) ?? (await lookupRawFuture);

      // If direct vehicle lookup didn't find the vehicle or timed out, but verifyPassWithServer
      // returned the vehicle object, parse it directly from verifyResult
      if (remoteVehicle == null && verifyResult != null) {
        final serverVeh = verifyResult['vehicle'] ?? verifyResult['data']?['vehicle'];
        if (serverVeh is Map<String, dynamic>) {
          try {
            remoteVehicle = VehicleRecord.fromQrJson(
              serverVeh,
              rawPayload: raw ?? 'SERVER_VERIFY_RECORD',
              isSyncedWithDb: true,
            );
          } catch (e) {
            debugPrint('[QrScannerScreen] Parse vehicle from verifyResult: $e');
          }
        }
      }

      if (mounted && (_scannedVehicle == null || _scannedVehicle?.plateNumber == vehicle.plateNumber)) {
        final vData = (verifyResult != null && verifyResult['data'] is Map<String, dynamic>)
            ? (verifyResult['data'] as Map<String, dynamic>)
            : verifyResult;

        final isServerBanned = vData != null &&
            (vData['result'] == 'BANNED' ||
             vData['result'] == 'SUSPENDED' ||
             vData['result'] == 'FORGED' ||
             vData['result'] == 'REVOKED' ||
             (vData['accepted'] == false && (vData['message']?.toString().toUpperCase().contains('BAN') == true)));

        final serverReason = vData?['reason']?.toString() ?? vData?['message']?.toString();
        final serverCampusStatus = vData?['result']?.toString() ?? remoteVehicle?.campusStatus;
        final isAntiPassback = (vData != null && vData['currentlyInside'] == true) ||
            (remoteVehicle != null && remoteVehicle.isAntiPassback);

        if (remoteVehicle != null) {
          final enriched = VehicleRecord(
            plateNumber: remoteVehicle.plateNumber.isNotEmpty ? remoteVehicle.plateNumber : vehicle.plateNumber,
            vehicleType: remoteVehicle.vehicleType.isNotEmpty ? remoteVehicle.vehicleType : vehicle.vehicleType,
            makeModelColor: remoteVehicle.makeModelColor.isNotEmpty ? remoteVehicle.makeModelColor : vehicle.makeModelColor,
            ownerName: remoteVehicle.ownerName.isNotEmpty ? remoteVehicle.ownerName : vehicle.ownerName,
            ownerRole: remoteVehicle.ownerRole.isNotEmpty ? remoteVehicle.ownerRole : vehicle.ownerRole,
            ownerIdNumber: remoteVehicle.ownerIdNumber.isNotEmpty && remoteVehicle.ownerIdNumber != 'UNKNOWN'
                ? remoteVehicle.ownerIdNumber
                : (vehicle.ownerIdNumber != 'UNKNOWN' ? vehicle.ownerIdNumber : 'CAMPUS-USER'),
            ownerPhotoUrl: (remoteVehicle.ownerPhotoUrl != null && remoteVehicle.ownerPhotoUrl!.isNotEmpty)
                ? remoteVehicle.ownerPhotoUrl
                : vehicle.ownerPhotoUrl,
            qrPassCode: vehicle.qrPassCode.isNotEmpty ? vehicle.qrPassCode : remoteVehicle.qrPassCode,
            // Preserves the physical sticker year from the pass (e.g. 2026), or defaults to remote
            stickerYear: vehicle.stickerYear.isNotEmpty ? vehicle.stickerYear : remoteVehicle.stickerYear,
            vehiclePicture: remoteVehicle.vehiclePicture ?? vehicle.vehiclePicture,
            authorizedDrivers: remoteVehicle.authorizedDrivers.isNotEmpty
                ? remoteVehicle.authorizedDrivers
                : vehicle.authorizedDrivers,
            isParsedFromQr: true,
            rawQrPayload: raw ?? vehicle.rawQrPayload,
            isSyncedWithDb: true,
            category: remoteVehicle.category,
            isFlagged: remoteVehicle.isFlagged,
            flagReason: remoteVehicle.flagReason ?? serverReason,
            flaggedAt: remoteVehicle.flaggedAt,
            isBanned: remoteVehicle.isBanned || isServerBanned,
            campusStatus: serverCampusStatus,
            isAntiPassback: isAntiPassback,
          );

          MockData.upsertVehicle(enriched);
          LocalCacheService.upsertVehicle(enriched);

          setState(() {
            _scannedVehicle = enriched;

            final wasOwnerSelected = _selectedDriverName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
                _selectedRelationship.toLowerCase().contains('self') ||
                _selectedRelationship.toLowerCase().contains('owner') ||
                _selectedRelationship.toLowerCase().contains('visitor') ||
                _selectedRelationship.toLowerCase().contains('driver');

            if (wasOwnerSelected || enriched.authorizedDrivers.isEmpty) {
              _selectedDriverName = enriched.ownerName;
              _selectedRelationship = 'Self (Owner)';
              _currentPhotoUrl = enriched.ownerPhotoUrl ?? '';
            } else {
              // Check if currently selected driver exists in the enriched driver roster
              final matched = enriched.authorizedDrivers.cast<AuthorizedDriver?>().firstWhere(
                (d) => d?.fullName.trim().toLowerCase() == _selectedDriverName.trim().toLowerCase(),
                orElse: () => null,
              );
              if (matched != null) {
                _selectedDriverName = matched.fullName;
                _selectedRelationship = matched.relationship;
                _currentPhotoUrl = (matched.photoUrl != null && matched.photoUrl!.isNotEmpty)
                    ? matched.photoUrl!
                    : (enriched.ownerPhotoUrl ?? '');
              } else if (enriched.authorizedDrivers.isNotEmpty) {
                final first = enriched.authorizedDrivers.first;
                _selectedDriverName = first.fullName;
                _selectedRelationship = first.relationship;
                _currentPhotoUrl = (first.photoUrl != null && first.photoUrl!.isNotEmpty)
                    ? first.photoUrl!
                    : (enriched.ownerPhotoUrl ?? '');
              } else {
                _selectedDriverName = enriched.ownerName;
                _selectedRelationship = 'Registered Owner';
                _currentPhotoUrl = enriched.ownerPhotoUrl ?? '';
              }
            }
          });
        } else if (verifyResult != null) {
          setState(() {
            _scannedVehicle = _scannedVehicle?.copyWith(
              isBanned: isServerBanned,
              campusStatus: serverCampusStatus,
              isAntiPassback: isAntiPassback,
              flagReason: serverReason,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('[QrScannerScreen] Database sync note: $e');
    }
  }

  void _showManualQrInputDialog() {
    ManualQrDialog.show(context, _processRawQrCode);
  }

  void _handleCleared() async {
    if (_scannedVehicle == null) return;
    final vehicle = _scannedVehicle!;

    // 1. Guard against Banned / Suspended / Denied vehicles
    if (vehicle.isAccessDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text(
            'ENTRY DENIED: ${vehicle.plateNumber} is banned or suspended. You must block this vehicle.',
            style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
    ).then((recorded) {
      if (recorded) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: NcstColors.crimson,
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          content: Text(
            'NOT RECORDED: $plateForLog was refused by the server (${ApiService.lastWriteError ?? 'no reason given'}). '
            'Do not admit this vehicle; contact the security office.',
            style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
          ),
        ),
      );
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
      if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else if (widget.onReturnToDashboard != null) {
        widget.onReturnToDashboard!();
      }
    }
  }

  void _showBlockDialog() {
    if (_scannedVehicle == null) return;
    BlockReasonDialog.show(context, _executeBlock);
  }

  void _executeBlock(String reason) {
    if (_scannedVehicle == null) return;

    final blockedEntry = AuditLogEntry(
      id: 'LOG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      plateNumber: _scannedVehicle!.plateNumber,
      vehicleType: _scannedVehicle!.vehicleType,
      ownerName: _scannedVehicle!.ownerName,
      driverName: _selectedDriverName,
      driverRelationship: _selectedRelationship,
      timeIn: DateTime.now(),
      status: GateStatus.blocked,
      blockReason: reason,
    );

    widget.onDecision(blockedEntry);

    // Asynchronously synchronize blocked event with InfinityFree MySQL Backend API
    ApiService.postGateLog(
      plateNumber: _scannedVehicle!.plateNumber,
      driverName: _selectedDriverName,
      driverRelationship: _selectedRelationship,
      gatePoint: 'Gate 1 (Main Ingress)',
      action: 'Entry Denied',
      status: 'Blocked',
      notes: reason,
      vehicleType: _scannedVehicle!.vehicleType,
      ownerName: _scannedVehicle!.ownerName,
    );
    ApiService.reportIncident(
      plateNumber: _scannedVehicle!.plateNumber,
      driverName: _selectedDriverName,
      reason: reason,
      gatePoint: 'Gate 1 (Main Ingress)',
      notes: 'Entry blocked at gate verification',
    );
    if (!widget.isEmbedded && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    } else if (widget.onReturnToDashboard != null) {
      widget.onReturnToDashboard!();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.crimson,
        content: Text(
          'ENTRY BLOCKED: ${_scannedVehicle!.plateNumber} ($reason)',
          style: const TextStyle(fontWeight: FontWeight.w700, color: NcstColors.white),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _scannedVehicle == null
        ? _buildViewfinderSection()
        : _buildScannedVerificationBody();

    final appBar = AppBar(
      leading: (widget.isEmbedded && widget.onReturnToDashboard != null)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Dashboard',
              onPressed: widget.onReturnToDashboard,
            )
          : null,
      title: Text(_scannedVehicle == null ? 'Scan Driver QR Pass' : 'Scanned Verification'),
      actions: [
        if (_scannedVehicle == null) ...[
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

  Widget _buildScannedVerificationBody() {
    final vehicle = _scannedVehicle!;
    final isDesktop = MediaQuery.of(context).size.width >= 880;

    return Column(
      children: [
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
          onCleared: _handleCleared,
          isClearedEnabled: !vehicle.isAccessDenied,
          clearedLabel: vehicle.isAccessDenied
              ? 'ACCESS DENIED (BANNED)'
              : (vehicle.isUnregistered
                  ? 'REGISTER VISITOR'
                  : 'CLEARED (TO GO)'),
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
