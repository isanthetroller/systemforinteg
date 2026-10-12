import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/scanner/models/scan_lane.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_lane_bar.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_result_view.dart';

Map<String, dynamic> vehicle({List<Map<String, dynamic>>? drivers}) => {
  'plateNumber': 'ABC 1234',
  'ownerName': 'Juan Dela Cruz',
  'ownerRole': 'Student',
  'ownerIdNumber': '2024-05182',
  'department': 'BSIT',
  'makeModelColor': 'Toyota Vios, white',
  'passValidUntil': '2026-12-31',
  'paymentStatus': 'Paid',
  'authorizedDrivers': drivers ??
      [
        {'id': 7, 'fullName': 'Maria Dela Cruz', 'relationship': 'Mother'},
        {'id': 8, 'fullName': 'Juan Dela Cruz', 'relationship': 'Self (Owner)'},
      ],
};

Map<String, dynamic> cleared({bool outgoing = false}) => {
  'accepted': true,
  'result': 'VALID',
  'vehicle': vehicle(),
  'movement': {'ticket': 't', 'currentStatus': outgoing ? 'INSIDE' : 'OUTSIDE', 'suggestedAction': outgoing ? 'OUT' : 'IN', 'checkpoint': 'Gate 1'},
};

Map<String, dynamic> refused(String result, {String reason = 'Not allowed.', bool inside = false}) => {
  'accepted': false,
  'result': result,
  'reason': reason,
  'currentlyInside': inside,
  'vehicle': vehicle(),
  'movement': null,
};

Widget view(
  Map<String, dynamic> data, {
  void Function(int?, bool)? onAllow,
  void Function(String, String, String)? onBlock,
  VoidCallback? onReport,
}) => MaterialApp(
  home: Scaffold(
    body: ScanResultView(
      data: data,
      lane: ScanLane.entry,
      gateLabel: 'Gate 1',
      saving: false,
      retryPending: false,
      invalidated: false,
      onAllow: onAllow ?? (_, _) {},
      onBlock: onBlock ?? (_, _, _) {},
      onScanNext: () {},
      onReport: onReport,
    ),
  ),
);

void main() {
  group('lane rules', () {
    test('Gate 1 account is locked to the entry lane', () {
      final c = LaneConfig.from(assignedGate: 'Gate 1 (Main Ingress)');
      expect(c.locked, isTrue);
      expect(c.resolve(ScanLane.exit), ScanLane.entry, reason: 'a saved exit lane cannot override the account');
      expect(c.gateFor(ScanLane.entry), 'Gate 1');
    });

    test('Gate 2 account is locked to the exit lane', () {
      final c = LaneConfig.from(assignedGate: 'Gate 2 (Main Egress)');
      expect(c.locked, isTrue);
      expect(c.defaultLane, ScanLane.exit);
    });

    test('event mode lets a Gate 1 guard switch lanes and keeps the gate', () {
      final c = LaneConfig.from(
        assignedGate: 'Gate 1 (Main Ingress)',
        policy: {'mode': 'event', 'gateNumber': 1, 'allowedDirections': ['Ingress', 'Egress']},
      );
      expect(c.locked, isFalse);
      expect(c.resolve(ScanLane.exit), ScanLane.exit);
      expect(c.gateFor(ScanLane.exit), 'Gate 1');
    });

    test('All Gates account switches lanes and the lane names the gate', () {
      final c = LaneConfig.from(assignedGate: 'All Gates', policy: {'mode': 'normal', 'gateNumber': null, 'allowedDirections': ['Ingress', 'Egress']});
      expect(c.locked, isFalse);
      expect(c.gateFor(ScanLane.entry), 'Gate 1');
      expect(c.gateFor(ScanLane.exit), 'Gate 2');
    });

    test('the server policy wins over the account text', () {
      final c = LaneConfig.from(assignedGate: 'Gate 1', policy: {'gateNumber': 1, 'allowedDirections': ['Ingress']});
      expect(c.locked, isTrue);
    });

    test('lane codes match what the server expects', () {
      expect(ScanLane.entry.code, 'IN');
      expect(ScanLane.exit.code, 'OUT');
    });
  });

  testWidgets('lane bar: locked account shows a lock, flexible account an IN / OUT switch', (tester) async {
    ScanLane? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ScanLaneBar(config: LaneConfig.from(assignedGate: 'Gate 1'), lane: ScanLane.entry, enabled: true, onChanged: (_) {}),
          ScanLaneBar(config: LaneConfig.from(assignedGate: 'All Gates'), lane: ScanLane.entry, enabled: true, onChanged: (l) => picked = l),
        ]),
      ),
    ));
    expect(find.byKey(const Key('laneLocked')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lane_OUT')));
    expect(picked, ScanLane.exit);
  });

  testWidgets('lane switch is disabled while a result is on screen', (tester) async {
    ScanLane? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ScanLaneBar(config: LaneConfig.from(assignedGate: 'All Gates'), lane: ScanLane.entry, enabled: false, onChanged: (l) => picked = l)),
    ));
    await tester.tap(find.byKey(const Key('lane_OUT')));
    expect(picked, isNull);
  });

  testWidgets('cleared entry: green banner, photos, facts, green Allow and red Block', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(view(cleared()));
    expect(find.text('Clear to enter'), findsOneWidget);
    expect(find.text('ABC 1234'), findsOneWidget);
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('Vehicle photo'), findsOneWidget);
    expect(find.text('Toyota Vios, white'), findsOneWidget);
    expect(find.text('Student · 2024-05182'), findsOneWidget);
    expect(find.text('31 Dec 2026'), findsOneWidget);
    final allow = tester.widget<FilledButton>(find.descendant(of: find.byKey(const Key('allowButton')), matching: find.byType(FilledButton)));
    final block = tester.widget<FilledButton>(find.descendant(of: find.byKey(const Key('blockButton')), matching: find.byType(FilledButton)));
    expect(allow.style!.backgroundColor!.resolve({}), const Color(0xFF16A34A));
    expect(block.style!.backgroundColor!.resolve({}), const Color(0xFFD92128));
  });

  testWidgets('the owner is preselected even when another driver is listed first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? driver;
    await tester.pumpWidget(view(cleared(), onAllow: (id, _) => driver = id));
    await tester.tap(find.byKey(const Key('allowButton')));
    expect(driver, 8);
  });

  testWidgets('choosing another driver is a single tap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? driver;
    await tester.pumpWidget(view(cleared(), onAllow: (id, _) => driver = id));
    await tester.tap(find.text('Maria Dela Cruz'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('allowButton')));
    expect(driver, 7);
  });

  for (final c in const [
    ('ALREADY_INSIDE', 'Already inside'),
    ('NOT_ON_CAMPUS', 'Not on campus'),
    ('BANNED', 'Security hold'),
    ('EXPIRED', 'Pass expired'),
    ('UNPAID', 'Fee unpaid'),
    ('FORGED', 'Forged or edited pass'),
  ]) {
    testWidgets('${c.$1}: red banner "${c.$2}" and no Allow button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(view(refused(c.$1)));
      expect(find.text(c.$2), findsOneWidget);
      expect(find.byKey(const Key('allowButton')), findsNothing);
      expect(find.byKey(const Key('scanNext')), findsOneWidget);
    });
  }

  testWidgets('passback shows Report and where the vehicle entered', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reported = false;
    final data = refused('ALREADY_INSIDE', inside: true)
      ..['onCampus'] = {'entryTime': '2026-10-09 07:42:00', 'gatePoint': 'Gate 1 (Main Ingress)', 'ownerPhone': '0917 000 0000'};
    await tester.pumpWidget(view(data, onReport: () => reported = true));
    expect(find.text('Already on campus'), findsOneWidget);
    expect(find.text('Gate 1 (Main Ingress)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reportRecord')));
    expect(reported, isTrue);
  });

  testWidgets('Block asks for a reason once, then reports it with the driver', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? reason;
    String? driver;
    await tester.pumpWidget(view(cleared(), onBlock: (r, d, _) { reason = r; driver = d; }));
    await tester.tap(find.byKey(const Key('blockButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fake or damaged pass'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmBlock')));
    await tester.pumpAndSettle();
    expect(reason, 'Fake or damaged pass');
    expect(driver, 'Juan Dela Cruz');
  });

  testWidgets('visitor with declared items needs the single Items match tick', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var saved = 0;
    bool? verified;
    final data = {
      'accepted': true,
      'result': 'VALID',
      'visitor': {
        'id': 5, 'passCode': 'VP-1', 'visitorName': 'Pedro Santos', 'plateNumber': 'VIS 3340', 'vehicleModel': 'Van',
        'purposeOfVisit': 'Pickup', 'personToVisit': 'Registrar', 'validDate': 'Today', 'status': 'Active',
        'items': [{'name': 'Laptop bag', 'quantity': 1}],
      },
      'movement': {'ticket': 't', 'currentStatus': 'OUTSIDE', 'suggestedAction': 'IN', 'checkpoint': 'Gate 1'},
    };
    await tester.pumpWidget(view(data, onAllow: (_, v) { saved++; verified = v; }));
    await tester.tap(find.byKey(const Key('allowButton')));
    await tester.pump();
    expect(saved, 0, reason: 'items must be ticked first');
    expect(find.textContaining('before allowing'), findsOneWidget);
    await tester.tap(find.byKey(const Key('itemsMatch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('allowButton')));
    expect(saved, 1);
    expect(verified, isTrue);
  });
}
