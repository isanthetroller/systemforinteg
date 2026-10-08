import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import 'handover_note_field.dart';

/// Guard duty: who is on which gate. Shows the previous guard's handover note, lets the guard go on duty at a gate and
/// end the shift with a note for the next guard. Everything is optional and never blocks a scan; if the server cannot be
/// reached the banner simply stays hidden.
class ShiftBanner extends StatefulWidget {
  /// The gate this terminal is set up for (pre-selected when going on duty).
  final String assignedGate;

  const ShiftBanner({super.key, required this.assignedGate});

  /// True while this guard has an open shift (read by the sign-out dialog to offer a handover note).
  static final ValueNotifier<bool> onDuty = ValueNotifier<bool>(false);

  static const List<String> gates = ['Gate 1 (Main Ingress)', 'Gate 2 (Main Egress)', 'Patrol / Other'];

  @override
  State<ShiftBanner> createState() => _ShiftBannerState();
}

class _ShiftBannerState extends State<ShiftBanner> {
  bool _loaded = false;
  bool _busy = false;
  bool _showHandover = true;
  Map<String, dynamic>? _mine;
  Map<String, dynamic>? _handover;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.fetchShifts();
    if (!mounted) return;
    setState(() {
      _loaded = data != null;
      _mine = data?['mine'] is Map ? Map<String, dynamic>.from(data!['mine']) : null;
      _handover = data?['handover'] is Map ? Map<String, dynamic>.from(data!['handover']) : null;
      ShiftBanner.onDuty.value = _mine != null;
    });
  }

  String _since(String? value) {
    final t = DateTime.tryParse((value ?? '').replaceFirst(' ', 'T'));
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _goOnDuty() async {
    final options = <String>{widget.assignedGate, ...ShiftBanner.gates}.toList();
    String gate = options.first;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Go on duty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Which gate are you on? Your supervisor can see who is on duty at each gate.', style: TextStyle(fontSize: 13, color: NcstColors.slate600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('shiftGateField'),
                initialValue: gate,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Gate'),
                items: options.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setLocal(() => gate = v ?? gate),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              key: const Key('shiftStartConfirm'),
              onPressed: () => Navigator.of(ctx).pop(gate),
              style: ElevatedButton.styleFrom(backgroundColor: NcstColors.green, foregroundColor: NcstColors.white),
              child: const Text('Go on duty'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    final result = await ApiService.startShift(chosen);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: NcstColors.crimson, content: Text('${result['error']}')));
      return;
    }
    setState(() {
      _mine = result['shift'] is Map ? Map<String, dynamic>.from(result['shift']) : null;
      _handover = result['handover'] is Map ? Map<String, dynamic>.from(result['handover']) : null;
      _showHandover = true;
      ShiftBanner.onDuty.value = _mine != null;
    });
  }

  Future<void> _endShift() async {
    var note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End shift', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Leave a note for the next guard on this gate (broken gate arm, a vehicle to watch, anything unfinished).', style: TextStyle(fontSize: 13, color: NcstColors.slate600)),
            const SizedBox(height: 12),
            HandoverNoteField(
              key: const Key('shiftHandoverField'),
              onChanged: (v) => note = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            key: const Key('shiftEndConfirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: NcstColors.navy, foregroundColor: NcstColors.white),
            child: const Text('End shift'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final problem = await ApiService.endShift(note.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: NcstColors.crimson, content: Text(problem)));
      return;
    }
    setState(() {
      _mine = null;
      ShiftBanner.onDuty.value = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final onDuty = _mine != null;
    final handover = _handover;
    final note = (handover?['handoverNotes'] ?? '').toString().trim();

    return Column(
      key: const Key('shiftBanner'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (handover != null && note.isNotEmpty && _showHandover)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: NcstColors.goldDark.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NcstColors.goldDark.withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.sticky_note_2_outlined, size: 20, color: NcstColors.goldDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Handover from ${handover['guard'] ?? 'the previous guard'}${handover['gate'] != null ? ' · ${handover['gate']}' : ''}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NcstColors.goldDark)),
                      const SizedBox(height: 2),
                      Text(note, style: const TextStyle(fontSize: 13, color: NcstColors.slate800, height: 1.35)),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Dismiss', onPressed: () => setState(() => _showHandover = false), icon: const Icon(Icons.close_rounded, size: 18)),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: onDuty ? NcstColors.green.withValues(alpha: 0.08) : NcstColors.slate100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onDuty ? NcstColors.green.withValues(alpha: 0.4) : NcstColors.slate200),
          ),
          child: Row(
            children: [
              Icon(onDuty ? Icons.verified_user_outlined : Icons.shield_outlined, size: 20, color: onDuty ? NcstColors.green : NcstColors.slate500),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  onDuty ? 'On duty · ${_mine!['gate'] ?? ''} · since ${_since(_mine!['startedAt']?.toString())}' : 'You are not on duty yet',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onDuty ? NcstColors.green : NcstColors.slate700),
                ),
              ),
              TextButton(
                key: Key(onDuty ? 'shiftEnd' : 'shiftStart'),
                onPressed: _busy ? null : (onDuty ? _endShift : _goOnDuty),
                child: Text(onDuty ? 'End shift' : 'Go on duty', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
