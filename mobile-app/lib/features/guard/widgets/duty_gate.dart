import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import 'shift_banner.dart';

/// Makes a guard go on duty at sign-in.
///
/// Right after the terminal opens (and again when the app comes back to the foreground with no open shift, for example
/// after the server closed a forgotten one) the guard must choose a gate and go on duty, so the admin's Guard Shifts
/// tab has a start time for every guard. The sheet cannot be dismissed. It never traps a guard at the gate, though: if
/// the shift cannot be recorded (no connection, server error) the guard may continue without it, and the admin tab then
/// shows those scans as "outside a shift".
class DutyGate {
  /// Tests that open the guard screen switch this off.
  static bool enabled = true;
  static bool _showing = false;

  /// A test that leaves the sheet open must not block the next one.
  @visibleForTesting
  static void resetForTesting() => _showing = false;

  /// Does nothing when the guard is already on duty. Otherwise asks until the guard is on duty, continues without a
  /// record, or signs out ([signOut]).
  static Future<void> ensureOnDuty(
    BuildContext context, {
    required String assignedGate,
    required Future<void> Function() signOut,
  }) async {
    if (!enabled || _showing || !context.mounted) return;
    _showing = true;
    try {
      final data = await ApiService.fetchShifts();
      if (!context.mounted) return;
      if (data != null && data['mine'] is Map) {
        ShiftBanner.onDuty.value = true;
        return;
      }
      final handover = data?['handover'] is Map
          ? Map<String, dynamic>.from(data!['handover'])
          : null;
      final choice = await showDialog<DutyChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: _DutyDialog(
            assignedGate: assignedGate,
            handover: handover,
            unreachable: data == null,
          ),
        ),
      );
      if (choice == DutyChoice.signOut) await signOut();
    } finally {
      _showing = false;
    }
  }
}

enum DutyChoice { started, continuedWithout, signOut }

class _DutyDialog extends StatefulWidget {
  final String assignedGate;
  final Map<String, dynamic>? handover;
  final bool unreachable;

  const _DutyDialog({
    required this.assignedGate,
    required this.handover,
    required this.unreachable,
  });

  @override
  State<_DutyDialog> createState() => _DutyDialogState();
}

class _DutyDialogState extends State<_DutyDialog> {
  late final List<String> _gates;
  late String _gate;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gates = <String>{...ShiftBanner.gates, widget.assignedGate}
        .where((g) => g.trim().isNotEmpty)
        .toList();
    // The gate this terminal is set up for, unless it is "All Gates" or something not worth offering
    _gate = ShiftBanner.gates.contains(widget.assignedGate)
        ? widget.assignedGate
        : _gates.first;
    if (widget.unreachable) {
      _error =
          'The server cannot be reached, so your shift cannot be recorded yet.';
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ApiService.startShift(_gate);
    if (!mounted) return;
    if (result['error'] != null) {
      setState(() {
        _busy = false;
        _error = '${result['error']}';
      });
      return;
    }
    ShiftBanner.onDuty.value = true;
    ApiService.liveRevision.value++; // the shift banner reloads and shows the handover note
    Navigator.of(context).pop(DutyChoice.started);
  }

  @override
  Widget build(BuildContext context) {
    final note = (widget.handover?['handoverNotes'] ?? '').toString().trim();
    return AlertDialog(
      key: const Key('dutyGate'),
      title: Row(
        children: const [
          Icon(Icons.verified_user_outlined, color: NcstColors.navy),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Start your shift',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose the gate you are working and go on duty. Your supervisor sees when your shift starts and ends.',
              style: TextStyle(fontSize: 13, color: NcstColors.slate600),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('dutyGateField'),
              initialValue: _gate,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'Gate',
              ),
              items: _gates
                  .map(
                    (g) => DropdownMenuItem(
                      value: g,
                      child: Text(g, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _gate = v ?? _gate),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NcstColors.goldDark.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: NcstColors.goldDark.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Handover from ${widget.handover?['guard'] ?? 'the previous guard'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: NcstColors.goldDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 13,
                        color: NcstColors.slate800,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('dutyGateError'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: NcstColors.crimson,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('dutyGateSignOut'),
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pop(DutyChoice.signOut),
          child: const Text('Sign out'),
        ),
        if (_error != null)
          TextButton(
            key: const Key('dutyGateSkip'),
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pop(DutyChoice.continuedWithout),
            child: const Text('Continue without recording'),
          ),
        ElevatedButton(
          key: const Key('dutyGateStart'),
          onPressed: _busy ? null : _start,
          style: ElevatedButton.styleFrom(
            backgroundColor: NcstColors.green,
            foregroundColor: NcstColors.white,
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_error != null ? 'Try again' : 'Go on duty'),
        ),
      ],
    );
  }
}
