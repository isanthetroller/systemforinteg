import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';

class BottomDecisionBar extends StatelessWidget {
  final VoidCallback onBlock;
  final VoidCallback onCleared;
  final bool isClearedEnabled;
  final String clearedLabel;
  /// Text on the (disabled) cleared button. Defaults to the refusal wording used for banned / suspended vehicles.
  final String? disabledLabel;
  final IconData clearedIcon;
  final Color? clearedColor;

  const BottomDecisionBar({
    super.key,
    required this.onBlock,
    required this.onCleared,
    this.isClearedEnabled = true,
    this.clearedLabel = 'CLEARED (TO GO)',
    this.disabledLabel,
    this.clearedIcon = Icons.check_rounded,
    this.clearedColor,
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

                  // CLEARED BUTTON (Green or custom action)
                  Expanded(
                    child: SizedBox(
                      height: isCompact ? 46 : 52,
                      child: ElevatedButton.icon(
                        onPressed: isClearedEnabled ? onCleared : null,
                        icon: Icon(
                          isClearedEnabled ? clearedIcon : Icons.lock_outline_rounded,
                          size: isCompact ? 18 : 22,
                          color: isClearedEnabled ? NcstColors.white : NcstColors.slate500,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isClearedEnabled ? clearedLabel : (disabledLabel ?? 'ACTION REFUSED'),
                            style: TextStyle(
                              fontSize: isCompact ? 13 : 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: isClearedEnabled ? NcstColors.white : NcstColors.slate500,
                            ),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isClearedEnabled
                              ? (clearedColor ?? NcstColors.green)
                              : NcstColors.slate200,
                          foregroundColor: isClearedEnabled ? NcstColors.white : NcstColors.slate500,
                          disabledBackgroundColor: NcstColors.slate200,
                          disabledForegroundColor: NcstColors.slate500,
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
