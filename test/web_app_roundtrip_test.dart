import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';
import 'package:systemforinteg/repositories/visitor_repository.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

void main() {
  late HttpServer webAppBackend;
  late int serverPort;

  // In-memory web application database state for round-trip verification
  final List<Map<String, dynamic>> webDbLogs = [];
  final List<Map<String, dynamic>> webDbVisitors = [];
  final List<Map<String, dynamic>> webDbIncidents = [];
  final List<Map<String, dynamic>> webDbVehicles = [
    {
      'id': 'veh-101',
      'plate_number': 'NDK-4821',
      'vehicle_type': 'Sedan',
      'make_model_color': 'White Toyota Vios',
      'owner_name': 'Prof. Juan Dela Cruz',
      'owner_role': 'Faculty Member',
      'owner_id_number': 'NCST-FAC-2024',
      'sticker_year': '2026',
      'qr_pass_code': 'NCST-QR-NDK4821',
      'status': 'Active',
      'authorized_drivers': [
        {
          'id': 'drv-1',
          'full_name': 'Maria Dela Cruz',
          'relationship': 'Spouse',
          'license_no': 'N01-20-112233',
        }
      ]
    },
    {
      'id': 'veh-102',
      'plate_number': 'ABC-1234',
      'vehicle_type': 'SUV',
      'make_model_color': 'Silver Mitsubishi Montero',
      'owner_name': 'Dr. Elena Santos',
      'owner_role': 'Dean - Engineering',
      'owner_id_number': 'NCST-ADM-2019',
      'sticker_year': '2026',
      'qr_pass_code': 'NCST-QR-ABC1234',
      'status': 'Active',
      'authorized_drivers': []
    }
  ];

  setUpAll(() async {
    // Spin up local HTTP server emulating the web application backend
    webAppBackend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverPort = webAppBackend.port;
    ApiConstants.baseUrl = 'http://${InternetAddress.loopbackIPv4.host}:$serverPort/api';

    webAppBackend.listen((HttpRequest request) async {
      final path = request.uri.path;
      final method = request.method;

      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Content-Type', 'application/json');

      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      // 1. Auth Endpoint: /api/auth.php
      if (path == '/api/auth.php') {
        if (request.uri.queryParameters['action'] == 'login' && method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          if (body['username'] == 'guard1' && body['password'] == 'password123') {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({
              'status': 'success',
              'data': {
                'token': 'mock-session-token-abc-123-xyz',
                'user': {
                  'id': 1,
                  'username': 'guard1',
                  'fullName': 'Officer J. Hernandez',
                  'role': 'guard',
                  'badgeNumber': 'NCST-SEC-01',
                  'gateAssigned': 'Gate 1 (Main Ingress)',
                }
              }
            }));
          } else {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.write(jsonEncode({'status': 'error', 'message': 'Invalid credentials'}));
          }
          await request.response.close();
          return;
        }

        if (request.uri.queryParameters['action'] == 'logout') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({'status': 'success', 'message': 'Logged out'}));
          await request.response.close();
          return;
        }
      }

      // 2. Vehicles Endpoint: /api/vehicles.php
      if (path == '/api/vehicles.php' && method == 'GET') {
        final plate = request.uri.queryParameters['plate'];
        if (plate != null) {
          final found = webDbVehicles.firstWhere(
            (v) => (v['plate_number'] as String).replaceAll('-', '').toUpperCase() == plate.replaceAll('-', '').toUpperCase(),
            orElse: () => {},
          );
          if (found.isNotEmpty) {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({'status': 'success', 'data': found}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({'status': 'error', 'message': 'Vehicle not found'}));
          }
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({'status': 'success', 'data': webDbVehicles}));
        }
        await request.response.close();
        return;
      }

      // 3. Gate Logs Endpoint: /api/logs.php
      if (path == '/api/logs.php') {
        if (method == 'POST') {
          final payload = jsonDecode(await utf8.decoder.bind(request).join());
          final logId = 'LOG-${DateTime.now().millisecondsSinceEpoch}';
          final newRecord = {
            'id': logId,
            'plate_number': payload['plateNumber'] ?? payload['plate'] ?? '',
            'driver_name': payload['driverName'] ?? '',
            'driver_relationship': payload['driverRelationship'] ?? 'Self (Owner)',
            'gate_point': payload['gatePoint'] ?? 'Gate 1',
            'action': payload['action'] ?? 'Entry Recorded',
            'status': payload['status'] ?? 'Inside Campus',
            'guard_name': payload['guardName'] ?? 'Officer',
            'notes': payload['notes'] ?? '',
            'vehicle_type': payload['vehicleType'] ?? 'Vehicle',
            'owner_name': payload['ownerName'] ?? payload['driverName'] ?? '',
            'timestamp': DateTime.now().toIso8601String(),
          };
          webDbLogs.insert(0, newRecord);

          request.response.statusCode = HttpStatus.created;
          request.response.write(jsonEncode({
            'status': 'success',
            'message': 'Log recorded in web application',
            'log_id': logId,
          }));
          await request.response.close();
          return;
        }

        if (method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'success',
            'count': webDbLogs.length,
            'data': webDbLogs,
          }));
          await request.response.close();
          return;
        }
      }

      // 4. Visitors Endpoint: /api/visitors.php
      if (path == '/api/visitors.php') {
        // Exit checkout: POST /api/visitors.php?action=exit
        if (request.uri.queryParameters['action'] == 'exit' && method == 'POST') {
          final payload = jsonDecode(await utf8.decoder.bind(request).join());
          final passId = payload['passId']?.toString() ?? '';
          final index = webDbVisitors.indexWhere((v) => v['passId'] == passId);
          if (index != -1) {
            webDbVisitors[index]['status'] = 'used';
            webDbVisitors[index]['exitTime'] = payload['exitTime'] ?? DateTime.now().toIso8601String();
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({
              'status': 'success',
              'message': 'Visitor exit confirmed by web application',
            }));
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({'status': 'error', 'message': 'Pass not found'}));
          }
          await request.response.close();
          return;
        }

        // Create pass: POST /api/visitors.php
        if (method == 'POST') {
          final payload = jsonDecode(await utf8.decoder.bind(request).join());
          webDbVisitors.add(Map<String, dynamic>.from(payload));

          request.response.statusCode = HttpStatus.created;
          request.response.write(jsonEncode({
            'status': 'success',
            'message': 'Visitor pass registered on server',
            'data': {'id': webDbVisitors.length, 'passId': payload['passId']},
          }));
          await request.response.close();
          return;
        }

        // Query pass: GET /api/visitors.php?q=...
        if (method == 'GET') {
          final query = request.uri.queryParameters['q'] ?? '';
          final match = webDbVisitors.firstWhere(
            (v) => (v['passId'] == query) || (v['plateNumber'] == query),
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({
              'status': 'success',
              'data': match,
            }));
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({'status': 'error', 'message': 'Visitor pass not found'}));
          }
          await request.response.close();
          return;
        }
      }

      // 5. Security Incidents Endpoint: /api/incidents.php
      if (path == '/api/incidents.php' && method == 'POST') {
        final payload = jsonDecode(await utf8.decoder.bind(request).join());
        webDbIncidents.add(Map<String, dynamic>.from(payload));

        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode({
          'status': 'success',
          'message': 'Incident registered on server',
          'case_number': 'INC-${DateTime.now().millisecondsSinceEpoch}',
        }));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await webAppBackend.close();
  });

  group('Automated Full-Loop Data Flow Tests (Mobile App <-> Web Application)', () {
    test('1. Authentication Flow: Mobile app logs into web application and stores auth token', () async {
      ApiService.resetClient();
      expect(ApiService.authToken, isNull);

      final loginResult = await ApiService.login(
        username: 'guard1',
        password: 'password123',
      );

      expect(loginResult, isNotNull);
      expect(ApiService.authToken, equals('mock-session-token-abc-123-xyz'));

      final guard = GuardUser.fromJson(loginResult!['user']);
      expect(guard.fullName, equals('Officer J. Hernandez'));
      expect(guard.badgeNumber, equals('NCST-SEC-01'));
      expect(guard.assignedGate, equals('Gate 1 (Main Ingress)'));
    });

    test('2. Data Fetching Flow: Mobile app fetches registered vehicle details from web app', () async {
      // Fetch specific vehicle by plate
      final vehicle = await ApiService.lookupVehicleByPlate('NDK-4821');
      expect(vehicle, isNotNull);
      expect(vehicle!.plateNumber, equals('NDK-4821'));
      expect(vehicle.ownerName, equals('Prof. Juan Dela Cruz'));
      expect(vehicle.makeModelColor, equals('White Toyota Vios'));
      expect(vehicle.authorizedDrivers.length, equals(1));
      expect(vehicle.authorizedDrivers.first.fullName, equals('Maria Dela Cruz'));

      // Fetch entire vehicle catalog
      final catalog = await ApiService.fetchVehicles();
      expect(catalog.length, equals(2));
      expect(catalog.any((v) => v.plateNumber == 'ABC-1234'), isTrue);
    });

    test('3. Data Sending Flow: Mobile app sends Gate Ingress Log to web application', () async {
      final initialServerLogCount = webDbLogs.length;

      final success = await ApiService.postGateLog(
        plateNumber: 'NDK-4821',
        driverName: 'Maria Dela Cruz',
        driverRelationship: 'Spouse',
        gatePoint: 'Gate 1 (Main Ingress)',
        action: 'Entry Recorded',
        status: 'Inside Campus',
        guardName: 'Officer J. Hernandez',
        notes: 'Verified driver against student/faculty registry',
        vehicleType: 'Sedan',
        ownerName: 'Prof. Juan Dela Cruz',
      );

      expect(success, isTrue);

      // Verify the web application database actually received and stored the record!
      expect(webDbLogs.length, equals(initialServerLogCount + 1));
      final storedLog = webDbLogs.first;
      expect(storedLog['plate_number'], equals('NDK-4821'));
      expect(storedLog['driver_name'], equals('Maria Dela Cruz'));
      expect(storedLog['status'], equals('Inside Campus'));
      expect(storedLog['guard_name'], equals('Officer J. Hernandez'));
      expect(storedLog['notes'], equals('Verified driver against student/faculty registry'));
    });

    test('4. Data Retrieval Loop: Mobile app fetches back the updated gate logs from web app', () async {
      final fetchedLogs = await ApiService.fetchLogs();

      expect(fetchedLogs, isNotEmpty);
      final latestLog = fetchedLogs.first;
      expect(latestLog.plateNumber, equals('NDK-4821'));
      expect(latestLog.driverName, equals('Maria Dela Cruz'));
      expect(latestLog.status, equals(GateStatus.inside));

      // Verify LocalCacheService also cached it for offline use
      final cached = LocalCacheService.getCachedLogs();
      expect(cached, isNotEmpty);
      expect(cached.first.plateNumber, equals('NDK-4821'));
    });

    test('5. Visitor Data Sending Flow: Mobile app registers visitor pass and sends to web app', () async {
      final initialVisitorCount = webDbVisitors.length;

      final pass = VisitorPass(
        passId: 'NCST-VIS-2026-8801',
        visitorName: 'Roberto M. Santos',
        contactNumber: '0917-555-0199',
        plateNumber: 'XYZ-7788',
        vehicleModel: 'SUV (Toyota Fortuner Black)',
        purposeOfVisit: 'Registrar / Document Request',
        personToVisit: 'Office of the Registrar',
        vehiclePhotoUrl: 'assets/images/kriz_monares.jpg',
        entryTime: DateTime.now(),
        expiryTime: DateTime.now().add(const Duration(hours: 8)),
        status: VisitorPassStatus.active,
        registeredByGuard: 'Officer J. Hernandez',
        gatePoint: 'Gate 1 (Main Ingress)',
        notes: 'Checked in via Gate Terminal Checklist',
      );

      // Send to web application backend via VisitorRepository
      await VisitorRepository().registerPass(pass);

      // Verify web application database received the visitor pass with all metadata fields intact
      expect(webDbVisitors.length, equals(initialVisitorCount + 1));
      final serverVisitor = webDbVisitors.last;
      expect(serverVisitor['passId'], equals('NCST-VIS-2026-8801'));
      expect(serverVisitor['visitorName'], equals('Roberto M. Santos'));
      expect(serverVisitor['contactNumber'], equals('0917-555-0199'));
      expect(serverVisitor['plateNumber'], equals('XYZ-7788'));
      expect(serverVisitor['vehicleModel'], equals('SUV (Toyota Fortuner Black)'));
      expect(serverVisitor['purposeOfVisit'], equals('Registrar / Document Request'));
      expect(serverVisitor['personToVisit'], equals('Office of the Registrar'));
      expect(serverVisitor['status'].toString().toLowerCase(), equals('active'));
    });

    test('6. Visitor Query & Verification Loop: Mobile app retrieves visitor pass back from web app', () async {
      final retrieved = await ApiService.lookupVisitorPass('NCST-VIS-2026-8801');

      expect(retrieved, isNotNull);
      expect(retrieved!.passId, equals('NCST-VIS-2026-8801'));
      expect(retrieved.visitorName, equals('Roberto M. Santos'));
      expect(retrieved.plateNumber, equals('XYZ-7788'));
      expect(retrieved.purposeOfVisit, equals('Registrar / Document Request'));
      expect(retrieved.personToVisit, equals('Office of the Registrar'));
      expect(retrieved.status, equals(VisitorPassStatus.active));
    });

    test('7. Visitor Checkout Flow: Mobile app sends exit checkout to web app and updates status', () async {
      final checkoutSuccess = await ApiService.postVisitorExit('NCST-VIS-2026-8801', 'XYZ-7788');
      expect(checkoutSuccess, isTrue);

      // Verify server record is marked as used
      final updatedOnServer = webDbVisitors.firstWhere((v) => v['passId'] == 'NCST-VIS-2026-8801');
      expect(updatedOnServer['status'], equals('used'));
      expect(updatedOnServer['exitTime'], isNotNull);
    });

    test('8. Offline Queue to Web App Sync: Enqueued offline data flushes to web app when online', () async {
      await SyncQueueService().clearQueue();
      expect(SyncQueueService().pendingCount, equals(0));

      final originalUrl = ApiConstants.baseUrl;

      // 1. Simulate Wi-Fi drop by setting unreachable baseUrl
      ApiConstants.baseUrl = 'http://127.0.0.1:49999/api';

      // 2. Action while offline: Post a gate entry log
      await ApiService.postGateLog(
        plateNumber: 'OFFLINE-999',
        driverName: 'Carlos Offline Driver',
        driverRelationship: 'Visitor',
        gatePoint: 'Gate 1',
        action: 'Entry Recorded',
        status: 'Inside Campus',
        vehicleType: 'Sedan',
        ownerName: 'Carlos Offline Driver',
      );

      // Action while offline: Register a visitor pass
      final offlinePass = VisitorPass(
        passId: 'NCST-VIS-OFFLINE-777',
        visitorName: 'Ana Offline Visitor',
        contactNumber: '0918-888-9999',
        plateNumber: 'OFF-7777',
        vehicleModel: 'Sedan',
        purposeOfVisit: 'Admissions Office',
        personToVisit: 'Dean',
        entryTime: DateTime.now(),
        expiryTime: DateTime.now().add(const Duration(hours: 8)),
        status: VisitorPassStatus.active,
        registeredByGuard: 'Officer J. Hernandez',
        gatePoint: 'Gate 1',
      );
      await ApiService.postVisitorPass(offlinePass);

      // Verify items are queued in offline storage
      expect(SyncQueueService().pendingCount, equals(2));

      // 3. Simulate Wi-Fi restoration by pointing back to the web application server
      ApiConstants.baseUrl = originalUrl;

      // 4. Trigger automated background sync
      final syncCompleted = await SyncQueueService().processQueue();
      expect(syncCompleted, isTrue);

      // Verify local queue is completely drained
      expect(SyncQueueService().pendingCount, equals(0));

      // Verify the web application backend actually received the enqueued data!
      expect(webDbLogs.any((l) => l['plate_number'] == 'OFFLINE-999'), isTrue);
      expect(webDbVisitors.any((v) => v['passId'] == 'NCST-VIS-OFFLINE-777'), isTrue);
      final syncedVisitor = webDbVisitors.firstWhere((v) => v['passId'] == 'NCST-VIS-OFFLINE-777');
      expect(syncedVisitor['visitorName'], equals('Ana Offline Visitor'));
      expect(syncedVisitor['plateNumber'], equals('OFF-7777'));
    });
  });
}
