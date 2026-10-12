import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/constants/app_constants.dart';
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
  void Function(BlockDecision, String, String)? onBlock,
  void Function(BlockDecision)? onReport,
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
    BlockDecision? reported;
    final data = refused('ALREADY_INSIDE', inside: true)
      ..['onCampus'] = {'entryTime': '2026-10-09 07:42:00', 'gatePoint': 'Gate 1 (Main Ingress)', 'ownerPhone': '0917 000 0000'};
    await tester.pumpWidget(view(data, onReport: (d) => reported = d));
    expect(find.text('Already on campus'), findsOneWidget);
    expect(find.text('Gate 1 (Main Ingress)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reportRecord')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reason_Pass used by another vehicle or driver')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmBlock')));
    await tester.pumpAndSettle();
    expect(reported!.reason, 'Pass used by another vehicle or driver');
  });

  group('Report sheet', () {
    Future<void> openReport(WidgetTester tester, String result, {void Function(BlockDecision)? onReport}) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(view(refused(result, inside: result == 'ALREADY_INSIDE'), onReport: onReport ?? (_) {}));
      await tester.tap(find.byKey(const Key('reportRecord')));
      await tester.pumpAndSettle();
    }

    testWidgets('says the vehicle is held, offers note and photo, and the report button', (tester) async {
      await openReport(tester, 'ALREADY_INSIDE');
      expect(find.text('Report a problem with ABC 1234'), findsOneWidget);
      expect(find.textContaining('held until an admin reviews it'), findsOneWidget);
      expect(find.byKey(const Key('blockNote')), findsOneWidget);
      expect(find.text('Photo of vehicle / plate'), findsOneWidget);
      expect(find.text('Report and open case'), findsOneWidget);
      expect(find.text('Block and log'), findsNothing);
    });

    testWidgets('the first reason matches which way the record is wrong', (tester) async {
      await openReport(tester, 'ALREADY_INSIDE');
      expect(find.byKey(const Key('reason_Vehicle already left (exit was not scanned)')), findsOneWidget);
      expect(find.byKey(const Key('reason_Vehicle is on campus (entry was not scanned)')), findsNothing);
    });

    testWidgets('a reason is required, and Other needs a description', (tester) async {
      BlockDecision? sent;
      await openReport(tester, 'ALREADY_INSIDE', onReport: (d) => sent = d);
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pump();
      expect(find.text('Pick a reason.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reason_Other')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pump();
      expect(find.text('Describe the reason in the note.'), findsOneWidget);
      expect(sent, isNull);
    });
  });

  group('Block sheet', () {
    Future<void> openSheet(WidgetTester tester, void Function(BlockDecision, String, String) onBlock) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(view(cleared(), onBlock: onBlock));
      await tester.tap(find.byKey(const Key('blockButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('offers the original reasons and reports the choice with the driver', (tester) async {
      BlockDecision? decision;
      String? driver;
      await openSheet(tester, (d, drv, _) { decision = d; driver = drv; });
      for (final r in AppConstants.defaultBlockReasons) {
        expect(find.byKey(Key('reason_$r')), findsOneWidget, reason: 'the reasons the app always had are kept');
      }
      await tester.tap(find.byKey(const Key('reason_Invalid / Revoked QR Pass')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pumpAndSettle();
      expect(decision!.reason, 'Invalid / Revoked QR Pass');
      expect(decision!.note, isEmpty);
      expect(driver, 'Juan Dela Cruz');
    });

    testWidgets('a reason is required and a note travels with it', (tester) async {
      BlockDecision? decision;
      await openSheet(tester, (d, _, _) => decision = d);
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pump();
      expect(find.text('Pick a reason.'), findsOneWidget);
      expect(decision, isNull);
      await tester.tap(find.byKey(const Key('reason_Suspicious behavior')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('blockNote')), 'Driver would not show a license');
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pumpAndSettle();
      expect(decision!.reason, 'Suspicious behavior');
      expect(decision!.text, 'Suspicious behavior: Driver would not show a license');
    });

    testWidgets('Other needs a description', (tester) async {
      BlockDecision? decision;
      await openSheet(tester, (d, _, _) => decision = d);
      await tester.tap(find.byKey(const Key('reason_Other')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pump();
      expect(find.text('Describe the reason in the note.'), findsOneWidget);
      expect(decision, isNull);
    });

    testWidgets('the sheet offers a photo', (tester) async {
      await openSheet(tester, (_, _, _) {});
      expect(find.text('Photo of vehicle / plate'), findsOneWidget);
    });
  });

  group('after a block', () {
    testWidgets('the red screen offers Call owner, Copy and Issue violation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var violation = 0;
      var next = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScanSavedView(
            blocked: true,
            title: 'Entry blocked',
            plate: 'ABC 1234',
            detail: 'Suspicious behavior · logged as an incident',
            ownerName: 'Juan Dela Cruz',
            ownerPhone: '0917 123 4567',
            onIssueViolation: () => violation++,
            onNext: () => next++,
          ),
        ),
      ));
      expect(find.text('Entry blocked'), findsOneWidget);
      expect(find.text('0917 123 4567'), findsOneWidget);
      expect(find.byKey(const Key('callOwner')), findsOneWidget);
      await tester.tap(find.byKey(const Key('issueViolationAfterBlock')));
      await tester.tap(find.byKey(const Key('savedNext')));
      expect(violation, 1);
      expect(next, 1);
    });

    testWidgets('the case reference is shown and the violation button says it is an extra', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScanSavedView(blocked: true, title: 'Entry blocked', plate: 'ABC 1234', detail: 'd', caseRef: 'SEC-0012', onIssueViolation: () {}, onNext: () {}),
        ),
      ));
      expect(find.byKey(const Key('caseRef')), findsOneWidget);
      expect(find.text('Case SEC-0012'), findsOneWidget);
      expect(find.text('Also issue a violation'), findsOneWidget);
    });

    testWidgets('no phone number means no call buttons, and a green save never offers them', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ScanSavedView(blocked: true, title: 'Exit blocked', plate: 'X 1', detail: 'd', onNext: () {})),
      ));
      expect(find.byKey(const Key('callOwner')), findsNothing);
      expect(find.byKey(const Key('issueViolationAfterBlock')), findsNothing);
    });
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
