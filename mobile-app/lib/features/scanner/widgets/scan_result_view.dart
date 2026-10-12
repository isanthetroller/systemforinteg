import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/driver_photo_view.dart';
import '../../../core/widgets/evidence_button.dart';
import '../../../core/widgets/vehicle_photo_panel.dart';
import '../../../models/scanned_visitor_pass.dart';
import '../../../services/evidence_service.dart';
import '../../../theme/ncst_theme.dart';
import '../models/scan_lane.dart';
import 'scan_notice_strip.dart';

/// Reasons a guard can pick when blocking a vehicle at the gate: the ones the app always had, plus two catch-alls.
final List<String> kBlockReasons = [
  ...AppConstants.defaultBlockReasons,
  'Suspicious behavior',
  'Other',
];

/// Reasons for a record-check report after an anti-passback refusal. The first one depends on which way the record is wrong.
List<String> reportReasonsFor(String result) => [
  result == 'NOT_ON_CAMPUS' ? 'Vehicle is on campus (entry was not scanned)' : 'Vehicle already left (exit was not scanned)',
  'Pass used by another vehicle or driver',
  'Plate & Vehicle Profile Mismatch',
  'Unauthorized / Unregistered Driver',
  'Suspicious behavior',
  'Other',
];

/// What the guard entered in the Block sheet.
class BlockDecision {
  final String reason;
  final String note;
  final PendingEvidence? photo;
  const BlockDecision(this.reason, this.note, this.photo);

  /// Reason and note as one line for the gate log and the incident report.
  String get text => note.isEmpty ? reason : '$reason: $note';
}

/// What the guard sees after every scan: a green or red status, the owner and vehicle photos, the facts to check, and
/// two big buttons. A cleared scan is one tap away from being saved (Allow); Block asks only for a reason.
class ScanResultView extends StatefulWidget {
  /// The server's answer to a movement `prepare` (vehicle / visitor, result, movement ticket, onCampus ...).
  final Map<String, dynamic> data;
  final ScanLane lane;
  final String gateLabel;
  final bool saving;
  final bool retryPending;
  final bool invalidated;
  final String? error;

  /// Called by the green button. [itemsVerified] is true when the visitor's declared items were ticked as matching.
  final void Function(int? driverId, bool itemsVerified) onAllow;

  /// Called by the red button after the guard filled in the Block sheet.
  final void Function(BlockDecision decision, String driverName, String relationship) onBlock;
  final VoidCallback onScanNext;

  /// Offered on a passback refusal: opens the same sheet as Block (reason, note, photo) and then an admin case.
  final void Function(BlockDecision decision)? onReport;
  final VoidCallback? onDetails;
  final VoidCallback? onIssueViolation;
  final ValueChanged<PendingEvidence?>? onEvidenceChanged;

  const ScanResultView({
    super.key,
    required this.data,
    required this.lane,
    required this.gateLabel,
    required this.saving,
    required this.retryPending,
    required this.invalidated,
    required this.onAllow,
    required this.onBlock,
    required this.onScanNext,
    this.error,
    this.onReport,
    this.onDetails,
    this.onIssueViolation,
    this.onEvidenceChanged,
  });

  /// True when the server cleared this scan and issued a movement ticket.
  static bool isCleared(Map<String, dynamic> data) =>
      data['accepted'] == true && data['movement'] is Map;

  @override
  State<ScanResultView> createState() => _ScanResultViewState();
}

class _ScanResultViewState extends State<ScanResultView> {
  int? _driverId;
  bool _itemsOk = false;
  bool _itemsHint = false;

  Map<String, dynamic> get _record => Map<String, dynamic>.from(
    (widget.data['vehicle'] ?? widget.data['visitor'] ?? const {}) as Map,
  );
  bool get _isVisitor => widget.data['visitor'] is Map && widget.data['vehicle'] is! Map;
  bool get _cleared => ScanResultView.isCleared(widget.data);
  List<Map> get _drivers => (_record['authorizedDrivers'] as List? ?? []).whereType<Map>().toList();
  bool get _vip => _record['isVip'] == true;

  /// A cleared scan names the direction the server approved; a refusal falls back to the lane the guard is working.
  ScanLane get _shownLane => _cleared
      ? ((widget.data['movement'] as Map)['suggestedAction'] == 'OUT' ? ScanLane.exit : ScanLane.entry)
      : widget.lane;
  ScannedVisitorPass? get _visitorPass => ScannedVisitorPass.fromVerify(widget.data);

  @override
  void initState() {
    super.initState();
    _driverId = _defaultDriverId();
  }

  /// The owner is preselected so the guard only taps when someone else is driving.
  int? _defaultDriverId() {
    if (_isVisitor || _vip) return null;
    final owner = (_record['ownerName'] ?? '').toString().trim().toLowerCase();
    Map? pick;
    for (final d in _drivers) {
      final rel = '${d['relationship'] ?? ''}'.toLowerCase();
      final name = '${d['fullName'] ?? d['full_name'] ?? ''}'.trim().toLowerCase();
      if (rel.contains('self') || rel.contains('owner') || (owner.isNotEmpty && name == owner)) {
        pick = d;
        break;
      }
    }
    pick ??= _drivers.isNotEmpty ? _drivers.first : null;
    return pick == null ? null : int.tryParse('${pick['id']}');
  }

  Map? get _selectedDriver => _drivers.where((d) => '${d['id']}' == '$_driverId').firstOrNull;

  String _text(List<String> keys, [Map? from]) {
    final m = from ?? _record;
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(String raw) {
    final t = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    return t == null ? raw : '${t.day} ${_months[t.month - 1]} ${t.year}';
  }

  static String _time(String raw) {
    final t = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (t == null) return raw;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${_months[t.month - 1]} ${t.day}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Title, icon and one-line explanation for the banner.
  ({String title, String sub, IconData icon}) _banner() {
    final lane = _shownLane;
    if (_cleared) {
      return (
        title: lane == ScanLane.entry ? 'Clear to enter' : 'Clear to leave',
        sub: _isVisitor ? 'Visitor pass is valid for today' : 'Pass valid, fee paid, no holds',
        icon: Icons.check_circle,
      );
    }
    final reason = (widget.data['reason'] ?? widget.data['message'] ?? '').toString();
    switch ('${widget.data['result']}') {
      case 'ALREADY_INSIDE':
        return (title: 'Already inside', sub: 'Anti-passback: a second entry was not recorded.', icon: Icons.repeat);
      case 'NOT_ON_CAMPUS':
        return (title: 'Not on campus', sub: 'Anti-passback: an exit was not recorded.', icon: Icons.repeat);
      case 'BANNED':
        return (title: 'Security hold', sub: reason, icon: Icons.pan_tool);
      case 'EXPIRED':
      case 'EXPIRED_TEMP':
        return (title: 'Pass expired', sub: reason, icon: Icons.event_busy);
      case 'NOT_YET_VALID':
        return (title: 'Pass not valid yet', sub: reason, icon: Icons.event_busy);
      case 'UNPAID':
        return (title: 'Fee unpaid', sub: reason, icon: Icons.payments_outlined);
      case 'RETIRED':
        return (title: 'Vehicle retired', sub: reason, icon: Icons.block);
      case 'SUSPENDED':
        return (title: 'Registration suspended', sub: reason, icon: Icons.block);
      case 'FORGED':
        return (title: 'Forged or edited pass', sub: reason, icon: Icons.gpp_bad);
      case 'REVOKED':
        return (title: 'Pass revoked', sub: reason, icon: Icons.gpp_bad);
      case 'GATE_DIRECTION_DENIED':
        return (title: 'Wrong gate for this lane', sub: reason, icon: Icons.alt_route);
      default:
        return (title: 'Pass not approved', sub: reason, icon: Icons.cancel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner();
    final color = _cleared ? NcstColors.green : NcstColors.crimson;
    final locked = widget.saving || widget.retryPending || widget.invalidated;
    return Column(
      children: [
        _Banner(
          color: color,
          icon: banner.icon,
          title: banner.title,
          sub: banner.sub,
          menu: _menu(),
          // A way out when the wrong vehicle was scanned (not while a save is in flight or being retried)
          onClose: widget.saving || widget.retryPending ? null : widget.onScanNext,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScanNoticeStrip(notices: ScanNotice.fromVerify(widget.data)),
                if (_cleared)
                  for (final w in (widget.data['warnings'] as List? ?? []))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('$w', style: const TextStyle(color: NcstColors.goldDark, fontWeight: FontWeight.w600)),
                    ),
                _photos(),
                const SizedBox(height: 10),
                _facts(),
                if (!_cleared && '${widget.data['result']}' == 'ALREADY_INSIDE') ..._insideDetails(),
                if (_cleared && !_isVisitor && !_vip && _drivers.isNotEmpty) ...[const SizedBox(height: 10), _driverCard(locked)],
                if (_cleared && _vip) ...[const SizedBox(height: 10), _info('VIP pass: driver check not required')],
                if (_cleared && _isVisitor && (_visitorPass?.items.isNotEmpty ?? false)) ...[const SizedBox(height: 10), _itemsCard(locked)],
                if (_cleared && widget.onEvidenceChanged != null) ...[
                  const SizedBox(height: 6),
                  AbsorbPointer(
                    absorbing: locked,
                    child: EvidenceButton(expectedPlate: _plate, onChanged: widget.onEvidenceChanged!),
                  ),
                ],
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(widget.error!, style: const TextStyle(color: NcstColors.crimson, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
        _bottomBar(locked),
      ],
    );
  }

  String get _plate => _text(['plateNumber', 'plate_number']);

  /// Tall enough to recognise a face or a car, short enough to leave the driver card on the first screen.
  static const double _photoHeight = 132;

  Widget? _menu() {
    final items = <PopupMenuEntry<String>>[
      if (widget.onDetails != null) const PopupMenuItem(value: 'details', child: Text('View details or report incident')),
      if (widget.onIssueViolation != null) const PopupMenuItem(value: 'violation', child: Text('Issue violation')),
    ];
    if (items.isEmpty) return null;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (v) => v == 'details' ? widget.onDetails?.call() : widget.onIssueViolation?.call(),
      itemBuilder: (_) => items,
    );
  }

  Widget _photos() {
    final ownerPhoto = _text(['ownerPhotoUrl', 'ownerPhoto', 'owner_photo']);
    final vehiclePhoto = _isVisitor ? (_visitorPass?.vehiclePhoto ?? '') : _text(['vehiclePhoto', 'vehicle_photo']);
    return LayoutBuilder(
      builder: (context, box) {
        // Android reports a zero-width surface for the first frame; never build a negative size from it
        final tile = ((box.maxWidth - 12) / 2).clamp(0.0, 600.0);
        if (tile <= 0) return const SizedBox.shrink();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: tile,
              child: Column(
                children: [
                  DriverPhotoView(photoUrl: ownerPhoto, size: tile < _photoHeight ? tile : _photoHeight),
                  const SizedBox(height: 4),
                  Text(_isVisitor ? 'Visitor' : 'Owner', style: const TextStyle(fontSize: 12, color: NcstColors.slate600)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: tile,
              child: VehiclePhotoPanel(photoData: vehiclePhoto, height: _photoHeight, caption: 'Vehicle photo'),
            ),
          ],
        );
      },
    );
  }

  Widget _facts() {
    final visitor = _isVisitor ? _visitorPass : null;
    final desc = visitor != null
        ? visitor.vehicleModel
        : _text(['makeModelColor', 'make_model_color', 'vehicleModel', 'vehicleType']);
    final inside = widget.data['currentlyInside'] == true;
    final lastEntry = _text(['lastEntryTime', 'last_entry_time']);
    final gate = _text(['lastGatePoint', 'last_gate_point']);
    final rows = <(String, String)>[
      ('Owner', visitor?.visitorName ?? _text(['ownerName', 'owner_name'])),
      if (visitor != null) ...[
        ('Visiting', visitor.personToVisit),
        ('Purpose', visitor.purposeOfVisit),
        ('Valid', visitor.validDate),
      ] else ...[
        ('Role and ID', [_text(['ownerRole', 'owner_role']), _text(['ownerIdNumber', 'owner_id_number'])].where((s) => s.isNotEmpty).join(' · ')),
        ('Pass valid until', _date(_text(['passValidUntil', 'pass_valid_until']))),
        ('Fee', _text(['paymentStatus', 'payment_status'])),
        ('Department', _text(['department'])),
      ],
      ('Last movement', inside ? 'Inside${lastEntry.isEmpty ? '' : ' since ${_time(lastEntry)}'}${gate.isEmpty ? '' : ' · $gate'}' : 'Outside campus'),
    ].where((r) => r.$2.isNotEmpty).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (visitor?.plateNumber ?? _plate).toUpperCase(),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NcstColors.slate900),
            ),
            if (desc.isNotEmpty) Text(desc, style: const TextStyle(color: NcstColors.slate600)),
            const SizedBox(height: 8),
            Wrap(
              runSpacing: 8,
              children: [
                for (final r in rows)
                  FractionallySizedBox(
                    widthFactor: (r.$1 == 'Last movement' || r.$1 == 'Department') ? 1 : 0.5,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.$1, style: const TextStyle(fontSize: 11.5, color: NcstColors.slate500)),
                          Text(r.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Where the vehicle is and who to call (shown on an anti-passback refusal).
  List<Widget> _insideDetails() {
    final oc = widget.data['onCampus'];
    if (oc is! Map) return const [];
    final rows = <(String, String)>[
      ('Entered', _time((oc['entryTime'] ?? '').toString())),
      ('Gate', (oc['gatePoint'] ?? '').toString()),
      ('Driven in by', (oc['enteredBy'] ?? '').toString()),
      ('Admitted by', (oc['admittedBy'] ?? '').toString()),
      ('Owner phone', (oc['ownerPhone'] ?? '').toString()),
    ].where((r) => r.$2.isNotEmpty && r.$2 != 'null').toList();
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Already on campus', style: TextStyle(fontWeight: FontWeight.w800, color: NcstColors.crimson)),
              const SizedBox(height: 6),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 100, child: Text(r.$1, style: const TextStyle(color: NcstColors.slate600))),
                      Expanded(child: SelectableText(r.$2, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _info(String text) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text, style: const TextStyle(color: NcstColors.navy, fontWeight: FontWeight.w600))),
  );

  Widget _driverCard(bool locked) {
    final selected = _selectedDriver;
    final photo = '${selected?['photoUrl'] ?? ''}'.isNotEmpty
        ? '${selected?['photoUrl']}'
        : ('${selected?['fullName'] ?? ''}' == (_record['ownerName'] ?? '') ? _text(['ownerPhotoUrl', 'ownerPhoto']) : '');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Who is driving', style: TextStyle(fontSize: 12, color: NcstColors.slate500)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final d in _drivers)
                  if (int.tryParse('${d['id']}') != null)
                    ChoiceChip(
                      label: Text('${d['fullName'] ?? d['full_name']}'),
                      selected: '${d['id']}' == '$_driverId',
                      selectedColor: const Color(0xFFDCFCE7),
                      onSelected: locked ? null : (_) => setState(() => _driverId = int.parse('${d['id']}')),
                    ),
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  DriverPhotoView(photoUrl: photo, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${selected['relationship'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('License: ${selected['licenseNo'] ?? 'Not provided'}', style: const TextStyle(color: NcstColors.slate600)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemsCard(bool locked) {
    final items = _visitorPass!.items;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Declared items', style: TextStyle(fontSize: 12, color: NcstColors.slate500)),
            const SizedBox(height: 6),
            for (final i in items) Text('${i.name} × ${i.quantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            CheckboxListTile(
              key: const Key('itemsMatch'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Items match the pass'),
              value: _itemsOk,
              onChanged: locked ? null : (v) => setState(() { _itemsOk = v == true; _itemsHint = false; }),
            ),
            if (_itemsHint)
              const Text('Tick "Items match the pass" before allowing.', style: TextStyle(color: NcstColors.crimson, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(bool locked) {
    final lane = _shownLane;
    Widget bar(List<Widget> children) => Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Row(children: children)),
      ),
    );
    if (widget.invalidated) {
      return bar([
        Expanded(child: _BigButton(key: const Key('scanNext'), color: NcstColors.navy, icon: Icons.qr_code_scanner, label: 'Scan again', onPressed: widget.onScanNext)),
      ]);
    }
    if (!_cleared) {
      return bar([
        Expanded(flex: 2, child: _BigButton(key: const Key('scanNext'), color: NcstColors.navy, icon: Icons.qr_code_scanner, label: 'Scan next', onPressed: widget.onScanNext)),
        if (widget.onReport != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 60,
              child: OutlinedButton(key: const Key('reportRecord'), onPressed: locked ? null : _report, child: const Text('Report', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            ),
          ),
        ],
      ]);
    }
    return bar([
      Expanded(
        flex: 2,
        child: _BigButton(
          key: const Key('allowButton'),
          color: NcstColors.green,
          icon: lane == ScanLane.entry ? Icons.login : Icons.logout,
          label: widget.saving ? 'Saving…' : widget.retryPending ? 'Retry save' : 'Allow ${lane.verb}',
          busy: widget.saving,
          onPressed: widget.saving ? null : _allow,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _BigButton(
          key: const Key('blockButton'),
          color: NcstColors.crimson,
          icon: Icons.block,
          label: 'Block',
          onPressed: locked ? null : _block,
        ),
      ),
    ]);
  }

  void _allow() {
    final hasItems = _isVisitor && (_visitorPass?.items.isNotEmpty ?? false);
    if (hasItems && !_itemsOk && !widget.retryPending) {
      setState(() => _itemsHint = true);
      return;
    }
    widget.onAllow(_driverId, hasItems);
  }

  Future<void> _report() async {
    final decision = await showModalBottomSheet<BlockDecision>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlockSheet(
        plate: _plate.isEmpty ? (_visitorPass?.plateNumber ?? '') : _plate,
        lane: _shownLane,
        report: true,
        result: '${widget.data['result']}',
      ),
    );
    if (decision == null || !mounted) return;
    widget.onReport?.call(decision);
  }

  Future<void> _block() async {
    final decision = await showModalBottomSheet<BlockDecision>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlockSheet(plate: _plate.isEmpty ? (_visitorPass?.plateNumber ?? '') : _plate, lane: _shownLane),
    );
    if (decision == null || !mounted) return;
    final driver = _isVisitor
        ? (_visitorPass?.visitorName ?? '')
        : ('${_selectedDriver?['fullName'] ?? _selectedDriver?['full_name'] ?? _record['ownerName'] ?? ''}');
    widget.onBlock(decision, driver, _isVisitor ? 'Visitor (Day Pass)' : '${_selectedDriver?['relationship'] ?? 'Registered Owner'}');
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String sub;
  final Widget? menu;
  final VoidCallback? onClose;
  const _Banner({required this.color, required this.icon, required this.title, required this.sub, this.menu, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.25)),
              ],
            ),
          ),
          ?menu,
          IconButton(
            key: const Key('closeResult'),
            tooltip: 'Scan another',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const _BigButton({super.key, required this.color, required this.icon, required this.label, required this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        icon: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Icon(icon, size: 26),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

/// Block sheet: reason (the app's usual list), an optional note, an optional photo, then one red button.
class BlockSheet extends StatefulWidget {
  final String plate;
  final ScanLane lane;

  /// Report mode: reasons about the record, and the result opens a case instead of blocking a passage.
  final bool report;
  final String result;
  const BlockSheet({super.key, required this.plate, required this.lane, this.report = false, this.result = ''});

  @override
  State<BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<BlockSheet> {
  String? _reason;
  final _note = TextEditingController();
  PendingEvidence? _photo;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _note.text.trim();
    if (_reason == null) {
      setState(() => _error = 'Pick a reason.');
      return;
    }
    if (_reason == 'Other' && note.isEmpty) {
      setState(() => _error = 'Describe the reason in the note.');
      return;
    }
    Navigator.pop(context, BlockDecision(_reason!, note, _photo));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.report ? 'Report a problem with ${widget.plate}' : 'Block ${widget.lane.verb} for ${widget.plate}?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: widget.report ? NcstColors.navy : NcstColors.crimson),
            ),
            const SizedBox(height: 4),
            Text(
              widget.report
                  ? 'An admin case is opened and the vehicle is held until an admin reviews it.'
                  : 'The vehicle is held and a security incident is logged.',
              style: const TextStyle(color: NcstColors.slate600),
            ),
            const SizedBox(height: 8),
            for (final r in widget.report ? reportReasonsFor(widget.result) : kBlockReasons)
              ListTile(
                key: Key('reason_$r'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_reason == r ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: _reason == r ? NcstColors.crimson : NcstColors.slate400),
                title: Text(r, style: TextStyle(fontWeight: _reason == r ? FontWeight.w800 : FontWeight.w600)),
                onTap: () => setState(() {
                  _reason = r;
                  _error = null;
                }),
              ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('blockNote'),
              controller: _note,
              maxLines: 2,
              maxLength: 200,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: _reason == 'Other' ? 'Describe the reason' : 'Note (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
            EvidenceButton(expectedPlate: widget.plate, onChanged: (p) => _photo = p),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: const TextStyle(color: NcstColors.crimson, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: SizedBox(height: 52, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: const Key('confirmBlock'),
                      style: FilledButton.styleFrom(backgroundColor: widget.report ? NcstColors.navy : NcstColors.crimson),
                      onPressed: _submit,
                      child: Text(widget.report ? 'Report and open case' : 'Block and log', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after a passage is saved (green, returns to the camera by itself) or a vehicle is blocked (red, stays until the
/// guard taps Scan next so there is time to call the owner or issue a violation).
class ScanSavedView extends StatelessWidget {
  final bool blocked;
  final String title;
  final String plate;
  final String detail;
  final VoidCallback onNext;

  /// Blocked screen follow-ups.
  final String ownerName;
  final String ownerPhone;
  final VoidCallback? onIssueViolation;
  const ScanSavedView({
    super.key,
    required this.blocked,
    required this.title,
    required this.plate,
    required this.detail,
    required this.onNext,
    this.ownerName = '',
    this.ownerPhone = '',
    this.onIssueViolation,
  });

  Future<void> _call(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(Uri(scheme: 'tel', path: ownerPhone.replaceAll(RegExp(r'[^0-9+*#]'), '')));
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('This phone cannot place calls. Copy the number instead.')));
  }

  @override
  Widget build(BuildContext context) {
    final color = blocked ? NcstColors.crimson : NcstColors.green;
    final hasPhone = blocked && ownerPhone.trim().isNotEmpty;
    return Container(
      color: color,
      width: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(blocked ? Icons.block : Icons.check_circle, color: Colors.white, size: blocked ? 72 : 96),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(plate, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14)),
              if (hasPhone) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      Text(ownerName.isEmpty ? 'Owner' : 'Owner: $ownerName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      SelectableText(ownerPhone, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('callOwner'),
                              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color, minimumSize: const Size.fromHeight(46)),
                              onPressed: () => _call(context),
                              icon: const Icon(Icons.call),
                              label: const Text('Call owner', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            key: const Key('copyPhone'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white), minimumSize: const Size(64, 46)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: ownerPhone));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Number copied')));
                            },
                            child: const Text('Copy'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (blocked && onIssueViolation != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const Key('issueViolationAfterBlock'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white, width: 1.5)),
                    onPressed: onIssueViolation,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Issue violation', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                height: 52,
                child: FilledButton(
                  key: const Key('savedNext'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color),
                  onPressed: onNext,
                  child: const Text('Scan next', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
