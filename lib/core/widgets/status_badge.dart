import 'package:flutter/material.dart';
import '../../models/vehicle_model.dart';
import '../../theme/ncst_theme.dart';

class StatusBadge extends StatelessWidget {
  final GateStatus status;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBlocked = status == GateStatus.blocked;
    final bgColor = isBlocked ? NcstColors.crimsonLight : NcstColors.greenLight;
    final borderColor = isBlocked
        ? NcstColors.crimson.withValues(alpha: 0.3)
        : NcstColors.green.withValues(alpha: 0.3);
    final textColor = isBlocked ? NcstColors.crimson : NcstColors.green;
    final text = isBlocked ? 'BLOCKED' : 'INSIDE';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
