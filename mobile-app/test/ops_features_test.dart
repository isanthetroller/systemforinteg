import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/core/utils/plate_reader.dart';
import 'package:systemforinteg/features/guard/widgets/shift_banner.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_notice_strip.dart';
import 'package:systemforinteg/services/api_service.dart';

http.Response json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('PlateReader', () {
    test('fold ignores spaces, dashes, case and the usual camera confusions', () {
      expect(PlateReader.fold('abc 1234'), PlateReader.fold('ABC-1234'));
      expect(PlateReader.fold('N0K 4B21'), PlateReader.fold('NOK 4821'));
      expect(PlateReader.fold(''), '');
    });

    test('matches: same plate yes, a different plate no, nothing never', () {
      expect(PlateReader.matches('NDK-4821', 'NDK 4821'), isTrue);
      expect(PlateReader.matches('NDK-4S21', 'NDK 4521'), isTrue); // S read for 5
      expect(PlateReader.matches('NDK-4822', 'NDK 4821'), isFalse);
      expect(PlateReader.matches(null, 'NDK 4821'), isFalse);
      expect(PlateReader.matches('', ''), isFalse);
    });

    test('candidates finds plate-shaped text among other words', () {
      const text = 'PHILIPPINES\nNDK 4821\nMAR 2027\nAB 12345';
      final found = PlateReader.candidates(text);
      expect(found, contains('NDK-4821'));
      expect(found, contains('AB-12345'));
    });

    test('pick prefers the candidate that matches the pass, else the first, else null', () {
      const text = 'XYZ 9999 and also NDK 4821';
      expect(PlateReader.pick(text, 'NDK 4821'), 'NDK-4821');
      expect(PlateReader.pick(text, 'AAA 1111'), 'XYZ-9999');
      expect(PlateReader.pick('no plate here', 'NDK 4821'), isNull);
    });
  });

  group('ScanNotice.fromVerify', () {
    test('nothing special -> no notices', () {
      expect(ScanNotice.fromVerify({'occupancy': {'level': 'ok'}}), isEmpty);
      expect(ScanNotice.fromVerify(null), isEmpty);
    });

    test('parking nearly full warns, full is a danger notice (entry stays the guard\'s decision)', () {
      final nearly = ScanNotice.fromVerify({'occupancy': {'level': 'nearly_full', 'message': 'Campus parking is nearly full (95 of 100).'}});
      expect(nearly.single.level, ScanNoticeLevel.warning);
      final full = ScanNotice.fromVerify({'occupancy': {'level': 'full', 'message': 'Campus parking is FULL (100 of 100).'}});
      expect(full.single.level, ScanNoticeLevel.danger);
      expect(full.single.detail, contains('still your decision'));
    });

    test('an exit release names who released it, until when, and why', () {
      final n = ScanNotice.fromVerify({
        'exitRelease': {'releasedBy': 'Admin One', 'expiresAt': '2026-10-08 14:30:00', 'reason': 'Family emergency'},
      });
      expect(n.single.title, contains('Admin One'));
      expect(n.single.title, contains('2:30 PM'));
      expect(n.single.detail, contains('Family emergency'));
    });

    test('the case holding the vehicle shows its step and a police referral', () {
      final n = ScanNotice.fromVerify({
        'case': {'title': 'Parking in Fire Lane', 'step': 'Awaiting clearance', 'policeReferred': true},
      });
      expect(n.single.title, contains('Awaiting clearance'));
      expect(n.single.title, contains('police'));
    });

    testWidgets('ScanNoticeStrip renders every notice and nothing when empty', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ScanNoticeStrip(notices: [
        ScanNotice(ScanNoticeLevel.warning, 'Parking is nearly full'),
        ScanNotice(ScanNoticeLevel.info, 'Case: X', 'Stays on hold'),
      ]))));
      expect(find.text('Parking is nearly full'), findsOneWidget);
      expect(find.text('Stays on hold'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ScanNoticeStrip(notices: []))));
      expect(find.byKey(const Key('scanNoticeStrip')), findsNothing);
    });
  });

  group('ApiService: shifts, evidence, violations, gate logs', () {
    final seen = <String, Map<String, dynamic>>{};

    setUp(() {
      seen.clear();
      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async {
        final path = request.url.path;
        final body = request.body.isNotEmpty ? jsonDecode(request.body) as Map<String, dynamic> : <String, dynamic>{};
        seen['${request.method} ${path.split('/').last}'] = body;
        if (path.endsWith('shifts.php') && request.method == 'GET') {
          return json(200, {'status': 'success', 'data': {'onDuty': [], 'mine': null, 'handover': {'guard': 'Guard A', 'gate': 'Gate 1', 'handoverNotes': 'Gate arm is jammed'}}});
        }
        if (path.endsWith('shifts.php')) {
          if (body['action'] == 'start') {
            return json(201, {'status': 'success', 'data': {'shift': {'id': 7, 'gate': body['gate'], 'startedAt': '2026-10-08 08:00:00'}, 'handover': null}});
          }
          return json(200, {'status': 'success', 'message': 'Shift ended.'});
        }
        if (path.endsWith('evidence.php')) {
          return body['kind'] == 'bogus' ? json(400, {'status': 'error', 'message': 'kind must be one of: entry, exit, violation, incident.'}) : json(201, {'status': 'success', 'data': {'id': 3}});
        }
        if (path.endsWith('violations.php')) {
          return json(201, {'status': 'success', 'data': {'violation': {'id': 42}}});
        }
        if (path.endsWith('logs.php')) {
          return json(201, {'status': 'success', 'data': {'id': 99}});
        }
        if (path.endsWith('sync.php')) return json(200, {'status': 'success', 'data': {'results': []}});
        return json(404, {'status': 'error', 'message': 'not found'});
      }));
    });

    tearDown(ApiService.resetClient);

    test('fetchShifts returns my shift and the handover note', () async {
      final data = await ApiService.fetchShifts();
      expect(data, isNotNull);
      expect(data!['mine'], isNull);
      expect((data['handover'] as Map)['handoverNotes'], 'Gate arm is jammed');
    });

    test('startShift sends the gate; endShift sends the handover note', () async {
      final started = await ApiService.startShift('Gate 2 (Main Egress)');
      expect(started['error'], isNull);
      expect(seen['POST shifts.php']!['gate'], 'Gate 2 (Main Egress)');
      expect(await ApiService.endShift('Watch the blue Vios'), isNull);
      expect(seen['POST shifts.php']!['notes'], 'Watch the blue Vios');
    });

    test('uploadEvidence: null on success, the server\'s message on refusal', () async {
      expect(await ApiService.uploadEvidence({'kind': 'entry', 'plate': 'NDK 4821', 'gateLogId': 1, 'image': 'AAAA'}), isNull);
      final problem = await ApiService.uploadEvidence({'kind': 'bogus', 'plate': 'NDK 4821', 'image': 'AAAA'});
      expect(problem, contains('kind must be one of'));
    });

    test('issueViolation remembers the new violation id (so a photo can be attached)', () async {
      final error = await ApiService.issueViolation(plateNumber: 'NDK 4821', type: 'Other', notes: 'x');
      expect(error, isNull);
      expect(ApiService.lastViolationId, 42);
    });

    test('a recorded gate passage carries how the vehicle was looked up and exposes the server log id', () async {
      final ok = await ApiService.postGateLog(
        plateNumber: 'NDK 4821',
        driverName: 'Maria',
        lookupMethod: 'manual',
      );
      expect(ok, isTrue);
      expect(seen['POST logs.php']!['lookupMethod'], 'manual');
      expect(ApiService.lastGateLogId, 99);
    });
  });

  group('ShiftBanner', () {
    Future<void> serve(WidgetTester tester, {Map<String, dynamic>? mine, Map<String, dynamic>? handover, List<Map<String, dynamic>>? calls}) async {
      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async {
        final body = request.body.isNotEmpty ? jsonDecode(request.body) as Map<String, dynamic> : <String, dynamic>{};
        calls?.add({'method': request.method, ...body});
        if (request.method == 'GET') return json(200, {'status': 'success', 'data': {'onDuty': [], 'mine': mine, 'handover': handover}});
        if (body['action'] == 'start') {
          return json(201, {'status': 'success', 'data': {'shift': {'gate': body['gate'], 'startedAt': '2026-10-08 08:00:00'}, 'handover': handover}});
        }
        return json(200, {'status': 'success'});
      }));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ShiftBanner(assignedGate: 'Gate 1 (Main Ingress)')))));
      await tester.pumpAndSettle();
    }

    testWidgets('not on duty: offers Go on duty and shows the previous guard\'s handover note', (tester) async {
      await serve(tester, handover: {'guard': 'Guard A', 'gate': 'Gate 1', 'handoverNotes': 'Gate arm is jammed'});
      expect(find.text('You are not on duty yet'), findsOneWidget);
      expect(find.textContaining('Gate arm is jammed'), findsOneWidget);
      expect(find.byKey(const Key('shiftStart')), findsOneWidget);
      expect(ShiftBanner.onDuty.value, isFalse);
    });

    testWidgets('going on duty sends the chosen gate and flips the banner', (tester) async {
      final calls = <Map<String, dynamic>>[];
      await serve(tester, calls: calls);
      await tester.tap(find.byKey(const Key('shiftStart')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shiftStartConfirm')));
      await tester.pumpAndSettle();
      expect(calls.any((c) => c['action'] == 'start' && c['gate'] == 'Gate 1 (Main Ingress)'), isTrue);
      expect(find.textContaining('On duty'), findsOneWidget);
      expect(ShiftBanner.onDuty.value, isTrue);
    });

    testWidgets('ending the shift sends the handover note', (tester) async {
      final calls = <Map<String, dynamic>>[];
      await serve(tester, mine: {'gate': 'Gate 1 (Main Ingress)', 'startedAt': '2026-10-08 08:00:00'}, calls: calls);
      expect(find.byKey(const Key('shiftEnd')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shiftEnd')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('shiftHandoverField')), 'Lights out at the back lot');
      await tester.tap(find.byKey(const Key('shiftEndConfirm')));
      await tester.pumpAndSettle();
      expect(calls.any((c) => c['action'] == 'end' && c['notes'] == 'Lights out at the back lot'), isTrue);
      expect(find.text('You are not on duty yet'), findsOneWidget);
    });

    testWidgets('server unreachable: the banner stays hidden and nothing breaks', (tester) async {
      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async => throw http.ClientException('offline')));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ShiftBanner(assignedGate: 'Gate 1 (Main Ingress)'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shiftBanner')), findsNothing);
    });
  });
}
