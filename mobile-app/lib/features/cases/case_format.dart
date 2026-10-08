import 'package:flutter/material.dart';

import '../../theme/ncst_theme.dart';

/// Shared wording and colours for the guard's case screens.
class CaseFormat {
  CaseFormat._();

  static const List<String> contactMethods = ['Phone call', 'Text message', 'In person', 'E-mail', 'Other'];
  static const List<String> contactResults = ['Reached owner', 'No answer', 'Left message', 'Wrong or unreachable number'];

  /// "2026-10-08 14:30:00" -> "Oct 8, 2:30 PM"
  static String when(dynamic value) {
    final t = DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
    if (t == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${months[t.month - 1]} ${t.day}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// "Open 3 days" style age of a case, from its opened-at time.
  static String age(dynamic openedAt, {DateTime? now}) {
    final t = DateTime.tryParse(openedAt.toString().replaceFirst(' ', 'T'));
    if (t == null) return '';
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inMinutes < 60) return 'Open ${d.inMinutes < 1 ? 1 : d.inMinutes} min';
    if (d.inHours < 24) return 'Open ${d.inHours} h';
    return 'Open ${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  }

  static Color statusColor(String status) {
    if (status == 'Awaiting clearance') return NcstColors.goldDark;
    if (status == 'Closed') return NcstColors.slate500;
    return NcstColors.crimson;
  }

  static IconData timelineIcon(String type) {
    switch (type) {
      case 'contact':
        return Icons.phone_in_talk_outlined;
      case 'awaiting':
        return Icons.hourglass_top_rounded;
      case 'police':
        return Icons.local_police_outlined;
      case 'closed':
        return Icons.check_circle_outline_rounded;
      case 'note':
        return Icons.sticky_note_2_outlined;
      default:
        return Icons.flag_outlined;
    }
  }
}
