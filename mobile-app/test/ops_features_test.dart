import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/core/utils/plate_reader.dart';
import 'package:systemforinteg/features/cases/case_format.dart';
import 'package:systemforinteg/features/cases/screens/case_detail_screen.dart';
import 'package:systemforinteg/features/cases/screens/cases_screen.dart';
import 'package:systemforinteg/features/guard/screens/guard_shell_screen.dart';
import 'package:systemforinteg/features/guard/widgets/shift_banner.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_rejection_view.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/scan_feedback.dart';
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
        if (path.endsWith('notices_send.php')) return json(200, {'status': 'success', 'data': {'sent': 1, 'waiting': 0}});
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

    test('after an entry or exit is recorded the phone asks the server to send the owner e-mail', () async {
      await ApiService.postGateLog(plateNumber: 'NDK 4821', driverName: 'Maria', action: 'Entry Recorded');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen.containsKey('POST notices_send.php'), isTrue);

      seen.clear();
      await ApiService.postGateLog(plateNumber: 'NDK 4821', driverName: 'Maria', action: 'Exit Approved', status: 'Outside');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen.containsKey('POST notices_send.php'), isTrue);
    });

    test('a refused passage does not ask for an e-mail', () async {
      seen.clear();
      await ApiService.postGateLog(plateNumber: 'NDK 4821', driverName: 'Maria', action: 'Entry Denied', status: 'Blocked');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen.containsKey('POST notices_send.php'), isFalse);
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

  group('ScanFeedback', () {
    tearDown(() {
      ScanFeedback.testSink = null;
      LocalCacheService.clearMemoryCache();
    });

    test('each outcome has its own tone and vibration, and the refused one is the longest', () {
      final cleared = ScanFeedback.wavFor(ScanOutcome.cleared);
      final warning = ScanFeedback.wavFor(ScanOutcome.warning);
      final refused = ScanFeedback.wavFor(ScanOutcome.refused);
      expect(cleared.length, isNot(warning.length));
      expect(refused.length, greaterThan(warning.length));
      expect(ScanFeedback.vibrationFor(ScanOutcome.cleared).length, 2);
      expect(ScanFeedback.vibrationFor(ScanOutcome.warning).length, 4);
      expect(ScanFeedback.vibrationFor(ScanOutcome.refused).reduce((a, b) => a + b), greaterThan(1000));
    });

    test('the generated sound is a valid 16-bit mono WAV file', () {
      final wav = ScanFeedback.wavFor(ScanOutcome.cleared);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      final data = ByteData.sublistView(wav);
      expect(data.getUint32(4, Endian.little), wav.length - 8);
      expect(data.getUint32(40, Endian.little), wav.length - 44);
      expect(data.getUint16(22, Endian.little), 1); // mono
      expect(data.getUint16(34, Endian.little), 16); // 16 bit
    });

    test('on by default; turning it off silences every cue and the choice is remembered', () async {
      final heard = <ScanOutcome>[];
      ScanFeedback.testSink = (o) async => heard.add(o);
      expect(ScanFeedback.enabled, isTrue);
      await ScanFeedback.play(ScanOutcome.refused);
      expect(heard, [ScanOutcome.refused]);

      await ScanFeedback.setEnabled(false);
      expect(ScanFeedback.enabled, isFalse);
      await ScanFeedback.play(ScanOutcome.cleared);
      expect(heard, [ScanOutcome.refused]); // nothing new
      await ScanFeedback.play(ScanOutcome.cleared, force: true); // the "test it" preview still plays
      expect(heard.last, ScanOutcome.cleared);

      await ScanFeedback.setEnabled(true);
      expect(ScanFeedback.enabled, isTrue);
    });

    testWidgets('ScanFeedbackGate plays once per result, not on every rebuild', (tester) async {
      final heard = <ScanOutcome>[];
      ScanFeedback.testSink = (o) async => heard.add(o);
      final gate = ScanFeedbackGate();
      Future<void> frame(ScanOutcome? now) async {
        gate.update(now);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      await frame(null);
      await frame(ScanOutcome.cleared);
      await frame(ScanOutcome.cleared);
      await frame(ScanOutcome.cleared);
      expect(heard, [ScanOutcome.cleared]);
      await frame(null); // back to scanning
      await frame(ScanOutcome.cleared); // the next vehicle, same kind of result
      await frame(ScanOutcome.refused);
      expect(heard, [ScanOutcome.cleared, ScanOutcome.cleared, ScanOutcome.refused]);
    });
  });

  group('Cases on the phone', () {
    final calls = <Map<String, dynamic>>[];
    late Map<String, dynamic> theCase;
    List<Map<String, dynamic>> listed = [];

    Map<String, dynamic> row(String key, String plate, String status, {int attempts = 0, bool police = false}) => {
          'key': key,
          'plateNumber': plate,
          'title': 'Parking in Fire Lane',
          'status': status,
          'step': status == 'Open' ? 'Reported' : status,
          'ownerName': 'Prof. John Smith',
          'ownerPhone': '0917 555 0100',
          'openedAt': '2026-10-08 08:00:00',
          'contactAttempts': attempts,
          'policeReferred': police,
        };

    setUp(() {
      calls.clear();
      theCase = {
        ...row('V12', 'ABC-1111', 'Open'),
        'timeline': [
          {'at': '2026-10-08 08:00:00', 'type': 'reported', 'label': 'Reported', 'detail': 'Parking in Fire Lane', 'by': 'Officer Entrance'},
        ],
      };
      listed = [row('V12', 'ABC-1111', 'Open'), row('I3', 'XYZ-9999', 'Awaiting clearance', attempts: 2, police: true)];
      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async {
        final body = request.body.isNotEmpty ? jsonDecode(request.body) as Map<String, dynamic> : <String, dynamic>{};
        if (!request.url.path.endsWith('cases.php')) return json(404, {'status': 'error', 'message': 'not found'});
        if (request.method == 'GET') {
          if (request.url.queryParameters['key'] != null) return json(200, {'status': 'success', 'data': theCase});
          calls.add({'GET': request.url.queryParameters['status']});
          return json(200, {'status': 'success', 'data': {'cases': listed, 'summary': {}, 'total': listed.length}});
        }
        calls.add(body);
        if (body['action'] == 'contact' && body['result'] == 'No answer') {
          theCase = {
            ...theCase,
            'contactAttempts': 1,
            'step': 'Contact attempted',
            'timeline': [
              ...(theCase['timeline'] as List),
              {'at': '2026-10-08 09:00:00', 'type': 'contact', 'label': 'Contact attempt: Phone call, No answer', 'detail': body['note'], 'by': 'Officer Entrance'},
            ],
          };
          return json(200, {'status': 'success', 'message': 'Contact attempt recorded.', 'data': {'case': theCase}});
        }
        if (body['action'] == 'awaiting') {
          theCase = {...theCase, 'status': 'Awaiting clearance', 'step': 'Awaiting clearance'};
          return json(200, {'status': 'success', 'message': 'Marked as waiting for the owner to come in for clearance.', 'data': {'case': theCase}});
        }
        if (body['action'] == 'close') return json(403, {'status': 'error', 'message': 'Only an administrator can do this.'});
        return json(400, {'status': 'error', 'message': 'Write the note.'});
      }));
    });

    tearDown(ApiService.resetClient);

    test('caseAction posts the key, the action and the contact fields; a refusal comes back as a message', () async {
      final ok = await ApiService.caseAction('V12', 'contact', method: 'Phone call', result: 'No answer', note: 'Rang 3 times');
      expect(ok['error'], isNull);
      expect(calls.last, {'key': 'V12', 'action': 'contact', 'method': 'Phone call', 'result': 'No answer', 'note': 'Rang 3 times'});
      final denied = await ApiService.caseAction('V12', 'close');
      expect(denied['error'], 'Only an administrator can do this.');
      expect(calls.last.containsKey('method'), isFalse);
    });

    test('server unreachable: lists give null and actions say nothing was saved', () async {
      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async => throw http.ClientException('offline')));
      expect(await ApiService.fetchCases(), isNull);
      expect(await ApiService.fetchCase('V12'), isNull);
      expect((await ApiService.caseAction('V12', 'note', note: 'x'))['error'], contains('Nothing was saved'));
    });

    testWidgets('the list shows open cases with counts and who has been tried', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CasesScreen())));
      await tester.pumpAndSettle();
      expect(calls.first['GET'], 'active');
      expect(find.text('ABC-1111'), findsOneWidget);
      expect(find.text('XYZ-9999'), findsOneWidget);
      expect(find.textContaining('not contacted yet'), findsOneWidget);
      expect(find.textContaining('2 contact attempts'), findsOneWidget);
      expect(find.text('Coming in'), findsOneWidget);
      expect(find.text('On hold'), findsWidgets);
    });

    testWidgets('no open cases says so; an unreachable server says that instead', (tester) async {
      listed = [];
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CasesScreen())));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('casesEmpty')), findsOneWidget);

      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async => throw http.ClientException('offline')));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CasesScreen())));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('casesUnreachable')), findsOneWidget);
    });

    testWidgets('open a case, log a contact attempt: the form needs both answers, then the timeline gains the attempt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CasesScreen())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('caseTile:V12')));
      await tester.pumpAndSettle();

      expect(find.text('Case V12'), findsOneWidget);
      expect(find.text('Prof. John Smith'), findsOneWidget);
      expect(find.text('0917 555 0100'), findsOneWidget);
      expect(find.byKey(const Key('callOwner')), findsOneWidget);
      expect(find.textContaining('administrator'), findsWidgets); // closing / police are not the guard's
      expect(find.text('Close case'), findsNothing);

      await tester.tap(find.byKey(const Key('logContact')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('contactSave'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('contactMethod:Phone call')));
      await tester.tap(find.byKey(const Key('contactResult:No answer')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('contactNoteField')), 'Rang 3 times');
      await tester.tap(find.byKey(const Key('contactSave')));
      await tester.pumpAndSettle();

      expect(calls.any((c) => c['action'] == 'contact' && c['method'] == 'Phone call' && c['result'] == 'No answer' && c['note'] == 'Rang 3 times'), isTrue);
      expect(find.text('Contact attempt recorded.'), findsOneWidget);
      expect(find.text('Contact attempt: Phone call, No answer'), findsOneWidget);
    });

    testWidgets('"Owner is coming in" asks first, then moves the case to Awaiting clearance and hides itself', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: CaseDetailScreen(caseKey: 'V12', preview: row('V12', 'ABC-1111', 'Open'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('markAwaiting')));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c['action'] == 'awaiting'), isEmpty); // not sent until confirmed
      await tester.tap(find.byKey(const Key('awaitingConfirm')));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c['action'] == 'awaiting').length, 1);
      expect(find.byKey(const Key('markAwaiting')), findsNothing);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('caseStatusChip')), matching: find.byType(Text))).data, 'Awaiting clearance');
    });

    testWidgets('a note is required; a closed case offers no actions; no phone on file says so', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: CaseDetailScreen(caseKey: 'V12', preview: row('V12', 'ABC-1111', 'Open'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addCaseNote')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('noteSave')));
      await tester.pumpAndSettle();
      expect(find.text('Write the note first.'), findsOneWidget);
      expect(calls.where((c) => c['action'] == 'note'), isEmpty);

      theCase = {...theCase, 'status': 'Closed', 'step': 'Closed: Clearance signed', 'ownerPhone': null};
      await tester.pumpWidget(MaterialApp(home: CaseDetailScreen(key: UniqueKey(), caseKey: 'V12')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('logContact')), findsNothing);
      expect(find.byKey(const Key('callOwner')), findsNothing);
      expect(find.byKey(const Key('noPhoneNote')), findsOneWidget);
    });

    testWidgets('a vehicle held by a case offers VIEW CASE on the rejection screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final details = ScanRejectionDetails(
        type: ScanRejectionType.blocked,
        title: 'ACCESS DENIED',
        message: 'On hold',
        notices: ScanNotice.fromVerify({
          'case': {'key': 'V12', 'title': 'Parking in Fire Lane', 'step': 'Reported', 'policeReferred': false},
        }),
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScanRejectionView(details: details, onScanAnother: () {}))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('viewCaseButton')));
      await tester.tap(find.byKey(const Key('viewCaseButton')));
      await tester.pumpAndSettle();
      expect(find.text('Case V12'), findsOneWidget);

      // a rejection with no case has no such button
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScanRejectionView(
            details: ScanRejectionDetails(type: ScanRejectionType.notFound, title: 'NOT FOUND', message: 'x'),
            onScanAnother: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('viewCaseButton')), findsNothing);
    });

    test('CaseFormat: friendly dates and ages', () {
      expect(CaseFormat.when('2026-10-08 14:30:00'), 'Oct 8, 2:30 PM');
      expect(CaseFormat.when('not a date'), '');
      expect(CaseFormat.age('2026-10-05 08:00:00', now: DateTime(2026, 10, 8, 9)), 'Open 3 days');
      expect(CaseFormat.age('2026-10-08 08:00:00', now: DateTime(2026, 10, 8, 9, 30)), 'Open 1 h');
      expect(CaseFormat.age('2026-10-08 08:00:00', now: DateTime(2026, 10, 8, 8, 20)), 'Open 20 min');
    });
  });

  group('Guard shell: Cases tab and scan sound switch', () {
    GuardUser guard(GuardRole role) => GuardUser(
          id: 'g',
          username: 'g',
          fullName: 'Officer Test',
          badgeNumber: 'B-1',
          role: role,
          assignedGate: role == GuardRole.entrance ? 'Gate 1 (Main Ingress)' : 'Gate 2 (Main Egress)',
          loginTime: DateTime.now(),
        );

    setUp(() {
      LocalCacheService.clearMemoryCache();
      ApiService.resetClient();
      ApiService.setClientForTesting(MockClient((request) async {
        if (request.url.path.endsWith('cases.php')) {
          return json(200, {'status': 'success', 'data': {'cases': [], 'summary': {}, 'total': 0}});
        }
        if (request.url.path.endsWith('shifts.php')) return json(200, {'status': 'success', 'data': {'onDuty': [], 'mine': null, 'handover': null}});
        return json(200, {'status': 'success', 'data': []});
      }));
    });

    tearDown(() {
      ApiService.resetClient();
      ScanFeedback.testSink = null;
    });

    for (final role in [GuardRole.entrance, GuardRole.exit]) {
      testWidgets('${role.name} guard: a Cases tab opens the list of open cases', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: GuardShellScreen(user: guard(role))));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Cases'), findsOneWidget);
        await tester.tap(find.text('Cases'));
        await tester.pumpAndSettle();
        expect(find.byType(CasesScreen), findsOneWidget);
        expect(find.byKey(const Key('casesEmpty')), findsOneWidget);
      });
    }

    testWidgets('the menu switch turns scan sound and vibration off and on, and previews the sound when turning on', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final heard = <ScanOutcome>[];
      ScanFeedback.testSink = (o) async => heard.add(o);
      await tester.pumpWidget(MaterialApp(home: GuardShellScreen(user: guard(GuardRole.entrance))));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('Guard account'));
      await tester.pumpAndSettle();
      expect(find.text('Scan sound & vibration: ON'), findsOneWidget);
      await tester.tap(find.byKey(const Key('toggleScanSound')));
      await tester.pumpAndSettle();
      expect(ScanFeedback.enabled, isFalse);
      expect(heard, isEmpty);

      await tester.tap(find.byTooltip('Guard account'));
      await tester.pumpAndSettle();
      expect(find.text('Scan sound & vibration: OFF'), findsOneWidget);
      await tester.tap(find.byKey(const Key('toggleScanSound')));
      await tester.pumpAndSettle();
      expect(ScanFeedback.enabled, isTrue);
      expect(heard, [ScanOutcome.cleared]);
    });
  });
}
