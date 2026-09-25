import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/constants/app_constants.dart';
import 'package:systemforinteg/core/utils/date_time_utils.dart';
import 'package:systemforinteg/core/widgets/plate_badge.dart';
import 'package:systemforinteg/core/widgets/status_badge.dart';
import 'package:systemforinteg/data/mock_data.dart';
import 'package:systemforinteg/features/dashboard/screens/dashboard_screen.dart';
import 'package:systemforinteg/features/dashboard/widgets/kpi_metric_card.dart';
import 'package:systemforinteg/features/scanner/dialogs/block_reason_dialog.dart';
import 'package:systemforinteg/features/scanner/dialogs/manual_qr_dialog.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/widgets/authorized_drivers_card.dart';
import 'package:systemforinteg/features/scanner/widgets/scanned_person_card.dart';
import 'package:systemforinteg/features/scanner/widgets/test_qr_presets_bar.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/services/vehicle_lookup_service.dart';

void main() {
  group('VehicleLookupService Unit Tests', () {
    test('Matches exact QR pass code', () {
      final vehicle = VehicleLookupService.resolveVehicleFromQr(
        rawQrCode: 'NCST-QR-ABC1234',
        registeredVehicles: MockData.registeredVehicles,
      );
      expect(vehicle.plateNumber, 'ABC-1234');
      expect(vehicle.ownerName, 'Prof. Roberto D. Reyes');
    });

    test('Matches plate number without hyphen and case-insensitive', () {
      final vehicle = VehicleLookupService.resolveVehicleFromQr(
        rawQrCode: 'abc1234',
        registeredVehicles: MockData.registeredVehicles,
      );
      expect(vehicle.plateNumber, 'ABC-1234');
    });

    test('Generates visitor pass for unknown QR payload', () {
      final visitor = VehicleLookupService.resolveVehicleFromQr(
        rawQrCode: 'GUEST-XYZ-999',
        registeredVehicles: MockData.registeredVehicles,
      );
      expect(visitor.plateNumber, 'GUEST-XYZ-99');
      expect(visitor.ownerRole, contains('Guest Driver'));
    });
  });

  group('DateTimeUtils Unit Tests', () {
    test('Formats DateTime into 12-hour AM/PM string', () {
      final dtAm = DateTime(2026, 9, 16, 8, 5);
      expect(DateTimeUtils.formatTime(dtAm), '8:05 AM');

      final dtPm = DateTime(2026, 9, 16, 14, 30);
      expect(DateTimeUtils.formatTime(dtPm), '2:30 PM');

      final dtMidnight = DateTime(2026, 9, 16, 0, 15);
      expect(DateTimeUtils.formatTime(dtMidnight), '12:15 AM');
    });
  });

  group('Core & Feature Widgets Isolated Tests', () {
    testWidgets('PlateBadge renders plate number with monospace style', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlateBadge(plateNumber: 'XYZ-7890', isProminent: true),
          ),
        ),
      );
      expect(find.text('XYZ-7890'), findsOneWidget);
    });

    testWidgets('StatusBadge renders INSIDE and BLOCKED text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StatusBadge(status: GateStatus.inside),
                StatusBadge(status: GateStatus.blocked),
              ],
            ),
          ),
        ),
      );
      expect(find.text('INSIDE'), findsOneWidget);
      expect(find.text('BLOCKED'), findsOneWidget);
    });

    testWidgets('KpiMetricCard renders label and value correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KpiMetricCard(
              label: 'INSIDE CAMPUS',
              value: '14',
              color: Colors.green,
              icon: Icons.directions_car,
            ),
          ),
        ),
      );
      expect(find.text('INSIDE CAMPUS'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('ManualQrDialog submits entered text', (tester) async {
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ManualQrDialog.show(context, (val) => submitted = val);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Enter QR Pass / Plate Number'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'TEST-CODE-123');
      await tester.tap(find.text('Verify QR Pass'));
      await tester.pumpAndSettle();

      expect(submitted, 'TEST-CODE-123');
    });

    testWidgets('BlockReasonDialog selects reason and invokes callback', (tester) async {
      String? selectedReason;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  BlockReasonDialog.show(context, (reason) => selectedReason = reason);
                },
                child: const Text('Open Block Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Block Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Block Vehicle Entry'), findsOneWidget);
      final firstReason = AppConstants.defaultBlockReasons.first;
      await tester.tap(find.text(firstReason));
      await tester.pumpAndSettle();

      expect(selectedReason, firstReason);
    });
  });

  group('Responsive Multi-Device Layout Tests', () {
    Future<void> testDeviceViewport({
      required WidgetTester tester,
      required Size size,
      required Widget widget,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: widget,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('DashboardScreen renders without overflow on 320x568 small phone', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(320, 568),
        widget: const Scaffold(body: DashboardScreen()),
      );
      expect(find.text('INSIDE CAMPUS'), findsOneWidget);
      expect(find.text('TOTAL ENTRIES'), findsOneWidget);
      expect(find.text('BLOCKED ATTEMPTS'), findsOneWidget);
      expect(find.text('SCAN QR PASS'), findsOneWidget);
    });

    testWidgets('DashboardScreen renders without overflow on 390x844 standard phone', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(390, 844),
        widget: const Scaffold(body: DashboardScreen()),
      );
      expect(find.text('INSIDE CAMPUS'), findsOneWidget);
      expect(find.text('AUDIT LOG'), findsOneWidget);
    });

    testWidgets('DashboardScreen renders without overflow on 640x360 phone landscape', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(640, 360),
        widget: const Scaffold(body: DashboardScreen()),
      );
      expect(find.text('Gate Security Terminal'), findsOneWidget);
    });

    testWidgets('DashboardScreen renders without overflow on 768x1024 tablet portrait', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(768, 1024),
        widget: const Scaffold(body: DashboardScreen()),
      );
      expect(find.text('Gate Security Terminal'), findsOneWidget);
    });

    testWidgets('DashboardScreen renders without overflow on 1920x1080 large desktop monitor', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(1920, 1080),
        widget: const Scaffold(body: DashboardScreen()),
      );
      expect(find.text('Gate Security Terminal'), findsOneWidget);
      expect(find.text('AUDIT LOG'), findsOneWidget);
    });

    testWidgets('Scanned Person and Verification card render without overflow on 320px phone', (tester) async {
      const testVehicle = VehicleRecord(
        plateNumber: 'GUEST-VISITOR-99',
        vehicleType: 'Van / Shuttle',
        makeModelColor: 'Dark Gray Metallic Nissan Urvan NV350 Premium Shuttle High Roof',
        ownerName: 'Dr. Maria Cristina Evangelista Santos-Villanueva',
        ownerRole: 'Visiting Chief Medical Officer & Honorary Chancellor of Academic Affairs',
        ownerIdNumber: 'VISITOR-EXT-99881122',
        qrPassCode: 'NCST-QR-GUEST99',
        authorizedDrivers: [],
      );

      await testDeviceViewport(
        tester: tester,
        size: const Size(320, 568),
        widget: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: const [
                ScannedPersonCard(
                  vehicle: testVehicle,
                  driverName: 'Dr. Maria Cristina Evangelista Santos-Villanueva',
                  relationship: 'Registered Owner',
                  photoUrl: '',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('SCANNED QR PASS VERIFIED'), findsOneWidget);
      expect(find.text('REGISTERED OWNER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AuthorizedDriversCard renders without overflow on 320px phone', (tester) async {
      final sampleVehicle = MockData.registeredVehicles.firstWhere((v) => v.authorizedDrivers.isNotEmpty);
      await testDeviceViewport(
        tester: tester,
        size: const Size(320, 568),
        widget: Scaffold(
          body: SingleChildScrollView(
            child: AuthorizedDriversCard(
              vehicle: sampleVehicle,
              selectedDriverName: sampleVehicle.ownerName,
              onSelectOwner: () {},
              onSelectDriver: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('REGISTERED VEHICLE OWNER'), findsOneWidget);
      expect(find.text('AUTHORIZED DRIVERS (IF NOT OWNER)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TestQrPresetsBar renders without overflow on 320px phone', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(320, 568),
        widget: Scaffold(
          body: TestQrPresetsBar(
            presets: MockData.registeredVehicles,
            onPresetSelected: (_) {},
            onGuestPassSelected: () {},
          ),
        ),
      );

      expect(find.text('TEST QR PRESETS (AUTO-SCANS ON VIEW)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('QrScannerScreen renders without overflow on 320x568 small phone', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(320, 568),
        widget: Scaffold(body: QrScannerScreen(onDecision: (_) {})),
      );

      expect(find.text('CAMERA AUTO-SCAN ACTIVE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Open manual input to simulate pass verification without presets
      await tester.tap(find.text('Enter QR Manually').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '{"ownerFullName":"Prof. Roberto D. Reyes","plateNumber":"ABC-1234","authorizedDrivers":[{"fullName":"Maria Elena Reyes","relationship":"Spouse","licenseNo":"N01-18-094821"}]}',
      );
      await tester.tap(find.text('Verify QR Pass'));
      await tester.pumpAndSettle();

      expect(find.text('SCANNED QR PASS VERIFIED'), findsOneWidget);
      expect(find.text('ABC-1234'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('QrScannerScreen renders without overflow on 1024x768 desktop landscape split view', (tester) async {
      await testDeviceViewport(
        tester: tester,
        size: const Size(1024, 768),
        widget: Scaffold(body: QrScannerScreen(onDecision: (_) {})),
      );

      expect(find.text('CAMERA AUTO-SCAN ACTIVE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Open manual input to trigger verification on desktop
      await tester.tap(find.text('Enter QR Manually').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '{"ownerFullName":"Prof. Roberto D. Reyes","plateNumber":"ABC-1234","authorizedDrivers":[{"fullName":"Maria Elena Reyes","relationship":"Spouse","licenseNo":"N01-18-094821"}]}',
      );
      await tester.tap(find.text('Verify QR Pass'));
      await tester.pumpAndSettle();

      expect(find.text('SCANNED QR PASS VERIFIED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ManualQrDialog and BlockReasonDialog render without overflow on 640x360 landscape', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => BlockReasonDialog.show(context, (_) {}),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Block Vehicle Entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scanned user profile for Monares, Kriz renders with student role and no LIVE GATE SNAPSHOT badge', (tester) async {
      final krizVehicle = MockData.registeredVehicles.firstWhere((v) => v.ownerName == 'Monares, Kriz');

      await testDeviceViewport(
        tester: tester,
        size: const Size(360, 640),
        widget: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ScannedPersonCard(
                  vehicle: krizVehicle,
                  driverName: krizVehicle.ownerName,
                  relationship: 'Registered Owner',
                  photoUrl: krizVehicle.ownerPhotoUrl ?? '',
                ),
                AuthorizedDriversCard(
                  vehicle: krizVehicle,
                  selectedDriverName: krizVehicle.ownerName,
                  onSelectOwner: () {},
                  onSelectDriver: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      // Verify Name & Student Role
      expect(find.text('Monares, Kriz'), findsWidgets);
      expect(find.textContaining('Student'), findsWidgets);
      expect(find.textContaining('NCST-2024-05182'), findsWidgets);
      expect(find.text('NKM-2024'), findsWidgets);

      // Verify DriverPhotoView has no 'LIVE GATE SNAPSHOT'
      expect(find.text('LIVE GATE SNAPSHOT'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
