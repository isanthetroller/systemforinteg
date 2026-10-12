import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import '../case_format.dart';
import 'case_detail_screen.dart';

/// The guard's list of cases that are still open: vehicles on hold, who has been tried, who is coming in. Pull down to
/// refresh. Tapping a case opens its timeline and the contact tools.
class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  List<Map<String, dynamic>> _cases = const [];
  bool _loading = true;
  bool _unreachable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.fetchCases();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _unreachable = data == null;
      if (data != null) {
        _cases = (data['cases'] is List) ? (data['cases'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
      }
    });
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CaseDetailScreen(caseKey: c['key'].toString(), preview: c)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final awaiting = _cases.where((c) => c['status'] == 'Awaiting clearance').length;
    final onHold = _cases.length - awaiting;
    return RefreshIndicator(
      onRefresh: _load,
      color: NcstColors.navy,
      child: ListView(
        key: const Key('casesList'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          const Text('Open cases', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: NcstColors.navy)),
          const SizedBox(height: 2),
          const Text('Vehicles on hold until a case is settled. Reach the owner, then tell the administrator.',
              style: TextStyle(fontSize: 12.5, color: NcstColors.slate600, height: 1.35)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: NcstColors.navy)))
          else if (_unreachable && _cases.isEmpty)
            _message(Icons.cloud_off_rounded, 'Cannot reach the server', 'Pull down to try again.', const Key('casesUnreachable'))
          else ...[
            if (_unreachable)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Could not refresh. Showing the last list.', style: TextStyle(fontSize: 12, color: NcstColors.crimson, fontWeight: FontWeight.w700)),
              ),
            if (_cases.isEmpty)
              _message(Icons.verified_outlined, 'No open cases', 'Every vehicle is clear to enter and leave.', const Key('casesEmpty'))
            else ...[
              Row(
                children: [
                  _count('On hold', onHold, NcstColors.crimson),
                  const SizedBox(width: 10),
                  _count('Owner coming in', awaiting, NcstColors.goldDark),
                ],
              ),
              const SizedBox(height: 12),
              for (final c in _cases) _tile(c),
            ],
          ],
        ],
      ),
    );
  }

  Widget _message(IconData icon, String title, String text, Key key) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Icon(icon, size: 44, color: NcstColors.slate400),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: NcstColors.slate700)),
            const SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: NcstColors.slate500)),
          ],
        ),
      );

  Widget _count(String label, int n, Color tone) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: tone.withValues(alpha: 0.35))),
          child: Row(
            children: [
              Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: tone)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone))),
            ],
          ),
        ),
      );

  Widget _tile(Map<String, dynamic> c) {
    final status = (c['status'] ?? '').toString();
    final tone = CaseFormat.statusColor(status);
    final owner = (c['ownerName'] ?? '').toString();
    final attempts = (c['contactAttempts'] ?? 0) as num;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('caseTile:${c['key']}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(c),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: NcstColors.slate200)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ('${c['reference'] ?? ''}'.isNotEmpty)
                        Text('${c['reference']}',
                            key: Key('caseRef:${c['key']}'),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: NcstColors.slate500)),
                      Text((c['plateNumber'] ?? '').toString(),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: NcstColors.navy)),
                      const SizedBox(height: 2),
                      Text((c['title'] ?? '').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: NcstColors.slate800)),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (owner.isNotEmpty && owner.toLowerCase() != 'unknown') owner,
                          CaseFormat.age(c['openedAt'] ?? ''),
                          attempts == 0 ? 'not contacted yet' : '$attempts contact attempt${attempts == 1 ? '' : 's'}',
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12, color: NcstColors.slate600, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: tone.withValues(alpha: 0.5))),
                      child: Text(status == 'Awaiting clearance' ? 'Coming in' : 'On hold', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tone)),
                    ),
                    if (c['policeReferred'] == true) ...[
                      const SizedBox(height: 6),
                      const Icon(Icons.local_police_outlined, size: 18, color: NcstColors.crimson),
                    ],
                  ],
                ),
                const Icon(Icons.chevron_right_rounded, color: NcstColors.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
