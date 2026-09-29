import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/widgets/driver_photo_view.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/user_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../services/api_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../theme/ncst_theme.dart';
import '../dialogs/manual_qr_dialog.dart';

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

  const ExitScannerScreen({
    super.key,
    required this.currentGuard,
    this.onDecision,
    this.onReturnToDashboard,
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
  ExitVerificationStatus? _resultStatus;
  VehicleRecord? _verifiedVehicleRecord;
  String? _statusReason;

  // Camera Stabilization State
  String? _candidateExitQr;
  DateTime? _candidateExitStartTime;
  DateTime? _lastSeenExitTime;
  double _exitStabilizationProgress = 0.0;
  Timer? _exitStabilizationTicker;
  bool _isExitStabilizing = false;
  bool _isExitLocked = false;
  bool _exitSteadyMode = true;
  String _exitStatusPrompt = 'Align QR code inside frame';
  final Duration _stabilizationDuration = const Duration(milliseconds: 900);

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
    _exitStabilizationTicker?.cancel();
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
      if (!_isVerifying && _resultStatus == null) {
        try {
          _cameraController?.start();
        } catch (_) {}
      }
    }
  }

  void _resetScanner() {
    _exitStabilizationTicker?.cancel();
    setState(() {
      _resultStatus = null;
      _verifiedVehicleRecord = null;
      _statusReason = null;
      _isVerifying = false;
      _candidateExitQr = null;
      _candidateExitStartTime = null;
      _lastSeenExitTime = null;
      _exitStabilizationProgress = 0.0;
      _isExitStabilizing = false;
      _isExitLocked = false;
      _exitStatusPrompt = 'Align QR code inside frame';
    });
    try {
      _cameraController?.start();
    } catch (_) {}
  }

  void _handleExitBarcodeDetect(String raw) {
    if (_isExitLocked || _isVerifying || _resultStatus != null) return;

    if (!_exitSteadyMode) {
      _isExitLocked = true;
      _verifyPass(raw);
      return;
    }

    final now = DateTime.now();
    if (_candidateExitQr != raw) {
      _candidateExitQr = raw;
      _candidateExitStartTime = now;
      _lastSeenExitTime = now;
      _exitStabilizationProgress = 0.0;
      _isExitStabilizing = true;
      _exitStatusPrompt = 'HOLD CAMERA STEADY...';
      _startExitStabilizationTimer();
      if (mounted) setState(() {});
    } else {
      _lastSeenExitTime = now;
    }
  }

  void _startExitStabilizationTimer() {
    _exitStabilizationTicker?.cancel();
    final targetMs = _stabilizationDuration.inMilliseconds;
    const intervalMs = 30;

    _exitStabilizationTicker = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_candidateExitQr == null || _candidateExitStartTime == null || _lastSeenExitTime == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      // Check if camera moved away (no detection heartbeat for > 400ms)
      if (now.difference(_lastSeenExitTime!).inMilliseconds > 400) {
        timer.cancel();
        setState(() {
          _candidateExitQr = null;
          _candidateExitStartTime = null;
          _isExitStabilizing = false;
          _exitStabilizationProgress = 0.0;
          _exitStatusPrompt = 'Camera moved • Hold steady to scan';
        });
        return;
      }

      final elapsedMs = now.difference(_candidateExitStartTime!).inMilliseconds;
      final progress = (elapsedMs / targetMs).clamp(0.0, 1.0);

      if (progress >= 1.0) {
        timer.cancel();
        final capturedCode = _candidateExitQr!;
        setState(() {
          _exitStabilizationProgress = 1.0;
          _isExitStabilizing = false;
          _isExitLocked = true;
          _exitStatusPrompt = '✓ CAMERA STABILIZED • QR LOCKED';
        });

        Future.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          _verifyPass(capturedCode);
        });
      } else {
        setState(() {
          _exitStabilizationProgress = progress;
          _exitStatusPrompt = 'Hold steady... ${(progress * 100).toInt()}%';
        });
      }
    });
  }

  /// Evaluates scanned QR code against the 6 verification criteria
  Future<void> _verifyPass(String raw) async {
    if (_isVerifying || _resultStatus != null) return;

    setState(() {
      _isVerifying = true;
    });

    try {
      _cameraController?.stop();
    } catch (_) {}

    final clean = raw.trim();

    // Verify Registered Student / Faculty / Employee Vehicle
    var registeredVehicle = await ApiService.lookupVehicle(clean);
    if (registeredVehicle == null || !registeredVehicle.isParsedFromQr || registeredVehicle.ownerIdNumber == 'UNKNOWN') {
      registeredVehicle = GateRepository().resolveVehicle(clean);
    }
    if (registeredVehicle == null || registeredVehicle.ownerIdNumber == 'UNKNOWN') {
      final verifyResult = await ApiService.verifyPassWithServer(qrCode: clean, plate: clean, gateType: 'Egress');
      if (verifyResult != null && verifyResult['vehicle'] is Map<String, dynamic>) {
        registeredVehicle = VehicleRecord.fromQrJson(
          verifyResult['vehicle'] as Map<String, dynamic>,
          rawPayload: clean,
          isSyncedWithDb: true,
        );
      }
    }
    if (registeredVehicle != null && registeredVehicle.isParsedFromQr && registeredVehicle.ownerIdNumber != 'UNKNOWN' && !registeredVehicle.ownerRole.contains('Guest')) {
      _evaluateRegisteredVehicle(registeredVehicle);
      return;
    }

    // Invalid / Unrecognized QR State (Guard 2 is for registered vehicles only)
    setState(() {
      _isVerifying = false;
      _resultStatus = ExitVerificationStatus.invalid;
      _statusReason = 'Pass code "$clean" is not a registered vehicle QR pass. Guard 2 scans registered campus vehicles only.';
    });
  }

  void _evaluateRegisteredVehicle(VehicleRecord vehicle) {
    ExitVerificationStatus status = ExitVerificationStatus.valid;
    String? reason;

    if (vehicle.isAccessDenied) {
      status = ExitVerificationStatus.valid;
      reason = 'HOLD ALERT: Vehicle is banned/suspended. Exit allowed to clear campus, but incident must be reported.';
    } else if (vehicle.campusStatus != null &&
        vehicle.campusStatus!.toLowerCase().contains('outside')) {
      reason = 'ATTENTION: No entry record found today — this vehicle was not recorded as inside campus.';
    } else if (vehicle.hasActiveFlag) {
      // Vehicle is cleared for exit log, but flagged warning must be shown
      reason = 'FLAGGED VEHICLE: ${vehicle.flagReason ?? "Security flag active"}';
    }

    setState(() {
      _isVerifying = false;
      _verifiedVehicleRecord = vehicle;
      _resultStatus = status;
      _statusReason = reason;
    });
  }

  Future<void> _handleConfirmExit() async {
    final now = DateTime.now();
    AuditLogEntry? exitEntry;

    if (_verifiedVehicleRecord != null) {
      final v = _verifiedVehicleRecord!;
      final driver = v.authorizedDrivers.isNotEmpty ? v.authorizedDrivers.first.fullName : v.ownerName;
      final rel = v.authorizedDrivers.isNotEmpty ? v.authorizedDrivers.first.relationship : 'Self (Owner)';

      exitEntry = AuditLogEntry(
        id: 'LOG-${now.millisecondsSinceEpoch}',
        plateNumber: v.plateNumber,
        vehicleType: v.vehicleType,
        ownerName: v.ownerName,
        driverName: driver,
        driverRelationship: rel,
        timeIn: now,
        action: 'Exit Approved',
        status: GateStatus.exited,
        blockReason: v.hasActiveFlag ? 'FLAGGED EXIT RECORDED: ${v.flagReason}' : null,
      );

      await ApiService.postGateLog(
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
      );
    }

    if (exitEntry != null) {
      widget.onDecision?.call(exitEntry);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle exit confirmed and logged to server.'),
          backgroundColor: NcstColors.green,
          duration: Duration(seconds: 2),
        ),
      );
      if (widget.onReturnToDashboard != null) {
        widget.onReturnToDashboard!();
      } else {
        _resetScanner();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 360;

    return Scaffold(
      backgroundColor: NcstColors.slate100,
      appBar: AppBar(
        title: const Text('Exit Pass Scanner'),
        backgroundColor: NcstColors.navy,
        foregroundColor: NcstColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'Enter QR Manually',
            onPressed: () => ManualQrDialog.show(context, _verifyPass),
          ),
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Toggle Flashlight',
            onPressed: () {
              try {
                _cameraController?.toggleTorch();
                setState(() {
                  _isTorchOn = !_isTorchOn;
                });
              } catch (_) {}
            },
          ),
          if (widget.onReturnToDashboard != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onReturnToDashboard,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Camera Viewfinder Box (or Camera Error)
                  _buildCameraViewfinder(isCompact),
                  const SizedBox(height: 14),

                  // Verification Result Dossier
                  if (_resultStatus != null) ...[
                    _buildVerificationResultCard(isCompact),
                    const SizedBox(height: 16),
                  ],

                  // Production Scanner Clearance Guidance
                  _buildScannerHelperCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraViewfinder(bool isCompact) {
    Color borderColor;
    if (_isExitLocked) {
      borderColor = NcstColors.green;
    } else if (_isExitStabilizing) {
      borderColor = const Color(0xFF38BDF8);
    } else {
      borderColor = NcstColors.navyLight;
    }

    return Column(
      children: [
        Container(
          height: 205,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: _isExitStabilizing || _isExitLocked ? 2.5 : 2.0,
            ),
            boxShadow: _isExitStabilizing
                ? [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!_cameraHasError && _cameraController != null)
                MobileScanner(
                  controller: _cameraController!,
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final raw = barcodes.first.rawValue;
                      if (raw != null && raw.isNotEmpty) {
                        _handleExitBarcodeDetect(raw);
                      }
                    }
                  },
                )
              else
                const Center(
                  child: Icon(Icons.qr_code_scanner, size: 64, color: NcstColors.slate400),
                ),

              // Reticle Viewport
              Container(
                width: 220,
                height: 130,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isExitLocked
                        ? NcstColors.green
                        : (_isExitStabilizing ? const Color(0xFF38BDF8) : NcstColors.gold),
                    width: _isExitStabilizing ? 2.5 : 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: _isExitStabilizing
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'STABILIZING CAMERA (${(_exitStabilizationProgress * 100).toInt()}%)',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        )
                      : (_isExitLocked
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, color: NcstColors.green, size: 26),
                                SizedBox(height: 4),
                                Text(
                                  'QR CODE LOCKED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: NcstColors.green,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'ALIGN PASS QR CODE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            )),
                ),
              ),

              // Top HUD Banner with prompt & progress
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isExitLocked
                        ? NcstColors.green.withValues(alpha: 0.92)
                        : (_isExitStabilizing
                            ? const Color(0xFF0369A1).withValues(alpha: 0.92)
                            : Colors.black.withValues(alpha: 0.65)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isExitLocked
                          ? Colors.white
                          : (_isExitStabilizing ? const Color(0xFF38BDF8) : Colors.white24),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isExitStabilizing) ...[
                        const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else if (_isExitLocked) ...[
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 13),
                        const SizedBox(width: 5),
                      ] else ...[
                        const Icon(Icons.center_focus_strong, color: Colors.white70, size: 12),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          _exitStatusPrompt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Linear Progress Bar at bottom of viewfinder
              if (_isExitStabilizing)
                Positioned(
                  bottom: 12,
                  left: 24,
                  right: 24,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _exitStabilizationProgress,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                      minHeight: 4,
                    ),
                  ),
                ),

              if (_isVerifying)
                Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: NcstColors.gold),
                        SizedBox(height: 10),
                        Text(
                          'VERIFYING PASS ON SERVER...',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Guard Stabilization Mode Toggle Pill
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _exitSteadyMode = !_exitSteadyMode;
                  _exitStabilizationTicker?.cancel();
                  _isExitStabilizing = false;
                  _candidateExitQr = null;
                  _candidateExitStartTime = null;
                  _lastSeenExitTime = null;
                  _exitStabilizationProgress = 0.0;
                  _exitStatusPrompt = _exitSteadyMode ? 'Align QR code inside frame' : 'Instant detection active';
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _exitSteadyMode ? const Color(0xFFE0F2FE) : NcstColors.slate200,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _exitSteadyMode ? const Color(0xFF0284C7) : NcstColors.slate300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _exitSteadyMode ? Icons.motion_photos_paused_rounded : Icons.flash_on_rounded,
                      size: 13,
                      color: _exitSteadyMode ? const Color(0xFF0369A1) : NcstColors.slate600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _exitSteadyMode ? 'Camera Steady Hold: ON (~0.9s)' : 'Instant Detection: ON',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _exitSteadyMode ? const Color(0xFF0369A1) : NcstColors.slate700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVerificationResultCard(bool isCompact) {
    Color bannerColor;
    Color textColor;
    IconData icon;
    String statusTitle;

    switch (_resultStatus!) {
      case ExitVerificationStatus.valid:
        bannerColor = NcstColors.greenLight;
        textColor = NcstColors.green;
        icon = Icons.check_circle_rounded;
        statusTitle = 'VALID — CLEARED FOR EXIT';
        break;
      case ExitVerificationStatus.blocked:
        bannerColor = NcstColors.crimsonLight;
        textColor = NcstColors.crimson;
        icon = Icons.block_rounded;
        statusTitle = 'PASS BLOCKED — ACCESS HOLD';
        break;
      case ExitVerificationStatus.expired:
        bannerColor = NcstColors.crimsonLight;
        textColor = NcstColors.crimson;
        icon = Icons.timer_off_rounded;
        statusTitle = 'PASS EXPIRED — OVERTIME STAY';
        break;
      case ExitVerificationStatus.alreadyUsed:
        bannerColor = NcstColors.slate200;
        textColor = NcstColors.slate800;
        icon = Icons.history_rounded;
        statusTitle = 'ALREADY CHECKED OUT';
        break;
      case ExitVerificationStatus.invalid:
        bannerColor = NcstColors.crimsonLight;
        textColor = NcstColors.crimson;
        icon = Icons.help_outline_rounded;
        statusTitle = 'UNRECOGNIZED / INVALID QR';
        break;
    }

    final isFlagged = _verifiedVehicleRecord != null && _verifiedVehicleRecord!.hasActiveFlag;

    return Container(
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(isCompact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bannerColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, color: textColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // If Flagged Student/Employee: Show Prominent Flag Alert Banner!
          if (isFlagged) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NcstColors.crimsonLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NcstColors.crimson, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: NcstColors.crimson, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'FLAGGED ${_verifiedVehicleRecord!.categoryDisplay.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: NcstColors.crimson,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Infraction: ${_verifiedVehicleRecord!.flagReason ?? "Security flag active"}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NcstColors.slate800,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_statusReason != null && !isFlagged) ...[
            const SizedBox(height: 10),
            Text(
              _statusReason!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: NcstColors.slate700,
              ),
            ),
          ],
          const Divider(height: 24),

          // Registered Vehicle Details
          if (_verifiedVehicleRecord != null) ...[
            _buildVehicleDossier(_verifiedVehicleRecord!),
          ],
          const SizedBox(height: 16),
          // Action Buttons: Scan Another & Confirm Exit
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetScanner,
                  child: const Text('SCAN ANOTHER'),
                ),
              ),
              if (_resultStatus == ExitVerificationStatus.valid) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _handleConfirmExit,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('CONFIRM EXIT'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDossier(VehicleRecord v) {
    final driver = v.authorizedDrivers.isNotEmpty ? v.authorizedDrivers.first : null;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DriverPhotoView(
              photoUrl: driver?.photoUrl ?? v.ownerPhotoUrl ?? '',
              size: 72,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.categoryDisplay.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: NcstColors.navy,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    driver?.fullName ?? v.ownerName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: NcstColors.slate900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v.makeModelColor,
                    style: const TextStyle(fontSize: 11, color: NcstColors.slate600),
                  ),
                  const SizedBox(height: 4),
                  PlateBadge(plateNumber: v.plateNumber),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NcstColors.slate50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildRow('Owner ID:', v.ownerIdNumber),
              _buildRow('Sticker Year:', '2026 Active'),
              _buildRow('User Role:', v.ownerRole),
              if (v.hasActiveFlag)
                _buildRow('Flag Status:', 'FLAGGED ON CAMPUS', textColor: NcstColors.crimson),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      width: 80,
      height: 70,
      decoration: BoxDecoration(
        color: NcstColors.slate200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(Icons.directions_car, color: NcstColors.slate500, size: 28),
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: NcstColors.slate600)),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor ?? NcstColors.slate900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerHelperCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NcstColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.qr_code_scanner, size: 18, color: NcstColors.navy),
              SizedBox(width: 8),
              Text(
                'Vehicle Exit Clearance Instructions',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: NcstColors.navyDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Present registered vehicle QR pass decal to the camera. The system verifies student/faculty registration, active status, driver credentials, and logs campus exit.',
            style: TextStyle(fontSize: 11.5, color: NcstColors.slate600, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ManualQrDialog.show(context, _verifyPass),
              icon: const Icon(Icons.keyboard_outlined, size: 18),
              label: const Text('ENTER VEHICLE PLATE / QR MANUALLY'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NcstColors.navy,
                side: const BorderSide(color: NcstColors.navy),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
