import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/widgets/driver_photo_view.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/user_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../models/visitor_pass_model.dart';
import '../../../repositories/gate_repository.dart';
import '../../../repositories/visitor_repository.dart';
import '../../../services/api_service.dart';
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
  VisitorPass? _verifiedVisitorPass;
  VehicleRecord? _verifiedVehicleRecord;
  String? _statusReason;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
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
      if (!_isVerifying && _resultStatus == null) {
        try {
          _cameraController?.start();
        } catch (_) {}
      }
    }
  }

  void _resetScanner() {
    setState(() {
      _resultStatus = null;
      _verifiedVisitorPass = null;
      _verifiedVehicleRecord = null;
      _statusReason = null;
      _isVerifying = false;
    });
    try {
      _cameraController?.start();
    } catch (_) {}
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

    // 1. First, check if it's a Temporary Visitor Pass
    final visitorPass = await VisitorRepository().lookupPass(clean);
    if (visitorPass != null) {
      _evaluateVisitorPass(visitorPass);
      return;
    }

    // 2. Second, check if it's a Registered Student / Faculty Vehicle
    var registeredVehicle = await ApiService.lookupVehicle(clean);
    if (registeredVehicle == null || !registeredVehicle.isParsedFromQr || registeredVehicle.ownerIdNumber == 'UNKNOWN') {
      registeredVehicle = GateRepository().resolveVehicle(clean);
    }
    if (registeredVehicle.isParsedFromQr && registeredVehicle.ownerIdNumber != 'UNKNOWN' && !registeredVehicle.ownerRole.contains('Guest')) {
      _evaluateRegisteredVehicle(registeredVehicle);
      return;
    }

    // 3. Fallback: Check if plate matches an active visitor pass
    final plateMatch = await VisitorRepository().lookupPass(clean);
    if (plateMatch != null) {
      _evaluateVisitorPass(plateMatch);
      return;
    }

    // 4. Invalid / Not Found State
    setState(() {
      _isVerifying = false;
      _resultStatus = ExitVerificationStatus.invalid;
      _statusReason = 'Pass code "$clean" could not be verified in the campus database.';
    });
  }

  void _evaluateVisitorPass(VisitorPass pass) {
    ExitVerificationStatus status;
    String? reason;

    if (pass.isBlocked) {
      status = ExitVerificationStatus.blocked;
      reason = pass.notes ?? 'Security Blacklist: Access hold active on this pass.';
    } else if (pass.isUsed) {
      status = ExitVerificationStatus.alreadyUsed;
      reason = 'This pass was already checked out at ${pass.exitTime != null ? DateTimeUtils.formatTime(pass.exitTime!) : 'earlier today'}.';
    } else if (pass.isExpired) {
      status = ExitVerificationStatus.expired;
      reason = 'Stay duration exceeded permitted 8-hour limit. Expired at ${DateTimeUtils.formatTime(pass.expiryTime)}.';
    } else {
      status = ExitVerificationStatus.valid;
    }

    setState(() {
      _isVerifying = false;
      _verifiedVisitorPass = pass;
      _resultStatus = status;
      _statusReason = reason;
    });
  }

  void _evaluateRegisteredVehicle(VehicleRecord vehicle) {
    ExitVerificationStatus status = ExitVerificationStatus.valid;
    String? reason;

    // Check if vehicle is flagged or blocked
    if (vehicle.hasActiveFlag) {
      // Vehicle is cleared for exit log, but flagged warning must be shown
      reason = vehicle.flagReason;
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

    if (_verifiedVisitorPass != null) {
      final pass = _verifiedVisitorPass!;
      await VisitorRepository().checkoutPass(pass.passId);

      exitEntry = AuditLogEntry(
        id: 'LOG-${now.millisecondsSinceEpoch}',
        plateNumber: pass.plateNumber,
        vehicleType: pass.vehicleModel ?? 'Visitor Vehicle',
        ownerName: pass.visitorName,
        driverName: pass.visitorName,
        driverRelationship: 'Visitor / Temporary Pass',
        timeIn: now,
        action: 'Exit Approved',
        status: GateStatus.exited,
      );

      await ApiService.postGateLog(
        plateNumber: pass.plateNumber,
        driverName: pass.visitorName,
        driverRelationship: 'Visitor / Temporary Pass',
        gatePoint: widget.currentGuard.assignedGate,
        action: 'Exit Approved',
        status: 'Departed Campus',
        guardName: widget.currentGuard.fullName,
        notes: 'Visitor pass ${pass.passId} checked out upon egress',
        vehicleType: 'Visitor Vehicle',
        ownerName: pass.visitorName,
      );
    } else if (_verifiedVehicleRecord != null) {
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
        status: 'Departed Campus',
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
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NcstColors.navyLight, width: 2),
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
                    _verifyPass(raw);
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
              border: Border.all(color: NcstColors.gold, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'ALIGN PASS QR CODE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
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

    final isVisitor = _verifiedVisitorPass != null;
    final isStudentOrFaculty = _verifiedVehicleRecord != null;
    final isFlagged = isStudentOrFaculty && _verifiedVehicleRecord!.hasActiveFlag;

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

          // Person / Vehicle Details
          if (isVisitor) ...[
            _buildVisitorDossier(_verifiedVisitorPass!),
          ] else if (isStudentOrFaculty) ...[
            _buildVehicleDossier(_verifiedVehicleRecord!),
          ],

          const SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetScanner,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NcstColors.green,
                      foregroundColor: NcstColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorDossier(VisitorPass pass) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vehicle Picture or Placeholder
            if (pass.vehiclePhotoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  pass.vehiclePhotoUrl!,
                  width: 80,
                  height: 70,
                  cacheWidth: 160,
                  cacheHeight: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildPlaceholderPhoto(),
                ),
              )
            else
              _buildPlaceholderPhoto(),
            const SizedBox(width: 12),

            // Visitor Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VISITOR / GUEST PASS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: NcstColors.navy,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    pass.visitorName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: NcstColors.slate900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PlateBadge(plateNumber: pass.plateNumber),
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
              _buildRow('Pass ID:', pass.passId),
              _buildRow('Entry Time:', DateTimeUtils.formatTime(pass.entryTime)),
              _buildRow('Validity:', DateTimeUtils.formatTime(pass.expiryTime)),
              _buildRow('Current Status:', pass.statusDisplay),
            ],
          ),
        ),
      ],
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
                'Exit Clearance Instructions',
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
            'Present driver QR code decal or visitor temporary pass to the camera. The system automatically inspects pass status, entry duration, and clearance to exit.',
            style: TextStyle(fontSize: 11.5, color: NcstColors.slate600, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ManualQrDialog.show(context, _verifyPass),
              icon: const Icon(Icons.keyboard_outlined, size: 18),
              label: const Text('ENTER PASS / PLATE MANUALLY'),
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
