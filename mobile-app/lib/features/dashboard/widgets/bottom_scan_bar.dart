import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';

class BottomScanBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const BottomScanBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NcstColors.white,
        border: const Border(top: BorderSide(color: NcstColors.slate200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              children: [
                // 1. Dashboard Tab Button
                Expanded(
                  child: InkWell(
                    onTap: () => onTabSelected(0),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: selectedIndex == 0
                            ? NcstColors.navy.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selectedIndex == 0
                              ? NcstColors.navy.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selectedIndex == 0
                                ? Icons.dashboard_rounded
                                : Icons.dashboard_outlined,
                            color: selectedIndex == 0
                                ? NcstColors.navy
                                : NcstColors.slate600,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Dashboard',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selectedIndex == 0
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: selectedIndex == 0
                                      ? NcstColors.navy
                                      : NcstColors.slate600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 2. Scan QR Pass Tab Button (Prominent NCST Gold)
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => onTabSelected(1),
                      icon: Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 20,
                        color: selectedIndex == 1 ? NcstColors.white : NcstColors.navyDark,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'SCAN QR PASS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: selectedIndex == 1 ? NcstColors.white : NcstColors.navyDark,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedIndex == 1 ? NcstColors.navy : NcstColors.gold,
                        foregroundColor: selectedIndex == 1 ? NcstColors.white : NcstColors.navyDark,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: selectedIndex == 1
                              ? const BorderSide(color: NcstColors.gold, width: 2)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
