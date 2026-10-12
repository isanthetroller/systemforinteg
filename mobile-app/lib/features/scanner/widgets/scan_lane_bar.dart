import 'package:flutter/material.dart';

import '../../../theme/ncst_theme.dart';
import '../models/scan_lane.dart';

/// Shows which gate and lane the guard is working. A fixed account sees a lock; event mode and All Gates accounts get an
/// IN / OUT switch (disabled while a scan result is on screen, so a result cannot be re-read in the other lane).
class ScanLaneBar extends StatelessWidget {
  final LaneConfig config;
  final ScanLane lane;
  final bool enabled;
  final ValueChanged<ScanLane> onChanged;

  const ScanLaneBar({super.key, required this.config, required this.lane, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: NcstColors.navyDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.gateFor(lane),
                  key: const Key('laneGate'),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(config.subtitle, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5)),
              ],
            ),
          ),
          if (config.locked)
            Container(
              key: const Key('laneLocked'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(lane.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final l in ScanLane.values)
                    GestureDetector(
                      key: Key('lane_${l.code}'),
                      onTap: enabled && lane != l ? () => onChanged(l) : null,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 64, minHeight: 40),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: lane == l ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          l.code,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: lane == l ? NcstColors.navyDark : (enabled ? Colors.white : Colors.white54),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
