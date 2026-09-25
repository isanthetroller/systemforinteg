import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';

class QuickScanBanner extends StatelessWidget {
  final VoidCallback onOpenScan;

  const QuickScanBanner({
    super.key,
    required this.onOpenScan,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 740;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NcstColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NcstColors.gold, width: 2),
            boxShadow: [
              BoxShadow(
                color: NcstColors.gold.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: NcstColors.navy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.qr_code_scanner, color: NcstColors.navy, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'READY FOR NEXT VEHICLE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: NcstColors.slate900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Point gate camera at driver\'s phone to scan digital pass',
                      style: TextStyle(
                        fontSize: 12,
                        color: NcstColors.slate600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onOpenScan,
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text(
                          'OPEN CAMERA SCAN',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NcstColors.navy,
                          foregroundColor: NcstColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NcstColors.navy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_scanner, color: NcstColors.navy, size: 28),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'READY FOR NEXT VEHICLE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: NcstColors.slate900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Point gate camera at driver\'s phone to scan digital pass',
                            style: TextStyle(
                              fontSize: 12,
                              color: NcstColors.slate600,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onOpenScan,
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text(
                        'OPEN CAMERA SCAN',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NcstColors.navy,
                        foregroundColor: NcstColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
