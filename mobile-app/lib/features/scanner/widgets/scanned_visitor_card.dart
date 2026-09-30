import 'package:flutter/material.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/scanned_visitor_pass.dart';
import '../../../theme/ncst_theme.dart';

/// What the guard sees when the plate or pass code belongs to a visitor day pass that already exists on the server
/// (issued in the web portal, or scheduled by an administrator): the server's verdict, who the visitor is, and the
/// items they declared, which the guard must tick off before the entry can be recorded.
class ScannedVisitorCard extends StatelessWidget {
  final ScannedVisitorPass pass;
  final Set<int> checkedItems;
  final ValueChanged<int> onToggleItem;

  const ScannedVisitorCard({
    super.key,
    required this.pass,
    required this.checkedItems,
    required this.onToggleItem,
  });

  @override
  Widget build(BuildContext context) {
    final ok = pass.accepted;
    final accent = ok ? (pass.warnings.isEmpty ? NcstColors.green : NcstColors.goldDark) : NcstColors.crimson;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.verified_rounded : Icons.block_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pass.verdictTitle,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5, color: accent),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: NcstColors.slate200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'VISITOR DAY PASS',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: NcstColors.slate700),
                  ),
                ),
              ],
            ),
            if (!ok && pass.reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              _banner(
                icon: Icons.error_outline,
                title: 'ENTRY NOT ALLOWED',
                lines: [pass.reason],
                background: const Color(0xFFFEE2E2),
                border: NcstColors.crimson,
              ),
            ],
            if (ok && pass.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _banner(
                icon: Icons.info_outline,
                title: 'CHECK BEFORE ENTRY',
                lines: pass.warnings,
                background: const Color(0xFFFEF3C7),
                border: NcstColors.goldDark,
              ),
            ],
            if (pass.currentlyInside) ...[
              const SizedBox(height: 12),
              _banner(
                icon: Icons.history_toggle_off,
                title: 'ALREADY RECORDED INSIDE',
                lines: const ['This visitor already entered today and has not been recorded leaving.'],
                background: const Color(0xFFFEF3C7),
                border: NcstColors.goldDark,
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: Text(
                pass.visitorName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: NcstColors.slate900),
              ),
            ),
            const SizedBox(height: 10),
            Center(child: PlateBadge(plateNumber: pass.plateNumber, isProminent: true)),
            if (pass.vehicleModel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  pass.vehicleModel,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: NcstColors.slate700),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _detail('Pass code', pass.passCode),
            _detail('Valid on', pass.validDate),
            if (pass.personToVisit.isNotEmpty) _detail('Visiting', pass.personToVisit),
            if (pass.purposeOfVisit.isNotEmpty) _detail('Purpose', pass.purposeOfVisit),
            if (pass.contactNumber.isNotEmpty) _detail('Contact', pass.contactNumber),
            if (pass.hasItems) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                'DECLARED ITEMS (${checkedItems.length}/${pass.items.length} checked)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: NcstColors.slate700),
              ),
              const SizedBox(height: 2),
              Text(
                ok ? 'Look at each item and tick it before recording the entry.' : 'Items are not checked because entry is not allowed.',
                style: const TextStyle(fontSize: 11.5, color: NcstColors.slate600),
              ),
              for (var i = 0; i < pass.items.length; i++)
                CheckboxListTile(
                  key: ValueKey('visitor-item-$i'),
                  value: checkedItems.contains(i),
                  onChanged: ok ? (_) => onToggleItem(i) : null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: NcstColors.green,
                  title: Text(
                    pass.items[i].label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: NcstColors.slate600)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: NcstColors.slate900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required String title,
    required List<String> lines,
    required Color background,
    required Color border,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: border, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: NcstColors.navyDark, fontSize: 13)),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: NcstColors.slate800, fontSize: 11.5),
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
