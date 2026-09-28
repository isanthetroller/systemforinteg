import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/repositories/gate_repository.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/vehicle_lookup_service.dart';

void main() {
  // The "Old QR Code" printed on the physical windshield sticker months ago
  const oldQrCode = '{"plateNumber":"ABC-9988","ownerFullName":"Old Owner Juan","makeModelColor":"Old Red 1998 Sedan","ownerStudentId":"FAC-OLD-11","stickerYear":"2026","authorizedDrivers":[{"fullName":"Old Driver Pedro","relationship":"Brother","licenseNo":"L-OLD-999"}]}';

  // The latest updated record currently in the MySQL database (after admin edited it in Web Admin)
  final updatedDbRecord = {
    'id': 105,
    'plate_number': 'ABC-9988',
    'vehicle_type': 'SUV',
    'make_model_color': '2025 Black Toyota Fortuner',
    'owner_name': 'Engr. Juan Dela Cruz Updated',
    'owner_role': 'Faculty - Engineering',
    'owner_id_number': 'NCST-FAC-2026',
    'sticker_year': '2026',
    'owner_photo_url': 'http://server.test/photos/juan_updated.jpg',
    'vehicle_photo_url': 'uploads/vehicles/fortuner.jpg',
    'qr_pass_code': 'NCST-QR-ABC9988',
    'status': 'Active',
    'authorized_drivers': [
      {
        'id': 'drv-1',
        'full_name': 'Engr. Juan Dela Cruz Updated',
        'relationship': 'Self (Owner)',
        'license_no': 'N01-20-999888',
        'photo_url': 'http://server.test/photos/juan_updated.jpg',
      },
      {
        'id': 'drv-2',
        'full_name': 'Engr. Maria Santos',
        'relationship': 'Associate Colleague',
        'license_no': 'N02-24-777666',
        'photo_url': 'http://server.test/photos/maria.jpg',
      }
    ]
  };

  late http.Client mockClient;

  setUp(() {
    mockClient = MockClient((request) async {
      final path = request.url.path;
      final queryParams = request.url.queryParameters;

      if (path.contains('vehicles.php')) {
        final plate = queryParams['plate'];
        final qr = queryParams['qr'];

        if (plate == 'ABC-9988' || (qr != null && qr.contains('ABC-9988'))) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': updatedDbRecord,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'status': 'error', 'message': 'Not found'}), 404);
      }

      if (path.contains('logs.php')) {
        return http.Response(jsonEncode({'status': 'success', 'message': 'Logged'}), 200);
      }

      return http.Response(jsonEncode({'status': 'ok'}), 200);
    });

    ApiService.setClientForTesting(mockClient);
  });

  tearDown(() {
    ApiService.resetClient();
  });

  group('Dynamic Database Fetch on Old QR Code Scan', () {
    test('VehicleLookupService prioritizes local database record over outdated QR data while preserving sticker year', () {
      final dbVehicle = VehicleRecord.fromQrJson(updatedDbRecord, isSyncedWithDb: true);

      final resolved = VehicleLookupService.resolveVehicleFromQr(
        rawQrCode: oldQrCode,
        registeredVehicles: [dbVehicle],
      );

      // Must show NEW database values, NOT old QR values
      expect(resolved.ownerName, equals('Engr. Juan Dela Cruz Updated'));
      expect(resolved.makeModelColor, equals('2025 Black Toyota Fortuner'));
      expect(resolved.ownerRole, equals('Faculty - Engineering'));
      expect(resolved.authorizedDrivers.length, equals(2));
      expect(resolved.authorizedDrivers[1].fullName, equals('Engr. Maria Santos'));

      // Must preserve the sticker year (2026) from the physical pass
      expect(resolved.stickerYear, equals('2026'));
      expect(resolved.isSyncedWithDb, isTrue);
    });

    test('ApiService.lookupVehicleByPlate fetches updated database record', () async {
      final remote = await ApiService.lookupVehicleByPlate('ABC-9988');
      expect(remote, isNotNull);
      expect(remote!.ownerName, equals('Engr. Juan Dela Cruz Updated'));
      expect(remote.makeModelColor, equals('2025 Black Toyota Fortuner'));
      expect(remote.stickerYear, equals('2026'));
      expect(remote.authorizedDrivers.length, equals(2));
    });

    testWidgets('QrScannerScreen scans old QR code and dynamically enriches UI with updated database information', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AuditLogEntry? recordedEntry;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrScannerScreen(
              repository: const GateRepository(),
              onDecision: (entry) {
                recordedEntry = entry;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open Manual QR dialog using tooltip
      final keyboardBtn = find.byTooltip('Enter QR Manually');
      expect(keyboardBtn, findsOneWidget);
      await tester.tap(keyboardBtn);
      await tester.pumpAndSettle();

      final inputField = find.byType(TextField);
      expect(inputField, findsOneWidget);
      await tester.enterText(inputField, oldQrCode);
      await tester.pump();

      final verifyBtn = find.text('Verify QR Pass');
      expect(verifyBtn, findsOneWidget);
      await tester.tap(verifyBtn);

      // Allow async ApiService.lookupVehicleByPlate to complete and update state
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify that the UI reflects the NEW database data, NOT the old QR data!
      expect(find.text('Engr. Juan Dela Cruz Updated'), findsWidgets);
      expect(find.text('2025 Black Toyota Fortuner'), findsOneWidget);
      expect(find.textContaining('Faculty - Engineering'), findsWidgets);
      expect(find.text('STICKER 2026'), findsOneWidget);
      expect(find.text('LIVE DATABASE'), findsOneWidget);

      // Verify the updated alternate driver is present in the driver selection list
      expect(find.text('Engr. Maria Santos'), findsOneWidget);

      // Verify old values are gone
      expect(find.text('Old Owner Juan'), findsNothing);
      expect(find.text('Old Red 1998 Sedan'), findsNothing);

      // Clear the vehicle entry at the gate
      final clearBtn = find.text('CLEARED (TO GO)');
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // Assert recorded entry logged the newly updated database data
      expect(recordedEntry, isNotNull);
      expect(recordedEntry!.plateNumber, equals('ABC-9988'));
      expect(recordedEntry!.ownerName, equals('Engr. Juan Dela Cruz Updated'));
      expect(recordedEntry!.status, equals(GateStatus.inside));
    });
  });
}
