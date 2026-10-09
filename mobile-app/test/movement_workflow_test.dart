import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/widgets/movement_confirmation_card.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';

Map<String, dynamic> preview({bool outgoing = false, bool vip = true}) => {
  'accepted': true,
  'vehicle': {
    'plateNumber': 'TEST 123',
    'ownerName': 'Test Owner',
    'makeModelColor': 'Blue car',
    'isVip': vip,
    'authorizedDrivers': [
      {'id': 1, 'fullName': 'Test Owner'},
    ],
  },
  'movement': {
    'ticket': 'same-signed-ticket',
    'currentStatus': outgoing ? 'INSIDE' : 'OUTSIDE',
    'suggestedAction': outgoing ? 'OUT' : 'IN',
    'checkpoint': 'Checkpoint 2',
  },
};

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
            jsonEncode({
              'status': 'success',
              'data': preview(outgoing: outgoing),
            }),
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

  testWidgets('scan and cancel do not submit a movement', (tester) async {
    final requests = <Map<String, dynamic>>[];
    await screen(
      tester,
      requests: requests,
      confirm: (_) async => throw StateError('Must not submit'),
      decision: () => fail('Must not save'),
    );
    expect(find.text('OUTSIDE'), findsOneWidget);
    expect(find.text('Confirm Entry'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r['action']), ['prepare']);
    expect(find.byType(MovementConfirmationCard), findsNothing);
  });

  testWidgets(
    'inside vehicle suggests exit; rapid taps submit once and wait for save',
    (tester) async {
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
      expect(find.text('INSIDE'), findsOneWidget);
      final button = find.text('Confirm Exit');
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
      await tester.pumpAndSettle();
      expect(decisions, 1);
      expect(find.text('Exit saved: TEST 123 is now OUTSIDE.'), findsOneWidget);
    },
  );

  testWidgets('uncertain network result retains identical ticket for retry', (
    tester,
  ) async {
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
    await tester.tap(find.text('Confirm Entry'));
    await tester.pumpAndSettle();
    expect(decisions, 0);
    expect(find.text('Retry confirmation'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry confirmation'));
    await tester.tap(find.text('Retry confirmation'));
    await tester.pumpAndSettle();
    final submissions = requests
        .where((r) => r['action'] == 'confirm')
        .toList();
    expect(submissions.length, 2);
    expect(submissions[0], submissions[1]);
    expect(decisions, 1);
  });

  testWidgets('stale scan displays error and never reports success', (
    tester,
  ) async {
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
    await tester.tap(find.text('Confirm Entry'));
    await tester.pumpAndSettle();
    expect(decisions, 0);
    expect(find.text('Scan again'), findsOneWidget);
    expect(find.textContaining('Another transaction changed'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'ordinary passes require explicit driver selection and identity check',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MovementConfirmationCard(
              preview: preview(vip: false),
              guardName: 'Guard 2',
              saving: false,
              retryPending: false,
              invalidated: false,
              onConfirm: (_, _) => saved++,
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Owner').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('I checked the selected driver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Entry'));
      expect(saved, 1);
    },
  );
}
