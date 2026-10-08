import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import '../../guard/widgets/handover_note_field.dart';
import '../case_format.dart';

/// One case as a guard sees it: who the owner is, how to reach them, what has been tried so far, and the three steps a
/// guard may take (log an attempt to reach the owner, mark that the owner is coming in, add a note). Closing a case and
/// referring it to the police stay with the administrators.
class CaseDetailScreen extends StatefulWidget {
  final String caseKey;

  /// What the list already knew, shown while the full case loads.
  final Map<String, dynamic>? preview;

  const CaseDetailScreen({super.key, required this.caseKey, this.preview});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  Map<String, dynamic>? _case;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _case = widget.preview;
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.fetchCase(widget.caseKey);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data != null) _case = data;
    });
  }

  String get _status => (_case?['status'] ?? '').toString();
  bool get _closed => _status == 'Closed';
  String get _phone => (_case?['ownerPhone'] ?? '').toString().trim();

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: error ? NcstColors.crimson : NcstColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _send(String action, {String? method, String? result, String note = ''}) async {
    setState(() => _busy = true);
    final res = await ApiService.caseAction(widget.caseKey, action, method: method, result: result, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      _toast(res['error'].toString(), error: true);
      return;
    }
    _changed = true;
    _toast((res['message'] ?? 'Saved.').toString());
    await _load();
  }

  Future<void> _callOwner() async {
    final phone = _phone;
    if (phone.isEmpty) return;
    var dialed = false;
    try {
      dialed = await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+*#]'), '')));
    } catch (_) {}
    if (!mounted) return;
    if (!dialed) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!mounted) return;
      _toast('This device cannot place calls. The number $phone was copied.', error: true);
    }
    // When the guard comes back from the call, the result is one tap away
    await _logContact(method: 'Phone call');
  }

  Future<void> _logContact({String? method}) async {
    String? chosenMethod = method;
    String? chosenResult;
    var note = '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              key: const Key('logContactSheet'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Log contact attempt', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: NcstColors.navy)),
                const SizedBox(height: 4),
                const Text('Write down how you tried to reach the owner. Administrators see this on the case.',
                    style: TextStyle(fontSize: 12.5, color: NcstColors.slate600, height: 1.35)),
                const SizedBox(height: 14),
                const Text('How', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: NcstColors.slate700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in CaseFormat.contactMethods)
                      ChoiceChip(
                        key: Key('contactMethod:$m'),
                        label: Text(m),
                        selected: chosenMethod == m,
                        onSelected: (_) => setSheet(() => chosenMethod = m),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('What happened', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: NcstColors.slate700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in CaseFormat.contactResults)
                      ChoiceChip(
                        key: Key('contactResult:$r'),
                        label: Text(r),
                        selected: chosenResult == r,
                        onSelected: (_) => setSheet(() => chosenResult = r),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                HandoverNoteField(
                  key: const Key('contactNoteField'),
                  lines: 2,
                  label: 'Note (optional)',
                  onChanged: (v) => note = v,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('NOT NOW'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('contactSave'),
                        onPressed: (chosenMethod != null && chosenResult != null) ? () => Navigator.of(ctx).pop(true) : null,
                        style: ElevatedButton.styleFrom(backgroundColor: NcstColors.navy, foregroundColor: NcstColors.white),
                        child: const Text('SAVE ATTEMPT'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && chosenMethod != null && chosenResult != null) {
      await _send('contact', method: chosenMethod, result: chosenResult, note: note.trim());
    }
  }

  Future<void> _awaiting() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Owner is coming in'),
        content: const Text('Use this when the owner said they will come to the Security Office to sign the clearance. '
            'The vehicle stays on hold until an administrator closes the case.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('CANCEL')),
          ElevatedButton(
            key: const Key('awaitingConfirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: NcstColors.navy, foregroundColor: NcstColors.white),
            child: const Text('MARK AS COMING IN'),
          ),
        ],
      ),
    );
    if (ok == true) await _send('awaiting');
  }

  Future<void> _addNote() async {
    var note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a note'),
        content: HandoverNoteField(key: const Key('caseNoteField'), lines: 4, label: 'Note', onChanged: (v) => note = v),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('CANCEL')),
          ElevatedButton(
            key: const Key('noteSave'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: NcstColors.navy, foregroundColor: NcstColors.white),
            child: const Text('SAVE NOTE'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (note.trim().isEmpty) {
        _toast('Write the note first.', error: true);
        return;
      }
      await _send('note', note: note.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: NcstColors.slate100,
        appBar: AppBar(
          backgroundColor: NcstColors.navy,
          foregroundColor: NcstColors.white,
          title: Text('Case ${widget.caseKey}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        body: c == null
            ? Center(
                child: _loading
                    ? const CircularProgressIndicator(color: NcstColors.navy)
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('This case could not be loaded.', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: () {
                                setState(() => _loading = true);
                                _load();
                              },
                              child: const Text('TRY AGAIN'),
                            ),
                          ],
                        ),
                      ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    _header(c),
                    const SizedBox(height: 12),
                    _ownerCard(c),
                    const SizedBox(height: 12),
                    if (!_closed) ...[_actions(), const SizedBox(height: 12)],
                    _timeline(c),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NcstColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NcstColors.slate200),
        ),
        child: child,
      );

  Widget _header(Map<String, dynamic> c) {
    final tone = CaseFormat.statusColor(_status);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((c['plateNumber'] ?? '').toString(),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1, color: NcstColors.navy)),
              ),
              Container(
                key: const Key('caseStatusChip'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: tone.withValues(alpha: 0.5))),
                child: Text(_status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tone)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text((c['title'] ?? '').toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: NcstColors.slate800)),
          const SizedBox(height: 4),
          Text(
            [
              (c['step'] ?? '').toString(),
              if (c['openedAt'] != null) 'opened ${CaseFormat.when(c['openedAt'])}',
              if ((c['contactAttempts'] ?? 0) != 0) '${c['contactAttempts']} contact attempt${c['contactAttempts'] == 1 ? '' : 's'}',
            ].where((e) => e.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 12, color: NcstColors.slate600, height: 1.35),
          ),
          if (c['policeReferred'] == true) ...[
            const SizedBox(height: 8),
            const Row(children: [
              Icon(Icons.local_police_outlined, size: 16, color: NcstColors.crimson),
              SizedBox(width: 6),
              Expanded(child: Text('Referred to the police', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NcstColors.crimson))),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _ownerCard(Map<String, dynamic> c) {
    final name = (c['ownerName'] ?? '').toString();
    final known = name.isNotEmpty && name.toLowerCase() != 'unknown';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OWNER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: NcstColors.slate500)),
          const SizedBox(height: 6),
          Text(known ? name : 'Owner not on record', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: NcstColors.slate900)),
          const SizedBox(height: 8),
          if (_phone.isEmpty)
            const Text('No phone number on file. Ask at the Security Office or try the owner in person.',
                key: Key('noPhoneNote'), style: TextStyle(fontSize: 12.5, color: NcstColors.slate600, height: 1.35))
          else
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 18, color: NcstColors.navy),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(_phone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: NcstColors.slate900))),
                IconButton(
                  tooltip: 'Copy number',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _phone));
                    if (mounted) _toast('Number copied.');
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    final awaiting = _status == 'Awaiting clearance';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_phone.isNotEmpty) ...[
            ElevatedButton.icon(
              key: const Key('callOwner'),
              onPressed: _busy ? null : _callOwner,
              icon: const Icon(Icons.call_rounded, size: 20),
              label: const Text('CALL OWNER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NcstColors.green,
                foregroundColor: NcstColors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            key: const Key('logContact'),
            onPressed: _busy ? null : () => _logContact(),
            icon: const Icon(Icons.edit_note_rounded, size: 20),
            label: const Text('LOG CONTACT ATTEMPT'),
            style: OutlinedButton.styleFrom(foregroundColor: NcstColors.navy, minimumSize: const Size.fromHeight(46)),
          ),
          if (!awaiting) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('markAwaiting'),
              onPressed: _busy ? null : _awaiting,
              icon: const Icon(Icons.hourglass_top_rounded, size: 20),
              label: const Text('OWNER IS COMING IN'),
              style: OutlinedButton.styleFrom(foregroundColor: NcstColors.navy, minimumSize: const Size.fromHeight(46)),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('addCaseNote'),
            onPressed: _busy ? null : _addNote,
            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
            label: const Text('Add a note'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Closing a case and referring it to the police are done by an administrator.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: NcstColors.slate500, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _timeline(Map<String, dynamic> c) {
    final items = (c['timeline'] is List) ? (c['timeline'] as List).whereType<Map>().toList() : const <Map>[];
    return _card(
      child: Column(
        key: const Key('caseTimeline'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WHAT HAS HAPPENED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: NcstColors.slate500)),
          const SizedBox(height: 8),
          if (items.isEmpty) const Text('Nothing recorded yet.', style: TextStyle(fontSize: 12.5, color: NcstColors.slate600)),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(CaseFormat.timelineIcon((items[i]['type'] ?? '').toString()), size: 20, color: NcstColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((items[i]['label'] ?? '').toString(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: NcstColors.slate900)),
                        if ((items[i]['detail'] ?? '').toString().isNotEmpty)
                          Text(items[i]['detail'].toString(), style: const TextStyle(fontSize: 12.5, color: NcstColors.slate700, height: 1.35)),
                        Text(
                          [CaseFormat.when(items[i]['at'] ?? ''), if ((items[i]['by'] ?? '').toString().isNotEmpty) items[i]['by'].toString()].where((e) => e.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 11.5, color: NcstColors.slate500),
                        ),
                      ],
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
