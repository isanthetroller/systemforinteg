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
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String text;

    switch (status) {
      case GateStatus.blocked:
        bgColor = NcstColors.crimsonLight;
        borderColor = NcstColors.crimson.withValues(alpha: 0.3);
        textColor = NcstColors.crimson;
        text = 'BLOCKED';
        break;
      case GateStatus.exited:
        bgColor = const Color(0xFFE2E8F0); // Slate 200
        borderColor = const Color(0xFFCBD5E1); // Slate 300
        textColor = const Color(0xFF475569); // Slate 600
        text = 'EXITED';
        break;
      case GateStatus.inside:
        bgColor = NcstColors.greenLight;
        borderColor = NcstColors.green.withValues(alpha: 0.3);
        textColor = NcstColors.green;
        text = 'INSIDE';
        break;
    }

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
