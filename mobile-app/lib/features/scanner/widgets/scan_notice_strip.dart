import 'package:flutter/material.dart';

import '../../../theme/ncst_theme.dart';

enum ScanNoticeLevel { info, warning, danger }

/// A line the guard should read next to a scan result (parking nearly full, an exit released by an administrator,
/// which case is holding the vehicle).
class ScanNotice {
  final ScanNoticeLevel level;
  final String title;
  final String? detail;

  const ScanNotice(this.level, this.title, [this.detail]);

  /// The notices carried by a verify.php answer: `occupancy`, `exitRelease`, `case`.
  static List<ScanNotice> fromVerify(Map<String, dynamic>? data) {
    final out = <ScanNotice>[];
    if (data == null) return out;

    final release = data['exitRelease'];
    if (release is Map) {
      final until = _clock((release['expiresAt'] ?? '').toString());
      out.add(ScanNotice(
        ScanNoticeLevel.warning,
        'Exit released by ${release['releasedBy'] ?? 'an administrator'}${until == null ? '' : ' until $until'}',
        'Let it out once. It stays on hold and cannot come back in. Reason: ${release['reason'] ?? '-'}',
      ));
    }

    final occupancy = data['occupancy'];
    if (occupancy is Map) {
      final level = (occupancy['level'] ?? '').toString();
      final message = (occupancy['message'] ?? '').toString();
      if ((level == 'full' || level == 'nearly_full') && message.isNotEmpty) {
        out.add(ScanNotice(
          level == 'full' ? ScanNoticeLevel.danger : ScanNoticeLevel.warning,
          message,
          level == 'full' ? 'Entry is still your decision (emergency or VIP vehicles may need to be let in).' : null,
        ));
      }
    }

    final theCase = data['case'];
    if (theCase is Map) {
      final police = theCase['policeReferred'] == true ? ' · referred to the police' : '';
      out.add(ScanNotice(
        ScanNoticeLevel.info,
        'Case: ${theCase['title'] ?? 'open case'} (${theCase['step'] ?? 'open'})$police',
        'The vehicle stays on hold until an administrator closes the case.',
      ));
    }
    return out;
  }

  /// "2026-10-08 14:30:00" -> "2:30 PM"
  static String? _clock(String value) {
    final t = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (t == null) return null;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }
}

/// Stack of [ScanNotice]s shown above a scan result. Renders nothing when there are none.
class ScanNoticeStrip extends StatelessWidget {
  final List<ScanNotice> notices;

  const ScanNoticeStrip({super.key, required this.notices});

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('scanNoticeStrip'),
      children: [
        for (final n in notices)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _tint(n.level).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _tint(n.level).withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(n.level), size: 20, color: _tint(n.level)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _tint(n.level), height: 1.3)),
                      if (n.detail != null) ...[
                        const SizedBox(height: 2),
                        Text(n.detail!, style: const TextStyle(fontSize: 12, color: NcstColors.slate700, height: 1.35)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color _tint(ScanNoticeLevel l) =>
      l == ScanNoticeLevel.danger ? NcstColors.crimson : (l == ScanNoticeLevel.warning ? NcstColors.goldDark : NcstColors.navy);

  static IconData _icon(ScanNoticeLevel l) =>
      l == ScanNoticeLevel.danger ? Icons.error_outline_rounded : (l == ScanNoticeLevel.warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded);
}
