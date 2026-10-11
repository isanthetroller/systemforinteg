import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:systemforinteg/features/visitor/screens/visitor_pass_confirmation_screen.dart';
import 'package:systemforinteg/features/visitor/screens/visitor_registration_screen.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';

void main() {
  final guard = GuardUser(
    id: '91', username: 'guard1', fullName: 'Officer UI',
    badgeNumber: 'UI-91', role: GuardRole.entrance,
    assignedGate: 'Checkpoint 1', loginTime: DateTime.now(),
  );
  final writes = <Map<String, dynamic>>[];
  var rejectPass = false;
  var rejectEntry = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalCacheService.clearMemoryCache();
    ApiService.authToken = 'widget-token';
    writes.clear();
    rejectPass = false;
    rejectEntry = false;
    ApiService.setClientForTesting(MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/visitors.php')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        writes.add({'path': 'visitors', ...body});
        if (rejectPass) {
          return http.Response(jsonEncode({'status': 'error', 'message': 'An active day pass already exists.'}), 409);
        }
        return http.Response(jsonEncode({'status': 'success', 'data': {
          ...body, 'id': 91, 'passCode': body['passId'],
          'validDate': DateTime.now().toIso8601String().substring(0, 10),
          'qrPayload': 'signed-visitor-qr',
        }}), 201);
      }
      if (request.method == 'POST' && path.endsWith('/logs.php')) {
        writes.add({'path': 'logs', ...jsonDecode(request.body) as Map<String, dynamic>});
        if (rejectEntry) {
          return http.Response(jsonEncode({'status': 'error', 'message': 'Gate audit rejected entry.'}), 403);
        }
        return http.Response(jsonEncode({'status': 'success', 'data': {'id': 111}}), 201);
      }
      return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
    }));
  });
  tearDown(() {
    ApiService.resetClient();
    ApiService.authToken = null;
  });

  Future<void> fillChecklist(WidgetTester tester, String plate) async {
    await tester.ensureVisible(find.text('Awaiting ID scan or manual input'));
    await tester.tap(find.text('Awaiting ID scan or manual input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Visitor Full Name *'), 'UI Visitor');
    await tester.enterText(find.widgetWithText(TextField, 'Contact Mobile Number'), '09123456789');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Awaiting plate scan or manual input'));
    await tester.tap(find.text('Awaiting plate scan or manual input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'License Plate *'), plate);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    final purpose = find.widgetWithText(TextField, 'Purpose of Visit & Host Destination *');
    await tester.ensureVisible(purpose);
    await tester.enterText(purpose, 'Visit Science Office');
    await tester.pump();
  }

  testWidgets('visitor checklist creates a pass and gate audit from screen taps', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(currentGuard: guard)));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'COMPLETE REQUIRED FIELDS')).onPressed, isNull);
    await fillChecklist(tester, 'UI-1234');
    final issue = find.widgetWithText(ElevatedButton, 'ISSUE VISITOR QR PASS');
    expect(tester.widget<ElevatedButton>(issue).onPressed, isNotNull);
    await tester.tap(issue);
    await tester.pumpAndSettle();
    expect(find.byType(VisitorPassConfirmationScreen), findsOneWidget);
    expect(writes.where((w) => w['path'] == 'visitors').length, 1);
    expect(writes.where((w) => w['path'] == 'logs').length, 1);
    expect(writes.first['plateNumber'], 'UI-1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets('server refusal leaves visitor checklist and shows its reason', (tester) async {
    rejectPass = true;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(currentGuard: guard)));
    await tester.pump();
    await fillChecklist(tester, 'UI-5678');
    await tester.tap(find.widgetWithText(ElevatedButton, 'ISSUE VISITOR QR PASS'));
    await tester.pumpAndSettle();
    expect(find.byType(VisitorRegistrationScreen), findsOneWidget);
    expect(find.byType(VisitorPassConfirmationScreen), findsNothing);
    expect(find.textContaining('already exists'), findsOneWidget);
    expect(find.text('UI-5678'), findsWidgets);
    expect(writes.where((w) => w['path'] == 'logs'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('issued pass warns when its gate entry audit is refused', (tester) async {
    rejectEntry = true;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(currentGuard: guard)));
    await tester.pump();
    await fillChecklist(tester, 'UI-9012');
    await tester.tap(find.widgetWithText(ElevatedButton, 'ISSUE VISITOR QR PASS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Entry not recorded'), findsOneWidget);
    expect(find.textContaining('Gate audit rejected entry.'), findsOneWidget);
    expect(writes.where((w) => w['path'] == 'visitors').length, 1);
    expect(writes.where((w) => w['path'] == 'logs').length, 1);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.byType(VisitorPassConfirmationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration controls fit small phones and larger text', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0, 440.0]) {
      for (final scale in [1.0, 1.5]) {
        await tester.binding.setSurfaceSize(Size(width, 844));
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: VisitorRegistrationScreen(currentGuard: guard),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width=$width textScale=$scale');
      }
    }
  });

  testWidgets('camera failure never claims a security photo was captured', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(currentGuard: guard)));
    await tester.pump();
    await tester.tap(find.text('SNAP & SCAN ID'));
    await tester.pump();
    expect(find.textContaining('Camera unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(currentGuard: guard)));
    await tester.pump();
    await tester.tap(find.text('Photo').first);
    await tester.pump();
    await tester.tap(find.text('SNAP VEHICLE PHOTO'));
    await tester.pump();
    expect(find.textContaining('Vehicle photo was not captured'), findsOneWidget);
    expect(find.text('SECURITY SNAPSHOT RECORDED'), findsNothing);
    expect(find.text('RETAKE VEHICLE PHOTO'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR text moves from ID name to plate without accepting noise', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(currentGuard: guard)));
    await tester.pump();
    final state = tester.state(find.byType(VisitorRegistrationScreen)) as dynamic;
    state.testConsumeOcrText('NAME: JUAN PEDRO DELA CRUZ');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text('Juan Pedro Dela Cruz'), findsWidgets);
    expect(find.text('SNAP & SCAN PLATE'), findsOneWidget);
    state.testConsumeOcrText('PILIPINAS');
    await tester.pump();
    expect(find.text('SNAP & SCAN PLATE'), findsOneWidget);
    state.testConsumeOcrText('NDK 4821');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text('NDK-4821'), findsWidgets);
    expect(find.text('SNAP VEHICLE PHOTO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid camera bytes become a photo on the visitor pass', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bytes = img.encodeJpg(img.Image(width: 4, height: 4));
    await tester.pumpWidget(MaterialApp(home: VisitorRegistrationScreen(
      currentGuard: guard,
      capturePhotoBytesForTesting: () async => Uint8List.fromList(bytes),
    )));
    await tester.pump();
    await tester.tap(find.text('Photo').first);
    await tester.pump();
    await tester.tap(find.text('SNAP VEHICLE PHOTO'));
    await tester.pump();
    expect(find.text('SECURITY SNAPSHOT RECORDED'), findsOneWidget);
    expect(find.text('RETAKE VEHICLE PHOTO'), findsOneWidget);
    await fillChecklist(tester, 'UI-3456');
    await tester.tap(find.widgetWithText(ElevatedButton, 'ISSUE VISITOR QR PASS'));
    await tester.pumpAndSettle();
    expect(writes.first['vehiclePhoto'], startsWith('data:image/jpeg;base64,'));
    expect(tester.takeException(), isNull);
  });
}
