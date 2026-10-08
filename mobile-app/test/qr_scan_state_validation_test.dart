import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/features/scanner/screens/exit_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/features/scanner/widgets/scan_rejection_view.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';

void main() {
  // In-memory backend database for our test server
  final Map<String, Map<String, dynamic>> dbVehicles = {};
  final List<Map<String, dynamic>> dbLogs = [];
  final List<Map<String, dynamic>> dbViolations = [];
  int violationStatus = 201;
  bool simulateNetworkFailure = false;
  // Server-side extras the gate scan can carry: parking nearly full, an exit released by an administrator
  bool occupancyNearlyFull = false;
  final Set<String> releasedExits = <String>{};

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
    occupancyNearlyFull = false;
    releasedExits.clear();
    dbVehicles.clear();
    dbLogs.clear();
    dbViolations.clear();
    violationStatus = 201;
    LocalCacheService.clearMemoryCache();
    ApiConstants.baseUrl = 'http://mock-api.local/api';

    // Default registered vehicle in Outside state
    dbVehicles['ABC-1111'] = {
      'id': 'v-101',
      'plate_number': 'ABC-1111',
      'vehicle_type': 'Sedan',
      'make_model_color': 'White Toyota Vios',
      'owner_name': 'Prof. John Smith',
      'owner_role': 'Faculty Member',
      'owner_id_number': 'NCST-FAC-01',
      'owner_phone': '0917 555 0100',
      'department': 'College of Computing',
      'qr_pass_code': 'ABC-1111',
      'sticker_year': '2026',
      'registration_status': 'Active',
      'status': 'Outside',
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

      if (path.contains('vehicles.php') && method == 'GET') {
        final plate = request.url.queryParameters['plate'];
        final qr = request.url.queryParameters['qr'];
        final query = (plate ?? qr ?? '').toUpperCase();

        if (query.isNotEmpty && dbVehicles.containsKey(query)) {
          final veh = dbVehicles[query]!;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': veh,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else {
          return http.Response(
            jsonEncode({
              'status': 'error',
              'message': 'Vehicle not found',
            }),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
      }

      if (path.contains('verify.php') && method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final code = (body['qr_code'] ?? body['plate'] ?? '').toString().toUpperCase();
        final gateType = body['gate_type'] ?? 'Ingress';

        if (dbVehicles.containsKey(code)) {
          final veh = dbVehicles[code]!;
          final isBanned = veh['is_banned'] == 1 || veh['is_banned'] == true || veh['is_banned'] == '1';
          final regStatus = (veh['registration_status'] ?? '').toString().toLowerCase();
          final isSuspended = regStatus == 'suspended' || regStatus == 'blocked' || regStatus == 'banned';
          final status = (veh['status'] ?? 'Outside').toString();
          final isBlocked = isBanned || isSuspended || status.toLowerCase().contains('block');
          final currentlyInside = status.toLowerCase().contains('inside');

          if (!isBlocked && gateType == 'Ingress' && veh['payment_status'] == 'Unpaid') {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'UNPAID',
                  'accepted': false,
                  'currentlyInside': false,
                  'reason': 'Registration fee not paid. The owner must pay online or at the cashier before this vehicle can enter.',
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (!isBlocked && gateType == 'Ingress' && veh['pass_expired'] == true) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'EXPIRED',
                  'accepted': false,
                  'currentlyInside': false,
                  'reason': 'Pass expired on 2025-12-31. Renew it at the Security Office.',
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (isBlocked && gateType == 'Egress' && currentlyInside && releasedExits.contains(code)) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'VALID',
                  'accepted': true,
                  'currentlyInside': true,
                  'warnings': ['EXIT RELEASED by Admin One until 2:30 PM (Family emergency).'],
                  'exitRelease': {'id': 5, 'releasedBy': 'Admin One', 'expiresAt': '2026-10-08 14:30:00', 'reason': 'Family emergency'},
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (isBlocked) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'BANNED',
                  'accepted': false,
                  'currentlyInside': currentlyInside,
                  'reason': 'This vehicle cannot proceed because it is currently blocked. The vehicle owner must resolve the issue before proceeding.',
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (gateType == 'Ingress' && currentlyInside) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'ANTI_PASSBACK',
                  'accepted': false,
                  'currentlyInside': true,
                  'reason': 'Vehicle is already inside campus.',
                  'onCampus': {
                    'entryTime': '2026-10-08 08:15:00',
                    'hoursInside': 3.5,
                    'gatePoint': 'Gate 1 (Main Ingress)',
                    'enteredBy': 'Prof. John Smith',
                    'admittedBy': 'Officer Reyes',
                    'ownerPhone': '0917 555 0100',
                  },
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (gateType == 'Egress' && !currentlyInside) {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'NOT_INSIDE',
                  'accepted': false,
                  'currentlyInside': false,
                  'reason': 'Vehicle is not recorded as inside campus.',
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else {
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'result': 'VALID',
                  'accepted': true,
                  'currentlyInside': currentlyInside,
                  if (occupancyNearlyFull)
                    'occupancy': {'level': 'nearly_full', 'inside': 95, 'capacity': 100, 'message': 'Campus parking is nearly full (95 of 100, 5 space(s) left).'},
                  'vehicle': veh,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        } else {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'result': 'NOT_FOUND',
                'accepted': false,
                'reason': 'Vehicle record not found',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      }

      if (path.contains('violations.php') && method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (violationStatus != 201) {
          return http.Response(
            jsonEncode({'status': 'error', 'message': 'VIP vehicles are exempt from violations.'}),
            violationStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        dbViolations.add(body);
        final plate = (body['plate'] ?? '').toString().toUpperCase();
        if (dbVehicles.containsKey(plate)) dbVehicles[plate]!['is_banned'] = 1;
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'onHold': true}, 'message': 'Violation recorded.'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (path.contains('logs.php') && method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final plate = (body['plate'] ?? body['plateNumber'] ?? body['plate_number'] ?? '').toString().toUpperCase();
        final action = (body['action'] ?? '').toString();
        final status = (body['status'] ?? '').toString();

        dbLogs.add(body);

        if (dbVehicles.containsKey(plate)) {
          if (action.contains('Entry') || status.contains('Inside')) {
            dbVehicles[plate]!['status'] = 'Inside Campus';
          } else if (action.contains('Exit') || status.contains('Outside')) {
            dbVehicles[plate]!['status'] = 'Outside';
          }
        }

        return http.Response(
          jsonEncode({
            'status': 'success',
            'message': 'Log saved successfully',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode({'status': 'error', 'message': 'Not found'}),
        404,
        headers: {'content-type': 'application/json'},
      );
    });

    ApiService.setClientForTesting(mockClient);
  });

  tearDown(() {
    ApiService.resetClient();
  });

  group('Entry State Checking & QR Validation (Guard 1)', () {
    testWidgets('Test 1: Vehicle outside enters campus successfully; state changes to Inside Campus', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      expect(dbVehicles['ABC-1111']!['status'], 'Outside');

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger manual QR entry simulation
      final dynamic state = tester.state(find.byType(QrScannerScreen));
      state.testProcessRawQrCode('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Scanned verification screen should appear with CLEARED button
      expect(find.text('Scanned Verification'), findsOneWidget);
      expect(find.text('Prof. John Smith'), findsWidgets);
      expect(find.text('CLEARED (TO GO)'), findsOneWidget);

      // Guard taps CLEARED (TO GO)
      await tester.tap(find.text('CLEARED (TO GO)'));
      await tester.pumpAndSettle();

      // Database vehicle status must now be 'Inside Campus'
      expect(dbVehicles['ABC-1111']!['status'], 'Inside Campus');
      expect(dbLogs.length, 1);
      expect(dbLogs.first['status'], 'Inside Campus');
    });

    testWidgets('Test 2: Scanning the exact same QR again for entry is REJECTED (Anti-Passback)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Vehicle is already inside campus
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scan same QR code
      final dynamic state = tester.state(find.byType(QrScannerScreen));
      state.testProcessRawQrCode('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // ScanRejectionView should be rendered
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Duplicate Entry Attempt'), findsOneWidget);
      expect(find.textContaining('already recorded as inside campus'), findsWidgets);
      expect(find.text('SCAN ANOTHER VEHICLE'), findsOneWidget);

      // Verify no new log was written
      expect(dbLogs.isEmpty, isTrue);
      // Status remained Inside Campus
      expect(dbVehicles['ABC-1111']!['status'], 'Inside Campus');
    });
    Future<void> scanVehicleAlreadyInside(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';
      await tester.pumpWidget(MaterialApp(home: QrScannerScreen(onDecision: (_) {})));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(QrScannerScreen));
      state.testProcessRawQrCode('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('Test 2b: scanning a vehicle that is already inside shows who it belongs to and how to contact them', (tester) async {
      await scanVehicleAlreadyInside(tester);

      expect(find.text('Duplicate Entry Attempt'), findsOneWidget);
      final details = find.byKey(const Key('onCampusDetails'));
      await tester.ensureVisible(details);
      expect(details, findsOneWidget);
      expect(find.descendant(of: details, matching: find.text('0917 555 0100')), findsOneWidget);
      expect(find.descendant(of: details, matching: find.text('Prof. John Smith')), findsWidgets);
      expect(find.descendant(of: details, matching: find.text('College of Computing')), findsOneWidget);
      expect(find.descendant(of: details, matching: find.textContaining('3.5 h')), findsOneWidget);
      expect(find.descendant(of: details, matching: find.text('Gate 1 (Main Ingress)')), findsOneWidget);
      expect(find.descendant(of: details, matching: find.text('Officer Reyes')), findsOneWidget);
      expect(find.descendant(of: details, matching: find.textContaining('Self (Owner)')), findsOneWidget);
      expect(find.byKey(const Key('copyPhoneButton')), findsOneWidget);
      expect(find.text('INSPECT ON-CAMPUS VEHICLE / REPORT INCIDENT'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('issueViolationButton')));
      expect(find.byKey(const Key('issueViolationButton')), findsOneWidget);
    });

    testWidgets('Test 2c: the guard issues a violation to the vehicle that is already inside', (tester) async {
      await scanVehicleAlreadyInside(tester);

      await tester.ensureVisible(find.byKey(const Key('issueViolationButton')));
      await tester.tap(find.byKey(const Key('issueViolationButton')));
      await tester.pumpAndSettle();

      // a type is required
      await tester.tap(find.byKey(const Key('issueViolationSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('Choose the type of violation.'), findsOneWidget);
      expect(dbViolations, isEmpty);

      await tester.tap(find.byKey(const Key('violationTypeField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parking in Fire Lane / Restricted Zone').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('violationNotesField')), 'Blocking the hydrant');
      await tester.tap(find.byKey(const Key('issueViolationSubmit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(dbViolations.length, 1);
      expect(dbViolations.first['plate'], 'ABC-1111');
      expect(dbViolations.first['type'], 'Parking in Fire Lane / Restricted Zone');
      expect(dbViolations.first['notes'], 'Blocking the hydrant');
      expect(find.textContaining('Violation recorded. ABC-1111 is on hold'), findsOneWidget);
      expect(find.byType(ScanRejectionView), findsNothing); // back to scanning
    });

    testWidgets('Test 2d: a refused violation is reported loudly and not shown as recorded', (tester) async {
      violationStatus = 409;
      await scanVehicleAlreadyInside(tester);

      await tester.ensureVisible(find.byKey(const Key('issueViolationButton')));
      await tester.tap(find.byKey(const Key('issueViolationButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('violationTypeField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unauthorized Driver at Helm').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('issueViolationSubmit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(dbViolations, isEmpty);
      expect(find.textContaining('NOT RECORDED: VIP vehicles are exempt from violations.'), findsOneWidget);
      expect(find.byType(ScanRejectionView), findsOneWidget); // still on the vehicle's screen
    });


    testWidgets('Parking nearly full: the guard sees the warning, entry can still be cleared and records how it was looked up', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      occupancyNearlyFull = true;

      await tester.pumpWidget(MaterialApp(home: QrScannerScreen(onDecision: (_) {})));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(QrScannerScreen));
      state.testProcessRawQrCode('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining('Campus parking is nearly full'), findsOneWidget);
      expect(find.byKey(const Key('evidenceTakePhoto')), findsOneWidget); // an optional photo can be taken first
      await tester.tap(find.text('CLEARED (TO GO)'));
      await tester.pumpAndSettle();
      expect(dbLogs.single['action'], 'Entry Recorded');
      expect(dbLogs.single['lookupMethod'], 'qr');
    });
  });

  group('Exit State Checking & QR Validation (Guard 2)', () {
    testWidgets('An exit released by an administrator lets a vehicle on hold leave once, with the release spelled out', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';
      dbVehicles['ABC-1111']!['is_banned'] = 1;
      dbVehicles['ABC-1111']!['registration_status'] = 'Suspended';
      releasedExits.add('ABC-1111');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExitScannerScreen(currentGuard: guard2, onDecision: (_) {}))));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining('Exit released by Admin One'), findsOneWidget);
      expect(find.text('CLEARED (EXIT)'), findsOneWidget);
      await tester.tap(find.text('CLEARED (EXIT)'));
      await tester.pumpAndSettle();
      expect(dbLogs.single['action'], 'Exit Approved');
    });

    testWidgets('Without a release the same vehicle on hold is still refused at the exit', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';
      dbVehicles['ABC-1111']!['is_banned'] = 1;
      dbVehicles['ABC-1111']!['registration_status'] = 'Suspended';

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExitScannerScreen(currentGuard: guard2, onDecision: (_) {}))));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('CLEARED (EXIT)'), findsNothing);
      expect(dbLogs, isEmpty);
    });

    testWidgets('Test 3: Vehicle inside campus exits successfully; state changes to Outside', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Vehicle is inside campus
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
              onDecision: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger QR scan on Exit Scanner
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Should show Scanned Verification screen with CLEARED (EXIT) button
      expect(find.text('Scanned Verification'), findsOneWidget);
      expect(find.text('Prof. John Smith'), findsWidgets);
      expect(find.text('CLEARED (EXIT)'), findsOneWidget);

      // Guard 2 taps CLEARED (EXIT)
      await tester.tap(find.text('CLEARED (EXIT)'));
      await tester.pumpAndSettle();

      // Database vehicle status must now be 'Outside'
      expect(dbVehicles['ABC-1111']!['status'], 'Outside');
      expect(dbLogs.length, 1);
      expect(dbLogs.first['status'], 'Outside');
      expect(dbLogs.first['action'], 'Exit Approved');
    });

    testWidgets('Test 4: Immediately scanning same QR again for exit is REJECTED', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Vehicle has already completed exit -> Status is Outside
      dbVehicles['ABC-1111']!['status'] = 'Outside';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
              onDecision: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Guard 2 scans same QR code
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Rejection View should be rendered with Duplicate Exit message
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Vehicle Not Inside Campus'), findsOneWidget);
      expect(find.textContaining('duplicate exit scan cannot be processed'), findsOneWidget);
      expect(find.text('SCAN ANOTHER VEHICLE'), findsOneWidget);

      // Verify no duplicate logs created
      expect(dbLogs.isEmpty, isTrue);
    });
  });

  group('Blocked Vehicle Handling & Real-time Unblocking Flow', () {
    testWidgets('Test 5: BLOCKED vehicle scanned at Exit is strictly rejected with owner resolution notice', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Vehicle is inside but BLOCKED
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';
      dbVehicles['ABC-1111']!['registration_status'] = 'Suspended';
      dbVehicles['ABC-1111']!['is_banned'] = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
              onDecision: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Guard 2 scans the blocked vehicle
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify ScanRejectionView is shown
      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Vehicle Blocked'), findsOneWidget);
      expect(find.textContaining('The vehicle owner must resolve the issue'), findsOneWidget);
      // Guard CANNOT bypass - only button is "SCAN ANOTHER VEHICLE"
      expect(find.text('CLEARED (EXIT)'), findsNothing);
      expect(find.text('SCAN ANOTHER VEHICLE'), findsOneWidget);

      // Verify DB was NOT updated
      expect(dbLogs.isEmpty, isTrue);
    });

    testWidgets('Test 6: Blocked -> Unblocked: Admin unblocks vehicle in DB; next scan immediately allows exit', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Initially blocked
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';
      dbVehicles['ABC-1111']!['registration_status'] = 'Suspended';
      dbVehicles['ABC-1111']!['is_banned'] = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitScannerScreen(
              currentGuard: guard2,
              onDecision: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First scan: Blocked
      final dynamic state = tester.state(find.byType(ExitScannerScreen));
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(ScanRejectionView), findsOneWidget);

      // Guard taps "SCAN ANOTHER VEHICLE" to reset scanner
      await tester.tap(find.text('SCAN ANOTHER VEHICLE'));
      await tester.pumpAndSettle();

      // ADMIN UNBLOCKS VEHICLE in web app database!
      dbVehicles['ABC-1111']!['registration_status'] = 'Active';
      dbVehicles['ABC-1111']!['is_banned'] = 0;
      dbVehicles['ABC-1111']!['status'] = 'Inside Campus';

      // Guard 2 scans the vehicle again
      state.testVerifyPass('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // The mobile app MUST detect the updated state from API and NOT cache the old blocked state!
      expect(find.byType(ScanRejectionView), findsNothing);
      expect(find.text('Scanned Verification'), findsOneWidget);
      expect(find.text('CLEARED (EXIT)'), findsOneWidget);

      // Exit can now be cleared
      await tester.tap(find.text('CLEARED (EXIT)'));
      await tester.pumpAndSettle();
      expect(dbVehicles['ABC-1111']!['status'], 'Outside');
    });
  });

  group('Invalid QR & Network Error Handling', () {
    for (final scenario in const [
      {'name': 'UNPAID registration fee', 'flag': 'payment_status', 'value': 'Unpaid', 'title': 'Registration Fee Unpaid'},
      {'name': 'EXPIRED pass', 'flag': 'pass_expired', 'value': true, 'title': 'Pass Expired'},
    ]) {
      testWidgets('Test 7b: the guard cannot approve a vehicle the server refused (${scenario['name']})', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        dbVehicles['ABC-1111']![scenario['flag'] as String] = scenario['value'];

        await tester.pumpWidget(
          MaterialApp(
            home: QrScannerScreen(
              onDecision: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dynamic state = tester.state(find.byType(QrScannerScreen));
        state.testProcessRawQrCode('ABC-1111');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.byType(ScanRejectionView), findsOneWidget);
        expect(find.text(scenario['title'] as String), findsOneWidget);
        expect(find.text('ACCESS DENIED'), findsOneWidget);
        expect(find.textContaining('Confirm'), findsNothing);
        expect(dbLogs.isEmpty, isTrue);
        expect(dbVehicles['ABC-1111']!['status'], 'Outside');
      });
    }

    testWidgets('Test 7: Scan an invalid / nonexistent QR shows Not Found rejection', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scan random unknown QR
      final dynamic state = tester.state(find.byType(QrScannerScreen));
      state.testProcessRawQrCode('RANDOM_GARBAGE_QR_12345');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Invalid / Unrecognized QR Code'), findsOneWidget);
      expect(find.text('SCAN ANOTHER VEHICLE'), findsOneWidget);
      expect(dbLogs.isEmpty, isTrue);
    });

    testWidgets('Test 8: Network failure rejects scan safely with Connection Error UI', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Simulate network failure
      simulateNetworkFailure = true;

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(QrScannerScreen));
      state.testProcessRawQrCode('ABC-1111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(ScanRejectionView), findsOneWidget);
      expect(find.text('Connection / API Error'), findsOneWidget);
      expect(dbLogs.isEmpty, isTrue);
    });
  });
}
