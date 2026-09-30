import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/scanner/widgets/scanned_visitor_card.dart';
import 'package:systemforinteg/models/scanned_visitor_pass.dart';

/// The shape `verify.php` returns (`data`) for a visitor day pass, taken from the local server.
Map<String, dynamic> verifyResponse({
  String result = 'VALID',
  bool accepted = true,
  String reason = '',
  List<String> warnings = const [],
  bool currentlyInside = false,
  List<Map<String, dynamic>>? items,
}) {
  return {
    'result': result,
    'accepted': accepted,
    'severity': accepted ? 'ok' : 'danger',
    'message': 'Pass verified.',
    'reason': reason,
    'warnings': warnings,
    'gateType': 'Ingress',
    'passType': 'visitor_temp',
    'autoLogged': false,
    'incident': null,
    'currentlyInside': currentlyInside,
    'vehicle': null,
    'visitor': {
      'id': 2,
      'passCode': 'VP-20260930-DEMO',
      'visitorName': 'Liza Soberano',
      'contactNumber': '0917 000 1111',
      'plateNumber': 'VIS2026',
      'vehicleModel': 'White Nissan Almera',
      'purposeOfVisit': 'Enrollment inquiry',
      'personToVisit': "Registrar's Office",
      'validDate': '2026-09-30',
      'entryTime': null,
      'exitTime': null,
      'status': 'Active',
      'items': items ??
          [
            {'name': 'Document box', 'quantity': 1, 'description': 'transcripts'},
            {'name': 'Monobloc chairs', 'quantity': 40, 'description': ''},
          ],
    },
  };
}

void main() {
  group('ScannedVisitorPass.fromVerify', () {
    test('reads the pass, the server verdict and the declared items', () {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(warnings: ['Manual lookup: verify the driver']))!;

      expect(pass.id, 2);
      expect(pass.passCode, 'VP-20260930-DEMO');
      expect(pass.visitorName, 'Liza Soberano');
      expect(pass.plateNumber, 'VIS2026');
      expect(pass.vehicleModel, 'White Nissan Almera');
      expect(pass.personToVisit, "Registrar's Office");
      expect(pass.validDate, '2026-09-30');
      expect(pass.result, 'VALID');
      expect(pass.canAdmit, isTrue);
      expect(pass.warnings, ['Manual lookup: verify the driver']);
      expect(pass.hasItems, isTrue);
      expect(pass.items.map((i) => i.label).toList(), ['1x Document box (transcripts)', '40x Monobloc chairs']);
    });

    test('a pass the server refused cannot be admitted, and says why', () {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(
        result: 'NOT_YET_VALID',
        accepted: false,
        reason: 'This day pass becomes active on 2026-10-05.',
      ))!;

      expect(pass.canAdmit, isFalse);
      expect(pass.verdictTitle, 'PASS NOT YET VALID');
      expect(pass.reason, contains('2026-10-05'));
    });

    test('a pass without declared items needs no item check', () {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(items: []))!;
      expect(pass.hasItems, isFalse);
    });

    test('a response with no visitor (a registered vehicle, or nothing found) gives null', () {
      final noVisitor = verifyResponse()..['visitor'] = null;
      expect(ScannedVisitorPass.fromVerify(noVisitor), isNull);
      expect(ScannedVisitorPass.fromVerify(null), isNull);
      expect(ScannedVisitorPass.fromVerify({'result': 'NOT_FOUND', 'accepted': false}), isNull);
    });

    test('a visitor object without a usable id is ignored rather than trusted', () {
      final broken = verifyResponse();
      (broken['visitor'] as Map<String, dynamic>)['id'] = 0;
      expect(ScannedVisitorPass.fromVerify(broken), isNull);
    });
  });

  group('ScannedVisitorCard', () {
    Future<void> pump(WidgetTester tester, ScannedVisitorPass pass, Set<int> checked, List<int> taps) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScannedVisitorCard(pass: pass, checkedItems: checked, onToggleItem: taps.add),
          ),
        ),
      ));
    }

    testWidgets('shows the visitor, the verdict and every declared item; ticking reports the item index', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse())!;
      final taps = <int>[];
      await pump(tester, pass, {}, taps);

      expect(find.text('VISITOR PASS VALID'), findsOneWidget);
      expect(find.text('Liza Soberano'), findsOneWidget);
      expect(find.text('VP-20260930-DEMO'), findsOneWidget);
      expect(find.text('DECLARED ITEMS (0/2 checked)'), findsOneWidget);
      expect(find.text('40x Monobloc chairs'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('visitor-item-1')));
      expect(taps, [1]);
    });

    testWidgets('reflects which items are ticked', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse())!;
      await pump(tester, pass, {0, 1}, []);

      expect(find.text('DECLARED ITEMS (2/2 checked)'), findsOneWidget);
    });

    testWidgets('a refused pass shows the reason and its items cannot be ticked', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(
        result: 'EXPIRED_TEMP',
        accepted: false,
        reason: 'EXPIRED TEMPORARY PASS - valid only on 2026-09-01.',
      ))!;
      final taps = <int>[];
      await pump(tester, pass, {}, taps);

      expect(find.text('ENTRY NOT ALLOWED'), findsOneWidget);
      expect(find.textContaining('valid only on 2026-09-01'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('visitor-item-0')));
      expect(taps, isEmpty);
    });

    testWidgets('at the exit gate a visitor who is inside gets no "already inside" warning and checks items OUT', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(currentlyInside: true))!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScannedVisitorCard(pass: pass, checkedItems: const {}, onToggleItem: (_) {}, isExit: true),
          ),
        ),
      ));

      expect(find.text('ALREADY RECORDED INSIDE'), findsNothing);
      expect(find.text('NO ENTRY RECORDED'), findsNothing);
      expect(find.textContaining('before recording the exit'), findsOneWidget);
    });

    testWidgets('at the exit gate a visitor with no recorded entry is flagged', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse())!; // currentlyInside: false
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScannedVisitorCard(pass: pass, checkedItems: const {}, onToggleItem: (_) {}, isExit: true),
          ),
        ),
      ));

      expect(find.text('NO ENTRY RECORDED'), findsOneWidget);
    });

    testWidgets('a refused pass at the exit gate says the EXIT is not allowed', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(
        result: 'REVOKED',
        accepted: false,
        reason: 'This single-day pass has already been used (entry and exit recorded).',
      ))!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScannedVisitorCard(pass: pass, checkedItems: const {}, onToggleItem: (_) {}, isExit: true),
          ),
        ),
      ));

      expect(find.text('EXIT NOT ALLOWED'), findsOneWidget);
      expect(find.text('ENTRY NOT ALLOWED'), findsNothing);
    });

    testWidgets('warns when the visitor is already recorded inside', (tester) async {
      final pass = ScannedVisitorPass.fromVerify(verifyResponse(currentlyInside: true))!;
      await pump(tester, pass, {}, []);

      expect(find.text('ALREADY RECORDED INSIDE'), findsOneWidget);
    });
  });
}
