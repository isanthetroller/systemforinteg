// Regression for RT003/RT006: an open pass must follow repository updates.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/visitor/screens/visitor_pass_confirmation_screen.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';
import 'package:systemforinteg/repositories/visitor_repository.dart';
import 'package:systemforinteg/services/api_service.dart';

VisitorPass fixture({
  String name = 'Fixture visitor',
  VisitorPassStatus status = VisitorPassStatus.active,
  DateTime? expiry,
}) => VisitorPass(
  passId: 'LIVE-PASS-91',
  dbId: 91,
  visitorName: name,
  plateNumber: 'LIVE91',
  entryTime: DateTime.now(),
  expiryTime: expiry ?? DateTime.now().add(const Duration(hours: 8)),
  registeredByGuard: 'Fixture guard',
  gatePoint: 'Checkpoint 1',
  status: status,
);

void main() {
  setUp(() {
    VisitorRepository().passesNotifier.value = [];
  });
  tearDown(() {
    VisitorRepository().passesNotifier.value = [];
  });
  testWidgets('open visitor confirmation follows a repository update', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = VisitorRepository();
    final previous = repository.passesNotifier.value;
    addTearDown(() {
      repository.passesNotifier.value = previous;
    });
    final original = VisitorPass(
      passId: 'BASELINE-PASS-1',
      dbId: 91,
      visitorName: 'Original fixture visitor',
      plateNumber: 'BASELINE91',
      entryTime: DateTime.now(),
      expiryTime: DateTime.now().add(const Duration(hours: 8)),
      registeredByGuard: 'Fixture guard',
      gatePoint: 'Checkpoint 1',
    );
    final changed = VisitorPass(
      passId: original.passId,
      dbId: original.dbId,
      visitorName: 'Updated fixture visitor',
      plateNumber: original.plateNumber,
      entryTime: original.entryTime,
      expiryTime: original.expiryTime,
      registeredByGuard: original.registeredByGuard,
      gatePoint: original.gatePoint,
      status: VisitorPassStatus.blocked,
    );
    repository.passesNotifier.value = [original];
    await tester.pumpWidget(
      MaterialApp(
        home: VisitorPassConfirmationScreen(pass: original, onFinish: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Original fixture visitor'), findsOneWidget);
    // The authoritative repository publication happens, but this already-open
    // screen must also follow it without a parent route rebuild.
    repository.passesNotifier.value = [changed];
    await tester.pumpAndSettle();
    expect(find.text('Updated fixture visitor'), findsOneWidget);
    expect(find.text('Original fixture visitor'), findsNothing);
    expect(find.text('This pass is blocked.'), findsOneWidget);
    expect(find.byKey(const Key('realQrCode')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('open fullscreen QR stops displaying a blocked pass', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = fixture();
    VisitorRepository().passesNotifier.value = [original];
    await tester.pumpWidget(
      MaterialApp(
        home: VisitorPassConfirmationScreen(pass: original, onFinish: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fullscreen QR for Driver'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('realQrCode')), findsNWidgets(2));
    VisitorRepository().passesNotifier.value = [
      fixture(status: VisitorPassStatus.blocked),
    ];
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('realQrCode')), findsNothing);
    expect(find.text('This pass is blocked.'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets('removed server pass shows unavailable without a QR', (
    tester,
  ) async {
    final original = fixture();
    VisitorRepository().passesNotifier.value = [original];
    await tester.pumpWidget(
      MaterialApp(
        home: VisitorPassConfirmationScreen(pass: original, onFinish: () {}),
      ),
    );
    await tester.pumpAndSettle();
    VisitorRepository().passesNotifier.value = [];
    await tester.pumpAndSettle();
    expect(find.text('This pass is no longer available.'), findsOneWidget);
    expect(find.byKey(const Key('realQrCode')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('expired and used passes cannot display a QR', (tester) async {
    for (final pass in [
      fixture(expiry: DateTime.now().subtract(const Duration(minutes: 1))),
      fixture(status: VisitorPassStatus.used),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: VisitorPassConfirmationScreen(pass: pass, onFinish: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('realQrCode')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'live minute revision updates eligibility and disposal removes listeners',
    (tester) async {
      final original = fixture();
      VisitorRepository().passesNotifier.value = [original];
      await tester.pumpWidget(
        MaterialApp(
          home: VisitorPassConfirmationScreen(pass: original, onFinish: () {}),
        ),
      );
      await tester.pumpAndSettle();
      ApiService.acknowledgeUpdates({'clock': 'next-minute'});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('realQrCode')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      ApiService.acknowledgeUpdates({'clock': 'later-minute'});
      VisitorRepository().passesNotifier.value = [
        fixture(status: VisitorPassStatus.blocked),
      ];
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('pass card fits phone and tablet widths with larger text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0, 440.0, 900.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        final pass = fixture();
        VisitorRepository().passesNotifier.value = [pass];
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: VisitorPassConfirmationScreen(pass: pass, onFinish: () {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width textScale=$scale',
        );
      }
    }
  });
}
