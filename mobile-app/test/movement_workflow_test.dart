import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/models/scan_lane.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_result_view.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';

Map<String, dynamic> preview({bool outgoing = false, bool vip = true}) => {
  'accepted': true,
  'result': 'VALID',
  'vehicle': {
    'plateNumber': 'TEST 123',
    'ownerName': 'Test Owner',
    'makeModelColor': 'Blue car',
    'isVip': vip,
    'authorizedDrivers': [
      {'id': 1, 'fullName': 'Test Owner', 'relationship': 'Self (Owner)'},
    ],
  },
  'movement': {
    'ticket': 'same-signed-ticket',
    'currentStatus': outgoing ? 'INSIDE' : 'OUTSIDE',
    'suggestedAction': outgoing ? 'OUT' : 'IN',
    'checkpoint': 'Checkpoint 2',
  },
};

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

ScanResultView resultView(
  Map<String, dynamic> data, {
  ScanLane lane = ScanLane.entry,
  bool saving = false,
  bool retryPending = false,
  bool invalidated = false,
  void Function(int?, bool)? onAllow,
  void Function(String, String, String)? onBlock,
  VoidCallback? onReport,
  VoidCallback? onDetails,
  VoidCallback? onIssueViolation,
  ValueChanged<dynamic>? onEvidenceChanged,
}) => ScanResultView(
  data: data,
  lane: lane,
  gateLabel: 'Gate 1',
  saving: saving,
  retryPending: retryPending,
  invalidated: invalidated,
  onAllow: onAllow ?? (_, _) {},
  onBlock: onBlock ?? (_, _, _) {},
  onScanNext: () {},
  onReport: onReport,
  onDetails: onDetails,
  onIssueViolation: onIssueViolation,
  onEvidenceChanged: onEvidenceChanged == null ? null : (p) => onEvidenceChanged(p),
);

void main() {
  setUp(() {
    ApiService.resetClient();
    LocalCacheService.clearMemoryCache();
  });
  tearDown(ApiService.resetClient);

  Future<void> screen(
    WidgetTester tester, {
    required List<Map<String, dynamic>> requests,
    required Future<http.Response> Function(Map<String, dynamic>) confirm,
    required VoidCallback decision,
    bool outgoing = false,
    Map<String, dynamic>? prepared,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.setClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response('{"status":"success","data":{}}', 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        if (body['action'] == 'prepare') {
          return http.Response(
            jsonEncode({'status': 'success', 'data': prepared ?? preview(outgoing: outgoing)}),
            200,
          );
        }
        return confirm(body);
      }),
    );
    ApiService.authToken = 'staff-test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrScannerScreen(
            isEmbedded: true,
            automaticMovement: true,
            onDecision: (_) => decision(),
          ),
        ),
      ),
    );
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    state.testProcessRawQrCode('existing-qr-format');
    await tester.pumpAndSettle();
  }

  testWidgets('scan shows the result and sends the lane; nothing is saved until Allow', (tester) async {
    final requests = <Map<String, dynamic>>[];
    await screen(
      tester,
      requests: requests,
      confirm: (_) async => throw StateError('Must not submit'),
      decision: () => fail('Must not save'),
    );
    expect(find.text('Clear to enter'), findsOneWidget);
    expect(find.text('Allow entry'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    await tester.tap(find.text('Re-Scan QR'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r['action']), ['prepare']);
    expect(requests.single['direction'], 'IN', reason: 'the phone tells the server which lane the guard is in');
    expect(find.byType(ScanResultView), findsNothing);
  });

  testWidgets('inside vehicle clears an exit; rapid taps submit once, then a green flash', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final reply = Completer<http.Response>();
    var decisions = 0;
    await screen(
      tester,
      outgoing: true,
      requests: requests,
      confirm: (_) => reply.future,
      decision: () => decisions++,
    );
    expect(find.text('Clear to leave'), findsOneWidget);
    final button = find.text('Allow exit');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(decisions, 0);
    expect(requests.where((r) => r['action'] == 'confirm').length, 1);
    reply.complete(
      http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'id': 10,
            'action': 'OUT',
            'plateNumber': 'TEST 123',
            'currentStatus': 'OUTSIDE',
            'loggedAt': '2026-10-09 12:00:00',
          },
        }),
        201,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(decisions, 1);
    expect(find.text('Exit recorded'), findsOneWidget);
    expect(find.text('TEST 123'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Exit recorded'), findsNothing, reason: 'the camera comes back by itself');
  });

  testWidgets('uncertain network result retains identical ticket for retry', (tester) async {
    final requests = <Map<String, dynamic>>[];
    var attempts = 0;
    var decisions = 0;
    await screen(
      tester,
      requests: requests,
      decision: () => decisions++,
      confirm: (_) async {
        if (++attempts == 1) {
          return http.Response(
            '{"status":"error","message":"Connection interrupted","data":{"code":"CONFIRM_RETRY"}}',
            503,
          );
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'id': 11,
              'duplicate': true,
              'action': 'IN',
              'plateNumber': 'TEST 123',
              'currentStatus': 'INSIDE',
              'loggedAt': '2026-10-09 12:00:00',
            },
          }),
          200,
        );
      },
    );
    await tester.tap(find.text('Allow entry'));
    await tester.pumpAndSettle();
    expect(decisions, 0);
    expect(find.text('Retry save'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry save'));
    await tester.tap(find.text('Retry save'));
    await tester.pump();
    await tester.pump();
    final submissions = requests.where((r) => r['action'] == 'confirm').toList();
    expect(submissions.length, 2);
    expect(submissions[0], submissions[1]);
    expect(decisions, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('stale scan displays error and never reports success', (tester) async {
    final requests = <Map<String, dynamic>>[];
    var decisions = 0;
    await screen(
      tester,
      requests: requests,
      decision: () => decisions++,
      confirm: (_) async => http.Response(
        '{"status":"error","message":"Another transaction changed this vehicle. Scan again.","data":{"code":"STALE_SCAN"}}',
        409,
      ),
    );
    await tester.tap(find.text('Allow entry'));
    await tester.pumpAndSettle();
    expect(decisions, 0);
    expect(find.text('Scan again'), findsOneWidget);
    expect(find.textContaining('Another transaction changed'), findsOneWidget);
    expect(find.text('Allow entry'), findsNothing, reason: 'a stale scan cannot be allowed');
  });

  testWidgets('anti-passback: an entry-lane scan of a vehicle already inside is refused with Report', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final refused = preview(outgoing: true)
      ..['accepted'] = false
      ..['result'] = 'ALREADY_INSIDE'
      ..['reason'] = 'Already recorded inside.'
      ..['currentlyInside'] = true
      ..['movement'] = null
      ..['onCampus'] = {'entryTime': '2026-10-09 07:42:00', 'gatePoint': 'Gate 1 (Main Ingress)'};
    await screen(
      tester,
      requests: requests,
      prepared: refused,
      confirm: (body) async => http.Response(jsonEncode({'status': 'success', 'data': {'reported': true}}), 201),
      decision: () => fail('Nothing may be saved'),
    );
    expect(find.text('Already inside'), findsOneWidget);
    expect(find.text('Allow entry'), findsNothing);
    expect(find.byKey(const Key('reportRecord')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reportRecord')));
    await tester.pumpAndSettle();
    final report = requests.last;
    expect(report['action'], 'report_discrepancy');
    expect(report['recorded'], 'INSIDE');
    expect(report['plate'], 'TEST 123');
  });

  testWidgets('ordinary pass: the owner is preselected and one tap saves', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? driver = -1;
    var saved = 0;
    await tester.pumpWidget(host(resultView(
      preview(vip: false),
      onAllow: (id, _) { driver = id; saved++; },
    )));
    await tester.tap(find.byKey(const Key('allowButton')));
    expect(saved, 1);
    expect(driver, 1, reason: 'the owner is chosen without any extra tap');
  });

  testWidgets('result keeps release, capacity and evidence controls and a More menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = preview(outgoing: true);
    data['occupancy'] = {'level': 'full', 'message': 'Campus parking is FULL'};
    data['exitRelease'] = {'releasedBy': 'Test Admin', 'expiresAt': '2026-10-09 12:30:00', 'reason': 'Emergency'};
    var inspected = false;
    await tester.pumpWidget(host(resultView(data, onEvidenceChanged: (_) {}, onDetails: () => inspected = true)));
    expect(find.text('Campus parking is FULL'), findsOneWidget);
    expect(find.textContaining('Exit released'), findsOneWidget);
    expect(find.text('Photo of vehicle / plate'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details or report incident'));
    expect(inspected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain confirmation locks Block and offers a retry', (tester) async {
    await tester.pumpWidget(host(resultView(preview(outgoing: true), retryPending: true)));
    final block = tester.widget<FilledButton>(find.descendant(of: find.byKey(const Key('blockButton')), matching: find.byType(FilledButton)));
    expect(block.onPressed, isNull);
    expect(find.text('Retry save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
