import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

void main() {
  late HttpServer mockServer;
  late int mockPort;
  Map<String, dynamic>? lastLogBody;

  setUpAll(() async {
    // Spin up a mock HTTP server mimicking InfinityFree PHP endpoints
    mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mockPort = mockServer.port;
    ApiConstants.baseUrl = 'http://${InternetAddress.loopbackIPv4.host}:$mockPort/api';

    mockServer.listen((HttpRequest request) async {
      final path = request.uri.path;
      final method = request.method;

      // Enable CORS headers as configured on InfinityFree .htaccess
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Content-Type', 'application/json');

      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      // 1. GET /api/vehicles.php
      if (path == '/api/vehicles.php' && method == 'GET') {
        final plate = request.uri.queryParameters['plate'];
        if (plate == 'NDK-4821') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'success',
            'data': {
              'id': 'veh-1001',
              'plate_number': 'NDK-4821',
              'vehicle_type': 'Sedan',
              'make_model_color': 'White Toyota Vios',
              'owner_name': 'Prof. Juan Dela Cruz',
              'owner_role': 'Faculty - CCS',
              'owner_id_number': 'NCST-FAC-2024',
              'sticker_year': '2026',
              'owner_photo_url': 'http://server.example.com/photos/owner.jpg',
              'vehicle_photo_url': 'uploads/vehicles/vios.jpg',
              'qr_pass_code': 'NCST-QR-NDK4821',
              'status': 'Active',
              'authorized_drivers': [
                {
                  'id': 'drv-1',
                  'full_name': 'Maria Dela Cruz',
                  'relationship': 'Spouse',
                  'license_no': 'N01-20-112233',
                  'photo_url': 'http://server.example.com/photos/maria.jpg',
                },
                {
                  'id': 'drv-2',
                  'full_name': 'Mark Dela Cruz',
                  'relationship': 'Son (Student)',
                  'license_no': 'N02-23-445566',
                  'photo_url': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                }
              ]
            }
          }));
        } else {
          // Return list of vehicles
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'success',
            'count': 1,
            'data': [
              {
                'id': 'veh-1001',
                'plate_number': 'NDK-4821',
                'vehicle_type': 'Sedan',
                'make_model_color': 'White Toyota Vios',
                'owner_name': 'Prof. Juan Dela Cruz',
                'owner_role': 'Faculty - CCS',
                'owner_id_number': 'NCST-FAC-2024',
                'sticker_year': '2026',
                'owner_photo_url': 'http://server.example.com/photos/owner.jpg',
                'vehicle_photo_url': 'uploads/vehicles/vios.jpg',
                'qr_pass_code': 'NCST-QR-NDK4821',
                'status': 'Active',
                'authorized_drivers': []
              }
            ]
          }));
        }
        await request.response.close();
        return;
      }

      // 2. POST /api/logs.php
      if (path == '/api/logs.php' && method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        final body = jsonDecode(content);
        lastLogBody = Map<String, dynamic>.from(body as Map);
        expect(body['plateNumber'], equals('NDK-4821'));
        expect(body['status'], equals('Inside Campus'));

        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode({
          'status': 'success',
          'message': 'Gate log recorded successfully',
          'log_id': 'log-9999'
        }));
        await request.response.close();
        return;
      }

      // POST /api/sync.php (the offline queue flushes here): every event is accepted
      if (path == '/api/sync.php' && method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        final body = jsonDecode(content);
        final results = (body['events'] as List)
            .map((e) => {'client_ref': e['client_ref'], 'status': 'accepted'})
            .toList();
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({
          'status': 'success',
          'data': {'results': results},
        }));
        await request.response.close();
        return;
      }

      // 3. POST /api/incidents.php
      if (path == '/api/incidents.php' && method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        final body = jsonDecode(content);
        expect(body['plateNumber'], equals('NDK-4821'));
        expect(body['reason'], equals('Unregistered Pass'));

        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode({
          'status': 'success',
          'message': 'Security incident recorded',
          'case_number': 'INC-2026-001'
        }));
        await request.response.close();
        return;
      }

      // 4. GET /photos/test_driver.jpg
      if (path == '/photos/test_driver.jpg' && method == 'GET') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
        await request.response.close();
        return;
      }

      // 5. POST /api/auth.php?action=login
      if (path == '/api/auth.php' && request.uri.queryParameters['action'] == 'login' && method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        final body = jsonDecode(content);
        if (body['username'] == 'guard1' && body['password'] == 'password123') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'success',
            'data': {
              'token': 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
              'expiresAt': '2026-10-01 00:00:00',
              'realm': 'staff',
              'user': {
                'id': 1,
                'username': 'guard1',
                'fullName': 'Officer J. Hernandez',
                'role': 'guard',
                'badgeNumber': 'NCST-SEC-01',
                'gateAssigned': 'Gate 1 (Main Ingress)',
                'mustChangePassword': false,
              }
            }
          }));
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write(jsonEncode({
            'status': 'error',
            'message': 'Invalid username or password.',
          }));
        }
        await request.response.close();
        return;
      }

      // 6. POST /api/auth.php?action=logout
      if (path == '/api/auth.php' && request.uri.queryParameters['action'] == 'logout' && method == 'POST') {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({
          'status': 'success',
          'message': 'Signed out.',
        }));
        await request.response.close();
        return;
      }

      // 7. POST /api/visitors.php
      if (path == '/api/visitors.php' && method == 'POST') {
        final authHeader = request.headers.value('authorization');
        final xAuthHeader = request.headers.value('x-auth-token');
        if (authHeader == null && xAuthHeader == null) {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write(jsonEncode({
            'status': 'error',
            'message': 'AUTH_REQUIRED',
          }));
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode({
          'status': 'success',
          'data': {'id': 99},
          'message': 'Pass created',
        }));
        await request.response.close();
        return;
      }

      // 8. POST /api/verify.php
      if (path == '/api/verify.php' && method == 'POST') {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({
          'status': 'success',
          'result': 'VALID',
          'accepted': true,
          'message': 'Pass verified.',
        }));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await mockServer.close();
  });

  group('Automated Web Server <-> Mobile App Communication Tests', () {
    test('Mobile App can fetch vehicle details and authorized drivers from backend', () async {
      final vehicle = await ApiService.lookupVehicleByPlate('NDK-4821');

      expect(vehicle, isNotNull);
      expect(vehicle!.plateNumber, equals('NDK-4821'));
      expect(vehicle.ownerName, equals('Prof. Juan Dela Cruz'));
      expect(vehicle.ownerIdNumber, equals('NCST-FAC-2024'));
      expect(vehicle.stickerYear, equals('2026'));
      expect(vehicle.vehicleType, equals('Sedan'));
      expect(vehicle.ownerPhotoUrl, equals('http://server.example.com/photos/owner.jpg'));

      // Authorized drivers parsing
      expect(vehicle.authorizedDrivers.length, equals(2));
      final maria = vehicle.authorizedDrivers[0];
      expect(maria.fullName, equals('Maria Dela Cruz'));
      expect(maria.relationship, equals('Spouse'));
      expect(maria.licenseNo, equals('N01-20-112233'));
      expect(maria.photoUrl, equals('http://server.example.com/photos/maria.jpg'));

      final mark = vehicle.authorizedDrivers[1];
      expect(mark.fullName, equals('Mark Dela Cruz'));
      expect(mark.photoUrl, startsWith('data:image/png;base64,'));
    });

    test('Mobile App can fetch full vehicle catalog from backend', () async {
      final list = await ApiService.fetchVehicles();
      expect(list, isNotEmpty);
      expect(list.first.plateNumber, equals('NDK-4821'));
    });

    test('Mobile App can post real-time gate passage log to backend', () async {
      final success = await ApiService.postGateLog(
        plateNumber: 'NDK-4821',
        driverName: 'Maria Dela Cruz',
        driverRelationship: 'Spouse',
        gatePoint: 'Gate 1 (Main Ingress)',
        action: 'Entry Recorded',
        status: 'Inside Campus',
        vehicleType: 'Sedan',
        ownerName: 'Prof. Juan Dela Cruz',
      );

      expect(success, isTrue);
    });

    test('Gate log carries the selected driver\'s server id (the server refuses a registered vehicle without it)', () async {
      lastLogBody = null;
      final success = await ApiService.postGateLog(
        plateNumber: 'NDK-4821',
        driverName: 'Maria Dela Cruz',
        driverRelationship: 'Spouse',
        vehicleType: 'Sedan',
        ownerName: 'Prof. Juan Dela Cruz',
        driverId: 7,
      );

      expect(success, isTrue);
      expect(lastLogBody?['driver_id'], equals(7));
      expect(lastLogBody?['driverName'], equals('Maria Dela Cruz'));
    });

    test('Gate log without a known driver id sends no driver_id at all', () async {
      lastLogBody = null;
      await ApiService.postGateLog(
        plateNumber: 'NDK-4821',
        driverName: 'Maria Dela Cruz',
        vehicleType: 'Sedan',
        ownerName: 'Prof. Juan Dela Cruz',
      );

      expect(lastLogBody, isNotNull);
      expect(lastLogBody!.containsKey('driver_id'), isFalse);
    });

    test('VehicleRecord.driverIdForName resolves the server id, ignoring case and placeholder ids', () {
      const vehicle = VehicleRecord(
        plateNumber: 'NDK-4821',
        vehicleType: 'Sedan',
        makeModelColor: 'White Toyota Vios',
        ownerName: 'Juan Dela Cruz',
        ownerRole: 'Student',
        ownerIdNumber: 'NCST-2024-05182',
        qrPassCode: 'SP-TEST',
        authorizedDrivers: [
          AuthorizedDriver(id: '12', fullName: 'Juan Dela Cruz', relationship: 'Self (Owner)', licenseNo: 'N01'),
          AuthorizedDriver(id: '13', fullName: 'Pedro Dela Cruz', relationship: 'Brother', licenseNo: 'N02'),
          AuthorizedDriver(id: 'drv-2', fullName: 'Offline Driver', relationship: 'Friend', licenseNo: 'N03'),
        ],
      );

      expect(vehicle.driverIdForName('Juan Dela Cruz'), equals(12));
      expect(vehicle.driverIdForName('  pedro dela cruz '), equals(13));
      expect(vehicle.driverIdForName('Offline Driver'), isNull); // 'drv-2' is a client-side placeholder
      expect(vehicle.driverIdForName('Somebody Else'), isNull);
    });

    test('Mobile App can report a security incident block to backend', () async {
      final success = await ApiService.reportIncident(
        plateNumber: 'NDK-4821',
        driverName: 'Unknown Driver',
        reason: 'Unregistered Pass',
        gatePoint: 'Gate 1 (Main Ingress)',
      );

      expect(success, isTrue);
    });

    test('Mobile App image resolution handles relative server paths, full URLs and data URIs', () {
      // 1. Relative server path
      final relUrl = ApiConstants.resolveImageUrl('uploads/drivers/driver1.jpg');
      expect(relUrl, equals('http://${InternetAddress.loopbackIPv4.host}:$mockPort/uploads/drivers/driver1.jpg'));

      // 2. Full HTTP URL
      final fullUrl = ApiConstants.resolveImageUrl('https://images.unsplash.com/sample.jpg');
      expect(fullUrl, equals('https://images.unsplash.com/sample.jpg'));

      // 3. Base64 Data URI
      final dataUri = ApiConstants.resolveImageUrl('data:image/jpeg;base64,/9j/4AAQSkZJRg==');
      expect(dataUri, equals('data:image/jpeg;base64,/9j/4AAQSkZJRg=='));

      // 4. Asset URI
      final assetUri = ApiConstants.resolveImageUrl('assets/images/kriz_monares.jpg');
      expect(assetUri, equals('assets/images/kriz_monares.jpg'));
    });

    test('ApiService can fetch image bytes and provides image headers', () async {
      final headers = ApiService.imageHeaders;
      expect(headers['Accept'], contains('image/'));
      expect(headers['User-Agent'], isNotEmpty);

      final imgUrl = 'http://${InternetAddress.loopbackIPv4.host}:$mockPort/photos/test_driver.jpg';
      final bytes = await ApiService.fetchImageBytes(imgUrl);
      expect(bytes, isNotNull);
      expect(bytes!.length, equals(8));
      expect(bytes[0], equals(0xFF));
      expect(bytes[1], equals(0xD8));
    });

    test('VehicleRecord inherits owner photo for owner driver when driver photo is omitted', () {
      final json = {
        'plateNumber': 'XYZ-999',
        'ownerName': 'Prof. Test Owner',
        'ownerPhoto': 'data:image/jpeg;base64,12345',
        'authorizedDrivers': [
          {
            'fullName': 'Prof. Test Owner',
            'relationship': 'Self (Owner)',
            'licenseNo': 'N01-00-000000',
          }
        ]
      };
      final record = VehicleRecord.fromQrJson(json);
      expect(record.ownerPhotoUrl, equals('data:image/jpeg;base64,12345'));
      expect(record.authorizedDrivers.first.photoUrl, equals('data:image/jpeg;base64,12345'));
    });

    test('Guard login establishes session token and transmits Bearer headers to protected endpoints', () async {
      // 1. Initial state: reset client and auth token
      ApiService.resetClient();
      expect(ApiService.authToken, isNull);

      // 2. Perform live login against mock server
      final data = await ApiService.login(
        username: 'guard1',
        password: 'password123',
      );
      expect(data, isNotNull);
      expect(ApiService.authToken, equals('a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'));

      final user = GuardUser.fromJson(data!['user']);
      expect(user.username, equals('guard1'));
      expect(user.fullName, equals('Officer J. Hernandez'));
      expect(user.role, equals(GuardRole.entrance));
      expect(user.assignedGate, equals('Gate 1 (Main Ingress)'));

      // 3. Post a visitor pass: this endpoint requires auth header and will pass
      final pass = VisitorPass(
        passId: 'VP-TEST-001',
        visitorName: 'Juan Dela Cruz',
        contactNumber: '0917-123-4567',
        plateNumber: 'VIS-9988',
        entryTime: DateTime.now(),
        expiryTime: DateTime.now().add(const Duration(hours: 8)),
        status: VisitorPassStatus.active,
        registeredByGuard: user.fullName,
        gatePoint: user.assignedGate,
      );
      final visitorSuccess = await ApiService.postVisitorPass(pass);
      expect(visitorSuccess, isTrue);

      // 4. Verify pass endpoint with server
      final verifyRes = await ApiService.verifyPassWithServer(plate: 'VIS-9988');
      expect(verifyRes, isNotNull);
      expect(verifyRes!['result'], equals('VALID'));
      expect(verifyRes['accepted'], isTrue);

      // 5. Logout revokes token and clears local session
      await ApiService.logout();
      expect(ApiService.authToken, isNull);
    });

    test('LocalCacheService saves and retrieves vehicles and audit logs when offline', () async {
      LocalCacheService.clearMemoryCache();

      final testVehicle = {
        'id': 'veh-offline-1',
        'plate_number': 'OFF-2026',
        'vehicle_type': 'SUV',
        'make_model_color': 'Black Toyota Fortuner',
        'owner_name': 'Offline Test User',
        'owner_role': 'Student',
        'owner_id_number': 'NCST-2026-OFF',
        'sticker_year': '2026',
        'qr_pass_code': 'NCST-QR-OFF2026',
        'status': 'Active',
        'authorized_drivers': [],
      };

      await LocalCacheService.saveVehicles([testVehicle]);
      final cachedVehicles = LocalCacheService.getCachedVehicles();
      expect(cachedVehicles.length, equals(1));
      expect(cachedVehicles.first.plateNumber, equals('OFF-2026'));

      // findVehicle searches local cache by plate or qr
      final found = LocalCacheService.findVehicle('OFF-2026');
      expect(found, isNotNull);
      expect(found!.ownerName, equals('Offline Test User'));

      // Audit logs caching
      final testLog = AuditLogEntry(
        id: 'LOG-OFFLINE-99',
        plateNumber: 'OFF-2026',
        vehicleType: 'SUV',
        ownerName: 'Offline Test User',
        driverName: 'Offline Test User',
        timeIn: DateTime.now(),
        status: GateStatus.inside,
      );
      await LocalCacheService.appendLocalLog(testLog);
      final cachedLogs = LocalCacheService.getCachedLogs();
      expect(cachedLogs.length, equals(1));
      expect(cachedLogs.first.id, equals('LOG-OFFLINE-99'));
    });

    test('Offline write operations automatically enqueue and auto-sync when Wi-Fi returns', () async {
      await SyncQueueService().clearQueue();
      expect(SyncQueueService().pendingCount, equals(0));

      // 1. Point baseUrl to an invalid port (simulating Wi-Fi disconnected / offline)
      final validUrl = ApiConstants.baseUrl;
      ApiConstants.baseUrl = 'http://127.0.0.1:54321/api'; // unreachable offline port

      // 2. Post gate passage while offline
      final success = await ApiService.postGateLog(
        plateNumber: 'NDK-4821',
        driverName: 'Maria Dela Cruz',
        driverRelationship: 'Spouse',
        gatePoint: 'Gate 1 (Main Ingress)',
        action: 'Entry Recorded',
        status: 'Inside Campus',
        vehicleType: 'Sedan',
        ownerName: 'Prof. Juan Dela Cruz',
      );
      expect(success, isTrue); // Returns true to UI so officer workflow is uninterrupted

      // Verify item was queued to persistent storage
      expect(SyncQueueService().pendingCount, equals(1));
      final queue = LocalCacheService.getSyncQueue();
      expect(queue.first['type'], equals('gate_log'));
      expect(queue.first['payload']['plateNumber'], equals('NDK-4821'));

      // 3. Restore Wi-Fi (point baseUrl back to working mock server)
      ApiConstants.baseUrl = validUrl;

      // 4. Automated sync drain
      final syncCompleted = await SyncQueueService().processQueue();
      expect(syncCompleted, isTrue);
      expect(SyncQueueService().pendingCount, equals(0));
      expect(LocalCacheService.getSyncQueue(), isEmpty);
    });
  });
}
