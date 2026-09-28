import 'package:flutter/material.dart';
import '../../theme/ncst_theme.dart';

class PlateBadge extends StatelessWidget {
  final String plateNumber;
  final bool isProminent;
  final double? fixedWidth;

  const PlateBadge({
    super.key,
    required this.plateNumber,
    this.isProminent = false,
    this.fixedWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fixedWidth,
      padding: EdgeInsets.symmetric(
        horizontal: isProminent ? 14 : 8,
        vertical: isProminent ? 6 : (fixedWidth != null ? 6 : 4),
      ),
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isProminent ? NcstColors.slate900 : NcstColors.slate800,
          width: isProminent ? 2.0 : 1.5,
        ),
        boxShadow: isProminent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          plateNumber,
          maxLines: 1,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: isProminent ? 18 : 12,
            fontWeight: FontWeight.w900,
            letterSpacing: isProminent ? 1.5 : null,
            color: NcstColors.slate900,
          ),
          textAlign: fixedWidth != null ? TextAlign.center : null,
        ),
      ),
    );
  }
}
