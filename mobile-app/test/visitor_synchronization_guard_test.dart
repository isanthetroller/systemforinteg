import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/features/scanner/screens/exit_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_rejection_view.dart';
import 'package:systemforinteg/features/scanner/widgets/scanned_visitor_card.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';
import 'package:systemforinteg/repositories/visitor_repository.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';

void main() {
  // In-memory backend database mock
  final Map<String, Map<String, dynamic>> dbVehicles = {};
  final Map<String, Map<String, dynamic>> dbVisitors = {};
  final List<Map<String, dynamic>> dbLogs = [];
  bool simulateNetworkFailure = false;

  final guard1 = GuardUser(
    id: 'guard-01',
    username: 'guard1',
    fullName: 'Officer Entrance',
    badgeNumber: 'G-101',
    role: GuardRole.entrance,
    assignedGate: 'Gate 1 (Main Ingress)',
    loginTime: DateTime.now(),
  );

  final guard2 = GuardUser(
    id: 'guard-02',
    username: 'guard2',
    fullName: 'Officer Exit',
    badgeNumber: 'G-102',
    role: GuardRole.exit,
    assignedGate: 'Gate 2 (Main Egress)',
    loginTime: DateTime.now(),
  );

  setUp(() {
    simulateNetworkFailure = false;
    dbVehicles.clear();
    dbVisitors.clear();
    dbLogs.clear();
    LocalCacheService.clearMemoryCache();
    ApiConstants.baseUrl = 'http://mock-api.local/api';

    // Normal Registered Vehicle in Database
    dbVehicles['ABC-1111'] = {
      'id': 'v-101',
      'plate_number': 'ABC-1111',
      'vehicle_type': 'Sedan',
      'make_model_color': 'White Toyota Vios',
      'owner_name': 'Prof. John Smith',
      'owner_role': 'Faculty Member',
      'owner_id_number': 'NCST-FAC-01',
      'qr_pass_code': 'ABC-1111',
      'sticker_year': '2026',
      'registration_status': 'Active',
      'status': 'Inside Campus',
      'is_banned': 0,
      'authorized_drivers': [
        {
          'id': 'drv-1',
          'fullName': 'Prof. John Smith',
          'relationship': 'Self (Owner)',
          'licenseNo': 'N01-99-123456',
        }
      ],
    };

    final mockClient = MockClient((http.Request request) async {
      if (simulateNetworkFailure) {
        throw http.ClientException('Simulated network failure');
      }

      final path = request.url.path;
      final method = request.method;

      // GET /api/vehicles.php
      if (path.contains('vehicles.php') && method == 'GET') {
        final plate = request.url.queryParameters['plate'];
        final qr = request.url.queryParameters['qr'];
        final query = (plate ?? qr ?? '').toUpperCase();

        if (query.isNotEmpty && dbVehicles.containsKey(query)) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': dbVehicles[query],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'error', 'message': 'Vehicle not found'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }

      // GET & POST /api/visitors.php
      if (path.contains('visitors.php')) {
        if (method == 'GET') {
          final q = request.url.queryParameters['q'];
          final id = request.url.queryParameters['id'];
          final query = (q ?? id ?? '').trim().toUpperCase();

          for (final entry in dbVisitors.values) {
            final passCode = (entry['passCode'] ?? '').toString().toUpperCase();
            final plate = (entry['plateNumber'] ?? '').toString().toUpperCase();
            final dbId = entry['id']?.toString() ?? '';
            if (passCode == query || plate == query || dbId == query) {
              return http.Response(
                jsonEncode({
                  'status': 'success',
                  'data': entry,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
          }
          return http.Response(
            jsonEncode({'status': 'error', 'message': 'Visitor pass not found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }

        if (method == 'POST') {
          if (request.url.queryParameters['action'] == 'exit') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final passId = (body['passId'] ?? '').toString();
            if (dbVisitors.containsKey(passId)) {
              dbVisitors[passId]!['status'] = 'Used';
              dbVisitors[passId]!['exitTime'] = DateTime.now().toIso8601String();
              dbVisitors[passId]!['isInside'] = false;
            }
            return http.Response(
              jsonEncode({'status': 'success', 'message': 'Visitor exit recorded.'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final passCode = body['passCode'] ?? body['passId'] ?? 'VP-2026-TEST';
          final int newId = dbVisitors.length + 1;
          final created = {
            'id': newId,
            'passCode': passCode,
            'visitorName': body['visitorName'] ?? body['visitor_name'] ?? 'Visitor',
            'contactNumber': body['contactNumber'] ?? body['contact_number'] ?? '09123456789',
            'plateNumber': body['plateNumber'] ?? body['plate_number'] ?? 'ABC-1234',
            'vehicleModel': body['vehicleModel'] ?? body['vehicle_model'] ?? 'Sedan',
            'purposeOfVisit': body['purposeOfVisit'] ?? body['purpose_of_visit'] ?? 'Campus Visit',
            'personToVisit': body['personToVisit'] ?? body['person_to_visit'] ?? 'Dean Santos',
            'validDate': DateTime.now().toIso8601String().substring(0, 10),
            'entryTime': DateTime.now().toIso8601String(),
            'exitTime': null,
            'status': 'Active',
            'isInside': true,
            'createdBy': 'Officer Entrance',
            'createdAt': DateTime.now().toIso8601String(),
            'items': body['items'] ?? [],
            'qrPayload': jsonEncode({
              'v': 1,
              'pid': passCode,
              'plate_number': (body['plateNumber'] ?? '').toString().replaceAll('-', ''),
              'type': 'visitor_temp',
              'valid': DateTime.now().toIso8601String().substring(0, 10),
              'sig': 'mock_valid_signature_123',
            }),
          };
          dbVisitors[passCode] = created;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': created,
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // POST /api/verify.php
      if (path.contains('verify.php') && method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final rawCode = (body['qr_code'] ?? body['plate'] ?? '').toString();
        final gateType = body['gate_type'] ?? 'Egress';

        // Check if rawCode is JSON with visitor payload
        String? visitorPassCode;
        if (rawCode.startsWith('{')) {
          try {
            final decoded = jsonDecode(rawCode) as Map<String, dynamic>;
            if (decoded['type'] == 'visitor_temp' || decoded['type'] == 'NCST_VISITOR_PASS') {
              visitorPassCode = (decoded['pid'] ?? decoded['passId'] ?? '').toString();
            }
          } catch (_) {}
        } else if (rawCode.startsWith('VP-')) {
          visitorPassCode = rawCode;
        }

        if (visitorPassCode != null && dbVisitors.containsKey(visitorPassCode)) {
          final vRecord = dbVisitors[visitorPassCode]!;
          final isBlocked = vRecord['status'] == 'Blocked' || vRecord['status'] == 'Revoked' || vRecord['has_incident'] == true;
          final isUsed = vRecord['status'] == 'Used' || vRecord['exitTime'] != null;
          final isInside = vRecord['isInside'] == true;

          if (isBlocked) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'passType': 'visitor_temp',
                  'result': 'REVOKED',
                  'accepted': false,
                  'currentlyInside': isInside,
                  'reason': 'This visitor pass is currently BLOCKED by security.',
                  'visitor': vRecord,
                  'incident': {
                    'id': 102,
                    'caseNumber': 'INC-2026-VIS-01',
                    'reason': 'Security Incident Hold on visitor.',
                    'status': 'Held',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (gateType == 'Egress' && (!isInside || isUsed)) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'passType': 'visitor_temp',
                  'result': 'ALREADY_EXITED',
                  'accepted': false,
                  'currentlyInside': false,
                  'reason': 'This visitor pass has already been used / checked out.',
                  'visitor': vRecord,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'passType': 'visitor_temp',
                'result': 'VALID',
                'accepted': true,
                'currentlyInside': isInside,
                'visitor': vRecord,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // Check normal vehicle
        final codeUpper = rawCode.toUpperCase();
        if (dbVehicles.containsKey(codeUpper)) {
          final veh = dbVehicles[codeUpper]!;
          final isBlocked = veh['status'] == 'Blocked / Alert' || veh['is_banned'] == 1 || veh['has_incident'] == true;
          final isInside = veh['status'] == 'Inside Campus';
          if (isBlocked) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'BANNED',
                  'accepted': false,
                  'currentlyInside': isInside,
                  'reason': 'Security Incident Hold on vehicle.',
                  'vehicle': veh,
                  'incident': {
                    'id': 101,
                    'caseNumber': 'INC-2026-VEH-01',
                    'reason': 'Reckless driving inside campus',
                    'status': 'Held',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'result': 'VALID',
                'accepted': true,
                'currentlyInside': isInside,
                'vehicle': veh,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Pass or plate unrecognized',
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      }

      // POST /api/gate_logs.php
      if (path.contains('gate_logs.php') && method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        dbLogs.add(body);
        return http.Response(
          jsonEncode({'status': 'success', 'message': 'Gate log recorded'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // POST /api/incidents.php
      if (path.contains('incidents.php') && method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final plate = (body['plate_number'] ?? body['plateNumber'] ?? '').toString().toUpperCase();
        if (dbVehicles.containsKey(plate)) {
          dbVehicles[plate]!['status'] = 'Blocked / Alert';
          dbVehicles[plate]!['has_incident'] = true;
        }
        for (final vis in dbVisitors.values) {
          if ((vis['plateNumber'] ?? '').toString().toUpperCase() == plate) {
            vis['status'] = 'Blocked';
            vis['has_incident'] = true;
          }
        }
        return http.Response(
          jsonEncode({'status': 'success', 'message': 'Incident reported and hold placed.'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode({'status': 'error', 'message': 'Endpoint not handled in mock'}),
        404,
        headers: {'content-type': 'application/json'},
      );
    });

    ApiService.setClientForTesting(mockClient);
  });

  tearDown(() {
    ApiService.resetClient();
  });

  group('Visitor Information Synchronization Between Guard 1 and Guard 2', () {
    testWidgets('Test 1 & Test 2: Guard 1 registers visitor -> Guard 2 scans QR -> Displays full visitor details, NOT "Registered Vehicle"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Guard 1 registers visitor with all detailed information
      final now = DateTime.now();
      final newVisitorPass = VisitorPass(
        passId: 'VP-2026-0001',
        visitorName: 'John Michael Doe',
        contactNumber: '09171234567',
        plateNumber: 'NBT-8899',
        vehicleModel: 'Toyota Vios 2022 Silver',
        purposeOfVisit: 'Official Campus Visit - Dean of Engineering Office',
        personToVisit: 'Dean Ronald Santos',
        entryTime: now,
        expiryTime: now.add(const Duration(hours: 8)),
        status: VisitorPassStatus.active,
        registeredByGuard: guard1.fullName,
        gatePoint: guard1.assignedGate,
        items: [
          {'name': 'Company Laptop', 'quantity': 1},
          {'name': 'HD Projector', 'quantity': 1},
        ],
      );

      final registered = await VisitorRepository().registerPass(newVisitorPass);
      expect(registered.passId, 'VP-2026-0001');
      expect(registered.dbId, isNotNull);
      expect(registered.qrPayload, isNotNull);

      // Verify stored in backend mock
      expect(dbVisitors.containsKey('VP-2026-0001'), isTrue);

      // 2. Guard 2 scans the exact QR generated for the visitor
      final qrToScan = registered.toQrPayload();
      expect(qrToScan, contains('visitor_temp'));
      expect(qrToScan, contains('VP-2026-0001'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger QR scan in Guard 2
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass(qrToScan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify that Guard 2 renders ScannedVisitorCard and NOT registered vehicle generic text
      expect(find.byType(ScannedVisitorCard), findsOneWidget);
      expect(find.text('John Michael Doe'), findsOneWidget);
      expect(find.text('NBT-8899'), findsOneWidget);
      expect(find.text('Toyota Vios 2022 Silver'), findsOneWidget);
      expect(find.text('Dean Ronald Santos'), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget);
      expect(find.text('VISITOR DAY PASS'), findsOneWidget);
      expect(find.textContaining('Company Laptop'), findsOneWidget);
      expect(find.textContaining('HD Projector'), findsOneWidget);

      // CRITICAL ASSERTION: Ensure it NEVER displays generic "Registered Vehicle"
      expect(find.text('Registered Vehicle'), findsNothing);
      expect(find.text('Student (Campus Registered)'), findsNothing);
    });

    testWidgets('Test 3: Guard 2 State Checking -> BLOCKED and ALREADY EXITED passes are strictly rejected', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Create blocked visitor pass in database
      dbVisitors['VP-2026-BLOCKED'] = {
        'id': 201,
        'passCode': 'VP-2026-BLOCKED',
        'visitorName': 'Blocked Intruder',
        'contactNumber': '09000000000',
        'plateNumber': 'BLK-9999',
        'vehicleModel': 'Black Van',
        'purposeOfVisit': 'Unknown',
        'personToVisit': 'None',
        'validDate': DateTime.now().toIso8601String().substring(0, 10),
        'entryTime': DateTime.now().toIso8601String(),
        'exitTime': null,
        'status': 'Blocked',
        'isInside': true,
        'items': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Scan blocked QR
      state.testVerifyPass(jsonEncode({
        'v': 1,
        'pid': 'VP-2026-BLOCKED',
        'plate_number': 'BLK9999',
        'type': 'visitor_temp',
        'valid': DateTime.now().toIso8601String().substring(0, 10),
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Visitor Pass Blocked'), findsOneWidget);
      expect(find.text('ACCESS DENIED'), findsOneWidget);
      expect(find.text('Registered Vehicle'), findsNothing);

      // Reset scanner
      state.testResetScanner();
      await tester.pumpAndSettle();

      // 2. Mark visitor as already exited (Outside)
      dbVisitors['VP-2026-EXITED'] = {
        'id': 202,
        'passCode': 'VP-2026-EXITED',
        'visitorName': 'Past Visitor',
        'contactNumber': '09111111111',
        'plateNumber': 'EXT-1234',
        'vehicleModel': 'Blue Hatchback',
        'purposeOfVisit': 'Meeting',
        'personToVisit': 'Registrar',
        'validDate': DateTime.now().toIso8601String().substring(0, 10),
        'entryTime': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
        'exitTime': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        'status': 'Used',
        'isInside': false,
        'items': [],
      };

      // Scan already exited QR
      state.testVerifyPass(jsonEncode({
        'v': 1,
        'pid': 'VP-2026-EXITED',
        'plate_number': 'EXT1234',
        'type': 'visitor_temp',
        'valid': DateTime.now().toIso8601String().substring(0, 10),
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Vehicle Not Inside Campus'), findsOneWidget);
      expect(find.text('EGRESS DENIED'), findsOneWidget);
      expect(find.text('Registered Vehicle'), findsNothing);
    });

    testWidgets('Test 4: Multiple Visitors -> Guard 2 displays correct data for each visitor without mixing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Create Visitor 1
      dbVisitors['VP-2026-USER1'] = {
        'id': 301,
        'passCode': 'VP-2026-USER1',
        'visitorName': 'Alice Johnson',
        'contactNumber': '09181112233',
        'plateNumber': 'ALICE-01',
        'vehicleModel': 'Red Honda Civic',
        'purposeOfVisit': 'Guest Lecture',
        'personToVisit': 'Prof. Martinez',
        'validDate': DateTime.now().toIso8601String().substring(0, 10),
        'entryTime': DateTime.now().toIso8601String(),
        'exitTime': null,
        'status': 'Active',
        'isInside': true,
        'items': [{'name': 'Lecture Notes', 'quantity': 1}],
      };

      // Create Visitor 2
      dbVisitors['VP-2026-USER2'] = {
        'id': 302,
        'passCode': 'VP-2026-USER2',
        'visitorName': 'Bob Williams',
        'contactNumber': '09194445566',
        'plateNumber': 'BOB-02',
        'vehicleModel': 'Black Ford Ranger',
        'purposeOfVisit': 'Equipment Delivery',
        'personToVisit': 'IT Department',
        'validDate': DateTime.now().toIso8601String().substring(0, 10),
        'entryTime': DateTime.now().toIso8601String(),
        'exitTime': null,
        'status': 'Active',
        'isInside': true,
        'items': [{'name': 'Server Rack', 'quantity': 2}],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Scan Visitor 1
      state.testVerifyPass(jsonEncode({
        'v': 1,
        'pid': 'VP-2026-USER1',
        'plate_number': 'ALICE01',
        'type': 'visitor_temp',
        'valid': DateTime.now().toIso8601String().substring(0, 10),
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Alice Johnson'), findsOneWidget);
      expect(find.text('ALICE-01'), findsOneWidget);
      expect(find.text('Red Honda Civic'), findsOneWidget);
      expect(find.text('Bob Williams'), findsNothing);

      // Reset and scan Visitor 2
      state.testResetScanner();
      await tester.pumpAndSettle();

      state.testVerifyPass(jsonEncode({
        'v': 1,
        'pid': 'VP-2026-USER2',
        'plate_number': 'BOB02',
        'type': 'visitor_temp',
        'valid': DateTime.now().toIso8601String().substring(0, 10),
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Bob Williams'), findsOneWidget);
      expect(find.text('BOB-02'), findsOneWidget);
      expect(find.text('Black Ford Ranger'), findsOneWidget);
      expect(find.text('Alice Johnson'), findsNothing);
    });

    testWidgets('Test 5: Existing Normal Registered Vehicle -> Behavior remains unchanged', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Scan registered vehicle plate / QR
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Should display regular vehicle card with owner and authorized driver details
      expect(find.text('Prof. John Smith'), findsWidgets);
      expect(find.text('ABC-1111'), findsOneWidget);
      expect(find.textContaining('White Toyota Vios'), findsOneWidget);
      expect(find.text('CLEARED (EXIT)'), findsOneWidget);
    });

    testWidgets('Test 6: Invalid QR Code -> Displays NOT FOUND rejection view without crashing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Scan completely unknown QR code
      state.testVerifyPass('UNKNOWN-RANDOM-QR-9999');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Invalid / Unrecognized QR Code'), findsOneWidget);
      expect(find.text('INVALID PASS'), findsOneWidget);
      expect(find.text('Registered Vehicle'), findsNothing);
    });

    testWidgets('Test 7: API / Network Failure -> Displays Connection Error rather than "Registered Vehicle"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      simulateNetworkFailure = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Scan when network is down
      state.testVerifyPass('VP-2026-0001');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Connection / API Error'), findsOneWidget);
      expect(find.text('Registered Vehicle'), findsNothing);
    });

    testWidgets('Test 8: Vehicle Incident Hold Blocks Guard 2 Exit -> Admin Resolves Incident -> Status Restored to "Inside Campus" -> Guard 2 Scan Succeeds', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Vehicle is inside campus but an incident is active
      dbVehicles['ABC-1111']!['status'] = 'Blocked / Alert';
      dbVehicles['ABC-1111']!['has_incident'] = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Guard 2 scans the blocked vehicle
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Guard 2 must REJECT exit: vehicle cannot proceed
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Vehicle Blocked'), findsOneWidget);
      expect(find.text('CLEARED (EXIT)'), findsNothing);

      // 2. Admin resolves incident on Web Admin
      // Because latest gate log was Entry Recorded with no subsequent Exit Approved,
      // the status is restored to 'Inside Campus' (NOT 'Outside'!)
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';
      dbVehicles['ABC-1111']!['has_incident'] = false;

      // Reset Guard 2 scanner and scan again
      state.testResetScanner();
      await tester.pumpAndSettle();

      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Now exit is ALLOWED
      expect(find.byType(ScanRejectionView), findsNothing);
      expect(find.text('CLEARED (EXIT)'), findsOneWidget);
    });

    testWidgets('Test 9: Visitor Incident Hold Blocks Guard 2 Exit -> Resolving Incident Clears Visitor For Exit', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Register visitor
      final now = DateTime.now();
      final visitorPass = VisitorPass(
        passId: 'VP-2026-HOLD',
        visitorName: 'Held Visitor',
        contactNumber: '09180001111',
        plateNumber: 'HLD-9999',
        vehicleModel: 'Blue Sedan',
        purposeOfVisit: 'Vendor Meeting',
        personToVisit: 'Procurement Head',
        entryTime: now,
        expiryTime: now.add(const Duration(hours: 4)),
        status: VisitorPassStatus.active,
        registeredByGuard: guard1.fullName,
        gatePoint: guard1.assignedGate,
        items: const [],
      );
      await VisitorRepository().registerPass(visitorPass);

      // Incident occurs -> Visitor pass has active incident hold
      dbVisitors['VP-2026-HOLD']!['has_incident'] = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(ExitScannerScreen));

      // Guard 2 scans the visitor pass under incident hold
      state.testVerifyPass(jsonEncode({
        'v': 1,
        'pid': 'VP-2026-HOLD',
        'plate_number': 'HLD9999',
        'type': 'visitor_temp',
        'valid': DateTime.now().toIso8601String().substring(0, 10),
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Guard 2 must REJECT exit: visitor under incident hold cannot exit
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Visitor Pass Blocked'), findsOneWidget);
      expect(find.text('CLEARED (VISITOR EXIT)'), findsNothing);

      // Admin resolves incident hold
      dbVisitors['VP-2026-HOLD']!['has_incident'] = false;

      // Reset and scan again
      state.testResetScanner();
      await tester.pumpAndSettle();

      state.testVerifyPass('VP-2026-HOLD');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Now Guard 2 displays visitor details and exit is permitted
      expect(find.byType(ScanRejectionView), findsNothing);
      expect(find.byType(ScannedVisitorCard), findsOneWidget);
      expect(find.text('Held Visitor'), findsOneWidget);
      expect(find.text('CLEARED (VISITOR EXIT)'), findsOneWidget);
    });

    testWidgets('Test 10: Guard 1 Patrol Inspection on In-Campus Vehicle -> Inspects without Gate Transit -> Reports Incident -> Blocked at Guard 2', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // ABC-1111 is already inside campus
      expect(dbVehicles['ABC-1111']!['status'], 'Inside Campus');
      final initialLogsCount = dbLogs.length;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrScannerScreen(
              onDecision: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic ingressState = tester.state(find.byType(QrScannerScreen));

      // Guard 1 scans already-inside vehicle
      ingressState.testProcessRawQrCode('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Duplicate Entry Attempt anti-passback rejection appears
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Duplicate Entry Attempt'), findsOneWidget);
      expect(find.text('INSPECT ON-CAMPUS VEHICLE / REPORT INCIDENT'), findsOneWidget);

      // Guard 1 taps INSPECT ON-CAMPUS VEHICLE
      await tester.tap(find.text('INSPECT ON-CAMPUS VEHICLE / REPORT INCIDENT'));
      await tester.pumpAndSettle();

      // Patrol Inspection Mode is active
      expect(find.text('PATROL INSPECTION MODE (ON-CAMPUS VEHICLE)'), findsOneWidget);
      expect(find.text('FINISH INSPECTION'), findsOneWidget);
      expect(find.text('REPORT INCIDENT / HOLD'), findsOneWidget);
      expect(find.text('Prof. John Smith'), findsWidgets);

      // No fake gate transit log was created!
      expect(dbLogs.length, initialLogsCount);

      // Guard 1 reports incident on this car
      await tester.tap(find.text('REPORT INCIDENT / HOLD'));
      await tester.pumpAndSettle();

      // Dialog opens: select a reason
      expect(find.text('Report In-Campus Incident'), findsOneWidget);
      await tester.tap(find.text('Security Officer Intervention'));
      await tester.pumpAndSettle();

      // Vehicle in database is now Blocked / Alert
      expect(dbVehicles['ABC-1111']!['status'], 'Blocked / Alert');

      // Still no Entry Denied or Entry Recorded gate log created during patrol inspection
      expect(dbLogs.where((l) => l['action'] == 'Entry Recorded' || l['action'] == 'Entry Denied').length, 0);

      // Guard 2 now scans ABC-1111 at exit gate
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic egressState = tester.state(find.byType(ExitScannerScreen));
      egressState.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Guard 2 strictly rejects the vehicle!
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Vehicle Blocked'), findsOneWidget);
      expect(find.text('CLEARED (EXIT)'), findsNothing);
    });
  });
}
