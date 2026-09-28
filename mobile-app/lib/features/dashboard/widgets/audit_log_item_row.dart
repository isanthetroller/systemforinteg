import 'package:flutter/material.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/vehicle_model.dart';
import '../../../theme/ncst_theme.dart';

class AuditLogItemRow extends StatelessWidget {
  final AuditLogEntry log;

  const AuditLogItemRow({
    super.key,
    required this.log,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 540;

        if (isMobile) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top line: Plate + Vehicle Type + Status
                Row(
                  children: [
                    Flexible(
                      child: PlateBadge(plateNumber: log.plateNumber),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NcstColors.slate100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log.vehicleType,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: NcstColors.slate600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    StatusBadge(status: log.status, compact: true),
                  ],
                ),
                const SizedBox(height: 6),
                // Bottom line: Owner / Driver + Time In
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.driverName == log.ownerName
                            ? log.ownerName
                            : '${log.driverName} (${log.driverRelationship ?? "Authorized"})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: NcstColors.slate600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        Icon(
                          log.isExited
                              ? Icons.logout
                              : (log.isBlocked ? Icons.block : Icons.login),
                          size: 13,
                          color: log.isExited
                              ? NcstColors.slate600
                              : (log.isBlocked ? NcstColors.crimson : NcstColors.green),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateTimeUtils.formatTime(log.timeIn),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: log.isExited ? NcstColors.slate500 : NcstColors.slate600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        // Desktop / Tablet layout
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PlateBadge(plateNumber: log.plateNumber, fixedWidth: 100),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            log.ownerName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: NcstColors.slate900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: NcstColors.slate100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            log.vehicleType,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: NcstColors.slate600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      log.driverName == log.ownerName
                          ? 'Driver: Owner (Self)'
                          : 'Driver: ${log.driverName} (${log.driverRelationship ?? "Authorized"})',
                      style: const TextStyle(fontSize: 11, color: NcstColors.slate600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(
                      log.isExited
                          ? Icons.logout
                          : (log.isBlocked ? Icons.block : Icons.login),
                      size: 14,
                      color: log.isExited
                          ? NcstColors.slate600
                          : (log.isBlocked ? NcstColors.crimson : NcstColors.green),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        DateTimeUtils.formatTime(log.timeIn),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: log.isExited ? NcstColors.slate500 : NcstColors.slate800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(status: log.status),
            ],
          ),
        );
      },
    );
  }
}
