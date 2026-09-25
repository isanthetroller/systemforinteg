import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../theme/ncst_theme.dart';
import 'qr_scanner_overlay_painter.dart';

class CameraViewfinder extends StatelessWidget {
  final MobileScannerController? cameraController;
  final bool cameraHasError;
  final ValueChanged<String> onQrDetected;
  final VoidCallback onManualQrPressed;
  final VoidCallback onFlipCameraPressed;

  const CameraViewfinder({
    super.key,
    required this.cameraController,
    required this.cameraHasError,
    required this.onQrDetected,
    required this.onManualQrPressed,
    required this.onFlipCameraPressed,
  });

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
                        decoration: const BoxDecoration(
                          color: NcstColors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'CAMERA AUTO-SCAN ACTIVE',
                          style: TextStyle(
                            color: NcstColors.navy,
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
                      color: NcstColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: NcstColors.navy.withValues(alpha: 0.2)),
                    ),
                    child: const Text(
                      'AUTO-DETECTS DRIVER QR',
                      style: TextStyle(
                        color: NcstColors.navy,
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
                    Container(
                      width: boxSize,
                      height: boxSize,
                      decoration: BoxDecoration(
                        color: NcstColors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: NcstColors.slate200, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (cameraController != null && !cameraHasError)
                            MobileScanner(
                              controller: cameraController,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error) {
                                return _buildSimulatedViewport();
                              },
                              onDetect: (capture) {
                                for (final barcode in capture.barcodes) {
                                  if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                                    onQrDetected(barcode.rawValue!);
                                    break;
                                  }
                                }
                              },
                            )
                          else
                            _buildSimulatedViewport(),

                          // Subtle alignment guide brackets
                          CustomPaint(
                            size: Size(boxSize - 40, boxSize - 40),
                            painter: const QrScannerOverlayPainter(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Helper label below viewfinder
                    const Text(
                      'Camera runs automatically • Holds driver QR in frame to detect',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: NcstColors.slate600,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Quick Action Buttons (Enter manually & switch camera)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onManualQrPressed,
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
                          onPressed: onFlipCameraPressed,
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
