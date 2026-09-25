import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';
import 'kpi_metric_card.dart';

class DashboardKpiRow extends StatelessWidget {
  final int insideCount;
  final int totalEntriesToday;
  final int blockedTodayCount;

  const DashboardKpiRow({
    super.key,
    required this.insideCount,
    required this.totalEntriesToday,
    required this.blockedTodayCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTabletOrDesktop = constraints.maxWidth >= 600;
        final isCompact = constraints.maxWidth < 850;
        final isUltraNarrow = constraints.maxWidth < 340;

        if (isUltraNarrow) {
          return Column(
            children: [
              KpiMetricCard(
                label: 'INSIDE CAMPUS',
                value: '$insideCount',
                color: NcstColors.green,
                icon: Icons.directions_car_outlined,
                compact: true,
              ),
              const SizedBox(height: 8),
              KpiMetricCard(
                label: 'TOTAL ENTRIES',
                value: '$totalEntriesToday',
                color: NcstColors.navy,
                icon: Icons.playlist_add_check_rounded,
                compact: true,
              ),
              const SizedBox(height: 8),
              KpiMetricCard(
                label: 'BLOCKED ATTEMPTS',
                value: '$blockedTodayCount',
                color: NcstColors.crimson,
                icon: Icons.block_outlined,
                compact: true,
              ),
            ],
          );
        }

        if (!isTabletOrDesktop) {
          return Column(
            children: [
              KpiMetricCard(
                label: 'INSIDE CAMPUS',
                value: '$insideCount',
                color: NcstColors.green,
                icon: Icons.directions_car_outlined,
                compact: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: KpiMetricCard(
                      label: 'TOTAL ENTRIES',
                      value: '$totalEntriesToday',
                      color: NcstColors.navy,
                      icon: Icons.playlist_add_check_rounded,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KpiMetricCard(
                      label: 'BLOCKED ATTEMPTS',
                      value: '$blockedTodayCount',
                      color: NcstColors.crimson,
                      icon: Icons.block_outlined,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: KpiMetricCard(
                label: 'INSIDE CAMPUS',
                value: '$insideCount',
                color: NcstColors.green,
                icon: Icons.directions_car_outlined,
                compact: isCompact,
              ),
            ),
            SizedBox(width: isCompact ? 8 : 12),
            Expanded(
              child: KpiMetricCard(
                label: 'TOTAL ENTRIES',
                value: '$totalEntriesToday',
                color: NcstColors.navy,
                icon: Icons.playlist_add_check_rounded,
                compact: isCompact,
              ),
            ),
            SizedBox(width: isCompact ? 8 : 12),
            Expanded(
              child: KpiMetricCard(
                label: 'BLOCKED ATTEMPTS',
                value: '$blockedTodayCount',
                color: NcstColors.crimson,
                icon: Icons.block_outlined,
                compact: isCompact,
              ),
            ),
          ],
        );
      },
    );
  }
}
