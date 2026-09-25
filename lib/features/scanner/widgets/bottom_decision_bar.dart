import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';

class BottomDecisionBar extends StatelessWidget {
  final VoidCallback onBlock;
  final VoidCallback onCleared;

  const BottomDecisionBar({
    super.key,
    required this.onBlock,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NcstColors.white,
        border: const Border(top: BorderSide(color: NcstColors.slate200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 400;
              return Row(
                children: [
                  // BLOCKED BUTTON (Red)
                  Expanded(
                    child: SizedBox(
                      height: isCompact ? 46 : 52,
                      child: ElevatedButton.icon(
                        onPressed: onBlock,
                        icon: Icon(
                          Icons.close_rounded,
                          size: isCompact ? 18 : 22,
                          color: NcstColors.white,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'BLOCKED',
                            style: TextStyle(
                              fontSize: isCompact ? 13 : 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: NcstColors.white,
                            ),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NcstColors.crimson,
                          foregroundColor: NcstColors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isCompact ? 10 : 16),

                  // CLEARED BUTTON (Green)
                  Expanded(
                    child: SizedBox(
                      height: isCompact ? 46 : 52,
                      child: ElevatedButton.icon(
                        onPressed: onCleared,
                        icon: Icon(
                          Icons.check_rounded,
                          size: isCompact ? 18 : 22,
                          color: NcstColors.white,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'CLEARED (TO GO)',
                            style: TextStyle(
                              fontSize: isCompact ? 13 : 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: NcstColors.white,
                            ),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NcstColors.green,
                          foregroundColor: NcstColors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
