import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../theme/ncst_theme.dart';
import 'qr_scanner_overlay_painter.dart';

class CameraViewfinder extends StatefulWidget {
  final MobileScannerController? cameraController;
  final bool cameraHasError;
  final ValueChanged<String> onQrDetected;
  final VoidCallback onManualQrPressed;
  final VoidCallback onFlipCameraPressed;
  final Duration stabilizationDuration;

  const CameraViewfinder({
    super.key,
    required this.cameraController,
    required this.cameraHasError,
    required this.onQrDetected,
    required this.onManualQrPressed,
    required this.onFlipCameraPressed,
    this.stabilizationDuration = const Duration(milliseconds: 900),
  });

  @override
  State<CameraViewfinder> createState() => _CameraViewfinderState();
}

class _CameraViewfinderState extends State<CameraViewfinder> {
  String? _candidateQr;
  DateTime? _candidateStartTime;
  DateTime? _lastSeenTime;
  double _stabilizationProgress = 0.0;
  Timer? _ticker;
  bool _isStabilizing = false;
  bool _isLocked = false;
  bool _steadyScanEnabled = true;
  String _statusPrompt = 'Align QR code inside frame';

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_isLocked) return;

    String? raw;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
        raw = barcode.rawValue!.trim();
        break;
      }
    }
    if (raw == null) return;

    if (!_steadyScanEnabled) {
      _isLocked = true;
      widget.onQrDetected(raw);
      return;
    }

    final now = DateTime.now();
    if (_candidateQr != raw) {
      // First detection or new QR code entering frame
      _candidateQr = raw;
      _candidateStartTime = now;
      _lastSeenTime = now;
      _stabilizationProgress = 0.0;
      _isStabilizing = true;
      _statusPrompt = 'HOLD CAMERA STEADY...';
      _startStabilizationTimer();
      if (mounted) setState(() {});
    } else {
      // Heartbeat: same QR code is still detected in camera view
      _lastSeenTime = now;
    }
  }

  void _startStabilizationTimer() {
    _ticker?.cancel();
    final targetMs = widget.stabilizationDuration.inMilliseconds;
    const intervalMs = 30;

    _ticker = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_candidateQr == null || _candidateStartTime == null || _lastSeenTime == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();

      // Check if camera moved away (no detection frame received for > 400ms)
      if (now.difference(_lastSeenTime!).inMilliseconds > 400) {
        timer.cancel();
        setState(() {
          _candidateQr = null;
          _candidateStartTime = null;
          _isStabilizing = false;
          _stabilizationProgress = 0.0;
          _statusPrompt = 'Camera moved • Hold steady to scan';
        });
        return;
      }

      final elapsedMs = now.difference(_candidateStartTime!).inMilliseconds;
      final progress = (elapsedMs / targetMs).clamp(0.0, 1.0);

      if (progress >= 1.0) {
        timer.cancel();
        final capturedCode = _candidateQr!;
        setState(() {
          _stabilizationProgress = 1.0;
          _isStabilizing = false;
          _isLocked = true;
          _statusPrompt = '✓ CAMERA STABILIZED • QR LOCKED';
        });

        // 120ms visual confirmation delay before triggering processing
        Future.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          widget.onQrDetected(capturedCode);
        });
      } else {
        setState(() {
          _stabilizationProgress = progress;
          _statusPrompt = 'Hold steady... ${(progress * 100).toInt()}%';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscapeShort = screenHeight < 500;
    final boxSize = isLandscapeShort ? 170.0 : 220.0;

    return Container(
      color: NcstColors.slate50,
      child: Column(
        children: [
          // 1. Camera Status header (Clean white background)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: const BoxDecoration(
              color: NcstColors.white,
              border: Border(
                bottom: BorderSide(color: NcstColors.slate200, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isLocked
                              ? NcstColors.green
                              : (_isStabilizing ? const Color(0xFF0284C7) : NcstColors.green),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _isLocked
                              ? 'QR PASS LOCKED ✓'
                              : (_isStabilizing ? 'STABILIZING FOCUS...' : 'CAMERA AUTO-SCAN ACTIVE'),
                          style: TextStyle(
                            color: _isLocked
                                ? NcstColors.greenDark
                                : (_isStabilizing ? const Color(0xFF0369A1) : NcstColors.navy),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (screenWidth >= 380) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _steadyScanEnabled
                          ? NcstColors.navy.withValues(alpha: 0.08)
                          : NcstColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _steadyScanEnabled
                            ? NcstColors.navy.withValues(alpha: 0.2)
                            : NcstColors.goldDark.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _steadyScanEnabled ? 'STEADY-HOLD PROTECT' : 'INSTANT SCAN',
                      style: TextStyle(
                        color: _steadyScanEnabled ? NcstColors.navy : NcstColors.goldDark,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 2. Central Viewfinder Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Scanner Card Frame
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: boxSize,
                      height: boxSize,
                      decoration: BoxDecoration(
                        color: NcstColors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isLocked
                              ? NcstColors.green
                              : (_isStabilizing ? const Color(0xFF0284C7) : NcstColors.slate200),
                          width: (_isStabilizing || _isLocked) ? 3 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isLocked
                                ? NcstColors.green.withValues(alpha: 0.25)
                                : (_isStabilizing
                                    ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.06)),
                            blurRadius: (_isStabilizing || _isLocked) ? 20 : 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (widget.cameraController != null && !widget.cameraHasError)
                            MobileScanner(
                              controller: widget.cameraController,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error) {
                                return _buildSimulatedViewport();
                              },
                              onDetect: _handleDetect,
                            )
                          else
                            _buildSimulatedViewport(),

                          // Alignment guide brackets
                          CustomPaint(
                            size: Size(boxSize - 40, boxSize - 40),
                            painter: const QrScannerOverlayPainter(),
                          ),

                          // Floating HUD Banner when stabilizing camera
                          if (_isStabilizing)
                            Positioned(
                              top: 10,
                              left: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        value: _stabilizationProgress,
                                        strokeWidth: 2.2,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'HOLD CAMERA STEADY',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10.5,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Success confirmation lock overlay
                          if (_isLocked)
                            Container(
                              color: Colors.black.withValues(alpha: 0.7),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: NcstColors.green,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, color: Colors.white, size: 28),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'CAMERA STABILIZED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const Text(
                                      'QR Code Locked ✓',
                                      style: TextStyle(
                                        color: Color(0xFF86EFAC),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Progress bar below the viewfinder while stabilizing
                    if (_isStabilizing) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: boxSize,
                        height: 6,
                        decoration: BoxDecoration(
                          color: NcstColors.slate200,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LinearProgressIndicator(
                          value: _stabilizationProgress,
                          backgroundColor: NcstColors.slate200,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Guidance status prompt badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _isLocked
                            ? NcstColors.greenLight
                            : (_isStabilizing ? const Color(0xFFE0F2FE) : NcstColors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isLocked
                              ? NcstColors.green.withValues(alpha: 0.4)
                              : (_isStabilizing ? const Color(0xFF38BDF8) : NcstColors.slate200),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isLocked
                                ? Icons.check_circle
                                : (_isStabilizing ? Icons.camera_alt_outlined : Icons.center_focus_strong),
                            size: 15,
                            color: _isLocked
                                ? NcstColors.greenDark
                                : (_isStabilizing ? const Color(0xFF0369A1) : NcstColors.slate600),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _statusPrompt,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _isLocked
                                    ? NcstColors.greenDark
                                    : (_isStabilizing ? const Color(0xFF0369A1) : NcstColors.slate700),
                                fontSize: 12,
                                fontWeight: (_isStabilizing || _isLocked) ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Mode Pill: Steady Scan (Anti-Mistake) toggle
                    InkWell(
                      onTap: () {
                        setState(() {
                          _steadyScanEnabled = !_steadyScanEnabled;
                          if (!_steadyScanEnabled) {
                            _ticker?.cancel();
                            _isStabilizing = false;
                            _statusPrompt = 'Instant Scan Mode Active';
                          } else {
                            _statusPrompt = 'Align QR code inside frame';
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _steadyScanEnabled ? NcstColors.navy.withValues(alpha: 0.07) : NcstColors.slate100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _steadyScanEnabled ? NcstColors.navy.withValues(alpha: 0.25) : NcstColors.slate300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _steadyScanEnabled ? Icons.shield_rounded : Icons.flash_on_rounded,
                              size: 13,
                              color: _steadyScanEnabled ? NcstColors.navy : NcstColors.slate600,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _steadyScanEnabled ? 'Stabilization: Steady Hold (~0.9s)' : 'Stabilization: Off (Instant)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: _steadyScanEnabled ? NcstColors.navy : NcstColors.slate600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Quick Action Buttons (Enter manually & switch camera)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: widget.onManualQrPressed,
                          icon: const Icon(Icons.keyboard_outlined, size: 16, color: NcstColors.navy),
                          label: const Text(
                            'Enter QR Manually',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: NcstColors.navy,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: NcstColors.white,
                            side: const BorderSide(color: NcstColors.slate200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.onFlipCameraPressed,
                          icon: const Icon(Icons.flip_camera_android, size: 16, color: NcstColors.navy),
                          label: const Text(
                            'Flip',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: NcstColors.navy,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: NcstColors.white,
                            side: const BorderSide(color: NcstColors.slate200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatedViewport() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(
          Icons.qr_code_2,
          size: 110,
          color: Color(0x33FFFFFF),
        ),
      ),
    );
  }
}
